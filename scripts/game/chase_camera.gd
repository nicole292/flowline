class_name ChaseCamera
extends Camera3D
## Third-person chase camera. Follows with lag, widens FOV with speed,
## pulls back under acceleration, adds very light high-speed shake and
## short kicks for near misses and impacts. In hood mode it rides on the
## car instead, looking down the road: the cockpit view uses it from the
## driver's seat (hood_side moves it off the centre line).

var base_fov := 58.0
var max_fov := 74.0
var distance := 6.4
var height := 2.35
var look_ahead := 14.0
## How much further down the road the view looks at top speed.
var speed_look := 6.0
var hood := false
## Hood view placement relative to the car centre (set from the car's size).
var hood_forward := 0.9
var hood_height := 1.12
var hood_side := 0.0
## How far below the horizon the hood / cockpit view looks (metres at 30 m).
var hood_drop := 0.55
var hood_fov := 64.0
## Extra roll in radians, for leaning into corners on a bike.
var lean := 0.0

var _x := 0.0
var _dist_offset := 0.0
var _kick := Vector3.ZERO
var _shake_t := 0.0
var _trauma := 0.0


func _ready() -> void:
	near = 0.15
	far = 900.0
	fov = base_fov


func kick(strength: float, dir_x := 0.0) -> void:
	_kick += Vector3(dir_x * 0.25, -0.08, 0.15) * strength
	_trauma = minf(1.0, _trauma + strength * 0.5)


func snap(target: Vector3) -> void:
	_x = target.x
	global_position = target + Vector3(0, height, distance)
	look_at(target + Vector3(0, 0.9, -look_ahead))


func follow(dt: float, target: Vector3, speed: float, top_speed: float,
		long_accel: float, lat_vel: float) -> void:
	var sf := clampf(speed / top_speed, 0.0, 1.0)
	if hood:
		_follow_hood(dt, target, speed, sf, lat_vel)
		return
	_x = lerpf(_x, target.x, 1.0 - exp(-4.5 * dt))
	var want_off := clampf(long_accel * 0.05, -0.35, 0.45)
	_dist_offset = lerpf(_dist_offset, want_off, 1.0 - exp(-2.5 * dt))
	_kick = _kick.lerp(Vector3.ZERO, 1.0 - exp(-7.0 * dt))
	_trauma = maxf(0.0, _trauma - dt * 1.6)
	_shake_t += dt
	var shake_amp := 0.012 * sf * sf + 0.06 * _trauma * _trauma
	var shake := Vector3(sin(_shake_t * 37.0) + sin(_shake_t * 23.0) * 0.6,
			sin(_shake_t * 41.0 + 1.3) * 0.8, 0.0) * shake_amp
	var d := distance + _dist_offset + sf * 0.5
	var pos := Vector3(_x + (target.x - _x) * 0.25, target.y + height - sf * 0.15, target.z + d)
	global_position = pos + _kick + shake
	var look := Vector3(lerpf(_x, target.x, 0.6), target.y + 0.85, target.z - look_ahead - sf * speed_look)
	look_at(look)
	rotate_object_local(Vector3.BACK, -lat_vel * 0.006)
	fov = lerpf(fov, base_fov + (max_fov - base_fov) * sf * sf, 1.0 - exp(-3.0 * dt))


func _follow_hood(dt: float, target: Vector3, speed: float, sf: float, lat_vel: float) -> void:
	_x = target.x
	_kick = _kick.lerp(Vector3.ZERO, 1.0 - exp(-9.0 * dt))
	_trauma = maxf(0.0, _trauma - dt * 1.6)
	_shake_t += dt
	# Road texture through the suspension: a faint high-frequency buzz.
	var amp := 0.004 * sf + 0.035 * _trauma * _trauma
	var shake := Vector3(sin(_shake_t * 31.0) * 0.5, sin(_shake_t * 47.0) + sin(_shake_t * 19.0) * 0.5, 0.0) * amp
	var h := atan2(lat_vel, maxf(speed, 1.0))
	var fwd := Vector3(sin(h), 0.0, -cos(h))
	var right := Vector3(cos(h), 0.0, sin(h))
	global_position = target + fwd * hood_forward + right * hood_side + Vector3(0, hood_height, 0)
	global_position += _kick * 0.4 + shake
	look_at(global_position + fwd * 30.0 + Vector3(0, -hood_drop, 0))
	rotate_object_local(Vector3.BACK, -lat_vel * 0.004 + lean)
	fov = lerpf(fov, hood_fov + 14.0 * sf * sf, 1.0 - exp(-3.0 * dt))
