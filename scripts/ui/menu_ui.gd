class_name MenuUI
extends Control
## Front-end screens over the live 3D scene: home, mode select, garage,
## missions and settings. Reads and writes SaveData directly and tells the
## game what to show (car preview, camera framing) and when to start a run.

signal play_requested(mode: String, env: String)
signal preview_changed(car_id: String, paint: Color, rim: int)
signal screen_changed(screen: String)
signal settings_changed
signal clicked

const MODES := [
	{"id": "endless", "name": "ENDLESS", "desc": "One-way traffic. Go as far as you can."},
	{"id": "twoway", "name": "TWO-WAY", "desc": "Drive into oncoming traffic for double points."},
	{"id": "time", "name": "TIME TRIAL", "desc": "Beat the clock to each checkpoint."},
]
const ENVS := [["day", "DAY", 1], ["sunset", "SUNSET", 3], ["night", "NIGHT", 5]]
const CONTROL_W := 340.0   ## width of the control column in settings rows
const SCROLL_PAD := 18     ## room around scrolled cards for their shadows

var save: SaveData
var _screens := {}
var _current := ""
var _margin := 28.0

var _top: HBoxContainer
var _back: Button
var _title_pill: PanelContainer
var _title: Label
var _cash: Label
var _level: Label
var _xp: ProgressBar
var _toast: Label
var _daily_popup: Control

var _mode := "endless"
var _env := "day"
var _mode_cards := {}
var _env_chips := {}
var _steer_chips := {}
var _mode_best := {}
var _go: Button

var _gi := 0
var _g := {}
var _g_tab := "upgrade"
var _pending_paint := -2
var _pending_rim := -1

var _missions_box: VBoxContainer
var _daily_box: VBoxContainer
var _settings_rows := {}
var _choice_chips := {}     # setting key -> {value: chip}
var _home_best: Label


func setup(data: SaveData) -> void:
	save = data
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode = save.last_mode
	_env = save.last_env
	_build_all()
	get_viewport().size_changed.connect(_layout)
	_layout()
	show_screen("home")


## The player's light/dark choice; until they make one, whatever the phone
## uses (dark when the device can't tell us).
func _theme_choice() -> String:
	var t := str(save.settings.get("theme", ""))
	if t == "light" or t == "dark":
		return t
	if DisplayServer.is_dark_mode_supported() and not DisplayServer.is_dark_mode():
		return "light"
	return "dark"


func _build_all() -> void:
	UiTheme.apply(_theme_choice())
	theme = UiTheme.make()
	_build_top_bar()
	_screens["home"] = _build_home()
	_screens["modes"] = _build_modes()
	_screens["garage"] = _build_garage()
	_screens["missions"] = _build_missions()
	_screens["settings"] = _build_settings()
	for s in _screens.values():
		add_child(s)
	_toast = Label.new()
	_toast.theme_type_variation = "Heading"
	_toast.add_theme_font_size_override("font_size", 28)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_toast.add_theme_constant_override("outline_size", 8)
	add_child(_toast)
	_toast.modulate.a = 0.0


## Tears the menus down and builds them again in the newly chosen mode.
func _restyle() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for d in [_screens, _mode_cards, _env_chips, _steer_chips, _mode_best, _g, _settings_rows, _choice_chips]:
		d.clear()
	_daily_popup = null
	_build_all()
	_layout()
	show_screen("settings")


# ------------------------------------------------------------------ helpers

func _label(text: String, variation := "", size := 0) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, primary := false, cb: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	if primary:
		b.theme_type_variation = "PrimaryButton"
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): clicked.emit())
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _chip(text: String, group: ButtonGroup, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "Chip"
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): clicked.emit())
	b.pressed.connect(cb)
	return b


func _screen() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.visible = false
	return c


func toast(text: String, color := UiTheme.ACCENT) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.modulate.a = 1.0
	var tw := _toast.create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


func _safe_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var safe := Rect2(Vector2.ZERO, vp)
	if OS.has_feature("mobile"):
		var ds := Rect2(DisplayServer.get_display_safe_area())
		var scr := Vector2(DisplayServer.screen_get_size())
		if scr.x > 0:
			var k := vp / scr
			safe = Rect2(ds.position * k, ds.size * k)
	return safe.grow(-_margin)


# ------------------------------------------------------------------ top bar

