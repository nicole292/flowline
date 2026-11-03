class_name CrashFx
extends Node3D
## Particle effects for a wreck: a burst of sparks, glass and body panels at
## the impact, sparks on every landing, and smoke pouring from the engine.
## CPU particles so it also runs in the web (Compatibility) renderer.

var _sparks: CPUParticles3D
var _glass: CPUParticles3D
var _debris: CPUParticles3D
var _smoke: CPUParticles3D
var _debris_mat: StandardMaterial3D


func _ready() -> void:
	_sparks = _make(70, 0.55, _box(Vector3(0.025, 0.025, 0.16), _unshaded(Color(1.0, 0.62, 0.2), 4.0)))
	_sparks.initial_velocity_min = 5.0
	_sparks.initial_velocity_max = 14.0
	_sparks.spread = 70.0
	_sparks.particle_flag_align_y = true
	_glass = _make(60, 1.3, _box(Vector3(0.07, 0.006, 0.05), _glass_mat()))
	_glass.initial_velocity_min = 2.5
	_glass.initial_velocity_max = 7.5
	_glass.spread = 85.0
	_glass.angular_velocity_min = -720.0
	_glass.angular_velocity_max = 720.0
	_debris_mat = StandardMaterial3D.new()
	_debris_mat.metallic = 0.5
	_debris_mat.roughness = 0.35
	_debris = _make(14, 1.8, _box(Vector3(0.28, 0.04, 0.2), _debris_mat))
	_debris.initial_velocity_min = 3.0
	_debris.initial_velocity_max = 8.0
	_debris.spread = 75.0
	_debris.angular_velocity_min = -540.0
	_debris.angular_velocity_max = 540.0
	_debris.scale_amount_min = 0.5
	_debris.scale_amount_max = 1.4
	_smoke = _make(28, 2.8, _smoke_mesh())
	_smoke.one_shot = false
	_smoke.explosiveness = 0.0
	_smoke.emitting = false
	_smoke.gravity = Vector3(0, 1.4, 0)
	_smoke.initial_velocity_min = 0.4
	_smoke.initial_velocity_max = 1.4
	_smoke.spread = 35.0
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke.emission_sphere_radius = 0.6
	# Puffs swell, then shrink away (no colour ramp: vertex colours would
	# leave a black disc at the emitter from not-yet-born particles).
	var grow := Curve.new()
	grow.max_value = 2.0
	grow.add_point(Vector2(0, 0.3))
	grow.add_point(Vector2(0.5, 1.5))
	grow.add_point(Vector2(1, 0.0))
	_smoke.scale_amount_curve = grow


func _make(amount: int, life: float, mesh: Mesh) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	p.mesh = mesh
	p.direction = Vector3.UP
	p.gravity = Vector3(0, -9.8, 0)
	p.local_coords = false
	add_child(p)
	return p


func _box(size: Vector3, mat: Material) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	return m


func _unshaded(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c * energy
	return m


func _glass_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.88, 0.95, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.8
	m.roughness = 0.05
	return m


func _gradient(offsets: Array[float], colors: Array[Color]) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	return g


func _smoke_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(0.5, 0.5, 0.52, 0.3)
	var tex := GradientTexture2D.new()
	tex.gradient = _gradient([0.0, 0.45, 1.0], [Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	m.albedo_texture = tex
	q.material = m
	return q


## The big hit: everything flies. `strength` 0..1 scales the amounts.
func impact(at: Vector3, paint: Color, strength: float) -> void:
	_debris_mat.albedo_color = paint
	for p: CPUParticles3D in [_sparks, _glass, _debris]:
		p.global_position = at
		p.speed_scale = lerpf(0.75, 1.15, clampf(strength, 0.0, 1.0))
		p.restart()
	_smoke.emitting = true


## Sparks when the tumbling car hits the road again.
func scrape(at: Vector3, strength: float) -> void:
	_sparks.global_position = at
	_sparks.speed_scale = lerpf(0.5, 1.0, clampf(strength, 0.0, 1.0))
	_sparks.restart()


## Keeps the engine smoke on the wreck.
func follow(at: Vector3) -> void:
	_smoke.global_position = at


## Ends every effect and clears what is still in the air.
func stop() -> void:
	for p: CPUParticles3D in [_sparks, _glass, _debris, _smoke]:
		p.restart()
		p.emitting = false
