class_name HighwayWorld
extends Node3D
## Builds and streams the highway environment around the player.
##
## Long meshes (roads, ground, barriers) follow the player and are textured
## in world space, so they look static. Repeating props snap to their period.
## Trees, gantries and bridges are recycled by absolute position. Everything
## is shifted back every REBASE metres to keep floats precise; every texture
## and prop period divides REBASE.
##
## Layout (x): our 4 lanes centred on 0, concrete median at -BARRIER_X,
## the opposite carriageway centred on OPP_CENTER, guardrails outside.
##
## Bends and tunnels come from RoadCurve. Everything is built straight; long
## meshes bend in their shaders (bend.gdshaderinc), and separate objects
## (signs, bridges, tree stands, cars) are moved onto the curve each frame by
## game.gd using bend_at() / bend_slope(). The sky and sun turn with the road.

const REBASE := 1200.0
const LANES := 4
const LANE_W := 3.6
const HALF_ROAD := LANES * LANE_W * 0.5
const BARRIER_X := HALF_ROAD + 1.7
const OPP_CENTER := -(BARRIER_X * 2.0 + 0.6)
const AHEAD := 650.0
const BEHIND := 120.0
const CHUNK := 100.0
const CHUNKS := 8
const SEG := 10.0          ## length of one mesh segment along the road (bending resolution)
const TUNNEL_H := 6.6      ## tunnel ceiling height

## Where the sun is in the sky photo (from tools/godot/find_sun.gd) and how
## far we turn the sky so the sun lights the traffic ahead from behind-right.
const SKY_SUN_U := 0.595
const SKY_SUN_V := 0.232
const SKY_YAW_DEG := 150.0

## Time-of-day presets. Sun positions come from tools/godot/find_sun.gd.
const ENVS := {
	# Bright morning (playtest: "more light, more morning"): a strong, slightly
	# warm sun, a brighter sky fill and a pale, warm haze.
	"day": {"name": "Daytime", "sky": "res://assets/env/sky.hdr", "u": 0.595, "v": 0.232, "yaw": 150.0,
		"sky_energy": 1.15, "sun_energy": 2.3, "sun_color": Color(1.0, 0.93, 0.82),
		"fog": Color(0.84, 0.86, 0.88), "fog_density": 0.0010, "exposure": 1.18, "ambient": 1.35,
		"trees": Color(0.92, 0.96, 0.86), "lamps": 0.0, "night": false},
	"sunset": {"name": "Golden Hour", "sky": "res://assets/env/sky_sunset.hdr", "u": 0.603, "v": 0.408,
		"yaw": 25.0, "sky_energy": 1.15, "sun_energy": 2.1, "sun_color": Color(1.0, 0.72, 0.42),
		"fog": Color(0.80, 0.70, 0.62), "fog_density": 0.0015, "exposure": 1.05, "ambient": 0.9,
		"trees": Color(0.62, 0.58, 0.5), "lamps": 0.0, "night": false},
	"night": {"name": "Night", "sky": "res://assets/env/sky_night.hdr", "u": 0.599, "v": 0.404,
		"yaw": 110.0, "sky_energy": 0.09, "sun_energy": 0.22, "sun_color": Color(0.62, 0.72, 1.0),
		"fog": Color(0.035, 0.045, 0.07), "fog_density": 0.0045, "exposure": 1.35, "ambient": 1.1,
		"trees": Color(0.07, 0.08, 0.1), "lamps": 1.0, "night": true},
}

const PLACES := ["Northgate", "Riverside", "Lakeview", "Ashford", "Kingsport", "Stonebridge",
		"Eastfield", "Harborview", "Millbrook", "Westcliff", "Oakridge", "Fairhaven"]

var noise_tex: NoiseTexture2D
var sun: DirectionalLight3D
var environment: Environment
var shifted_total := 0.0
var font: Font

var _follow: Array[Node3D] = []
var _snapped: Array = []   # [node, period]
var _chunks: Array[Dictionary] = []
var _tree_meshes: Array[Mesh] = []
var _tree_sizes: Array[float] = []
var _periodic: Array[Dictionary] = []   # {nodes, period, offset, place: Callable}
var _concrete: StandardMaterial3D
var _steel: StandardMaterial3D
var _road_mats: Array[ShaderMaterial] = []
var _lamp_mat: ShaderMaterial
var _refl_mat: ShaderMaterial
var _pole_mats: Array[ShaderMaterial] = []   ## lamp columns: hidden inside tunnels
var _terrain_mat: ShaderMaterial

var curve := RoadCurve.new()
var _bend_mats: Array[ShaderMaterial] = []   ## every material that bends with the road
var _bend_table := PackedFloat32Array()
var _tunnels := {}                           ## tunnel start u -> node
var _tunnel_mats := {}
var _tunnel_parts := {}
## 0 outside, 1 deep inside a tunnel (at the camera): daylight is shut out.
var tunnel_t := 0.0
var _base_sun_basis := Basis.IDENTITY
var _base_sky_yaw := 0.0
var _base_sun_energy := 1.0
var _base_ambient := 1.0
var _sign_mats: Array[StandardMaterial3D] = []
var _tree_mats: Array[StandardMaterial3D] = []
var _sky_mat: PanoramaSkyMaterial
var env_name := "day"
var is_night := false


