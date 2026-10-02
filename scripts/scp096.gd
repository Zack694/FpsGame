extends NPCBase
## SCP-096: harmless while nobody sees its face. Seeing it = it screams, then charges through everything.

enum S { SIT, WANDER, TRIGGERED, CHASE, CALM }
var state := S.SIT
var home := Vector3.ZERO
var home_yaw := 0.0
var _t := 0.0
var _lost_t := 0.0
var _chase_t := 0.0
var _cry: AudioStreamPlayer3D
var _speed := 7.6

func _ready() -> void:
	setup(get_tree().get_first_node_in_group("game"), "res://assets/models/npc/scp096.glb", 0.42, 2.3)
	_speed = [6.6, 7.6, 8.6][Settings.difficulty] as float
	home = global_position
	home_yaw = rotation.y
	_cry = Sfx.make_loop(self, "music_096", 2.0, 16.0)
	_cry.play()
	play("sit")
	_t = randf_range(60.0, 120.0)

func face_visible() -> bool:
	var face_p := global_position + Vector3(0, 1.75 if state == S.SIT else 2.15, 0) + (-global_transform.basis.z) * 0.25
	if not player.can_see_point(face_p, 30.0):
		return false
	var to_player := flat_dir_to(player.global_position)
	var fwd := -global_transform.basis.z
	fwd.y = 0
	return fwd.normalized().dot(to_player) > 0.15

func _physics_process(delta: float) -> void:
	if not player.alive:
		return
	match state:
		S.SIT:
			play("sit", true, 0.8)
			velocity = Vector3.ZERO
			if face_visible():
				_trigger()
				return
			_t -= delta
			if _t <= 0.0:
				state = S.WANDER
				_t = randf_range(25.0, 40.0)
				set_goal(map.cell_center(map.random_cell_of_theme(["v", "q", "o"][randi() % 3])))
		S.WANDER, S.CALM:
			if face_visible():
				_trigger()
				return
			play("walk", true, 0.9)
			if state == S.CALM:
				set_goal(home)
			navigate(delta, 1.0, 0, 3.0)
			_t -= delta
			if state == S.WANDER and (_t <= 0.0):
				state = S.CALM
			if state == S.CALM and reached_goal(0.9):
				state = S.SIT
				rotation.y = home_yaw
				_t = randf_range(70.0, 140.0)
			elif state == S.WANDER and reached_goal(1.0):
				set_goal(map.cell_center(map.random_cell_of_theme(["v", "q", "o", "."][randi() % 4])))
		S.TRIGGERED:
			velocity = Vector3.ZERO
			face(flat_dir_to(player.global_position), delta, 3.0)
			_t -= delta
			if _cur_anim == "trigger" and anim_progress() >= 0.99:
				play("scream", true, 1.0)
			if _t <= 0.0:
				state = S.CHASE
				_chase_t = 0.0
				_lost_t = 0.0
				game.call("set_music_state", "096chase", true)
		S.CHASE:
			play("run", true, 1.2)
			set_goal(player.global_position)
			navigate(delta, _speed, 1, 10.0)
			_chase_t += delta
			var d := dist_to_player()
			if d < 1.5:
				Sfx.play("scp_096_scream", 6.0)
				player.die("096")
				return
			if bool(game.call("has_los", global_position + Vector3(0, 1.8, 0), player.eye_position())):
				_lost_t = 0.0
			else:
				_lost_t += delta
			if _lost_t > 20.0 and _chase_t > 35.0:
				state = S.CALM
				game.call("set_music_state", "096chase", false)
				_cry.play()

func _trigger() -> void:
	if state == S.TRIGGERED or state == S.CHASE:
		return
	state = S.TRIGGERED
	_t = [7.0, 5.5, 4.0][Settings.difficulty] as float
	_cry.stop()
	play("trigger", false, 1.6, 0.15)
	Sfx.play_at("scp_096_triggered", global_position + Vector3(0, 2, 0), 8.0, 60.0)
	Sfx.play("horror_horror8", 0.0)
	player.shake(0.4)
	game.call("on_096_triggered")

func take_damage(amount: float, pos: Vector3, dir: Vector3) -> void:
	_trigger()

func hear(pos: Vector3, radius_m: float) -> void:
	pass
