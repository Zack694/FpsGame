extends NPCBase
## SCP-049-2 instance: slow, relentless, can be shot down (and revived by SCP-049).

enum S { IDLE, LYING, RISE, CHASE, ATTACK, DEAD }
var state := S.IDLE
var hp := 100.0
var start_lying := false
var _t := 0.0
var _hit_done := false
var _speed := 2.0
var _dmg := 22.0
var _breath: AudioStreamPlayer3D
var _wander := Vector3.ZERO
var _col: CollisionShape3D

func _ready() -> void:
	setup(get_tree().get_first_node_in_group("game"), "res://assets/models/npc/zombie.glb", 0.33, 1.75)
	add_to_group("shootable")
	add_to_group("zombies")
	_col = get_child(0) as CollisionShape3D
	_speed = [1.6, 2.1, 2.6][Settings.difficulty] as float
	_dmg = [16.0, 22.0, 30.0][Settings.difficulty] as float
	_breath = Sfx.make_loop(self, "scp_049_0492breath", -4.0, 12.0)
	_breath.play(randf() * 5.0)
	if start_lying:
		state = S.LYING
		play("lying", true, 0.5, 0.0)
	else:
		play("idle", true, randf_range(0.8, 1.1), 0.0)
	if anim:
		anim.seek(randf() * 3.0, true)

func aim_point() -> Vector3:
	return global_position + Vector3(0, 1.3, 0)

func _alerted() -> bool:
	var d := dist_to_player()
	return d < 4.5 or sees_player(13.0, 140.0, 1.6)

func _physics_process(delta: float) -> void:
	if state == S.DEAD:
		return
	if not player.alive:
		play("idle")
		return
	match state:
		S.LYING:
			if _alerted():
				state = S.RISE
				play("standup", false, 4.2, 0.1)
		S.IDLE:
			velocity = Vector3.ZERO
			play("idle", true)
			if _alerted():
				state = S.CHASE
		S.RISE:
			velocity = Vector3.ZERO
			if anim_progress() >= 0.98:
				state = S.CHASE
		S.CHASE:
			play("walk", true, _speed * 0.62)
			set_goal(player.global_position)
			navigate(delta, _speed, 2, 6.0)
			if dist_to_player() < 1.45:
				state = S.ATTACK
				_hit_done = false
				play("attack1" if randf() < 0.5 else "attack2", false, 1.25, 0.1)
			elif dist_to_player() > 30.0:
				state = S.IDLE
		S.ATTACK:
			velocity = Vector3.ZERO
			face(flat_dir_to(player.global_position), delta, 6.0)
			var p := anim_progress()
			if not _hit_done and p > 0.42:
				_hit_done = true
				if dist_to_player() < 1.9:
					player.damage(_dmg, "0492")
			if p >= 0.98:
				state = S.CHASE

func take_damage(amount: float, pos: Vector3, dir: Vector3) -> void:
	if state == S.DEAD:
		return
	var head := pos.y - global_position.y > 1.5
	hp -= amount * (2.6 if head else 1.0)
	if state == S.IDLE or state == S.LYING:
		state = S.CHASE if state == S.IDLE else S.RISE
		if state == S.RISE:
			play("standup", false, 4.2, 0.1)
	if hp <= 0.0:
		_die()

func _die() -> void:
	state = S.DEAD
	alive = false
	velocity = Vector3.ZERO
	play("death", false, 1.0, 0.1)
	_breath.stop()
	FX.blood_pool(get_tree().current_scene, global_position)
	collision_layer = 0
	collision_mask = 1
	remove_from_group("actors")
	add_to_group("corpses")
	game.call("on_zombie_killed")

func revive() -> void:
	if state != S.DEAD:
		return
	hp = 100.0
	alive = true
	collision_layer = 4 | 8
	collision_mask = 1 | 2 | 4
	add_to_group("actors")
	remove_from_group("corpses")
	state = S.RISE
	_breath.play()
	play("standup", false, 4.2, 0.2)

func hear(pos: Vector3, radius_m: float) -> void:
	if state == S.DEAD:
		return
	if global_position.distance_to(pos) < radius_m * 0.7:
		if state == S.IDLE:
			state = S.CHASE
		elif state == S.LYING:
			state = S.RISE
			play("standup", false, 4.2, 0.1)