func _build_top_bar() -> void:
	_top = HBoxContainer.new()
	_top.add_theme_constant_override("separation", 12)
	_title_pill = PanelContainer.new()
	_title_pill.theme_type_variation = "SoftPanel"
	_title_pill.add_theme_stylebox_override("panel", UiTheme.card(UiTheme.PANEL_SOFT, 30, 6, 0.6))
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 14)
	_back = _icon_button("", "back", "IconButton", func(): _go_back())
	_back.custom_minimum_size = Vector2(48, 48)
	th.add_child(_back)
	_title = _label("", "Heading", 30)
	th.add_child(_title)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(6, 0)
	th.add_child(pad)
	_title_pill.add_child(th)
	_top.add_child(_title_pill)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(spacer)
	var lv := PanelContainer.new()
	lv.theme_type_variation = "SoftPanel"
	var lvb := HBoxContainer.new()
	lvb.add_theme_constant_override("separation", 12)
	_level = _label("LV 1", "", 21)
	_level.add_theme_font_override("font", UiTheme.BOLD)
	lvb.add_child(_level)
	_xp = ProgressBar.new()
	_xp.show_percentage = false
	_xp.custom_minimum_size = Vector2(100, 10)
	_xp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lvb.add_child(_xp)
	lv.add_child(lvb)
	_top.add_child(lv)
	var cp := PanelContainer.new()
	cp.theme_type_variation = "SoftPanel"
	var cb := HBoxContainer.new()
	cb.add_theme_constant_override("separation", 8)
	var coin := Label.new()
	coin.text = "$"
	coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coin.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coin.custom_minimum_size = Vector2(26, 26)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.add_theme_font_override("font", UiTheme.BOLD)
	coin.add_theme_font_size_override("font_size", 17)
	coin.add_theme_color_override("font_color", UiTheme.ON_ACCENT)
	coin.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.ACCENT, 13, Color(0, 0, 0, 0), 0, 0))
	cb.add_child(coin)
	_cash = _label("0", "", 22)
	_cash.add_theme_font_override("font", UiTheme.BOLD)
	cb.add_child(_cash)
	cp.add_child(cb)
	_top.add_child(cp)
	add_child(_top)


func refresh_top() -> void:
	var info := Progression.level_info(save.xp)
	_level.text = "LV %d" % info["level"]
	_xp.max_value = info["need"]
	_xp.value = info["into"]
	_cash.text = UiTheme.money(save.cash)


# ------------------------------------------------------------------ home

func _build_home() -> Control:
	var s := _screen()
	var side := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, UiTheme.SCRIM)
	grad.set_color(1, Color(UiTheme.SCRIM, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.35, 0)
	gt.fill_to = Vector2(1, 0)
	side.texture = gt
	side.stretch_mode = TextureRect.STRETCH_SCALE
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.name = "Side"
	s.add_child(side)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.add_child(_label("FLOWLINE", "Display"))
	var play := _icon_button("PLAY", "play", "PrimaryButton", func(): show_screen("modes"))
	play.custom_minimum_size = Vector2(380, 80)
	(play.get_meta("label") as Label).add_theme_font_size_override("font_size", 36)
	col.add_child(play)
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 12)
	for spec in [["GARAGE", "garage", "car"], ["MISSIONS", "missions", "flag"], ["SETTINGS", "settings", "gear"]]:
		var target: String = spec[1]
		var b := _icon_button(spec[0], spec[2], "Button", func(): show_screen(target), true)
		b.custom_minimum_size = Vector2(118, 100)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(b.get_meta("label") as Label).add_theme_font_size_override("font_size", 18)
		b.name = target
		tiles.add_child(b)
	col.add_child(tiles)
	_home_best = _label("", "Caption", 17)
	col.add_child(_home_best)
	s.add_child(col)
	return s


# ------------------------------------------------------------------ modes

func _build_modes() -> Control:
	var s := _screen()
	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 16)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for m in MODES:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(300, 170)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var n := _label(m["name"], "Heading", 34)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(n)
		var tick := PanelContainer.new()
		tick.custom_minimum_size = Vector2(30, 30)
		tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tick.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.ACCENT, 15, Color(0, 0, 0, 0), 0, 0))
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tick.add_child(UiIcon.make("check", 22.0, UiTheme.ON_ACCENT))
		tick.name = "Tick"
		head.add_child(tick)
		v.add_child(head)
		var d := _label(m["desc"], "Muted", 19)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.size_flags_vertical = Control.SIZE_EXPAND_FILL
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(d)
		var best := _label("", "Caption", 16)
		best.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(best)
		_mode_best[m["id"]] = best
		card.add_child(v)
		var id: String = m["id"]
		card.gui_input.connect(func(e: InputEvent):
			if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
				clicked.emit()
				_mode = id
				_refresh_modes())
		_mode_cards[id] = card
		row.add_child(card)
	col.add_child(row)
	# Run options, one aligned row each, with DRIVE beside them.
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiTheme.card(UiTheme.PANEL, UiTheme.R + 6, 20))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	var opts := VBoxContainer.new()
	opts.add_theme_constant_override("separation", 8)
	opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var g := ButtonGroup.new()
	var seg := _option_row(opts, "TIME OF DAY")
	for e in ENVS:
		var id: String = e[0]
		var chip := _chip(e[1], g, func():
			_env = id
			_refresh_modes())
		_env_chips[id] = chip
		seg.add_child(chip)
	# Arrows or a wheel on screen, or GYRO (turn the phone; the saved value is still "tilt").
	var sg := ButtonGroup.new()
	var sseg := _option_row(opts, "STEERING")
	for o in [["ARROWS", "buttons"], ["WHEEL", "wheel"], ["GYRO", "tilt"]]:
		var val: String = o[1]
		var chip := _chip(o[0], sg, func():
			save.settings["controls"] = val
			save.save_to_disk()
			settings_changed.emit())
		_steer_chips[val] = chip
		sseg.add_child(chip)
	hb.add_child(opts)
	_go = _icon_button("DRIVE", "play", "PrimaryButton", func():
		save.last_mode = _mode
		save.last_env = _env
		save.save_to_disk()
		play_requested.emit(_mode, _env))
	_go.custom_minimum_size = Vector2(300, 0)
	(_go.get_meta("label") as Label).add_theme_font_size_override("font_size", 40)
	hb.add_child(_go)
	bar.add_child(hb)
	col.add_child(bar)
	s.add_child(col)
	return s