func build() -> void:
	font = load("res://assets/fonts/BarlowSemiCondensed-Bold.ttf")
	noise_tex = NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	noise_tex.generate_mipmaps = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	fn.fractal_octaves = 4
	noise_tex.noise = fn
	_make_shared_materials()
	_build_environment()
	_build_roads()
	_build_terrain()
	_build_barriers()
	_build_poles()
	_build_trees()
	_build_gantries()
	_build_bridges()
	_make_tunnel_parts()
	apply_env("day")


func _tex(name: String) -> Texture2D:
	return load("res://assets/env/textures/%s.jpg" % name)


func _make_shared_materials() -> void:
	_concrete = StandardMaterial3D.new()
	_concrete.albedo_texture = _tex("concrete_albedo")
	_concrete.normal_enabled = true
	_concrete.normal_texture = _tex("concrete_normal")
	_concrete.albedo_color = Color(0.62, 0.61, 0.59)
	_concrete.uv1_triplanar = true
	_concrete.uv1_world_triplanar = true
	_concrete.uv1_scale = Vector3(0.5, 0.5, 0.5)
	_concrete.roughness = 0.88
	_concrete.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_steel = StandardMaterial3D.new()
	_steel.albedo_color = Color(0.62, 0.64, 0.66)
	_steel.metallic = 0.85
	_steel.roughness = 0.38
	_steel.cull_mode = BaseMaterial3D.CULL_DISABLED


