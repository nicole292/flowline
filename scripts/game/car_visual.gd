class_name CarVisual
extends Node3D
## Visual representation of any vehicle built by tools/blender/build_cars.py:
## swaps in shared runtime materials, spins/steers wheels, drives body
## roll/pitch (suspension feel), brake lights, blinkers and a contact shadow.

static var _shared := {}
static var _scenes := {}

var length := 4.5
var width := 1.9
var height := 1.4
var wheel_radius := 0.34

var _model: Node3D
var _body: Node3D
var _body_base := Transform3D.IDENTITY
var _wheels: Array[Dictionary] = []   # {node, base, steer, sign}
var _paint: StandardMaterial3D
var _tail_slots: Array = []           # [MeshInstance3D, surface]
var _blinkers: Array[MeshInstance3D] = []
var _braking := false
var _spin := 0.0
var _blink_clock := 0.0


static func shared_material(key: String) -> Material:
	if _shared.has(key):
		return _shared[key]
	var m := StandardMaterial3D.new()
	match key:
		"Glass":
			m.albedo_color = Color(0.012, 0.016, 0.02)
			m.metallic = 0.15
			m.roughness = 0.02
			m.metallic_specular = 1.0
		"Trim":
			m.albedo_color = Color(0.025, 0.025, 0.028)
			m.roughness = 0.55
		"Chrome":
			m.albedo_color = Color(0.9, 0.9, 0.92)
			m.metallic = 1.0
			m.roughness = 0.12
		"Tire":
			m.albedo_color = Color(0.03, 0.03, 0.032)
			m.roughness = 0.9
		"Rim":
			m.albedo_color = Color(0.66, 0.67, 0.7)
			m.metallic = 1.0
			m.roughness = 0.3
		"Headlight":
			m.albedo_color = Color(0.85, 0.88, 0.95)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.97, 0.9)
			m.emission_energy_multiplier = 1.2
			m.roughness = 0.1
		"TailLens":
			m.albedo_color = Color(0.18, 0.01, 0.01)
			m.roughness = 0.05
			m.metallic_specular = 0.9
			m.emission_enabled = true
			m.emission = Color(1.0, 0.03, 0.02)
			m.emission_energy_multiplier = 0.25
		"Plate":
			m.albedo_color = Color(0.86, 0.86, 0.83)
			m.roughness = 0.35
		"TailOff":
			m.albedo_color = Color(0.32, 0.02, 0.02)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.05, 0.03)
			m.emission_energy_multiplier = 1.6
			m.roughness = 0.15
		"TailOn":
			m.albedo_color = Color(0.6, 0.03, 0.02)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.06, 0.03)
			m.emission_energy_multiplier = 5.0
			m.roughness = 0.15
		"Blinker":
			m.albedo_color = Color(1.0, 0.55, 0.05)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.5, 0.05)
			m.emission_energy_multiplier = 5.0
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"Shadow":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0, 0, 0, 0.5)
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
			m.disable_receive_shadows = true
		_:
			m.albedo_color = Color.MAGENTA
	# Baked ambient occlusion lives in the vertex colours of every car mesh.
	if key != "Shadow" and key != "Blinker":
		m.vertex_color_use_as_albedo = true
	_shared[key] = m
	return m


static func load_scene(id: String) -> PackedScene:
	if not _scenes.has(id):
		_scenes[id] = load(CarCatalog.model_path(id))
	return _scenes[id]


