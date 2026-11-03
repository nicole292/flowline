class_name TiltSteer
extends RefCounted
## Tilt steering: turn the phone like a steering wheel. Input is gravity in
## screen coordinates (x right, y up). The angle the phone is held at when
## (re)calibrated counts as straight ahead.
##
## Phone apps report the direction of gravity (y is negative when upright),
## browsers report its reaction (y positive); "down" on the screen tells
## which one we have, so the steering sign is right either way.

var lock_deg := 22.0        ## tilt for full lock
var dead_deg := 1.5         ## small dead zone so straight is easy to hold
var calibrate := true       ## next reading becomes the centre
var zero_deg := 0.0
var value := 0.0            ## smoothed output, -1 (left) .. 1 (right)
var _sign := 1.0


## Feeds one sensor reading; returns the smoothed steering value.
func update(g: Vector2) -> float:
	if g.length() < 1.0:
		return value
	if absf(g.y) > 1.0:
		_sign = -signf(g.y)
	var deg := rad_to_deg(asin(clampf(g.x * _sign / 9.81, -1.0, 1.0)))
	if calibrate:
		calibrate = false
		zero_deg = clampf(deg, -20.0, 20.0)
	var d := deg - zero_deg
	d = signf(d) * maxf(0.0, absf(d) - dead_deg)
	value = lerpf(value, clampf(d / lock_deg, -1.0, 1.0), 0.35)
	return value
