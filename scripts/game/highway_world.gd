class_name HighwayWorld
extends Node3D
## Builds and streams the highway environment around the player.
##
## Long meshes (road, grass, barriers, hills) follow the player and are
## textured in world space, so they look static. Repeating props snap to
## their period. Trees live in recycled chunks seeded by absolute position.
## Everything is shifted back every REBASE metres to keep floats precise.

const REBASE := 1200.0
const LANES := 4
const LANE_W := 3.6
const HALF_ROAD := LANES * LANE_W * 0.5
const BARRIER_X := HALF_ROAD + 1.7
const AHEAD := 650.0
const BEHIND := 120.0
const CHUNK := 100.0
const CHUNKS := 8

var noise_tex: NoiseTexture2D
var sun: DirectionalLight3D
var environment: Environment
var shifted_total := 0.0

var _follow: Array[Node3D] = []
var _snapped: Array = []   # [node, period]
var _chunks: Array[Dictionary] = []
var _tree_meshes: Array[Mesh] = []


func build() -> void:
	noise_tex = NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	noise_tex.generate_mipmaps = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	fn.fractal_octaves = 4
	noise_tex.noise = fn
	_build_environment()
	_build_road()
	_build_terrain()
	_build_barriers()
	_build_poles()
	_build_trees()


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.74)
	sky_mat.sky_horizon_color = Color(0.70, 0.78, 0.86)
	sky_mat.ground_horizon_color = Color(0.70, 0.78, 0.86)
	sky_mat.ground_bottom_color = Color(0.22, 0.24, 0.26)
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.9
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.05
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.68, 0.76, 0.85)
	environment.fog_density = 0.0028
	environment.fog_aerial_perspective = 0.6
	environment.fog_sky_affect = 0.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.3
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.08
	environment.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 150, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.95, 0.87)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_blur = 1.0
	add_child(sun)


func _strip(width: float, x: float, mat: Material) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(width, AHEAD + BEHIND)
	pm.subdivide_depth = 0
	pm.center_offset = Vector3(x, 0, -(AHEAD - BEHIND) * 0.5)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.extra_cull_margin = 50.0
	add_child(mi)
	_follow.append(mi)
	return mi


