class_name Hud
extends Control
## In-game HUD, touch controls and the pause / results overlays.
## Touch layout: left thumb steers with two arrow pads (a horn button sits
## above them), right thumb works the gas and brake pedals. A round
## speedometer sits above the pedals. The steering wheel ("wheel" mode) is
## parked for now: the settings no longer offer it.

signal menu_pressed
signal end_pressed
signal pause_pressed
signal camera_pressed
signal resume_pressed
signal restart_pressed

const ACCENT := Color(1.0, 0.74, 0.18)
const FLOW_COL := Color(1.0, 0.42, 0.14)
const PANEL_BG := Color(0.05, 0.055, 0.065, 0.86)
const BOLD := preload("res://assets/fonts/BarlowSemiCondensed-Bold.ttf")
const MEDIUM := preload("res://assets/fonts/BarlowSemiCondensed-Medium.ttf")

const WHEEL_LOCK := deg_to_rad(90.0)  ## wheel rotation for full steering lock

var _skip: Label   ## "tap to skip" under a wreck
var steer_axis := 0.0
var brake_held := false
var gas_held := false
var horn_held := false
var mph := false
var steer_mode := "buttons"   ## "buttons" (arrows) | "wheel" | "tilt" (GYRO, no steering on screen)
var auto_gas := false
## Keyboard / gyro steering, so the drawn wheel turns with them too.
var external_steer := 0.0

var _score: Label
var _score_cap: Label
var _timer: Label
var _bonus: Label
var _mult: Label
var _dist: Label
var _gauge: Control
var _gauge_speed := 0.0     ## m/s
var _gear := 1
var _flow_bar: Control
var _damage_bar: Control
var _damage := 0.0
var _flow := 0.0
var _flow_active := false
var _popup_root: Control
var _controls: Control
var _wheel_angle := 0.0    ## radians, positive = clockwise (steer right)
var _wheel_touch := -1
var _wheel_last := 0.0      ## angle of the wheel touch around the centre last event
var _drawn_external := 0.0
var _horn_touch := -1
var _arrow_touches := {}    # index -> -1 (left) | 1 (right)
var _pedal_touches := {}    # index -> "gas" | "brake"
var _pause_panel: Control
var _results_panel: Control
var _results_body: VBoxContainer
var _pause_btn: Button
var _cam_btn: Button
var _safe := Rect2()
var _gameplay_nodes: Array[Control] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_set_gameplay_visible(false)


# ---------------------------------------------------------------- building

func _label(size: int, color := Color.WHITE, outline := 6, bold := true) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", BOLD if bold else MEDIUM)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 72)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_font_override("font", BOLD)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		var base := ACCENT if primary else Color(0.06, 0.07, 0.09, 0.55)  # readable over bright sky too
		if not primary:
			sb.border_color = Color(1, 1, 1, 0.25)
			sb.set_border_width_all(1)
		sb.bg_color = base.darkened(0.15) if state == "pressed" else base
		if state == "focus":
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = Color(1, 1, 1, 0.5)
			sb.set_border_width_all(2)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color(0.02, 0.06, 0.08) if primary else Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color(0.02, 0.06, 0.08) if primary else Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(0.02, 0.06, 0.08) if primary else Color.WHITE)
	return b


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 48
	sb.content_margin_right = 48
	sb.content_margin_top = 36
	sb.content_margin_bottom = 36
	p.add_theme_stylebox_override("panel", sb)
	return p


func _build() -> void:
	_score_cap = _label(17, Color(1, 1, 1, 0.65), 3, false)
	_score_cap.text = "SCORE"
	_score = _label(48)
	_mult = _label(24, FLOW_COL)
	_dist = _label(30)
	_dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gauge = Control.new()
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge.draw.connect(_draw_gauge)
	_flow_bar = Control.new()
	_flow_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flow_bar.draw.connect(_draw_flow)
	_damage_bar = Control.new()
	_damage_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_bar.draw.connect(_draw_damage)
	_popup_root = Control.new()
	_popup_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls = Control.new()
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls.draw.connect(_draw_controls)
	_pause_btn = _button("II")
	_pause_btn.custom_minimum_size = Vector2(64, 64)
	_pause_btn.pressed.connect(func(): pause_pressed.emit())
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_cam_btn = _button("")
	_cam_btn.custom_minimum_size = Vector2(64, 64)
	_cam_btn.pressed.connect(func(): camera_pressed.emit())
	_cam_btn.focus_mode = Control.FOCUS_NONE
	_cam_btn.draw.connect(_draw_camera_icon)
	_timer = _label(40)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bonus = _label(24, ACCENT)
	_bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for n in [_controls, _score_cap, _score, _mult, _dist, _gauge, _flow_bar, _damage_bar, _popup_root,
			_pause_btn, _cam_btn, _timer, _bonus]:
		add_child(n)
		_gameplay_nodes.append(n)

	# Pause overlay
	_pause_panel = _make_center_panel("PAUSED", [
		["RESUME", true, func(): resume_pressed.emit()],
		["END RUN", false, func(): end_pressed.emit()],
		["RESTART", false, func(): restart_pressed.emit()],
		["MENU", false, func(): menu_pressed.emit()]])
	# Results overlay
	_results_panel = _make_center_panel("", [["DRIVE AGAIN", true, func(): restart_pressed.emit()],
		["MENU", false, func(): menu_pressed.emit()]], true)
	_results_body = _results_panel.find_child("Body", true, false)


