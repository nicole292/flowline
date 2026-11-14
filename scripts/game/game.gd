extends Node3D
## Main game controller: owns the simulation objects, maps them to visuals,
## handles input, menus, game modes, crashes, rewards and the test harness.
##
## Dev flags (after `--` on the command line):
##   --play            start driving immediately
##   --autopilot       a simple bot drives (for screenshots and soak tests)
##   --mode=M          endless | twoway | time
##   --env=E           day | sunset | night
##   --screen=S        open a menu screen (garage, modes, missions, settings)
##   --cash=N          give cash (testing the garage)
##   --shots=a,b,c     save screenshots at these times (seconds)
##   --shot-prefix=P   path prefix for screenshots
##   --quit-at=S       quit after S seconds
##   --bench           print frame time stats on quit
##   --seed=N          fixed traffic seed
##   --car=id          player car
##   --menu            count time (for shots) while in the menu
##   --cam=VIEW        near | top | cockpit for this session (not saved)
##   --paint=N         garage: preview paint swatch N (with --screen=garage)
##   --wreck-at=M      first crash site after M metres (default 900)
##   --steer=MODE      buttons (arrows) | wheel | tilt (GYRO) steering
##   --no-hud          hide all 2D UI (clean shots for store graphics)
##   --road-at=M       start M metres into the road plan (bends, tunnels: first tunnel ~2040 m)
##   --supersample=K   render 3D at K x the window resolution (store screenshots)
##   --no-autopause    keep driving when the window loses focus (recordings)
##   --slow=MS         add MS to every frame (tests the automatic quality step-down)
##   --slow-gpu=MS     add MS x (3D scale)^2 to every frame (a GPU-bound phone)
##   --crash-at=S,...  force a crash into the nearest car ahead at S seconds (dents, the last one wrecks)
##   --restart         with --autopilot: start a new run as soon as the results show (--bench also reports a tilted car)
##   --flow-at=S       start Flow Drive at S seconds (store screenshots)
##   --skin=TONE       hand skin tone in the cockpit view (light medium tan brown dark)

enum State { MENU, PLAYING, PAUSED, CRASHING, RESULTS }

const UI_PHONE_SCALE := 1.3
## Menus need about this many layout units of width. Squarer screens
## (iPads 4:3, Android tablets 16:10, older 16:9 phones) get less than the
## full phone enlargement, so nothing is pushed off the right edge.
const UI_MIN_WIDTH := 1180.0
var _phone_ui := false
const CRASH_TIME := 3.0     ## real seconds from impact to the results (tap skips)
const CHECKPOINT_M := 2000.0
## Camera views, in the order the in-game camera button cycles them.
## Crushed versions of traffic cars, for crash sites (tools/blender/build_cars.py WRECKS).
const WRECK_MODELS := {"t_sedan": "t_sedan_wreck", "t_hatch": "t_hatch_wreck", "t_suv": "t_suv_wreck"}
const CAMERA_VIEWS := ["near", "top", "cockpit"]
const CAMERA_NAMES := {"near": "CHASE", "top": "TOP", "cockpit": "COCKPIT"}

var world: HighwayWorld
var camera: ChaseCamera
var cockpit: Cockpit
var hud: Hud
var menu: MenuUI
var audio: AudioDirector
var crash_fx: CrashFx
var player_root: Node3D
var player_view: CarVisual
var model := VehicleModel.new()
var score := ScoreModel.new()
var sim := TrafficSim.new()
var save := SaveData.new()
var car_data: Dictionary
var state := State.MENU
var player_z := 0.0
var mode := "endless"
var env := "day"

var _views := {}      # agent id -> CarVisual
var _sites := {}      # wreck agent id -> CrashSite (cones, smoke) and whether it was announced
var _pools := {}      # type index -> Array of free CarVisual
var _prev_x := {}     # agent id -> x last frame
var _oncoming: Array[Dictionary] = []  # visual-only traffic on the other carriageway
var _crash := {}
var _menu_t := 0.0
var _menu_drag := 0.0
var _flash: ColorRect
var _fx: ColorRect
var _fx_flow := 0.0
var _fx_time := 0.0
var _scraping := false
var _loaded_car := ""
var _cockpit_on := false
var _time_left := 0.0
var _next_cp := CHECKPOINT_M
var _checkpoints := 0
var _tilt := TiltSteer.new()
var _last_gravity := Vector2.ZERO
var _no_motion_t := 0.0     ## seconds of GYRO steering with no sensor data
var _horn_on := false
var _horn_cool := 0.0
var _invuln := 0.0                       # ghost time after a crash you drive through
var _wrecks: Array[Dictionary] = []      # cars knocked aside, animated, no collisions

# dev harness
var _args := {}
var _shots: Array[float] = []
var _frame_times: PackedFloat32Array = []
## Automatic 3D resolution: slower phones drop render resolution until the
## game holds its frame rate (the HUD stays sharp). 1.0 = native.
var _auto_scale := 1.0
var _perf_t := 0.0
var _perf_frames := 0
var _perf_slow := 0
var _shadows_cut := false
var _scale_done := false      ## lowering resolution did not help on this device
var _perf_done := false       ## stopped adapting
var _perf_last := ""          ## the step taken after the last window: "scale" | "shadows" | ""
var _perf_prev_fps := 0.0     ## frame rate before that step
const AUTO_SCALE_MIN := 0.6
const MAX_STEP_DT := 0.05     ## longer frames (hitches) are simulated as 50 ms
var _run_dt := 0.0            ## unclamped frame time (the bench measures real frames)
## Bends: in a curve the car is pushed gently to the outside, so you steer a
## little to hold your lane (m/s sideways per m/s^2 of cornering).
const CURVE_PUSH := 0.25
var _bent: Array = []         ## [node, its straight transform] bent onto the curve this frame
var _lights_on := false
var _recent_paints: Array = []
var _run_time := 0.0


