extends Control
class_name TouchControls
## On-screen controls: floating joystick (left), drag-to-look (right), action buttons.

var player: Player
var game: Node

class TButton:
	var id: String
	var label: String
	var center: Vector2
	var radius: float
	var pressed := false
	var toggled := false
	var visible := true
	var touch := -1

var buttons: Array[TButton] = []
var _joy_touch := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _look_touches: Dictionary = {} # index -> last pos
var _sprint_toggle := false
var _font: Font

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_layout()
	get_viewport().size_changed.connect(_layout)
	Settings.changed.connect(_layout)

func _add(id: String, text: String, c: Vector2, r: float) -> void:
	var b := TButton.new()
	b.id = id
	b.label = text
	b.center = c
	b.radius = r
	buttons.append(b)

func _layout() -> void:
	var old := {}
	for b in buttons:
		old[b.id] = b.toggled
	buttons.clear()
	var s := get_viewport_rect().size
	var k := Settings.f("button_size")
	var mirror := Settings.b("left_handed")
	var base := 62.0 * k
	var items := [
		["fire", "FIRE", Vector2(s.x - 150 * k, s.y - 150 * k), base * 1.45],
		["reload", "RELOAD", Vector2(s.x - 300 * k, s.y - 95 * k), base * 0.85],
		["use", "USE", Vector2(s.x - 315 * k, s.y - 235 * k), base * 0.95],
		["light", "LIGHT", Vector2(s.x - 95 * k, s.y - 330 * k), base * 0.8],
		["blink", "BLINK", Vector2(s.x - 235 * k, s.y - 380 * k), base * 0.75],
		["crouch", "CROUCH", Vector2(s.x - 420 * k, s.y - 90 * k), base * 0.75],
		["sprint", "RUN", Vector2(330 * k, s.y - 90 * k), base * 0.8],
		["pause", "II", Vector2(s.x - 60, 60), 38.0],
		["map", "MAP", Vector2(s.x - 150, 60), 38.0],
	]
	for it: Array in items:
		var c: Vector2 = it[1 + 1]
		if mirror and it[0] != "pause" and it[0] != "map":
			c.x = s.x - c.x
		_add(it[0], it[1], c, it[3])
	for b in buttons:
		b.toggled = bool(old.get(b.id, false))
	queue_redraw()

func _btn(id: String) -> TButton:
	for b in buttons:
		if b.id == id:
			return b
	return null

func _hit(p: Vector2) -> TButton:
	for b in buttons:
		if b.visible and p.distance_to(b.center) <= b.radius * 1.15:
			return b
	return null

func _joy_side(p: Vector2) -> bool:
	var s := get_viewport_rect().size
	return p.x > s.x * 0.6 if Settings.b("left_handed") else p.x < s.x * 0.4

func _input(event: InputEvent) -> void:
	if not visible or player == null or get_tree().paused or not player.alive:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var b := _hit(t.position)
			if b:
				b.pressed = true
				b.touch = t.index
				_press(b)
				if b.id == "fire":
					_look_touches[t.index] = t.position
			elif _joy_side(t.position) and _joy_touch == -1:
				_joy_touch = t.index
				_joy_origin = t.position
				_joy_pos = t.position
			else:
				_look_touches[t.index] = t.position
		else:
			for b in buttons:
				if b.touch == t.index:
					b.pressed = false
					b.touch = -1
					_release(b)
			if t.index == _joy_touch:
				_joy_touch = -1
				player.touch_move = Vector2.ZERO
			_look_touches.erase(t.index)
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _joy_touch:
			_joy_pos = d.position
			_update_joy()
		elif _look_touches.has(d.index):
			player.add_look(d.relative, true)
			_look_touches[d.index] = d.position
		queue_redraw()
		get_viewport().set_input_as_handled()

func _update_joy() -> void:
	var r := 95.0 * Settings.f("joystick_size")
	var off := _joy_pos - _joy_origin
	if off.length() > r * 1.6:
		_joy_origin = _joy_pos - off.normalized() * r * 1.6
		off = _joy_pos - _joy_origin
	var v := off / r
	player.touch_move = v.limit_length(1.0)
	# push the stick far forward to sprint
	player.touch_sprint = _sprint_toggle or (v.length() > 1.25 and v.y < -0.6)

func _press(b: TButton) -> void:
	match b.id:
		"fire":
			player.set_fire_held(true)
		"reload":
			player.revolver.try_reload()
		"use":
			player.interact()
		"light":
			player.toggle_flashlight()
		"blink":
			player.blink()
		"crouch":
			player.toggle_crouch()
			b.toggled = player.crouching
		"sprint":
			_sprint_toggle = not _sprint_toggle
			b.toggled = _sprint_toggle
			player.touch_sprint = _sprint_toggle
		"pause":
			game.call("toggle_pause")
		"map":
			game.call("toggle_map")

func _release(b: TButton) -> void:
	if b.id == "fire":
		player.set_fire_held(false)

func _process(_delta: float) -> void:
	if player == null:
		return
	var use := _btn("use")
	if use:
		var has := player.get_interact_target() != null
		if has != use.visible:
			use.visible = has
			queue_redraw()
	var cr := _btn("crouch")
	if cr and cr.toggled != player.crouching:
		cr.toggled = player.crouching
		queue_redraw()
	if _sprint_toggle and player.touch_move.length() < 0.1 and _joy_touch == -1:
		pass

func _draw() -> void:
	var a := Settings.f("button_opacity")
	# joystick
	var r := 95.0 * Settings.f("joystick_size")
	if _joy_touch != -1:
		draw_circle(_joy_origin, r, Color(1, 1, 1, 0.08 * a / 0.55))
		draw_arc(_joy_origin, r, 0, TAU, 48, Color(1, 1, 1, 0.45 * a), 3.0, true)
		var knob := _joy_origin + (_joy_pos - _joy_origin).limit_length(r)
		draw_circle(knob, r * 0.42, Color(1, 1, 1, 0.35 * a))
	else:
		var s := get_viewport_rect().size
		var hint := Vector2(s.x - 190, s.y - 190) if Settings.b("left_handed") else Vector2(190, s.y - 190)
		draw_arc(hint, r, 0, TAU, 48, Color(1, 1, 1, 0.18 * a), 2.0, true)
		draw_circle(hint, r * 0.42, Color(1, 1, 1, 0.1 * a))
	for b in buttons:
		if not b.visible:
			continue
		var fill := Color(0.75, 0.1, 0.08, 0.45 * a) if (b.pressed or b.toggled) else Color(0.05, 0.05, 0.06, 0.45 * a)
		draw_circle(b.center, b.radius, fill)
		draw_arc(b.center, b.radius, 0, TAU, 48, Color(1, 1, 1, 0.6 * a), 2.5, true)
		var fs := int(clampf(b.radius * 0.36, 14, 30))
		var ts := _font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(_font, b.center + Vector2(-ts.x * 0.5, ts.y * 0.3), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, minf(1.0, 0.9 * a + 0.3)))
