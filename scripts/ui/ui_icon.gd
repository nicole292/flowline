class_name UiIcon
extends Control
## Small line icons drawn with shapes (the Barlow font has no symbol glyphs).
## Draws into its own rect, centred, at `icon_size`.

var icon := ""
var color := Color.WHITE
var icon_size := 28.0


static func make(name: String, size := 28.0, c := Color.WHITE) -> UiIcon:
	var i := UiIcon.new()
	i.icon = name
	i.icon_size = size
	i.color = c
	i.custom_minimum_size = Vector2(size, size)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _draw() -> void:
	var s := icon_size
	var o := size * 0.5 - Vector2(s, s) * 0.5   # top-left of the icon box
	var w := maxf(2.0, s * 0.1)                  # stroke width
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	match icon:
		"back":
			draw_polyline([p.call(0.6, 0.2), p.call(0.3, 0.5), p.call(0.6, 0.8)], color, w * 1.2, true)
		"next":
			draw_polyline([p.call(0.4, 0.2), p.call(0.7, 0.5), p.call(0.4, 0.8)], color, w * 1.2, true)
		"play":
			draw_colored_polygon([p.call(0.28, 0.16), p.call(0.84, 0.5), p.call(0.28, 0.84)], color)
		"car":
			draw_colored_polygon([p.call(0.06, 0.62), p.call(0.1, 0.46), p.call(0.28, 0.42), p.call(0.38, 0.26),
					p.call(0.68, 0.26), p.call(0.8, 0.42), p.call(0.94, 0.48), p.call(0.96, 0.62)], color)
			for x in [0.27, 0.75]:
				draw_circle(p.call(x, 0.66), s * 0.12, color)
		"flag":
			draw_line(p.call(0.24, 0.12), p.call(0.24, 0.9), color, w, true)
			draw_colored_polygon([p.call(0.24, 0.14), p.call(0.82, 0.3), p.call(0.24, 0.5)], color)
		"gear":
			var c: Vector2 = p.call(0.5, 0.5)
			for k in 8:
				var a := TAU * k / 8.0
				var d := Vector2.from_angle(a)
				var n := d.orthogonal()
				draw_colored_polygon([c + d * s * 0.28 + n * s * 0.08, c + d * s * 0.46 + n * s * 0.06,
						c + d * s * 0.46 - n * s * 0.06, c + d * s * 0.28 - n * s * 0.08], color)
			draw_arc(c, s * 0.24, 0.0, TAU, 32, color, s * 0.14, true)
		"check":
			draw_polyline([p.call(0.2, 0.52), p.call(0.42, 0.74), p.call(0.82, 0.28)], color, w * 1.3, true)
		"lock":
			draw_arc(p.call(0.5, 0.42), s * 0.18, PI, TAU, 16, color, w, true)
			draw_line(p.call(0.32, 0.42), p.call(0.32, 0.5), color, w)
			draw_line(p.call(0.68, 0.42), p.call(0.68, 0.5), color, w)
			draw_rect(Rect2(p.call(0.22, 0.48), Vector2(0.56, 0.4) * s), color)
		"moon":
			var pts := PackedVector2Array()
			var c: Vector2 = p.call(0.5, 0.5)
			for k in 25:  # outer arc, then the inner bite back the other way
				pts.append(c + Vector2.from_angle(lerpf(-2.3, 2.3, k / 24.0) + PI * 0.5) * s * 0.4)
			var b: Vector2 = c + Vector2(s * 0.2, -s * 0.14)
			for k in 25:
				pts.append(b + Vector2.from_angle(lerpf(2.6, -2.0, k / 24.0) + PI * 0.5) * s * 0.34)
			draw_colored_polygon(pts, color)
