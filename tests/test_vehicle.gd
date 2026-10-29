extends RefCounted

var t


func _car() -> VehicleModel:
	var m := VehicleModel.new()
	m.configure(CarCatalog.PLAYER_CARS[1]["stats"])
	m.speed = 20.0
	return m


func test_accelerates_but_never_exceeds_top_speed() -> void:
	var m := _car()
	var prev := m.speed
	for i in 60 * 60:
		m.step(1.0 / 60.0, 1.0, 0.0, 0.0)
		t.check(m.speed >= prev - 0.0001, "speed must not drop under full throttle")
		prev = m.speed
	t.check(m.speed <= m.top_speed + 0.001, "top speed respected")
	t.check(m.speed > m.top_speed * 0.9, "reaches near top speed within a minute")


func test_braking_slows_to_min_speed_not_below() -> void:
	var m := _car()
	m.speed = 50.0
	m.step(0.1, 0.0, 1.0, 0.0)
	t.near(m.speed, 50.0 - m.brake_decel * 0.1, 0.01, "brake deceleration")
	for i in 600:
		m.step(1.0 / 60.0, 0.0, 1.0, 0.0)
	t.near(m.speed, m.min_speed, 0.001, "clamped at min speed")


func test_steering_direction_and_grip_limit() -> void:
	var m := _car()
	m.speed = 40.0
	var dt := 1.0 / 60.0
	for i in 30:
		var before := m.lat_vel
		m.step(dt, 1.0, 0.0, 1.0)
		t.check(absf(m.lat_vel - before) <= m.lat_grip * dt + 1e-5, "lateral change limited by grip")
	t.check(m.x > 0.0 and m.lat_vel > 0.0, "positive steer moves towards +x")


func test_releasing_steer_settles_quickly() -> void:
	var m := _car()
	m.speed = 55.0
	for i in 30:
		m.step(1.0 / 60.0, 1.0, 0.0, -1.0)
	for i in 72:
		m.step(1.0 / 60.0, 1.0, 0.0, 0.0)
	t.check(absf(m.lat_vel) < 0.3, "lateral velocity settles within 1.2 s (got %f)" % m.lat_vel)


func test_lane_change_takes_reasonable_time() -> void:
	# One lane (3.6 m) at highway speed should take roughly 0.6-1.4 s.
	var m := _car()
	m.speed = 35.0
	var time := 0.0
	while m.x < 3.6 and time < 5.0:
		m.step(1.0 / 60.0, 1.0, 0.0, 1.0)
		time += 1.0 / 60.0
	t.check(time > 0.6 and time < 1.4, "lane change time %f" % time)


func test_barrier_constrain() -> void:
	var m := _car()
	m.speed = 40.0
	m.x = 8.0
	m.lat_vel = 5.0
	var impact := m.constrain(7.5)
	t.near(m.x, 7.5, 0.0001, "clamped to limit")
	t.near(impact, 5.0, 0.0001, "impact reported")
	t.check(m.lat_vel < 0.0, "bounces back")
	t.check(m.speed < 40.0, "scrape costs speed")
	t.near(m.constrain(7.5), 0.0, 0.0, "no impact when inside")


func test_cars_differ_in_handling() -> void:
	var times := []
	for c in CarCatalog.PLAYER_CARS:
		var m := VehicleModel.new()
		m.configure(c["stats"])
		m.speed = 15.0
		var time := 0.0
		while m.speed < 27.0 and time < 30.0:
			m.step(1.0 / 60.0, 1.0, 0.0, 0.0)
			time += 1.0 / 60.0
		times.append(time)
	t.check(times[0] > times[4], "supercar out-accelerates the starter car")