func _make_center_panel(title: String, buttons: Array, side_by_side := false) -> Control:
	var root := CenterContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(shade)
	holder.add_child(root)
	var p := _panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	if title != "":
		var t := _label(54)
		t.text = title
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(t)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 6)
	box.add_child(body)
	var holder_row: BoxContainer = HBoxContainer.new() if side_by_side else box
	if side_by_side:
		holder_row.add_theme_constant_override("separation", 14)
		holder_row.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_child(holder_row)
	for spec in buttons:
		var b := _button(spec[0], spec[1])
		if side_by_side:
			b.custom_minimum_size = Vector2(230, 66)
		b.pressed.connect(spec[2])
		holder_row.add_child(b)
	p.add_child(box)
	root.add_child(p)
	holder.visible = false
	add_child(holder)
	return holder


func _layout() -> void:
	var vp := get_viewport_rect().size
	# Respect notches / rounded corners on phones.
	var safe := Rect2(Vector2.ZERO, vp)
	if OS.has_feature("mobile"):
		var ds := Rect2(DisplayServer.get_display_safe_area())
		var scr := Vector2(DisplayServer.screen_get_size())
		if scr.x > 0:
			var k := vp / scr
			safe = Rect2(ds.position * k, ds.size * k)
	var m := 28.0
	_safe = safe.grow(-m)
	# Sized explicitly (anchors are reset to top-left so Godot doesn't fight us).
	for n in [self, _pause_panel, _results_panel]:
		n.set_anchors_preset(Control.PRESET_TOP_LEFT)
		n.position = Vector2.ZERO
		n.size = vp
		for c in n.get_children():
			if n != self and (c is ColorRect or c is Container):
				(c as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
				(c as Control).position = Vector2.ZERO
				(c as Control).size = vp
	var s := _safe
	_score_cap.position = s.position + Vector2(2, -6)
	_score.position = s.position + Vector2(0, 10)
	_mult.position = s.position + Vector2(2, 66)
	_damage_bar.size = Vector2(190, 22)
	_damage_bar.position = s.position + Vector2(2, 100)
	_dist.size = Vector2(300, 40)
	_dist.position = Vector2(s.end.x - 300 - 160, s.position.y + 8)
	_pause_btn.position = Vector2(s.end.x - 64, s.position.y)
	_cam_btn.position = Vector2(s.end.x - 64 - 76, s.position.y)
	_flow_bar.size = Vector2(minf(420, s.size.x * 0.34), 46)
	_flow_bar.position = Vector2(vp.x * 0.5 - _flow_bar.size.x * 0.5, s.position.y + 4)
	var gr := _gauge_radius()
	_gauge.size = Vector2(gr * 2.0, gr * 2.0)
	_gauge.position = _gauge_center() - Vector2(gr, gr)
	_gauge.queue_redraw()
	_popup_root.size = vp
	_controls.size = vp
	_controls.queue_redraw()
	_timer.size = Vector2(300, 50)
	_timer.position = Vector2(vp.x * 0.5 - 150, s.position.y + 50)
	_bonus.size = Vector2(400, 30)
	_bonus.position = Vector2(vp.x * 0.5 - 200, s.position.y + 98)


## Camera glyph for the view button (the UI font has no icons).
func _draw_camera_icon() -> void:
	var c := _cam_btn.size * 0.5
	var ink := Color(1, 1, 1, 0.9)
	var body := StyleBoxFlat.new()
	body.bg_color = ink
	body.set_corner_radius_all(4)
	_cam_btn.draw_style_box(body, Rect2(c + Vector2(-17, -10), Vector2(34, 23)))
	_cam_btn.draw_rect(Rect2(c + Vector2(-7, -15), Vector2(14, 6)), ink)
	_cam_btn.draw_circle(c + Vector2(0, 1.5), 7.5, Color(0.1, 0.1, 0.12))
	_cam_btn.draw_circle(c + Vector2(0, 1.5), 4.0, ink)


# ---------------------------------------------------------------- touch

## Layout scale: 1.0 on a 720 px tall viewport.
## Size of drawn controls relative to the 720-high design. Includes the
## phone UI scale, so the wheel, arrows and pedals grow with the rest of the UI.
## HUD size factor. Sized by height on phones; on squarer screens (iPads,
## tablets) by a 16:9 share of the width instead, so the wheel, pedals and
## speedometer don't grow to cover the road.
func _k() -> float:
	var vp := get_viewport_rect().size
	return minf(vp.y, vp.x * 9.0 / 16.0) * get_tree().root.content_scale_factor / 720.0


func _wheel_radius() -> float:
	return minf(get_viewport_rect().size.y * 0.22, 137.0 * _k())


func _wheel_center() -> Vector2:
	var r := _wheel_radius()
	return Vector2(_safe.position.x + r + 6.0, _safe.end.y - r + 4.0)


func _arrow_rects() -> Dictionary:
	var k := _k()
	var w := 128.0 * k
	var h := 150.0 * k
	var left := Rect2(_safe.position.x, _safe.end.y - h, w, h)
	var right := Rect2(left.end.x + 16.0 * k, left.position.y, w, h)
	return {"left": left, "right": right}


func _horn_center() -> Vector2:
	var a := _arrow_rects()
	return Vector2((a["left"].end.x + a["right"].position.x) * 0.5, a["left"].position.y - 52.0 * _k())


func _horn_radius() -> float:
	return 30.0 * _k()


## Which arrow a touch lands on: generous, the whole lower-left area counts
## and the gap between the pads is split down the middle.
func _arrow_at(p: Vector2) -> int:
	var vp := get_viewport_rect().size
	var a := _arrow_rects()
	if p.y < vp.y * 0.45 or p.x > a["right"].end.x + 60.0 * _k():
		return 0
	return -1 if p.x < (a["left"].end.x + a["right"].position.x) * 0.5 else 1


func _update_arrow_steer() -> void:
	var v := 0
	for d in _arrow_touches.values():
		v += d
	steer_axis = float(clampi(v, -1, 1))


func _pedal_rects() -> Dictionary:
	var k := _k()
	var gas := Rect2(_safe.end.x - 82 * k, _safe.end.y - 168 * k, 82 * k, 168 * k)
	var brake: Rect2
	if steer_mode == "tilt":  # GYRO, Traffic Racer style: brake bottom-left, gas bottom-right
		brake = Rect2(_safe.position.x, _safe.end.y - 118 * k, 150 * k, 118 * k)
	elif auto_gas:
		brake = Rect2(_safe.end.x - 150 * k, _safe.end.y - 118 * k, 150 * k, 118 * k)
	else:
		brake = Rect2(gas.position.x - 158 * k, _safe.end.y - 112 * k, 132 * k, 112 * k)
	return {"gas": gas, "brake": brake}


func _gauge_radius() -> float:
	return 84.0 * _k()


func _gauge_center() -> Vector2:
	var r := _gauge_radius()
	var top := minf(_pedal_rects()["gas"].position.y, _pedal_rects()["brake"].position.y)
	return Vector2(_safe.end.x - r - 4.0 * _k(), top - r - 34.0 * _k())


## Which pedal a touch lands on. The zones are generous: a thumb near a
## pedal counts, and the space between them is split down the middle.
func _pedal_at(p: Vector2) -> String:
	var vp := get_viewport_rect().size
	if p.y < vp.y * 0.45:
		return ""
	var r := _pedal_rects()
	var gas: Rect2 = r["gas"]
	var brake: Rect2 = r["brake"]
	if steer_mode == "tilt":  # GYRO: the whole lower half is two big pedals
		if p.x < vp.x * 0.5:
			return "brake"
		return "" if auto_gas else "gas"
	if auto_gas:
		return "brake" if p.x > brake.position.x - 90.0 * _k() else ""
	if p.x >= (brake.end.x + gas.position.x) * 0.5:
		return "gas"
	if p.x >= brake.position.x - 70.0 * _k():
		return "brake"
	return ""


func _wheel_hit(p: Vector2) -> String:
	if steer_mode == "buttons":
		return "horn" if p.distance_to(_horn_center()) < _horn_radius() * 1.3 else ""
	if steer_mode != "wheel":
		return ""
	var r := _wheel_radius()
	var d := p.distance_to(_wheel_center())
	if d < r * 0.27:
		return "horn"
	var vp := get_viewport_rect().size
	if d < r * 1.6 or (p.x < vp.x * 0.4 and p.y > vp.y * 0.4):
		return "wheel"
	return ""


func _input(event: InputEvent) -> void:
	if not _controls.visible:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_press(e.index, e.position)
		else:
			_release(e.index)
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		if e.index == _wheel_touch:
			_turn_wheel(e.position)
		elif _arrow_touches.has(e.index):
			var d := _arrow_at(e.position)
			if d != 0:
				_arrow_touches[e.index] = d  # thumb slid across to the other arrow
		elif _pedal_touches.has(e.index):
			var pedal := _pedal_at(e.position)
			if pedal != "":
				_pedal_touches[e.index] = pedal  # thumb slid across to the other pedal
	else:
		return
	gas_held = _pedal_touches.values().has("gas")
	brake_held = _pedal_touches.values().has("brake")
	horn_held = _horn_touch != -1
	if steer_mode == "buttons":
		_update_arrow_steer()
	_controls.queue_redraw()


func _press(index: int, p: Vector2) -> void:
	var hit := _wheel_hit(p)
	if hit == "horn" and _horn_touch == -1:
		_horn_touch = index
	elif hit == "wheel" and _wheel_touch == -1:
		_wheel_touch = index
		_wheel_last = (p - _wheel_center()).angle()
	elif steer_mode == "buttons" and _arrow_at(p) != 0:
		_arrow_touches[index] = _arrow_at(p)
	else:
		var pedal := _pedal_at(p)
		if pedal != "":
			_pedal_touches[index] = pedal


func _release(index: int) -> void:
	if index == _wheel_touch:
		_wheel_touch = -1
	if index == _horn_touch:
		_horn_touch = -1
	_arrow_touches.erase(index)
	_pedal_touches.erase(index)


## The wheel turns by how far the thumb travels around its centre, so it
## can be grabbed anywhere on the rim and never jumps.
func _turn_wheel(p: Vector2) -> void:
	var v := p - _wheel_center()
	var a := v.angle()
	if v.length() > _wheel_radius() * 0.2:  # too close to the hub to read an angle
		_wheel_angle = clampf(_wheel_angle + wrapf(a - _wheel_last, -PI, PI), -WHEEL_LOCK, WHEEL_LOCK)
	_wheel_last = a


func _process(dt: float) -> void:
	if not _controls.visible or get_tree().paused:
		return
	if steer_mode != "wheel":
		if external_steer != _drawn_external:  # keyboard / gyro lights the arrows
			_drawn_external = external_steer
			_controls.queue_redraw()
		return
	var before := _wheel_angle
	if _wheel_touch == -1 and _wheel_angle != 0.0:
		# Self-centring, like a real wheel when you loosen your grip.
		_wheel_angle *= exp(-10.0 * dt)
		if absf(_wheel_angle) < 0.002:
			_wheel_angle = 0.0
	var a := _wheel_angle / WHEEL_LOCK
	if absf(a) < 0.03:
		a = 0.0
	# Linear: the car turns as soon as the wheel does.
	steer_axis = a
	if before != _wheel_angle or external_steer != _drawn_external:
		_drawn_external = external_steer
		_controls.queue_redraw()


func set_controls(steer: String, auto: bool) -> void:
	steer_mode = steer
	auto_gas = auto
	if is_node_ready():
		clear_touches()
		_layout()


func clear_touches() -> void:
	_wheel_touch = -1
	_horn_touch = -1
	_arrow_touches.clear()
	_pedal_touches.clear()
	_wheel_angle = 0.0
	steer_axis = 0.0
	brake_held = false
	gas_held = false
	horn_held = false


func _draw_controls() -> void:
	if steer_mode == "wheel":
		_draw_wheel()
	elif steer_mode == "buttons":
		_draw_arrows()
	var r := _pedal_rects()
	if not auto_gas:
		_draw_pedal(r["gas"], gas_held, "GAS", 7)
	_draw_pedal(r["brake"], brake_held, "BRAKE", 4)


func _draw_wheel() -> void:
	var ci := _controls
	var r := _wheel_radius()
	var held := _wheel_touch != -1
	var ang := clampf(_wheel_angle + external_steer * WHEEL_LOCK, -WHEEL_LOCK, WHEEL_LOCK)
	var a := 0.92 if held else 0.74
	var rim_r := r * 0.86
	var rim_w := r * 0.2
	ci.draw_set_transform(_wheel_center(), ang, Vector2.ONE)
	ci.draw_circle(Vector2(0, 5), r * 0.98, Color(0, 0, 0, 0.16))
	# Three spokes: a dark edge with a brushed-metal face.
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
		var n := Vector2(-dir.y, dir.x)
		var w0 := r * (0.17 if dir != Vector2.DOWN else 0.13)
		var w1 := r * (0.10 if dir != Vector2.DOWN else 0.08)
		ci.draw_colored_polygon(PackedVector2Array([dir * r * 0.2 + n * w0, dir * rim_r + n * w1,
				dir * rim_r - n * w1, dir * r * 0.2 - n * w0]), Color(0.16, 0.17, 0.19, a))
		ci.draw_colored_polygon(PackedVector2Array([dir * r * 0.24 + n * w0 * 0.7,
				dir * (rim_r - rim_w * 0.45) + n * w1 * 0.55, dir * (rim_r - rim_w * 0.45) - n * w1 * 0.55,
				dir * r * 0.24 - n * w0 * 0.7]), Color(0.58, 0.6, 0.64, a))
	# Leather rim, thicker grips at nine and three, a highlight and a top marker.
	ci.draw_arc(Vector2.ZERO, rim_r, 0.0, TAU, 72, Color(0.07, 0.07, 0.08, a), rim_w, true)
	for g in [0.0, PI]:
		ci.draw_arc(Vector2.ZERO, rim_r, g - 0.55, g + 0.55, 24, Color(0.14, 0.14, 0.155, a), rim_w * 1.18, true)
	# Rounded leather: a darker outer edge, an inner shadow, and the stitched seam.
	ci.draw_arc(Vector2.ZERO, rim_r + rim_w * 0.42, 0.0, TAU, 72, Color(0, 0, 0, 0.35 * a), rim_w * 0.16, true)
	ci.draw_arc(Vector2.ZERO, rim_r - rim_w * 0.42, 0.0, TAU, 72, Color(0, 0, 0, 0.25 * a), rim_w * 0.16, true)
	for i in 64:
		var t := TAU * i / 64.0
		ci.draw_arc(Vector2.ZERO, rim_r - rim_w * 0.18, t, t + TAU / 160.0, 2, Color(0.42, 0.42, 0.45, 0.8 * a), 1.2, true)
	ci.draw_arc(Vector2.ZERO, rim_r + rim_w * 0.3, PI * 1.08, PI * 1.62, 24, Color(1, 1, 1, 0.18 * a), 2.0, true)
	ci.draw_arc(Vector2.ZERO, rim_r, -PI * 0.5 - 0.085, -PI * 0.5 + 0.085, 6, Color(ACCENT, a), rim_w * 1.02, true)
	# Hub = horn.
	var hub := r * 0.27
	ci.draw_circle(Vector2.ZERO, hub, Color(0.1, 0.1, 0.11, a))
	ci.draw_arc(Vector2.ZERO, hub, 0.0, TAU, 40, Color(0.55, 0.57, 0.61, a), 2.0, true)
	_draw_horn_icon(hub * 0.62, Color(ACCENT, 1.0) if horn_held else Color(1, 1, 1, 0.6))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_arrows() -> void:
	var ci := _controls
	var k := _k()
	var a := _arrow_rects()
	for d: int in [-1, 1]:
		var r: Rect2 = a["left"] if d < 0 else a["right"]
		var on: bool = steer_axis * d > 0.0 or external_steer * d > 0.3
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.24 if on else 0.1)
		sb.set_corner_radius_all(int(22 * k))
		sb.border_color = Color(1, 1, 1, 0.22)
		sb.set_border_width_all(2)
		ci.draw_style_box(sb, r)
		# Arrows are drawn, not typed: the UI font has no arrow glyphs.
		var m := r.get_center()
		var s := 22.0 * k
		ci.draw_colored_polygon(PackedVector2Array([m + Vector2(d * s, 0), m + Vector2(-d * s * 0.7, -s),
				m + Vector2(-d * s * 0.7, s)]), Color(1, 1, 1, 0.85 if on else 0.55))
	# Horn button above the arrows.
	var hc := _horn_center()
	var hr := _horn_radius()
	ci.draw_circle(hc, hr, Color(0.06, 0.07, 0.09, 0.6 if horn_held else 0.4))
	ci.draw_arc(hc, hr, 0.0, TAU, 32, Color(1, 1, 1, 0.25), 2.0, true)
	ci.draw_set_transform(hc, 0.0, Vector2.ONE)
	_draw_horn_icon(hr * 0.75, Color(ACCENT, 1.0) if horn_held else Color(1, 1, 1, 0.7))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_horn_icon(s: float, col: Color) -> void:
	var ci := _controls
	var o := Vector2(-s * 0.2, 0)
	ci.draw_rect(Rect2(o + Vector2(-s * 0.75, -s * 0.16), Vector2(s * 0.45, s * 0.32)), col)
	ci.draw_colored_polygon(PackedVector2Array([o + Vector2(-s * 0.32, -s * 0.16), o + Vector2(s * 0.45, -s * 0.6),
			o + Vector2(s * 0.45, s * 0.6), o + Vector2(-s * 0.32, s * 0.16)]), col)
	if horn_held:
		for i in 2:
			ci.draw_arc(o + Vector2(s * 0.45, 0), s * (0.35 + 0.3 * i), -0.7, 0.7, 10, col, 2.0, true)


