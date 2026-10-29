class_name Hud
extends Control
## In-game HUD, touch controls and the pause / results overlays.
## Touch layout: left thumb steers (two zones), right thumb brakes.
## The car accelerates on its own.

signal menu_pressed
signal end_pressed
signal pause_pressed
signal resume_pressed
signal restart_pressed

const ACCENT := Color(1.0, 0.74, 0.18)
const FLOW_COL := Color(1.0, 0.42, 0.14)
const PANEL_BG := Color(0.05, 0.055, 0.065, 0.86)
const BOLD := preload("res://assets/fonts/BarlowSemiCondensed-Bold.ttf")
const MEDIUM := preload("res://assets/fonts/BarlowSemiCondensed-Medium.ttf")

var steer_axis := 0.0
var brake_held := false
var mph := false
var show_steer_buttons := true

var _score: Label
var _score_cap: Label
var _timer: Label
var _bonus: Label
var _mult: Label
var _dist: Label
var _speed: Label
var _speed_unit: Label
var _flow_bar: Control
var _flow := 0.0
var _flow_active := false
var _popup_root: Control
var _controls: Control
var _touches := {}  # index -> position
var _pause_panel: Control
var _results_panel: Control
var _results_body: VBoxContainer
var _pause_btn: Button
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
		var base := ACCENT if primary else Color(1, 1, 1, 0.1)
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
	_speed = _label(64)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_unit = _label(20, Color(1, 1, 1, 0.7), 4)
	_speed_unit.text = "KM/H"
	_speed_unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flow_bar = Control.new()
	_flow_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flow_bar.draw.connect(_draw_flow)
	_popup_root = Control.new()
	_popup_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls = Control.new()
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls.draw.connect(_draw_controls)
	_pause_btn = _button("II")
	_pause_btn.custom_minimum_size = Vector2(64, 64)
	_pause_btn.pressed.connect(func(): pause_pressed.emit())
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_timer = _label(40)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bonus = _label(24, ACCENT)
	_bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for n in [_controls, _score_cap, _score, _mult, _dist, _speed, _speed_unit, _flow_bar, _popup_root,
			_pause_btn, _timer, _bonus]:
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
	_dist.size = Vector2(300, 40)
	_dist.position = Vector2(s.end.x - 300 - 84, s.position.y + 8)
	_pause_btn.position = Vector2(s.end.x - 64, s.position.y)
	_flow_bar.size = Vector2(minf(420, s.size.x * 0.34), 46)
	_flow_bar.position = Vector2(vp.x * 0.5 - _flow_bar.size.x * 0.5, s.position.y + 4)
	_speed.size = Vector2(240, 70)
	_speed.position = Vector2(vp.x * 0.5 - 120, s.end.y - 98)
	_speed_unit.size = Vector2(240, 24)
	_speed_unit.position = Vector2(vp.x * 0.5 - 120, s.end.y - 28)
	_popup_root.size = vp
	_controls.size = vp
	_controls.queue_redraw()
	_timer.size = Vector2(300, 50)
	_timer.position = Vector2(vp.x * 0.5 - 150, s.position.y + 50)
	_bonus.size = Vector2(400, 30)
	_bonus.position = Vector2(vp.x * 0.5 - 200, s.position.y + 98)


# ---------------------------------------------------------------- touch

func _zones() -> Dictionary:
	var vp := get_viewport_rect().size
	var h := vp.y * 0.42
	var y := vp.y - h
	var w := minf(vp.x * 0.19, 260.0)
	return {
		"left": Rect2(0, y, _safe.position.x + w, h),
		"right": Rect2(_safe.position.x + w, y, w, h),
		"brake": Rect2(vp.x - _safe.position.x - w * 1.3, y, _safe.position.x + w * 1.3, h),
	}


func _input(event: InputEvent) -> void:
	if not _controls.visible:
		return
	if not show_steer_buttons:
		# Tilt steering: the whole right half brakes.
		if event is InputEventScreenTouch:
			var t := event as InputEventScreenTouch
			if t.pressed and t.position.x > get_viewport_rect().size.x * 0.5:
				_touches[t.index] = t.position
			else:
				_touches.erase(t.index)
			brake_held = not _touches.is_empty()
			_controls.queue_redraw()
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_touches[e.index] = e.position
		else:
			_touches.erase(e.index)
		_update_touch()
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		_touches[e.index] = e.position
		_update_touch()


func _update_touch() -> void:
	var z := _zones()
	var steer := 0.0
	var brake := false
	for p in _touches.values():
		if z["left"].has_point(p):
			steer -= 1.0
		elif z["right"].has_point(p):
			steer += 1.0
		elif z["brake"].has_point(p):
			brake = true
	steer_axis = clampf(steer, -1.0, 1.0)
	brake_held = brake
	_controls.queue_redraw()


func clear_touches() -> void:
	_touches.clear()
	steer_axis = 0.0
	brake_held = false


func _draw_controls() -> void:
	var z := _zones()
	var pad := 18.0
	var keys := [["left", steer_axis < 0.0, ""], ["right", steer_axis > 0.0, ""], ["brake", brake_held, "BRAKE"]]
	if not show_steer_buttons:
		keys = [["brake", brake_held, "BRAKE"]]
	for k in keys:
		var r: Rect2 = z[k[0]]
		var c := r.intersection(_safe.grow(10)).grow(-pad * 0.5)
		c.position.y += c.size.y * 0.3
		c.size.y *= 0.7
		var col := Color(1, 1, 1, 0.22 if k[1] else 0.09)
		_controls.draw_style_box(_rounded(col), c)
		var ink := Color(1, 1, 1, 0.75 if k[1] else 0.5)
		var m := c.get_center()
		if k[0] == "brake":
			var font := get_theme_default_font()
			var ts := font.get_string_size(k[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 30)
			_controls.draw_string(font, m + Vector2(-ts.x * 0.5, 30 * 0.35), k[2],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
		else:
			# Arrows are drawn, not typed: the UI font has no arrow glyphs.
			var d := -1.0 if k[0] == "left" else 1.0
			_controls.draw_colored_polygon(PackedVector2Array([
				m + Vector2(d * 16, 0), m + Vector2(-d * 11, -17), m + Vector2(-d * 11, 17)]), ink)


func _rounded(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(22)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(2)
	return sb


# ---------------------------------------------------------------- updates

func set_values(score: float, distance_m: float, speed_ms: float, flow: float,
		flow_active: bool, streak: int) -> void:
	_score.text = _fmt(int(score))
	_dist.text = "%.2f km" % (distance_m / 1000.0)
	_speed.text = str(int(round(speed_ms * (2.237 if mph else 3.6))))
	_speed_unit.text = "MPH" if mph else "KM/H"
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