func _refresh_modes() -> void:
	# Motorcycles steer with the arrows or GYRO only: no wheel chip for them.
	var steer := save.steer_for(save.selected_car)
	for k in _steer_chips:
		(_steer_chips[k] as Button).visible = k != "wheel" or not CarCatalog.is_bike(save.selected_car)
		(_steer_chips[k] as Button).set_pressed_no_signal(steer == k)
	var lvl := save.level()
	for m in MODES:
		var card: PanelContainer = _mode_cards[m["id"]]
		var on: bool = m["id"] == _mode
		var sb := UiTheme.card(UiTheme.PANEL, UiTheme.R + 6, 24, 1.4 if on else 0.6)
		if on:
			sb.border_color = UiTheme.ACCENT
			sb.set_border_width_all(3)
		card.add_theme_stylebox_override("panel", sb)
		card.modulate.a = 1.0 if on else 0.82
		(card.find_child("Tick", true, false) as Control).modulate.a = 1.0 if on else 0.0
		var best := int(save.best_by_mode.get(m["id"], 0))
		(_mode_best[m["id"]] as Label).text = "BEST  %s" % UiTheme.money(best) if best > 0 else ""
	for e in ENVS:
		var chip: Button = _env_chips[e[0]]
		var need: int = e[2]
		chip.disabled = lvl < need
		chip.text = e[1] if lvl >= need else "%s  LV %d" % [e[1], need]
		chip.button_pressed = e[0] == _env
	if lvl < _env_need(_env):
		_env = "day"
		(_env_chips["day"] as Button).button_pressed = true


func _env_need(id: String) -> int:
	for e in ENVS:
		if e[0] == id:
			return e[2]
	return 1


# ------------------------------------------------------------------ garage

func _build_garage() -> Control:
	var s := _screen()
	var panel := PanelContainer.new()
	panel.name = "Panel"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := HBoxContainer.new()
	_g["count"] = _label("", "Caption", 15)
	_g["class"] = _label("", "Caption", 15)
	_g["class"].add_theme_color_override("font_color", UiTheme.AMBER)
	_g["class"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_g["class"])
	head.add_child(_g["count"])
	v.add_child(head)
	_g["name"] = _label("", "Heading", 36)
	v.add_child(_g["name"])
	var tg := ButtonGroup.new()
	var tabs := _segment(v)
	for t in [["UPGRADE", "upgrade"], ["PAINT", "paint"], ["RIMS", "rims"], ["PLATE", "plate"]]:
		var id: String = t[1]
		var chip := _chip(t[0], tg, func():
			_g_tab = id
			_refresh_garage())
		chip.button_pressed = id == _g_tab
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(chip)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = NO_DRAG
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_g["tab"] = VBoxContainer.new()
	_g["tab"].add_theme_constant_override("separation", 6)
	_g["tab"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_g["tab"])
	v.add_child(scroll)
	_g["action"] = _button("", true, func(): _garage_action())
	_g["action"].custom_minimum_size = Vector2(0, 58)
	_g["action"].add_theme_font_size_override("font_size", 26)
	v.add_child(_g["action"])
	s.add_child(panel)
	for d in [-1, 1]:
		var step: int = d
		var b := _icon_button("", "back" if d < 0 else "next", "IconButton", func(): _browse(step))
		b.custom_minimum_size = Vector2(64, 64)
		b.name = "Prev" if d < 0 else "Next"
		s.add_child(b)
	return s


func _car() -> Dictionary:
	return CarCatalog.PLAYER_CARS[_gi]


func _browse(step: int) -> void:
	_gi = posmod(_gi + step, CarCatalog.PLAYER_CARS.size())
	_pending_paint = -2
	_pending_rim = -1
	_refresh_garage()


func _preview() -> void:
	var id: String = _car()["id"]
	var paint_i := _pending_paint if _pending_paint > -2 else save.paint_index(id)
	var rim_i := _pending_rim if _pending_rim >= 0 else save.rim_index(id)
	preview_changed.emit(id, CarCatalog.paint_for(id, paint_i), rim_i)


func _refresh_garage() -> void:
	var car := _car()
	var id: String = car["id"]
	var owned := save.owned_cars.has(id)
	_g["name"].text = String(car["name"]).to_upper()
	_g["class"].text = String(car["class"]).to_upper()
	_g["count"].text = "%d / %d" % [_gi + 1, CarCatalog.PLAYER_CARS.size()]
	var tab: VBoxContainer = _g["tab"]
	for c in tab.get_children():
		c.queue_free()
	match _g_tab:
		"upgrade":
			_fill_upgrades(tab, car, owned)
		"paint":
			_fill_swatches(tab, id, true)
		"rims":
			_fill_swatches(tab, id, false)
		"plate":
			_fill_plate(tab)
	_refresh_action()
	refresh_top()
	_preview()


