class_name UiTheme
extends RefCounted
## One visual language for every menu: dark smoked-glass panels over the
## live 3D scene, signal-amber accent, Barlow Semi Condensed.

const PANEL := Color(0.055, 0.062, 0.075, 0.9)
const PANEL_SOFT := Color(0.055, 0.062, 0.075, 0.72)
const LINE := Color(1, 1, 1, 0.12)
const INK := Color(0.95, 0.955, 0.96)
const MUTED := Color(0.63, 0.66, 0.70)
const AMBER := Color(1.0, 0.74, 0.18)
const DARK_INK := Color(0.07, 0.06, 0.03)
const GOOD := Color(0.30, 0.86, 0.52)
const BAD := Color(1.0, 0.38, 0.32)

const BOLD := preload("res://assets/fonts/BarlowSemiCondensed-Bold.ttf")
const SEMI := preload("res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf")
const MEDIUM := preload("res://assets/fonts/BarlowSemiCondensed-Medium.ttf")


static func box(bg: Color, radius := 10, border := Color(0, 0, 0, 0), bw := 0, pad := 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.55
	sb.content_margin_bottom = pad * 0.55
	sb.anti_aliasing = true
	return sb


static func make() -> Theme:
	var t := Theme.new()
	t.default_font = SEMI
	t.default_font_size = 22

	# Plain button: smoked glass with a hairline border.
	t.set_stylebox("normal", "Button", box(Color(1, 1, 1, 0.07), 10, LINE, 1, 18))
	t.set_stylebox("hover", "Button", box(Color(1, 1, 1, 0.12), 10, Color(1, 1, 1, 0.25), 1, 18))
	t.set_stylebox("pressed", "Button", box(Color(1, 1, 1, 0.18), 10, AMBER, 2, 18))
	t.set_stylebox("disabled", "Button", box(Color(1, 1, 1, 0.03), 10, Color(1, 1, 1, 0.06), 1, 18))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 10, Color(1, 1, 1, 0.45), 2, 18))
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_hover_pressed_color", "Button", INK)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	t.set_font("font", "Button", BOLD)
	t.set_font_size("font_size", "Button", 24)

	# Primary call to action: solid amber.
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", box(AMBER, 10, Color(0, 0, 0, 0), 0, 22))
	t.set_stylebox("hover", "PrimaryButton", box(AMBER.lightened(0.08), 10, Color(0, 0, 0, 0), 0, 22))
	t.set_stylebox("pressed", "PrimaryButton", box(AMBER.darkened(0.12), 10, Color(0, 0, 0, 0), 0, 22))
	t.set_stylebox("disabled", "PrimaryButton", box(Color(1, 1, 1, 0.08), 10, Color(0, 0, 0, 0), 0, 22))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "PrimaryButton", DARK_INK)
	t.set_color("font_disabled_color", "PrimaryButton", Color(1, 1, 1, 0.35))

	# Chips: toggle buttons for tabs and option groups.
	t.set_type_variation("Chip", "Button")
	t.set_stylebox("normal", "Chip", box(Color(1, 1, 1, 0.06), 20, LINE, 1, 16))
	t.set_stylebox("hover", "Chip", box(Color(1, 1, 1, 0.1), 20, Color(1, 1, 1, 0.22), 1, 16))
	t.set_stylebox("pressed", "Chip", box(Color(1.0, 0.74, 0.18, 0.16), 20, AMBER, 2, 16))
	t.set_stylebox("hover_pressed", "Chip", box(Color(1.0, 0.74, 0.18, 0.2), 20, AMBER, 2, 16))
	t.set_stylebox("disabled", "Chip", box(Color(1, 1, 1, 0.03), 20, Color(1, 1, 1, 0.05), 1, 16))
	t.set_font_size("font_size", "Chip", 20)

	t.set_stylebox("panel", "PanelContainer", box(PANEL, 16, LINE, 1, 22))
	t.set_type_variation("SoftPanel", "PanelContainer")
	t.set_stylebox("panel", "SoftPanel", box(PANEL_SOFT, 14, LINE, 1, 18))

	t.set_color("font_color", "Label", INK)
	t.set_type_variation("Muted", "Label")
	t.set_color("font_color", "Muted", MUTED)
	t.set_font("font", "Muted", MEDIUM)
	t.set_font_size("font_size", "Muted", 19)
	t.set_type_variation("Caption", "Label")
	t.set_color("font_color", "Caption", MUTED)
	t.set_font_size("font_size", "Caption", 15)
	t.set_type_variation("Heading", "Label")
	t.set_font("font", "Heading", BOLD)
	t.set_font_size("font_size", "Heading", 40)
	t.set_type_variation("Display", "Label")
	t.set_font("font", "Display", BOLD)
	t.set_font_size("font_size", "Display", 96)

	var bar_bg := box(Color(1, 1, 1, 0.1), 4, Color(0, 0, 0, 0), 0, 0)
	var bar_fill := box(AMBER, 4, Color(0, 0, 0, 0), 0, 0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_constant("show_percentage", "ProgressBar", 0)

	t.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.14), 4, Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("grabber_area", "HSlider", box(AMBER, 4, Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(AMBER, 4, Color(0, 0, 0, 0), 0, 3))
	t.set_icon("grabber", "HSlider", _dot(28, INK))
	t.set_icon("grabber_highlight", "HSlider", _dot(30, Color.WHITE))
	return t


static func _dot(size: int, c: Color) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(c.r, c.g, c.b, clampf(r - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
