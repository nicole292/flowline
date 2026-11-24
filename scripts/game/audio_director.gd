class_name AudioDirector
extends Node
## All game audio: layered sports-car engine with a simulated gearbox, barrier
## scrape, near-miss whooshes (panned to the passed car), chimes, crash,
## horn and a quiet looping background track.
## Uses three buses (Music, Sfx, Engine) so settings can scale each one.

const GEARS := [0.0, 0.17, 0.31, 0.46, 0.62, 0.80, 1.01]

var _engine_low: AudioStreamPlayer
## Engine sound (Settings > Engine): "classic" = the original two synthesised
## tones; "sport" = real recordings (CC0 Freesound, docs/audio_sources.md)
## with an on-load (exhaust) and off-load (muffled coasting) take crossfaded
## by the throttle, a roar near the redline, crackles and pops on lift-off,
## as racing games do; "muscle" = the same, deeper and heavier.
var engine_profile := "sport"
var _real: Array[AudioStreamPlayer] = []   # low, high, low_off, high_off
## Two recordings of the engine, as racing games do: ON load (foot down:
## loud, raw exhaust) and OFF load (coasting or braking: the distant and
## engine-bay mics, muffled, with exhaust crackles while the revs fall).
var _load := 1.0            ## 1 = on the gas, 0 = off; glides between
var _crackle_t := 0.0
## Motorcycle: the engine revs higher.
var bike := false
var _engine_high: AudioStreamPlayer
var _scrape: AudioStreamPlayer
var _ui: AudioStreamPlayer
var _chimes: Array[AudioStreamPlayer] = []   ## one per tier (swapping a playing stream cuts it off)
var _flow: AudioStreamPlayer
var _crash: AudioStreamPlayer
var _horn: AudioStreamPlayer
var _music: AudioStreamPlayer
var _music_db := -8.0      ## target level; dipped during crashes and pauses
var _whooshes: Array[AudioStreamPlayer3D] = []
var _whoosh_i := 0
var _rpm := 0.3
var _gear := 1
var _scrape_t := 0.0
var _streams := {}
## Arcade-racer engine feel: a quick rev drop and a short dip on every
## upshift, a blip on downshifts, and exhaust pops when you lift off at
## high revs (CC0 recordings, tools/audio/real_engine.py pops).
const SHIFT_TIME := 0.16
var _shift_t := 0.0
var _prev_throttle := 0.0
var _pop_cool := 0.0
var _pops: AudioStreamPlayer
const POP_SOUNDS := ["pop_crackle", "pop_1", "pop_2", "pop_3"]
## Loops that come and go (horn, scrape) are faded in and out instead of
## started and stopped: cutting a waveform mid-cycle is an audible click.
## player -> [gain now, gain wanted, level in dB at full gain]
var _gates := {}
## Players fading out before they stop: player -> dB per second.
var _fading := {}
const GATE_TIME := 0.04


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
	for n in ["engine_real_low", "engine_real_high", "engine_real_low_off", "engine_real_high_off"]:
		_real.append(_player(n, "Engine", true))
	_scrape = _player("scrape", "Sfx", true)
	_ui = _player("click", "Sfx")
	for t in 3:
		var c := _player("near_%d" % t, "Sfx")
		c.volume_db = -8.0
		c.max_polyphony = 2
		_chimes.append(c)
	_flow = _player("flow_start", "Sfx")
	_flow.volume_db = -4.0
	_crash = _player("crash", "Sfx")
	# Back-to-back hits overlap instead of chopping the previous crunch.
	_crash.max_polyphony = 3
	_ui.max_polyphony = 3
	_horn = _player("horn", "Sfx", true)
	_pops = _player("pop_1", "Engine")
	_pops.max_polyphony = 3
	_gates[_horn] = [0.0, 0.0, -7.0]
	_gates[_scrape] = [0.0, 0.0, 0.0]
	_music = _player("music", "Music", true)
	_music.volume_db = -40.0
	_music.play()
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
		s.loop_end = int(round(s.get_length() * s.mix_rate))
	_streams[key] = s
	return s


func _player(name: String, bus: String, loop := false) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _stream(name, loop)
	p.bus = bus
	add_child(p)
	return p


func apply_settings(settings: Dictionary) -> void:
	var prof := str(settings.get("engine_sound", "sport"))
	if prof != engine_profile:
		var running := _engine_players().any(func(p): return p.playing and not _fading.has(p))
		for p in _engine_players():
			_fade_out(p, 0.15)
		engine_profile = prof
		if running:
			start_engine()
	for bus in ["Music", "Sfx", "Engine"]:
		var v := float(settings.get(bus.to_lower() if bus != "Sfx" else "sfx", 1.0))
		var i := AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)


func _engine_players() -> Array:
	return [_engine_low, _engine_high] if engine_profile == "classic" else _real


