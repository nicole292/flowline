class_name TiltSteer
extends RefCounted
## Tilt steering: turn the phone like a steering wheel. Input is the gravity
## sensor's x and y. The steering angle is how far gravity has turned since
## the last calibration (how the phone was held at the start counts as
## straight ahead).
##
## Phones disagree on how they report this: Android gives the reaction
## (+9.8 upward), iOS the pull itself, some in m/s² and some in g, and some
## in the screen's landscape axes, others in the phone's own upright axes.
## Measuring the turn relative to the calibrated direction gives the same
## answer for all of them, because each is only a rotation, a flip of both
## axes or a scale of the screen's x/y. `invert` covers a phone that mirrors.

var lock_deg := 22.0        ## turn for full lock
var dead_deg := 1.5         ## small dead zone so straight is easy to hold
var calibrate := true       ## next usable reading becomes the centre
var invert := false
var value := 0.0            ## smoothed output, -1 (left) .. 1 (right)
var _zero := Vector2.ZERO   ## calibrated gravity direction (unit)
var _peak := 0.0            ## largest reading seen, so units don't matter


## Feeds one sensor reading; returns the smoothed steering value.
func update(g: Vector2) -> float:
	var len := g.length()
	_peak = maxf(_peak, len)
	# Phone lying (nearly) flat: x/y say nothing about the wheel. Hold.
	if len < 0.001 or len < _peak * 0.25:
		return value
	var dir := g / len
	if calibrate or _zero == Vector2.ZERO:
		calibrate = false
		_zero = dir
	# Clockwise turn of the phone (right) turns gravity anticlockwise on the
	# screen, which is a positive cross product with x right, y up.
	var deg := rad_to_deg(atan2(_zero.cross(dir), _zero.dot(dir)))
	if invert:
		deg = -deg
	deg = signf(deg) * maxf(0.0, absf(deg) - dead_deg)
	value = lerpf(value, clampf(deg / lock_deg, -1.0, 1.0), 0.35)
	return value