func _draw_pedal(rect: Rect2, pressed: bool, label: String, ribs: int) -> void:
	var ci := _controls
	var k := _k()
	var r := rect
	if pressed:  # pushed in: a touch smaller and lower
		r = r.grow(-r.size.x * 0.04)
		r.position.y += r.size.y * 0.03
	var corner := int(14 * k)
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.25)
	shadow.set_corner_radius_all(corner)
	ci.draw_style_box(shadow, Rect2(r.position + Vector2(0, 5 * k), r.size))
	var face := StyleBoxFlat.new()
	face.set_corner_radius_all(corner)
	face.bg_color = Color(0.45, 0.47, 0.51, 0.9) if pressed else Color(0.66, 0.68, 0.72, 0.8)
	face.border_color = Color(0.14, 0.15, 0.17, 0.9)
	face.set_border_width_all(maxi(2, int(3 * k)))
	ci.draw_style_box(face, r)
	# Rubber ribs.
	var inner := r.grow(-minf(r.size.x, r.size.y) * 0.16)
	var bh := inner.size.y / float(ribs * 2 - 1)
	var rib := StyleBoxFlat.new()
	rib.bg_color = Color(0.09, 0.09, 0.1, 0.92)
	rib.set_corner_radius_all(int(bh * 0.5))
	for i in ribs:
		ci.draw_style_box(rib, Rect2(inner.position + Vector2(0, i * 2 * bh), Vector2(inner.size.x, bh)))
	var font := BOLD
	var fs := int(16 * k)
	var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var at := Vector2(rect.get_center().x - ts.x * 0.5, rect.position.y - 8 * k)
	ci.draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.45))
	ci.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(1, 1, 1, 0.9 if pressed else 0.6))