func start_engine() -> void:
	for p in _engine_players():
		_fading.erase(p)
		if not p.playing:
			p.play()


func stop_engine() -> void:
	for p in _engine_players():
		_fade_out(p, 0.25)
	_gate(_scrape, false)
	_gate(_horn, false)


## Ramps a player down to silence, then stops it (no click).
func _fade_out(p: AudioStreamPlayer, seconds: float) -> void:
	if p.playing:
		_fading[p] = 60.0 / maxf(seconds, 0.01)


func _gate(p: AudioStreamPlayer, on: bool) -> void:
	var g: Array = _gates[p]
	g[1] = 1.0 if on else 0.0
	if on and not p.playing:
		g[0] = 0.0
		p.volume_db = -80.0
		p.play()


func _process(dt: float) -> void:
	# Music fades towards its target so dips and returns are smooth.
	_music.volume_db = move_toward(_music.volume_db, _music_db, dt * 18.0)
	for p: AudioStreamPlayer in _gates:
		var g: Array = _gates[p]
		if not p.playing or p.stream_paused:
			continue
		g[0] = move_toward(g[0], g[1], dt / GATE_TIME)
		p.volume_db = float(g[2]) + linear_to_db(maxf(g[0], 0.0001))
		if g[0] <= 0.0 and g[1] <= 0.0:
			p.stop()
	for p: AudioStreamPlayer in _fading.keys():
		if p.stream_paused:
			continue
		p.volume_db -= float(_fading[p]) * dt
		if p.volume_db <= -60.0 or not p.playing:
			p.stop()
			_fading.erase(p)


## The world was shifted by dz (see game._maybe_rebase): keep any whoosh
## still playing at the car it belongs to.
func shift(dz: float) -> void:
	for w in _whooshes:
		w.global_position.z += dz


## Freezes game sounds for the pause menu; the music keeps playing, quieter.
func set_paused(on: bool) -> void:
	for p in get_children():
		if p != _music and (p is AudioStreamPlayer or p is AudioStreamPlayer3D):
			p.stream_paused = on
	duck_music(on)


## Quieter music under a crash or the pause menu.
func duck_music(on: bool) -> void:
	_music_db = -17.0 if on else -8.0


func gear() -> int:
	return _gear


func horn(on: bool) -> void:
	_gate(_horn, on)


## Engine RPM from speed through a 6-speed box; 0..1 within the rev range.
## Engine revs 0..1 and the current gear, for the cockpit instruments.
func engine_rpm() -> float:
	return _rpm


func gear_number() -> int:
	return _gear


static func rpm_for(speed_frac: float, gear: int) -> float:
	var lo: float = GEARS[gear - 1]
	var hi: float = GEARS[gear]
	var r := clampf((speed_frac - lo) / (hi - lo), 0.0, 1.0)
	var floor_rpm := 0.25 if gear == 1 else 0.42
	return lerpf(floor_rpm, 1.0, r)


func update_engine(dt: float, speed: float, top_speed: float, throttle: float, scraping: bool) -> void:
	var sf := clampf(speed / top_speed, 0.0, 1.0)
	var was := _gear
	while _gear < GEARS.size() - 1 and sf > GEARS[_gear]:
		_gear += 1
	while _gear > 1 and sf < GEARS[_gear - 1] - 0.02:
		_gear -= 1
	if _gear != was:
		_shift_t = SHIFT_TIME
		if engine_profile != "classic" and _gear > was and _rpm > 0.8 and randf() < 0.3:
			_pop()   # the odd crack on a full-throttle upshift
	_shift_t = maxf(0.0, _shift_t - dt)
	var target := rpm_for(sf, _gear)
	# Revs snap to the new gear during a shift, then follow smoothly.
	# Real engines: revs snap to the new gear during a shift, then follow.
	var snap := _shift_t > 0.0 and engine_profile != "classic"
	_rpm = lerpf(_rpm, target, 1.0 - exp(-(30.0 if snap else 9.0) * dt))
	# Lifting off at high revs: exhaust pops.
	_pop_cool = maxf(0.0, _pop_cool - dt)
	if engine_profile != "classic" and _prev_throttle > 0.5 and throttle <= 0.5 and _rpm > 0.6 and randf() < 0.75:
		_pop()
	_prev_throttle = throttle
	if engine_profile == "classic":
		_mix_classic(dt, throttle)
	else:
		_mix_real(dt, throttle, engine_profile == "muscle")
	_scrape_t = 0.25 if scraping else maxf(0.0, _scrape_t - dt)
	_gate(_scrape, _scrape_t > 0.0)


