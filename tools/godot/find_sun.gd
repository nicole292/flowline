extends SceneTree
## Prints the brightest direction in an equirectangular HDR (the sun).
func _initialize() -> void:
	var img := Image.load_from_file(OS.get_cmdline_user_args()[0])
	img.resize(512, 256, Image.INTERPOLATE_BILINEAR)
	var best := 0.0
	var bp := Vector2i()
	for y in img.get_height() / 2:
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var l := c.r + c.g + c.b
			if l > best:
				best = l
				bp = Vector2i(x, y)
	var u := (bp.x + 0.5) / img.get_width()
	var v := (bp.y + 0.5) / img.get_height()
	print("SUN u=%.3f v=%.3f elevation=%.1f deg  azimuth(u*360)=%.1f deg  lum=%.1f" % [u, v, 90.0 - v * 180.0, u * 360.0, best])
	quit()
