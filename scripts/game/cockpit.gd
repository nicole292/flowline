class_name Cockpit
extends Node3D
## Driver's-eye view: what you see from the seat with your hands on the
## controls. The interiors are modelled in Blender (tools/blender/build_cars.py
## COCKPITS) around the eye at the origin and parented to the camera. Cars
## get a dashboard, bonnet, pillars and a leather wheel held at quarter to
## three; bikes the yokes, clip-ons, clocks, tank and screen. The wheel or bars
## turn with the steering and the forearms stretch from the shoulders to the
## wrists (Wrist_L / Wrist_R in the model).

const WHEEL_TURN := 1.6   ## wheel rotation (radians) at full steering lock
const BAR_TURN := 0.22    ## handlebar yaw at full lock
## Skin tones for the driver's bare hands (setting "skin").
const SKIN := {"light": Color(0.87, 0.69, 0.58), "medium": Color(0.76, 0.56, 0.42),
		"tan": Color(0.64, 0.44, 0.3), "brown": Color(0.45, 0.29, 0.19), "dark": Color(0.27, 0.17, 0.11)}

var bike := false

var _model: Node3D
var _wheel: Node3D        # SteerWheel (car) or Bars (bike)
var _wrists: Array[Node3D] = []
var _shoulders: Array[Vector3] = []
var _arms: Array[MeshInstance3D] = []
var _skin := StandardMaterial3D.new()
## Rear-view mirror: a small camera looking backwards renders into a
## viewport shown on the modelled mirror glass (only while this view is on).
const LAYER := 2           ## the cockpit's own render layer; the mirror camera skips it
var _mirror_vp: SubViewport
var _mirror_cam: Camera3D
var _mirror_mat: StandardMaterial3D
var _mirrors: Array[MeshInstance3D] = []
## The wheel turns like a real one: it eases towards the steering with a
## little momentum instead of snapping (arrow buttons are on/off).
var _wheel_angle := 0.0
var _wheel_vel := 0.0
const WHEEL_SMOOTH := 14.0   ## spring rate (1/s); higher = snappier
## Live instruments: needles on both dials and the gear/speed screen.
var _needles: Array[Node3D] = []   # [rev counter, speedometer]
var _screen_text: Label3D
var _needle_v := [0.0, 0.0]
## Slow device (graphics lowered): the mirror refreshes every other frame.
var low_cost := false
var _mirror_tick := 0


