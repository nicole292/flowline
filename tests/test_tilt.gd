extends RefCounted
## Tilt steering maths with both sensor sign conventions.

var t


## Gravity on screen for a phone held upright-ish (leaning back `lean` degrees
## from vertical) and turned `turn` degrees clockwise like a wheel.
## reaction = true gives the browser convention (y positive when upright).
func _g(turn: float, lean := 40.0, reaction := false) -> Vector2:
	var inplane := 9.81 * cos(deg_to_rad(lean))
	var r := deg_to_rad(turn)
	var down := Vector2(sin(r), -cos(r)) * inplane
	return -down if reaction else down


func _settle(s: TiltSteer, g: Vector2) -> float:
	for i in 40:
		s.update(g)
	return s.value


func test_turning_right_steers_right_in_both_conventions() -> void:
	for reaction in [false, true]:
		var s := TiltSteer.new()
		s.update(_g(0.0, 40.0, reaction))
		t.check(_settle(s, _g(12.0, 40.0, reaction)) > 0.3, "turn clockwise -> right (reaction=%s)" % reaction)
		t.check(_settle(s, _g(-12.0, 40.0, reaction)) < -0.3, "turn anticlockwise -> left (reaction=%s)" % reaction)
		t.near(_settle(s, _g(0.0, 40.0, reaction)), 0.0, 0.01, "level -> straight (reaction=%s)" % reaction)


func test_full_lock_and_dead_zone() -> void:
	var s := TiltSteer.new()
	s.update(_g(0.0, 0.0))
	t.near(_settle(s, _g(60.0, 0.0)), 1.0, 0.001, "big turn clamps at full lock")
	t.near(_settle(s, _g(1.0, 0.0)), 0.0, 0.001, "a 1 degree wobble does nothing")


func test_calibrates_to_how_the_phone_is_held() -> void:
	var s := TiltSteer.new()
	s.update(_g(8.0))  # player happens to hold it turned a little
	t.near(_settle(s, _g(8.0)), 0.0, 0.01, "that angle is straight ahead")
	t.check(_settle(s, _g(20.0)) > 0.3, "turning further still steers")
	s.calibrate = true
	s.update(_g(20.0))
	t.near(_settle(s, _g(20.0)), 0.0, 0.01, "recalibration re-centres")


## Same reading in the phone's own upright (portrait) axes, held in landscape:
## the screen's axes turned 90 degrees either way. iPhones can report this.
func _portrait(g: Vector2, side: float) -> Vector2:
	return Vector2(-g.y, g.x) * side


func test_portrait_axes_in_landscape_steer_the_right_way() -> void:
	for side in [1.0, -1.0]:
		for reaction in [false, true]:
			var s := TiltSteer.new()
			s.update(_portrait(_g(0.0, 40.0, reaction), side))
			t.check(_settle(s, _portrait(_g(12.0, 40.0, reaction), side)) > 0.3,
					"portrait axes, turn right -> right (side=%s reaction=%s)" % [side, reaction])
			t.check(_settle(s, _portrait(_g(-12.0, 40.0, reaction), side)) < -0.3,
					"portrait axes, turn left -> left (side=%s reaction=%s)" % [side, reaction])


func test_readings_in_g_units_work_too() -> void:
	var s := TiltSteer.new()
	s.update(_g(0.0) / 9.81)
	t.check(_settle(s, _g(12.0) / 9.81) > 0.3, "g units: turn right -> right")
	t.check(_settle(s, _g(-12.0) / 9.81) < -0.3, "g units: turn left -> left")


func test_invert_flips_the_direction() -> void:
	var s := TiltSteer.new()
	s.invert = true
	s.update(_g(0.0))
	t.check(_settle(s, _g(12.0)) < -0.3, "inverted: turn right -> left")


func test_phone_flat_holds_the_last_value() -> void:
	var s := TiltSteer.new()
	s.update(_g(0.0, 40.0))
	var v := _settle(s, _g(15.0, 40.0))
	t.near(_settle(s, _g(15.0, 89.0)), v, 0.01, "nearly flat: no sudden jump")
