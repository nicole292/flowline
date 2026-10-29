class_name TrafficSim
extends RefCounted
## Pure-logic traffic: spawning, despawning, car-following, lane changes,
## overtake/near-miss events and collision tests. The world moves towards -Z.
##
## Fairness rules:
##  * cars only appear far ahead (beyond spawn_ahead_min) or behind the
##    camera, never right in front of the player;
##  * a spawn is rejected if it would leave no open lane in its window;
##  * cars never cut in front of a nearby player.

class Agent:
	extends RefCounted
	var id := 0
	var type_index := 0
	var lane := 0
	var target_lane := 0
	var lane_t := 1.0          ## 0..1 progress of a lane change
	var signal_time := 0.0     ## blinker time left before moving over
	var x := 0.0
	var z := 0.0
	var speed := 20.0
	var desired_speed := 20.0
	var accel := 0.0
	var length := 4.5
	var width := 1.9
	var braking := false
	var ahead_of_player := true
	var dir := -1               ## -1 travels with the player (-z), +1 oncoming

	func occupies(l: int) -> bool:
		return lane == l or target_lane == l

	func changing() -> bool:
		return lane != target_lane

	func blinker() -> int:
		return signi(target_lane - lane) if changing() else 0


var lanes := 4
var lane_width := 3.6
## Left lane (index 0, -x) is the fast lane.
var lane_speeds: Array[float] = [31.0, 27.0, 23.5, 20.0]
## Travel direction per lane: -1 with the player, +1 oncoming (two-way mode).
var lane_dir: Array[int] = [-1, -1, -1, -1]
var spawn_ahead_min := 210.0
var spawn_ahead_max := 360.0
var despawn_behind := 70.0
var despawn_ahead := 520.0
var min_spawn_gap := 22.0
var wall_window := 14.0
var lane_change_rate := 0.05   ## chance per second per car
var density_start := 14
var density_max := 28
var density_ramp := 9000.0     ## metres to reach max density
## Each type: {length, width, weight, speed_mul}
var types: Array[Dictionary] = [{"length": 4.5, "width": 1.9, "weight": 1.0, "speed_mul": 1.0}]

var agents: Array[Agent] = []
var rng := RandomNumberGenerator.new()
var _next_id := 1


func lane_x(lane: int) -> float:
	return (lane - (lanes - 1) * 0.5) * lane_width


func lane_of_x(x: float) -> int:
	return clampi(int(round(x / lane_width + (lanes - 1) * 0.5)), 0, lanes - 1)


func target_count(distance: float) -> int:
	var t := clampf(distance / density_ramp, 0.0, 1.0)
	return int(round(lerpf(density_start, density_max, t)))


## Distance needed behind a leader at a given speed.
static func safe_gap(speed: float) -> float:
	return 7.0 + speed * 0.75


func lane_free(lane: int, z: float, gap: float, ignore: Agent = null) -> bool:
	for a in agents:
		if a == ignore or not a.occupies(lane):
			continue
		if absf(a.z - z) < gap + a.length * 0.5:
			return false
	return true


func blocked_lanes(z: float, window: float, extra_lane := -1) -> int:
	var blocked := {}
	if extra_lane >= 0:
		blocked[extra_lane] = true
	for a in agents:
		if absf(a.z - z) < window + a.length * 0.5:
			blocked[a.lane] = true
			blocked[a.target_lane] = true
	return blocked.size()


func can_spawn(lane: int, z: float) -> bool:
	if not lane_free(lane, z, min_spawn_gap):
		return false
	return blocked_lanes(z, wall_window, lane) < lanes


func pick_type() -> int:
	var total := 0.0
	for t in types:
		total += float(t["weight"])
	var r := rng.randf() * total
	for i in types.size():
		r -= float(types[i]["weight"])
		if r <= 0.0:
			return i
	return types.size() - 1


func spawn(lane: int, z: float, type_index: int) -> Agent:
	var t: Dictionary = types[type_index]
	var a := Agent.new()
	a.id = _next_id
	_next_id += 1
	a.type_index = type_index
	a.lane = lane
	a.target_lane = lane
	a.x = lane_x(lane)
	a.z = z
	a.length = t["length"]
	a.width = t["width"]
	a.desired_speed = lane_speeds[lane] * float(t["speed_mul"]) * rng.randf_range(0.92, 1.06)
	a.speed = a.desired_speed
	a.dir = lane_dir[lane]
	agents.append(a)
	return a


## Fills the road ahead at the start of a run, leaving the player's
## surroundings empty.
func populate(player_z: float, distance: float) -> Array[Agent]:
	var made: Array[Agent] = []
	var want := target_count(distance)
	var tries := 0
	while agents.size() < want and tries < want * 12:
		tries += 1
		var lane := rng.randi_range(0, lanes - 1)
		var z := player_z - rng.randf_range(70.0, spawn_ahead_max)
		if can_spawn(lane, z):
			made.append(spawn(lane, z, pick_type()))
	return made