## Rebuilds the rig for a car or a bike, painted like the vehicle.
func build(is_bike: bool, paint: Material) -> void:
	if _model:
		_model.queue_free()
	for a in _arms:
		a.queue_free()
	_arms.clear()
	_wrists.clear()
	bike = is_bike
	var path := "res://assets/vehicles/cockpit_%s.glb" % ("bike" if bike else "car")
	_model = (load(path) as PackedScene).instantiate()
	add_child(_model)
	# A rider's eye sits low behind the screen: lift the bars into view.
	_model.position = Vector3(0, 0.1, 0.04) if bike else Vector3.ZERO
	_paint(_model, paint)
	_wheel = _model.find_child("Bars" if bike else "SteerWheel", true, false)
	for w in ["Wrist_L", "Wrist_R"]:
		_wrists.append(_model.find_child(w, true, false))
	# Shoulders sit just below and either side of the eye, out of view.
	if bike:
		_shoulders = [Vector3(-0.24, -0.42, 0.12), Vector3(0.24, -0.42, 0.12)]
	else:
		_shoulders = [Vector3(-0.25, -0.56, 0.14), Vector3(0.25, -0.56, 0.14)]
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color(0.05, 0.05, 0.06) if bike else Color(0.1, 0.13, 0.2)
	sleeve.roughness = 0.6 if bike else 0.9
	for i in 2:
		var arm := MeshInstance3D.new()
		var c := CapsuleMesh.new()
		c.radius = 0.048 if bike else 0.045
		c.height = 1.0   # stretched by scaling each frame (rebuilding the mesh every frame stuttered)
		c.radial_segments = 16
		c.rings = 6
		arm.mesh = c
		arm.material_override = sleeve
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(arm)
		_arms.append(arm)
	if not bike:
		_add_cabin_shade()
	for a in _arms:
		a.layers = LAYER
	_build_mirrors()
	_build_instruments()
	_wheel_angle = 0.0
	_wheel_vel = 0.0
	update(0.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _mirror_vp:
		_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() 				else SubViewport.UPDATE_DISABLED


## Finds the modelled mirror glass (material "Mirror") and lays the live
## rear view over it. A car has one mirror; a bike two, each showing its side.
func _build_mirrors() -> void:
	for m in _mirrors:
		m.queue_free()
	_mirrors.clear()
	if _mirror_vp == null:
		_mirror_vp = SubViewport.new()
		_mirror_vp.size = Vector2i(384, 96)
		_mirror_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(_mirror_vp)
		_mirror_cam = Camera3D.new()
		_mirror_cam.cull_mask = 1   # the world only, not this cabin
		_mirror_cam.fov = 20.0
		_mirror_cam.near = 0.5
		_mirror_cam.far = 200.0   # in a mirror this small, beyond 200 m is a few pixels
		_mirror_vp.add_child(_mirror_cam)
		_mirror_mat = StandardMaterial3D.new()
		_mirror_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mirror_mat.albedo_texture = _mirror_vp.get_texture()
	var boxes: Array[AABB] = []
	var wings: Array[AABB] = []   # car wing mirrors (material "SideMirror")
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		var xf := _to_cockpit(mi as Node3D)
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			if src and src.resource_name == "SideMirror":
				for side in [-1.0, 1.0]:  # left and right wing mirror, split at the car's centre line
					var wb := AABB()
					var wfirst := true
					for v in mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
						var p: Vector3 = xf * v
						if signf(p.x - 0.37) != side:
							continue
						wb = AABB(p, Vector3.ZERO) if wfirst else wb.expand(p)
						wfirst = false
					if not wfirst:
						wings.append(wb)
				continue
			if src == null or src.resource_name != "Mirror":
				continue
			var sides := [-1.0, 1.0] if bike else [0.0]
			for side in sides:
				var box := AABB()
				var first := true
				for v in mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
					var p: Vector3 = xf * v
					if side != 0.0 and signf(p.x) != side:
						continue
					box = AABB(p, Vector3.ZERO) if first else box.expand(p)
					first = false
				if not first:
					boxes.append(box)
	# Wing mirrors show the outer thirds of the same live rear view (no extra
	# rendering): the left mirror the traffic behind on the left, the right
	# mirror behind on the right, each flipped like real glass.
	for box in wings:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.2, box.size.y * 0.93)
		q.mesh = qm
		var mat: StandardMaterial3D = _mirror_mat.duplicate()
		var left := box.get_center().x < 0.37
		mat.uv1_scale = Vector3(-1.0 / 3.0, 1, 1)
		mat.uv1_offset = Vector3(1.0 if left else 1.0 / 3.0, 0, 0)
		q.material_override = mat
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.layers = LAYER
		# Turned like the glass: halfway between the driver's eye (the origin)
		# and straight back (+z), level.
		var c := box.get_center()
		var to_eye := Vector3(-c.x, 0.0, -c.z).normalized()
		var nrm := (to_eye + Vector3.BACK).normalized()
		q.transform = Transform3D(Basis.looking_at(-nrm, Vector3.UP), c + nrm * 0.004)
		add_child(q)
		_mirrors.append(q)
	for box in boxes:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(box.size.x, box.size.y)
		q.mesh = qm
		var mat := _mirror_mat
		if bike:  # each bike mirror shows its own half of the view
			mat = _mirror_mat.duplicate()
			var left := box.get_center().x < 0.0
			mat.uv1_scale = Vector3(-0.5, 1, 1)
			mat.uv1_offset = Vector3(0.5 if left else 1.0, 0, 0)
		else:
			mat.uv1_scale = Vector3(-1, 1, 1)   # mirrored left-right, like real glass
			mat.uv1_offset = Vector3(1, 0, 0)
		q.material_override = mat
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.layers = LAYER
		# The face nearest the eye (the eye is the origin, looking down -z).
		q.position = Vector3(box.get_center().x, box.get_center().y, box.end.z + 0.0015)
		add_child(q)
		_mirrors.append(q)


## Needles (rev counter, speedometer) and the small screen's text, placed at
## the Dial_L / Dial_R / Cluster_C empties of the car cockpit model.
func _build_instruments() -> void:
	_needles.clear()
	_screen_text = null
	if bike:
		return
	# The dials lean back 20 degrees: their face points up a little, at the driver.
	var n := Vector3(0, sin(deg_to_rad(20.0)), cos(deg_to_rad(20.0)))
	var up := Vector3(0, cos(deg_to_rad(20.0)), -sin(deg_to_rad(20.0)))
	var face := Basis(up.cross(n), up, n)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.35, 0.12)
	for dial in ["Dial_L", "Dial_R"]:
		var e: Node3D = _model.find_child(dial, true, false)
		if e == null:
			continue
		var pivot := Node3D.new()
		_model.add_child(pivot)
		pivot.transform = Transform3D(face, _to_cockpit(e).origin - _model.position)
		var needle := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.005, 0.068, 0.002)
		needle.mesh = bm
		needle.material_override = mat
		needle.position = Vector3(0, 0.026, 0.003)
		needle.layers = LAYER
		needle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(needle)
		_needles.append(pivot)
	var c: Node3D = _model.find_child("Cluster_C", true, false)
	if c:
		_screen_text = Label3D.new()
		_screen_text.font = UiTheme.BOLD
		_screen_text.font_size = 48
		_screen_text.pixel_size = 0.0004
		_screen_text.modulate = Color(0.75, 0.92, 1.0)
		_screen_text.outline_size = 0
		_screen_text.shaded = false
		_screen_text.layers = LAYER
		_screen_text.transform = Transform3D(face, _to_cockpit(c).origin - _model.position + n * 0.004)
		_model.add_child(_screen_text)


