extends SceneTree
## crop.gd -- <src> <dst> <x> <y> <size> <out_size>: square crop + resize.
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var img := Image.load_from_file(a[0])
	img = img.get_region(Rect2i(int(a[2]), int(a[3]), int(a[4]), int(a[4])))
	img.resize(int(a[5]), int(a[5]), Image.INTERPOLATE_LANCZOS)
	img.save_png(a[1])
	quit()
