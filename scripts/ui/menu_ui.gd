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
	{"id": "endless", "name": "ENDLESS", "desc": "A one-way highway. Survive as long as you can and chase a high score."},
	{"id": "twoway", "name": "TWO-WAY", "desc": "Two lanes come straight at you. Drive against traffic for double points and +35% cash."},
	{"id": "time", "name": "TIME TRIAL", "desc": "Race the clock. Every checkpoint adds time. How far can you get?"},
]
const ENVS := [["day", "DAYTIME", 1], ["sunset", "GOLDEN HOUR", 3], ["night", "NIGHT", 5]]

var save: SaveData
var _screens := {}
var _current := ""
var _margin := 28.0

var _top: HBoxContainer
var _back: Button
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
var _home_best: Label


func setup(data: SaveData) -> void:
	save = data
	theme = UiTheme.make()
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode = save.last_mode
	_env = save.last_env
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
	get_viewport().size_changed.connect(_layout)
	_layout()
	show_screen("home")


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


func toast(text: String, color := UiTheme.AMBER) -> void:
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
	_top.add_theme_constant_override("separation", 14)
	_back = _button("BACK", false, func(): _go_back())
	_back.custom_minimum_size = Vector2(110, 52)
	_top.add_child(_back)
	_title = _label("", "Heading", 34)
	_top.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(spacer)
	var lv := PanelContainer.new()
	lv.theme_type_variation = "SoftPanel"
	var lvb := HBoxContainer.new()
	lvb.add_theme_constant_override("separation", 10)
	_level = _label("LV 1", "", 22)
	lvb.add_child(_level)
	_xp = ProgressBar.new()
	_xp.show_percentage = false
	_xp.custom_minimum_size = Vector2(110, 8)
	_xp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lvb.add_child(_xp)
	lv.add_child(lvb)
	_top.add_child(lv)
	var cp := PanelContainer.new()
	cp.theme_type_variation = "SoftPanel"
	_cash = _label("$ 0", "", 24)
	_cash.add_theme_color_override("font_color", UiTheme.AMBER)
	cp.add_child(_cash)
	_top.add_child(cp)
	add_child(_top)


func refresh_top() -> void:
	var info := Progression.level_info(save.xp)
	_level.text = "LV %d" % info["level"]
	_xp.max_value = info["need"]
	_xp.value = info["into"]
	_cash.text = "$ " + UiTheme.money(save.cash)


# ------------------------------------------------------------------ home

func _build_home() -> Control:
	var s := _screen()
	var side := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.025, 0.03, 0.85))
	grad.set_color(1, Color(0.02, 0.025, 0.03, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.3, 0)
	gt.fill_to = Vector2(1, 0)
	side.texture = gt
	side.stretch_mode = TextureRect.STRETCH_SCALE
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.name = "Side"
	s.add_child(side)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 12)
	var title := _label("FLOWLINE", "Display")
	col.add_child(title)
	var tag := _label("Pass close to traffic to build Flow. Fill it for double points.", "Muted", 22)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size = Vector2(440, 0)
	col.add_child(tag)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	col.add_child(gap)
	var play := _button("PLAY", true, func(): show_screen("modes"))
	play.custom_minimum_size = Vector2(360, 78)
	play.add_theme_font_size_override("font_size", 34)
	col.add_child(play)
	for spec in [["GARAGE", "garage"], ["MISSIONS", "missions"], ["SETTINGS", "settings"]]:
		var target: String = spec[1]
		var b := _button(spec[0], false, func(): show_screen(target))
		b.custom_minimum_size = Vector2(360, 58)
		b.name = target
		col.add_child(b)
	_home_best = _label("", "Muted", 20)
	col.add_child(_home_best)
	s.add_child(col)
	return s


# ------------------------------------------------------------------ modes

func _build_modes() -> Control:
	var s := _screen()
	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 20)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for m in MODES:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(300, 220)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var n := _label(m["name"], "Heading", 34)
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(n)
		var d := _label(m["desc"], "Muted", 19)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.size_flags_vertical = Control.SIZE_EXPAND_FILL
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(d)
		var best := _label("", "Caption", 17)
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
	var envrow := HBoxContainer.new()
	envrow.add_theme_constant_override("separation", 10)
	envrow.add_child(_label("TIME OF DAY", "Caption", 17))
	var g := ButtonGroup.new()
	for e in ENVS:
		var id: String = e[0]
		var chip := _chip(e[1], g, func():
			_env = id
			_refresh_modes())
		_env_chips[id] = chip
		envrow.add_child(chip)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	envrow.add_child(sp)
	_go = _button("DRIVE", true, func():
		save.last_mode = _mode
		save.last_env = _env
		save.save_to_disk()
		play_requested.emit(_mode, _env))
	_go.custom_minimum_size = Vector2(240, 70)
	_go.add_theme_font_size_override("font_size", 32)
	envrow.add_child(_go)
	col.add_child(envrow)
	s.add_child(col)
	return s


