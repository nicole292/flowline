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
##
## Crash sites: every so often a wreck (or two) sits stopped in a lane far
## ahead. It always leaves an open lane; traffic signals and goes around it.

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
	var wreck := false          ## a stopped, crashed car to drive around
	var yaw := 0.0              ## how far a wreck is slewed across its lane (radians)
	var police := false         ## the patrol car parked behind a crash, lights flashing

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
## Crash sites: distance (m) to the first one and the spacing after that.
var crash_sites := true
var crash_first := 900.0
var crash_spacing := Vector2(900.0, 1700.0)
## Traffic types that can be a wreck (indices into types); empty = any.
var wreck_types: Array[int] = []
## Type index of the police car that guards most crash sites (-1 = none).
var police_type := -1
## Each type: {length, width, weight, speed_mul}
var types: Array[Dictionary] = [{"length": 4.5, "width": 1.9, "weight": 1.0, "speed_mul": 1.0}]

var agents: Array[Agent] = []
var rng := RandomNumberGenerator.new()
var _next_id := 1
var _next_crash := -1.0
var _wrecks: Array[Agent] = []   # this frame's wrecks, so lane checks don't scan all traffic


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
		if r <= 0.0 and float(types[i]["weight"]) > 0.0:
			return i
	for i in range(types.size() - 1, -1, -1):  # rounding left a sliver: last real type
		if float(types[i]["weight"]) > 0.0:
			return i
	return 0


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

	spawned.append_array(_maybe_crash_site(player_z, distance))
	_wrecks.clear()
	for a in agents:
		if a.wreck:
			_wrecks.append(a)
	_drive(dt, player_z, player_x, player_speed, player_len, player_w)

	var passes: Array[Dictionary] = []
	for a in agents:
		var ahead := a.z < player_z
		if a.ahead_of_player and not ahead:
			var gap := absf(a.x - player_x) - (a.width + player_w) * 0.5
			passes.append({"agent": a, "gap": gap})
		a.ahead_of_player = ahead
	return {"spawned": spawned, "despawned": despawned, "passes": passes}


## Places a crash site far ahead once the run has gone far enough. One wreck,
## sometimes a second one slewed the other way just behind it; it only goes
## where at least one lane stays open.
func _maybe_crash_site(player_z: float, distance: float) -> Array[Agent]:
	var made: Array[Agent] = []
	if not crash_sites:
		return made
	if _next_crash < 0.0:
		_next_crash = crash_first
	if distance < _next_crash:
		return made
	var lanes_ok: Array[int] = []
	for l in lanes:
		if lane_dir[l] < 0:
			lanes_ok.append(l)
	var z := player_z - spawn_ahead_max + 20.0
	for attempt in 4:
		var lane: int = lanes_ok[rng.randi_range(0, lanes_ok.size() - 1)]
		if not lane_free(lane, z, 30.0) or blocked_lanes(z, 30.0, lane) >= lanes:
			continue
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		made.append(spawn_wreck(lane, z, side * rng.randf_range(0.25, 0.45)))
		if rng.randf() < 0.45 and lane_free(lane, z + 7.0, 3.0):
			made.append(spawn_wreck(lane, z + 7.0, -side * rng.randf_range(0.5, 0.8)))
		# The first patrol car on the scene parks behind it, slightly angled.
		if police_type >= 0 and rng.randf() < 0.75 and lane_free(lane, z + 18.0, 4.0):
			var p := spawn_wreck(lane, z + 18.0, side * 0.08, police_type)
			p.police = true
		# Placed: the next one comes later. Otherwise try again next frame.
		_next_crash = distance + rng.randf_range(crash_spacing.x, crash_spacing.y)
		break
	return made


func spawn_wreck(lane: int, z: float, yaw: float, type_index := -1) -> Agent:
	var ti := type_index
	if ti < 0:
		ti = pick_type() if wreck_types.is_empty() else wreck_types[rng.randi_range(0, wreck_types.size() - 1)]
	var a := spawn(lane, z, ti)
	a.wreck = true
	a.yaw = yaw
	a.speed = 0.0
	a.desired_speed = 0.0
	a.dir = -1
	# Footprint of the car turned across the lane.
	var l := a.length
	var w := a.width
	a.width = absf(l * sin(yaw)) + absf(w * cos(yaw))
	a.length = absf(l * cos(yaw)) + absf(w * sin(yaw))
	return a


## A wreck in `lane` within `reach` metres ahead of z (for traffic going -z).
func wreck_ahead(lane: int, z: float, reach: float) -> bool:
	for b in _wrecks:
		if b.lane == lane and z - b.z > 0.0 and z - b.z < reach:
			return true
	return false


func _drive(dt: float, pz: float, px: float, pspeed: float, plen: float, pw: float) -> void:
	for a in agents:
		if a.wreck:
			continue
		# Coming up on a wreck: get out of its lane now, not at random.
		if not a.changing() and a.dir < 0 and wreck_ahead(a.lane, a.z, 160.0):
			_try_lane_change(a, pz, px, 0.5)
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
			# Already moving out of a wreck's lane with room to spare: don't stop for it.
			if b.wreck and a.changing() and b.lane != a.target_lane and g > 12.0:
				continue
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


func _try_lane_change(a: Agent, pz: float, px: float, signal_s := 1.3) -> void:
	var options: Array[int] = []
	for d in [-1, 1]:
		var l: int = a.lane + d
		if l < 0 or l >= lanes or lane_dir[l] != a.dir:
			continue
		if not lane_free(l, a.z, a.length + 10.0, a) or wreck_ahead(l, a.z, 120.0):
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
	a.signal_time = signal_s


## Horn: the nearest car ahead in the player's lane signals briefly and
## moves over (preferring the slower lane) if a neighbouring lane is clear.
## Returns that car, or null when nobody can make room.
func honk(px: float, pz: float, reach := 90.0) -> Agent:
	var lane := lane_of_x(px)
	var best: Agent = null
	for a in agents:
		if a.dir > 0 or a.wreck or a.changing() or a.lane != lane:
			continue
		var ahead := pz - a.z
		if ahead > 0.0 and ahead < reach and (best == null or a.z > best.z):
			best = a
	if best == null:
		return null
	var options: Array[int] = []
	for d in [-1, 1]:
		var l: int = best.lane + d
		if l >= 0 and l < lanes and lane_dir[l] == best.dir and lane_free(l, best.z, best.length + 8.0, best):
			options.append(l)
	if options.is_empty():
		return null
	best.target_lane = options.max()
	best.lane_t = 0.0
	best.signal_time = 0.45
	return best


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
	_wrecks.clear()
	_next_crash = -1.0
