extends Node3D
class_name Game
## Game orchestrator: world, actors, items, objectives, nuke ending, pause/death.

var map: MapBuilder
var player: Player
var hud: HUD
var env: Environment
var world_env: WorldEnvironment

var code: Array[int] = [0, 0, 0, 0]
var found: Array[bool] = [false, false, false, false]
var fragments_found := 0
var kills := 0
var elapsed := 0.0
var state := "play" # play | nuke | dead | won
var nuke_t := 0.0
var map_open := false

var _music_flags := {}
var _amb_t := 10.0
var _siren: AudioStreamPlayer
var _paused_by_menu := false
var _last_beep := -1

const NUKE_TIME := 30.0
const DEATH_TEXT := {
	"173": "SCP-173 snapped your neck the moment you looked away.",
	"096": "You saw SCP-096's face. It found you.",
	"049": "SCP-049: \"I sense the pestilence in you... I am the cure.\"",
	"0492": "You were torn apart by an instance of SCP-049-2.",
}

func _ready() -> void:
	add_to_group("game")
	var seed_value := randi()
	_make_environment()
	map = MapBuilder.new()
	map.name = "Map"
	add_child(map)
	map.build(seed_value)
	for n in 4:
		code[n] = randi() % 10
	_spawn_player()
	_spawn_npcs()
	_spawn_items()
	hud = HUD.new()
	add_child(hud)
	hud.setup(self, player)
	player.damaged.connect(func(a: float) -> void: hud.damage_flash(a))
	player.died.connect(_on_player_died)
	player.revolver.reserve = [18, 12, 6][Settings.difficulty] as int
	player.blink_period = [12.0, 9.0, 7.0][Settings.difficulty] as float
	Sfx.music("music_heavycontainment", 3.0, -6.0)
	if not Settings.use_touch():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	hud.message("CONTAINMENT BREACH.\nFind the 4 Alpha Warhead code fragments.", 6.0)
	Settings.changed.connect(_apply_env_settings)

# ------------------------------------------------------------------ setup
func _make_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.09, 0.09, 0.1)
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.03, 0.03, 0.035)
	env.fog_density = 0.03
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 0.85
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	_apply_env_settings()

func _apply_env_settings() -> void:
	var br := Settings.f("brightness")
	env.adjustment_brightness = 0.85 + 0.15 * br
	env.ambient_light_energy = 0.6 + br * 0.6
	env.tonemap_exposure = 0.85 + 0.25 * br
	env.glow_enabled = Settings.b("glow") and Settings.i("quality") > 0

func _spawn_player() -> void:
	player = Player.new()
	player.name = "Player"
	player.game = self
	add_child(player)
	var c: Vector2i = map.cells_of("P")[0]
	player.global_position = map.cell_center(c, 0.05)
	player.rotation.y = PI * 0.5 # face east, towards the dorm door

func _spawn_npc(script_path: String, c: Vector2i, yaw: float) -> Node3D:
	var s: GDScript = load(script_path)
	var n: Node3D = s.new()
	n.position = map.cell_center(c, 0.02)
	n.rotation.y = yaw
	add_child(n)
	return n

func _spawn_npcs() -> void:
	_spawn_npc("res://scripts/scp173.gd", map.cells_of("1")[0], 0.0)
	# SCP-096 sits facing the east wall of its chamber (face +X -> yaw -PI/2)
	_spawn_npc("res://scripts/scp096.gd", map.cells_of("6")[0], -PI * 0.5)
	_spawn_npc("res://scripts/scp049.gd", map.cells_of("4")[0], PI)
	var zc: Array = map.cells_of("z").duplicate()
	zc.shuffle()
	var count := mini(zc.size(), [6, 9, 12][Settings.difficulty] as int)
	for n in count:
		var z: Node3D = load("res://scripts/zombie.gd").new()
		z.set("start_lying", randf() < 0.35)
		z.position = map.cell_center(zc[n], 0.02) + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
		z.rotation.y = randf() * TAU
		add_child(z)

func spawn_zombie_near(pos: Vector3) -> void:
	if get_tree().get_nodes_in_group("zombies").size() >= 16:
		return
	var base := map.world_to_cell(pos)
	for tries in 12:
		var c := base + Vector2i(randi_range(-3, 3), randi_range(-3, 3))
		if map.is_walkable(c) and c != base and map.door_in_cell(c) == null:
			var z: Node3D = load("res://scripts/zombie.gd").new()
			z.set("start_lying", true)
			z.position = map.cell_center(c, 0.02)
			add_child(z)
			return

func _spawn_pickup(kind: String, c: Vector2i, amount: int = 0, fragment: int = -1) -> void:
	var p: Area3D = load("res://scripts/pickup.gd").new()
	p.set("kind", kind)
	p.set("amount", amount)
	p.set("fragment", fragment)
	p.position = map.cell_center(c) + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
	add_child(p)

