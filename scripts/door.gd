extends Node3D
## Sliding facility door. Lives in a 3 m door cell; passage runs along local Z.

const P := "res://assets/models/props/"

var heavy := false
var cell := Vector2i.ZERO
var is_open := false
var locked := false
var progress := 0.0 # 0 closed .. 1 open
var bash_time := 0.0

var _panels: Array[Node3D] = []
var _closed_x: Array[float] = []
var _blocker: CollisionShape3D
var _open_w := 1.5
var _auto_close := 0.0
var _speed := 1.8

func _ready() -> void:
	_speed = 0.7 if heavy else 1.8
	var metal := StandardMaterial3D.new()
	metal.albedo_texture = load("res://assets/textures/metalpanels2.jpg")
	metal.roughness = 0.5
	metal.metallic = 0.5
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.85, 0.65, 0.1) if heavy else Color(0.2, 0.2, 0.22)
	trim.roughness = 0.5
	var open_h := 2.8 if heavy else 2.55
	_open_w = 2.5 if heavy else 1.5
	var side_w := (3.0 - _open_w) * 0.5
	# side wall pieces and lintel (panels slide into the side pieces)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for s: float in [-1.0, 1.0]:
		_wall_piece(body, Vector3(s * (_open_w * 0.5 + side_w * 0.5), 1.6, 0), Vector3(side_w, 3.2, 0.5), metal)
	_wall_piece(body, Vector3(0, open_h + (3.2 - open_h) * 0.5, 0), Vector3(_open_w, 3.2 - open_h, 0.5), metal)
	# hazard trim around the opening (both faces)
	for z: float in [-0.26, 0.26]:
		for s: float in [-1.0, 1.0]:
			_deco(Vector3(s * (_open_w * 0.5 + 0.05), open_h * 0.5, z), Vector3(0.1, open_h, 0.03), trim)
		_deco(Vector3(0, open_h + 0.05, z), Vector3(_open_w + 0.2, 0.1, 0.03), trim)
	# panels
	var paths := [P + "ContDoorLeft.glb", P + "ContDoorRight.glb"] if heavy else [P + "Door01.glb", P + "Door01.glb"]
	var pw := _open_w * 0.5
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var holder := Node3D.new()
		var m: Node3D = (load(paths[i]) as PackedScene).instantiate()
		holder.add_child(m)
		var bb := MapBuilder.node_aabb(holder)
		m.scale = Vector3(pw / bb.size.x, open_h / bb.size.y, 0.14 / maxf(bb.size.z, 0.001))
		m.position = -Vector3(bb.get_center().x * m.scale.x, bb.position.y * m.scale.y, bb.get_center().z * m.scale.z)
		if not heavy and i == 1:
			holder.rotation.y = PI
		add_child(holder)
		var cx := side * pw * 0.5
		holder.position = Vector3(cx, 0, 0)
		_panels.append(holder)
		_closed_x.append(cx)
	# blocker collision while closed
	var bbody := StaticBody3D.new()
	bbody.collision_layer = 1
	bbody.collision_mask = 0
	add_child(bbody)
	_blocker = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(_open_w, open_h, 0.2)
	_blocker.shape = bs
	_blocker.position = Vector3(0, open_h * 0.5, 0)
	bbody.add_child(_blocker)
	# buttons on both faces, on the right-hand side piece
	for z: float in [-1.0, 1.0]:
		var bx := (_open_w * 0.5 + side_w * 0.5) * (-z)
		var btn := Node3D.new()
		btn.position = Vector3(bx, 1.25, z * 0.27)
		if z < 0:
			btn.rotation.y = PI
		add_child(btn)
		var bm: Node3D = (load(P + ("ButtonCode.glb" if heavy else "Button.glb")) as PackedScene).instantiate()
		var hb := Node3D.new()
		hb.add_child(bm)
		var bbb := MapBuilder.node_aabb(hb)
		var sc := 0.26 / maxf(bbb.size.y, 0.001)
		bm.scale = Vector3.ONE * sc
		bm.position = -bbb.get_center() * sc
		btn.add_child(hb)
		var ib := StaticBody3D.new()
		ib.collision_layer = MapBuilder.LAYER_INTERACT
		ib.collision_mask = 0
		ib.set_meta("interact", self)
		var ics := CollisionShape3D.new()
		var ibs := BoxShape3D.new()
		ibs.size = Vector3(0.5, 0.6, 0.3)
		ics.shape = ibs
		ib.add_child(ics)
		btn.add_child(ib)

func _wall_piece(body: StaticBody3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)

func _deco(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func get_prompt() -> String:
	if locked:
		return "LOCKED"
	return "Close door" if is_open else "Open door"

func interact(_player: Node) -> void:
	if locked:
		Sfx.play_at("door_doorerror", global_position + Vector3(0, 1.2, 0), 0.0, 15.0)
		return
	Sfx.play_at("interact_button" if randf() < 0.5 else "interact_button2", global_position + Vector3(0, 1.2, 0), -4.0, 10.0)
	set_open(not is_open)
	_auto_close = 0.0

func set_open(v: bool, silent: bool = false) -> void:
	if v == is_open:
		return
	is_open = v
	if silent:
		return
	var snd := ""
	if heavy:
		snd = "door_bigdooropen" if v else "door_bigdoorclose"
	else:
		snd = ("door_dooropen1" if randf() < 0.5 else "door_dooropen2") if v else ("door_doorclose1" if randf() < 0.5 else "door_doorclose2")
	Sfx.play_at(snd, global_position + Vector3(0, 1.4, 0), 0.0, 28.0)

## NPCs call this when they want to pass. Returns true when passable.
func npc_open(force: bool = false, auto_close_after: float = 7.0) -> bool:
	if locked and not force:
		return false
	if not is_open:
		set_open(true)
	_auto_close = auto_close_after
	return progress > 0.7

func slam_open() -> void:
	locked = false
	if not is_open:
		Sfx.play_at("door_dooropen173", global_position + Vector3(0, 1.4, 0), 4.0, 40.0)
		set_open(true, true)
	progress = maxf(progress, 0.6)

func is_passable() -> bool:
	return progress > 0.7

func _physics_process(delta: float) -> void:
	var target := 1.0 if is_open else 0.0
	if progress != target:
		progress = move_toward(progress, target, delta * _speed)
		for i in _panels.size():
			var side := -1.0 if i == 0 else 1.0
			_panels[i].position.x = _closed_x[i] + side * progress * (_open_w * 0.5 + 0.02)
	_blocker.disabled = progress > 0.6
	if _auto_close > 0.0 and is_open:
		_auto_close -= delta
		if _auto_close <= 0.0:
			var blocked := false
			for a in get_tree().get_nodes_in_group("actors"):
				if a is Node3D and (a as Node3D).global_position.distance_to(global_position) < 2.2:
					blocked = true
					break
			if blocked:
				_auto_close = 1.0
			else:
				set_open(false)