func _ready() -> void:
	_parse_args()
	_setup_input()
	# Android phones span 60-144 Hz screens and much weaker GPUs than iPhones;
	# a steady 60 (paced by Swappy) looks smoother than a rate that keeps
	# dropping between 120 and 40, and the phone stays cooler, so no
	# thermal slow-down after a few minutes.
	if OS.get_name() == "Android":
		Engine.max_fps = 60
	# Phones get a gas pedal; a mouse can't hold gas and steer at once.
	var phone := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	save.settings["gas"] = "pedal" if phone else "auto"
	# A phone screen is small in the hand: draw all menus and the HUD 1.3x
	# larger there (the layouts then see about 985 x 554 units).
	_phone_ui = phone or _args.has("phone")
	_update_ui_scale()
	get_tree().root.size_changed.connect(_update_ui_scale)
	save.load_from_disk()
	if _args.has("steer"):  # harness: buttons | wheel | tilt (GYRO)
		save.settings["controls"] = _args["steer"]
	if _args.has("theme"):  # harness: light | dark
		save.settings["theme"] = _args["theme"]
	if _args.has("skin"):  # harness: light | medium | tan | brown | dark (cockpit hands)
		save.settings["skin"] = _args["skin"]
	if _args.has("cash"):
		save.cash = int(_args["cash"])
	if _args.has("car") and CarCatalog.has_player_car(_args["car"]):
		if not save.owned_cars.has(_args["car"]):
			save.owned_cars.append(_args["car"])
		save.selected_car = _args["car"]
	world = HighwayWorld.new()
	if _args.has("road-at"):
		world.curve.offset = float(_args["road-at"])
	add_child(world)
	world.build()
	camera = ChaseCamera.new()
	add_child(camera)
	camera.current = true
	cockpit = Cockpit.new()
	cockpit.visible = false
	camera.add_child(cockpit)

	player_root = Node3D.new()
	add_child(player_root)
	player_view = CarVisual.new()
	player_view.brake_glow = true
	player_root.add_child(player_view)
	_show_car(save.selected_car, CarCatalog.paint_for(save.selected_car, save.paint_index(save.selected_car)),
			save.rim_index(save.selected_car))

	sim.lanes = HighwayWorld.LANES
	sim.lane_width = HighwayWorld.LANE_W
	sim.types.clear()
	for t in CarCatalog.TRAFFIC:
		sim.types.append(t)
		if WRECK_MODELS.has(t["id"]):
			sim.wreck_types.append(sim.types.size() - 1)
		if t["id"] == "t_police":
			sim.police_type = sim.types.size() - 1
	if _args.has("seed"):
		sim.rng.seed = int(_args["seed"])
	if _args.has("wreck-at"):
		sim.crash_first = float(_args["wreck-at"])
	_prewarm_pools()

	audio = AudioDirector.new()
	add_child(audio)
	crash_fx = CrashFx.new()
	add_child(crash_fx)

	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.visible = not _args.has("no-hud")
	add_child(layer)
	_fx = ColorRect.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fx_mat := ShaderMaterial.new()
	fx_mat.shader = load("res://shaders/speed_fx.gdshader")
	_fx.material = fx_mat
	_fx.visible = false
	layer.add_child(_fx)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash)
	hud = Hud.new()
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(hud)
	hud.pause_pressed.connect(func(): audio.click(); set_paused(true))
	hud.camera_pressed.connect(func(): audio.click(); _cycle_camera())
	hud.resume_pressed.connect(func(): audio.click(); set_paused(false))
	hud.restart_pressed.connect(func(): audio.click(); restart())
	hud.menu_pressed.connect(func(): audio.click(); _quit_to_menu())
	hud.end_pressed.connect(func():
		audio.click()
		set_paused(false)
		_finish_run("RUN ENDED"))
	menu = MenuUI.new()
	menu.skip_daily = _args.has("no-daily")
	layer.add_child(menu)
	menu.setup(save)
	menu.clicked.connect(func(): audio.click())
	menu.play_requested.connect(func(m: String, e: String): start_run(m, e))
	menu.preview_changed.connect(_show_car)
	menu.settings_changed.connect(_apply_settings)
	_apply_settings()

	_reset_player()
	_enter_menu()
	_warm_up.call_deferred()
	if _args.has("screen"):
		menu._g_tab = _args.get("tab", menu._g_tab)  # harness: upgrade | paint | rims | plate
		menu.show_screen(_args["screen"])
		if _args.has("paint"):  # harness: preview a paint swatch in the garage
			menu._pending_paint = int(_args["paint"])
			menu._preview()
	if _args.has("play") or _args.has("autopilot"):
		start_run.call_deferred(_args.get("mode", save.last_mode), _args.get("env", "day"))


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _args.has("shots"):
		for s in str(_args["shots"]).split(","):
			_shots.append(float(s))


