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
	s.record_run("endless", 5000, 2400.0, 7, 130, 900, 40)
	s.owned_cars.append("brute")
	s.selected_car = "brute"
	s.car_levels("brute")["speed"] = 3
	s.paints["brute"] = 4
	s.settings["sfx"] = 0.4
	s.settings["controls"] = "tilt"
	s.ensure_missions()
	t.check(s.save_to_disk(), "saved")
	var l := SaveData.new()
	l.path = PATH
	t.check(l.load_from_disk(), "loaded")
	t.check(l.best_by_mode["endless"] == 5000 and l.cash == 130 and l.runs == 1 and l.xp == 900, "values survive")
	t.check(l.selected_car == "brute" and l.owned_cars.has("brute"), "cars survive")
	t.check(int(l.car_levels("brute")["speed"]) == 3 and l.paint_index("brute") == 4, "upgrades and paint survive")
	t.near(l.settings["sfx"], 0.4, 0.0001, "slider settings survive")
	t.check(l.settings["controls"] == "tilt", "choice settings survive")
	t.check(l.missions.size() == 3, "missions survive")
	t.check(l.save_to_disk(), "can overwrite existing save")


func test_old_version_save_still_loads() -> void:
	var s := _fresh()
	s.from_dict({"best_score": 777, "cash": 50, "selected_car": "vanta", "owned_cars": ["vanta"],
			"settings": {"sfx": 0.5}})
	t.check(s.best_by_mode["endless"] == 777, "old best score becomes the endless best")
	t.check(s.missions.size() == 3, "missions created for old saves")
	t.check(s.settings["controls"] == "buttons", "new settings get defaults")
	s.from_dict({"settings": {"controls": "wheel", "camera": "hood"}})
	t.check(s.settings["controls"] == "wheel", "the steering wheel setting is kept")
	t.check(s.steer_for("vanta") == "wheel" and s.steer_for("raptor") == "buttons", "bikes ride with the arrows, not a wheel")
	s.settings["controls"] = "tilt"
	t.check(s.steer_for("raptor") == "tilt", "bikes can use GYRO")
	s.settings["controls"] = "wheel"
	t.check(s.settings["camera"] == "near", "a removed camera view falls back to the chase view")
	t.check(SaveData.clean_plate("my car!99xyz") == "MY CAR99", "plates are capitals, 8 characters max")
	s.from_dict({"plate": "nicky-1"})
	t.check(s.plate == "NICKY-1", "the plate survives a save")
	t.check(s.to_dict()["plate"] == "NICKY-1", "the plate is written to the save")


func test_corrupt_file_is_ignored() -> void:
	var s := _fresh()
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	t.check(not s.load_from_disk(), "corrupt save rejected")
	t.check(s.best_score == 0 and s.selected_car == SaveData.STARTER, "defaults kept")


func test_sanitises_bad_values() -> void:
	var s := _fresh()
	s.from_dict({"cash": -500, "selected_car": "solstice", "owned_cars": ["brute", "not_a_car"],
			"upgrades": {"brute": {"speed": 99}}})
	t.check(s.cash == 0, "negative cash clamped")
	t.check(s.owned_cars.has(SaveData.STARTER), "starter car always owned")
	t.check(not s.owned_cars.has("not_a_car"), "unknown cars dropped")
	t.check(s.selected_car == SaveData.STARTER, "cannot select a car you don't own")
	t.check(int(s.car_levels("brute")["speed"]) == Progression.MAX_LEVEL, "upgrade levels clamped")


func test_best_score_logic() -> void:
	var s := _fresh()
	t.check(s.record_run("endless", 100, 10.0, 0, 1)["best"], "first run is best")
	t.check(not s.record_run("endless", 50, 10.0, 0, 1)["best"], "lower is not best")
	t.check(s.record_run("twoway", 60, 10.0, 0, 1)["best"], "bests are per mode")
	t.check(s.cash == 3 and s.runs == 3, "accumulates")


func test_buying_cars_and_upgrades() -> void:
	var s := _fresh()
	s.cash = 11999
	t.check(not s.buy_car("kestrel"), "cannot buy without enough cash")
	s.cash = 12000
	t.check(s.buy_car("kestrel") and s.cash == 0, "buying spends the price")
	t.check(not s.buy_car("kestrel"), "cannot buy twice")
	var cost := Progression.upgrade_cost(CarCatalog.player_car("kestrel"), 1)
	s.cash = cost
	t.check(s.buy_upgrade("kestrel", "speed") and s.cash == 0, "upgrade spends its cost")
	t.check(not s.buy_upgrade("meridian", "speed"), "cannot upgrade a car you don't own")
	s.cash = 10_000_000
	for i in 10:
		s.buy_upgrade("kestrel", "brakes")
	t.check(int(s.car_levels("kestrel")["brakes"]) == Progression.MAX_LEVEL, "upgrades stop at max")


func test_paint_bought_once_then_free() -> void:
	var s := _fresh()
	s.cash = Progression.PAINT_COST
	t.check(s.choose_paint("vanta", 3) and s.cash == 0, "first time costs")
	t.check(s.choose_paint("vanta", -1), "factory colour is free")
	t.check(s.choose_paint("vanta", 3) and s.cash == 0, "owned colour is free to switch back")
	t.check(not s.choose_paint("vanta", 5), "new colour needs cash")


func test_level_up_pays_bonus() -> void:
	var s := _fresh()
	var r := s.record_run("endless", 0, 0.0, 0, 0, Progression.xp_to_next(1) + 10)
	t.check(r["level_after"] == 2 and r["level_bonus"] == Progression.level_up_reward(2), "level up reported")
	t.check(s.cash == Progression.level_up_reward(2), "bonus paid")


func test_missions_pay_and_refill() -> void:
	var s := _fresh()
	s.ensure_missions()
	var m: Dictionary = s.missions[0]
	var before := s.cash
	var done := s.apply_missions({m["stat"]: int(m["target"])})
	t.check(done.size() >= 1 and s.cash > before, "completed mission pays")
	t.check(s.missions.size() == 3, "list refilled")
	t.check(not s.missions.has(m), "completed mission removed")


func test_daily_reward_once_per_day() -> void:
	var s := _fresh()
	t.check(s.claim_daily("2026-11-01") == 500, "day 1 pays 500")
	t.check(s.claim_daily("2026-11-01") == 0, "only once a day")
	t.check(s.claim_daily("2026-11-02") == 1000, "streak grows")
	t.check(s.claim_daily("2026-11-05") == 500, "missed day resets streak")