func _update_instruments(dt: float, speed_frac: float, rpm: float, gear: int, speed_text: String) -> void:
	if _needles.size() < 2:
		return
	# 0 points down-left (+135 deg), full scale down-right (-135 deg); needles
	# follow with a short lag like real gauges.
	for i in 2:
		var want: float = clampf(rpm if i == 0 else speed_frac, 0.0, 1.0)
		_needle_v[i] = lerpf(_needle_v[i], want, 1.0 - exp(-12.0 * dt))
		_needles[i].transform.basis = _needle_face() * Basis(Vector3.BACK, deg_to_rad(lerpf(135.0, -135.0, _needle_v[i])))
	if _screen_text:
		_screen_text.text = "%d
%s" % [gear, speed_text]


func _needle_face() -> Basis:
	var n := Vector3(0, sin(deg_to_rad(20.0)), cos(deg_to_rad(20.0)))
	var up := Vector3(0, cos(deg_to_rad(20.0)), -sin(deg_to_rad(20.0)))
	return Basis(up.cross(n), up, n)


func _to_cockpit(n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != self:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## The rest of the cabin is never seen, but its roof and doors still keep
## the sun off the dashboard, as in a real car: invisible shadow casters.
func _add_cabin_shade() -> void:
	var cx := 0.37  # car centre line, right of the driver's eye
	for b in [[Vector3(cx, 0.36, 0.25), Vector3(2.4, 0.05, 1.9)],       # roof
			[Vector3(cx - 1.2, -0.6, -0.1), Vector3(0.05, 0.6, 2.2)],    # driver's door
			[Vector3(cx + 1.2, -0.6, -0.1), Vector3(0.05, 0.6, 2.2)]]:   # passenger door
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = b[1]
		mi.mesh = box
		mi.position = b[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		_model.add_child(mi)


func _paint(n: Node, paint: Material) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = LAYER
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src and src.resource_name == "Paint":
				mi.set_surface_override_material(i, paint)
			elif src and src.resource_name == "Skin":
				mi.set_surface_override_material(i, _skin)
	for c in n.get_children():
		_paint(c, paint)


func set_skin(tone: String) -> void:
	_skin.albedo_color = SKIN.get(tone, SKIN["medium"])
	_skin.roughness = 0.55
	# A touch of subsurface-like softness: light passes the edges of real skin.
	_skin.rim_enabled = true
	_skin.rim = 0.25
	_skin.rim_tint = 0.6


## steer: -1 (left) .. 1 (right). speed_frac / rpm 0..1, gear and speed
## text for the instruments (car only).
func update(steer: float, speed_frac := 0.0, rpm := 0.0, gear := 1, speed_text := "") -> void:
	if _wheel == null:
		return
	var dt := clampf(get_process_delta_time(), 0.0, 0.05)
	# Critically damped spring: smooth start and stop, no overshoot.
	var target := -steer * (BAR_TURN if bike else WHEEL_TURN)
	var acc := WHEEL_SMOOTH * WHEEL_SMOOTH * (target - _wheel_angle) - 2.0 * WHEEL_SMOOTH * _wheel_vel
	_wheel_vel += acc * dt
	_wheel_angle += _wheel_vel * dt
	_update_instruments(dt, speed_frac, rpm, gear, speed_text)
	if _mirror_cam:  # from just above the eye, looking straight back
		var b := global_basis.orthonormalized()
		_mirror_cam.global_transform = Transform3D(b * Basis(Vector3.UP, PI), global_position + b.y * 0.12)
		if is_visible_in_tree():
			_mirror_tick += 1
			var mode := SubViewport.UPDATE_ALWAYS
			if low_cost:
				mode = SubViewport.UPDATE_ONCE if _mirror_tick % 2 == 0 else SubViewport.UPDATE_DISABLED
			_mirror_vp.render_target_update_mode = mode
	if bike:
		_wheel.rotation.y = _wheel_angle
	else:
		_wheel.rotation.z = _wheel_angle
	# Stretch each forearm from the shoulder to the wrist.
	for i in _arms.size():
		var wrist := to_local(_wrists[i].global_position)
		var from: Vector3 = _shoulders[i]
		var v := wrist - from
		var arm := _arms[i]
		var up := v.normalized()
		var side := up.cross(Vector3.BACK).normalized() if absf(up.z) < 0.99 else Vector3.RIGHT
		arm.transform = Transform3D(Basis(side, up * (v.length() + 0.06), side.cross(up)), from + v * 0.5)
