extends RefCounted

var t


func _sim(seed := 1) -> TrafficSim:
	var s := TrafficSim.new()
	s.rng.seed = seed
	s.types.clear()
	for ty in CarCatalog.TRAFFIC:
		s.types.append(ty)
	return s


func test_spawn_rejects_same_lane_overlap() -> void:
	var s := _sim()
	s.spawn(1, -200.0, 0)
	t.check(not s.can_spawn(1, -210.0), "too close in same lane")
	t.check(s.can_spawn(1, -260.0), "far enough in same lane")
	t.check(s.can_spawn(2, -200.0), "other lane ok")


func test_spawn_never_walls_off_all_lanes() -> void:
	var s := _sim()
	s.spawn(0, -200.0, 0)
	s.spawn(1, -202.0, 0)
	s.spawn(2, -198.0, 0)
	t.check(not s.can_spawn(3, -200.0), "fourth lane must stay open")
	t.check(s.can_spawn(3, -260.0), "fine further on")


func test_populate_keeps_player_area_clear() -> void:
	var s := _sim()
	var made := s.populate(0.0, 0.0)
	t.check(made.size() >= s.density_start - 2, "populates close to target (%d)" % made.size())
	for a in s.agents:
		t.check(a.z <= -70.0, "nothing spawned right in front of player (z=%f)" % a.z)


func _overlaps(s: TrafficSim) -> int:
	var n := 0
	for a in s.agents:
		for b in s.agents:
			if a.id >= b.id:
				continue
			if absf(a.x - b.x) < (a.width + b.width) * 0.5 - 0.05 \
					and absf(a.z - b.z) < (a.length + b.length) * 0.5 - 0.05:
				n += 1
	return n


func test_long_simulation_no_traffic_clipping() -> void:
	for seed in [1, 2, 3]:
		var s := _sim(seed)
		s.density_ramp = 1.0  # max density immediately
		var pz := 0.0
		var px := s.lane_x(1)
		var speed := 40.0
		s.populate(pz, 99999.0)
		var dist := 0.0
		var bad := 0
		var spawned_near := 0
		for i in 60 * 120:
			var dt := 1.0 / 60.0
			# Player weaves between lanes every few seconds.
			px = s.lane_x(int(i / 240) % 4)
			pz -= speed * dt
			dist += speed * dt
			var res := s.update(dt, pz, px, speed, 4.5, 1.9, dist)
			for a in res["spawned"]:
				if a.z < pz and a.z > pz - s.spawn_ahead_min + 1.0:
					spawned_near += 1
			bad += _overlaps(s)
		t.check(bad == 0, "seed %d: traffic overlapped %d times" % [seed, bad])
		t.check(spawned_near == 0, "seed %d: %d cars spawned inside view" % [seed, spawned_near])
		t.check(s.agents.size() <= s.density_max, "count bounded (%d)" % s.agents.size())


func test_despawn_cleans_up_behind() -> void:
	var s := _sim()
	s.spawn(0, 0.0, 0)
	var res := s.update(1.0 / 60.0, -500.0, 0.0, 40.0, 4.5, 1.9, 0.0)
	t.check(res["despawned"].size() == 1, "car far behind removed")


func test_pass_event_reports_gap() -> void:
	var s := _sim()
	s.density_start = 0
	s.density_max = 0
	var a := s.spawn(1, -10.0, 0)
	a.desired_speed = 20.0
	a.speed = 20.0
	var px := a.x + (a.width + 1.9) * 0.5 + 0.4
	var pz := 0.0
	var got := []
	for i in 120:
		pz -= 40.0 / 60.0
		var res := s.update(1.0 / 60.0, pz, px, 40.0, 4.5, 1.9, 0.0)
		got.append_array(res["passes"])
	t.check(got.size() == 1, "one pass event (%d)" % got.size())
	if got.size() == 1:
		t.near(got[0]["gap"], 0.4, 0.01, "gap measured between bodies")


