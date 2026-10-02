extends CharacterBody3D
class_name NPCBase
## Shared NPC logic: model, animation, grid path following, door handling.

var game: Node
var map: MapBuilder
var player: Player
var alive := true
var model: Node3D
var anim: AnimationPlayer
var radius := 0.4
var body_height := 1.8

var _path: PackedVector3Array = PackedVector3Array()
var _path_i := 0
var _repath := 0.0
var _goal := Vector3.ZERO
var _cur_anim := ""
var _door_wait := 0.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO

func setup(g: Node, model_path: String, r: float, height: float) -> void:
	game = g
	map = g.get("map")
	player = g.get("player")
	radius = r
	body_height = height
	add_to_group("actors")
	add_to_group("npcs")
	collision_layer = 4 | 8
	collision_mask = 1 | 2 | 4
	set_meta("npc", self)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = height
	cs.shape = cap
	cs.position.y = height * 0.5
	add_child(cs)
	model = (load(model_path) as PackedScene).instantiate() as Node3D
	add_child(model)
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_last_pos = global_position

func play(anim_name: String, loop: bool = true, speed: float = 1.0, blend: float = 0.25) -> void:
	if anim == null or not anim.has_animation(anim_name):
		return
	var a := anim.get_animation(anim_name)
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	if _cur_anim == anim_name and anim.is_playing():
		anim.speed_scale = speed
		return
	_cur_anim = anim_name
	anim.play(anim_name, blend)
	anim.speed_scale = speed

func anim_progress() -> float:
	if anim == null or anim.current_animation == "":
		return 1.0
	return anim.current_animation_position / maxf(anim.current_animation_length, 0.001)

func aim_point() -> Vector3:
	return global_position + Vector3(0, body_height * 0.6, 0)

func dist_to_player() -> float:
	return global_position.distance_to(player.global_position)

func flat_dir_to(p: Vector3) -> Vector3:
	var d := p - global_position
	d.y = 0
	return d.normalized() if d.length() > 0.001 else Vector3.ZERO

func face(dir: Vector3, delta: float, rate: float = 8.0) -> void:
	if dir.length() < 0.01:
		return
	var target := atan2(dir.x, dir.z) + PI # model faces -Z
	rotation.y = lerp_angle(rotation.y, target, clampf(delta * rate, 0, 1))

func face_now(dir: Vector3) -> void:
	if dir.length() < 0.01:
		return
	rotation.y = atan2(dir.x, dir.z) + PI

## NPC sees the player (eye at `eye_h`) within range and field of view.
func sees_player(max_range: float, fov_deg: float, eye_h: float = 1.6) -> bool:
	if not player.alive:
		return false
	var eye := global_position + Vector3(0, eye_h, 0)
	var tgt := player.eye_position()
	var to := tgt - eye
	if to.length() > max_range:
		return false
	var fwd := -global_transform.basis.z
	fwd.y = 0
	var t2 := to
	t2.y = 0
	if fwd.normalized().dot(t2.normalized()) < cos(deg_to_rad(fov_deg * 0.5)):
		return false
	return bool(game.call("has_los", eye, tgt))

func set_goal(p: Vector3) -> void:
	_goal = p
	_repath = 0.0

func clear_path() -> void:
	_path = PackedVector3Array()
	_path_i = 0

## Moves towards the current goal along the grid path. Returns false while blocked by a door.
func navigate(delta: float, speed: float, door_mode: int = 0, direct_range: float = 5.0) -> bool:
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.4
		_path = map.find_path(global_position, _goal)
		_path_i = 0
	var target := _goal
	var to_goal := _goal - global_position
	to_goal.y = 0
	var direct := to_goal.length() < direct_range and bool(game.call("has_los", global_position + Vector3(0, 1.0, 0), _goal + Vector3(0, 1.0, 0)))
	if not direct:
		while _path_i < _path.size() and Vector2(_path[_path_i].x - global_position.x, _path[_path_i].z - global_position.z).length() < 0.6:
			_path_i += 1
		if _path_i < _path.size():
			target = _path[_path_i]
	# doors in the way
	var here := map.world_to_cell(global_position)
	var ahead := map.world_to_cell(global_position + flat_dir_to(target) * 1.6)
	for c: Vector2i in [here, ahead]:
		var d: Node3D = map.door_in_cell(c)
		if d and not bool(d.call("is_passable")):
			var ok := false
			match door_mode:
				0: # opens doors
					ok = bool(d.call("npc_open", false, 6.0))
				1: # smashes doors
					d.call("slam_open")
					ok = true
				2: # zombies: bang for a while then force
					_door_wait += delta
					if _door_wait > 3.0:
						ok = bool(d.call("npc_open", true, 6.0))
			if not ok:
				velocity = Vector3.ZERO
				return false
	_door_wait = 0.0
	var dir := flat_dir_to(target)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0
	move_and_slide()
	face(dir, delta)
	# unstick
	if global_position.distance_to(_last_pos) < speed * delta * 0.2 and speed > 0.5:
		_stuck_t += delta
		if _stuck_t > 1.2:
			_stuck_t = 0.0
			_repath = 0.0
			global_position += Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	else:
		_stuck_t = 0.0
	_last_pos = global_position
	return true

func reached_goal(tol: float = 0.8) -> bool:
	var d := _goal - global_position
	d.y = 0
	return d.length() < tol

func take_damage(amount: float, pos: Vector3, dir: Vector3) -> void:
	pass

func hear(pos: Vector3, radius_m: float) -> void:
	pass
