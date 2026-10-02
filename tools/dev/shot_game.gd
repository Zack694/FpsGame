extends Node
# Dev-only: boots the game scene and captures screenshots from given cells.
# args: shots="cx,cy,yaw[,pitch];..." out=/dir prefix  wait=frames

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	Settings.values["touch_controls"] = int(args.get("touch", "2"))
	var g: Node3D = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(g)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = g
	for n in int(args.get("wait", "30")):
		await get_tree().process_frame
	var player: Player = g.get("player")
	player.died.connect(func(c: String) -> void: print("DIED cause=", c, " at ", player.global_position, " t=", Time.get_ticks_msec()))
	if args.get("god", "0") == "1":
		player.set_physics_process(true)
		g.set("state", "play")
	print("NPCS ", get_tree().get_nodes_in_group("npcs").size(), " LIGHTS ", (g.get("map") as MapBuilder).lights.size(), " DOORS ", (g.get("map") as MapBuilder).doors.size())
	if args.get("freeze", "0") == "1":
		for n in get_tree().get_nodes_in_group("npcs"):
			n.set_physics_process(false)
	# place=script_suffix,cx,cy,yaw;...
	for pl in str(args.get("place", "")).split(";", false):
		var q := pl.split(",")
		for n in get_tree().get_nodes_in_group("npcs"):
			if str(n.get_script().resource_path).ends_with(q[0] + ".gd"):
				(n as Node3D).global_position = (g.get("map") as MapBuilder).cell_center(Vector2i(int(q[1]), int(q[2])), 0.02)
				(n as Node3D).rotation.y = deg_to_rad(float(q[3]))
				break
	var shots: PackedStringArray = str(args.get("shots", "")).split(";", false)
	var i := 0
	for s in shots:
		var p := s.split(",")
		var map: MapBuilder = g.get("map")
		player.global_position = map.cell_center(Vector2i(int(p[0]), int(p[1])), 0.05)
		player.rotation.y = deg_to_rad(float(p[2]))
		if p.size() > 3:
			player.head.rotation.x = deg_to_rad(float(p[3]))
			player.set("_pitch", deg_to_rad(float(p[3])))
		player.blink_meter = 100.0
		print("TELEPORT ", s, " t=", Time.get_ticks_msec())
		for n in int(args.get("settle", "20")):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%02d.png" % [args.get("out", "/root/work/shots/g"), i])
		print("SHOT ", i, " ", s, " fps ", Engine.get_frames_per_second(), " alive ", player.alive)
		i += 1
	get_tree().quit()
