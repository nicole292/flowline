class_name RoadCurve
extends RefCounted
## Where the highway bends and where it goes through tunnels, as a function
## of absolute distance u (metres along the road). Pure logic, deterministic.
##
## The road is planned in blocks of BLOCK metres: a straight, then a curve
## whose curvature eases in and out (sin² profile, so there is never a kink),
## then a short straight (radius 550-1300 m). The first block is straight. Some blocks start
## with a tunnel.
##
## The driving simulation stays straight; the curve is only drawn. Each frame
## bend_table() gives, for points d metres ahead of (or behind) the camera,
## how far sideways the road has moved off the camera's straight line. Road,
## barriers and tunnels are bent in their shaders; cars, signs and trees are
## moved and turned onto the curve (game.gd _bend_scene).

const BLOCK := 1000.0
## The bend table: TABLE_N values every TABLE_STEP metres from TABLE_D0.
## Must match shaders/bend.gdshaderinc.
const TABLE_D0 := -160.0
const TABLE_STEP := 20.0
const TABLE_N := 44
const _H := 5.0                 ## integration step (m)

var seed := 7
## Test harness: start this many metres into the plan (game --road-at=M).
var offset := 0.0
var _blocks := {}               ## block index -> params
var _cum: PackedFloat64Array = [0.0, 0.0]   ## heading at the start of block k


## {straight, curve_len, k (peak curvature 1/m, signed), tunnel: [u0, u1] or []}
func block(k: int) -> Dictionary:
	if _blocks.has(k):
		return _blocks[k]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k * 7919 + seed * 104729)
	var b := {"straight": rng.randf_range(250.0, 450.0), "k": 0.0, "curve_len": 0.0, "tunnel": []}
	if k >= 1:
		b["curve_len"] = BLOCK - b["straight"] - 50.0
		var radius := rng.randf_range(550.0, 1300.0)
		b["k"] = (1.0 if rng.randf() < 0.5 else -1.0) / radius
	# Block 2 always has a tunnel (so a run soon reaches one), then about one
	# block in three.
	if k == 2 or (k >= 3 and rng.randf() < 0.34):
		var u0 := k * BLOCK + 40.0
		b["tunnel"] = [u0, u0 + snappedf(rng.randf_range(220.0, 420.0), 10.0)]  # whole 10 m slices
	_blocks[k] = b
	return b


## Curvature at u (1/m): positive bends right (towards +x ahead).
func curvature(u: float) -> float:
	u += offset
	var k := floori(u / BLOCK)
	if k < 1:
		return 0.0
	var b := block(k)
	var x := (u - k * BLOCK - float(b["straight"])) / float(b["curve_len"])
	if x <= 0.0 or x >= 1.0:
		return 0.0
	return float(b["k"]) * pow(sin(PI * x), 2.0)


## Road heading at u (radians, positive = turned right since the start).
func heading(u: float) -> float:
	u += offset
	var k := floori(u / BLOCK)
	if k < 1:
		return 0.0
	while _cum.size() <= k:
		var j := _cum.size() - 1  # heading at the start of block j+1 = start of j + all of j
		var bj := block(j)
		_cum.append(_cum[j] + float(bj["k"]) * float(bj["curve_len"]) * 0.5)
	var b := block(k)
	var x := clampf((u - k * BLOCK - float(b["straight"])) / maxf(float(b["curve_len"]), 1.0), 0.0, 1.0)
	# integral of sin²(pi x) from 0 to x = x/2 - sin(2 pi x) / (4 pi)
	var part := float(b["k"]) * float(b["curve_len"]) * (x * 0.5 - sin(TAU * x) / (4.0 * PI))
	return _cum[k] + part


## Sideways offset of the road d metres from u_cam, relative to the straight
## line the camera faces (the road's direction at the camera), for
## d = TABLE_D0 + i * TABLE_STEP.
func bend_table(u_cam: float) -> PackedFloat32Array:
	var h0 := heading(u_cam)
	var per := int(TABLE_STEP / _H)
	var i0 := int(-TABLE_D0 / _H)                 # fine-grid index of d = 0
	var n := (TABLE_N - 1) * per + 1
	var fine := PackedFloat32Array()
	fine.resize(n)
	fine[i0] = 0.0
	var prev := 0.0
	for i in range(i0 + 1, n):   # ahead
		var s := sin(heading(u_cam + TABLE_D0 + i * _H) - h0)
		fine[i] = fine[i - 1] + (prev + s) * 0.5 * _H
		prev = s
	prev = 0.0
	for i in range(i0 - 1, -1, -1):   # behind
		var s := sin(heading(u_cam + TABLE_D0 + i * _H) - h0)
		fine[i] = fine[i + 1] - (prev + s) * 0.5 * _H
		prev = s
	var out := PackedFloat32Array()
	out.resize(TABLE_N)
	for i in TABLE_N:
		out[i] = fine[i * per]
	return out


## Linear lookup in a bend table (same as the shaders).
static func table_at(table: PackedFloat32Array, d: float) -> float:
	var f := clampf((d - TABLE_D0) / TABLE_STEP, 0.0, TABLE_N - 1.001)
	var i := int(f)
	return lerpf(table[i], table[i + 1], f - i)


## Slope of the bent road (sideways metres per metre ahead) at distance d.
static func table_slope(table: PackedFloat32Array, d: float) -> float:
	return (table_at(table, d + 2.0) - table_at(table, d - 2.0)) * 0.25


## Tunnels [u0, u1] that overlap [a, b].
func tunnels_between(a: float, b: float) -> Array:
	var out := []
	a += offset
	b += offset
	for k in range(floori(a / BLOCK) - 1, floori(b / BLOCK) + 1):
		var t: Array = block(k)["tunnel"]
		if not t.is_empty() and t[1] >= a and t[0] <= b:
			out.append([float(t[0]) - offset, float(t[1]) - offset])
	return out


## 0 outside tunnels, 1 well inside (ramps over `fade` metres at the portals).
func tunnel_depth(u: float, fade := 40.0) -> float:
	for t in tunnels_between(u - 1.0, u + 1.0):
		return clampf(minf(u - float(t[0]), float(t[1]) - u) / fade, 0.0, 1.0)
	return 0.0