## One row per stat: its rating bar (which grows with upgrades), the level,
## and the price of the next level.
func _fill_upgrades(tab: VBoxContainer, car: Dictionary, owned: bool) -> void:
	var id: String = car["id"]
	var lv := save.car_levels(id)
	var r := Progression.ratings(Progression.stats_for(car, lv if owned else {}))
	for cat in Progression.UPGRADES:
		var strip := PanelContainer.new()
		strip.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.WELL, 0.55), UiTheme.R - 4, Color(0, 0, 0, 0), 0, 10))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name := _label(Progression.UPGRADE_NAMES[cat], "", 20)
		name.custom_minimum_size = Vector2(118, 0)
		row.add_child(name)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.001
		bar.value = r[cat]
		bar.custom_minimum_size = Vector2(60, 10)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var level := int(lv[cat])
		var lvl := _label("%d/%d" % [level, Progression.MAX_LEVEL], "Caption", 15)
		lvl.custom_minimum_size = Vector2(30, 0)
		row.add_child(lvl)
		var b := Button.new()
		b.theme_type_variation = "SmallButton"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(112, 40)
		b.add_theme_font_size_override("font_size", 19)
		if level >= Progression.MAX_LEVEL:
			b.text = "MAX"
			b.disabled = true
		elif not owned:
			b.text = "LOCKED"
			b.disabled = true
		else:
			var cost := Progression.upgrade_cost(car, level + 1)
			b.text = "$ " + UiTheme.money(cost)
			b.disabled = save.cash < cost
			var category: String = cat
			b.pressed.connect(func():
				clicked.emit()
				if save.buy_upgrade(id, category):
					save.save_to_disk()
					toast("%s UPGRADED" % Progression.UPGRADE_NAMES[category].to_upper(), UiTheme.GOOD)
					settings_changed.emit()
				_refresh_garage())
		row.add_child(b)
		strip.add_child(row)
		tab.add_child(strip)


func _fill_swatches(tab: VBoxContainer, id: String, paint: bool) -> void:
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var list: Array = CarCatalog.PAINTS if paint else CarCatalog.RIMS
	var current := (_pending_paint if _pending_paint > -2 else save.paint_index(id)) if paint \
			else (_pending_rim if _pending_rim >= 0 else save.rim_index(id))
	var owned: Array = save.owned_paints.get(id, []) if paint else save.owned_rims.get(id, [0])
	var entries := []
	if paint:
		entries.append([-1, "Factory", CarCatalog.player_car(id)["paint"]])
	for i in list.size():
		entries.append([i, list[i][0], list[i][1]])
	for e in entries:
		var idx: int = e[0]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(48, 48)
		b.tooltip_text = e[1]
		var sel := idx == current
		var have := owned.has(idx) or (paint and idx == -1)
		b.add_theme_stylebox_override("normal", UiTheme.box(e[2], 24, UiTheme.ACCENT if sel else UiTheme.tint(0.15), 4 if sel else 1, 0))
		b.add_theme_stylebox_override("hover", UiTheme.box(e[2], 24, UiTheme.INK, 2, 0))
		b.add_theme_stylebox_override("pressed", UiTheme.box(e[2], 24, UiTheme.ACCENT, 4, 0))
		if not have:
			b.text = "$"
			b.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
			b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
			b.add_theme_constant_override("outline_size", 6)
		b.pressed.connect(func():
			clicked.emit()
			if paint:
				_pending_paint = idx
			else:
				_pending_rim = idx
			if have and save.owned_cars.has(id):
				if paint:
					save.choose_paint(id, idx)
				else:
					save.choose_rim(id, idx)
				save.save_to_disk()
				_pending_paint = -2
				_pending_rim = -1
			_refresh_garage())
		grid.add_child(b)
	tab.add_child(grid)
	var name: String = ""
	for e in entries:
		if e[0] == current:
			name = e[1]
	var cost := Progression.PAINT_COST if paint else Progression.RIM_COST
	tab.add_child(_label("%s  ·  NEW $ %s" % [name.to_upper(), UiTheme.money(cost)], "Caption", 15))


func _refresh_action() -> void:
	var car := _car()
	var id: String = car["id"]
	var b: Button = _g["action"]
	b.disabled = false
	_mark_selected(b, false)
	var owned := save.owned_cars.has(id)
	if owned and _pending_paint > -2 and not (save.owned_paints.get(id, []) as Array).has(_pending_paint) and _pending_paint != -1:
		b.text = "BUY PAINT  ·  $ " + UiTheme.money(Progression.PAINT_COST)
		b.disabled = save.cash < Progression.PAINT_COST
	elif owned and _pending_rim >= 0 and not (save.owned_rims.get(id, [0]) as Array).has(_pending_rim):
		b.text = "BUY RIMS  ·  $ " + UiTheme.money(Progression.RIM_COST)
		b.disabled = save.cash < Progression.RIM_COST
	elif not owned:
		var price := int(car["price"])
		if save.cash >= price:
			b.text = "BUY  ·  $ " + UiTheme.money(price)
		else:
			b.text = "NEED $ %s MORE" % UiTheme.money(price - save.cash)
			b.disabled = true
	elif save.selected_car == id:
		b.text = "SELECTED"
		b.disabled = true
		_mark_selected(b, true)
	else:
		b.text = "SELECT"