## Round speedometer: needle, lit arc, red zone, digital readout and gear.
func _draw_gauge() -> void:
	var g := _gauge
	var r := _gauge_radius()
	var k := _k()
	var c := Vector2(r, r)
	var unit := 2.237 if mph else 3.6
	var max_v := 180.0 if mph else 280.0
	var major := 20.0 if mph else 40.0
	var a0 := PI * 0.75
	var sweep := PI * 1.5
	g.draw_circle(c, r, Color(0.03, 0.035, 0.045, 0.78))
	g.draw_arc(c, r - 1.5, 0.0, TAU, 64, Color(1, 1, 1, 0.22), 2.0, true)
	g.draw_arc(c, r * 0.86, a0 + sweep * 0.86, a0 + sweep, 16, Color(0.95, 0.22, 0.16, 0.85), 4.0 * k, true)
	var v := 0.0
	while v <= max_v + 0.1:
		var dir := Vector2.from_angle(a0 + sweep * v / max_v)
		var is_major := is_zero_approx(fmod(v, major))
		var tick := r * (0.15 if is_major else 0.07)
		g.draw_line(c + dir * (r * 0.92 - tick), c + dir * r * 0.92,
				Color(1, 1, 1, 0.9 if is_major else 0.45), (2.5 if is_major else 1.5) * k, true)
		if is_major:
			var txt := str(int(v))
			var fs := int(13 * k)
			var ts := BOLD.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			g.draw_string(BOLD, c + dir * r * 0.62 + Vector2(-ts.x * 0.5, fs * 0.35), txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.75))
		v += 10.0
	var cur := _gauge_speed * unit
	var t := clampf(cur / max_v, 0.0, 1.0)
	if t > 0.002:
		g.draw_arc(c, r * 0.955, a0, a0 + sweep * t, 48, Color(ACCENT, 0.95), 3.0 * k, true)
	# Gear indicator.
	var gear_txt := str(_gear)
	var gfs := int(17 * k)
	var gs := BOLD.get_string_size(gear_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, gfs)
	var gbox := StyleBoxFlat.new()
	gbox.bg_color = Color(1, 1, 1, 0.1)
	gbox.set_corner_radius_all(int(4 * k))
	g.draw_style_box(gbox, Rect2(c + Vector2(-11 * k, -r * 0.32 - 11 * k), Vector2(22 * k, 22 * k)))
	g.draw_string(BOLD, c + Vector2(-gs.x * 0.5, -r * 0.32 + gfs * 0.36), gear_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, gfs, ACCENT)
	# Digital readout.
	var num := str(int(round(cur)))
	var nfs := int(30 * k)
	var ns := BOLD.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs)
	g.draw_string(BOLD, c + Vector2(-ns.x * 0.5, r * 0.5 + nfs * 0.36), num, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs)
	var u := "MPH" if mph else "KM/H"
	var ufs := int(11 * k)
	var us := MEDIUM.get_string_size(u, HORIZONTAL_ALIGNMENT_LEFT, -1, ufs)
	g.draw_string(MEDIUM, c + Vector2(-us.x * 0.5, r * 0.76 + ufs * 0.36), u, HORIZONTAL_ALIGNMENT_LEFT, -1, ufs,
			Color(1, 1, 1, 0.65))
	# Needle.
	var nd := Vector2.from_angle(a0 + sweep * t)
	var needle := Color(1.0, 0.36, 0.2)
	g.draw_line(c - nd * r * 0.12, c + nd * r * 0.82, needle, 3.5 * k, true)
	g.draw_circle(c, r * 0.09, Color(0.16, 0.16, 0.18))
	g.draw_arc(c, r * 0.09, 0.0, TAU, 20, needle, 2.0, true)