## A material that bends with the road (see shaders/bend_std.gdshader).
func _bend_mat(params: Dictionary, double_sided := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/bend_std_double.gdshader" if double_sided else "res://shaders/bend_std.gdshader")
	for k in params:
		m.set_shader_parameter(k, params[k])
	_bend_mats.append(m)
	return m


func _concrete_bend() -> ShaderMaterial:
	return _bend_mat({"albedo": Color(0.62, 0.61, 0.59), "use_tex": true,
			"albedo_tex": _tex("concrete_albedo"), "tex_scale": 0.5, "roughness_v": 0.88})


func _steel_bend() -> ShaderMaterial:
	return _bend_mat({"albedo": Color(0.62, 0.64, 0.66), "metallic_v": 0.85, "roughness_v": 0.38}, true)


static func sky_dir(u: float, v: float) -> Vector3:
	var phi := u * TAU - PI
	var theta := v * PI
	return Vector3(sin(phi) * sin(theta), cos(theta), -cos(phi) * sin(theta))


func _build_environment() -> void:
	_sky_mat = PanoramaSkyMaterial.new()
	_sky_mat.panorama = load("res://assets/env/sky.hdr")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.sky_rotation = Vector3(0, deg_to_rad(SKY_YAW_DEG), 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.72, 0.78, 0.86)
	environment.fog_density = 0.0016
	environment.fog_aerial_perspective = 0.6  # lighter haze: far traffic stays readable
	environment.fog_sky_affect = 0.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.45
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.4
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.05
	environment.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	# Most of the shadow map goes to the first ~15 m around the player's car,
	# so its shadow has clean edges instead of stair steps.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	sun.directional_shadow_split_1 = 0.25
	sun.directional_shadow_blend_splits = true  # no visible pop at the 15 m seam
	sun.shadow_blur = 1.5
	add_child(sun)


func _strip(width: float, x: float, mat: Material) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(width, AHEAD + BEHIND)
	pm.subdivide_depth = int((AHEAD + BEHIND) / SEG)   # vertices to bend along the road
	pm.center_offset = Vector3(x, 0, -(AHEAD - BEHIND) * 0.5)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.extra_cull_margin = 50.0
	add_child(mi)
	_follow.append(mi)
	return mi


func _road_material(center: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/road.gdshader")
	m.set_shader_parameter("albedo_tex", _tex("asphalt_albedo"))
	m.set_shader_parameter("normal_tex", _tex("asphalt_normal"))
	m.set_shader_parameter("rough_tex", _tex("asphalt_rough"))
	m.set_shader_parameter("noise_tex", noise_tex)
	m.set_shader_parameter("lane_width", LANE_W)
	m.set_shader_parameter("lanes", LANES)
	m.set_shader_parameter("center_x", center)
	m.set_shader_parameter("lamp_x", -BARRIER_X - 0.1 + 2.75)
	m.set_shader_parameter("lamp_x2", -BARRIER_X - 0.1 - 2.75)
	_road_mats.append(m)
	_bend_mats.append(m)
	return m


func _build_roads() -> void:
	var w := BARRIER_X * 2.0 + 0.6
	_strip(w, 0.0, _road_material(0.0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_strip(w, OPP_CENTER, _road_material(OPP_CENTER)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_terrain() -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/terrain.gdshader")
	m.set_shader_parameter("grass_tex", _tex("grass_albedo"))
	m.set_shader_parameter("grass_nrm", _tex("grass_normal"))
	m.set_shader_parameter("gravel_tex", _tex("gravel_albedo"))
	m.set_shader_parameter("gravel_nrm", _tex("gravel_normal"))
	m.set_shader_parameter("noise_tex", noise_tex)
	m.set_shader_parameter("verge_center", 0.0)
	m.set_shader_parameter("verge_in", BARRIER_X + 0.2)
	m.set_shader_parameter("verge_out", BARRIER_X + 1.4)
	m.set_shader_parameter("verge_center2", OPP_CENTER)
	m.set_shader_parameter("verge_in2", BARRIER_X + 0.2)
	m.set_shader_parameter("verge_out2", BARRIER_X + 1.4)
	_bend_mats.append(m)
	_terrain_mat = m
	var w := 900.0
	var right := _strip(w, BARRIER_X + 0.3 + w * 0.5, m)
	var left := _strip(w, OPP_CENTER - BARRIER_X - 0.3 - w * 0.5, m)
	for t in [right, left]:
		t.position.y = -0.03
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Extrudes a 2D (x, y) profile along -Z into a mesh following the player.
func _extrude(profile: PackedVector2Array, x: float, mat: Material, smooth := true) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if smooth:
		st.set_smooth_group(0)
	var segs := int((AHEAD + BEHIND) / SEG)
	for sgi in segs:  # in short segments, so the shader can bend it
		var z0 := BEHIND - sgi * SEG
		var z1 := z0 - SEG
		for i in profile.size() - 1:
			var a := profile[i]
			var b := profile[i + 1]
			var v0 := Vector3(x + a.x, a.y, z0)
			var v1 := Vector3(x + b.x, b.y, z0)
			var v2 := Vector3(x + b.x, b.y, z1)
			var v3 := Vector3(x + a.x, a.y, z1)
			for v in [v0, v1, v2, v0, v2, v3]:
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.extra_cull_margin = 50.0
	add_child(mi)
	_follow.append(mi)
	return mi


func _build_barriers() -> void:
	# Concrete median barrier between the carriageways.
	var jersey := PackedVector2Array([
		Vector2(0.32, 0.0), Vector2(0.28, 0.08), Vector2(0.13, 0.33), Vector2(0.09, 0.86),
		Vector2(-0.09, 0.86), Vector2(-0.13, 0.33), Vector2(-0.28, 0.08), Vector2(-0.32, 0.0)])
	_extrude(jersey, -BARRIER_X - 0.1, _concrete_bend(), false)

	# Galvanised W-beam guardrails on both outer edges.
	var beam := PackedVector2Array([
		Vector2(0.0, 0.50), Vector2(-0.09, 0.56), Vector2(-0.09, 0.62), Vector2(-0.025, 0.67),
		Vector2(-0.09, 0.72), Vector2(-0.09, 0.78), Vector2(0.0, 0.84)])
	var steel := _steel_bend()
	_extrude(beam, BARRIER_X, steel)
	var beam_l := PackedVector2Array()
	for p in beam:
		beam_l.append(Vector2(-p.x, p.y))
	_extrude(beam_l, OPP_CENTER - BARRIER_X, steel)

	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.12, 0.95, 0.16)
	post_mesh.material = _bend_mat({"albedo": Color(0.45, 0.46, 0.48), "metallic_v": 0.6, "roughness_v": 0.5})
	var xforms: Array[Transform3D] = []
	var z := BEHIND
	while z > -AHEAD:
		xforms.append(Transform3D(Basis.IDENTITY, Vector3(BARRIER_X + 0.14, 0.47, z)))
		xforms.append(Transform3D(Basis.IDENTITY, Vector3(OPP_CENTER - BARRIER_X - 0.14, 0.47, z)))
		z -= 4.0
	_add_snapped(post_mesh, xforms, 4.0)
	# Reflectors on every 12th post (white on the right, like real motorways).
	var refl := BoxMesh.new()
	refl.size = Vector3(0.03, 0.09, 0.07)
	_refl_mat = _bend_mat({"albedo": Color(1, 1, 1), "emission_color": Color(1, 1, 1), "emission_energy": 0.4})
	refl.material = _refl_mat
	var rx: Array[Transform3D] = []
	z = BEHIND
	while z > -AHEAD:
		rx.append(Transform3D(Basis.IDENTITY, Vector3(BARRIER_X - 0.11, 0.68, z)))
		z -= 48.0
	_add_snapped(refl, rx, 48.0, false)


func _add_snapped(mesh: Mesh, xforms: Array[Transform3D], period: float,
		shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.extra_cull_margin = 50.0
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_snapped.append([mmi, period])
	return mmi


func _build_poles() -> void:
	# Double-armed lighting columns on the central reserve.
	var metal := _bend_mat({"albedo": Color(0.55, 0.57, 0.6), "metallic_v": 0.75, "roughness_v": 0.4})
	var lamp := _bend_mat({"albedo": Color(0.85, 0.85, 0.8), "roughness_v": 0.3,
			"emission_color": Color(1.0, 0.8, 0.5), "emission_energy": 0.0})
	_lamp_mat = lamp
	_pole_mats = [metal, lamp]
	var st := SurfaceTool.new()
	var pole := CylinderMesh.new()
	pole.top_radius = 0.08
	pole.bottom_radius = 0.14
	pole.height = 11.0
	pole.radial_segments = 10
	st.append_from(pole, 0, Transform3D(Basis.IDENTITY, Vector3(0, 6.3, 0)))
	var base := CylinderMesh.new()
	base.top_radius = 0.2
	base.bottom_radius = 0.22
	base.height = 0.9
	st.append_from(base, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0)))
	for side in [-1.0, 1.0]:
		var arm := CylinderMesh.new()
		arm.top_radius = 0.05
		arm.bottom_radius = 0.065
		arm.height = 2.8
		arm.radial_segments = 8
		st.append_from(arm, 0, Transform3D(Basis(Vector3.BACK, -side * deg_to_rad(78)),
				Vector3(side * 1.35, 11.6, 0)))
	var mesh := st.commit()
	mesh.surface_set_material(0, metal)
	var st2 := SurfaceTool.new()
	for side in [-1.0, 1.0]:
		var head := BoxMesh.new()
		head.size = Vector3(0.75, 0.13, 0.3)
		st2.append_from(head, 0, Transform3D(Basis.IDENTITY, Vector3(side * 2.75, 11.85, 0)))
	st2.commit(mesh)
	mesh.surface_set_material(1, lamp)
	var xforms: Array[Transform3D] = []
	var z := BEHIND
	while z > -AHEAD:
		xforms.append(Transform3D(Basis.IDENTITY, Vector3(-BARRIER_X - 0.1, 0.86, z)))
		z -= 60.0
	_add_snapped(mesh, xforms, 60.0)


# ------------------------------------------------------------------ trees

## Impostors baked by tools/blender/bake_impostors.py from CC0 Poly Haven trees.
func _make_tree_meshes() -> void:
	var dir := DirAccess.open("res://assets/env/trees")
	var names: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".json"):
			names.append(f.get_basename())
	names.sort()
	for n in names:
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/env/trees/%s.json" % n))
		var h := float(meta["height"])
		var w := float(meta["width"])
		for view in ["a", "b"]:
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = load("res://assets/env/trees/%s_%s.png" % [n, view])
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.alpha_scissor_threshold = 0.42
			mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			mat.billboard_keep_scale = true
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(0.82, 0.86, 0.8)
			_tree_mats.append(mat)
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			var q := QuadMesh.new()
			q.size = Vector2(w, h)
			q.center_offset = Vector3(0, h * 0.5, 0)
			q.material = mat
			_tree_meshes.append(q)
			_tree_sizes.append(h)


func _build_trees() -> void:
	_make_tree_meshes()
	for i in CHUNKS:
		var node := Node3D.new()
		add_child(node)
		var mms: Array[MultiMeshInstance3D] = []
		for mesh in _tree_meshes:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = 26
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.extra_cull_margin = 20.0
			# Billboards turn with the camera, so their shadows would swim.
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mmi)
			mms.append(mmi)
		_chunks.append({"node": node, "index": -999999, "mms": mms})


## Absolute chunk index -> deterministic forest layout. Trees cluster in
## stands with a ragged tree line, the way verges are actually planted.
func _fill_chunk(chunk: Dictionary, index: int) -> void:
	chunk["index"] = index
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(index * 7919 + 17)
	var node: Node3D = chunk["node"]
	# The node sits at the chunk's middle, so turning it onto a bend moves
	# its trees at most half a chunk off the curve.
	node.position.z = -(index + 0.5) * CHUNK - shifted_total
	var tunnels := curve.tunnels_between(index * CHUNK - 60.0, (index + 1) * CHUNK + 60.0)
	var right_edge := BARRIER_X + 7.0 + rng.randf() * 6.0
	var left_edge := -OPP_CENTER + BARRIER_X + 6.0 + rng.randf() * 6.0
	var mms: Array = chunk["mms"]
	for ti in mms.size():
		var mm: MultiMesh = (mms[ti] as MultiMeshInstance3D).multimesh
		var tall := _tree_sizes[ti] > 5.0  # firs are tall, the broadleaf is short
		for i in mm.instance_count:
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var edge := right_edge if side > 0 else left_edge
			var dist := edge + pow(rng.randf(), 1.8) * 110.0
			var s := rng.randf_range(1.2, 2.0) if tall else rng.randf_range(2.0, 3.2)
			var b := Basis.IDENTITY.scaled(Vector3(s * rng.randf_range(0.85, 1.15), s, s))
			var x := dist if side > 0 else -dist
			var z := (0.5 - rng.randf()) * CHUNK
			var u := (index + 0.5) * CHUNK - z
			for tn in tunnels:  # the tunnel's hill stands here: no trees through it
				if u > float(tn[0]) - 60.0 and u < float(tn[1]) + 60.0:
					b = Basis.IDENTITY.scaled(Vector3.ONE * 0.001)
			mm.set_instance_transform(i, Transform3D(b, Vector3(x, -0.1, z)))


# ------------------------------------------------------------------ gantries / bridges

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _label(parent: Node3D, text: String, pos: Vector3, size: int, color := Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = 0.0075
	l.modulate = color
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.position = pos
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.width = 900.0
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	parent.add_child(l)
	return l


func _make_gantry() -> Node3D:
	var g := Node3D.new()
	add_child(g)
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.0, 0.32, 0.17)
	green.roughness = 0.45
	green.emission_enabled = true
	green.emission = Color(0.0, 0.32, 0.17)
	green.emission_energy_multiplier = 0.0
	_sign_mats.append(green)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.92, 0.9)
	var x0 := -BARRIER_X - 0.1
	var x1 := BARRIER_X + 1.2
	var span := x1 - x0
	var cx := (x0 + x1) * 0.5
	for x in [x0, x1]:
		_box(g, Vector3(0.45, 7.8, 0.45), Vector3(x, 3.9, 0), _steel)
	for y in [6.7, 7.6]:
		for z in [-0.35, 0.35]:
			_box(g, Vector3(span, 0.14, 0.14), Vector3(cx, y, z), _steel)
	var x := x0 + 0.6
	while x < x1 - 0.3:
		_box(g, Vector3(0.08, 0.9, 0.08), Vector3(x, 7.15, 0.35), _steel)
		_box(g, Vector3(0.08, 0.9, 0.08), Vector3(x, 7.15, -0.35), _steel)
		x += 1.2
	# Two direction signs over the lanes.
	var signs := [[-3.9, 6.6], [3.0, 6.2]]
	for s in signs:
		_box(g, Vector3(s[1] + 0.16, 2.56, 0.08), Vector3(s[0], 8.25, 0.42), white)
		_box(g, Vector3(s[1], 2.4, 0.1), Vector3(s[0], 8.25, 0.44), green)
	g.set_meta("labels", [
		_label(g, "", Vector3(-3.9 - 2.9, 8.25, 0.5), 96),
		_label(g, "", Vector3(3.0 - 2.75, 8.25, 0.5), 96)])
	return g


