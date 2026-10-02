extends RefCounted
class_name UIKit
## Small helpers for building a consistent dark "SCP terminal" style UI in code.

const ACCENT := Color(0.85, 0.12, 0.1)
const TEXT := Color(0.9, 0.9, 0.88)
const DIM := Color(0.6, 0.6, 0.6)

static var _theme: Theme

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 22
	var normal := _box(Color(0.08, 0.08, 0.09, 0.92), Color(0.45, 0.45, 0.45), 2)
	var hover := _box(Color(0.16, 0.05, 0.05, 0.95), ACCENT, 2)
	var pressed := _box(Color(0.3, 0.05, 0.05, 0.95), ACCENT, 3)
	var disabled := _box(Color(0.05, 0.05, 0.05, 0.8), Color(0.25, 0.25, 0.25), 2)
	for cls in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("focus", cls, _box(Color(0, 0, 0, 0), ACCENT, 2))
		t.set_stylebox("disabled", cls, disabled)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_font_size("font_size", cls, 22)
	t.set_stylebox("panel", "Panel", _box(Color(0.04, 0.04, 0.05, 0.94), Color(0.35, 0.35, 0.35), 2))
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.04, 0.04, 0.05, 0.94), Color(0.35, 0.35, 0.35), 2, 18))
	t.set_color("font_color", "Label", TEXT)
	var tab_sel := _box(Color(0.25, 0.05, 0.05, 1), ACCENT, 2)
	var tab_un := _box(Color(0.08, 0.08, 0.09, 1), Color(0.3, 0.3, 0.3), 1)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", hover)
	t.set_stylebox("panel", "TabContainer", _box(Color(0.03, 0.03, 0.04, 0.95), Color(0.3, 0.3, 0.3), 1, 14))
	t.set_font_size("font_size", "TabContainer", 22)
	var grab := StyleBoxFlat.new()
	grab.bg_color = ACCENT
	t.set_stylebox("slider", "HSlider", _box(Color(0.2, 0.2, 0.2), Color(0.3, 0.3, 0.3), 1))
	t.set_stylebox("grabber_area", "HSlider", _box(Color(0.6, 0.1, 0.08), Color(0.6, 0.1, 0.08), 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(Color(0.8, 0.15, 0.1), Color(0.8, 0.15, 0.1), 0))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	_theme = t
	return t

static func _box(bg: Color, border: Color, bw: int, pad: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(4)
	s.content_margin_left = pad + 4
	s.content_margin_right = pad + 4
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s

static func label(text: String, size: int = 22, color: Color = TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func button(text: String, cb: Callable, min_w: float = 320.0, h: float = 58.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, h)
	b.pressed.connect(func() -> void:
		Sfx.play("interact_button", -8.0)
		cb.call())
	return b

static func center_panel(parent: Control, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = theme()
	p.custom_minimum_size = size
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = -size.x * 0.5
	p.offset_right = size.x * 0.5
	p.offset_top = -size.y * 0.5
	p.offset_bottom = size.y * 0.5
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	parent.add_child(p)
	return p

static func dim_layer(parent: Node, alpha: float = 0.7) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, alpha)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.theme = theme()
	parent.add_child(r)
	return r
