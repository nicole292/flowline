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

enum State { MENU, PLAYING, PAUSED, CRASHING, RESULTS }

const CRASH_TIME := 1.7
const CHECKPOINT_M := 2000.0

var world: HighwayWorld
var camera: ChaseCamera
var hud: Hud
var menu: MenuUI
var audio: AudioDirector
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
var _time_left := 0.0
var _next_cp := CHECKPOINT_M
var _checkpoints := 0
var _tilt := 0.0

# dev harness
var _args := {}
var _shots: Array[float] = []
var _frame_times: PackedFloat32Array = []
var _run_time := 0.0


func _ready() -> void:
	_parse_args()
	_setup_input()
	save.load_from_disk()
	if _args.has("cash"):
		save.cash = int(_args["cash"])
	if _args.has("car") and CarCatalog.has_player_car(_args["car"]):
		if not save.owned_cars.has(_args["car"]):
			save.owned_cars.append(_args["car"])
		save.selected_car = _args["car"]
	world = HighwayWorld.new()
	add_child(world)
	world.build()
	camera = ChaseCamera.new()
	add_child(camera)
	camera.current = true

	player_root = Node3D.new()
	add_child(player_root)
	player_view = CarVisual.new()
	player_root.add_child(player_view)
	_show_car(save.selected_car, CarCatalog.paint_for(save.selected_car, save.paint_index(save.selected_car)),
			save.rim_index(save.selected_car))

	sim.lanes = HighwayWorld.LANES
	sim.lane_width = HighwayWorld.LANE_W
	sim.types.clear()
	for t in CarCatalog.TRAFFIC:
		sim.types.append(t)
	if _args.has("seed"):
		sim.rng.seed = int(_args["seed"])
	_prewarm_pools()

	audio = AudioDirector.new()
	add_child(audio)

	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
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
	hud.resume_pressed.connect(func(): audio.click(); set_paused(false))
	hud.restart_pressed.connect(func(): audio.click(); restart())
	hud.menu_pressed.connect(func(): audio.click(); _quit_to_menu())
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
	if _args.has("screen"):
		menu.show_screen(_args["screen"])
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
	hud.show_steer_buttons = save.settings.get("controls", "buttons") != "tilt"
	var far: bool = save.settings.get("camera", "near") == "far"
	camera.distance = 7.6 if far else 6.4
	camera.height = 2.8 if far else 2.35
	var high: bool = save.settings.get("quality", "high") == "high"
	world.set_quality(high)
	get_viewport().scaling_3d_scale = 1.0 if high else 0.75
	if state == State.MENU:
		_show_car(save.selected_car, CarCatalog.paint_for(save.selected_car, save.paint_index(save.selected_car)),
				save.rim_index(save.selected_car))


## Loads (or recolours) the car shown in the menu and driven in a run.
func _show_car(id: String, paint: Color, rim: int) -> void:
	if _loaded_car != id:
		player_view.setup(id, paint)
		_loaded_car = id
	player_view.set_paint(paint)
	player_view.set_rim(rim)


# ------------------------------------------------------------------ states

func _reset_player() -> void:
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
	_set_env(save.last_env if save.level() >= menu._env_need(save.last_env) else "day")
	player_view.set_headlights(world.is_night)
	_reset_player()
	_show_car(save.selected_car, CarCatalog.paint_for(save.selected_car, save.paint_index(save.selected_car)),
			save.rim_index(save.selected_car))
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
	camera.h_offset = 0.0
	camera.snap(player_root.position)
	hud.show_playing()
	hud.set_timer(_time_left, _next_cp / 1000.0)
	hud.set_bonus("")
	audio.start_engine()
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
	get_tree().paused = on
	hud.show_pause(on)
	for p in audio.get_children():
		if p is AudioStreamPlayer or p is AudioStreamPlayer3D:
			p.stream_paused = on


func _notification(what: int) -> void:
	# Phones: pause when the app is backgrounded or interrupted.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if state == State.PLAYING:
			set_paused(true)
		save.save_to_disk()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		save.save_to_disk()


func _unhandled_input(event: InputEvent) -> void:
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
	var pool: Array = _pools.get(a.type_index, [])
	var v: CarVisual
	if pool.is_empty():
		v = CarVisual.new()
		add_child(v)
		v.setup(CarCatalog.TRAFFIC[a.type_index]["id"], Color.WHITE, true)
	else:
		v = pool.pop_back()
		v.visible = true
	v.set_paint(CarCatalog.random_paint(sim.rng))
	v.position = Vector3(a.x, 0, a.z)
	v.rotation = Vector3(0, PI if a.dir > 0 else 0.0, 0)
	_views[a.id] = v
	_prev_x[a.id] = a.x


func _on_despawn(a: TrafficSim.Agent) -> void:
	var v: CarVisual = _views.get(a.id)
	if v == null:
		return
	_views.erase(a.id)
	_prev_x.erase(a.id)
	_release_view(a.type_index, v)


