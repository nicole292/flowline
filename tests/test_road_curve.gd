extends RefCounted
## The planned bends and tunnels of the highway.

var t


func test_first_kilometre_is_straight() -> void:
	var c := RoadCurve.new()
	for u in [0.0, 300.0, 999.0]:
		t.near(c.curvature(u), 0.0, 1e-9, "straight at %d m" % u)
		t.near(c.heading(u), 0.0, 1e-9, "heading 0 at %d m" % u)


func test_every_block_bends_gently_and_smoothly() -> void:
	var c := RoadCurve.new()
	for k in range(1, 30):
		var b := c.block(k)
		t.check(absf(float(b["k"])) >= 1.0 / 1300.0 - 1e-9 and absf(float(b["k"])) <= 1.0 / 550.0 + 1e-9,
				"block %d radius within 550-1300 m" % k)
	# no jumps in curvature anywhere (eases in and out)
	var prev := c.curvature(0.0)
	var worst := 0.0
	var u := 0.0
	while u < 30000.0:
		u += 2.0
		var k := c.curvature(u)
		worst = maxf(worst, absf(k - prev))
		prev = k
	t.check(worst < 1e-4, "curvature continuous (largest step per 2 m: %f)" % worst)


func test_heading_is_the_integral_of_curvature() -> void:
	var c := RoadCurve.new()
	var h := 0.0
	var u := 0.0
	while u < 8000.0:
		h += c.curvature(u + 0.5) * 1.0
		u += 1.0
	t.near(c.heading(8000.0), h, 0.002, "closed-form heading matches numeric integral")


func test_bend_table_is_zero_at_the_camera_and_follows_the_turn() -> void:
	var c := RoadCurve.new()
	# find a point in the middle of a curve
	var u := 1000.0
	while absf(c.curvature(u)) < 0.0004:
		u += 10.0
	var tab := c.bend_table(u)
	t.near(RoadCurve.table_at(tab, 0.0), 0.0, 1e-4, "no offset at the camera")
	t.near(RoadCurve.table_slope(tab, 0.0), 0.0, 0.01, "camera faces along the road")
	var ahead := RoadCurve.table_at(tab, 300.0)
	t.check(signf(ahead) == signf(c.curvature(u)) and absf(ahead) > 10.0,
			"road 300 m ahead has swung the way it bends (%f)" % ahead)


func test_tunnels_come_early_and_stay_on_their_block() -> void:
	var c := RoadCurve.new()
	var first: Array = c.tunnels_between(0.0, 5000.0)
	t.check(not first.is_empty() and float(first[0][0]) < 2500.0, "a tunnel within the first 2.5 km")
	for k in range(0, 60):
		var tn: Array = c.block(k)["tunnel"]
		if tn.is_empty():
			continue
		t.check(float(tn[1]) - float(tn[0]) >= 220.0 and float(tn[1]) < (k + 1) * RoadCurve.BLOCK,
				"tunnel %d sized and inside its block" % k)
	var u := float(first[0][0]) + 100.0
	t.near(c.tunnel_depth(u), 1.0, 1e-6, "deep inside the tunnel")
	t.near(c.tunnel_depth(10.0), 0.0, 1e-6, "outside")