## The car you drive: the action button turns solid green with a tick, so it
## reads as chosen rather than greyed out.
func _mark_selected(b: Button, on: bool) -> void:
	if not _g.has("tick"):
		var tick := UiIcon.make("check", 26, Color.WHITE)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tick)
		_g["tick"] = tick
	var tick: Control = _g["tick"]
	tick.visible = on
	if not on:
		b.remove_theme_stylebox_override("disabled")
		b.remove_theme_color_override("font_disabled_color")
		return
	var sb := UiTheme.box(UiTheme.GOOD, UiTheme.R - 4, Color(0, 0, 0, 0), 0, 22)
	b.add_theme_stylebox_override("disabled", sb)
	# Dark mode's green is bright: dark text reads better on it.
	var ink := Color(0.02, 0.16, 0.08) if UiTheme.mode == "dark" else Color.WHITE
	b.add_theme_color_override("font_disabled_color", ink)
	(tick as UiIcon).color = ink
	tick.queue_redraw()
	# Tick just left of the centred label.
	var fs := b.get_theme_font_size("font_size")
	var w := b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	tick.anchor_left = 0.5
	tick.anchor_right = 0.5
	tick.anchor_top = 0.5
	tick.anchor_bottom = 0.5
	tick.offset_left = -w * 0.5 - 40.0
	tick.offset_top = -13.0
	tick.offset_right = tick.offset_left + 26.0
	tick.offset_bottom = 13.0


func _garage_action() -> void:
	var id: String = _car()["id"]
	var owned := save.owned_cars.has(id)
	if owned and _pending_paint > -2:
		if save.choose_paint(id, _pending_paint):
			toast("NEW PAINT", UiTheme.GOOD)
		_pending_paint = -2
	elif owned and _pending_rim >= 0:
		if save.choose_rim(id, _pending_rim):
			toast("NEW RIMS", UiTheme.GOOD)
		_pending_rim = -1
	elif not owned:
		if save.buy_car(id):
			save.selected_car = id
			toast("%s IS YOURS" % String(_car()["name"]).to_upper(), UiTheme.GOOD)
	else:
		save.selected_car = id
	save.save_to_disk()
	settings_changed.emit()
	_refresh_garage()


# ------------------------------------------------------------------ missions

func _build_missions() -> Control:
	var s := _screen()
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 14)
	var hero := PanelContainer.new()
	hero.add_theme_stylebox_override("panel", UiTheme.card(UiTheme.ACCENT, UiTheme.R + 6, 24, 1.0))
	_daily_box = VBoxContainer.new()
	hero.add_child(_daily_box)
	panel.add_child(hero)
	var card := PanelContainer.new()
	_missions_box = VBoxContainer.new()
	_missions_box.add_theme_constant_override("separation", 10)
	card.add_child(_missions_box)
	panel.add_child(card)
	s.add_child(_scroller(panel))
	return s


func _refresh_missions() -> void:
	for c in _daily_box.get_children():
		c.queue_free()
	for c in _missions_box.get_children():
		c.queue_free()
	var st := Progression.daily_state(save.last_daily, save.daily_streak, today())
	var row := HBoxContainer.new()
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cap := _label("DAILY REWARD", "Caption", 15)
	cap.add_theme_color_override("font_color", Color(UiTheme.ON_ACCENT, 0.65))
	info.add_child(cap)
	var big: Label
	if st["available"]:
		big = _label("Day %d:  $ %s" % [st["streak"], UiTheme.money(st["reward"])], "Heading", 30)
	else:
		big = _label("Claimed. Back tomorrow.", "Heading", 28)
	big.add_theme_color_override("font_color", UiTheme.ON_ACCENT)
	info.add_child(big)
	row.add_child(info)
	if st["available"]:
		var b := _button("CLAIM", false, func(): _claim_daily())
		b.custom_minimum_size = Vector2(160, 56)
		b.add_theme_stylebox_override("normal", UiTheme.card(UiTheme.ON_ACCENT, UiTheme.R - 4, 18, 0.5))
		b.add_theme_stylebox_override("hover", UiTheme.card(UiTheme.ON_ACCENT.lightened(0.1), UiTheme.R - 4, 18, 0.7))
		b.add_theme_stylebox_override("pressed", UiTheme.card(UiTheme.ON_ACCENT, UiTheme.R - 4, 18, 0.2))
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(c, UiTheme.ACCENT)
		row.add_child(b)
	_daily_box.add_child(row)
	for m in save.missions:
		var strip := PanelContainer.new()
		strip.theme_type_variation = "Row"
		var r := VBoxContainer.new()
		r.add_theme_constant_override("separation", 6)
		var top := HBoxContainer.new()
		var t := _label(m["text"], "", 21)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(t)
		var prog := _label("%d / %d" % [int(m["progress"]), int(m["target"])], "Caption", 15)
		prog.custom_minimum_size = Vector2(70, 0)
		prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		top.add_child(prog)
		var rw := _label("$ " + UiTheme.money(int(m["reward"])), "", 21)
		rw.custom_minimum_size = Vector2(90, 0)
		rw.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rw.add_theme_font_override("font", UiTheme.BOLD)
		rw.add_theme_color_override("font_color", UiTheme.AMBER)
		top.add_child(rw)
		r.add_child(top)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = float(m["target"])
		bar.value = float(m["progress"])
		bar.custom_minimum_size = Vector2(0, 10)
		r.add_child(bar)
		strip.add_child(r)
		_missions_box.add_child(strip)


static func today() -> String:
	return Time.get_date_string_from_system()


func _claim_daily() -> void:
	var got := save.claim_daily(today())
	if got > 0:
		save.save_to_disk()
		toast("+ $ %s" % UiTheme.money(got), UiTheme.GOOD)
	if _daily_popup:
		_daily_popup.queue_free()
		_daily_popup = null
	refresh_top()
	if _current == "missions":
		_refresh_missions()