func setup(id: String, paint: Color, with_blinkers := false) -> void:
	if _model:
		_model.queue_free()
		_wheels.clear()
		_tail_slots.clear()
		for b in _blinkers:
			b.queue_free()
		_blinkers.clear()
	_model = load_scene(id).instantiate()
	add_child(_model)
	_paint = StandardMaterial3D.new()
	_paint.vertex_color_use_as_albedo = true
	_paint.metallic = 0.45
	_paint.roughness = 0.32
	_paint.clearcoat_enabled = true
	_paint.clearcoat = 1.0
	_paint.clearcoat_roughness = 0.08
	set_paint(paint)
	_apply_materials(_model)
	_body = _model.find_child("Body", true, false)
	_body_base = _body.transform
	var aabb := _mesh_aabb(_body)
	length = aabb.size.z
	width = aabb.size.x
	height = aabb.end.y
	for wname in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var w: Node3D = _model.find_child(wname, true, false)
		if w == null:
			continue
		var waabb := _mesh_aabb(w)
		wheel_radius = waabb.size.y * 0.5
		_wheels.append({"node": w, "base": w.transform, "steer": wname.begins_with("Wheel_F"),
				"sign": 1.0 if w.position.x < 0.0 else -1.0})
	_add_shadow()
	if with_blinkers:
		_add_blinkers(aabb)


func set_paint(c: Color) -> void:
	_paint.albedo_color = c


func _apply_materials(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var key := src.resource_name if src else ""
			match key:
				"Paint":
					mi.set_surface_override_material(i, _paint)
				"Taillight":
					mi.set_surface_override_material(i, shared_material("TailOff"))
					_tail_slots.append([mi, i])
				"Glass", "Trim", "Chrome", "Tire", "Rim", "Headlight", "TailLens", "Plate":
					mi.set_surface_override_material(i, shared_material(key))
	for c in n.get_children():
		_apply_materials(c)


func _mesh_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in [n] + n.find_children("*", "MeshInstance3D", true, false):
		if not (mi is MeshInstance3D):
			continue
		var box: AABB = _relative_xform(mi) * (mi as MeshInstance3D).get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _relative_xform(n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != _model:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _add_shadow() -> void:
	var q := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(width + 0.7, length + 1.0)
	q.mesh = mesh
	q.material_override = shared_material("Shadow")
	q.rotation.x = -PI / 2
	q.position.y = 0.03
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(q)


func _add_blinkers(aabb: AABB) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.07, 0.05)
	var y := aabb.position.y + aabb.size.y * (0.42 if height > 2.2 else 0.56)
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:  # -1 front (-z), +1 rear (+z)
			var b := MeshInstance3D.new()
			b.mesh = box
			b.material_override = shared_material("Blinker")
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			b.position = Vector3(side * (width * 0.5 - 0.1), y,
					(aabb.end.z - 0.02) if end > 0 else (aabb.position.z + 0.06))
			b.set_meta("side", side)
			b.visible = false
			add_child(b)
			_blinkers.append(b)


func set_brake(on: bool) -> void:
	if on == _braking:
		return
	_braking = on
	var m := shared_material("TailOn" if on else "TailOff")
	for slot in _tail_slots:
		(slot[0] as MeshInstance3D).set_surface_override_material(slot[1], m)


func set_blinker(dir: int, dt: float) -> void:
	_blink_clock += dt
	var lit := dir != 0 and fmod(_blink_clock, 0.7) < 0.38
	for b in _blinkers:
		b.visible = lit and signf(b.get_meta("side")) == float(dir)


## speed m/s, steer radians for front wheels, roll/pitch radians for body.
func animate(dt: float, speed: float, steer: float, roll: float, pitch: float) -> void:
	_spin = fmod(_spin + speed * dt / wheel_radius, TAU)
	for w in _wheels:
		var base: Transform3D = w["base"]
		var yaw := steer if w["steer"] else 0.0
		var b := Basis(Vector3.UP, yaw) * base.basis * Basis(Vector3.RIGHT, _spin * float(w["sign"]))
		(w["node"] as Node3D).transform = Transform3D(b, base.origin)
	if _body:
		var pivot := Vector3(0, 0.55, 0)
		var rot := Basis.from_euler(Vector3(pitch, 0, roll))
		var t := Transform3D(Basis.IDENTITY, pivot) * Transform3D(rot, Vector3.ZERO) \
				* Transform3D(Basis.IDENTITY, -pivot)
		_body.transform = t * _body_base