# ---------------------------------------------------------------- updates

func set_values(score: float, distance_m: float, speed_ms: float, flow: float,
		flow_active: bool, streak: int, gear := 1) -> void:
	_score.text = _fmt(int(score))
	_dist.text = "%.2f km" % (distance_m / 1000.0)
	if absf(speed_ms - _gauge_speed) > 0.03 or gear != _gear:
		_gauge_speed = speed_ms
		_gear = gear
		_gauge.queue_redraw()
	if flow_active:
		_mult.text = "FLOW DRIVE  x2"
	elif streak > 1:
		_mult.text = "STREAK x%d" % streak
	else:
		_mult.text = ""
	if absf(flow - _flow) > 0.002 or flow_active != _flow_active:
		_flow = flow
		_flow_active = flow_active
		_flow_bar.queue_redraw()


## Car condition, 0 = like new, 1 = wrecked.
func set_damage(d: float) -> void:
	if absf(d - _damage) > 0.001:
		_damage = d
		_damage_bar.queue_redraw()


## Condition bar under the score: green when healthy, red near a wreck.
func _draw_damage() -> void:
	var sz := _damage_bar.size
	var font := BOLD
	var label := "CAR"
	_damage_bar.draw_string_outline(font, Vector2(0, 17), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 3,
			Color(0, 0, 0, 0.45))
	_damage_bar.draw_string(font, Vector2(0, 17), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, 0.75))
	var bar := Rect2(40, 6, sz.x - 40, 12)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(6)
	_damage_bar.draw_style_box(bg, bar)
	var health := clampf(1.0 - _damage, 0.0, 1.0)
	if health > 0.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.95, 0.3, 0.25) if health < 0.35 else (ACCENT if health < 0.7 else Color(0.45, 0.9, 0.55))
		fill.set_corner_radius_all(6)
		_damage_bar.draw_style_box(fill, Rect2(bar.position, Vector2(maxf(12.0, bar.size.x * health), bar.size.y)))