func _place_gantry(g: Node3D, index: int) -> void:
	var labels: Array = g.get_meta("labels")
	var a: String = PLACES[posmod(index * 3, PLACES.size())]
	var b: String = PLACES[posmod(index * 3 + 1, PLACES.size())]
	var c: String = PLACES[posmod(index * 3 + 2, PLACES.size())]
	var km := 8 + posmod(index * 7, 60)
	(labels[0] as Label3D).text = "%s   %d\n%s   %d" % [a, km, b, km + 23 + posmod(index, 9)]
	(labels[1] as Label3D).text = "EXIT %d\n%s" % [10 + posmod(index, 80), c]


func _build_gantries() -> void:
	var nodes: Array[Node3D] = [_make_gantry(), _make_gantry()]
	_periodic.append({"nodes": nodes, "period": 600.0, "offset": 150.0, "place": _place_gantry})


func _make_bridge() -> Node3D:
	var g := Node3D.new()
	add_child(g)
	var left := OPP_CENTER - BARRIER_X - 6.0
	var right := BARRIER_X + 6.0
	var cx := (left + right) * 0.5
	var span := right - left
	_box(g, Vector3(span, 1.3, 13.0), Vector3(cx, 6.45, 0), _concrete)
	for z in [-6.3, 6.3]:
		_box(g, Vector3(span, 1.1, 0.35), Vector3(cx, 7.65, z), _concrete)
	for z in [-3.8, 0.0, 3.8]:
		for x in [BARRIER_X + 2.4, -BARRIER_X - 0.1, OPP_CENTER - BARRIER_X - 2.4]:
			_box(g, Vector3(1.0, 5.8, 1.0), Vector3(x, 2.9, z), _concrete)
	# Abutment walls at both ends hide the deck ends.
	for x in [left, right]:
		_box(g, Vector3(1.5, 7.2, 14.0), Vector3(x, 3.6, 0), _concrete)
	return g


