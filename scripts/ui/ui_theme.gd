class_name UiTheme
extends RefCounted
## One visual language for every menu, in a light and a dark mode (Settings >
## Dark mode). Solid rounded cards with soft shadows, no hairline borders,
## segmented controls for choices, Barlow Semi Condensed throughout.

const MODES := {
	"light": {"panel": Color(0.985, 0.987, 0.992, 0.95), "soft": Color(0.985, 0.987, 0.992, 0.9),
		"well": Color(0.90, 0.915, 0.94), "ink": Color(0.07, 0.08, 0.11), "muted": Color(0.42, 0.45, 0.52),
		"accent_ink": Color(0.78, 0.42, 0.0), "fg": Color(0.07, 0.09, 0.16), "scrim": Color(0.97, 0.975, 0.985, 0.82),
		"good": Color(0.06, 0.58, 0.3), "bad": Color(0.86, 0.2, 0.18), "shadow": Color(0.05, 0.08, 0.15, 0.18)},
	"dark": {"panel": Color(0.105, 0.115, 0.14, 0.94), "soft": Color(0.105, 0.115, 0.14, 0.86),
		"well": Color(0.19, 0.2, 0.24), "ink": Color(0.96, 0.965, 0.975), "muted": Color(0.6, 0.63, 0.7),
		"accent_ink": Color(1.0, 0.74, 0.18), "fg": Color.WHITE, "scrim": Color(0.05, 0.055, 0.07, 0.85),
		"good": Color(0.32, 0.88, 0.55), "bad": Color(1.0, 0.42, 0.36), "shadow": Color(0, 0, 0, 0.35)},
}

const ACCENT := Color(1.0, 0.7, 0.12)
const ON_ACCENT := Color(0.1, 0.07, 0.02)

static var mode := "light"
static var PANEL: Color      # cards
static var PANEL_SOFT: Color # small pills over the scene
static var WELL: Color       # recessed tracks: segmented controls, bars, inputs
static var LINE: Color
static var INK: Color
static var MUTED: Color
static var AMBER: Color      # accent as text; fills use ACCENT
static var DARK_INK: Color
static var GOOD: Color
static var BAD: Color
static var SCRIM: Color
static var SHADOW: Color
static var FG: Color
const R := 18                # card corner radius; buttons use R - 4

const BOLD := preload("res://assets/fonts/BarlowSemiCondensed-Bold.ttf")
const SEMI := preload("res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf")
const MEDIUM := preload("res://assets/fonts/BarlowSemiCondensed-Medium.ttf")


## Switches between "light" and "dark". Anything else means light.
static func apply(name: String) -> void:
	if not MODES.has(name):
		name = "light"
	mode = name
	var p: Dictionary = MODES[name]
	PANEL = p["panel"]
	PANEL_SOFT = p["soft"]
	WELL = p["well"]
	INK = p["ink"]
	MUTED = p["muted"]
	AMBER = p["accent_ink"]
	DARK_INK = ON_ACCENT
	GOOD = p["good"]
	BAD = p["bad"]
	SCRIM = p["scrim"]
	SHADOW = p["shadow"]
	FG = p["fg"]
	LINE = tint(0.1)


static func dark() -> bool:
	return mode == "dark"


## The mode's foreground tone at a given strength: white on dark, navy on light.
static func tint(a: float) -> Color:
	return Color(FG.r, FG.g, FG.b, a)


static func _static_init() -> void:
	apply(mode)


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


## A raised surface: box() plus a soft drop shadow.
static func card(bg: Color, radius := R, pad := 22, lift := 1.0) -> StyleBoxFlat:
	var sb := box(bg, radius, Color(0, 0, 0, 0), 0, pad)
	sb.content_margin_top = pad * 0.8
	sb.content_margin_bottom = pad * 0.8
	sb.shadow_color = Color(SHADOW, SHADOW.a * lift)
	sb.shadow_size = int(16 * lift)
	sb.shadow_offset = Vector2(0, 6 * lift)
	return sb


