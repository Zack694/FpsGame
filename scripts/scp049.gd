extends NPCBase
## SCP-049 "The Plague Doctor": hunts the player, cures with a touch, revives dead 049-2 instances.

enum S { WANDER, LOOK, CHASE, SEARCH, REVIVE, STAGGER }
var state := S.WANDER
var _t := 0.0
var _last_seen := Vector3.ZERO
var _lost := 0.0
var _voice_cd := 0.0
var _step_t := 0.0
var _revive_target: Node3D
var _spawn_cd := 0.0
var _chase_speed := 2.9

func _ready() -> void:
	setup(get_tree().get_first_node_in_group("game"), "res://assets/models/npc/scp049.glb", 0.36, 1.95)
	add_to_group("shootable")
	_chase_speed = [2.4, 2.9, 3.4][Settings.difficulty] as float
	_spawn_cd = randf_range(90.0, 150.0)
	_new_wander()

func _new_wander() -> void:
	state = S.WANDER
	var themes := ["", ".", ".", "o", "h", "e", "q", "w", "g"]
	var t: String = themes[randi() % themes.size()]
	var c := map.random_walkable_cell() if t == "" else map.random_cell_of_theme(t)
	set_goal(map.cell_center(c))

func _physics_process(delta: float) -> void:
	if not player.alive:
		play("idle")
		return
	_voice_cd -= delta
	var sees := sees_player(17.0, 130.0, 1.7) or (dist_to_player() < 3.0)
	match state:
		S.WANDER:
			play("walk", true, 1.0)
			navigate(delta, 1.45, 0, 4.0)
			_steps(delta, 0.75)
			if reached_goal(1.0):
				state = S.LOOK
				_t = randf_range(3.0, 6.0)
			if sees:
				_start_chase()
			_check_corpses()
			_spawn_cd -= delta
			if _spawn_cd <= 0.0 and dist_to_player() > 20.0:
				_spawn_cd = randf_range(110.0, 170.0)
				game.call("spawn_zombie_near", global_position)
		S.LOOK:
			play("idle", true)
			velocity = Vector3.ZERO
			_t -= delta
			if sees:
				_start_chase()
			elif _t <= 0.0:
				_new_wander()
		S.CHASE:
			play("chase", true, 1.1)
			if sees:
				_last_seen = player.global_position
				_lost = 0.0
			else:
				_lost += delta
			set_goal(_last_seen if _lost > 0.0 else player.global_position)
			navigate(delta, _chase_speed, 0, 8.0)
			_steps(delta, 0.5)
			if dist_to_player() < 1.3:
				Sfx.play_at("scp_049_kidnap1", global_position + Vector3(0, 1.6, 0), 4.0, 20.0)
				player.die("049")
				return
			if _voice_cd <= 0.0:
				_voice_cd = randf_range(7.0, 12.0)
				_say(["scp_049_spotted1", "scp_049_spotted2", "scp_049_spotted3", "scp_049_spotted4", "scp_049_spotted5"])
			if _lost > 2.0 and reached_goal(1.2) or _lost > 12.0:
				state = S.SEARCH
				_t = 8.0
				game.call("set_music_state", "049chase", false)
		S.SEARCH:
			play("walk", true, 1.0)
			_t -= delta
			if reached_goal(1.0):
				set_goal(map.cell_center(map.nearest_walkable(map.world_to_cell(_last_seen) + Vector2i(randi_range(-3, 3), randi_range(-3, 3)))))
			navigate(delta, 1.6, 0, 4.0)
			_steps(delta, 0.7)
			if _voice_cd <= 0.0:
				_voice_cd = randf_range(6.0, 10.0)
				_say(["scp_049_searching1", "scp_049_searching2", "scp_049_searching3", "scp_049_searching4"])
			if sees:
				_start_chase()
			elif _t <= 0.0:
				_new_wander()
		S.REVIVE:
			velocity = Vector3.ZERO
			if _revive_target and is_instance_valid(_revive_target):
				face(flat_dir_to(_revive_target.global_position), delta)
			play("kill", false, 0.9)
			_t -= delta
			if sees:
				_start_chase()
			elif _t <= 0.0:
				if _revive_target and is_instance_valid(_revive_target):
					_revive_target.call("revive")
				_revive_target = null
				_new_wander()
		S.STAGGER:
			velocity = Vector3.ZERO
			play("idle", true)
			_t -= delta
			if _t <= 0.0:
				_start_chase()

func _start_chase() -> void:
	if state != S.CHASE:
		state = S.CHASE
		_last_seen = player.global_position
		_lost = 0.0
		_voice_cd = 0.0
		game.call("set_music_state", "049chase", true)

func _check_corpses() -> void:
	for z in get_tree().get_nodes_in_group("corpses"):
		var zn := z as Node3D
		if zn and zn.global_position.distance_to(global_position) < 2.6:
			_revive_target = zn
			state = S.REVIVE
			_t = 5.0
			zn.remove_from_group("corpses")
			return

func _steps(delta: float, interval: float) -> void:
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = interval
		Sfx.play_at(Sfx.pick(["scp_049_step1", "scp_049_step2", "scp_049_step3"]), global_position, -4.0, 16.0)

func _say(lines: Array) -> void:
	Sfx.play_at(Sfx.pick(lines), global_position + Vector3(0, 1.7, 0), 3.0, 26.0)

func take_damage(amount: float, pos: Vector3, dir: Vector3) -> void:
	# bullets do not hurt SCP-049, but they make it flinch
	if state != S.STAGGER:
		state = S.STAGGER
		_t = 0.7
	_last_seen = player.global_position

func hear(pos: Vector3, radius_m: float) -> void:
	if state == S.CHASE:
		return
	if global_position.distance_to(pos) < radius_m:
		_last_seen = pos
		state = S.SEARCH
		_t = 10.0
		set_goal(pos)
