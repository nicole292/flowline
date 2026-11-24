extends RefCounted
## Sounds that come and go fade instead of being cut mid-waveform (a click),
## and the imported WAVs are plain PCM (no QOA decoding in the audio thread).

var t


func _director() -> AudioDirector:
	var a := AudioDirector.new()
	t.root.add_child(a)
	return a


func _run(a: AudioDirector, seconds: float) -> void:
	for i in int(seconds / 0.01):
		a._process(0.01)


func test_horn_fades_out_then_stops() -> void:
	var a := _director()
	a.horn(true)
	t.check(a._horn.playing, "horn starts")
	t.check(a._horn.volume_db < -40.0, "horn starts silent, not at full level")
	_run(a, 0.1)
	t.near(a._horn.volume_db, -7.0, 0.01, "horn reaches its level")
	a.horn(false)
	a._process(0.01)
	t.check(a._horn.playing, "horn still playing while it fades")
	t.check(a._horn.volume_db < -7.0, "horn is getting quieter")
	_run(a, 0.1)
	t.check(not a._horn.playing, "horn stopped once silent")
	a.free()


func test_scrape_follows_contact_with_fades() -> void:
	var a := _director()
	a.update_engine(0.016, 30.0, 70.0, 1.0, true)
	t.check(a._scrape.playing, "scrape starts on contact")
	for i in 40:  # contact ends; scrape holds 0.25 s, then fades out
		a.update_engine(0.016, 30.0, 70.0, 1.0, false)
		a._process(0.016)
	t.check(not a._scrape.playing, "scrape stopped after contact ended")
	a.free()


func test_engine_fades_when_run_ends() -> void:
	var a := _director()
	var e: AudioStreamPlayer = a._engine_players()[0]   # whichever engine sound is selected
	a.start_engine()
	a.update_engine(0.016, 30.0, 70.0, 1.0, false)
	a.stop_engine()
	t.check(e.playing, "engine fades rather than cutting off")
	_run(a, 0.5)
	t.check(not e.playing, "engine stopped after the fade")
	a.start_engine()
	t.check(e.playing and not a._fading.has(e), "restart cancels the fade")
	a.free()


func test_wavs_imported_uncompressed() -> void:
	for f in DirAccess.get_files_at("res://assets/audio"):
		if f.ends_with(".import"):
			var cfg := ConfigFile.new()
			cfg.load("res://assets/audio/" + f)
			t.check(int(cfg.get_value("params", "compress/mode", -1)) == 0, f + " is PCM")


func test_engine_softer_off_the_gas() -> void:
	# The original engine: lifting off makes it about 5 dB softer, gliding there.
	var a := _director()
	a.engine_profile = "classic"
	for i in 60:
		a.update_engine(0.016, 40.0, 62.0, 1.0, false)
	var on_db := a._engine_low.volume_db
	for i in 60:
		a.update_engine(0.016, 40.0, 62.0, 0.0, false)
	t.check(a._engine_low.volume_db < on_db - 3.0, "quieter off the gas (%.1f -> %.1f dB)" % [on_db, a._engine_low.volume_db])
	a.free()


func test_sport_engine_swaps_recordings_on_and_off_the_gas() -> void:
	# SPORT / MUSCLE: on the gas the exhaust take leads, off the gas the
	# muffled coasting take; MUSCLE is pitched lower for the same revs.
	var a := _director()
	a.engine_profile = "sport"
	for i in 60:
		a.update_engine(0.016, 50.0, 62.0, 1.0, false)
	t.check(a._real[1].volume_db > a._real[3].volume_db + 15.0, "gas: on-load take leads")
	var sport_pitch := a._real[0].pitch_scale
	for i in 60:
		a.update_engine(0.016, 50.0, 62.0, 0.0, false)
	t.check(a._real[3].volume_db > a._real[1].volume_db + 15.0, "off the gas: coasting take leads")
	a.engine_profile = "muscle"
	for i in 60:
		a.update_engine(0.016, 50.0, 62.0, 1.0, false)
	t.check(a._real[0].pitch_scale < sport_pitch * 0.85, "muscle is deeper")
	a.free()