func _setup_input() -> void:
	var binds := {
		"steer_left": [KEY_LEFT, KEY_A], "steer_right": [KEY_RIGHT, KEY_D],
		"brake": [KEY_DOWN, KEY_S, KEY_SPACE], "pause": [KEY_ESCAPE, KEY_P],
		"gas": [KEY_UP, KEY_W], "horn": [KEY_H], "camera": [KEY_C],
	}
	for action in binds:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in binds[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


func _apply_settings() -> void:
	audio.apply_settings(save.settings)
	hud.mph = save.settings.get("units", "kmh") == "mph"
	hud.set_controls(save.steer_for(save.selected_car), save.settings.get("gas", "pedal") == "auto")
	cockpit.set_skin(save.settings.get("skin", "medium"))
	# iPhones report the tilt mirrored compared with Android and browsers
	# (playtest: turning right steered left), so iOS starts flipped. The
	# Gyro setting flips it again for any phone that still gets it wrong.
	_tilt.invert = (save.settings.get("gyro", "normal") == "invert") != (OS.get_name() == "iOS")
	_apply_camera()
	if OS.has_feature("web") and save.settings.get("controls", "buttons") == "tilt":
		JavaScriptBridge.eval("window.__wantMotion = true")  # lets the page ask iOS for motion access
	_apply_quality()
	if state == State.MENU:
		_show_car(save.selected_car, CarCatalog.paint_for(save.selected_car, save.paint_index(save.selected_car)),
				save.rim_index(save.selected_car))


func _apply_quality() -> void:
	var high: bool = save.settings.get("quality", "high") == "high"
	world.set_quality(high and not _shadows_cut)
	get_viewport().scaling_3d_scale = (1.0 if high else 0.75) * _auto_scale
	if _args.has("supersample"):  # store screenshots: render 3D at this multiple, sharper when upscaled
		get_viewport().scaling_3d_scale = float(_args["supersample"])
	cockpit.low_cost = not high or _shadows_cut or _auto_scale < 0.999


## Watches the frame rate while driving. If over 3 s more than a quarter of
## frames miss the target (60 fps, or the screen's rate if lower), the 3D
## image is rendered 10% smaller, down to 60%; after that the sun shadows go.
## Every step must buy at least 5% more frames, or it is undone: a phone
## held back by its CPU (or an emulator) would only get blurrier.
## Fast phones (and the iPhone) never trigger it.
func _watch_performance(real_dt: float) -> void:
	if _run_time < 3.0 or _perf_done or _args.has("bench"):
		return
	var hz := DisplayServer.screen_get_refresh_rate()
	var target := 1.0 / clampf(hz if hz > 0.0 else 60.0, 30.0, 60.0)
	_perf_t += real_dt
	_perf_frames += 1
	if real_dt > target * 1.35:
		_perf_slow += 1
	if _perf_t < 3.0:
		return
	var fps := _perf_frames / _perf_t
	var slow := _perf_slow * 4 > _perf_frames
	if slow and _perf_last != "" and fps < _perf_prev_fps * 1.05:
		if _perf_last == "scale":  # resolution is not the bottleneck: back up, try shadows
			_auto_scale = minf(1.0, _auto_scale + 0.1)
			_scale_done = true
		else:  # nothing helps: put everything back and stop watching
			_shadows_cut = false
			_perf_done = true
		_perf_last = ""
		_apply_quality()
		print("auto quality: no gain (%.0f fps), undone: 3D scale %.2f, sun shadows %s" % [
				fps, _auto_scale, not _shadows_cut])
	elif slow:
		if not _scale_done and _auto_scale > AUTO_SCALE_MIN + 0.001:
			_auto_scale = maxf(AUTO_SCALE_MIN, _auto_scale - 0.1)
			_perf_last = "scale"
		elif not _shadows_cut:
			_shadows_cut = true
			_perf_last = "shadows"
		else:
			_perf_done = true
		_perf_prev_fps = fps
		_apply_quality()
		print("auto quality: %.0f fps -> 3D scale %.2f, sun shadows %s" % [fps, _auto_scale, not _shadows_cut])
	else:
		_perf_last = ""
	_perf_t = 0.0
	_perf_frames = 0
	_perf_slow = 0


## Phone UI enlargement, as large as the screen's shape allows (see UI_MIN_WIDTH).
## Also runs when the window changes (rotation, split screen, resizing).
func _update_ui_scale() -> void:
	var root := get_tree().root
	var k := 1.0
	if _phone_ui:
		var win := Vector2(DisplayServer.window_get_size())
		if win.x > 0.0 and win.y > 0.0:
			k = clampf(ui_width_units(win) / UI_MIN_WIDTH, 1.0, UI_PHONE_SCALE)
	if not is_equal_approx(root.content_scale_factor, k):
		root.content_scale_factor = k


## Layout width at scale 1 for a window (1280 x 720 base, stretch "expand").
static func ui_width_units(win: Vector2) -> float:
	return 720.0 * win.x / win.y if win.x / win.y >= 1280.0 / 720.0 else 1280.0


## Loads (or recolours) the car shown in the menu and driven in a run.
func _show_car(id: String, paint: Color, rim: int) -> void:
	if _loaded_car != id:
		player_view.setup(id, paint)
		_loaded_car = id
		cockpit.build(player_view.is_bike, player_view.paint_material())
	player_view.set_paint(paint)
	player_view.set_rim(rim)
	player_view.set_plate(save.plate)


# ------------------------------------------------------------------ states

func _reset_player() -> void:
	# Put bent objects back first: otherwise the next frame's _unbend()
	# restores the pose saved before this reset (a wrecked car on a bend
	# started the next run on its side or roof).
	_unbend()
	car_data = CarCatalog.player_car(save.selected_car)
	model.configure(Progression.stats_for(car_data, save.car_levels(car_data["id"])))
	model.speed = 0.0 if state == State.MENU else 22.0
	model.x = sim.lane_x(2)
	model.lat_vel = 0.0
	model.steer_input = 0.0
	player_z = 0.0
	player_root.position = Vector3(model.x, 0, player_z)
	player_root.rotation = Vector3.ZERO
	world.update(player_z)


func _enter_menu() -> void:
	state = State.MENU
	get_tree().paused = false
	Engine.time_scale = 1.0
	_clear_traffic()
	audio.stop_engine()
	_fx.visible = false
	_flash.color.a = 0.0
	hud.hide_all()
	_cockpit_on = false
	cockpit.visible = false
	_set_env(save.last_env if save.level() >= menu._env_need(save.last_env) else "day")
	player_view.set_headlights(world.is_night)
	_lights_on = world.is_night
	player_view.set_fill_light(world.is_night)
	_reset_player()
	_show_car(save.selected_car, CarCatalog.paint_for(save.selected_car, save.paint_index(save.selected_car)),
			save.rim_index(save.selected_car))
	player_view.set_parked(true)
	menu.visible = true
	menu.show_screen("home")


func _set_env(e: String) -> void:
	env = e
	world.apply_env(e)
	CarVisual.set_night(world.is_night)


func start_run(m := "endless", e := "day") -> void:
	if state == State.PLAYING:
		return
	mode = m if SaveData.MODES.has(m) else "endless"
	get_tree().paused = false
	Engine.time_scale = 1.0
	_clear_traffic()
	_set_env(e)
	menu.visible = false
	score = ScoreModel.new()
	state = State.PLAYING
	_show_car(save.selected_car, CarCatalog.paint_for(save.selected_car, save.paint_index(save.selected_car)),
			save.rim_index(save.selected_car))
	_reset_player()
	model.speed = 22.0
	# Two-way: the two left lanes carry oncoming traffic.
	if mode == "twoway":
		sim.lane_dir = [1, 1, -1, -1]
		sim.lane_speeds = [23.0, 19.5, 25.0, 21.0]
	else:
		sim.lane_dir = [-1, -1, -1, -1]
		sim.lane_speeds = [31.0, 27.0, 23.5, 20.0]
	world.set_two_way(mode == "twoway")
	for a in sim.populate(player_z, 0.0):
		_on_spawn(a)
	_time_left = 60.0 if mode == "time" else -1.0
	_next_cp = CHECKPOINT_M
	_checkpoints = 0
	player_view.set_headlights(world.is_night)
	_lights_on = world.is_night
	player_view.set_fill_light(world.is_night)
	camera.h_offset = 0.0
	_apply_camera()
	_tilt.calibrate = true
	if save.settings.get("controls", "buttons") == "tilt":
		hud.popup("GYRO STEERING", "Turn the phone like a wheel. How you hold it now is straight", Color.WHITE)
	_no_motion_t = 0.0
	camera.snap(player_root.position)
	hud.show_playing()
	hud.set_timer(_time_left, _next_cp / 1000.0)
	hud.set_bonus("")
	audio.bike = player_view.is_bike
	player_view.set_parked(false)
	hud.set_controls(save.steer_for(save.selected_car), save.settings.get("gas", "pedal") == "auto")
	audio.start_engine()
	_horn_on = false
	_fx.visible = true
	_fx_flow = 0.0
	_run_time = 0.0


func restart() -> void:
	state = State.RESULTS
	start_run(mode, env)


func _quit_to_menu() -> void:
	_enter_menu()


func set_paused(on: bool) -> void:
	if on and state != State.PLAYING:
		return
	if not on and state != State.PAUSED:
		return
	state = State.PAUSED if on else State.PLAYING
	_tilt.calibrate = not on  # re-centre tilt when play resumes
	get_tree().paused = on
	hud.show_pause(on)
	audio.set_paused(on)


func _notification(what: int) -> void:
	# Phones: pause when the app is backgrounded or interrupted.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if state == State.PLAYING and not _args.has("no-autopause"):
			set_paused(true)
		save.save_to_disk()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		save.save_to_disk()


## Any tap, click or key during a wreck skips straight to the results.
func _input(event: InputEvent) -> void:
	if state != State.CRASHING or float(_crash.get("t", 0.0)) < 0.5:
		return
	var tap: bool = (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventKey and event.pressed and not event.echo)
	if tap:
		get_viewport().set_input_as_handled()
		_finish_run("WRECKED")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera"):
		_cycle_camera()
	if event.is_action_pressed("pause"):
		if state == State.PLAYING:
			set_paused(true)
		elif state == State.PAUSED:
			set_paused(false)
	# Drag on the 3D view in the garage to turn the car.
	if state == State.MENU and menu.current_screen() == "garage":
		if event is InputEventScreenDrag:
			_menu_drag += (event as InputEventScreenDrag).relative.x * 0.008
		elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
			_menu_drag += (event as InputEventMouseMotion).relative.x * 0.008


# ------------------------------------------------------------------ traffic views

func _on_spawn(a: TrafficSim.Agent) -> void:
	if a.wreck:
		_spawn_wreck_view(a)
		return
	var pool: Array = _pools.get(a.type_index, [])
	var v: CarVisual
	if pool.is_empty():
		v = CarVisual.new()
		add_child(v)
		v.setup(CarCatalog.TRAFFIC[a.type_index]["id"], Color.WHITE, true)
	else:
		v = pool.pop_back()
		v.visible = true
	v.set_paint(_next_paint())
	v.position = Vector3(a.x, 0, a.z)
	v.rotation = Vector3(0, PI if a.dir > 0 else 0.0, 0)
	_views[a.id] = v
	_prev_x[a.id] = a.x


## Traffic colour, never one of the last three handed out.
func _next_paint() -> Color:
	var c := CarCatalog.random_paint(sim.rng, _recent_paints)
	_recent_paints.append(c)
	if _recent_paints.size() > 3:
		_recent_paints.pop_front()
	return c


## A crash-site car: its own crushed model (or the patrol car), parked
## across the lane with the hazards on, plus cones, debris and smoke.
func _spawn_wreck_view(a: TrafficSim.Agent) -> void:
	var id: String = CarCatalog.TRAFFIC[a.type_index]["id"]
	var v := CarVisual.new()
	add_child(v)
	v.setup(id if a.police else WRECK_MODELS.get(id, id), Color(0.92, 0.92, 0.93), true)
	if not a.police:
		v.set_paint(_next_paint())
	v.set_headlights(a.police and world.is_night)
	v.position = Vector3(a.x, 0, a.z)
	v.rotation = Vector3(0, a.yaw, 0.0 if a.police else sim.rng.randf_range(-0.035, 0.035))
	_views[a.id] = v
	_prev_x[a.id] = a.x
	if not a.police:
		var site := CrashSite.new()
		add_child(site)
		site.position = v.position
		site.build(a.length, sim.rng)
		_sites[a.id] = {"node": site, "warned": false}


func _on_despawn(a: TrafficSim.Agent) -> void:
	var v: CarVisual = _views.get(a.id)
	if v == null:
		return
	_views.erase(a.id)
	_prev_x.erase(a.id)
	if a.wreck:
		v.queue_free()
	else:
		_release_view(a.type_index, v)
	_free_site(a.id)


func _free_site(id: int) -> void:
	if _sites.has(id):
		(_sites[id]["node"] as Node).queue_free()
		_sites.erase(id)


## Loads every traffic model up front so spawning never hitches mid-run.
func _prewarm_pools() -> void:
	for id in WRECK_MODELS.values():
		CarVisual.load_scene(id)
	for i in CarCatalog.TRAFFIC.size():
		for n in 2:
			var v := CarVisual.new()
			add_child(v)
			v.setup(CarCatalog.TRAFFIC[i]["id"], Color.WHITE, true)
			_release_view(i, v)


## Every material is compiled the first time it is drawn, and in a phone
## browser that stalls the game for a moment: the first camera switch,
## crash, crash site or new traffic model would hitch. So draw them all once
## at start-up, below the road surface where nobody can see them.
func _warm_up() -> void:
	var cam := camera.global_transform
	var fwd := -cam.basis.z
	fwd.y = 0.0
	# Far ahead and well under the road: in view (so it is drawn), never seen.
	var hide_at := cam.origin + fwd.normalized() * 150.0 + Vector3(0, -12.0 - cam.origin.y, 0)
	for ti in _pools:
		for v: CarVisual in _pools[ti]:
			v.position = hide_at
			v.visible = true
	var temp: Array[Node3D] = []
	for id in WRECK_MODELS.values():
		var w := CarVisual.new()
		add_child(w)
		w.setup(id, Color.WHITE, true)
		w.position = hide_at
		temp.append(w)
	var site := CrashSite.new()
	add_child(site)
	site.position = hide_at
	site.build(4.5, RandomNumberGenerator.new())
	temp.append(site)
	cockpit.position = cam.basis.inverse() * (hide_at - cam.origin)
	cockpit.visible = true
	crash_fx.impact(hide_at, Color.WHITE, 0.5)
	# A short tunnel (its hill is 16 m tall, so deeper still), and the lights
	# a run switches on later (brake glow; headlights in tunnels): the first
	# draw of each costs a shader build, a visible stall on some devices.
	var tunnel := world._build_tunnel(20.0)
	tunnel.position = hide_at + Vector3(0, -30.0, 0)
	temp.append(tunnel)
	player_view.set_brake(true)
	player_view.set_headlights(true)
	for i in 3:
		await get_tree().process_frame
	player_view.set_brake(false)
	player_view.set_headlights(_lights_on)
	for ti in _pools:  # a run may have started meanwhile and taken some
		for v: CarVisual in _pools[ti]:
			v.visible = false
	for n in temp:
		n.queue_free()
	cockpit.position = Vector3.ZERO
	cockpit.visible = _cockpit_on
	crash_fx.stop()


func _release_view(type_index: int, v: CarVisual) -> void:
	v.visible = false
	v.set_brake(false)
	v.rotation = Vector3.ZERO
	if not _pools.has(type_index):
		_pools[type_index] = []
	_pools[type_index].append(v)


func _clear_traffic() -> void:
	for w in _wrecks:
		_release_view(w["type"], w["view"])
	_wrecks.clear()
	_invuln = 0.0
	player_view.visible = true
	for o in _oncoming:
		_release_view(o["type"], o["view"])
	_oncoming.clear()
	for a in sim.agents:
		_on_despawn(a)
	for id in _sites.keys():
		_free_site(id)
	sim.clear()
	if _crash.has("view") and _crash["view"] != null:
		_release_view(_crash["type"], _crash["view"])
	_crash = {}
	crash_fx.stop()


## Oncoming cars behind the median: no collisions, they just make the road live.
func _update_oncoming(dt: float) -> void:
	for i in range(_oncoming.size() - 1, -1, -1):
		var o := _oncoming[i]
		o["z"] += float(o["speed"]) * dt
		var v: CarVisual = o["view"]
		v.position.z = o["z"]
		v.animate(dt, o["speed"], 0.0, 0.0, 0.0)
		if float(o["z"]) > player_z + HighwayWorld.BEHIND:
			_release_view(o["type"], v)
			_oncoming.remove_at(i)
	var want := 4 + int(clampf(score.distance / 3000.0, 0.0, 1.0) * 5.0)
	if _oncoming.size() < want and sim.rng.randf() < dt * 3.0:
		var lane := sim.rng.randi_range(0, 3)
		var z := player_z - sim.rng.randf_range(380.0, 620.0)
		for o in _oncoming:
			if o["lane"] == lane and absf(float(o["z"]) - z) < 45.0:
				return
		var ti := sim.pick_type()
		var pool: Array = _pools.get(ti, [])
		var v: CarVisual
		if pool.is_empty():
			v = CarVisual.new()
			add_child(v)
			v.setup(CarCatalog.TRAFFIC[ti]["id"], Color.WHITE, true)
		else:
			v = pool.pop_back()
			v.visible = true
		v.set_paint(_next_paint())
		var x := HighwayWorld.OPP_CENTER + (lane - 1.5) * HighwayWorld.LANE_W
		v.position = Vector3(x, 0, z)
		v.rotation = Vector3(0, PI, 0)
		_oncoming.append({"view": v, "type": ti, "lane": lane, "z": z,
				"speed": [21.0, 24.5, 28.0, 31.0][lane] * sim.rng.randf_range(0.95, 1.05)})


func _sync_traffic(dt: float) -> void:
	for a in sim.agents:
		var v: CarVisual = _views.get(a.id)
		if v == null:
			continue
		if a.wreck:
			v.position.z = a.z
			v.set_blinker(2, dt)
			v.update_siren(_fx_time)
			if not _sites.has(a.id):
				continue
			(_sites[a.id]["node"] as Node3D).position = v.position
			if not _sites[a.id]["warned"] and player_z - a.z < 300.0:
				_sites[a.id]["warned"] = true
				var side := "RIGHT" if a.x > model.x + 1.0 else ("LEFT" if a.x < model.x - 1.0 else "YOUR LANE")
				hud.popup("CRASH AHEAD", "Wreck " + ("in your lane" if side == "YOUR LANE" else "on the " + side.to_lower()),
						Color(1.0, 0.7, 0.2), true)
			continue
		var lat := (a.x - float(_prev_x[a.id])) / maxf(dt, 0.0001)
		_prev_x[a.id] = a.x
		v.position = Vector3(a.x, 0, a.z)
		var base := PI if a.dir > 0 else 0.0
		v.rotation.y = base - a.dir * -atan2(lat, maxf(a.speed, 1.0))
		v.set_brake(a.braking)
		v.set_blinker(a.blinker() * -a.dir, dt)
		v.animate(dt, a.speed, 0.0, 0.0, clampf(a.accel * 0.004, -0.03, 0.02))


# ------------------------------------------------------------------ main loop

func _process(dt: float) -> void:
	_run_dt = dt
	# A hitch (shader compile, OS hiccup) must not teleport the traffic or
	# skip the car through another one: long frames are simulated as 50 ms.
	dt = minf(dt, MAX_STEP_DT)
	_unbend()
	match state:
		State.MENU:
			_menu_camera(dt)
		State.PLAYING:
			_drive(dt)
			_watch_performance(_run_dt)
		State.CRASHING:
			_update_crash(dt)
	_bend_scene()
	_dev_harness(dt)


## The game runs on a straight road; the bends are drawn. After everything
## has moved, every separate object is shifted and turned onto the curve
## (long meshes bend in their shaders). Next frame starts by putting them
## back, so game logic only ever sees straight positions.
func _bend_scene() -> void:
	world.update_curve(camera.global_position.z)
	var cam_z := camera.global_position.z
	var nodes: Array[Node3D] = world.rigid_nodes()
	nodes.append(player_root)
	for v in _views.values():
		nodes.append(v)
	for o in _oncoming:
		nodes.append(o["view"])
	for w in _wrecks:
		nodes.append(w["view"])
	for id in _sites:
		nodes.append(_sites[id]["node"])
	for n in nodes:
		if not is_instance_valid(n) or not n.visible:
			continue
		var d := cam_z - n.position.z
		var b := world.bend_at(d)
		if absf(b) < 0.001 and absf(world.bend_slope(d)) < 0.0001:
			continue
		_bent.append([n, n.transform])
		n.transform = Transform3D(Basis(Vector3.UP, -atan(world.bend_slope(d))) * n.basis,
				n.position + Vector3(b, 0, 0))


func _unbend() -> void:
	for e in _bent:
		if is_instance_valid(e[0]):
			(e[0] as Node3D).transform = e[1]
	_bent.clear()


## Slow orbit on the home screen; a closer, draggable showroom view in the garage.
func _menu_camera(dt: float) -> void:
	player_view.animate(dt, 0.0, 0.0, 0.0, 0.0)
	var target := player_root.position
	var garage: bool = menu.current_screen() == "garage"
	_menu_t += dt
	var ang := _menu_t * (0.08 if garage else 0.12) + 0.6 + _menu_drag
	var k := 0.72 if player_view.is_bike else 1.0  # a bike is half a car long: come closer
	var dist := (7.4 if garage else 7.5) * k
	var want := target + Vector3(sin(ang) * dist, 1.45 if garage else 1.6, cos(ang) * dist)
	camera.global_position = camera.global_position.lerp(want, 1.0 - exp(-6.0 * dt)) \
			if _menu_t > 0.2 else want
	camera.look_at(target + Vector3(0, 0.75 if player_view.is_bike else 0.55, 0))
	camera.fov = 44.0 if garage else 48.0
	camera.h_offset = lerpf(camera.h_offset, (1.1 if garage else -2.4) * k, 1.0 - exp(-5.0 * dt))


## [steer -1..1, brake 0..1, throttle 0..1]
func _input_state() -> Array:
	var ext := Input.get_axis("steer_left", "steer_right")
	if save.settings.get("controls", "buttons") == "tilt":
		ext += _tilt_steer()
	hud.external_steer = clampf(ext, -1.0, 1.0)
	var steer := ext + hud.steer_axis
	var brake := 1.0 if (Input.is_action_pressed("brake") or hud.brake_held) else 0.0
	var gas := 1.0 if (hud.auto_gas or hud.gas_held or Input.is_action_pressed("gas")) else 0.0
	if _args.has("autopilot"):
		var ap := _autopilot()
		steer = ap[0]
		brake = ap[1]
		gas = 1.0
		hud.external_steer = steer
	steer *= float(save.settings.get("steer_sensitivity", 1.0))
	return [clampf(steer, -1.0, 1.0), brake, 0.0 if brake > 0.0 else gas]


## Sets the camera up for the chosen view (--cam=VIEW overrides it for the harness).
func _apply_camera() -> void:
	var cam: String = _args.get("cam", save.settings.get("camera", "near"))
	if not CAMERA_VIEWS.has(cam):
		cam = "near"
	_cockpit_on = cam == "cockpit" and state != State.MENU
	cockpit.visible = _cockpit_on
	player_view.visible = not _cockpit_on
	camera.hood = cam == "cockpit"
	camera.lean = 0.0
	# Bikes are short and low, so the chase view sits a little closer.
	camera.distance = 4.6 if player_view.is_bike else 6.4
	camera.height = 1.8 if player_view.is_bike else 2.35
	camera.look_ahead = 14.0
	camera.speed_look = 6.0
	if cam == "top":  # high and steep, the car big in the lower third
		camera.distance = 5.2 if player_view.is_bike else 6.5
		camera.height = 4.6 if player_view.is_bike else 5.5
		camera.look_ahead = 2.0
		camera.speed_look = 1.5
	camera.hood_side = 0.0
	camera.hood_drop = 0.55
	camera.hood_fov = 64.0
	if cam == "cockpit":  # from the driver's seat (left-hand drive) or the rider's helmet
		camera.hood_forward = -0.3 if player_view.is_bike else player_view.length * 0.02
		camera.hood_height = 1.4 if player_view.is_bike else player_view.height * 0.8
		camera.hood_side = 0.0 if player_view.is_bike else -0.37
		# On a bike you look down over the clocks to the bars and your hands.
		camera.hood_drop = 7.5 if player_view.is_bike else 2.2
		camera.hood_fov = 72.0 if player_view.is_bike else 68.0


func _cycle_camera() -> void:
	if state != State.PLAYING:
		return
	_args.erase("cam")
	var cur: String = save.settings.get("camera", "near")
	var next: String = CAMERA_VIEWS[(CAMERA_VIEWS.find(cur) + 1) % CAMERA_VIEWS.size()]
	save.settings["camera"] = next
	save.save_to_disk()
	_apply_camera()
	camera.snap(player_root.position)
	hud.popup(CAMERA_NAMES[next] + " VIEW", "", Color.WHITE)


## Gravity in screen coordinates (x right, y up). In a browser it comes
## from the page's devicemotion listener (Godot has no sensor there).
func _gravity_on_screen() -> Vector2:
	if OS.has_feature("web"):
		var parts := str(JavaScriptBridge.eval("window.__grav || ''")).split(",")
		return Vector2(float(parts[0]), float(parts[1])) if parts.size() == 2 else Vector2.ZERO
	# The fused gravity sensor ignores bumps and hand shake; fall back to the
	# raw accelerometer on phones without one.
	var g := Input.get_gravity()
	if g.length() < 0.01:
		g = Input.get_accelerometer()
	return Vector2(g.x, g.y)


## GYRO steering: turn the phone like a steering wheel (see TiltSteer).
func _tilt_steer() -> float:
	_last_gravity = _gravity_on_screen()
	return _tilt.update(_last_gravity)


## Some views get no motion data at all (a page embedded in another site, a
## desktop). Rather than leave the car unsteerable, go back to the arrows.
func _check_motion(dt: float) -> void:
	if save.settings.get("controls", "buttons") != "tilt" or _args.has("autopilot"):
		return
	_no_motion_t = 0.0 if _last_gravity.length() >= 0.05 else _no_motion_t + dt  # m/s² or g
	if _no_motion_t > 3.0:
		save.settings["controls"] = "buttons"
		save.save_to_disk()
		_apply_settings()
		hud.popup("GYRO NOT AVAILABLE HERE", "Switched to the arrow buttons", Color(1.0, 0.75, 0.3), true)


func _drive(dt: float) -> void:
	# Rebase first, before anything is placed this frame: rebasing after the
	# car was placed but before the camera followed it left the camera 1.2 km
	# away for one frame (a flash of empty sky every ~20 s, worst at 60 Hz).
	_maybe_rebase()
	var inp := _input_state()
	var throttle: float = inp[2]
	model.step(dt, throttle, inp[1], inp[0])
	_check_motion(dt)
	_update_horn(dt)
	var limit := HighwayWorld.BARRIER_X - 0.45 - player_view.width * 0.5
	var impact := model.constrain(limit)
	_scraping = absf(model.x) >= limit - 0.02 and absf(model.lat_vel) > 0.05 or impact > 0.0
	if impact > 0.6:
		_vibrate(25)
		score.on_bump()
		camera.kick(clampf(impact * 0.15, 0.1, 0.8), -signf(model.x))
		hud.popup("SCRAPE", "Flow lost", Color(1, 0.4, 0.3))
	player_z -= model.speed * dt
	model.x -= world.curve.curvature(world.u_of(player_z)) * model.speed * model.speed * CURVE_PUSH * dt
	# Lights on at night and in tunnels.
	var lights := world.is_night or world.tunnel_t > 0.2
	if lights != _lights_on:
		_lights_on = lights
		player_view.set_headlights(lights)
	# Two-way: driving in the oncoming lanes doubles every point.
	if mode == "twoway":
		var against := model.x < -0.4 and model.speed > 20.0
		score.lane_bonus = 2.0 if against else 1.0
		hud.set_bonus("ONCOMING  x2" if against else "")
	score.tick(dt, model.speed)
	if mode == "time":
		_time_left -= dt
		if score.distance >= _next_cp:
			_checkpoints += 1
			var bonus := maxf(18.0, 40.0 - _checkpoints * 3.0)
			_time_left += bonus
			_next_cp += CHECKPOINT_M
			hud.popup("CHECKPOINT", "+%d s" % int(bonus), Color(0.45, 0.95, 0.6), true)
			audio.flow_started()
		hud.set_timer(maxf(_time_left, 0.0), (_next_cp - score.distance) / 1000.0)
		if _time_left <= 0.0:
			_finish_run("TIME'S UP")
			return

	var res := sim.update(dt, player_z, model.x, model.speed, player_view.length,
			player_view.width, score.distance)
	for a in res["despawned"]:
		_on_despawn(a)
	for a in res["spawned"]:
		_on_spawn(a)
	for p in res["passes"]:
		var ag: TrafficSim.Agent = p["agent"]
		var r := score.on_pass(p["gap"], model.speed + (ag.speed if ag.dir > 0 else 0.0) * 0.5)
		if not r.is_empty():
			var sub := "+%d" % r["points"]
			if r["streak"] > 1:
				sub += "   x%d" % r["streak"]
			var col: Color = [Color(0.85, 0.95, 1.0), Hud.ACCENT, Color(1.0, 0.85, 0.2)][r["tier"]]
			hud.popup(r["name"], sub, col)
			camera.kick(0.15 + 0.12 * r["tier"], signf(model.x - ag.x))
			audio.near_miss(r["tier"], Vector3(ag.x, 0.8, ag.z))
			_vibrate(12 + 10 * int(r["tier"]))
			if r["flow_started"]:
				hud.popup("FLOW DRIVE", "All points x2" + ("   ·   car repaired" if r["repaired"] > 0.0 else ""),
						Hud.FLOW_COL, true)
				audio.flow_started()
				_vibrate(60)

	var hit: TrafficSim.Agent = null
	_invuln = maxf(0.0, _invuln - dt)
	if _invuln <= 0.0:
		hit = sim.collide(model.x, player_z, player_view.length, player_view.width)
	_update_player_view(dt, inp[1])
	player_view.visible = not _cockpit_on
	_sync_traffic(dt)
	_update_oncoming(dt)
	_update_wrecks(dt)
	if hit:  # a crash dents the car; the one that wrecks it ends the run
		if not hit.wreck and score.would_wreck(absf(model.speed - hit.speed * -hit.dir)):
			_begin_crash(hit)
		else:
			_bump(hit)
	world.update(player_z)
	camera.follow(dt, player_root.position, model.speed, model.top_speed, model.long_accel, model.lat_vel)
	audio.update_engine(dt, model.speed, model.top_speed, throttle, _scraping)
	_update_fx(dt)
	hud.set_values(score.score, score.distance, model.speed, score.flow, score.flow_active, score.streak,
			audio.gear())
	hud.set_damage(score.damage)


## Horn: hold the wheel hub (or H). The car ahead in your lane moves over
## if the next lane is clear.
func _update_horn(dt: float) -> void:
	var on := hud.horn_held or Input.is_action_pressed("horn")
	_horn_cool = maxf(0.0, _horn_cool - dt)
	if on != _horn_on:
		_horn_on = on
		audio.horn(on)
		if on and _horn_cool <= 0.0:
			_horn_cool = 0.6
			sim.honk(model.x, player_z)


func _update_fx(dt: float) -> void:
	_fx_time += dt
	_fx_flow = lerpf(_fx_flow, 1.0 if score.flow_active else 0.0, 1.0 - exp(-4.0 * dt))
	var sf := smoothstep(0.55, 1.0, model.speed / model.top_speed)
	var m := _fx.material as ShaderMaterial
	m.set_shader_parameter("speed", sf)
	m.set_shader_parameter("flow", _fx_flow)
	m.set_shader_parameter("time_s", _fx_time)
	world.environment.adjustment_saturation = 1.05 + 0.2 * _fx_flow


func _vibrate(ms: int) -> void:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		Input.vibrate_handheld(ms)


func _update_player_view(dt: float, brake: float) -> void:
	# Whole transform, never just the yaw, so no leftover roll can stick.
	player_root.transform = Transform3D(Basis(Vector3.UP, -model.heading()), Vector3(model.x, 0, player_z))
	var roll := clampf(model.lat_accel * 0.0045, -0.07, 0.07)
	var pitch := clampf(model.long_accel * 0.0045, -0.05, 0.035)
	player_view.animate(dt, model.speed, -model.steer_input * 0.22, roll, pitch)
	player_view.set_brake(brake > 0.0)
	if _cockpit_on:
		cockpit.update(model.steer_input)
		camera.lean = -player_view.lean * 0.5


func _maybe_rebase() -> void:
	if player_z > -HighwayWorld.REBASE:
		return
	var dz := HighwayWorld.REBASE
	player_z += dz
	sim.shift(dz)
	world.rebase(dz)
	camera.global_position.z += dz
	player_root.position.z += dz
	audio.shift(dz)
	for id in _sites:
		(_sites[id]["node"] as Node3D).position.z += dz
	for o in _oncoming:
		o["z"] += dz
		(o["view"] as CarVisual).position.z = o["z"]
	for w in _wrecks:
		w["z"] += dz
		(w["view"] as CarVisual).position.z = w["z"]
	for a in sim.agents:
		var v: CarVisual = _views.get(a.id)
		if v:
			v.position.z = a.z


# ------------------------------------------------------------------ crash

## A crash you drive through: the other car is knocked aside, you bounce
## off and lose speed, Flow and some points, then get a short ghost window.
func _bump(a: TrafficSim.Agent) -> void:
	var v: CarVisual = null
	if not a.wreck:  # a parked wreck stays put; you bounce off it
		v = _views.get(a.id)
		_views.erase(a.id)
		_prev_x.erase(a.id)
		sim.agents.erase(a)
	var closing := absf(model.speed - a.speed * -a.dir)
	var dx := model.x - a.x
	var side := signf(dx) if dx != 0.0 else 1.0
	if v:
		_wrecks.append({"view": v, "type": a.type_index, "x": a.x, "z": a.z, "dir": a.dir,
				"speed": a.speed if a.dir > 0 else a.speed + minf(closing, 15.0) * 0.4,
				"lat": -side * clampf(closing * 0.25, 2.0, 6.0), "yaw": PI if a.dir > 0 else 0.0,
				"spin": -side * clampf(closing * 0.05, 0.6, 2.0), "t": 0.0})
	if a.dir > 0:
		model.speed = maxf(model.min_speed, model.speed * 0.3)
	else:
		model.speed = maxf(model.min_speed, minf(model.speed, a.speed * 0.75))
	model.lat_vel = side * clampf(closing * 0.25, 2.5, 6.0)
	var penalty := score.on_crash(closing)
	hud.popup("CRASH", "-%d   ·   CAR %d%%" % [penalty, int(round((1.0 - score.damage) * 100.0))],
			Color(1.0, 0.4, 0.32), true)
	hud.set_bonus("")
	camera.kick(clampf(closing * 0.06, 0.6, 1.4), side)
	audio.impact()
	_vibrate(110)
	_flash.color = Color(1, 1, 1, 0.12)
	_invuln = 1.6


func _update_wrecks(dt: float) -> void:
	_flash.color.a = maxf(0.0, _flash.color.a - dt * 2.0)
	for i in range(_wrecks.size() - 1, -1, -1):
		var w := _wrecks[i]
		w["t"] += dt
		w["speed"] = maxf(0.0, float(w["speed"]) - 8.0 * dt)
		w["z"] += float(w["dir"]) * float(w["speed"]) * dt
		w["lat"] = float(w["lat"]) * exp(-1.5 * dt)
		w["x"] = clampf(float(w["x"]) + float(w["lat"]) * dt, -HighwayWorld.BARRIER_X + 1.1,
				HighwayWorld.BARRIER_X - 1.1)
		w["spin"] = float(w["spin"]) * exp(-1.6 * dt)
		w["yaw"] += float(w["spin"]) * dt
		var v: CarVisual = w["view"]
		v.position = Vector3(w["x"], 0, w["z"])
		v.rotation.y = w["yaw"]
		v.set_brake(true)
		v.animate(dt, w["speed"], 0.0, 0.0, 0.0)
		if float(w["z"]) > player_z + HighwayWorld.BEHIND or float(w["t"]) > 12.0:
			_release_view(w["type"], v)
			_wrecks.remove_at(i)

## A run-ending crash: slow motion, the car is thrown (hard hits flip and
## tumble it), sparks, glass and panels fly, the wreck smokes, and the
## camera circles it before the results.
func _begin_crash(a: TrafficSim.Agent) -> void:
	state = State.CRASHING
	_cockpit_on = false  # the crash camera circles the car, so show it
	cockpit.visible = false
	player_view.visible = true
	var v: CarVisual = _views.get(a.id)
	_views.erase(a.id)
	_prev_x.erase(a.id)
	sim.agents.erase(a)
	# Closing speed: head-on crashes in two-way are much harder.
	var rel := model.speed - a.speed * -a.dir
	var dx := model.x - a.x
	var side := signf(dx) if dx != 0.0 else 1.0
	var side_hit := absf(dx) > (a.width + player_view.width) * 0.5 - 0.5
	var sev := clampf(absf(rel) / 22.0, 0.25, 1.0)
	var flips := sev > 0.4
	_crash = {
		"t": 0.0, "view": v, "type": a.type_index, "o_dir": a.dir,
		"p_speed": model.speed, "p_spin": side * clampf(absf(rel) * 0.06, 0.6, 2.6),
		"p_lat": side * (2.5 if side_hit else 1.0), "p_yaw": player_root.rotation.y,
		"o_x": a.x, "o_z": a.z, "o_speed": maxf(a.speed * 0.3, a.speed - absf(rel) * 0.3) if a.dir > 0 				else a.speed + maxf(rel, 0.0) * 0.55,
		"o_spin": -side * clampf(absf(rel) * 0.03, 0.2, 1.4), "o_yaw": PI if a.dir > 0 else 0.0,
		# Tumble: height above resting, roll (barrel roll) and pitch.
		"y": 0.0, "vy": 1.5 + 3.2 * sev if flips else 0.8, "roll": 0.0, "pitch": 0.0,
		"roll_v": side * (2.5 + 6.0 * sev) if flips else side * 0.8,
		"pitch_v": randf_range(-1.2, 1.2) * sev, "spark_t": 0.0,
		"orbit": side, "slowmo": 0.9 + 0.5 * sev,
	}
	model.speed = (a.speed * 0.6 + model.speed * 0.15) if a.dir < 0 else model.speed * 0.2
	var paint := CarCatalog.paint_for(save.selected_car, save.paint_index(save.selected_car))
	crash_fx.impact(Vector3((model.x + a.x) * 0.5, 0.7, (player_z + a.z) * 0.5), paint, sev)
	camera.kick(1.6, side)
	audio.crash()
	audio.duck_music(true)
	_vibrate(180)
	_flash.color = Color(1, 1, 1, 0.3)
	Engine.time_scale = 0.25
	score.on_bump()
	score.crashes += 1
	score.damage = 1.0
	hud.set_bonus("")
	hud.show_crash()
	hud.popup("WRECKED", "", Color(1.0, 0.36, 0.28), true)


func _update_crash(dt: float) -> void:
	var c := _crash
	var real_dt := dt / maxf(Engine.time_scale, 0.01)
	c["t"] += real_dt
	_flash.color.a = maxf(0.0, _flash.color.a - real_dt * 1.2)
	if c["t"] > c["slowmo"]:
		Engine.time_scale = lerpf(Engine.time_scale, 1.0, 1.0 - exp(-2.5 * real_dt))
	# Player: thrown sideways, skids to a stop while spinning.
	model.speed = maxf(0.0, model.speed - 11.0 * dt)
	player_z -= model.speed * dt
	c["p_spin"] *= exp(-1.2 * dt)
	c["p_yaw"] += c["p_spin"] * dt
	c["p_lat"] *= exp(-2.0 * dt)
	model.x = clampf(model.x + c["p_lat"] * dt, -HighwayWorld.BARRIER_X + 1.2, HighwayWorld.BARRIER_X - 1.2)
	_tumble(c, dt)
	player_view.animate(dt, model.speed, 0.0, 0.0, 0.0)
	player_view.set_brake(true)
	crash_fx.follow(player_root.position + Vector3(0, 0.9, 0))
	# Hit car: shoved along its direction, spins, brakes.
	var v: CarVisual = c.get("view")
	if v:
		c["o_speed"] = maxf(0.0, c["o_speed"] - 9.0 * dt)
		c["o_z"] += float(c["o_dir"]) * c["o_speed"] * dt
		c["o_spin"] *= exp(-1.5 * dt)
		c["o_yaw"] += c["o_spin"] * dt
		v.position = Vector3(c["o_x"], 0, c["o_z"])
		v.rotation.y = c["o_yaw"]
		v.set_brake(true)
		v.animate(dt, c["o_speed"], 0.0, 0.0, 0.0)
	var res := sim.update(dt, player_z, model.x, model.speed, player_view.length,
			player_view.width, score.distance)
	for a in res["despawned"]:
		_on_despawn(a)
	for a in res["spawned"]:
		_on_spawn(a)
	_sync_traffic(dt)
	_update_oncoming(dt)
	world.update(player_z)
	# Cinematic camera: swings round the wreck, rising and pulling back
	# (high enough to look over traffic stopped behind it).
	var target := Vector3(model.x, 0.6, player_z)
	var ang: float = c["orbit"] * 1.1 * smoothstep(0.0, CRASH_TIME, c["t"])
	var d: float = 7.0 + c["t"] * 0.8
	var want := target + Vector3(sin(ang) * d, 3.0 + c["t"] * 0.5, cos(ang) * d)
	camera.h_offset = 0.0
	camera.global_position = camera.global_position.lerp(want, 1.0 - exp(-3.0 * real_dt))
	camera.look_at(target)
	camera.fov = lerpf(camera.fov, 55.0, 1.0 - exp(-2.0 * real_dt))
	if c["t"] >= CRASH_TIME:
		_finish_run("WRECKED")


## Rigid-body-ish tumble of the player car: gravity, bounces that throw
## sparks, roof scraping, then it settles on its wheels or its roof.
func _tumble(c: Dictionary, dt: float) -> void:
	c["vy"] -= 9.8 * dt
	c["y"] += c["vy"] * dt
	c["roll"] += c["roll_v"] * dt
	c["pitch"] += c["pitch_v"] * dt
	var grounded := false
	if c["y"] <= 0.0:
		c["y"] = 0.0
		grounded = true
		var hit_v: float = -c["vy"]
		if hit_v > 1.6:
			c["vy"] = hit_v * 0.38
			c["roll_v"] *= 0.6
			c["pitch_v"] *= 0.4
			crash_fx.scrape(player_root.position + Vector3(0, 0.3, 0), hit_v / 8.0)
			audio.impact()
			_vibrate(50)
		else:
			c["vy"] = 0.0
	if grounded and c["vy"] == 0.0:
		var rest := roundf(c["roll"] / PI) * PI  # back on its wheels, or on its roof
		c["roll"] = lerpf(c["roll"], rest, 1.0 - exp(-5.0 * dt))
		c["roll_v"] *= exp(-5.0 * dt)
		c["pitch"] = lerpf(c["pitch"], 0.0, 1.0 - exp(-5.0 * dt))
		c["pitch_v"] = 0.0
		# Metal on asphalt while it slides on its roof or side.
		c["spark_t"] -= dt
		if cos(c["roll"]) < 0.6 and model.speed > 4.0 and c["spark_t"] <= 0.0:
			c["spark_t"] = 0.1
			crash_fx.scrape(player_root.position + Vector3(0, 0.2, 0), 0.5)
	var b := Basis.from_euler(Vector3(c["pitch"], c["p_yaw"], c["roll"]))
	var cm := Vector3(0, player_view.height * 0.45, 0)
	# Lift so the lowest corner of the body rests on the road.
	var low := INF
	for sx in [-0.5, 0.5]:
		for sy in [0.0, 1.0]:
			for sz in [-0.5, 0.5]:
				var p := b * (Vector3(sx * player_view.width, sy * player_view.height, sz * player_view.length) - cm)
				low = minf(low, p.y)
	var pivot := Vector3(model.x, c["y"] - low, player_z)  # the body rotates about its centre of mass
	player_root.transform = Transform3D(b, pivot - b * cm)


func _finish_run(reason: String) -> void:
	Engine.time_scale = 1.0
	audio.duck_music(false)
	player_view.visible = true
	audio.stop_engine()
	_fx.visible = false
	state = State.RESULTS
	hud.set_timer(-1.0, 0.0)
	hud.set_bonus("")
	var rw := Progression.run_rewards(score.score, score.distance, score.near_misses, mode, score.crashes)
	var prev_best := int(save.best_by_mode.get(mode, 0))
	var rec := save.record_run(mode, int(score.score), score.distance, score.near_misses,
			int(rw["cash"]), int(rw["xp"]), score.overtakes)
	var done := save.apply_missions({
		"near_misses": score.near_misses, "distance_km": int(score.distance / 1000.0),
		"top_kmh": int(score.top_speed * 3.6), "flow_drives": score.flow_activations,
		"overtakes_total": score.overtakes, "twoway_m": int(score.oncoming_distance),
		"checkpoints": _checkpoints, "best_streak": score.best_streak,
	})
	save.save_to_disk()
	var mph := hud.mph
	var stats := [
		["Score", UiTheme.money(int(score.score))],
		["Distance", "%.2f %s" % [score.distance / (1609.0 if mph else 1000.0), "mi" if mph else "km"]],
		["Near misses", "%d   (best streak x%d)" % [score.near_misses, score.best_streak]],
		["Crashes", str(score.crashes)],
		["Top speed", "%d %s" % [int(score.top_speed * (2.237 if mph else 3.6)), "mph" if mph else "km/h"]],
		["Cash earned", "+ $ %s" % UiTheme.money(int(rw["cash"]))],
		["XP", "+ %s" % UiTheme.money(int(rw["xp"]))],
	]
	if mode == "time":
		stats.insert(2, ["Checkpoints", str(_checkpoints)])
	var extras := []
	if int(rw["clean_bonus"]) > 0:
		extras.append(["CLEAN RUN, NO CRASHES   + $ %s" % UiTheme.money(int(rw["clean_bonus"])), Color(0.45, 0.95, 0.6)])
	if rec["level_after"] > rec["level_before"]:
		extras.append(["LEVEL UP!  LV %d   + $ %s" % [rec["level_after"], UiTheme.money(rec["level_bonus"])], Hud.ACCENT])
	for m in done:
		extras.append(["MISSION COMPLETE: %s   + $ %s" % [m["text"], UiTheme.money(int(m["reward"]))],
				Color(0.45, 0.95, 0.6)])
	var head := "NEW BEST!" if rec["best"] and prev_best > 0 else reason
	hud.show_results(stats, head, extras)


# ------------------------------------------------------------------ autopilot

## Picks the lane with the most free road ahead and steers into it.
func _autopilot() -> Array:
	var best_lane := sim.lane_of_x(model.x)
	var best_free := -1.0
	var cur := best_lane
	var frees := []
	for l in sim.lanes:
		var free := 400.0
		for a in sim.agents:
			if a.occupies(l) and a.z < player_z + 3.0:
				free = minf(free, (player_z - a.z) * (0.35 if a.dir > 0 else 1.0))
		frees.append(free)
	for l in sim.lanes:
		var f: float = frees[l]
		# Only consider adjacent lanes whose side is clear right now.
		if absi(l - cur) > 1:
			continue
		if l != cur:
			var blocked := false
			for a in sim.agents:
				if a.occupies(l) and absf(a.z - player_z) < (a.length + player_view.length) * 0.5 + 2.0:
					blocked = true
			if blocked:
				continue
		var bonus := 15.0 if l == cur else 0.0
		if f + bonus > best_free:
			best_free = f + bonus
			best_lane = l
	var tx := sim.lane_x(best_lane)
	# Skilled driving: drift towards a car being passed in the next lane.
	for a in sim.agents:
		if absi(a.lane - best_lane) == 1 and not a.changing() and a.dir < 0 \
				and a.z < player_z + 2.0 and a.z > player_z - 12.0:
			tx += signf(a.x - tx) * 0.75
			break
	var steer := clampf((tx - model.x) * 0.9 - model.lat_vel * 0.3, -1.0, 1.0)
	var need := 18.0 + model.speed * 0.9
	var brake := 1.0 if frees[cur] < need and best_lane == cur else 0.0
	return [steer, brake]


# ------------------------------------------------------------------ harness

func _dev_harness(dt: float) -> void:
	if _args.has("slow"):  # pretend to be a weak phone: every frame takes N ms longer
		OS.delay_msec(int(_args["slow"]))
	if _args.has("slow-gpu"):  # ...or one whose GPU is the limit (cost scales with pixels)
		var sc := get_viewport().scaling_3d_scale
		OS.delay_msec(int(float(_args["slow-gpu"]) * sc * sc))
	if state == State.PLAYING or state == State.CRASHING or _args.has("menu"):
		_run_time += dt
		if _args.has("bench") and _run_time > 2.0:
			_frame_times.append(_run_dt)
			if _run_dt > 0.05:
				print("HITCH %.1f ms at t=%.2f dist=%d traffic=%d" % [_run_dt * 1000.0, _run_time, int(score.distance), sim.agents.size()])
	# Every rendered frame the camera must be near the car (catches world-rebase slips).
	if _args.has("bench") and state == State.PLAYING and not _cockpit_on \
			and absf(camera.global_position.z - player_z) > 40.0:
		print("CAMERA OFF CAR by %.0f m at dist=%d" % [camera.global_position.z - player_z, int(score.distance)])
	if state == State.PLAYING and _args.has("crash-at") and _run_time >= float(_args["crash-at"].split(",")[0]):
		var rest: PackedStringArray = _args["crash-at"].split(",").slice(1)
		if rest.is_empty():
			_args.erase("crash-at")
		else:
			_args["crash-at"] = ",".join(rest)
		var near: TrafficSim.Agent = null
		for a in sim.agents:
			if a.dir < 0 and a.z < player_z and (near == null or a.z > near.z):
				near = a
		if near:  # put it right in front, slightly offset, and hit it
			near.x = model.x + 0.7
			near.z = player_z - (near.length + player_view.length) * 0.5 + 0.4
			if score.would_wreck(absf(model.speed - near.speed * -near.dir)):
				_begin_crash(near)
			else:
				_bump(near)
	if state == State.PLAYING and _args.has("flow-at") and _run_time >= float(_args["flow-at"]):
		_args.erase("flow-at")
		score.flow = 1.0
		score.flow_active = true
		hud.popup("FLOW DRIVE", "All points x2", Hud.FLOW_COL, true)
		audio.flow_started()
	if state == State.RESULTS and _args.has("autopilot") and _args.has("restart"):
		start_run(mode, env)
	# The bend only yaws the car, so while driving it must stay upright.
	if state == State.PLAYING and _args.has("bench") and player_root.basis.y.y < 0.995:
		print("PLAYER TILTED at %.1f s: up=%s" % [_run_time, player_root.basis.y])
	if not _shots.is_empty() and _run_time >= _shots[0] and (state != State.MENU or _args.has("menu")):
		var t: float = _shots.pop_front()
		_screenshot("%s_%05.1f.png" % [_args.get("shot-prefix", "user://shot"), t])
	if _args.has("quit-at") and (_run_time >= float(_args["quit-at"]) \
			or Time.get_ticks_msec() > float(_args["quit-at"]) * 1000.0 + 15000.0):
		_quit()
	if state == State.RESULTS and _args.has("shot-results") and not _args.has("_res_done"):
		_args["_res_done"] = "1"
		await get_tree().create_timer(0.6).timeout
		_screenshot("%s_results.png" % _args.get("shot-prefix", "user://shot"))


func _screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path, " state=", State.keys()[state], " score=", int(score.score),
			" dist=", int(score.distance), " speed=", int(model.speed * 3.6), " traffic=", sim.agents.size())


func _quit() -> void:
	if _args.has("bench") and _frame_times.size() > 0:
		var arr := _frame_times.duplicate()
		arr.sort()
		var total := 0.0
		for f in arr:
			total += f
		var avg := total / arr.size()
		print("BENCH frames=%d avg_ms=%.2f p95_ms=%.2f max_ms=%.2f draw_calls=%d prims=%d" % [
			arr.size(), avg * 1000.0, arr[int(arr.size() * 0.95)] * 1000.0, arr[-1] * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	print("RUN mode=%s score=%d dist=%d near=%d overtakes=%d flow=%d state=%s" % [
		mode, int(score.score), int(score.distance), score.near_misses, score.overtakes,
		score.flow_activations, State.keys()[state]])
	get_tree().quit()