func _build_road() -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/road.gdshader")
	m.set_shader_parameter("noise_tex", noise_tex)
	m.set_shader_parameter("lane_width", LANE_W)
	m.set_shader_parameter("lanes", LANES)
	var road := _strip(BARRIER_X * 2.0 + 0.6, 0.0, m)
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_terrain() -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/terrain.gdshader")
	m.set_shader_parameter("noise_tex", noise_tex)
	m.set_shader_parameter("verge_from", BARRIER_X + 0.5)
	m.set_shader_parameter("verge_to", BARRIER_X + 2.5)
	var w := 900.0
	for side in [-1.0, 1.0]:
		var t := _strip(w, side * (BARRIER_X + 0.3 + w * 0.5), m)
		t.position.y = -0.03
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Extrudes a 2D (x, y) profile along -Z into a mesh following the player.
func _extrude(profile: PackedVector2Array, x: float, mat: Material, smooth := true) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if smooth:
		st.set_smooth_group(0)
	var z0 := BEHIND
	var z1 := -AHEAD
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
	# Concrete median barrier on the left (fast-lane side).
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.74, 0.73, 0.70)
	var ctex := NoiseTexture2D.new()
	ctex.width = 128
	ctex.height = 128
	ctex.seamless = true
	ctex.noise = noise_tex.noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.82, 0.82, 0.80))
	ramp.set_color(1, Color(1.0, 1.0, 0.98))
	ctex.color_ramp = ramp
	concrete.albedo_texture = ctex
	concrete.uv1_triplanar = true
	concrete.uv1_world_triplanar = true
	concrete.uv1_scale = Vector3(0.25, 0.25, 0.25)
	concrete.roughness = 0.9
	var jersey := PackedVector2Array([
		Vector2(-0.32, 0.0), Vector2(-0.28, 0.08), Vector2(-0.13, 0.33), Vector2(-0.09, 0.86),
		Vector2(0.09, 0.86), Vector2(0.13, 0.33), Vector2(0.28, 0.08), Vector2(0.32, 0.0)])
	# Profile is ordered so the road-facing side gets outward normals.
	var rev := PackedVector2Array()
	for i in range(jersey.size() - 1, -1, -1):
		rev.append(jersey[i])
	_extrude(rev, -BARRIER_X - 0.1, concrete, false)

	# Galvanised W-beam guardrail on the right.
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.60, 0.62, 0.64)
	steel.metallic = 0.85
	steel.roughness = 0.35
	steel.cull_mode = BaseMaterial3D.CULL_DISABLED
	var beam := PackedVector2Array([
		Vector2(0.0, 0.50), Vector2(-0.09, 0.56), Vector2(-0.09, 0.62), Vector2(-0.025, 0.67),
		Vector2(-0.09, 0.72), Vector2(-0.09, 0.78), Vector2(0.0, 0.84)])
	_extrude(beam, BARRIER_X, steel)

	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.12, 0.95, 0.16)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.45, 0.46, 0.48)
	post_mat.metallic = 0.6
	post_mat.roughness = 0.5
	post_mesh.material = post_mat
	var xforms: Array[Transform3D] = []
	var z := BEHIND
	while z > -AHEAD:
		xforms.append(Transform3D(Basis.IDENTITY, Vector3(BARRIER_X + 0.14, 0.47, z)))
		z -= 4.0
	_add_snapped(post_mesh, xforms, 4.0)


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
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.5, 0.52, 0.55)
	metal.metallic = 0.7
	metal.roughness = 0.45
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(0.9, 0.9, 0.85)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.85, 0.6)
	lamp.emission_energy_multiplier = 0.0
	var st := SurfaceTool.new()
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.12
	pole.height = 10.0
	pole.radial_segments = 10
	st.append_from(pole, 0, Transform3D(Basis.IDENTITY, Vector3(0, 5.0, 0)))
	var arm := CylinderMesh.new()
	arm.top_radius = 0.05
	arm.bottom_radius = 0.06
	arm.height = 2.6
	arm.radial_segments = 8
	st.append_from(arm, 0, Transform3D(Basis(Vector3.BACK, deg_to_rad(80)), Vector3(-1.25, 10.1, 0)))
	var mesh := st.commit()
	mesh.surface_set_material(0, metal)
	var head := BoxMesh.new()
	head.size = Vector3(0.8, 0.12, 0.32)
	var st2 := SurfaceTool.new()
	st2.append_from(head, 0, Transform3D(Basis.IDENTITY, Vector3(-2.6, 10.28, 0)))
	st2.commit(mesh)
	mesh.surface_set_material(1, lamp)
	var xforms: Array[Transform3D] = []
	var z := BEHIND
	while z > -AHEAD:
		xforms.append(Transform3D(Basis.IDENTITY, Vector3(BARRIER_X + 1.2, 0, z)))
		z -= 48.0
	_add_snapped(mesh, xforms, 48.0)


