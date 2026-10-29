extends Node3D
## Main game controller: owns the simulation objects, maps them to visuals,
## handles input, game states, crashes and the dev/test harness.
##
## Dev flags (after `--` on the command line):
##   --play            start driving immediately
##   --autopilot       a simple bot drives (for screenshots and soak tests)
##   --shots=a,b,c     save screenshots at these run times (seconds)
##   --shot-prefix=P   path prefix for screenshots
##   --quit-at=S       quit after S seconds of run time
##   --bench           print frame time stats on quit
##   --seed=N          fixed traffic seed
##   --car=id          player car

enum State { MENU, PLAYING, PAUSED, CRASHING, RESULTS }

const CRASH_TIME := 1.7

var world: HighwayWorld
var camera: ChaseCamera
var hud: Hud
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

var _views := {}      # agent id -> CarVisual
var _pools := {}      # type index -> Array of free CarVisual
var _prev_x := {}     # agent id -> x last frame
var _crash := {}
var _menu_t := 0.0
var _flash: ColorRect
var _fx: ColorRect
var _fx_flow := 0.0
var _fx_time := 0.0
var _scraping := false

# dev harness
var _args := {}
var _shots: Array[float] = []
var _frame_times: PackedFloat32Array = []
var _run_time := 0.0


func _ready() -> void:
	_parse_args()
	_setup_input()
	save.load_from_disk()
	world = HighwayWorld.new()
	add_child(world)
	world.build()
	camera = ChaseCamera.new()
	add_child(camera)
	camera.current = true

	var car_id: String = _args.get("car", save.selected_car)
	car_data = CarCatalog.player_car(car_id)
	model.configure(car_data["stats"])
	player_root = Node3D.new()
	add_child(player_root)
	player_view = CarVisual.new()
	player_root.add_child(player_view)
	player_view.setup(car_data["id"], car_data["paint"])

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
	audio.apply_settings(save.settings)

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
	hud.start_pressed.connect(func(): audio.click(); start_run())
	hud.pause_pressed.connect(func(): audio.click(); set_paused(true))
	hud.resume_pressed.connect(func(): audio.click(); set_paused(false))
	hud.restart_pressed.connect(func(): audio.click(); restart())

	_reset_player()
	_enter_menu()
	if _args.has("play") or _args.has("autopilot"):
		start_run.call_deferred()


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


# ------------------------------------------------------------------ states

func _reset_player() -> void:
	model.configure(car_data["stats"])
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
	_clear_traffic()
	hud.show_start()


func start_run() -> void:
	if state == State.PLAYING:
		return
	get_tree().paused = false
	Engine.time_scale = 1.0
	_clear_traffic()
	score = ScoreModel.new()
	state = State.PLAYING
	_reset_player()
	model.speed = 22.0
	for a in sim.populate(player_z, 0.0):
		_on_spawn(a)
	camera.snap(player_root.position)
	hud.show_playing()
	audio.start_engine()
	_fx.visible = true
	_fx_flow = 0.0
	_run_time = 0.0


func restart() -> void:
	state = State.RESULTS
	start_run()


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
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		save.save_to_disk()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if state == State.PLAYING:
			set_paused(true)
		elif state == State.PAUSED:
			set_paused(false)
	elif state == State.MENU and event.is_action_pressed("ui_accept"):
		start_run()


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
	for a in sim.agents:
		_on_despawn(a)
	sim.clear()
	if _crash.has("view"):
		_release_view(_crash["type"], _crash["view"])
	_crash = {}


func _sync_traffic(dt: float) -> void:
	for a in sim.agents:
		var v: CarVisual = _views.get(a.id)
		if v == null:
			continue
		var lat := (a.x - float(_prev_x[a.id])) / maxf(dt, 0.0001)
		_prev_x[a.id] = a.x
		v.position = Vector3(a.x, 0, a.z)
		v.rotation.y = -atan2(lat, maxf(a.speed, 1.0))
		v.set_brake(a.braking)
		v.set_blinker(a.blinker(), dt)
		v.animate(dt, a.speed, 0.0, 0.0, clampf(a.accel * 0.004, -0.03, 0.02))


# ------------------------------------------------------------------ main loop

func _process(dt: float) -> void:
	match state:
		State.MENU:
			_menu_t += dt
			player_view.animate(dt, 0.0, 0.0, 0.0, 0.0)
			var target := player_root.position
			var ang := _menu_t * 0.12 + 0.6
			camera.global_position = target + Vector3(sin(ang) * 7.5, 1.6, cos(ang) * 7.5)
			camera.look_at(target + Vector3(0, 0.6, 0))
			camera.fov = 50.0
		State.PLAYING:
			_drive(dt)
		State.CRASHING:
			_update_crash(dt)
	_dev_harness(dt)