static func make() -> Theme:
	var t := Theme.new()
	t.default_font = SEMI
	t.default_font_size = 22
	var br := R - 4

	# Plain button: a solid raised tile.
	var flat := Color(PANEL, 1.0) if not dark() else WELL
	t.set_stylebox("normal", "Button", card(flat, br, 18, 0.6))
	t.set_stylebox("hover", "Button", card(flat.lerp(FG, 0.05), br, 18, 0.8))
	t.set_stylebox("pressed", "Button", card(flat.lerp(FG, 0.1), br, 18, 0.2))
	t.set_stylebox("disabled", "Button", box(Color(flat, 0.55), br, Color(0, 0, 0, 0), 0, 18))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(INK, 0.35))
	t.set_color("icon_normal_color", "Button", INK)
	t.set_font("font", "Button", BOLD)
	t.set_font_size("font_size", "Button", 24)

	# Primary call to action: solid accent with a coloured glow.
	t.set_type_variation("PrimaryButton", "Button")
	var glow := func(c: Color, lift: float) -> StyleBoxFlat:
		var sb := card(c, br, 22, lift)
		sb.shadow_color = Color(ACCENT.darkened(0.3), 0.35 * lift)
		return sb
	t.set_stylebox("normal", "PrimaryButton", glow.call(ACCENT, 1.0))
	t.set_stylebox("hover", "PrimaryButton", glow.call(ACCENT.lightened(0.1), 1.2))
	t.set_stylebox("pressed", "PrimaryButton", glow.call(ACCENT.darkened(0.1), 0.3))
	t.set_stylebox("disabled", "PrimaryButton", box(WELL, br, Color(0, 0, 0, 0), 0, 22))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "PrimaryButton", ON_ACCENT)
	t.set_color("font_disabled_color", "PrimaryButton", Color(INK, 0.4))

	# Segments: options inside a recessed track (see Segment panel below).
	# The chosen one is a solid accent pill; the rest are bare text.
	t.set_type_variation("Chip", "Button")
	var none := box(Color(0, 0, 0, 0), br - 4, Color(0, 0, 0, 0), 0, 13)
	t.set_stylebox("normal", "Chip", none)
	t.set_stylebox("hover", "Chip", box(tint(0.06), br - 4, Color(0, 0, 0, 0), 0, 13))
	t.set_stylebox("pressed", "Chip", card(ACCENT, br - 4, 13, 0.35))
	t.set_stylebox("hover_pressed", "Chip", card(ACCENT, br - 4, 13, 0.35))
	t.set_stylebox("disabled", "Chip", none)
	t.set_color("font_color", "Chip", MUTED)
	t.set_color("font_hover_color", "Chip", INK)
	for c in ["font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "Chip", ON_ACCENT)
	t.set_color("font_disabled_color", "Chip", Color(MUTED, 0.45))
	t.set_font_size("font_size", "Chip", 19)
	t.set_type_variation("Segment", "PanelContainer")
	t.set_stylebox("panel", "Segment", box(WELL, br, Color(0, 0, 0, 0), 0, 4))

	# Round icon button (back).
	t.set_type_variation("IconButton", "Button")
	for s in ["normal", "hover", "pressed"]:
		var lift: float = {"normal": 0.6, "hover": 0.9, "pressed": 0.2}[s]
		t.set_stylebox(s, "IconButton", card(flat.lerp(FG, 0.05 if s == "hover" else 0.0), 28, 0, lift))

	# Compact button for in-row actions (upgrade prices).
	t.set_type_variation("SmallButton", "Button")
	for s in ["normal", "hover", "pressed", "disabled"]:
		var sb := (t.get_stylebox(s, "Button") as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		t.set_stylebox(s, "SmallButton", sb)

	t.set_stylebox("panel", "PanelContainer", card(PANEL, R + 6, 24))
	t.set_type_variation("SoftPanel", "PanelContainer")
	t.set_stylebox("panel", "SoftPanel", card(PANEL_SOFT, 28, 18, 0.6))
	# A row inside a card: a slightly recessed rounded strip.
	t.set_type_variation("Row", "PanelContainer")
	t.set_stylebox("panel", "Row", box(Color(WELL, 0.55), br, Color(0, 0, 0, 0), 0, 16))

	t.set_color("font_color", "Label", INK)
	t.set_type_variation("Muted", "Label")
	t.set_color("font_color", "Muted", MUTED)
	t.set_font("font", "Muted", MEDIUM)
	t.set_font_size("font_size", "Muted", 19)
	t.set_type_variation("Caption", "Label")
	t.set_color("font_color", "Caption", MUTED)
	t.set_font("font", "Caption", BOLD)
	t.set_font_size("font_size", "Caption", 15)
	t.set_type_variation("Heading", "Label")
	t.set_font("font", "Heading", BOLD)
	t.set_font_size("font_size", "Heading", 40)
	t.set_type_variation("Display", "Label")
	t.set_font("font", "Display", BOLD)
	t.set_font_size("font_size", "Display", 104)

	t.set_stylebox("background", "ProgressBar", box(WELL, 6, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 6, Color(0, 0, 0, 0), 0, 0))
	t.set_constant("show_percentage", "ProgressBar", 0)

	t.set_stylebox("slider", "HSlider", box(WELL, 6, Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT, 6, Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, 6, Color(0, 0, 0, 0), 0, 4))
	t.set_icon("grabber", "HSlider", _dot(30, Color.WHITE, true))
	t.set_icon("grabber_highlight", "HSlider", _dot(32, Color.WHITE, true))

	# Thin rounded scrollbar.
	t.set_stylebox("scroll", "VScrollBar", box(tint(0.06), 4, Color(0, 0, 0, 0), 0, 0))
	for g in ["grabber", "grabber_highlight", "grabber_pressed"]:
		t.set_stylebox(g, "VScrollBar", box(tint(0.3), 4, Color(0, 0, 0, 0), 0, 3))

	# On/off switch.
	t.set_icon("checked", "CheckButton", _switch(true))
	t.set_icon("unchecked", "CheckButton", _switch(false))
	t.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("hover_pressed", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	return t


## Antialiased disc; ringed gives it a faint edge so a white knob shows on white.
static func _dot(size: int, c: Color, ringed := false) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - 1.0 - d, 0.0, 1.0)
			var px := c
			if ringed and d > r - 3.0:
				px = c.darkened(0.25)
			img.set_pixel(x, y, Color(px.r, px.g, px.b, a))
	return ImageTexture.create_from_image(img)


static func _switch(on: bool) -> Texture2D:
	var w := 64
	var h := 36
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := ACCENT if on else WELL.darkened(0.08 if not dark() else -0.1)
	var rr := h * 0.5
	var knob := Vector2(w - rr if on else rr, rr)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var q := Vector2(clampf(p.x, rr, w - rr), rr)
			var a := clampf(rr - p.distance_to(q), 0.0, 1.0)
			var kd := p.distance_to(knob)
			var ka := clampf(rr - 3.0 - kd, 0.0, 1.0)
			var col := track.lerp(Color.WHITE, ka)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)


static func money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