func _build_bridges() -> void:
	var nodes: Array[Node3D] = [_make_bridge(), _make_bridge()]
	_periodic.append({"nodes": nodes, "period": 1200.0, "offset": 450.0, "place": Callable()})


func _update_periodic(player_z: float) -> void:
	for p in _periodic:
		var period: float = p["period"]
		var offset: float = p["offset"]
		var nodes: Array = p["nodes"]
		# absolute z of index k is -(k * period + offset)
		var abs_far := player_z + shifted_total - AHEAD
		var abs_near := player_z + shifted_total + BEHIND
		var k0 := int(ceil((-abs_near - offset) / period))
		var k1 := int(floor((-abs_far - offset) / period))
		var used := 0
		for k in range(k0, k1 + 1):
			if used >= nodes.size():
				break
			var n: Node3D = nodes[used]
			used += 1
			var u := k * period + offset
			n.visible = curve.tunnels_between(u - 30.0, u + 30.0).is_empty()  # never inside a tunnel
			n.position.z = -u - shifted_total
			if n.get_meta("index", -1) != k:
				n.set_meta("index", k)
				var place: Callable = p["place"]
				if place.is_valid():
					place.call(n, k)
		for i in range(used, nodes.size()):
			(nodes[i] as Node3D).visible = false


## Switches time of day: sky, sun, fog, exposure, lamps and tree shading.
func apply_env(name: String) -> void:
	if not ENVS.has(name):
		name = "day"
	env_name = name
	var e: Dictionary = ENVS[name]
	is_night = e["night"]
	_sky_mat.panorama = load(e["sky"])
	_sky_mat.energy_multiplier = e["sky_energy"]
	environment.sky_rotation = Vector3(0, deg_to_rad(e["yaw"]), 0)
	environment.fog_light_color = e["fog"]
	environment.fog_density = e["fog_density"]
	environment.tonemap_exposure = e["exposure"]
	environment.ambient_light_energy = e["ambient"]
	environment.glow_hdr_threshold = 0.9 if is_night else 1.4
	environment.glow_intensity = 0.8 if is_night else 0.45
	var to_sun := Basis.from_euler(environment.sky_rotation) * sky_dir(e["u"], e["v"])
	sun.look_at_from_position(Vector3.ZERO, -to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.BACK)
	sun.light_energy = e["sun_energy"]
	sun.light_color = e["sun_color"]
	_base_sun_basis = sun.basis
	_base_sky_yaw = environment.sky_rotation.y
	_base_sun_energy = sun.light_energy
	_base_ambient = environment.ambient_light_energy
	for m in _road_mats:
		m.set_shader_parameter("lamps", e["lamps"])
	_lamp_mat.set_shader_parameter("emission_energy", 6.0 if is_night else 0.0)
	_refl_mat.set_shader_parameter("emission_energy", 3.0 if is_night else 0.4)
	for m in _sign_mats:
		m.emission_energy_multiplier = 0.6 if is_night else 0.0
	for m in _tree_mats:
		m.albedo_color = e["trees"]


