extends Control
class_name SettingsMenu
## Settings screen (used from the main menu and the pause menu).

signal closed

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	UIKit.dim_layer(self, 0.75)
	var panel := UIKit.center_panel(self, Vector2(980, 620))
	var v := VBoxContainer.new()
	panel.add_child(v)
	var title := UIKit.label("SETTINGS", 34, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(title)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)

	var ctl := _page(tabs, "Controls")
	_slider(ctl, "Touch look sensitivity", "look_sensitivity", 0.2, 3.0, 0.05)
	_slider(ctl, "Mouse sensitivity", "mouse_sensitivity", 0.2, 3.0, 0.05)
	_check(ctl, "Invert look Y", "invert_y")
	_option(ctl, "Touch controls", "touch_controls", ["Auto", "Always on", "Off"])
	_slider(ctl, "Joystick size", "joystick_size", 0.6, 1.6, 0.05)
	_slider(ctl, "Button size", "button_size", 0.6, 1.6, 0.05)
	_slider(ctl, "Button opacity", "button_opacity", 0.15, 1.0, 0.05)
	_check(ctl, "Left-handed layout", "left_handed")
	_check(ctl, "Aim assist (touch)", "aim_assist")

	var gfx := _page(tabs, "Graphics")
	_option(gfx, "Quality", "quality", ["Low", "Medium", "High"])
	_slider(gfx, "Render scale", "render_scale", 0.5, 1.0, 0.05)
	_slider(gfx, "Field of view", "fov", 60.0, 100.0, 1.0)
	_slider(gfx, "Brightness", "brightness", 0.5, 1.8, 0.05)
	_check(gfx, "Flashlight shadows", "flashlight_shadows")
	_check(gfx, "Glow / bloom", "glow")
	_option_values(gfx, "FPS limit", "fps_cap", ["30", "60", "90", "120"], [30, 60, 90, 120])
	_check(gfx, "Show FPS counter", "show_fps")

	var aud := _page(tabs, "Audio")
	_slider(aud, "Master volume", "master_volume", 0.0, 1.0, 0.05)
	_slider(aud, "Music volume", "music_volume", 0.0, 1.0, 0.05)
	_slider(aud, "Effects volume", "sfx_volume", 0.0, 1.0, 0.05)

	var gp := _page(tabs, "Gameplay")
	_check(gp, "Head bob", "head_bob")
	gp.add_child(UIKit.label("Difficulty is chosen when starting a new game.", 18, UIKit.DIM))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	row.add_child(UIKit.button("RESET DEFAULTS", func() -> void:
		Settings.reset_defaults()
		_rebuild(), 260))
	row.add_child(UIKit.button("BACK", func() -> void:
		closed.emit()
		queue_free(), 260))

func _rebuild() -> void:
	var parent := get_parent()
	var cb := closed.get_connections()
	var nm := SettingsMenu.new()
	for c: Dictionary in cb:
		nm.closed.connect(c["callable"])
	parent.add_child(nm)
	queue_free()

func _page(tabs: TabContainer, title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v

func _row(parent: VBoxContainer, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.custom_minimum_size.y = 52
	var l := UIKit.label(text, 21)
	l.custom_minimum_size.x = 360
	h.add_child(l)
	parent.add_child(h)
	return h

func _slider(parent: VBoxContainer, text: String, key: String, mn: float, mx: float, step: float) -> void:
	var h := _row(parent, text)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = Settings.f(key)
	s.custom_minimum_size = Vector2(380, 44)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var val := UIKit.label(_fmt(s.value, step), 20, UIKit.DIM)
	val.custom_minimum_size.x = 80
	h.add_child(val)
	s.value_changed.connect(func(x: float) -> void:
		val.text = _fmt(x, step))
	s.drag_ended.connect(func(_c: bool) -> void:
		Settings.set_value(key, s.value))

func _fmt(x: float, step: float) -> String:
	return str(int(round(x))) if step >= 1.0 else "%.2f" % x

func _check(parent: VBoxContainer, text: String, key: String) -> void:
	var h := _row(parent, text)
	var c := CheckButton.new()
	c.button_pressed = Settings.b(key)
	c.text = "On" if c.button_pressed else "Off"
	c.toggled.connect(func(on: bool) -> void:
		c.text = "On" if on else "Off"
		Settings.set_value(key, on))
	h.add_child(c)

func _option(parent: VBoxContainer, text: String, key: String, items: Array) -> void:
	var vals: Array = []
	for n in items.size():
		vals.append(n)
	_option_values(parent, text, key, items, vals)

func _option_values(parent: VBoxContainer, text: String, key: String, items: Array, vals: Array) -> void:
	var h := _row(parent, text)
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(240, 46)
	for it: String in items:
		o.add_item(it)
	var cur := vals.find(Settings.i(key))
	o.selected = maxi(cur, 0)
	o.item_selected.connect(func(idx: int) -> void:
		Settings.set_value(key, vals[idx]))
	h.add_child(o)
