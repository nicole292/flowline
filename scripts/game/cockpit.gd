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
		_mirror_vp.size = Vector2i(320, 80)
		_mirror_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(_mirror_vp)
		_mirror_cam = Camera3D.new()
		_mirror_cam.cull_mask = 1   # the world only, not this cabin
		_mirror_cam.fov = 20.0
		_mirror_cam.near = 0.5
		_mirror_cam.far = 400.0
		_mirror_vp.add_child(_mirror_cam)
		_mirror_mat = StandardMaterial3D.new()
		_mirror_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mirror_mat.albedo_texture = _mirror_vp.get_texture()
	var boxes: Array[AABB] = []
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		var xf := _to_cockpit(mi as Node3D)
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
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


## steer: -1 (left) .. 1 (right).
func update(steer: float) -> void:
	if _wheel == null:
		return
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
		_wheel.rotation.y = -steer * BAR_TURN
	else:
		_wheel.rotation.z = -steer * WHEEL_TURN
	# Stretch each forearm from the shoulder to the wrist.
	for i in _arms.size():
		var wrist := to_local(_wrists[i].global_position)
		var from: Vector3 = _shoulders[i]
		var v := wrist - from
		var arm := _arms[i]
		(arm.mesh as CapsuleMesh).height = v.length() + 0.06
		var up := v.normalized()
		var side := up.cross(Vector3.BACK).normalized() if absf(up.z) < 0.99 else Vector3.RIGHT
		arm.transform = Transform3D(Basis(side, up, side.cross(up)), from + v * 0.5)
