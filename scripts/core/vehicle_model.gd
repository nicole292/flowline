class_name VehicleModel
extends RefCounted
## Arcade driving model for a straight highway.
##
## Longitudinal: engine force that is traction-limited at low speed and
## power-limited above `power_speed` (so it falls off like a real car's),
## fading to zero at top speed; brakes; engine braking and drag off throttle.
## Lateral: steering sets a target sideways velocity; the car reaches it
## through a response rate and a grip limit, which is what gives lane changes
## weight. Visual yaw/roll/pitch are derived from these values by the view.

var top_speed := 62.0       ## m/s
var accel := 8.0            ## m/s² from low speed
var brake_decel := 13.0     ## m/s²
var lat_max := 8.0          ## m/s sideways at full lock
var steer_response := 10.0  ## 1/s, how fast lateral velocity follows input
var lat_grip := 30.0        ## m/s², max change of lateral velocity
var min_speed := 11.0       ## the car never fully stops on the highway
var power_speed := 26.0     ## m/s where full acceleration starts to fall off

var speed := 20.0
var x := 0.0
var lat_vel := 0.0
var long_accel := 0.0
var lat_accel := 0.0
var steer_input := 0.0      ## smoothed steering actually applied

## Game-wide steering quickness on top of each car's stats (the garage bars
## compare cars, so they stay as they were). Playtest 2026-11-14: "turns faster".
const TURN_SPEED := 1.3     ## sideways speed at full lock
const TURN_SNAP := 1.35     ## how quickly the car reaches it
const TURN_GRIP := 1.4      ## grip limit on that change


func configure(stats: Dictionary) -> void:
	for key in stats:
		set(key, stats[key])


func step(dt: float, throttle: float, brake: float, steer: float) -> void:
	var prev_speed := speed
	var a: float
	if brake > 0.0:
		a = -brake_decel * brake
	else:
		var r := speed / top_speed
		var drive := accel * minf(1.0, power_speed / maxf(speed, 1.0)) * (1.0 - r * r) * throttle
		var drag := (0.6 + 0.0003 * speed * speed) * (1.0 - throttle)
		a = drive - drag
	speed = clampf(speed + a * dt, min_speed, top_speed)
	long_accel = (speed - prev_speed) / dt

	# Input reaches the wheels in ~0.03 s: just enough to take the edge off a
	# digital tap, short enough that a turn feels immediate.
	steer_input = move_toward(steer_input, clampf(steer, -1.0, 1.0), dt * 30.0)
	var speed_factor := clampf(speed / 24.0, 0.35, 1.0)
	var target := steer_input * lat_max * TURN_SPEED * speed_factor
	var dv := (target - lat_vel) * (1.0 - exp(-steer_response * TURN_SNAP * dt))
	# Steering against the current drift bites harder, so flicking from one
	# direction to the other happens at once instead of after a slide.
	var grip := lat_grip * TURN_GRIP * (1.6 if target * lat_vel < 0.0 else 1.0)
	dv = clampf(dv, -grip * dt, grip * dt)
	lat_vel += dv
	lat_accel = dv / dt
	x += lat_vel * dt


## Keeps the car between the barriers. Returns impact speed (m/s) if it hit.
func constrain(limit: float) -> float:
	if absf(x) <= limit:
		return 0.0
	var impact := absf(lat_vel)
	x = clampf(x, -limit, limit)
	lat_vel = -lat_vel * 0.25
	speed = maxf(min_speed, speed - impact * 1.2)
	return impact


## Visual heading of the car in radians (positive = towards +x).
func heading() -> float:
	return atan2(lat_vel, maxf(speed, 1.0))