func set_two_way(on: bool) -> void:
	_road_mats[0].set_shader_parameter("two_way", on)


## Low quality: no sun shadows and a thinner forest, for older phones.
func set_quality(high: bool) -> void:
	sun.shadow_enabled = high
	for c in _chunks:
		for mmi in c["mms"]:
			(mmi as MultiMeshInstance3D).multimesh.visible_instance_count = -1 if high else 12


func update(player_z: float) -> void:
	for f in _follow:
		f.position.z = player_z
	for s in _snapped:
		var period: float = s[1]
		(s[0] as Node3D).position.z = floorf(player_z / period) * period
	_update_periodic(player_z)
	_update_tunnels(player_z)
	# Recycle tree chunks to cover [player - AHEAD, player + BEHIND].
	var abs_z := player_z + shifted_total
	var first := int(floor(-(abs_z + BEHIND) / CHUNK))
	var wanted := {}
	for i in CHUNKS:
		wanted[first + i] = true
	var free: Array[Dictionary] = []
	for c in _chunks:
		if wanted.has(c["index"]):
			wanted.erase(c["index"])
		else:
			free.append(c)
	for idx in wanted.keys():
		if free.is_empty():
			break
		_fill_chunk(free.pop_back(), idx)


## Shifts everything by +dz when the player has travelled far.
func rebase(dz: float) -> void:
	shifted_total -= dz
	for c in _chunks:
		(c["node"] as Node3D).position.z += dz
	for k in _tunnels:
		(_tunnels[k] as Node3D).position.z += dz


## Absolute distance along the road of a world z.
func u_of(z: float) -> float:
	return -(z + shifted_total)


## Called once a frame after the camera has moved: bends every bending
## material around the camera, turns sky and sun with the road, and dims the
## daylight inside tunnels.
func update_curve(cam_z: float) -> void:
	var u_cam := u_of(cam_z)
	_bend_table = curve.bend_table(u_cam)
	var tz := Vector4(-1e9, 1e9, -1e9, 1e9)
	var tl := curve.tunnels_between(u_cam - BEHIND - 200.0, u_cam + AHEAD + 200.0)
	for i in mini(tl.size(), 2):
		tz[i * 2] = -float(tl[i][0]) - shifted_total
		tz[i * 2 + 1] = -float(tl[i][1]) - shifted_total
	for m in _bend_mats:
		m.set_shader_parameter("bend", _bend_table)
		m.set_shader_parameter("bend_cam_z", cam_z)
	for m in _road_mats:
		m.set_shader_parameter("tunnels", tz)
	var hide := Vector4(tz.x + 15.0, tz.y - 15.0, tz.z + 15.0, tz.w - 15.0)
	for m in _pole_mats:
		m.set_shader_parameter("hide", hide)
	# Turning right swings the sky (and the sun) to the left.
	var h := curve.heading(u_cam)
	environment.sky_rotation = Vector3(0, _base_sky_yaw + h, 0)
	sun.basis = Basis(Vector3.UP, h) * _base_sun_basis
	tunnel_t = curve.tunnel_depth(u_cam)
	sun.light_energy = _base_sun_energy * (1.0 - 0.85 * tunnel_t)
	environment.ambient_light_energy = _base_ambient * (1.0 - 0.65 * tunnel_t)


## Sideways offset of the road d metres ahead of the camera (see RoadCurve).
func bend_at(d: float) -> float:
	return 0.0 if _bend_table.is_empty() else RoadCurve.table_at(_bend_table, d)


func bend_slope(d: float) -> float:
	return 0.0 if _bend_table.is_empty() else RoadCurve.table_slope(_bend_table, d)


