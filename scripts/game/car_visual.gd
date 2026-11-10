class_name CarVisual
extends Node3D
## Visual representation of any vehicle built by tools/blender/build_cars.py:
## swaps in shared runtime materials, spins/steers wheels, drives body
## roll/pitch (suspension feel), brake lights, blinkers and a contact shadow.
## Motorcycles (two wheels, Wheel_F / Wheel_R) lean into turns instead of rolling.

static var _shared := {}
static var _scenes := {}

var length := 4.5
var width := 1.9
var height := 1.4
var wheel_radius := 0.34
var is_bike := false
## Current bike lean in radians (positive = leaning right).
var lean := 0.0
const PARKED_LEAN := -0.14  ## onto the side stand (left)

var _parked := false
var _stand: Node3D
var _riders: Array[Node3D] = []

var _model: Node3D
var _body: Node3D
var _body_base := Transform3D.IDENTITY
var _wheels: Array[Dictionary] = []   # {node, base, steer, sign}
var _paint: StandardMaterial3D
var _rim: StandardMaterial3D
var _lights: Array[SpotLight3D] = []
var _fill: OmniLight3D
var _plates: Array[Label3D] = []
var _tail_slots: Array = []           # [MeshInstance3D, surface]
var _blinkers: Array[MeshInstance3D] = []
var _siren: OmniLight3D               # police light bar glow, only on the patrol car
## Player's car: braking also throws a red glow on the road behind it.
var brake_glow := false
var _brake_light: OmniLight3D
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
			m.emission_energy_multiplier = 2.6
			m.roughness = 0.1
		"TailLens":
			m.albedo_color = Color(0.18, 0.01, 0.01)
			m.roughness = 0.05
			m.metallic_specular = 0.9
			m.emission_enabled = true
			m.emission = Color(1.0, 0.03, 0.02)
			m.emission_energy_multiplier = 0.25
		"Gloss":
			m.albedo_color = Color(0.012, 0.012, 0.014)
			m.metallic = 0.3
			m.roughness = 0.08
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
		"Caliper":
			m.albedo_color = Color(0.75, 0.04, 0.03)
			m.roughness = 0.3
		"Plate":
			m.albedo_color = Color(0.86, 0.86, 0.83)
			m.roughness = 0.35
		"TailOff":
			m.albedo_color = Color(0.32, 0.02, 0.02)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.05, 0.03)
			m.emission_energy_multiplier = 1.0
			m.roughness = 0.15
		"TailOn":
			m.albedo_color = Color(0.9, 0.04, 0.02)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.06, 0.03)
			m.emission_energy_multiplier = 12.0
			m.roughness = 0.15
		"SirenRed", "SirenBlue":
			var blue := key == "SirenBlue"
			m.albedo_color = Color(0.1, 0.25, 1.0) if blue else Color(1.0, 0.08, 0.05)
			m.emission_enabled = true
			m.emission = m.albedo_color
			m.emission_energy_multiplier = 1.0
			m.roughness = 0.2
		"Cracked":  # crazed safety glass: pale and frosted
			m.albedo_color = Color(0.5, 0.54, 0.56)
			m.roughness = 0.4
			m.metallic = 0.1
		"Blinker":
			m.albedo_color = Color(1.0, 0.55, 0.05)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.5, 0.05)
			m.emission_energy_multiplier = 5.0
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"Shadow":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			m.albedo_color = Color(0, 0, 0, 0.28)
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
		_plates.clear()
	_model = load_scene(id).instantiate()
	add_child(_model)
	_paint = StandardMaterial3D.new()
	_paint.vertex_color_use_as_albedo = true
	_paint.metallic = 0.55
	_paint.roughness = 0.22
	_paint.clearcoat_enabled = true
	_paint.clearcoat = 1.0
	_paint.clearcoat_roughness = 0.08
	set_paint(paint)
	_rim = (shared_material("Rim") as StandardMaterial3D).duplicate()
	_apply_materials(_model)
	_body = _model.find_child("Body", true, false)
	_body_base = _body.transform
	var aabb := _mesh_aabb(_body)
	length = aabb.size.z
	width = aabb.size.x
	height = aabb.end.y
	is_bike = _model.find_child("Wheel_F", true, false) != null
	lean = 0.0
	_stand = _model.find_child("Stand", true, false)
	_riders.clear()
	for n in ["Rider", "RiderGear"]:
		var r: Node3D = _model.find_child(n, true, false)
		if r:
			_riders.append(r)
	set_parked(_parked)
	for wname in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR", "Wheel_F", "Wheel_R"]:
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
	if _siren:
		_siren.queue_free()
		_siren = null
	if id == "t_police":
		_dress_police(aabb)


