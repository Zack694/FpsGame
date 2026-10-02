extends Control
## Title screen.

var _bg: TextureRect
var _t := 0.0
var _menu: VBoxContainer

func _ready() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	_bg = TextureRect.new()
	_bg.texture = load("res://assets/textures/173back.jpg")
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.modulate = Color(0.55, 0.55, 0.55)
	add_child(_bg)
	var grad := ColorRect.new()
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment() {
	float l = smoothstep(0.75, 0.15, UV.x);
	float v = smoothstep(0.2, 0.9, length(UV - 0.5));
	COLOR = vec4(0.0, 0.0, 0.0, clamp(l * 0.85 + v * 0.6, 0.0, 0.95));
}"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	grad.material = sm
	add_child(grad)
	var left := VBoxContainer.new()
	left.position = Vector2(80, 70)
	left.add_theme_constant_override("separation", 6)
	add_child(left)
	left.add_child(UIKit.label("SCP: LOCKDOWN", 64, Color(0.95, 0.95, 0.92)))
	left.add_child(UIKit.label("SECURE. CONTAIN. PROTECT.", 20, UIKit.ACCENT))
	var sp := Control.new()
	sp.custom_minimum_size.y = 30
	left.add_child(sp)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 12)
	left.add_child(_menu)
	_build_main()
	var foot := UIKit.label("v1.0  -  SCP Foundation content & SCP: Containment Breach assets are CC BY-SA 3.0", 14, UIKit.DIM)
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_top = -36
	foot.offset_left = 24
	add_child(foot)
	Sfx.music("music_menu", 2.0, -2.0)

func _clear() -> void:
	for c in _menu.get_children():
		c.queue_free()

func _build_main() -> void:
	_clear()
	_menu.add_child(UIKit.button("NEW GAME", _build_difficulty, 360))
	_menu.add_child(UIKit.button("HOW TO PLAY", func() -> void: add_child(HowToPlay.new()), 360))
	_menu.add_child(UIKit.button("SETTINGS", func() -> void: add_child(SettingsMenu.new()), 360))
	_menu.add_child(UIKit.button("CREDITS", _show_credits, 360))
	if not OS.has_feature("web"):
		_menu.add_child(UIKit.button("QUIT", func() -> void: get_tree().quit(), 360))
	if Settings.best_time > 0.0:
		_menu.add_child(UIKit.label("Best escape: %02d:%02d" % [int(Settings.best_time) / 60, int(Settings.best_time) % 60], 18, UIKit.DIM))

func _build_difficulty() -> void:
	_clear()
	_menu.add_child(UIKit.label("SELECT DIFFICULTY", 24, UIKit.TEXT))
	var descs := [
		["SAFE  (Easy)", "Slower SCPs, more ammo, longer blink interval."],
		["EUCLID  (Normal)", "The intended experience."],
		["KETER  (Hard)", "Fast SCPs, scarce ammo, you blink often."],
	]
	for n in 3:
		var d := n
		var b := UIKit.button(descs[n][0], func() -> void: _start(d), 360)
		_menu.add_child(b)
		_menu.add_child(UIKit.label("   " + str(descs[n][1]), 16, UIKit.DIM))
	_menu.add_child(UIKit.button("BACK", _build_main, 360))

func _start(d: int) -> void:
	Settings.difficulty = d
	Settings.save_settings()
	Sfx.stop_music(0.8)
	Sfx.play("door_bigdooropen", 0.0)
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fade)
	var lbl := UIKit.label("LOADING SITE-19...", 26, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.modulate.a = 0.0
	add_child(lbl)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.8)
	tw.parallel().tween_property(lbl, "modulate:a", 1.0, 0.8)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file("res://scenes/game.tscn"))

func _show_credits() -> void:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	UIKit.dim_layer(c, 0.85)
	var p := UIKit.center_panel(c, Vector2(900, 560))
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UIKit.label("CREDITS", 32, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", 18)
	r.text = """Game design & code: SCP: Lockdown (built with the Godot Engine, MIT license).

SCP-173, SCP-096 and SCP-049 / SCP-049-2 models, textures, props, doors and all sound effects/music are taken from [b]SCP - Containment Breach[/b] by Undertow Games (Regalis) and contributors, licensed under Creative Commons Attribution-ShareAlike 3.0 (github.com/Regalis11/scpcb). See assets/SCPCB_Credits.txt for the full list of original authors.

The SCP Foundation universe (scp-wiki.wikidot.com) is licensed under CC BY-SA 3.0. SCP-173 was created by Moto42, SCP-096 by Dr Dan, SCP-049 by Gabriel Jade.

As a derivative work, this game's assets are distributed under CC BY-SA 3.0."""
	v.add_child(r)
	var b := UIKit.button("BACK", c.queue_free, 220)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	add_child(c)

func _process(delta: float) -> void:
	_t += delta
	var f := 0.55 + 0.04 * sin(_t * 1.3)
	if fmod(_t, 7.0) < 0.12:
		f = 0.25
	_bg.modulate = Color(f, f, f)
	_bg.position.x = sin(_t * 0.1) * 12.0
