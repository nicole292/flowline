extends RefCounted

var t


func test_upgrades_improve_the_right_stats() -> void:
	var car := CarCatalog.player_car("vanta")
	var base := Progression.stats_for(car, {})
	var up := Progression.stats_for(car, {"speed": 5, "accel": 5, "handling": 5, "brakes": 5})
	t.check(up["top_speed"] > base["top_speed"] * 1.15, "top speed upgrade is noticeable")
	t.check(up["accel"] > base["accel"] * 1.3, "acceleration upgrade is noticeable")
	t.check(up["lat_max"] > base["lat_max"] and up["steer_response"] > base["steer_response"], "handling upgrade")
	t.check(up["brake_decel"] > base["brake_decel"] * 1.3, "brake upgrade")
	t.check(car["stats"]["top_speed"] == 56.0, "catalog data is not modified")


func test_upgrades_change_how_the_car_drives() -> void:
	var car := CarCatalog.player_car("vanta")
	var times := []
	for lv in [0, 5]:
		var m := VehicleModel.new()
		m.configure(Progression.stats_for(car, {"accel": lv}))
		m.speed = 15.0
		var time := 0.0
		while m.speed < 35.0 and time < 30.0:
			m.step(1.0 / 60.0, 1.0, 0.0, 0.0)
			time += 1.0 / 60.0
		times.append(time)
	t.check(times[1] < times[0] * 0.85, "fully upgraded car is clearly quicker (%.2f vs %.2f s)" % [times[1], times[0]])


func test_car_ladder_gets_faster_and_dearer() -> void:
	var cars := CarCatalog.PLAYER_CARS
	for i in range(1, cars.size()):
		t.check(int(cars[i]["price"]) > int(cars[i - 1]["price"]), "%s costs more" % cars[i]["id"])
		t.check(float(cars[i]["stats"]["top_speed"]) >= float(cars[i - 1]["stats"]["top_speed"]),
				"%s is at least as fast" % cars[i]["id"])
	t.check(int(cars[0]["price"]) == 0, "starter is free")


func test_upgrade_costs_rise() -> void:
	var car := CarCatalog.player_car("brute")
	for lv in range(2, Progression.MAX_LEVEL + 1):
		t.check(Progression.upgrade_cost(car, lv) > Progression.upgrade_cost(car, lv - 1), "level %d dearer" % lv)


func test_levels() -> void:
	t.check(Progression.level_info(0)["level"] == 1, "start at level 1")
	var need := Progression.xp_to_next(1)
	t.check(Progression.level_info(need)["level"] == 2, "level 2 at threshold")
	t.check(Progression.level_info(need - 1)["level"] == 1, "not before")


func test_rewards_favour_two_way() -> void:
	var a := Progression.run_rewards(10000.0, 3000.0, 10, "endless")
	var b := Progression.run_rewards(10000.0, 3000.0, 10, "twoway")
	t.check(b["cash"] > a["cash"], "two-way pays more")
	t.check(a["cash"] > 800 and a["cash"] < 3000, "a decent run pays a sensible amount (%d)" % a["cash"])


func test_first_car_is_reachable() -> void:
	# A decent 2-minute run should be worth a meaningful slice of the first car.
	var r := Progression.run_rewards(12000.0, 4000.0, 12, "endless")
	var runs := ceili(float(CarCatalog.PLAYER_CARS[1]["price"]) / float(r["cash"]))
	t.check(runs >= 4 and runs <= 12, "first new car takes %d good runs" % runs)


func test_missions_progress() -> void:
	var ms := [Progression.make_mission(0), Progression.make_mission(1)]
	for m in ms:
		m["per_run"] = true
	var stat: String = ms[0]["stat"]
	Progression.apply_run(ms, {stat: 1})
	t.check(int(ms[0]["progress"]) == 1, "per-run progress recorded")
	Progression.apply_run(ms, {stat: 0})
	t.check(int(ms[0]["progress"]) == 1, "per-run keeps the best, not the last")
	var life := Progression.make_mission(0)
	life["per_run"] = false
	Progression.apply_run([life], {life["stat"]: 2})
	Progression.apply_run([life], {life["stat"]: 2})
	t.check(int(life["progress"]) == mini(4, int(life["target"])), "lifetime missions add up")


func test_missions_get_harder() -> void:
	var first := Progression.make_mission(0)
	var later := Progression.make_mission(Progression.MISSIONS.size() * 3)
	t.check(later["stat"] == first["stat"] and int(later["target"]) > int(first["target"]), "targets grow")
	t.check(int(later["reward"]) > int(first["reward"]), "rewards grow")
