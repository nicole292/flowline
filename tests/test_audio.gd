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
	a.start_engine()
	a.update_engine(0.016, 30.0, 70.0, 1.0, false)
	a.stop_engine()
	t.check(a._engine_low.playing, "engine fades rather than cutting off")
	_run(a, 0.5)
	t.check(not a._engine_low.playing, "engine stopped after the fade")
	a.start_engine()
	t.check(a._engine_low.playing and not a._fading.has(a._engine_low), "restart cancels the fade")
	a.free()


func test_wavs_imported_uncompressed() -> void:
	for f in DirAccess.get_files_at("res://assets/audio"):
		if f.ends_with(".import"):
			var cfg := ConfigFile.new()
			cfg.load("res://assets/audio/" + f)
			t.check(int(cfg.get_value("params", "compress/mode", -1)) == 0, f + " is PCM")
