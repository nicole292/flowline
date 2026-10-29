extends RefCounted

var t
const PATH := "user://test_save.json"


func _fresh() -> SaveData:
	var s := SaveData.new()
	s.path = PATH
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	return s


func test_roundtrip() -> void:
	var s := _fresh()
	s.record_run(5000, 2400.0, 7, 130)
	s.owned_cars.append("vanta")
	s.selected_car = "vanta"
	s.settings["sfx"] = 0.4
	t.check(s.save_to_disk(), "saved")
	var l := SaveData.new()
	l.path = PATH
	t.check(l.load_from_disk(), "loaded")
	t.check(l.best_score == 5000 and l.cash == 130 and l.runs == 1, "values survive")
	t.check(l.selected_car == "vanta" and l.owned_cars.has("vanta"), "cars survive")
	t.near(l.settings["sfx"], 0.4, 0.0001, "settings survive")
	t.check(l.save_to_disk(), "can overwrite existing save")


func test_corrupt_file_is_ignored() -> void:
	var s := _fresh()
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	t.check(not s.load_from_disk(), "corrupt save rejected")
	t.check(s.best_score == 0 and s.selected_car == "kestrel", "defaults kept")


func test_sanitises_bad_values() -> void:
	var s := _fresh()
	s.from_dict({"cash": -500, "selected_car": "solstice", "owned_cars": ["vanta"]})
	t.check(s.cash == 0, "negative cash clamped")
	t.check(s.owned_cars.has("kestrel"), "starter car always owned")
	t.check(s.selected_car == "kestrel", "cannot select a car you don't own")


func test_best_score_logic() -> void:
	var s := _fresh()
	t.check(s.record_run(100, 10.0, 0, 1), "first run is best")
	t.check(not s.record_run(50, 10.0, 0, 1), "lower is not best")
	t.check(s.record_run(150, 10.0, 0, 1), "higher is best")
	t.check(s.cash == 3 and s.runs == 3, "accumulates")
