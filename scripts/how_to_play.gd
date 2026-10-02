extends Control
class_name HowToPlay
## Instructions screen.

const TEXT := """[b]OBJECTIVE[/b]
A containment breach has occurred. Find the [color=#ff6a5a]4 Alpha Warhead code fragments[/color] hidden on clipboards around the facility. Each one reveals one digit. Enter the full 4-digit code at the terminal in the [b]Control Room[/b] (north-east) to nuke everything.

[b]THREATS[/b]
[color=#e8c36a]SCP-173[/color] - The Sculpture. It can only move when nobody is looking. Keep your eyes on it and don't blink near it. Bullets do nothing.
[color=#e8c36a]SCP-096[/color] - The Shy Guy. Harmless... unless you see its FACE. Then it screams and comes for you through any door. Approach it only from behind.
[color=#e8c36a]SCP-049[/color] - The Plague Doctor. Slow but relentless; one touch is death. Bullets only make it flinch. It revives dead 049-2 instances.
[color=#e8c36a]SCP-049-2[/color] - Its "cured" victims. They can be shot down with the revolver. Headshots deal far more damage.

[b]SURVIVAL[/b]
- Ammo boxes, flashlight batteries and medkits are scattered everywhere. Walk over them to pick them up.
- Your eyes blink automatically when the BLINK meter runs out. Blink manually at a safe moment to reset it.
- Sprinting is loud and drains stamina. Crouching is quiet. Gunshots attract attention.
- Close doors behind you; 049-2 instances need time to force them open.
- Use the MAP to find your way.

[b]CONTROLS (touch)[/b]
Left side: move (push the stick to the edge to sprint) - Right side: look - FIRE (drag it to aim) - AIM (aim down sights) - RELOAD - USE - LIGHT - BLINK - CROUCH - RUN - MAP - II pause.

[b]CONTROLS (keyboard / mouse / gamepad)[/b]
WASD move - Mouse look - LMB fire - RMB / Q aim down sights - R reload - E use - F flashlight - Space blink - Shift sprint - Ctrl/C crouch - M map - Esc pause - F1 cheats.

[b]CHEATS[/b]
Pause menu > CHEATS: per-SCP ESP, god mode, infinite ammo / stamina / battery, no blinking."""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	UIKit.dim_layer(self, 0.8)
	var p := UIKit.center_panel(self, Vector2(1000, 640))
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UIKit.label("HOW TO PLAY", 32, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.text = TEXT
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", 19)
	r.add_theme_font_size_override("bold_font_size", 21)
	r.scroll_active = true
	v.add_child(r)
	var b := UIKit.button("BACK", queue_free, 240)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