## Loads every traffic model up front so spawning never hitches mid-run.
func _prewarm_pools() -> void:
	for i in CarCatalog.TRAFFIC.size():
		for n in 2:
			var v := CarVisual.new()
			add_child(v)
			v.setup(CarCatalog.TRAFFIC[i]["id"], Color.WHITE, true)
			_release_view(i, v)


func _release_view(type_index: int, v: CarVisual) -> void:
	v.visible = false
	v.set_brake(false)
	v.rotation = Vector3.ZERO
	if not _pools.has(type_index):
		_pools[type_index] = []
	_pools[type_index].append(v)


func _clear_traffic() -> void:
	for o in _oncoming:
		_release_view(o["type"], o["view"])
	_oncoming.clear()
	for a in sim.agents:
		_on_despawn(a)
	sim.clear()
	if _crash.has("view") and _crash["view"] != null:
		_release_view(_crash["type"], _crash["view"])
	_crash = {}


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
		v.set_paint(CarCatalog.random_paint(sim.rng))
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
	match state:
		State.MENU:
			_menu_camera(dt)
		State.PLAYING:
			_drive(dt)
		State.CRASHING:
			_update_crash(dt)
	_dev_harness(dt)


## Slow orbit on the home screen; a closer, draggable showroom view in the garage.
func _menu_camera(dt: float) -> void:
	player_view.animate(dt, 0.0, 0.0, 0.0, 0.0)
	var target := player_root.position
	var garage: bool = menu.current_screen() == "garage"
	_menu_t += dt
	var ang := _menu_t * (0.08 if garage else 0.12) + 0.6 + _menu_drag
	var dist := 7.4 if garage else 7.5
	var want := target + Vector3(sin(ang) * dist, 1.45 if garage else 1.6, cos(ang) * dist)
	camera.global_position = camera.global_position.lerp(want, 1.0 - exp(-6.0 * dt)) \
			if _menu_t > 0.2 else want
	camera.look_at(target + Vector3(0, 0.55, 0))
	camera.fov = 44.0 if garage else 48.0
	camera.h_offset = lerpf(camera.h_offset, 1.1 if garage else -2.4, 1.0 - exp(-5.0 * dt))


func _input_state() -> Array:
	var steer := Input.get_axis("steer_left", "steer_right") + hud.steer_axis
	if save.settings.get("controls", "buttons") == "tilt":
		steer += _tilt_steer()
	var brake := 1.0 if (Input.is_action_pressed("brake") or hud.brake_held) else 0.0
	if _args.has("autopilot"):
		var ap := _autopilot()
		steer = ap[0]
		brake = ap[1]
	steer *= float(save.settings.get("steer_sensitivity", 1.0))
	return [clampf(steer, -1.0, 1.0), brake]


## Tilt steering: rolling the phone like a wheel. ~25 degrees is full lock.
func _tilt_steer() -> float:
	var g := Input.get_accelerometer()
	if g.length() < 1.0:
		return 0.0
	var side := g.y if DisplayServer.screen_get_orientation() != DisplayServer.SCREEN_REVERSE_LANDSCAPE else -g.y
	var raw := clampf(side / (9.8 * sin(deg_to_rad(25.0))), -1.0, 1.0)
	if absf(raw) < 0.06:
		raw = 0.0
	_tilt = lerpf(_tilt, raw, 0.35)
	return _tilt


func _drive(dt: float) -> void:
	var inp := _input_state()
	var throttle := 0.0 if inp[1] > 0.0 else 1.0
	model.step(dt, throttle, inp[1], inp[0])
	var limit := HighwayWorld.BARRIER_X - 0.45 - player_view.width * 0.5
	var impact := model.constrain(limit)
	_scraping = absf(model.x) >= limit - 0.02 and absf(model.lat_vel) > 0.05 or impact > 0.0
	if impact > 0.6:
		_vibrate(25)
		score.on_bump()
		camera.kick(clampf(impact * 0.15, 0.1, 0.8), -signf(model.x))
		hud.popup("SCRAPE", "Flow lost", Color(1, 0.4, 0.3))
	player_z -= model.speed * dt
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
				hud.popup("FLOW DRIVE", "All points x2", Hud.FLOW_COL, true)
				audio.flow_started()
				_vibrate(60)

	var hit := sim.collide(model.x, player_z, player_view.length, player_view.width)
	_update_player_view(dt, inp[1])
	_sync_traffic(dt)
	_update_oncoming(dt)
	if hit:
		_begin_crash(hit)
	_maybe_rebase()
	world.update(player_z)
	camera.follow(dt, player_root.position, model.speed, model.top_speed, model.long_accel, model.lat_vel)
	audio.update_engine(dt, model.speed, model.top_speed, throttle, _scraping)
	_update_fx(dt)
	hud.set_values(score.score, score.distance, model.speed, score.flow, score.flow_active, score.streak)


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
	player_root.position = Vector3(model.x, 0, player_z)
	player_root.rotation.y = -model.heading()
	var roll := clampf(model.lat_accel * 0.0045, -0.07, 0.07)
	var pitch := clampf(model.long_accel * 0.0045, -0.05, 0.035)
	player_view.animate(dt, model.speed, -model.steer_input * 0.22, roll, pitch)
	player_view.set_brake(brake > 0.0)


