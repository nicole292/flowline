extends RefCounted

var t


func test_tiers() -> void:
	t.check(ScoreModel.tier_for_gap(0.1) == 2, "insane")
	t.check(ScoreModel.tier_for_gap(0.5) == 1, "close")
	t.check(ScoreModel.tier_for_gap(1.1) == 0, "near")
	t.check(ScoreModel.tier_for_gap(1.5) == -1, "too far")
	t.check(ScoreModel.tier_for_gap(-0.1) == -1, "overlap is not a near miss")


func test_plain_overtake() -> void:
	var s := ScoreModel.new()
	var r := s.on_pass(2.0, 30.0)
	t.check(r.is_empty(), "no near miss")
	t.check(s.overtakes == 1 and s.near_misses == 0, "counted as overtake")
	t.near(s.score, ScoreModel.OVERTAKE_POINTS, 0.001, "overtake points")


func test_near_miss_points_scale_with_speed_and_streak() -> void:
	var a := ScoreModel.new()
	var slow := a.on_pass(0.5, 20.0)
	var b := ScoreModel.new()
	var fast := b.on_pass(0.5, 50.0)
	t.check(fast["points"] > slow["points"], "faster pass pays more")
	var second := b.on_pass(0.5, 50.0)
	t.check(second["streak"] == 2 and second["points"] > fast["points"], "streak bonus")


func test_streak_expires() -> void:
	var s := ScoreModel.new()
	s.on_pass(0.5, 30.0)
	s.tick(ScoreModel.STREAK_WINDOW + 0.1, 30.0)
	var r := s.on_pass(0.5, 30.0)
	t.check(r["streak"] == 1, "streak reset after window")


func test_flow_activates_doubles_and_drains() -> void:
	var s := ScoreModel.new()
	var started := false
	for i in 10:
		var r := s.on_pass(0.2, 40.0)
		if r["flow_started"]:
			started = true
			break
	t.check(started and s.flow_active, "insane passes fill flow")
	t.near(s.multiplier(), 2.0, 0.0, "x2 in flow")
	var before := s.score
	s.tick(1.0, 30.0)
	t.near(s.score - before, 30.0 * ScoreModel.DIST_POINTS * ScoreModel.speed_factor(30.0) * 2.0, 0.01,
			"distance points doubled")
	s.tick(30.0, 30.0)
	t.check(not s.flow_active and s.flow == 0.0, "flow drains out")


func test_bump_ends_flow() -> void:
	var s := ScoreModel.new()
	for i in 6:
		s.on_pass(0.2, 40.0)
	s.on_bump()
	t.check(not s.flow_active and s.flow == 0.0 and s.streak == 0, "bump resets flow and streak")


func test_flow_decays_only_after_grace() -> void:
	var s := ScoreModel.new()
	s.on_pass(0.5, 30.0)
	var f := s.flow
	s.tick(1.0, 30.0)
	t.near(s.flow, f, 0.0001, "no decay during grace")
	s.tick(5.0, 30.0)
	t.check(s.flow < f, "decays after grace")


func test_speed_factor() -> void:
	t.near(ScoreModel.speed_factor(80.0 / 3.6), 1.0, 0.001, "1x at 80")
	t.near(ScoreModel.speed_factor(160.0 / 3.6), 2.0, 0.001, "2x at 160")
	t.near(ScoreModel.speed_factor(10.0), 1.0, 0.001, "no penalty when slow")


func test_cash() -> void:
	var s := ScoreModel.new()
	s.score = 4000.0
	s.near_misses = 5
	t.check(s.cash_earned() == 110, "cash formula")


func test_crash_costs_points_but_never_below_zero() -> void:
	var s := ScoreModel.new()
	s.score = 5000.0
	for i in 6:
		s.on_pass(0.2, 40.0)
	var before := s.score
	var p := s.on_crash(30.0)
	t.check(p > 0 and is_equal_approx(s.score, before - p), "crash costs points")
	t.check(not s.flow_active and s.flow == 0.0 and s.streak == 0, "crash ends Flow and streak")
	t.check(s.crashes == 1, "crash counted")
	var small := ScoreModel.new()
	small.score = 100.0
	t.check(small.on_crash(50.0) == 100 and small.score == 0.0, "penalty never takes the score negative")


func test_crashes_add_up_to_a_wreck() -> void:
	var s := ScoreModel.new()
	t.check(not s.would_wreck(10.0), "a new car survives a crash")
	s.on_crash(10.0)
	t.check(s.damage > 0.2 and s.damage < 0.5, "a light crash dents the car (%f)" % s.damage)
	t.check(ScoreModel.crash_damage(40.0) > ScoreModel.crash_damage(10.0), "harder hits do more damage")
	s.on_crash(10.0)
	s.on_crash(10.0)
	t.check(s.would_wreck(10.0), "the fourth light crash wrecks it")


func test_flow_drive_repairs_the_car() -> void:
	var s := ScoreModel.new()
	s.on_crash(20.0)
	var d := s.damage
	var repaired := 0.0
	for i in 10:
		var r := s.on_pass(0.2, 40.0)
		if r["flow_started"]:
			repaired = r["repaired"]
			break
	t.near(repaired, ScoreModel.FLOW_REPAIR, 0.0001, "Flow Drive repairs damage")
	t.near(s.damage, d - ScoreModel.FLOW_REPAIR, 0.0001, "damage went down")