func _refresh_modes() -> void:
	var lvl := save.level()
	for m in MODES:
		var card: PanelContainer = _mode_cards[m["id"]]
		var on: bool = m["id"] == _mode
		card.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL, 16,
				UiTheme.AMBER if on else UiTheme.LINE, 2 if on else 1, 22))
		var best := int(save.best_by_mode.get(m["id"], 0))
		(_mode_best[m["id"]] as Label).text = "BEST  %s" % UiTheme.money(best) if best > 0 else "NO RUNS YET"
	for e in ENVS:
		var chip: Button = _env_chips[e[0]]
		var need: int = e[2]
		chip.disabled = lvl < need
		chip.text = e[1] if lvl >= need else "%s  ·  LV %d" % [e[1], need]
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
	_g["count"] = _label("", "Caption", 16)
	_g["class"] = _label("", "Caption", 16)
	_g["class"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_g["class"])
	head.add_child(_g["count"])
	v.add_child(head)
	_g["name"] = _label("", "Heading", 44)
	v.add_child(_g["name"])
	_g["blurb"] = _label("", "Muted", 18)
	_g["blurb"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_g["blurb"].custom_minimum_size = Vector2(380, 0)
	v.add_child(_g["blurb"])
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 14)
	stats.add_theme_constant_override("v_separation", 8)
	_g["bars"] = {}
	for cat in Progression.UPGRADES:
		var l := _label(Progression.UPGRADE_NAMES[cat].to_upper(), "Caption", 15)
		l.custom_minimum_size = Vector2(118, 0)
		stats.add_child(l)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.001
		bar.custom_minimum_size = Vector2(240, 10)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stats.add_child(bar)
		_g["bars"][cat] = bar
	v.add_child(stats)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	var tg := ButtonGroup.new()
	for t in [["UPGRADE", "upgrade"], ["PAINT", "paint"], ["RIMS", "rims"]]:
		var id: String = t[1]
		var chip := _chip(t[0], tg, func():
			_g_tab = id
			_refresh_garage())
		chip.button_pressed = id == _g_tab
		tabs.add_child(chip)
	v.add_child(tabs)
	_g["tab"] = VBoxContainer.new()
	_g["tab"].add_theme_constant_override("separation", 8)
	_g["tab"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_g["tab"])
	_g["action"] = _button("", true, func(): _garage_action())
	_g["action"].custom_minimum_size = Vector2(0, 66)
	_g["action"].add_theme_font_size_override("font_size", 28)
	v.add_child(_g["action"])
	s.add_child(panel)
	for d in [-1, 1]:
		var step: int = d
		var b := _button("<" if d < 0 else ">", false, func(): _browse(step))
		b.custom_minimum_size = Vector2(64, 96)
		b.add_theme_font_size_override("font_size", 40)
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
	_g["blurb"].text = car["blurb"]
	var r := Progression.ratings(Progression.stats_for(car, save.car_levels(id) if owned else {}))
	for cat in Progression.UPGRADES:
		(_g["bars"][cat] as ProgressBar).value = r[cat]
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
	_refresh_action()
	refresh_top()
	_preview()


func _fill_upgrades(tab: VBoxContainer, car: Dictionary, owned: bool) -> void:
	var id: String = car["id"]
	var lv := save.car_levels(id)
	for cat in Progression.UPGRADES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name := _label(Progression.UPGRADE_NAMES[cat], "", 20)
		name.custom_minimum_size = Vector2(130, 0)
		row.add_child(name)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 4)
		pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for i in Progression.MAX_LEVEL:
			var p := ColorRect.new()
			p.custom_minimum_size = Vector2(22, 8)
			p.color = UiTheme.AMBER if i < int(lv[cat]) else Color(1, 1, 1, 0.14)
			pips.add_child(p)
		row.add_child(pips)
		var level := int(lv[cat])
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(130, 44)
		b.add_theme_font_size_override("font_size", 20)
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
		tab.add_child(row)
	if not owned:
		tab.add_child(_label("Buy this car to upgrade it.", "Caption", 16))


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
		b.add_theme_stylebox_override("normal", UiTheme.box(e[2], 24, UiTheme.AMBER if sel else Color(1, 1, 1, 0.3), 3 if sel else 1, 0))
		b.add_theme_stylebox_override("hover", UiTheme.box(e[2], 24, Color.WHITE, 2, 0))
		b.add_theme_stylebox_override("pressed", UiTheme.box(e[2], 24, UiTheme.AMBER, 3, 0))
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
	tab.add_child(_label("%s   ·   new colours $ %s, then free to switch" % [name.to_upper(), UiTheme.money(cost)], "Caption", 16))