## Advances traffic. Returns {spawned, despawned, passes} where passes is a
## list of {agent, gap} for cars the player just overtook.
func update(dt: float, player_z: float, player_x: float, player_speed: float,
		player_len: float, player_w: float, distance: float) -> Dictionary:
	var despawned: Array[Agent] = []
	for i in range(agents.size() - 1, -1, -1):
		var a := agents[i]
		if a.z > player_z + despawn_behind or a.z < player_z - despawn_ahead:
			despawned.append(a)
			agents.remove_at(i)

	var spawned: Array[Agent] = []
	var want := target_count(distance)
	var attempts := 3
	while agents.size() < want and attempts > 0:
		attempts -= 1
		var lane := rng.randi_range(0, lanes - 1)
		var z := player_z - rng.randf_range(spawn_ahead_min, spawn_ahead_max)
		# When the player is slow, faster lanes refill from behind instead.
		var player_lane := lane_of_x(player_x)
		if lane_dir[lane] < 0 and player_speed < lane_speeds[lane] * 0.8 and lane != player_lane 				and rng.randf() < 0.5:
			z = player_z + rng.randf_range(45.0, despawn_behind - 5.0)
		if can_spawn(lane, z):
			spawned.append(spawn(lane, z, pick_type()))

	_drive(dt, player_z, player_x, player_speed, player_len, player_w)

	var passes: Array[Dictionary] = []
	for a in agents:
		var ahead := a.z < player_z
		if a.ahead_of_player and not ahead:
			var gap := absf(a.x - player_x) - (a.width + player_w) * 0.5
			passes.append({"agent": a, "gap": gap})
		a.ahead_of_player = ahead
	return {"spawned": spawned, "despawned": despawned, "passes": passes}


func _drive(dt: float, pz: float, px: float, pspeed: float, plen: float, pw: float) -> void:
	for a in agents:
		# Lane change state machine: signal first, then move over smoothly.
		if a.changing():
			if a.signal_time > 0.0:
				a.signal_time -= dt
			else:
				a.lane_t = minf(1.0, a.lane_t + dt / 2.4)
				var s := a.lane_t * a.lane_t * (3.0 - 2.0 * a.lane_t)
				a.x = lerpf(lane_x(a.lane), lane_x(a.target_lane), s)
				if a.lane_t >= 1.0:
					a.lane = a.target_lane
					a.desired_speed = lane_speeds[a.lane] * float(types[a.type_index]["speed_mul"]) \
							* rng.randf_range(0.92, 1.06)
		elif rng.randf() < lane_change_rate * dt:
			_try_lane_change(a, pz, px)

		# Car following: nearest thing ahead (in this car's travel direction)
		# in any lane it occupies.
		var leader_gap := INF
		var leader_speed := a.desired_speed
		for b in agents:
			if b == a or b.dir != a.dir:
				continue
			var ahead := (a.z - b.z) * -a.dir
			if ahead <= 0.0:
				continue
			if not (b.occupies(a.lane) or b.occupies(a.target_lane)):
				continue
			var g := ahead - (a.length + b.length) * 0.5
			if g < leader_gap:
				leader_gap = g
				leader_speed = b.speed
		if a.dir < 0 and pz < a.z and absf(px - a.x) < (pw + a.width) * 0.5 + 0.5:
			var g := a.z - pz - (a.length + plen) * 0.5
			if g < leader_gap:
				leader_gap = g
				leader_speed = pspeed

		var target := a.desired_speed
		var want_gap := safe_gap(a.speed)
		if leader_gap < want_gap:
			target = minf(target, leader_speed - (want_gap - leader_gap) * 0.25)
		var max_brake := 9.0 if leader_gap < 6.0 else 5.5
		var acc := clampf((target - a.speed) * 1.5, -max_brake, 2.2)
		a.speed = maxf(0.0, a.speed + acc * dt)
		a.accel = acc
		a.braking = acc < -1.2
		a.z += a.dir * a.speed * dt
		# Hard guarantee: traffic never overlaps traffic.
		if leader_gap < INF:
			var new_gap := leader_gap - (a.speed - leader_speed) * dt
			if new_gap < 0.6:
				a.z += -a.dir * (0.6 - new_gap)
				a.speed = minf(a.speed, leader_speed)


func _try_lane_change(a: Agent, pz: float, px: float) -> void:
	var options: Array[int] = []
	for d in [-1, 1]:
		var l: int = a.lane + d
		if l < 0 or l >= lanes or lane_dir[l] != a.dir:
			continue
		if not lane_free(l, a.z, a.length + 10.0, a):
			continue
		# Never cut in front of a player who is close behind in that lane.
		var player_lane := lane_of_x(px)
		if player_lane == l and a.z < pz + 8.0 and a.z > pz - 45.0:
			continue
		options.append(l)
	if options.is_empty():
		return
	a.target_lane = options[rng.randi_range(0, options.size() - 1)]
	a.lane_t = 0.0
	a.signal_time = 1.3


## Returns the first agent overlapping the player's footprint, or null.
## Hitboxes are trimmed slightly so grazes read as near misses, not crashes.
func collide(px: float, pz: float, plen: float, pw: float) -> Agent:
	for a in agents:
		if absf(a.x - px) < (a.width + pw) * 0.5 - 0.08 \
				and absf(a.z - pz) < (a.length + plen) * 0.5 - 0.12:
			return a
	return null


func shift(dz: float) -> void:
	for a in agents:
		a.z += dz


func clear() -> void:
	agents.clear()