func _spawn_items() -> void:
	var ammo: Array = map.cells_of("a").duplicate()
	ammo.shuffle()
	var na := mini(ammo.size(), [14, 11, 8][Settings.difficulty] as int)
	for n in na:
		_spawn_pickup("ammo", ammo[n], [6, 6, 4][Settings.difficulty] as int)
	for c: Vector2i in map.cells_of("b"):
		_spawn_pickup("battery", c, 50)
	var med: Array = map.cells_of("+").duplicate()
	med.shuffle()
	for n in mini(med.size(), [5, 4, 3][Settings.difficulty] as int):
		_spawn_pickup("medkit", med[n], 40)
	# code fragments: one always in the starting dorm, three elsewhere
	var notes: Array = map.cells_of("N").duplicate()
	var dorm: Vector2i = notes[0]
	for c: Vector2i in notes:
		if map.theme_at(c) == "d":
			dorm = c
	notes.erase(dorm)
	notes.shuffle()
	var order: Array = [0, 1, 2, 3]
	order.shuffle()
	_spawn_pickup("note", dorm, 0, order[0])
	for n in 3:
		_spawn_pickup("note", notes[n], 0, order[n + 1])

# ------------------------------------------------------------------ queries
func has_los(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func make_noise(pos: Vector3, radius: float) -> void:
	for n in get_tree().get_nodes_in_group("npcs"):
		var npc := n as Node3D
		if npc and npc.global_position.distance_to(pos) < radius:
			npc.call("hear", pos, radius)

func code_display() -> String:
	var s := ""
	for n in 4:
		s += (str(code[n]) if found[n] else "_") + (" " if n < 3 else "")
	return s

func objective_text() -> String:
	match state:
		"nuke":
			return "ALPHA WARHEAD DETONATION IN PROGRESS"
		"won":
			return "Facility purged."
		"dead":
			return ""
	if fragments_found < 4:
		return "Find the Alpha Warhead code fragments (%d/4)" % fragments_found
	return "Enter the code at the terminal in the Control Room"

# ------------------------------------------------------------------ items
func collect(p: Node) -> bool:
	var kind := str(p.get("kind"))
	match kind:
		"ammo":
			var n := int(p.get("amount"))
			player.revolver.add_ammo(n)
			Sfx.play("interact_pickitem0", -2.0)
			hud.message("+%d .357 rounds" % n, 1.6)
		"battery":
			if player.battery >= 99.0:
				return false
			player.battery = minf(100.0, player.battery + 50.0)
			Sfx.play("interact_pickitem1", -2.0)
			hud.message("Flashlight battery +50%", 1.6)
		"medkit":
			if player.health >= 99.0:
				return false
			player.heal(40.0)
			Sfx.play("interact_pickitem2", -2.0)
			hud.message("Medkit: +40 health", 1.6)
		"note":
			var f := int(p.get("fragment"))
			if not found[f]:
				found[f] = true
				fragments_found += 1
			Sfx.play("interact_pickitem2", -2.0)
			var pos_words := ["FIRST", "SECOND", "THIRD", "FOURTH"]
			var body := "Fragment %d of 4\n\n%s digit of the authorization code:\n\n          [  %d  ]\n\nThe full code must be entered at the terminal in the Control Room. Do not let this document leave Site-19.\n\n- O5 Council" % [fragments_found, pos_words[f], code[f]]
			hud.show_note("ALPHA WARHEAD AUTHORIZATION", body)
			if fragments_found == 4:
				hud.message("All fragments found!\nGo to the Control Room terminal.", 5.0)
	return true

# ------------------------------------------------------------------ warhead
func open_keypad() -> void:
	if state != "play":
		return
	if fragments_found < 4:
		hud.message("The terminal requires the full 4-digit code.\nFragments found: %d/4" % fragments_found, 3.0)
	hud.open_keypad()

func submit_code(s: String) -> bool:
	var target := ""
	for n in 4:
		target += str(code[n])
	if s != target:
		Sfx.play("door_doorerror", 0.0)
		return false
	_start_nuke()
	return true

func _start_nuke() -> void:
	state = "nuke"
	nuke_t = NUKE_TIME
	Sfx.play("interact_scanneruse1", 0.0)
	var cd: Node3D = map.control_door
	if cd:
		cd.call("set_open", false)
		cd.set("locked", true)
	map.set_alarm(true)
	Sfx.stop_music(1.0)
	_siren = AudioStreamPlayer.new()
	var s: AudioStream = Sfx.stream("ending_gateb_siren")
	if s is AudioStreamOggVorbis:
		s = s.duplicate()
		(s as AudioStreamOggVorbis).loop = true
	_siren.stream = s
	_siren.bus = "SFX"
	_siren.volume_db = -6.0
	add_child(_siren)
	_siren.play()
	Sfx.play("ending_gateb_detonatingalphawarheads", 4.0)
	hud.message("CODE ACCEPTED.\nAlpha Warhead armed. Control Room sealed.", 5.0)

func _detonate() -> void:
	state = "won"
	if _siren:
		_siren.stop()
	Sfx.play("ending_gateb_nuke1", 8.0)
	Sfx.play("ending_gateb_nuke2", 6.0)
	player.shake(3.0)
	var tw := create_tween()
	tw.tween_method(hud.white_flash, 0.0, 1.0, 0.6)
	tw.tween_interval(1.2)
	tw.tween_callback(func() -> void:
		get_tree().paused = true
		var best := Settings.best_time
		if best < 0.0 or elapsed < best:
			Settings.best_time = elapsed
			Settings.save_settings()
		hud.white_flash(0.0)
		hud.show_win(_stats()))

func _stats() -> String:
	var bt := Settings.best_time
	return "Time: %s   |   049-2 instances neutralized: %d   |   Difficulty: %s%s" % [
		_fmt_time(elapsed), kills, ["Easy", "Normal", "Hard"][Settings.difficulty],
		("\nBest time: " + _fmt_time(bt)) if bt > 0.0 else ""]

func _fmt_time(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]

# ------------------------------------------------------------------ events
func on_096_triggered() -> void:
	hud.message("YOU SAW ITS FACE.\nRUN.", 4.0)
	set_music_state("096angered", true)

func on_zombie_killed() -> void:
	kills += 1

func set_music_state(track: String, on: bool) -> void:
	if state != "play":
		return
	_music_flags[track] = on
	if track == "096chase" and on:
		_music_flags["096angered"] = false
	var pick := "music_heavycontainment"
	var vol := -6.0
	if bool(_music_flags.get("096chase", false)):
		pick = "music_096chase"
		vol = 0.0
	elif bool(_music_flags.get("096angered", false)):
		pick = "music_096angered"
		vol = 0.0
	elif bool(_music_flags.get("049chase", false)):
		pick = "music_049chase"
		vol = -2.0
	Sfx.music(pick, 1.0, vol)

func _on_player_died(cause: String) -> void:
	if state == "won":
		return
	state = "dead"
	Sfx.stop_music(2.0)
	if _siren:
		_siren.stop()
	Sfx.play("horror_horror1", 0.0)
	await get_tree().create_timer(1.8).timeout
	hud.show_game_over(str(DEATH_TEXT.get(cause, "You died.")), _stats())

# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if state == "play" or state == "nuke":
		elapsed += delta
	if state == "nuke":
		nuke_t -= delta
		var sec := int(ceil(nuke_t))
		hud.set_countdown("DETONATION IN %d" % maxi(sec, 0))
		if sec != _last_beep and sec <= 10:
			_last_beep = sec
			Sfx.play("interact_button2", 0.0, 1.5)
		player.shake(0.05 + (1.0 - nuke_t / NUKE_TIME) * 0.15)
		if nuke_t <= 0.0:
			hud.set_countdown("")
			_detonate()
	# random ambience
	_amb_t -= delta
	if _amb_t <= 0.0 and state == "play":
		_amb_t = randf_range(18.0, 40.0)
		var snd := Sfx.pick(["ambient_zone1_ambient1", "ambient_zone1_ambient2", "ambient_zone1_ambient4", "ambient_zone1_ambient5", "ambient_zone1_ambient6", "ambient_zone1_ambient7", "ambient_zone1_ambient9", "horror_horror0", "horror_horror2", "horror_horror3", "horror_horror9", "horror_horror10"])
		var off := Vector3(randf_range(-12, 12), 1.5, randf_range(-12, 12))
		Sfx.play_at(snd, player.global_position + off, -2.0, 40.0)

func handle_pause_input() -> void:
	if map_open:
		toggle_map()
	elif hud.dialog_open() and not get_tree().paused and state == "play":
		hud.close_dialog()
	else:
		toggle_pause()

func toggle_pause() -> void:
	if state == "dead" or state == "won":
		return
	if get_tree().paused:
		for c in hud.root.get_children():
			if c is SettingsMenu or c is HowToPlay or c is CheatsMenu:
				c.queue_free()
		get_tree().paused = false
		hud.close_dialog()
	else:
		if map_open:
			toggle_map()
		hud.show_pause()
		get_tree().paused = true

func toggle_map() -> void:
	if state == "dead" or state == "won" or get_tree().paused:
		return
	map_open = not map_open
	hud.minimap.visible = map_open

func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func to_menu() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if state == "play" and not get_tree().paused and is_inside_tree():
			toggle_pause()