## The original FLOWLINE engine (Stage 2, by player request 2026-11-24):
## two synthesised tones, a deep one and a high one, crossfading as the
## revs rise; lifting off makes it 5 dB softer. No exhaust pops.
func _mix_classic(dt: float, throttle: float) -> void:
	var fire_hz := lerpf(38.0, 200.0, _rpm)
	_engine_low.pitch_scale = clampf(fire_hz / 60.0, 0.3, 4.0)
	_engine_high.pitch_scale = clampf(fire_hz / 120.0, 0.3, 4.0)
	var hi_mix := smoothstep(0.3, 0.85, _rpm)
	_load = move_toward(_load, 1.0 if throttle > 0.5 else 0.0, dt * 12.0)   # glide, no step (click-free)
	var load_db := lerpf(-5.0, 0.0, _load)
	_engine_low.volume_db = linear_to_db(lerpf(1.0, 0.35, hi_mix)) - 4.0 + load_db
	_engine_high.volume_db = linear_to_db(maxf(hi_mix, 0.02)) - 6.0 + load_db


## Real recordings (dyno sessions at ~2550 and ~6200 rpm, firing at 85 and
## 206 Hz): each layer is pitched only a little and they crossfade at equal
## power; on-load and off-load takes crossfade with the throttle.
## muscle: everything pitched ~30% lower with more of the deep layer.
func _mix_real(dt: float, throttle: float, muscle: bool) -> void:
	var fire_hz := 70.0 * pow(290.0 / 70.0, _rpm) if bike else 55.0 * pow(240.0 / 55.0, _rpm)
	if muscle:
		fire_hz *= 0.7
	var lo_pitch := clampf(fire_hz / 85.0, 0.45, 2.2)
	var hi_pitch := clampf(fire_hz / 206.0, 0.45, 1.4)
	_real[0].pitch_scale = lo_pitch
	_real[1].pitch_scale = hi_pitch
	_real[2].pitch_scale = lo_pitch
	_real[3].pitch_scale = hi_pitch
	var hi_mix := smoothstep(115.0, 165.0, fire_hz) if not muscle else smoothstep(95.0, 160.0, fire_hz) * 0.8
	# Foot down: the loud exhaust take within ~0.1 s; lifting off fades over
	# ~0.25 s into the muffled coasting take.
	_load = move_toward(_load, 1.0 if throttle > 0.5 else 0.0, dt * (9.0 if throttle > 0.5 else 4.0))
	var shift_db := -6.0 * (_shift_t / SHIFT_TIME)   # the gap while the clutch is in
	var roar_db := (3.5 if muscle else 2.5) * smoothstep(0.75, 1.0, _rpm) * _load   # flat out: louder still
	var on_db := linear_to_db(maxf(sin(_load * PI * 0.5), 0.001)) + shift_db + roar_db - 3.0
	var off_db := linear_to_db(maxf(cos(_load * PI * 0.5), 0.001)) + shift_db - 5.0
	var lo_g := linear_to_db(maxf(cos(hi_mix * PI * 0.5), 0.01)) + (1.5 if muscle else 0.0)
	var hi_g := linear_to_db(maxf(sin(hi_mix * PI * 0.5), 0.01))
	_real[0].volume_db = lo_g + on_db
	_real[1].volume_db = hi_g + on_db
	_real[2].volume_db = lo_g + off_db
	_real[3].volume_db = hi_g + off_db
	# Coasting at high revs: the exhaust crackles and burbles now and then.
	_crackle_t -= dt
	if _load < 0.3 and _rpm > 0.45 and _crackle_t <= 0.0:
		_crackle_t = randf_range(0.22, 0.65)
		if randf() < 0.7:
			_crackle()


## A small, quiet pop for the off-throttle burble (separate from the big bang).
func _crackle() -> void:
	_pops.stream = _stream(POP_SOUNDS[1 + randi() % 3])
	_pops.pitch_scale = randf_range(1.0, 1.3)
	_pops.volume_db = randf_range(-20.0, -14.0)
	_pops.play()


func _pop() -> void:
	if _pop_cool > 0.0:
		return
	_pop_cool = 1.2
	_pops.stream = _stream(POP_SOUNDS[randi() % POP_SOUNDS.size()])
	_pops.pitch_scale = randf_range(0.9, 1.12)
	_pops.volume_db = randf_range(-12.0, -8.0)
	_pops.play()


func near_miss(tier: int, at: Vector3) -> void:
	var w := _whooshes[_whoosh_i]
	_whoosh_i = (_whoosh_i + 1) % _whooshes.size()
	w.global_position = at
	w.pitch_scale = randf_range(0.92, 1.1)
	w.play()
	_chimes[clampi(tier, 0, 2)].play()


func flow_started() -> void:
	_flow.play()


## A hit you drive through: the crunch without killing the engine.
func impact() -> void:
	_crash.play()


func crash() -> void:
	_crash.play()
	_gate(_horn, false)
	_gate(_scrape, false)
	_fade_out(_engine_high, 0.15)
	_fade_out(_real[1], 0.15)
	_fade_out(_real[3], 0.15)


func click() -> void:
	_ui.play()