var skip_daily := false


func maybe_show_daily() -> void:
	if skip_daily:
		return
	var st := Progression.daily_state(save.last_daily, save.daily_streak, today())
	if not st["available"] or _daily_popup:
		return
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_TOP_LEFT)
	shade.add_child(center)
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var cap := _label("DAILY REWARD  ·  DAY %d" % st["streak"], "Caption", 18)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	var amt := _label("$ " + UiTheme.money(st["reward"]), "Display", 72)
	amt.add_theme_color_override("font_color", UiTheme.AMBER)
	amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(amt)
	var b := _button("CLAIM", true, func(): _claim_daily())
	b.custom_minimum_size = Vector2(260, 64)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	p.add_child(v)
	center.add_child(p)
	_daily_popup = shade
	add_child(shade)
	shade.position = Vector2.ZERO
	shade.size = get_viewport_rect().size
	center.size = shade.size


# ------------------------------------------------------------------ settings

func _build_settings() -> Control:
	var s := _screen()
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 16)
	# Two 3-row cards side by side, so rows line up straight across.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	panel.add_child(cols)
	var look := _section(cols, "DISPLAY")
	var sw := CheckButton.new()
	sw.focus_mode = Control.FOCUS_NONE
	sw.button_pressed = UiTheme.dark()
	sw.toggled.connect(func(on: bool):
		clicked.emit()
		save.settings["theme"] = "dark" if on else "light"
		save.save_to_disk()
		_restyle.call_deferred())  # deferred: this switch is freed by the rebuild
	_setting_row(look, "Dark mode").add_child(sw)
	_choice_row(look, "Graphics", "quality", [["HIGH", "high"], ["SAVER", "low"]])
	_choice_row(look, "Speed", "units", [["KM/H", "kmh"], ["MPH", "mph"]])
	var ctl := _section(cols, "CONTROLS")
	_choice_row(ctl, "Steering", "controls", [["ARROWS", "buttons"], ["WHEEL", "wheel"], ["GYRO", "tilt"]])
	_choice_row(ctl, "Pedal", "gas", [["GAS PEDAL", "pedal"], ["AUTO", "auto"]])
	_choice_row(ctl, "Hands", "skin", [["LIGHT", "light"], ["MEDIUM", "medium"], ["TAN", "tan"],
			["BROWN", "brown"], ["DARK", "dark"]])
	_setting_row(ctl, "Sensitivity").add_child(_slider("steer_sensitivity", 0.5, 1.5))
	for c in cols.get_children():
		(c as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Full-width cards: the camera views, then the three volumes side by side.
	var cam := _section(panel, "CAMERA")
	_choice_seg(cam, "camera", [["CHASE", "near"], ["TOP", "top"], ["COCKPIT", "cockpit"]])
	var snd := _section(panel, "SOUND")
	var vols := HBoxContainer.new()
	vols.add_theme_constant_override("separation", 32)
	for spec in [["Music", "music"], ["Effects", "sfx"], ["Engine", "engine"]]:
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(_label(spec[0], "", 21))
		v.add_child(_slider(spec[1]))
		vols.add_child(v)
	snd.add_child(vols)
	s.add_child(_scroller(panel))
	return s




func _choice_row(parent: VBoxContainer, text: String, key: String, options: Array) -> void:
	_choice_seg(_setting_row(parent, text), key, options)


# ------------------------------------------------------------------ navigation

func show_screen(name: String) -> void:
	if name == "garage" and _current != "garage":
		_gi = CarCatalog.index_of(save.selected_car)
		_pending_paint = -2
		_pending_rim = -1
	_current = name
	for k in _screens:
		(_screens[k] as Control).visible = k == name
	_title_pill.visible = name != "home"
	_title.text = {"home": "", "modes": "CHOOSE A MODE", "garage": "GARAGE", "missions": "MISSIONS",
			"settings": "SETTINGS"}[name]
	match name:
		"home":
			var best := int(save.best_by_mode.get("endless", 0))
			_home_best.text = "BEST  %s" % UiTheme.money(best) if best > 0 else ""
			_preview_selected()
			maybe_show_daily()
		"modes":
			_refresh_modes()
		"garage":
			_refresh_garage()
		"missions":
			_refresh_missions()
		"settings":  # some choices can change elsewhere (camera button, mode screen)
			for key in _choice_chips:
				for val in _choice_chips[key]:
					(_choice_chips[key][val] as Button).set_pressed_no_signal(str(save.settings.get(key, "")) == val)
	refresh_top()
	screen_changed.emit(name)
	_layout()


func _preview_selected() -> void:
	var id := save.selected_car
	preview_changed.emit(id, CarCatalog.paint_for(id, save.paint_index(id)), save.rim_index(id))


func _go_back() -> void:
	show_screen("home")


func current_screen() -> String:
	return _current


# ------------------------------------------------------------------ layout

func _layout() -> void:
	var vp := get_viewport_rect().size
	position = Vector2.ZERO
	size = vp
	var s := _safe_rect()
	_top.position = s.position
	_top.size = Vector2(s.size.x, 60)
	for k in _screens:
		var sc: Control = _screens[k]
		sc.position = Vector2.ZERO
		sc.size = vp
	var home: Control = _screens["home"]
	var side: TextureRect = home.get_node("Side")
	side.size = Vector2(vp.x * 0.6, vp.y)
	var hc: Control = home.get_node("Col")
	hc.position = Vector2(s.position.x + 8, s.position.y + 60)
	hc.size = Vector2(minf(520, s.size.x * 0.5), s.size.y - 60)
	var modes: Control = _screens["modes"]
	var mc: Control = modes.get_node("Col")
	mc.position = Vector2(s.position.x, s.position.y + 76)
	mc.size = Vector2(s.size.x, s.size.y - 76)
	var gar: Control = _screens["garage"]
	var gp: Control = gar.get_node("Panel")
	var pw := minf(500.0, s.size.x * 0.46)
	gp.position = Vector2(s.end.x - pw, s.position.y + 70)
	gp.size = Vector2(pw, s.size.y - 70)
	var prev: Control = gar.get_node("Prev")
	var nxt: Control = gar.get_node("Next")
	prev.position = Vector2(s.position.x, vp.y * 0.5 - 32)
	nxt.position = Vector2(gp.position.x - 84, vp.y * 0.5 - 32)
	for k in ["missions", "settings"]:
		var p: Control = (_screens[k] as Control).get_node("Panel")
		var w := minf(820.0 if k == "missions" else 1120.0, s.size.x) + SCROLL_PAD * 2.0
		var top := s.position.y + 72 - SCROLL_PAD
		p.position = Vector2(vp.x * 0.5 - w * 0.5, top)
		p.size = Vector2(w, vp.y - top)
	_toast.position = Vector2(0, vp.y * 0.16)
	_toast.size = Vector2(vp.x, 50)
	if _daily_popup:
		_daily_popup.size = vp


## A button whose face is an icon and/or text laid out by a box container
## (Button's own icon slot wants a texture; our icons are drawn).
func _icon_button(text: String, icon: String, variation: String, cb: Callable, vertical := false) -> Button:
	var b := _button("", false, cb)
	b.theme_type_variation = variation
	var box: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6 if vertical else 12)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ink := UiTheme.ON_ACCENT if variation == "PrimaryButton" else UiTheme.INK
	if icon != "":
		var i := UiIcon.make(icon, 34.0 if vertical else 26.0, ink)
		i.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(i)
	if text != "":
		var l := _label(text, "", 0)
		l.add_theme_font_override("font", UiTheme.BOLD)
		l.add_theme_color_override("font_color", ink)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
		b.set_meta("label", l)
	b.add_child(box)
	return b


