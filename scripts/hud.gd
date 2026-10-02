extends CanvasLayer
class_name HUD
## In-game HUD, overlays and dialogs.

var game: Node
var player: Player

var root: Control
var _objective: Label
var _room: Label
var _code: Label
var _ammo: Label
var _prompt: Label
var _fps: Label
var _msg: Label
var _countdown: Label
var _bars: Dictionary = {}
var _blink: ColorRect
var _damage: ColorRect
var _white: ColorRect
var _vignette: ColorRect
var _crosshair: Control
var _dialog: Control
var _keypad_display: Label
var _keypad_text := ""
var _msg_t := 0.0
var minimap: Minimap
var touch: TouchControls

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float strength = 0.55;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
void fragment() {
	vec2 uv = UV - 0.5;
	float v = smoothstep(0.25, 0.75, length(uv * vec2(1.25, 1.0)));
	COLOR = vec4(tint.rgb, v * strength);
}"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_vignette.material = sm
	root.add_child(_vignette)
	_damage = _full_rect(Color(0.6, 0.0, 0.0, 0.0))
	# top-left: objective + room + bars
	var tl := VBoxContainer.new()
	tl.position = Vector2(24, 18)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_theme_constant_override("separation", 4)
	root.add_child(tl)
	_objective = UIKit.label("", 20, Color(1, 0.85, 0.6))
	tl.add_child(_objective)
	_room = UIKit.label("", 16, UIKit.DIM)
	tl.add_child(_room)
	for b: Array in [["health", "HEALTH", Color(0.8, 0.12, 0.1)], ["stamina", "STAMINA", Color(0.85, 0.85, 0.85)], ["blink", "BLINK", Color(0.35, 0.65, 1.0)], ["battery", "BATTERY", Color(1.0, 0.8, 0.2)]]:
		tl.add_child(_bar(b[0], b[1], b[2]))
	# top-right: code + ammo
	var tr := VBoxContainer.new()
	tr.anchor_left = 1.0
	tr.anchor_right = 1.0
	tr.offset_left = -440
	tr.offset_right = -200
	tr.offset_top = 22
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tr)
	_code = UIKit.label("", 24, Color(1, 0.35, 0.3), HORIZONTAL_ALIGNMENT_RIGHT)
	tr.add_child(_code)
	_ammo = UIKit.label("", 30, UIKit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	tr.add_child(_ammo)
	_fps = UIKit.label("", 16, Color(0.5, 1, 0.5), HORIZONTAL_ALIGNMENT_RIGHT)
	tr.add_child(_fps)
	# center
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(func() -> void:
		_crosshair.draw_circle(Vector2.ZERO, 2.5, Color(1, 1, 1, 0.8))
		_crosshair.draw_arc(Vector2.ZERO, 9.0, 0, TAU, 24, Color(1, 1, 1, 0.25), 1.5, true))
	root.add_child(_crosshair)
	_prompt = UIKit.label("", 22, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	_center_label(_prompt, 60)
	_msg = UIKit.label("", 26, Color(1, 0.9, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	_center_label(_msg, -190)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_countdown = UIKit.label("", 40, Color(1, 0.2, 0.15), HORIZONTAL_ALIGNMENT_CENTER)
	_center_label(_countdown, -260)
	touch = TouchControls.new()
	root.add_child(touch)
	minimap = Minimap.new()
	minimap.visible = false
	root.add_child(minimap)
	_blink = _full_rect(Color(0, 0, 0, 0))
	_white = _full_rect(Color(1, 1, 1, 0))

func setup(g: Node, p: Player) -> void:
	game = g
	player = p
	touch.player = p
	touch.game = g
	touch.visible = Settings.use_touch()
	minimap.map = g.get("map")
	minimap.player = p
	minimap.game = g
	Settings.changed.connect(func() -> void: touch.visible = Settings.use_touch() and _dialog == null)

func _full_rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	return r

func _center_label(l: Label, y: float) -> void:
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.anchor_top = 0.5
	l.anchor_bottom = 0.5
	l.offset_left = -420
	l.offset_right = 420
	l.offset_top = y
	l.offset_bottom = y + 40
	root.add_child(l)

func _bar(id: String, title: String, col: Color) -> Control:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label(title, 14, UIKit.DIM)
	l.custom_minimum_size.x = 82
	h.add_child(l)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.custom_minimum_size = Vector2(190, 12)
	bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fg := ColorRect.new()
	fg.color = col
	fg.size = Vector2(190, 12)
	fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(fg)
	h.add_child(bg)
	_bars[id] = fg
	return h

func _set_bar(id: String, v: float) -> void:
	var fg: ColorRect = _bars[id]
	fg.size.x = 190.0 * clampf(v / 100.0, 0.0, 1.0)

func _process(delta: float) -> void:
	if player == null:
		return
	_crosshair.queue_redraw()
	_set_bar("health", player.health)
	_set_bar("stamina", player.stamina)
	_set_bar("blink", player.blink_meter)
	_set_bar("battery", player.battery)
	var bc: ColorRect = _bars["blink"]
	bc.color = Color(1, 0.3, 0.2) if player.blink_meter < 25.0 else Color(0.35, 0.65, 1.0)
	_blink.color.a = 1.0 if player.is_blinking() else 0.0
	_damage.color.a = maxf(0.0, _damage.color.a - delta * 1.2)
	var low := clampf(1.0 - player.health / 60.0, 0.0, 1.0)
	(_vignette.material as ShaderMaterial).set_shader_parameter("strength", 0.55 + low * 0.35)
	(_vignette.material as ShaderMaterial).set_shader_parameter("tint", Color(0.35 * low, 0, 0, 1))
	var rv := player.revolver
	_ammo.text = ("RELOADING..." if rv.reloading else "%d  |  %d" % [rv.mag, rv.reserve])
	_ammo.add_theme_color_override("font_color", Color(1, 0.4, 0.3) if rv.mag == 0 else UIKit.TEXT)
	_code.text = "WARHEAD CODE  " + str(game.call("code_display"))
	_objective.text = str(game.call("objective_text"))
	_room.text = str(game.get("map").call("room_name_at", player.global_position)).to_upper()
	var t := player.get_interact_target()
	var pr := ""
	if t:
		pr = str(t.call("get_prompt"))
		if not Settings.use_touch():
			pr = "[E] " + pr
	_prompt.text = pr
	_fps.visible = Settings.b("show_fps")
	_fps.text = "%d FPS" % Engine.get_frames_per_second()
	if _msg_t > 0.0:
		_msg_t -= delta
		_msg.modulate.a = clampf(_msg_t, 0.0, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if game == null:
		return
	if event.is_action_pressed("pause"):
		game.call("handle_pause_input")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map"):
		game.call("toggle_map")
		get_viewport().set_input_as_handled()

func damage_flash(amount: float) -> void:
	_damage.color.a = clampf(0.25 + amount / 60.0, 0.0, 0.7)

func message(text: String, dur: float = 3.5) -> void:
	_msg.text = text
	_msg_t = dur
	_msg.modulate.a = 1.0

func set_countdown(text: String) -> void:
	_countdown.text = text

func white_flash(alpha: float) -> void:
	_white.color.a = alpha

func dialog_open() -> bool:
	return _dialog != null

func _open_dialog(dim: float = 0.6) -> void:
	close_dialog()
	_dialog = UIKit.dim_layer(root, dim)
	touch.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func close_dialog() -> void:
	if _dialog:
		_dialog.queue_free()
		_dialog = null
	touch.visible = Settings.use_touch()
	if player and player.alive and not get_tree().paused and not Settings.use_touch():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# ------------------------------------------------------------- note
func show_note(title: String, body: String) -> void:
	_open_dialog(0.55)
	var p := UIKit.center_panel(_dialog, Vector2(560, 470))
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(0.86, 0.83, 0.74)
	paper.set_corner_radius_all(3)
	paper.content_margin_left = 34
	paper.content_margin_right = 34
	paper.content_margin_top = 26
	paper.content_margin_bottom = 22
	p.add_theme_stylebox_override("panel", paper)
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UIKit.label(title, 26, Color(0.12, 0.1, 0.08), HORIZONTAL_ALIGNMENT_CENTER))
	var body_l := UIKit.label(body, 21, Color(0.15, 0.12, 0.1))
	body_l.add_theme_constant_override("outline_size", 0)
	body_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_l.custom_minimum_size = Vector2(480, 280)
	v.add_child(body_l)
	var b := UIKit.button("CLOSE", close_dialog, 200)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)

# ------------------------------------------------------------- keypad
func open_keypad() -> void:
	_open_dialog(0.5)
	_keypad_text = ""
	var p := UIKit.center_panel(_dialog, Vector2(420, 600))
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UIKit.label("ALPHA WARHEAD", 26, Color(1, 0.3, 0.25), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label("Enter 4-digit authorization code", 17, UIKit.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var dbg := PanelContainer.new()
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.1, 0.16, 0.1)
	ds.border_color = Color(0.3, 0.5, 0.3)
	ds.set_border_width_all(2)
	ds.content_margin_top = 8
	ds.content_margin_bottom = 8
	dbg.add_theme_stylebox_override("panel", ds)
	_keypad_display = UIKit.label("_ _ _ _", 46, Color(0.5, 1.0, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
	dbg.add_child(_keypad_display)
	v.add_child(dbg)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(grid)
	for k: String in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "CLR", "0", "ENT"]:
		var key := k
		var b := Button.new()
		b.text = k
		b.custom_minimum_size = Vector2(108, 72)
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(func() -> void: _keypad_press(key))
		grid.add_child(b)
	var close := UIKit.button("CANCEL", close_dialog, 200, 52)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(close)

func _keypad_press(k: String) -> void:
	Sfx.play("interact_button2", -6.0)
	if k == "CLR":
		_keypad_text = ""
	elif k == "ENT":
		if _keypad_text.length() == 4:
			var ok := bool(game.call("submit_code", _keypad_text))
			if ok:
				close_dialog()
				return
			_keypad_display.add_theme_color_override("font_color", Color(1, 0.3, 0.2))
			_keypad_display.text = "DENIED"
			_keypad_text = ""
			return
	elif _keypad_text.length() < 4:
		_keypad_text += k
	_keypad_display.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	var shown := ""
	for n in 4:
		shown += (_keypad_text[n] if n < _keypad_text.length() else "_") + (" " if n < 3 else "")
	_keypad_display.text = shown

# ------------------------------------------------------------- pause
func show_pause() -> void:
	_open_dialog(0.7)
	var p := UIKit.center_panel(_dialog, Vector2(460, 520))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	v.add_child(UIKit.label("PAUSED", 36, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label(str(game.call("objective_text")), 17, UIKit.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.button("RESUME", func() -> void: game.call("toggle_pause")))
	v.add_child(UIKit.button("SETTINGS", func() -> void:
		var sm := SettingsMenu.new()
		root.add_child(sm)))
	v.add_child(UIKit.button("HOW TO PLAY", func() -> void:
		var hp := HowToPlay.new()
		root.add_child(hp)))
	v.add_child(UIKit.button("RESTART", func() -> void: game.call("restart")))
	v.add_child(UIKit.button("MAIN MENU", func() -> void: game.call("to_menu")))

# ------------------------------------------------------------- end screens
func show_game_over(cause_text: String, stats: String) -> void:
	_open_dialog(0.0)
	var bg := _dialog as ColorRect
	var tw := create_tween()
	tw.tween_property(bg, "color", Color(0.12, 0, 0, 0.88), 2.0)
	var p := UIKit.center_panel(_dialog, Vector2(640, 420))
	p.modulate.a = 0.0
	tw.parallel().tween_property(p, "modulate:a", 1.0, 2.0).set_delay(0.8)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	v.add_child(UIKit.label("YOU DIED", 52, Color(0.9, 0.12, 0.1), HORIZONTAL_ALIGNMENT_CENTER))
	var c := UIKit.label(cause_text, 22, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.custom_minimum_size.x = 560
	v.add_child(c)
	v.add_child(UIKit.label(stats, 18, UIKit.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	row.add_child(UIKit.button("TRY AGAIN", func() -> void: game.call("restart"), 240))
	row.add_child(UIKit.button("MAIN MENU", func() -> void: game.call("to_menu"), 240))

func show_win(stats: String) -> void:
	_open_dialog(0.0)
	var bg := _dialog as ColorRect
	bg.color = Color(1, 1, 1, 1)
	var tw := create_tween()
	tw.tween_property(bg, "color", Color(0, 0, 0, 0.96), 4.0)
	var p := UIKit.center_panel(_dialog, Vector2(720, 460))
	p.modulate.a = 0.0
	tw.parallel().tween_property(p, "modulate:a", 1.0, 2.0).set_delay(2.5)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	v.add_child(UIKit.label("ALPHA WARHEAD DETONATED", 40, Color(1, 0.75, 0.3), HORIZONTAL_ALIGNMENT_CENTER))
	var t := UIKit.label("Site-19 has been purged. SCP-173, SCP-096, SCP-049 and every instance of SCP-049-2 were caught in the blast.\nYou sealed yourself inside the reinforced Control Room... and survived.", 20, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 640
	v.add_child(t)
	v.add_child(UIKit.label(stats, 19, Color(0.8, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	row.add_child(UIKit.button("PLAY AGAIN", func() -> void: game.call("restart"), 240))
	row.add_child(UIKit.button("MAIN MENU", func() -> void: game.call("to_menu"), 240))