## Separate objects that game.gd turns onto the curve each frame.
func rigid_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c in _chunks:
		out.append(c["node"])
	for p in _periodic:
		for n in p["nodes"]:
			if (n as Node3D).visible:
				out.append(n)
	return out


# ------------------------------------------------------------------ tunnels

func _update_tunnels(player_z: float) -> void:
	var u := u_of(player_z)
	var want := {}
	for t in curve.tunnels_between(u - BEHIND - 150.0, u + AHEAD + 150.0):
		want[float(t[0])] = t
	for k in _tunnels.keys():
		if not want.has(k):
			(_tunnels[k] as Node).queue_free()
			_tunnels.erase(k)
	for k in want:
		if not _tunnels.has(k):
			var node := _build_tunnel(float(want[k][1]) - float(want[k][0]))
			node.position.z = -float(k) - shifted_total
			_tunnels[k] = node


func _tunnel_materials() -> Dictionary:
	if _tunnel_mats.is_empty():
		_tunnel_mats = {
			"wall": _bend_mat({"albedo": Color(0.42, 0.42, 0.4), "use_tex": true,
					"albedo_tex": _tex("concrete_albedo"), "tex_scale": 0.35, "roughness_v": 0.7,
					"emission_color": Color(1.0, 0.85, 0.65), "emission_energy": 0.06}),
			"band": _bend_mat({"albedo": Color(0.85, 0.6, 0.1), "roughness_v": 0.5,
					"emission_color": Color(0.85, 0.6, 0.1), "emission_energy": 0.15}),
			"ceiling": _bend_mat({"albedo": Color(0.08, 0.08, 0.085), "roughness_v": 0.9}),
			"lamp": _bend_mat({"albedo": Color(1.0, 0.9, 0.75), "emission_color": Color(1.0, 0.84, 0.6),
					"emission_energy": 5.0, "dash_period": 6.0, "dash_fill": 0.55}),
			"portal": _concrete_bend(),
			"rock": _bend_mat({"albedo": Color(0.5, 0.45, 0.39), "use_tex": true,
					"albedo_tex": _tex("concrete_albedo"), "tex_scale": 0.12, "roughness_v": 0.95}),
		}
		var hill := _terrain_mat.duplicate() as ShaderMaterial
		hill.set_shader_parameter("verge_in", -100.0)   # all grass, no gravel verge
		hill.set_shader_parameter("verge_out", -90.0)
		hill.set_shader_parameter("verge_in2", -1.0)
		_bend_mats.append(hill)
		_tunnel_mats["hill"] = hill
	return _tunnel_mats


## Adds a box from (x0, y0, 0) to (x1, y1, -length), cut into SEG pieces
## along z so it bends with the road. `caps`: close the two ends.
static func _long_box(st: SurfaceTool, x0: float, x1: float, y0: float, y1: float, length: float,
		caps := true) -> void:
	var segs := maxi(1, int(ceil(length / SEG)))
	for i in segs:
		var za := -i * length / segs
		var zb := -(i + 1) * length / segs
		var c := [Vector3(x0, y0, za), Vector3(x1, y0, za), Vector3(x1, y1, za), Vector3(x0, y1, za),
				Vector3(x0, y0, zb), Vector3(x1, y0, zb), Vector3(x1, y1, zb), Vector3(x0, y1, zb)]
		# top, bottom, left (-x), right (+x), counter-clockwise seen from outside
		var faces := [[3, 2, 6, 7], [0, 4, 5, 1], [0, 3, 7, 4], [1, 5, 6, 2]]
		if caps and i == 0:
			faces.append([0, 1, 2, 3])   # near end (+z)
		if caps and i == segs - 1:
			faces.append([5, 4, 7, 6])   # far end (-z)
		for f in faces:
			for q in [0, 2, 1, 0, 3, 2]:
				st.add_vertex(c[f[q]])


static func _commit(build: Callable) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	build.call(st)
	st.generate_normals()
	return st.commit()


## The ridge over a tunnel: height of the hill dx metres from its crest line.
func _hill_y(dx: float) -> float:
	return (TUNNEL_H + 9.0) * pow(1.0 - smoothstep(18.0, 160.0, absf(dx)), 1.3) + 0.4