## A recessed track holding a row of options; returns the row to add chips to.
func _segment(parent: Control) -> HBoxContainer:
	var track := PanelContainer.new()
	track.theme_type_variation = "Segment"
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	track.add_child(row)
	parent.add_child(track)
	return row


## A titled group of settings rows: caption above a card.
func _section(parent: Control, title: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.card(UiTheme.PANEL, UiTheme.R + 6, 22))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_child(_label(title, "Caption", 14))
	card.add_child(v)
	parent.add_child(card)
	return v


## A settings line: label on the left, a fixed-width, right-aligned slot for
## the control (returned), so every control in a card shares one edge.
func _setting_row(parent: VBoxContainer, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 46)
	var l := _label(text, "", 21)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var slot := HBoxContainer.new()
	slot.custom_minimum_size = Vector2(CONTROL_W, 0)
	slot.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(slot)
	parent.add_child(row)
	return slot


func _option_row(parent: VBoxContainer, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := _label(text, "Caption", 15)
	l.custom_minimum_size = Vector2(120, 0)
	row.add_child(l)
	var seg := _segment(row)
	seg.get_parent().custom_minimum_size = Vector2(440, 0)
	seg.child_entered_tree.connect(func(c: Node):
		(c as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL)
	parent.add_child(row)
	return seg


## The number plate, drawn like a real European plate (blue band, black
## frame). Tapping it opens the phone's own keyboard.
func _fill_plate(tab: VBoxContainer) -> void:
	var plate := PanelContainer.new()
	plate.custom_minimum_size = Vector2(0, 92)
	plate.add_theme_stylebox_override("panel", UiTheme.box(Color(0.96, 0.96, 0.93), 10, Color(0.07, 0.07, 0.09), 4, 4))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	var band := PanelContainer.new()
	band.custom_minimum_size = Vector2(38, 0)
	var bs := UiTheme.box(Color(0.0, 0.2, 0.6), 0, Color(0, 0, 0, 0), 0, 0)
	bs.corner_radius_top_left = 7
	bs.corner_radius_bottom_left = 7
	band.add_theme_stylebox_override("panel", bs)
	var code := Label.new()
	code.text = "FL"
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	code.add_theme_font_override("font", UiTheme.BOLD)
	code.add_theme_font_size_override("font_size", 17)
	code.add_theme_color_override("font_color", Color.WHITE)
	band.add_child(code)
	hb.add_child(band)
	var ed := LineEdit.new()
	ed.text = save.plate
	ed.max_length = 8
	ed.placeholder_text = "TAP TO TYPE"
	ed.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ed.virtual_keyboard_enabled = true
	ed.context_menu_enabled = false
	ed.add_theme_font_override("font", UiTheme.BOLD)
	ed.add_theme_font_size_override("font_size", 58)
	for c in ["font_color", "font_uneditable_color"]:
		ed.add_theme_color_override(c, Color(0.06, 0.07, 0.1))
	ed.add_theme_color_override("font_placeholder_color", Color(0.06, 0.07, 0.1, 0.3))
	ed.add_theme_color_override("caret_color", Color(0.06, 0.07, 0.1))
	ed.add_theme_color_override("selection_color", Color(UiTheme.ACCENT, 0.4))
	for st in ["normal", "focus", "read_only"]:
		ed.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	ed.text_changed.connect(func(t: String):
		var clean := SaveData.clean_plate(t)
		if clean != t:
			ed.text = clean
			ed.caret_column = clean.length()
		_set_plate(clean))
	ed.text_submitted.connect(func(_t: String): ed.release_focus())
	hb.add_child(ed)
	plate.add_child(hb)
	tab.add_child(plate)
	var hint := _label("TAP THE PLATE TO CHANGE IT", "Caption", 14)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tab.add_child(hint)










func _set_plate(text: String) -> void:
	save.plate = SaveData.clean_plate(text)
	save.save_to_disk()
	_preview()




func _slider(key: String, lo := 0.0, hi := 1.0) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 0.05
	sl.custom_minimum_size = Vector2(0, 34)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value = float(save.settings.get(key, 1.0))
	sl.value_changed.connect(func(v: float):
		save.settings[key] = v
		settings_changed.emit())
	sl.drag_ended.connect(func(_c: bool): save.save_to_disk())
	_settings_rows[key] = sl
	return sl


## A segmented choice bound to a setting, stretched across its parent.
func _choice_seg(parent: Container, key: String, options: Array) -> void:
	var seg := _segment(parent)
	seg.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var g := ButtonGroup.new()
	for o in options:
		var val: String = o[1]
		var chip := _chip(o[0], g, func():
			save.settings[key] = val
			save.save_to_disk()
			settings_changed.emit())
		chip.button_pressed = str(save.settings.get(key, "")) == val
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_choice_chips.get_or_add(key, {})[val] = chip
		seg.add_child(chip)


## Touch scrolling. Settings and missions are almost all buttons, chips and
## sliders, and those keep the finger, so the ScrollContainer underneath
## never saw a swipe. Swipes are read here instead: once the finger has
## clearly moved up or down, whatever it pressed is let go (no tap fires)
## and the list follows the finger, then glides on with momentum.
const SWIPE_START := 14.0   ## pixels of vertical travel before it counts as a swipe
## Lists don't drag themselves (that fought with the swipes above); the
## mouse wheel still scrolls them.
const NO_DRAG := 1 << 20

var _sw_scroll: ScrollContainer   # list under the finger
var _sw_from := Vector2.ZERO
var _sw_active := false
var _sw_vel := 0.0               # pixels per second, for the glide
var _sw_swallow := false         # eat the release that ends a swipe


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).index == 0:
		var t := event as InputEventScreenTouch
		if t.position.x < -5000.0:  # our own let-go, mirrored as a touch on desktop
			return
		if t.pressed:
			_sw_scroll = _scroll_at(t.position)
			_sw_from = t.position
			_sw_active = false
			_sw_vel = 0.0
		else:
			if _sw_active:
				_sw_swallow = true
				get_viewport().set_input_as_handled()
			_sw_active = false
			_sw_scroll = null
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == 0 and _sw_scroll:
		var d := event as InputEventScreenDrag
		if not _sw_active:
			var moved := d.position - _sw_from
			if absf(moved.y) < SWIPE_START or absf(moved.y) < absf(moved.x):
				return
			_sw_active = true
			# Let go of the button or slider the swipe started on, away from it, so it doesn't fire.
			var up := InputEventMouseButton.new()
			up.button_index = MOUSE_BUTTON_LEFT
			up.pressed = false
			up.position = Vector2(-10000, -10000)
			up.global_position = up.position
			Input.parse_input_event(up)
		_sw_scroll.scroll_vertical -= int(round(d.relative.y))
		_sw_vel = lerpf(_sw_vel, -d.velocity.y, 0.5)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _sw_active:
		get_viewport().set_input_as_handled()  # the finger's mirrored mouse moves
	elif event is InputEventMouseButton and not (event as InputEventMouseButton).pressed and _sw_swallow \
			and (event as InputEventMouseButton).position.x > -5000.0:
		_sw_swallow = false
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	_sw_swallow = false
	if _sw_active or absf(_sw_vel) < 20.0 or _glide == null:
		if not _sw_active:
			_sw_vel = 0.0
		return
	_glide.scroll_vertical += int(round(_sw_vel * dt))
	_sw_vel *= exp(-4.0 * dt)


var _glide: ScrollContainer:
	get:
		return _sw_scroll if _sw_scroll else _last_scroll
var _last_scroll: ScrollContainer


## The visible vertical list under a screen point, if any.
func _scroll_at(p: Vector2) -> ScrollContainer:
	var scr: Control = _screens.get(_current)
	if scr == null:
		return null
	for sc in scr.find_children("*", "ScrollContainer", true, false):
		var s := sc as ScrollContainer
		if s.is_visible_in_tree() and s.get_global_rect().has_point(p):
			_last_scroll = s
			return s
	return null


## Wraps a screen's content in a vertical scroller (named "Panel" for
## _layout), with a margin so card shadows aren't clipped. Phones show less
## height once the UI is scaled up, so tall screens scroll there.
func _scroller(content: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.name = "Panel"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = NO_DRAG
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, SCROLL_PAD)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(content)
	sc.add_child(m)
	return sc