## Patrol car: POLICE on both doors and a light that washes the road in
## red and blue as the bar flashes.
func _dress_police(aabb: AABB) -> void:
	for side in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = "POLICE"
		l.font = UiTheme.BOLD
		l.font_size = 64
		l.pixel_size = 0.0045
		l.outline_size = 0
		l.modulate = Color(0.03, 0.1, 0.4)
		l.position = Vector3(side * (aabb.end.x + 0.012), aabb.size.y * 0.5, 0.1)
		l.rotation.y = side * PI / 2
		_model.add_child(l)
	_siren = OmniLight3D.new()
	_siren.omni_range = 11.0
	_siren.light_energy = 2.5
	_siren.shadow_enabled = false
	_siren.position = Vector3(0, aabb.end.y + 0.4, 0)
	add_child(_siren)


## Flashes the light bars (shared by every patrol car): red, red, blue, blue.
func update_siren(t: float) -> void:
	if _siren == null:
		return
	var phase := fmod(t, 0.8)
	var red_on := phase < 0.4 and fmod(phase, 0.2) < 0.11
	var blue_on := phase >= 0.4 and fmod(phase, 0.2) < 0.11
	(shared_material("SirenRed") as StandardMaterial3D).emission_energy_multiplier = 9.0 if red_on else 0.6
	(shared_material("SirenBlue") as StandardMaterial3D).emission_energy_multiplier = 9.0 if blue_on else 0.6
	_siren.visible = red_on or blue_on
	_siren.light_color = Color(1.0, 0.1, 0.05) if red_on else Color(0.15, 0.3, 1.0)


## A bike parked in the garage: rider off, side stand down, leaning on it.
func set_parked(on: bool) -> void:
	_parked = on
	if _stand:
		_stand.visible = on
	for r in _riders:
		r.visible = not on
	if on and is_bike:
		lean = PARKED_LEAN
		_model.transform = Transform3D(Basis(Vector3.BACK, -lean), Vector3.ZERO)


func paint_material() -> Material:
	return _paint


func set_paint(c: Color) -> void:
	_paint.albedo_color = c


func set_rim(index: int) -> void:
	var r: Array = CarCatalog.RIMS[clampi(index, 0, CarCatalog.RIMS.size() - 1)]
	_rim.albedo_color = r[1]
	_rim.metallic = r[2]
	_rim.roughness = r[3]


## Two real headlight beams for the player's car at night.
func set_headlights(on: bool) -> void:
	if on and _lights.is_empty():
		for side in ([0.0] if is_bike else [-1.0, 1.0]):
			var l := SpotLight3D.new()
			l.light_color = Color(1.0, 0.95, 0.85)
			l.light_energy = 7.0
			l.spot_range = 70.0
			l.spot_angle = 24.0
			l.spot_attenuation = 0.8
			l.shadow_enabled = false
			l.position = Vector3(side * width * 0.32, 0.95 if is_bike else 0.68, -length * 0.5 + 0.1)
			l.rotation.x = deg_to_rad(-4.0)
			add_child(l)
			_lights.append(l)
	for l in _lights:
		l.visible = on


## Night: a soft warm light above and behind the car, like passing under
## street lamps, so the player's car doesn't vanish into the dark.
func set_fill_light(on: bool) -> void:
	if on and _fill == null:
		_fill = OmniLight3D.new()
		_fill.light_color = Color(1.0, 0.82, 0.62)
		_fill.light_energy = 1.6
		_fill.omni_range = 9.0
		_fill.omni_attenuation = 1.2
		_fill.shadow_enabled = false
		add_child(_fill)
	if _fill:
		_fill.position = Vector3(0, height + 2.6, length * 0.5 + 2.0)
		_fill.visible = on


## Writes the player's own text on both number plates: a clean plate face
## goes over the modelled one (which carries fake characters) with the
## text on top. The plates ride on their mesh, so they follow body roll.
func set_plate(text: String) -> void:
	if _plates.is_empty():
		_build_plates()
	for l in _plates:
		l.text = text
		var px := l.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x
		var w: float = l.get_meta("w")
		var h: float = l.get_meta("h")
		l.pixel_size = minf(h * 0.8 / l.font_size, w * 0.9 / maxf(px, 1.0))


func _build_plates() -> void:
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m == null or m.resource_name != "Plate":
				continue
			var verts: PackedVector3Array = mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
			for rear in [true, false]:  # rear plate sits at +z, front at -z
				var box := AABB()
				var first := true
				for v in verts:
					if (v.z > 0.0) != rear:
						continue
					box = AABB(v, Vector3.ZERO) if first else box.expand(v)
					first = false
				if not first:
					_add_plate(mi, box, rear)


