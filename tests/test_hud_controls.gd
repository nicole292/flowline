extends RefCounted
## Touch controls: the arrow pads and horn button, the (parked) steering
## wheel and its horn hub, and the pedals, driven
## with synthetic touch events.

var t


func _hud(auto_gas := false, steer := "wheel") -> Hud:
	var h := Hud.new()
	t.root.add_child(h)
	h.set_controls(steer, auto_gas)
	h.show_playing()
	return h


func _touch(h: Hud, index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	h._input(e)


func _drag(h: Hud, index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	h._input(e)


## Drags touch 0 around the wheel rim from `from_deg` to `to_deg` (0 = right, -90 = top).
func _turn(h: Hud, from_deg: float, to_deg: float) -> void:
	var c := h._wheel_center()
	var r := h._wheel_radius() * 0.85
	var steps := 24
	for i in steps + 1:
		var a := deg_to_rad(lerpf(from_deg, to_deg, float(i) / steps))
		_drag(h, 0, c + Vector2.from_angle(a) * r)
	h._process(1.0 / 60.0)


func test_wheel_turns_both_ways_and_recentres() -> void:
	var h := _hud()
	var c := h._wheel_center()
	var r := h._wheel_radius() * 0.85
	_touch(h, 0, c + Vector2(0, -r), true)
	_turn(h, -90.0, -30.0)  # clockwise
	t.check(h.steer_axis > 0.3, "turning clockwise steers right (%f)" % h.steer_axis)
	_turn(h, -30.0, -150.0)  # back past centre, anticlockwise
	t.check(h.steer_axis < -0.3, "turning anticlockwise steers left (%f)" % h.steer_axis)
	_touch(h, 0, c + Vector2.from_angle(deg_to_rad(-150.0)) * r, false)
	for i in 40:
		h._process(1.0 / 60.0)
	t.near(h.steer_axis, 0.0, 0.001, "wheel self-centres when released")
	h.free()


func test_wheel_stops_at_full_lock_and_grabs_anywhere() -> void:
	var h := _hud()
	var c := h._wheel_center()
	var r := h._wheel_radius() * 0.85
	# Grab the bottom of the rim: no jump just from touching it.
	_touch(h, 0, c + Vector2(0, r), true)
	h._process(1.0 / 60.0)
	t.near(h.steer_axis, 0.0, 0.0001, "grabbing the wheel does not turn it")
	_turn(h, 90.0, 400.0)  # nearly a full turn clockwise
	t.near(h.steer_axis, 1.0, 0.0001, "clamped at full lock")
	_turn(h, 400.0, 380.0)
	t.check(h.steer_axis < 1.0, "turning back responds immediately at the lock")
	h.free()


func test_hub_is_the_horn() -> void:
	var h := _hud()
	_touch(h, 3, h._wheel_center(), true)
	t.check(h.horn_held, "pressing the hub sounds the horn")
	h._process(1.0 / 60.0)
	t.near(h.steer_axis, 0.0, 0.0001, "the horn does not steer")
	_touch(h, 3, h._wheel_center(), false)
	t.check(not h.horn_held, "released")
	h.free()


func test_pedals_and_sliding_between_them() -> void:
	var h := _hud()
	var r := h._pedal_rects()
	var gas: Rect2 = r["gas"]
	var brake: Rect2 = r["brake"]
	_touch(h, 1, gas.get_center(), true)
	t.check(h.gas_held and not h.brake_held, "gas pedal")
	_drag(h, 1, brake.get_center())
	t.check(h.brake_held and not h.gas_held, "thumb slides from gas onto brake")
	_touch(h, 1, brake.get_center(), false)
	t.check(not h.brake_held and not h.gas_held, "both released")
	# Steering and gas at the same time (two thumbs).
	var c := h._wheel_center()
	_touch(h, 0, c + Vector2(0, -h._wheel_radius() * 0.85), true)
	_touch(h, 1, gas.get_center(), true)
	_turn(h, -90.0, -45.0)
	t.check(h.gas_held and h.steer_axis > 0.2, "two thumbs: gas and steer together")
	h.clear_touches()
	h.free()


func test_auto_gas_has_only_a_brake() -> void:
	var h := _hud(true)
	var brake: Rect2 = h._pedal_rects()["brake"]
	_touch(h, 1, brake.get_center(), true)
	t.check(h.brake_held and not h.gas_held, "brake pedal in automatic mode")
	h.free()


func test_gyro_layout_brake_left_gas_right() -> void:
	var h := Hud.new()
	t.root.add_child(h)
	h.set_controls("tilt", false)
	h.show_playing()
	var vp := h.get_viewport_rect().size
	_touch(h, 0, Vector2(vp.x * 0.2, vp.y * 0.8), true)
	t.check(h.brake_held and not h.gas_held, "left half of the screen brakes")
	_touch(h, 1, Vector2(vp.x * 0.8, vp.y * 0.8), true)
	t.check(h.gas_held, "right half is the gas")
	t.check(h._pedal_rects()["brake"].position.x < vp.x * 0.5, "brake pedal drawn on the left")
	h.clear_touches()
	h.free()


func test_arrows_steer_and_slide() -> void:
	var h := _hud(false, "buttons")
	var a := h._arrow_rects()
	_touch(h, 0, a["left"].get_center(), true)
	t.near(h.steer_axis, -1.0, 0.0001, "left arrow steers left")
	_drag(h, 0, a["right"].get_center())
	t.near(h.steer_axis, 1.0, 0.0001, "thumb slides onto the right arrow")
	h._process(1.0 / 60.0)
	t.near(h.steer_axis, 1.0, 0.0001, "the wheel's self-centring does not touch the arrows")
	_touch(h, 0, a["right"].get_center(), false)
	t.near(h.steer_axis, 0.0, 0.0001, "released")
	# Arrow and gas together (two thumbs).
	_touch(h, 0, a["left"].get_center(), true)
	_touch(h, 1, h._pedal_rects()["gas"].get_center(), true)
	t.check(h.gas_held and h.steer_axis < 0.0, "two thumbs: gas and steer together")
	h.clear_touches()
	h.free()


func test_arrows_horn_button() -> void:
	var h := _hud(false, "buttons")
	_touch(h, 2, h._horn_center(), true)
	t.check(h.horn_held, "the horn button honks")
	t.near(h.steer_axis, 0.0, 0.0001, "the horn does not steer")
	_touch(h, 2, h._horn_center(), false)
	t.check(not h.horn_held, "released")
	h.free()