static func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _draw_flow() -> void:
	var sz := _flow_bar.size
	var bar := Rect2(0, 22, sz.x, 14)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(7)
	_flow_bar.draw_style_box(bg, bar)
	if _flow > 0.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = FLOW_COL if _flow_active else ACCENT
		fill.set_corner_radius_all(7)
		_flow_bar.draw_style_box(fill, Rect2(bar.position, Vector2(maxf(14.0, bar.size.x * _flow), bar.size.y)))
	var font := get_theme_default_font()
	var label := "FLOW DRIVE" if _flow_active else "FLOW"
	var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	_flow_bar.draw_string_outline(font, Vector2(sz.x * 0.5 - ts.x * 0.5, 16), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0, 0.5))
	_flow_bar.draw_string(font, Vector2(sz.x * 0.5 - ts.x * 0.5, 16), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, FLOW_COL if _flow_active else Color(1, 1, 1, 0.85))


func popup(text: String, sub: String, color: Color, big := false) -> void:
	var vp := get_viewport_rect().size
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := _label(54 if big else 40, color, 8)
	a.text = text
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(a)
	if sub != "":
		var b := _label(30, Color.WHITE, 6)
		b.text = sub
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(b)
	box.size = Vector2(vp.x, 120)
	box.position = Vector2(0, vp.y * 0.24)
	box.pivot_offset = Vector2(vp.x * 0.5, 40)
	box.scale = Vector2(0.6, 0.6)
	# Only the newest popup stays readable.
	for c in _popup_root.get_children():
		c.queue_free()
	_popup_root.add_child(box)
	var tw := box.create_tween()
	tw.tween_property(box, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.55)
	tw.parallel().tween_property(box, "position:y", box.position.y - 30, 0.9).set_delay(0.55)
	tw.tween_property(box, "modulate:a", 0.0, 0.3)
	tw.tween_callback(box.queue_free)