func test_collision_box() -> void:
	var s := _sim()
	var a := s.spawn(1, -20.0, 0)
	t.check(s.collide(a.x, a.z + 2.0, 4.5, 1.9) == a, "rear-end detected")
	t.check(s.collide(a.x + (a.width + 1.9) * 0.5 - 0.02, a.z, 4.5, 1.9) == null,
			"a 2 cm graze is forgiven")
	t.check(s.collide(a.x + 3.6, a.z, 4.5, 1.9) == null, "next lane clear")


func test_traffic_brakes_for_slow_player() -> void:
	var s := _sim()
	s.density_start = 0
	s.density_max = 0
	var a := s.spawn(2, 40.0, 0)  # behind the player, same lane
	a.speed = 30.0
	a.desired_speed = 30.0
	var pz := 0.0
	for i in 600:
		pz -= 15.0 / 60.0
		s.update(1.0 / 60.0, pz, a.x, 15.0, 4.5, 1.9, 0.0)
		t.check(a.z - pz > (a.length + 4.5) * 0.5, "never rear-ends the player")
		if a.changing():
			break


func test_no_cut_in_close_to_player() -> void:
	var s := _sim(7)
	s.lane_change_rate = 50.0  # try to change lanes constantly
	s.density_start = 0
	s.density_max = 0
	var a := s.spawn(1, -15.0, 0)  # 15 m ahead in the lane next to the player
	var px := s.lane_x(2)
	s.update(1.0 / 60.0, 0.0, px, a.speed, 4.5, 1.9, 0.0)
	t.check(a.target_lane != 2, "won't move into the player's lane right ahead")


func test_heavy_traffic_update_cost() -> void:
	var s := _sim()
	s.density_start = 40
	s.density_max = 40
	s.min_spawn_gap = 8.0
	s.populate(0.0, 0.0)
	var start := Time.get_ticks_usec()
	var pz := 0.0
	for i in 600:
		pz -= 0.6
		s.update(1.0 / 60.0, pz, 0.0, 36.0, 4.5, 1.9, 0.0)
	var per_frame_ms := (Time.get_ticks_usec() - start) / 600.0 / 1000.0
	print("    traffic update with %d cars: %.3f ms/frame" % [s.agents.size(), per_frame_ms])
	t.check(per_frame_ms < 1.0, "traffic logic under 1 ms/frame (%.3f)" % per_frame_ms)


func test_two_way_traffic() -> void:
	var s := _sim(4)
	s.lane_dir = [1, 1, -1, -1]
	s.lane_speeds = [23.0, 19.5, 25.0, 21.0]
	s.density_ramp = 1.0
	s.lane_change_rate = 0.5
	var pz := 0.0
	var px := s.lane_x(3)
	s.populate(pz, 99999.0)
	var bad := 0
	var wrong_lane := 0
	var oncoming_passes := 0
	for i in 60 * 60:
		pz -= 30.0 / 60.0
		var before := {}
		for a in s.agents:
			before[a.id] = a.z
		var res := s.update(1.0 / 60.0, pz, px, 30.0, 4.5, 1.9, 99999.0)
		for a in s.agents:
			if s.lane_dir[a.lane] != a.dir or s.lane_dir[a.target_lane] != a.dir:
				wrong_lane += 1
			if a.dir > 0 and before.has(a.id) and a.z < float(before[a.id]) - 0.01:
				bad += 1
		for p in res["passes"]:
			if (p["agent"] as TrafficSim.Agent).dir > 0:
				oncoming_passes += 1
		bad += _overlaps(s)
	t.check(bad == 0, "oncoming traffic moves towards the player and never overlaps (%d)" % bad)
	t.check(wrong_lane == 0, "cars never drift into the other direction's lanes")
	t.check(oncoming_passes > 10, "oncoming cars are passed (%d)" % oncoming_passes)
