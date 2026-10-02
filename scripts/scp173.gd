extends NPCBase
## SCP-173: only moves when nobody is looking (or the player blinks). Snaps necks on contact.

var hunting := false
var _drag: AudioStreamPlayer3D
var _moving := false
var _roam_t := 0.0
var _rattle_cd := 0.0
var _speed := 7.0
var _seen_t := 0.0

func _ready() -> void:
	setup(get_tree().get_first_node_in_group("game"), "res://assets/models/npc/scp173.glb", 0.4, 2.1)
	_speed = [5.5, 7.0, 8.8][Settings.difficulty] as float
	_drag = Sfx.make_loop(self, "scp_173_stonedrag", -2.0, 22.0)
	set_goal(global_position)

func is_seen() -> bool:
	var base := global_position
	var right := global_transform.basis.x * 0.3
	for p: Vector3 in [base + Vector3(0, 0.35, 0), base + Vector3(0, 1.1, 0), base + Vector3(0, 1.95, 0), base + right + Vector3(0, 1.1, 0), base - right + Vector3(0, 1.1, 0)]:
		if player.can_see_point(p, 50.0):
			return true
	return false

func _physics_process(delta: float) -> void:
	if not alive or not player.alive:
		_set_moving(false)
		return
	var seen := is_seen()
	var d := dist_to_player()
	if seen:
		_seen_t = 1.0
		_set_moving(false)
		hunting = true
		return
	_seen_t = maxf(0.0, _seen_t - delta)
	# decide target
	var path_len := d
	if not hunting and d < 22.0:
		hunting = true
	if hunting and d > 34.0 and not bool(game.call("has_los", global_position + Vector3(0, 1.5, 0), player.eye_position())):
		hunting = false
	if hunting:
		set_goal(player.global_position)
		_moving = navigate(delta, _speed, 0, 7.0)
		if d < 1.25:
			_kill()
			return
	else:
		_roam_t -= delta
		if _roam_t <= 0.0 or reached_goal(1.0):
			_roam_t = randf_range(10.0, 25.0)
			set_goal(map.cell_center(map.random_walkable_cell()))
		_moving = navigate(delta, _speed * 0.45, 0, 5.0)
	_set_moving(_moving and velocity.length() > 0.2)
	_rattle_cd -= delta
	if _rattle_cd <= 0.0 and d < 18.0:
		_rattle_cd = randf_range(4.0, 9.0)
		Sfx.play_at(Sfx.pick(["scp_173_rattle1", "scp_173_rattle2", "scp_173_rattle3"]), global_position + Vector3(0, 1, 0), 0.0, 20.0)
	if hunting:
		face_now(flat_dir_to(player.global_position))

func _set_moving(v: bool) -> void:
	if v and not _drag.playing:
		_drag.play()
	elif not v and _drag.playing:
		_drag.stop()

func _kill() -> void:
	var toward := flat_dir_to(player.global_position)
	global_position = player.global_position - toward * 0.9
	face_now(toward)
	Sfx.play(Sfx.pick(["scp_173_necksnap1", "scp_173_necksnap2", "scp_173_necksnap3"]), 6.0)
	player.die("173")

func take_damage(amount: float, pos: Vector3, dir: Vector3) -> void:
	Sfx.play_at("interact_leverflip", pos, 0.0, 15.0, 0.6)

func hear(pos: Vector3, radius_m: float) -> void:
	if global_position.distance_to(pos) < radius_m * 0.8:
		hunting = true