func _make_tree_meshes() -> void:
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.25, 0.19, 0.14)
	bark.roughness = 1.0
	var leaves_pine := StandardMaterial3D.new()
	leaves_pine.albedo_color = Color(0.12, 0.20, 0.11)
	leaves_pine.roughness = 1.0
	var leaves_broad := StandardMaterial3D.new()
	leaves_broad.albedo_color = Color(0.20, 0.30, 0.12)
	leaves_broad.roughness = 1.0

	# Conifer: trunk + stacked cones.
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.2
	trunk.height = 3.0
	trunk.radial_segments = 6
	var pine := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0)))
	st.commit(pine)
	pine.surface_set_material(0, bark)
	st = SurfaceTool.new()
	for i in 4:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 2.2 - i * 0.45
		cone.height = 3.2 - i * 0.3
		cone.radial_segments = 9
		cone.rings = 1
		st.append_from(cone, 0, Transform3D(Basis(Vector3.UP, i * 0.7), Vector3(0, 2.6 + i * 1.9, 0)))
	st.commit(pine)
	pine.surface_set_material(1, leaves_pine)
	_tree_meshes.append(pine)

	# Broadleaf: trunk + clustered spheres.
	var broad := ArrayMesh.new()
	st = SurfaceTool.new()
	st.append_from(trunk, 0, Transform3D(Basis.IDENTITY.scaled(Vector3(1.2, 1.3, 1.2)), Vector3(0, 1.95, 0)))
	st.commit(broad)
	broad.surface_set_material(0, bark)
	st = SurfaceTool.new()
	var blobs := [Vector4(0, 5.2, 0, 2.4), Vector4(1.3, 4.5, 0.4, 1.7), Vector4(-1.2, 4.7, -0.3, 1.8),
			Vector4(0.2, 4.4, 1.3, 1.6), Vector4(-0.3, 6.4, -0.4, 1.6)]
	for b in blobs:
		var s := SphereMesh.new()
		s.radius = b.w
		s.height = b.w * 1.8
		s.radial_segments = 10
		s.rings = 6
		st.append_from(s, 0, Transform3D(Basis.IDENTITY, Vector3(b.x, b.y, b.z)))
	st.commit(broad)
	broad.surface_set_material(1, leaves_broad)
	_tree_meshes.append(broad)


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
			mm.instance_count = 22
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			node.add_child(mmi)
			mms.append(mmi)
		var chunk := {"node": node, "index": -999999, "mms": mms}
		_chunks.append(chunk)


## Absolute chunk index -> deterministic tree layout.
func _fill_chunk(chunk: Dictionary, index: int) -> void:
	chunk["index"] = index
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(index * 7919 + 17)
	var node: Node3D = chunk["node"]
	node.position.z = -index * CHUNK - shifted_total
	for mmi in chunk["mms"]:
		var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
		for i in mm.instance_count:
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var dist := 14.0 + pow(rng.randf(), 1.6) * 90.0
			var s := rng.randf_range(0.75, 1.45)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s))
			mm.set_instance_transform(i, Transform3D(b, Vector3(side * (BARRIER_X + dist), 0, -rng.randf() * CHUNK)))


func _build_hills() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.27, 0.22)
	mat.roughness = 1.0
	var fn := FastNoiseLite.new()
	fn.frequency = 0.0022
	fn.fractal_octaves = 3
	fn.seed = 3
	for side in [-1.0, 1.0]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0)
		var xs := [260.0, 420.0, 600.0, 820.0, 1100.0]
		var zs: Array[float] = []
		var z := 400.0
		while z > -1800.0:
			zs.append(z)
			z -= 50.0
		var grid := []
		for zi in zs.size():
			var row := []
			for xi in xs.size():
				var x: float = xs[xi]
				var h := (fn.get_noise_2d(x * side, zs[zi]) * 0.5 + 0.5) * (30.0 + xi * 60.0) + xi * 12.0
				if xi == 0:
					h = 0.0
				row.append(Vector3(side * x, h - 2.0, zs[zi]))
			grid.append(row)
		for zi in zs.size() - 1:
			for xi in xs.size() - 1:
				var a: Vector3 = grid[zi][xi]
				var b: Vector3 = grid[zi][xi + 1]
				var c: Vector3 = grid[zi + 1][xi + 1]
				var d: Vector3 = grid[zi + 1][xi]
				var tri := [a, b, c, a, c, d] if side > 0 else [a, c, b, a, d, c]
				for v in tri:
					st.add_vertex(v)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_follow.append(mi)


func update(player_z: float) -> void:
	for f in _follow:
		f.position.z = player_z
	for s in _snapped:
		var period: float = s[1]
		(s[0] as Node3D).position.z = floorf(player_z / period) * period
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
