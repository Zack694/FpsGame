extends Control
class_name ESP
## Cheat overlay: boxes, names and distances for each SCP type, visible through walls.

var player: Player
var _font: Font

const KINDS := {
	"scp173": ["esp_173", "SCP-173", Color(1.0, 0.75, 0.2)],
	"scp096": ["esp_096", "SCP-096", Color(1.0, 0.25, 0.25)],
	"scp049": ["esp_049", "SCP-049", Color(0.75, 0.4, 1.0)],
	"zombie": ["esp_0492", "SCP-049-2", Color(0.35, 1.0, 0.45)],
}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font

func _process(_d: float) -> void:
	queue_redraw()

func _kind_of(n: Node) -> String:
	var path := str(n.get_script().resource_path) if n.get_script() else ""
	for k: String in KINDS.keys():
		if path.ends_with(k + ".gd"):
			return k
	return ""

func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	var cam := player.camera
	var vs := get_viewport_rect().size
	var cam_fwd := -cam.global_transform.basis.z
	for n in get_tree().get_nodes_in_group("npcs"):
		var npc := n as Node3D
		if npc == null:
			continue
		var k := _kind_of(npc)
		if k == "":
			continue
		var info: Array = KINDS[k]
		if not Settings.cheat(info[0]):
			continue
		var dead := not bool(npc.get("alive"))
		var col: Color = info[2]
		if dead:
			col = Color(0.5, 0.5, 0.5, 0.6)
		var h: float = float(npc.get("body_height"))
		var feet := npc.global_position
		var head := feet + Vector3(0, h, 0)
		var dist := cam.global_position.distance_to(feet)
		var to := (feet + Vector3(0, h * 0.5, 0)) - cam.global_position
		if to.dot(cam_fwd) < 0.1:
			# behind the camera: draw an edge arrow
			var dir2 := Vector2(to.dot(cam.global_transform.basis.x), -to.dot(cam.global_transform.basis.y)).normalized()
			if dir2.length() < 0.1:
				dir2 = Vector2(0, 1)
			var edge := vs * 0.5 + dir2 * minf(vs.x, vs.y) * 0.42
			draw_circle(edge, 7, col)
			draw_string(_font, edge + Vector2(10, 5), "%s %dm" % [info[1], int(dist)], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
			continue
		var a := cam.unproject_position(head)
		var b := cam.unproject_position(feet)
		var hh := absf(b.y - a.y)
		var ww := hh * 0.42
		var r := Rect2(Vector2(b.x - ww * 0.5, a.y), Vector2(ww, hh))
		draw_rect(r, col, false, 2.0)
		# corner accents
		var c := minf(ww, hh) * 0.25
		for p: Vector2 in [r.position, r.position + Vector2(r.size.x, 0), r.position + Vector2(0, r.size.y), r.end]:
			draw_circle(p, 2.5, col)
		var label := "%s  %dm%s" % [info[1], int(dist), "  (dead)" if dead else ""]
		var ts := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
		draw_rect(Rect2(Vector2(r.position.x + ww * 0.5 - ts.x * 0.5 - 4, r.position.y - 22), Vector2(ts.x + 8, 19)), Color(0, 0, 0, 0.55))
		draw_string(_font, Vector2(r.position.x + ww * 0.5 - ts.x * 0.5, r.position.y - 7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
		# zombie health bar
		if k == "zombie" and not dead:
			var hp := clampf(float(npc.get("hp")) / 100.0, 0.0, 1.0)
			draw_rect(Rect2(r.position + Vector2(-7, 0), Vector2(4, hh)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(r.position + Vector2(-7, hh * (1.0 - hp)), Vector2(4, hh * hp)), col)
