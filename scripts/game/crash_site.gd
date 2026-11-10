class_name CrashSite
extends Node3D
## Dressing for a wreck stopped on the road: a warning triangle and cones
## behind it, glass and debris on the tarmac and a column of smoke you can
## spot from a long way off. Placed at the wreck; +z is towards the player.

static var _mats := {}


static func _mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"red":
			m.albedo_color = Color(0.9, 0.08, 0.05)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.1, 0.05)
			m.emission_energy_multiplier = 0.8
			m.roughness = 0.3
		"cone":
			m.albedo_color = Color(1.0, 0.35, 0.05)
			m.roughness = 0.5
		"stripe":
			m.albedo_color = Color(0.95, 0.95, 0.95)
			m.roughness = 0.4
		"debris":
			m.albedo_color = Color(0.08, 0.08, 0.09)
			m.roughness = 0.8
		"glass":
			m.albedo_color = Color(0.7, 0.8, 0.85)
			m.metallic = 0.6
			m.roughness = 0.05
		"smoke":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			m.albedo_color = Color(0.22, 0.22, 0.23, 0.55)
			var g := Gradient.new()
			g.set_color(0, Color(1, 1, 1, 1))
			g.set_color(1, Color(1, 1, 1, 0))
			var tex := GradientTexture2D.new()
			tex.gradient = g
			tex.fill = GradientTexture2D.FILL_RADIAL
			tex.fill_from = Vector2(0.5, 0.5)
			tex.fill_to = Vector2(0.5, 0.0)
			tex.width = 64
			tex.height = 64
			m.albedo_texture = tex
	_mats[key] = m
	return m


func _add(mesh: Mesh, mat: String, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(mat)
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## length: the wreck's footprint length; rng places the bits.
func build(length: float, rng: RandomNumberGenerator) -> void:
	# Warning triangle well behind the wreck.
	var tri := PrismMesh.new()
	tri.size = Vector3(0.5, 0.45, 0.03)
	_add(tri, "red", Vector3(rng.randf_range(-0.6, 0.6), 0.23, length * 0.5 + 22.0))
	# A row of cones angled across the lane.
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.17
	cone.height = 0.6
	cone.radial_segments = 10
	var band := CylinderMesh.new()
	band.top_radius = 0.09
	band.bottom_radius = 0.11
	band.height = 0.1
	band.radial_segments = 10
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	for i in 4:
		var p := Vector3(side * (1.4 - i * 0.9), 0.3, length * 0.5 + 6.0 + i * 2.2)
		_add(cone, "cone", p)
		_add(band, "stripe", p + Vector3(0, 0.05, 0))
	# Debris and glass on the road around the cars.
	for i in 14:
		var b := BoxMesh.new()
		var glass := i % 2 == 0
		b.size = Vector3(rng.randf_range(0.05, 0.3), 0.02, rng.randf_range(0.05, 0.25))
		_add(b, "glass" if glass else "debris",
				Vector3(rng.randf_range(-2.2, 2.2), 0.012, rng.randf_range(-length * 0.6, length * 0.6 + 3.0)),
				Vector3(0, rng.randf() * TAU, 0))
	# Smoke column from the engine bay.
	var smoke := CPUParticles3D.new()
	smoke.amount = 26
	smoke.lifetime = 4.0
	smoke.preprocess = 4.0
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 2.2)
	q.material = _mat("smoke")
	smoke.mesh = q
	smoke.direction = Vector3(0, 1, 0)
	smoke.spread = 12.0
	smoke.gravity = Vector3(0.4, 0.6, 0)
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 1.8
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 2.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 3.0))
	smoke.scale_amount_curve = curve
	smoke.position = Vector3(0, 1.0, -length * 0.3)
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.local_coords = true  # the site is static; world-space smoke was left behind on rebase
	add_child(smoke)