func _add_plate(parent: Node3D, box: AABB, rear: bool) -> void:
	var c := box.get_center()
	var out := 1.0 if rear else -1.0
	var face := (box.end.z if rear else box.position.z) + out * 0.006
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(box.size.x, box.size.y)
	q.mesh = qm
	q.material_override = shared_material("Plate")
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.position = Vector3(c.x, c.y, face)
	q.rotation.y = 0.0 if rear else PI
	parent.add_child(q)
	# Blue band on the left, like a European plate.
	var bw := box.size.x * 0.09
	var side := 1.0 if rear else -1.0  # the viewer's left is -x behind the car, +x in front
	var band := MeshInstance3D.new()
	var bm := QuadMesh.new()
	bm.size = Vector2(bw, box.size.y)
	band.mesh = bm
	band.material_override = _band_material()
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	band.position = Vector3(c.x - side * (box.size.x - bw) * 0.5, c.y, face + out * 0.0015)
	band.rotation.y = q.rotation.y
	parent.add_child(band)
	var l := Label3D.new()
	l.font = UiTheme.BOLD
	l.font_size = 96
	l.outline_size = 0
	l.modulate = Color(0.05, 0.06, 0.09)
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.position = Vector3(c.x + side * bw * 0.5, c.y, face + out * 0.003)
	l.rotation.y = 0.0 if rear else PI
	l.set_meta("w", box.size.x - bw)
	l.set_meta("h", box.size.y)
	parent.add_child(l)
	_plates.append(l)


static func _band_material() -> Material:
	if not _shared.has("PlateBand"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.0, 0.2, 0.6)
		m.roughness = 0.4
		_shared["PlateBand"] = m
	return _shared["PlateBand"]


## Night makes every car's lamps glow brighter (shared materials).
static func set_night(on: bool) -> void:
	(shared_material("Headlight") as StandardMaterial3D).emission_energy_multiplier = 5.0 if on else 2.6
	(shared_material("TailOff") as StandardMaterial3D).emission_energy_multiplier = 2.2 if on else 1.0
	(shared_material("TailOn") as StandardMaterial3D).emission_energy_multiplier = 14.0 if on else 12.0
	(shared_material("TailLens") as StandardMaterial3D).emission_energy_multiplier = 0.8 if on else 0.25


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
				"Rim":
					mi.set_surface_override_material(i, _rim)
				"Glass", "Trim", "Chrome", "Tire", "Headlight", "TailLens", "Plate", "Gloss", "Caliper", "SirenRed", \
						"SirenBlue", "Cracked":
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
	q.position.y = 0.06  # high enough not to flicker against the road far away
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(q)


func _add_blinkers(aabb: AABB) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.07, 0.05)
	var y := aabb.position.y + aabb.size.y * (0.42 if height > 2.2 else 0.56)
	var half := width * 0.5 - 0.1
	if is_bike:  # small stalks either side of the lamp and the tail
		y = 0.85
		half = 0.15
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:  # -1 front (-z), +1 rear (+z)
			var b := MeshInstance3D.new()
			b.mesh = box
			b.material_override = shared_material("Blinker")
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			b.position = Vector3(side * half, y,
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
	if brake_glow:
		if _brake_light == null:
			_brake_light = OmniLight3D.new()
			_brake_light.light_color = Color(1.0, 0.05, 0.02)
			_brake_light.light_energy = 1.6
			_brake_light.omni_range = 3.5
			_brake_light.shadow_enabled = false
			add_child(_brake_light)
		_brake_light.position = Vector3(0, 0.55, length * 0.5 + 0.6)
		_brake_light.visible = on


## dir: -1 left, 1 right, 0 off, 2 hazard lights (both sides).
func set_blinker(dir: int, dt: float) -> void:
	_blink_clock += dt
	var lit := dir != 0 and fmod(_blink_clock, 0.7) < 0.38
	for b in _blinkers:
		b.visible = lit and (dir == 2 or signf(b.get_meta("side")) == float(dir))


## speed m/s, steer radians for front wheels, roll/pitch radians for body.
func animate(dt: float, speed: float, steer: float, roll: float, pitch: float) -> void:
	_spin = fmod(_spin + speed * dt / wheel_radius, TAU)
	for w in _wheels:
		var base: Transform3D = w["base"]
		var yaw := steer if w["steer"] else 0.0
		var b := Basis(Vector3.UP, yaw) * base.basis * Basis(Vector3.RIGHT, _spin * float(w["sign"]))
		(w["node"] as Node3D).transform = Transform3D(b, base.origin)
	if is_bike:
		# The whole bike leans about the tyre contact line: into the turn,
		# much further than a car's body rolls out of it.
		var want := PARKED_LEAN if _parked else clampf(roll * 7.0, -0.55, 0.55)
		lean = lerpf(lean, want, 1.0 - exp(-8.0 * dt))
		_model.transform = Transform3D(Basis(Vector3.BACK, -lean) * Basis(Vector3.RIGHT, pitch * 0.4), Vector3.ZERO)
		return
	if _body:
		var pivot := Vector3(0, 0.55, 0)
		var rot := Basis.from_euler(Vector3(pitch, 0, roll))
		var t := Transform3D(Basis.IDENTITY, pivot) * Transform3D(rot, Vector3.ZERO) \
				* Transform3D(Basis.IDENTITY, -pivot)
		_body.transform = t * _body_base
