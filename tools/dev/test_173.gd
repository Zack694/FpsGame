extends Node
# Dev-only: checks SCP-173 visibility logic headlessly.

func _ready() -> void:
	Settings.values["touch_controls"] = 2
	var g: Node3D = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(g)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = g
	var player: Player = g.get("player")
	var map: MapBuilder = g.get("map")
	var s173: Node3D = null
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.get_script().resource_path.ends_with("scp173.gd"):
			s173 = n
	player.global_position = map.cell_center(Vector2i(4, 5), 0.05)
	player.rotation.y = 0.0
	for f in 120:
		await get_tree().physics_frame
		if f % 10 == 0:
			var p: Vector3 = s173.global_position + Vector3(0, 1.1, 0)
			print("f", f, " 173 at ", s173.global_position, " dist ", s173.global_position.distance_to(player.global_position),
				" frustum ", player.camera.is_position_in_frustum(p), " los ", g.call("has_los", player.camera.global_position, p),
				" seen ", s173.call("is_seen"), " alive ", player.alive, " cam ", player.camera.global_position)
	get_tree().quit()