func _maybe_rebase() -> void:
	if player_z > -HighwayWorld.REBASE:
		return
	var dz := HighwayWorld.REBASE
	player_z += dz
	sim.shift(dz)
	world.rebase(dz)
	camera.global_position.z += dz
	for o in _oncoming:
		o["z"] += dz
		(o["view"] as CarVisual).position.z = o["z"]
	for a in sim.agents:
		var v: CarVisual = _views.get(a.id)
		if v:
			v.position.z = a.z


# ------------------------------------------------------------------ crash

func _begin_crash(a: TrafficSim.Agent) -> void:
	state = State.CRASHING
	var v: CarVisual = _views.get(a.id)
	_views.erase(a.id)
	_prev_x.erase(a.id)
	sim.agents.erase(a)
	# Closing speed: head-on crashes in two-way are much harder.
	var rel := model.speed - a.speed * -a.dir
	var dx := model.x - a.x
	var side_hit := absf(dx) > (a.width + player_view.width) * 0.5 - 0.5
	_crash = {
		"t": 0.0, "view": v, "type": a.type_index, "o_dir": a.dir,
		"p_speed": model.speed, "p_spin": (signf(dx) if dx != 0.0 else 1.0) * clampf(absf(rel) * 0.06, 0.6, 2.6),
		"p_lat": signf(dx) * (2.5 if side_hit else 1.0), "p_yaw": player_root.rotation.y,
		"o_x": a.x, "o_z": a.z, "o_speed": maxf(a.speed * 0.3, a.speed - absf(rel) * 0.3) if a.dir > 0 \
				else a.speed + maxf(rel, 0.0) * 0.55,
		"o_spin": -signf(dx) * clampf(absf(rel) * 0.03, 0.2, 1.4), "o_yaw": PI if a.dir > 0 else 0.0,
	}
	model.speed = (a.speed * 0.6 + model.speed * 0.15) if a.dir < 0 else model.speed * 0.2
	camera.kick(1.6, signf(dx))
	audio.crash()
	_vibrate(140)
	_flash.color = Color(1, 1, 1, 0.55)
	Engine.time_scale = 0.4
	score.on_bump()
	hud.set_bonus("")


func _update_crash(dt: float) -> void:
	var c := _crash
	var real_dt := dt / maxf(Engine.time_scale, 0.01)
	c["t"] += real_dt
	_flash.color.a = maxf(0.0, _flash.color.a - real_dt * 1.5)
	if c["t"] > 0.6:
		Engine.time_scale = lerpf(Engine.time_scale, 1.0, 1.0 - exp(-3.0 * real_dt))
	# Player: skid to a stop while rotating.
	model.speed = maxf(0.0, model.speed - 14.0 * dt)
	player_z -= model.speed * dt
	c["p_spin"] *= exp(-1.2 * dt)
	c["p_yaw"] += c["p_spin"] * dt
	c["p_lat"] *= exp(-2.0 * dt)
	model.x = clampf(model.x + c["p_lat"] * dt, -HighwayWorld.BARRIER_X + 1.2, HighwayWorld.BARRIER_X - 1.2)
	player_root.position = Vector3(model.x, 0, player_z)
	player_root.rotation.y = c["p_yaw"]
	player_view.animate(dt, model.speed, 0.0, 0.0, 0.0)
	player_view.set_brake(true)
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
	camera.follow(dt, player_root.position, maxf(model.speed, 1.0), model.top_speed, -8.0, 0.0)
	if c["t"] >= CRASH_TIME:
		_finish_run("CRASHED")


func _finish_run(reason: String) -> void:
	Engine.time_scale = 1.0
	audio.stop_engine()
	_fx.visible = false
	state = State.RESULTS
	hud.set_timer(-1.0, 0.0)
	hud.set_bonus("")
	var rw := Progression.run_rewards(score.score, score.distance, score.near_misses, mode)
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
		["Top speed", "%d %s" % [int(score.top_speed * (2.237 if mph else 3.6)), "mph" if mph else "km/h"]],
		["Cash earned", "+ $ %s" % UiTheme.money(int(rw["cash"]))],
		["XP", "+ %s" % UiTheme.money(int(rw["xp"]))],
	]
	if mode == "time":
		stats.insert(2, ["Checkpoints", str(_checkpoints)])
	var extras := []
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
	if state == State.PLAYING or state == State.CRASHING or _args.has("menu"):
		_run_time += dt
		if _args.has("bench") and _run_time > 2.0:
			_frame_times.append(dt)
			if dt > 0.05:
				print("HITCH %.1f ms at t=%.2f dist=%d traffic=%d" % [dt * 1000.0, _run_time, int(score.distance), sim.agents.size()])
	if state == State.RESULTS and _args.has("autopilot") and _args.has("restart"):
		start_run(mode, env)
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
