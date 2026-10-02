extends Control
class_name Minimap
## Facility map overlay (toggle with M / MAP button).

var map: MapBuilder
var player: Player
var game: Node
var _font: Font

const THEME_COL := {
	".": Color(0.35, 0.35, 0.36), "c": Color(0.45, 0.3, 0.2), "o": Color(0.3, 0.38, 0.45),
	"s": Color(0.22, 0.35, 0.5), "k": Color(0.55, 0.15, 0.12), "w": Color(0.4, 0.35, 0.25),
	"e": Color(0.3, 0.45, 0.42), "h": Color(0.4, 0.4, 0.3), "g": Color(0.45, 0.35, 0.15),
	"d": Color(0.35, 0.33, 0.3), "q": Color(0.4, 0.22, 0.3), "v": Color(0.45, 0.18, 0.18),
	"door": Color(0.75, 0.6, 0.15),
}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font

func _process(_d: float) -> void:
	if visible:
		queue_redraw()

func _draw() -> void:
	if map == null:
		return
	var s := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.72))
	var cs := minf((s.x * 0.86) / map.w, (s.y * 0.78) / map.h)
	var org := Vector2((s.x - cs * map.w) * 0.5, (s.y - cs * map.h) * 0.5 + 20)
	for y in map.h:
		for x in map.w:
			var t := map.theme_at(Vector2i(x, y))
			if t == "":
				continue
			var col: Color = THEME_COL.get(t, Color.GRAY)
			draw_rect(Rect2(org + Vector2(x, y) * cs, Vector2(cs, cs)), col)
	# room labels
	var done := {}
	for y in map.h:
		for x in map.w:
			var t := map.theme_at(Vector2i(x, y))
			if t == "" or t == "." or t == "door" or done.has(t + str(x / 10) + str(y / 8)):
				continue
			done[t + str(x / 10) + str(y / 8)] = true
			var nm: String = MapBuilder.ROOM_NAMES.get(t, "")
			var p := org + Vector2(x + 0.3, y + 1.4) * cs
			draw_string(_font, p, nm.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, cs * 7.5, int(cs * 0.42), Color(1, 1, 1, 0.75))
	# keypad
	if map.keypad_cell.x >= 0:
		var kp := org + (Vector2(map.keypad_cell) + Vector2(0.5, 0.5)) * cs
		draw_circle(kp, cs * 0.45, Color(1, 0.2, 0.15))
		draw_string(_font, kp + Vector2(cs * 0.6, cs * 0.3), "WARHEAD TERMINAL", HORIZONTAL_ALIGNMENT_LEFT, -1, int(cs * 0.45), Color(1, 0.5, 0.4))
	# player arrow
	var pp := org + Vector2(player.global_position.x, player.global_position.z) / MapBuilder.CELL * cs
	var fwd3 := -player.global_transform.basis.z
	var fwd := Vector2(fwd3.x, fwd3.z).normalized()
	var side := Vector2(-fwd.y, fwd.x)
	var pts := PackedVector2Array([pp + fwd * cs * 0.9, pp - fwd * cs * 0.5 + side * cs * 0.5, pp - fwd * cs * 0.5 - side * cs * 0.5])
	draw_colored_polygon(pts, Color(0.2, 1.0, 0.3))
	draw_string(_font, Vector2(org.x, org.y - 18), "SITE-19 :: SECTOR 3 MAP      (fragments found: %d/4)" % int(game.get("fragments_found")), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.9, 0.9))