# ---------------------------------------------------------------- screens

func _set_gameplay_visible(v: bool) -> void:
	for n in _gameplay_nodes:
		n.visible = v
	if _skip:
		_skip.visible = false


## Time Trial clock; pass seconds < 0 to hide it.
func set_timer(seconds: float, next_km: float) -> void:
	_timer.visible = seconds >= 0.0
	if seconds >= 0.0:
		_timer.text = "%d:%04.1f   ·   CHECKPOINT %.1f KM" % [int(seconds) / 60, fmod(seconds, 60.0), next_km]
		_timer.add_theme_color_override("font_color", Color(1, 0.4, 0.3) if seconds < 10.0 else Color.WHITE)


func set_bonus(text: String) -> void:
	_bonus.text = text


func hide_all() -> void:
	_set_gameplay_visible(false)
	_pause_panel.visible = false
	_results_panel.visible = false


func show_playing() -> void:
	_set_gameplay_visible(true)
	_pause_panel.visible = false
	_results_panel.visible = false
	clear_touches()


## During a wreck: only the score and the popups stay on screen.
func show_crash() -> void:
	clear_touches()
	for n in [_controls, _gauge, _flow_bar, _mult, _damage_bar]:
		n.visible = false
	if _skip == null:
		_skip = _label(20, Color(1, 1, 1, 0.85), 6)
		_skip.text = "TAP TO SKIP"
		_skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_skip)
	var vp := get_viewport_rect().size
	_skip.position = Vector2(0, vp.y - 70)
	_skip.size = Vector2(vp.x, 30)
	_skip.visible = true
	_skip.modulate.a = 0.0
	create_tween().tween_property(_skip, "modulate:a", 1.0, 0.4).set_delay(0.5)


func show_pause(on: bool) -> void:
	_pause_panel.visible = on
	_controls.visible = not on
	clear_touches()


func show_results(stats: Array, headline: String, extras: Array = []) -> void:
	_set_gameplay_visible(false)
	for c in _results_body.get_children():
		c.queue_free()
	var h := _label(46, ACCENT)
	h.text = headline
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_body.add_child(h)
	for row in stats:
		var line := HBoxContainer.new()
		line.custom_minimum_size = Vector2(440, 0)
		var k := _label(23, Color(1, 1, 1, 0.7), 0, false)
		k.text = row[0]
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := _label(23, Color.WHITE, 0)
		v.text = row[1]
		line.add_child(k)
		line.add_child(v)
		_results_body.add_child(line)
	for e in extras:
		var x := _label(22, e[1], 0)
		x.text = e[0]
		x.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_results_body.add_child(x)
	_results_panel.visible = true
