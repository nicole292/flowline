class_name AudioDirector
extends Node
## All game audio: layered engine with a simulated gearbox, wind, barrier
## scrape, near-miss whooshes (panned to the passed car), chimes, crash.
## Uses three buses (Music, Sfx, Engine) so settings can scale each one.

const GEARS := [0.0, 0.17, 0.31, 0.46, 0.62, 0.80, 1.01]

var _engine_low: AudioStreamPlayer
var _engine_high: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _scrape: AudioStreamPlayer
var _ui: AudioStreamPlayer
var _chime: AudioStreamPlayer
var _flow: AudioStreamPlayer
var _crash: AudioStreamPlayer
var _whooshes: Array[AudioStreamPlayer3D] = []
var _whoosh_i := 0
var _rpm := 0.3
var _gear := 1
var _scrape_t := 0.0
var _streams := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "Sfx", "Engine"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	_engine_low = _player("engine_low", "Engine", true)
	_engine_high = _player("engine_high", "Engine", true)
	_wind = _player("wind", "Sfx", true)
	_scrape = _player("scrape", "Sfx", true)
	_ui = _player("click", "Sfx")
	_chime = _player("near_0", "Sfx")
	_flow = _player("flow_start", "Sfx")
	_crash = _player("crash", "Sfx")
	for i in 4:
		var p := AudioStreamPlayer3D.new()
		p.stream = _stream("whoosh")
		p.bus = "Sfx"
		p.unit_size = 6.0
		p.max_db = 3.0
		add_child(p)
		_whooshes.append(p)


func _stream(name: String, loop := false) -> AudioStreamWAV:
	var key := name + ("_loop" if loop else "")
	if _streams.has(key):
		return _streams[key]
	var s: AudioStreamWAV = load("res://assets/audio/%s.wav" % name)
	if loop:
		s = s.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	_streams[key] = s
	return s


func _player(name: String, bus: String, loop := false) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _stream(name, loop)
	p.bus = bus
	add_child(p)
	return p


func apply_settings(settings: Dictionary) -> void:
	for bus in ["Music", "Sfx", "Engine"]:
		var v := float(settings.get(bus.to_lower() if bus != "Sfx" else "sfx", 1.0))
		var i := AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)


func start_engine() -> void:
	for p in [_engine_low, _engine_high, _wind]:
		if not p.playing:
			p.play()


func stop_engine() -> void:
	for p in [_engine_low, _engine_high, _wind, _scrape]:
		p.stop()


## Engine RPM from speed through a 6-speed box; 0..1 within the rev range.
static func rpm_for(speed_frac: float, gear: int) -> float:
	var lo: float = GEARS[gear - 1]
	var hi: float = GEARS[gear]
	var r := clampf((speed_frac - lo) / (hi - lo), 0.0, 1.0)
	var floor_rpm := 0.25 if gear == 1 else 0.42
	return lerpf(floor_rpm, 1.0, r)


func update_engine(dt: float, speed: float, top_speed: float, throttle: float, scraping: bool) -> void:
	var sf := clampf(speed / top_speed, 0.0, 1.0)
	while _gear < GEARS.size() - 1 and sf > GEARS[_gear]:
		_gear += 1
	while _gear > 1 and sf < GEARS[_gear - 1] - 0.02:
		_gear -= 1
	var target := rpm_for(sf, _gear)
	_rpm = lerpf(_rpm, target, 1.0 - exp(-9.0 * dt))
	var fire_hz := lerpf(38.0, 200.0, _rpm)
	_engine_low.pitch_scale = clampf(fire_hz / 60.0, 0.3, 4.0)
	_engine_high.pitch_scale = clampf(fire_hz / 120.0, 0.3, 4.0)
	var hi_mix := smoothstep(0.3, 0.85, _rpm)
	var load_db := 0.0 if throttle > 0.5 else -5.0
	_engine_low.volume_db = linear_to_db(lerpf(1.0, 0.35, hi_mix)) - 4.0 + load_db
	_engine_high.volume_db = linear_to_db(maxf(hi_mix, 0.02)) - 6.0 + load_db
	_wind.volume_db = linear_to_db(clampf(sf * sf * 1.2, 0.001, 1.0)) - 3.0
	_wind.pitch_scale = 0.8 + sf * 0.45
	_scrape_t = 0.25 if scraping else maxf(0.0, _scrape_t - dt)
	if _scrape_t > 0.0 and not _scrape.playing:
		_scrape.play()
	elif _scrape_t <= 0.0 and _scrape.playing:
		_scrape.stop()


func near_miss(tier: int, at: Vector3) -> void:
	var w := _whooshes[_whoosh_i]
	_whoosh_i = (_whoosh_i + 1) % _whooshes.size()
	w.global_position = at
	w.pitch_scale = randf_range(0.92, 1.1)
	w.play()
	_chime.stream = _stream("near_%d" % clampi(tier, 0, 2))
	_chime.volume_db = -8.0
	_chime.play()


func flow_started() -> void:
	_flow.volume_db = -4.0
	_flow.play()


## A hit you drive through: the crunch without killing the engine.
func impact() -> void:
	_crash.play()


func crash() -> void:
	_crash.play()
	_engine_high.stop()
	_scrape.stop()


func click() -> void:
	_ui.play()
