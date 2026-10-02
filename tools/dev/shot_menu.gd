extends Node
# Dev-only: screenshots the main menu with the settings / how-to-play screens open.

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var m: Control = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(m)
	await get_tree().process_frame
	await get_tree().process_frame
	var out: String = args.get("out", "/root/work/shots/m")
	var i := 0
	for which in ["none", "settings", "howto", "cheats"]:
		var extra: Control = null
		if which == "settings":
			extra = SettingsMenu.new()
		elif which == "howto":
			extra = HowToPlay.new()
		elif which == "cheats" and ClassDB.class_exists("Node") and ResourceLoader.exists("res://scripts/cheats_menu.gd"):
			extra = (load("res://scripts/cheats_menu.gd") as GDScript).new()
		if extra:
			m.add_child(extra)
		for n in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [out, i])
		i += 1
		if extra:
			extra.queue_free()
	get_tree().quit()