func _input_state() -> Array:
	var steer := Input.get_axis("steer_left", "steer_right") + hud.steer_axis
	var brake := 1.0 if (Input.is_action_pressed("brake") or hud.brake_held) else 0.0
	if _args.has("autopilot"):
		var ap := _autopilot()
		steer = ap[0]
		brake = ap[1]
	steer *= float(save.settings.get("steer_sensitivity", 1.0))
	return [clampf(steer, -1.0, 1.0), brake]


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
	score.tick(dt, model.speed)

	var res := sim.update(dt, player_z, model.x, model.speed, player_view.length,
			player_view.width, score.distance)
	for a in res["despawned"]:
		_on_despawn(a)
	for a in res["spawned"]:
		_on_spawn(a)
	for p in res["passes"]:
		var r := score.on_pass(p["gap"], model.speed)
		if not r.is_empty():
			var sub := "+%d" % r["points"]
			if r["streak"] > 1:
				sub += "   x%d" % r["streak"]
			var col: Color = [Color(0.85, 0.95, 1.0), Hud.ACCENT, Color(1.0, 0.85, 0.2)][r["tier"]]
			hud.popup(r["name"], sub, col)
			var ag: TrafficSim.Agent = p["agent"]
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
	world.environment.adjustment_saturation = 1.08 + 0.2 * _fx_flow
	world.environment.glow_intensity = 0.55 + 0.35 * _fx_flow


func _vibrate(ms: int) -> void:
	if OS.has_feature("mobile"):
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
	var rel := model.speed - a.speed
	var dx := model.x - a.x
	var side_hit := absf(dx) > (a.width + player_view.width) * 0.5 - 0.5
	_crash = {
		"t": 0.0, "view": v, "type": a.type_index,
		"p_speed": model.speed, "p_spin": (signf(dx) if dx != 0.0 else 1.0) * clampf(absf(rel) * 0.06, 0.6, 2.6),
		"p_lat": signf(dx) * (2.5 if side_hit else 1.0), "p_yaw": player_root.rotation.y,
		"o_x": a.x, "o_z": a.z, "o_speed": a.speed + maxf(rel, 0.0) * 0.55,
		"o_spin": -signf(dx) * clampf(absf(rel) * 0.03, 0.2, 1.4), "o_yaw": 0.0,
	}
	model.speed = a.speed * 0.6 + model.speed * 0.15
	camera.kick(1.6, signf(dx))
	audio.crash()
	_vibrate(140)
	_flash.color = Color(1, 1, 1, 0.55)
	Engine.time_scale = 0.4
	score.on_bump()


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
	# Hit car: shoved forward, spins, brakes.
	var v: CarVisual = c.get("view")
	if v:
		c["o_speed"] = maxf(0.0, c["o_speed"] - 9.0 * dt)
		c["o_z"] -= c["o_speed"] * dt
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
	world.update(player_z)
	camera.follow(dt, player_root.position, maxf(model.speed, 1.0), model.top_speed, -8.0, 0.0)
	if c["t"] >= CRASH_TIME:
		_finish_run()


func _finish_run() -> void:
	Engine.time_scale = 1.0
	audio.stop_engine()
	_fx.visible = false
	state = State.RESULTS
	var earned := score.cash_earned()
	var prev_best := save.best_score
	var is_best := save.record_run(int(score.score), score.distance, score.near_misses, earned)
	save.save_to_disk()
	var stats := [
		["Score", Hud._fmt(int(score.score))],
		["Distance", "%.2f km" % (score.distance / 1000.0)],
		["Near misses", str(score.near_misses)],
		["Best streak", "x%d" % score.best_streak],
		["Top speed", "%d km/h" % int(score.top_speed * 3.6)],
		["Flow Drives", str(score.flow_activations)],
		["Cash earned", "+$%s" % Hud._fmt(earned)],
		["Best score", Hud._fmt(maxi(prev_best, int(score.score)))],
	]
	hud.show_results(stats, "NEW BEST!" if is_best and prev_best > 0 else "RUN OVER")


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
				free = minf(free, player_z - a.z)
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
		if absi(a.lane - best_lane) == 1 and not a.changing() 				and a.z < player_z + 2.0 and a.z > player_z - 12.0:
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
		start_run()
	if not _shots.is_empty() and _run_time >= _shots[0] and (state != State.MENU or _args.has("menu")):
		var t: float = _shots.pop_front()
		_screenshot("%s_%05.1f.png" % [_args.get("shot-prefix", "user://shot"), t])
	if _args.has("quit-at") and (_run_time >= float(_args["quit-at"]) 			or Time.get_ticks_msec() > float(_args["quit-at"]) * 1000.0 + 15000.0):
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
	print("RUN score=%d dist=%d near=%d overtakes=%d flow=%d state=%s" % [
		int(score.score), int(score.distance), score.near_misses, score.overtakes,
		score.flow_activations, State.keys()[state]])
	get_tree().quit()
