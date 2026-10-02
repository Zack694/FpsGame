extends Control
class_name CheatsMenu
## Cheat toggles (pause menu / main menu / F1).

const ITEMS := [
	["ESP", ""],
	["esp_173", "SCP-173 ESP"],
	["esp_096", "SCP-096 ESP"],
	["esp_049", "SCP-049 ESP"],
	["esp_0492", "SCP-049-2 ESP"],
	["PLAYER", ""],
	["god", "God mode"],
	["inf_ammo", "Infinite ammo"],
	["inf_stamina", "Infinite stamina"],
	["inf_battery", "Infinite flashlight battery"],
	["no_blink", "No blinking"],
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	UIKit.dim_layer(self, 0.75)
	var panel := UIKit.center_panel(self, Vector2(620, 640))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(UIKit.label("CHEATS", 34, Color(1, 0.8, 0.3), HORIZONTAL_ALIGNMENT_CENTER))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for it: Array in ITEMS:
		var key: String = it[0]
		if it[1] == "":
			list.add_child(UIKit.label(key, 18, UIKit.ACCENT))
			continue
		var h := HBoxContainer.new()
		h.custom_minimum_size.y = 50
		var l := UIKit.label(it[1], 21)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var c := CheckButton.new()
		c.button_pressed = Settings.cheat(key)
		c.text = "On" if c.button_pressed else "Off"
		c.toggled.connect(func(on: bool) -> void:
			c.text = "On" if on else "Off"
			Settings.set_cheat(key, on))
		h.add_child(c)
		list.add_child(h)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	row.add_child(UIKit.button("ALL OFF", func() -> void:
		for k: String in Settings.CHEAT_KEYS:
			Settings.cheats[k] = false
		Settings.save_settings()
		Settings.changed.emit()
		var p := get_parent()
		queue_free()
		p.add_child(CheatsMenu.new()), 220))
	row.add_child(UIKit.button("BACK", queue_free, 220))