func _refresh_action() -> void:
	var car := _car()
	var id: String = car["id"]
	var b: Button = _g["action"]
	b.disabled = false
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
	else:
		b.text = "SELECT"


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
	var panel := PanelContainer.new()
	panel.name = "Panel"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_daily_box = VBoxContainer.new()
	v.add_child(_daily_box)
	v.add_child(HSeparator.new())
	_missions_box = VBoxContainer.new()
	_missions_box.add_theme_constant_override("separation", 16)
	v.add_child(_missions_box)
	panel.add_child(v)
	s.add_child(panel)
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
	info.add_child(_label("DAILY REWARD", "Caption", 16))
	if st["available"]:
		info.add_child(_label("Day %d streak: $ %s" % [st["streak"], UiTheme.money(st["reward"])], "", 26))
	else:
		info.add_child(_label("Claimed. Come back tomorrow for day %d." % (save.daily_streak + 1), "", 24))
	row.add_child(info)
	if st["available"]:
		var b := _button("CLAIM", true, func(): _claim_daily())
		b.custom_minimum_size = Vector2(160, 56)
		row.add_child(b)
	_daily_box.add_child(row)
	for m in save.missions:
		var r := VBoxContainer.new()
		r.add_theme_constant_override("separation", 6)
		var top := HBoxContainer.new()
		var t := _label(m["text"], "", 22)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(t)
		var rw := _label("$ " + UiTheme.money(int(m["reward"])), "", 22)
		rw.add_theme_color_override("font_color", UiTheme.AMBER)
		top.add_child(rw)
		r.add_child(top)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = float(m["target"])
		bar.value = float(m["progress"])
		bar.custom_minimum_size = Vector2(0, 8)
		r.add_child(bar)
		var lbl := "%d / %d" % [int(m["progress"]), int(m["target"])]
		if not m["per_run"]:
			lbl += "  ·  adds up over runs"
		r.add_child(_label(lbl, "Caption", 15))
		_missions_box.add_child(r)


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
	var sub := _label("Come back every day. The reward grows for 7 days in a row.", "Muted", 19)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
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
	var panel := PanelContainer.new()
	panel.name = "Panel"
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 16)
	panel.add_child(grid)
	_slider_row(grid, "Sound effects", "sfx")
	_slider_row(grid, "Engine sound", "engine")
	_choice_row(grid, "Steering", "controls", [["BUTTONS", "buttons"], ["TILT", "tilt"]])
	_slider_row(grid, "Steering sensitivity", "steer_sensitivity", 0.5, 1.5)
	_choice_row(grid, "Camera", "camera", [["CLOSE", "near"], ["FAR", "far"]])
	_choice_row(grid, "Graphics", "quality", [["HIGH", "high"], ["BATTERY SAVER", "low"]])
	_choice_row(grid, "Speed", "units", [["KM/H", "kmh"], ["MPH", "mph"]])
	s.add_child(panel)
	return s


func _slider_row(grid: GridContainer, text: String, key: String, lo := 0.0, hi := 1.0) -> void:
	grid.add_child(_label(text, "", 22))
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 0.05
	sl.custom_minimum_size = Vector2(320, 36)
	sl.value = float(save.settings.get(key, 1.0))
	sl.value_changed.connect(func(v: float):
		save.settings[key] = v
		settings_changed.emit())
	sl.drag_ended.connect(func(_c: bool): save.save_to_disk())
	grid.add_child(sl)
	_settings_rows[key] = sl


func _choice_row(grid: GridContainer, text: String, key: String, options: Array) -> void:
	grid.add_child(_label(text, "", 22))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var g := ButtonGroup.new()
	for o in options:
		var val: String = o[1]
		var chip := _chip(o[0], g, func():
			save.settings[key] = val
			save.save_to_disk()
			settings_changed.emit())
		chip.button_pressed = str(save.settings.get(key, "")) == val
		row.add_child(chip)
	grid.add_child(row)


# ------------------------------------------------------------------ navigation

func show_screen(name: String) -> void:
	if name == "garage" and _current != "garage":
		_gi = CarCatalog.index_of(save.selected_car)
		_pending_paint = -2
		_pending_rim = -1
	_current = name
	for k in _screens:
		(_screens[k] as Control).visible = k == name
	_back.visible = name != "home"
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
	_top.size = Vector2(s.size.x, 56)
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
	mc.position = Vector2(s.position.x, s.position.y + 80)
	mc.size = Vector2(s.size.x, s.size.y - 80)
	var gar: Control = _screens["garage"]
	var gp: Control = gar.get_node("Panel")
	var pw := minf(500.0, s.size.x * 0.46)
	gp.position = Vector2(s.end.x - pw, s.position.y + 70)
	gp.size = Vector2(pw, s.size.y - 70)
	var prev: Control = gar.get_node("Prev")
	var nxt: Control = gar.get_node("Next")
	prev.position = Vector2(s.position.x, vp.y * 0.5 - 48)
	nxt.position = Vector2(gp.position.x - 84, vp.y * 0.5 - 48)
	for k in ["missions", "settings"]:
		var p: Control = (_screens[k] as Control).get_node("Panel")
		var w := minf(820.0, s.size.x)
		p.position = Vector2(vp.x * 0.5 - w * 0.5, s.position.y + 76)
		p.size = Vector2(w, 0)
	_toast.position = Vector2(0, vp.y * 0.16)
	_toast.size = Vector2(vp.x, 50)
	if _daily_popup:
		_daily_popup.size = vp