## Tunnel pieces, built once when the world is built: 10 m slices (walls,
## kerbs, ceiling, lamp rows, hill) that a tunnel repeats as instances, and
## the end pieces. Placing a tunnel then costs next to nothing, so there is
## no hitch on a slow phone when one comes into view.
## name -> [mesh, material, casts shadows, kind: "slice" | "portal" | "near" | "far"]
func _make_tunnel_parts() -> void:
	var mats := _tunnel_materials()
	var h := TUNNEL_H
	var out_r := BARRIER_X + 0.9                  # outer wall of our tube
	var out_l := OPP_CENTER - BARRIER_X - 0.9     # outer wall of the other tube
	var mid0 := -BARRIER_X - 0.5                  # central wall between the tubes
	var mid1 := -BARRIER_X + 0.3
	_tunnel_parts["wall"] = [_commit(func(st: SurfaceTool) -> void:
		_long_box(st, out_r, out_r + 0.8, 0.0, h, SEG, false)
		_long_box(st, out_l - 0.8, out_l, 0.0, h, SEG, false)
		_long_box(st, mid0, mid1, 0.0, h, SEG, false)), mats["wall"], true, "slice"]
	_tunnel_parts["band"] = [_commit(func(st: SurfaceTool) -> void:  # yellow kerb at the foot of each wall
		_long_box(st, out_r - 0.05, out_r, 0.0, 0.5, SEG, false)
		_long_box(st, out_l, out_l + 0.05, 0.0, 0.5, SEG, false)
		_long_box(st, mid0 - 0.05, mid0, 0.0, 0.5, SEG, false)
		_long_box(st, mid1, mid1 + 0.05, 0.0, 0.5, SEG, false)), mats["band"], false, "slice"]
	_tunnel_parts["ceiling"] = [_commit(func(st: SurfaceTool) -> void:
		_long_box(st, out_l - 0.8, out_r + 0.8, h, h + 0.7, SEG, false)), mats["ceiling"], true, "slice"]
	_tunnel_parts["lamp"] = [_commit(func(st: SurfaceTool) -> void:  # lamp rows near the top of every wall
		for x in [out_r - 0.12, mid1 + 0.04, mid0 - 0.12, out_l + 0.04]:
			_long_box(st, x, x + 0.08, h - 0.7, h - 0.5, SEG, false)), mats["lamp"], false, "slice"]
	var cx := (out_l + out_r) * 0.5
	var xs: Array[float] = []
	var xx := -160.0
	while xx <= 160.0:
		xs.append(xx)
		xx += 10.0
	_tunnel_parts["hill"] = [_commit(func(st: SurfaceTool) -> void:
		for j in xs.size() - 1:
			var a := Vector3(cx + xs[j], _hill_y(xs[j]), 0.0)
			var b := Vector3(cx + xs[j + 1], _hill_y(xs[j + 1]), 0.0)
			var c := Vector3(cx + xs[j + 1], _hill_y(xs[j + 1]), -SEG)
			var d := Vector3(cx + xs[j], _hill_y(xs[j]), -SEG)
			for v in [a, c, b, a, d, c]:
				st.add_vertex(v)), mats["hill"], true, "slice"]
	# Portal: a concrete face around both tube mouths, 1.2 m deep, centred on the mouth.
	_tunnel_parts["portal"] = [_commit(func(st: SurfaceTool) -> void:
		var w0 := out_l - 16.0
		var w1 := out_r + 16.0
		_long_box(st, w0, w1, h, h + 4.5, 1.2)        # lintel over both tubes
		_long_box(st, w0, out_l - 0.8, 0.0, h, 1.2)   # side walls
		_long_box(st, out_r + 0.8, w1, 0.0, h, 1.2)), mats["portal"], true, "portal"]
	# Cut rock faces where the road goes into the hill, open over the tubes.
	for end in ["near", "far"]:
		_tunnel_parts["rock_" + end] = [_commit(func(st: SurfaceTool) -> void:
			for j in xs.size() - 1:
				var xa := cx + xs[j]
				var xb := cx + xs[j + 1]
				var y0 := h + 4.5 if (xb > out_l - 0.8 and xa < out_r + 0.8) else 0.0
				var q := [Vector3(xa, y0, 0.0), Vector3(xb, y0, 0.0),
						Vector3(xb, maxf(_hill_y(xs[j + 1]), y0), 0.0), Vector3(xa, maxf(_hill_y(xs[j]), y0), 0.0)]
				var order := [0, 2, 1, 0, 3, 2] if end == "near" else [0, 1, 2, 0, 2, 3]  # facing out of the hill
				for o in order:
					st.add_vertex(q[o])), mats["rock"], true, end]


## A twin-tube tunnel through a grassy hill: one tube per carriageway, lamp
## rows along the walls, concrete portals at both ends. Straight from z = 0
## to z = -length (a multiple of SEG); it bends with the road in its shaders.
func _build_tunnel(length: float) -> Node3D:
	if _tunnel_parts.is_empty():
		_make_tunnel_parts()
	var node := Node3D.new()
	add_child(node)
	var segs := maxi(1, int(round(length / SEG)))
	length = segs * SEG
	for key in _tunnel_parts:
		var part: Array = _tunnel_parts[key]
		var gi: GeometryInstance3D
		match part[3]:
			"slice":
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = part[0]
				mm.instance_count = segs
				for i in segs:
					mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0, 0, -i * SEG)))
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				gi = mmi
			_:
				for z in ([0.0, -length] if part[3] == "portal" else [0.0 if part[3] == "near" else -length]):
					var mi := MeshInstance3D.new()
					mi.mesh = part[0]
					mi.position.z = z + (0.6 if part[3] == "portal" else 0.0)
					mi.material_override = part[1]
					mi.extra_cull_margin = 120.0
					if not part[2]:
						mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					node.add_child(mi)
				continue
		gi.material_override = part[1]
		gi.extra_cull_margin = 120.0   # it is drawn bent, up to ~100 m off its straight box
		if not part[2]:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(gi)
	return node
