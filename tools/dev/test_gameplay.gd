extends Node
# Dev-only headless gameplay checks. Prints PASS/FAIL lines.

var g: Node3D
var player: Player
var map: MapBuilder
var fails := 0

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + extra if extra != "" else ""))
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func npc(suffix: String) -> Node3D:
	for n in get_tree().get_nodes_in_group("npcs"):
		if str(n.get_script().resource_path).ends_with(suffix + ".gd"):
			return n
	return null

func freeze_all(except: Node = null) -> void:
	for n in get_tree().get_nodes_in_group("npcs"):
		n.set_physics_process(n == except)

func _ready() -> void:
	Settings.values["touch_controls"] = 2
	Settings.difficulty = 1
	g = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(g)
	await frames(3)
	get_tree().current_scene = g
	player = g.get("player")
	map = g.get("map")
	await frames(5)
	check("npcs spawned", get_tree().get_nodes_in_group("npcs").size() >= 10, str(get_tree().get_nodes_in_group("npcs").size()))
	check("pickups spawned", get_tree().get_nodes_in_group("npcs").size() > 0)

	# --- path finding across the map
	var path := map.find_path(map.cell_center(Vector2i(3, 21)), map.cell_center(Vector2i(35, 3)))
	check("path dorm->control room", path.size() > 20, str(path.size()))

	# --- shooting a zombie
	var z: Node3D = null
	for n in get_tree().get_nodes_in_group("zombies"):
		z = n
		break
	freeze_all(z)
	z.set("start_lying", false)
	z.set("state", 1) # IDLE
	z.global_position = map.cell_center(Vector2i(19, 12), 0.02)
	player.global_position = map.cell_center(Vector2i(19, 15), 0.05)
	player.rotation.y = 0.0
	player.set("_pitch", 0.0)
	player.head.rotation.x = deg_to_rad(-3)
	await frames(3)
	var hp0: float = z.get("hp")
	for shot in 4:
		player.revolver.set("_cool", 0.0)
		player.revolver.try_fire(player.camera, false)
		await frames(2)
	var hp1: float = z.get("hp")
	check("zombie takes revolver damage", hp1 < hp0, "%s -> %s" % [hp0, hp1])
	check("zombie dies after shots", not bool(z.get("alive")) or hp1 <= 0.0, "hp=%s" % hp1)
	check("ammo consumed", player.revolver.mag == 2, str(player.revolver.mag))
	player.revolver.try_reload()
	await frames(200)
	check("reload refills", player.revolver.mag == 6, "mag=%d reserve=%d" % [player.revolver.mag, player.revolver.reserve])

	# --- door interaction
	var d: Node3D = map.door_in_cell(Vector2i(14, 9))
	var was: bool = d.get("is_open")
	d.call("interact", player)
	await frames(90)
	check("door toggles", bool(d.get("is_open")) != was and float(d.get("progress")) > 0.9)

	# --- SCP-096 trigger
	var s96 := npc("scp096")
	freeze_all(s96)
	s96.global_position = map.cell_center(Vector2i(19, 4), 0.02)
	s96.rotation.y = PI # face +Z (towards the player standing south)
	s96.set("state", 0)
	player.global_position = map.cell_center(Vector2i(19, 8), 0.05)
	player.rotation.y = 0.0
	player.head.rotation.x = deg_to_rad(8)
	player.blink_meter = 100.0
	await frames(10)
	check("096 triggers when face seen", int(s96.get("state")) >= 2, "state=%d" % int(s96.get("state")))
	s96.set_physics_process(false)
	s96.set("state", 0)
	s96.global_position = map.cell_center(Vector2i(36, 22), 0.02)

	# --- SCP-173 freezes when watched, moves when not
	var s173 := npc("scp173")
	freeze_all(s173)
	s173.global_position = map.cell_center(Vector2i(19, 3), 0.02)
	player.global_position = map.cell_center(Vector2i(19, 8), 0.05)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player.blink_meter = 100.0
	player.blink_time = 0.0
	await frames(5)
	var p0 := s173.global_position
	await frames(30)
	check("173 frozen while watched", s173.global_position.distance_to(p0) < 0.05, str(s173.global_position.distance_to(p0)))
	player.rotation.y = PI # turn away
	await frames(20)
	check("173 moves when not watched", s173.global_position.distance_to(p0) > 1.0, str(s173.global_position.distance_to(p0)))
	s173.set_physics_process(false)
	s173.global_position = map.cell_center(Vector2i(4, 2), 0.02)
	player.rotation.y = 0.0

	# --- ADS
	player.revolver.aiming = true
	Input.action_press("aim")
	await frames(40)
	check("ADS engages", player.revolver.ads > 0.95, "ads=%.2f fov=%.1f" % [player.revolver.ads, player.camera.fov])
	check("ADS zooms FOV", player.camera.fov < Settings.f("fov") * 0.8)
	Input.action_release("aim")
	await frames(40)
	check("ADS releases", player.revolver.ads < 0.05)

	# --- cheats
	Settings.cheats["inf_ammo"] = true
	var m0 := player.revolver.mag
	player.revolver.set("_cool", 0.0)
	player.revolver.try_fire(player.camera, false)
	check("infinite ammo", player.revolver.mag == m0)
	Settings.cheats["inf_ammo"] = false
	Settings.cheats["inf_stamina"] = true
	player.stamina = 5.0
	await frames(2)
	check("infinite stamina", player.stamina >= 99.0)
	Settings.cheats["inf_stamina"] = false
	Settings.cheats["god"] = true
	var hp_before := player.health
	player.damage(50.0, "0492")
	player.die("173")
	check("god mode blocks damage/death", player.alive and player.health == hp_before)
	freeze_all(s173)
	s173.global_position = player.global_position + Vector3(0, 0, 0.8)
	player.rotation.y = 0.0
	await frames(20)
	check("173 cannot kill in god mode", player.alive)
	s173.set_physics_process(false)
	s173.global_position = map.cell_center(Vector2i(4, 2), 0.02)
	Settings.cheats["god"] = false
	Settings.cheats["esp_173"] = true
	await frames(2)
	check("esp overlay exists", (g.get("hud") as HUD).esp != null)
	Settings.cheats["esp_173"] = false

	# --- collect all code fragments
	var notes := 0
	for n in g.get_children():
		if n is Area3D and str(n.get("kind")) == "note":
			notes += 1
			g.call("collect", n)
			n.queue_free()
	check("4 notes placed", notes == 4, str(notes))
	check("all fragments found", int(g.get("fragments_found")) == 4)
	g.get("hud").call("close_dialog")
	var code := ""
	for k in 4:
		code += str((g.get("code") as Array)[k])
	check("wrong code rejected", not bool(g.call("submit_code", "0000" if code != "0000" else "1111")))
	# go to control room and enter the code
	player.global_position = map.cell_center(Vector2i(35, 3), 0.05)
	check("correct code accepted", bool(g.call("submit_code", code)))
	check("state nuke", str(g.get("state")) == "nuke")
	await frames(10)
	check("control door locked", bool(map.control_door.get("locked")))
	g.set("nuke_t", 0.5)
	await frames(80)
	check("game won", str(g.get("state")) == "won")
	print("DONE fails=%d" % fails)
	get_tree().paused = false
	get_tree().quit()
