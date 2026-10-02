extends Node3D
class_name Revolver
## First-person .357 revolver built from primitives. Handles ammo, firing, reload, viewmodel motion.

signal fired
signal ammo_changed(mag: int, reserve: int)

const MAG_SIZE := 6
const FIRE_DELAY := 0.42
const RANGE := 70.0
const VIEW_LAYER := 2

var mag := 6
var reserve := 12
var player: Node # Player
var reloading := false

var _cool := 0.0
var _gun: Node3D
var _cyl: Node3D
var _hammer: Node3D
var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _kick := 0.0
var _bob_t := 0.0
var _rest := Vector3(0.13, -0.135, -0.36)
var _lower := 0.0
var _reload_tw: Tween

func _ready() -> void:
	position = _rest
	_gun = Node3D.new()
	add_child(_gun)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.16, 0.17, 0.19)
	steel.metallic = 0.85
	steel.roughness = 0.28
	var steel2 := StandardMaterial3D.new()
	steel2.albedo_color = Color(0.09, 0.09, 0.1)
	steel2.metallic = 0.8
	steel2.roughness = 0.4
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = load("res://assets/textures/wood.jpg")
	wood.albedo_color = Color(0.22, 0.11, 0.06)
	wood.roughness = 0.45
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.8, 0.62, 0.25)
	brass.metallic = 1.0
	brass.roughness = 0.3
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(1, 0.15, 0.1)
	red.emission_enabled = true
	red.emission = Color(1, 0.1, 0.05)
	red.emission_energy_multiplier = 1.5
	# barrel (-Z forward)
	_cylinder(_gun, 0.0115, 0.17, Vector3(0, 0.036, -0.125), steel, true)
	_box(_gun, Vector3(0.022, 0.022, 0.15), Vector3(0, 0.014, -0.118), steel)
	_box(_gun, Vector3(0.012, 0.008, 0.17), Vector3(0, 0.052, -0.125), steel2)
	_box(_gun, Vector3(0.004, 0.014, 0.016), Vector3(0, 0.062, -0.2), steel2)
	_box(_gun, Vector3(0.0045, 0.005, 0.006), Vector3(0, 0.066, -0.205), red)
	# frame + top strap + rear sight
	_box(_gun, Vector3(0.03, 0.075, 0.075), Vector3(0, 0.022, -0.005), steel)
	_box(_gun, Vector3(0.026, 0.013, 0.085), Vector3(0, 0.064, -0.01), steel)
	_box(_gun, Vector3(0.016, 0.01, 0.012), Vector3(0, 0.074, 0.03), steel2)
	# cylinder (spins)
	_cyl = Node3D.new()
	_cyl.position = Vector3(0, 0.03, -0.02)
	_gun.add_child(_cyl)
	_cylinder(_cyl, 0.027, 0.052, Vector3.ZERO, steel, true)
	for k in 6:
		var a := TAU * k / 6.0
		var off := Vector3(cos(a) * 0.017, sin(a) * 0.017, 0.026)
		_cylinder(_cyl, 0.0055, 0.004, off, brass, true)
		var flute := _box(_cyl, Vector3(0.006, 0.006, 0.04), Vector3(cos(a + TAU / 12.0) * 0.026, sin(a + TAU / 12.0) * 0.026, 0), steel2)
		flute.rotation.z = a + TAU / 12.0
	# hammer
	_hammer = Node3D.new()
	_hammer.position = Vector3(0, 0.058, 0.035)
	_gun.add_child(_hammer)
	var hm := _box(_hammer, Vector3(0.009, 0.03, 0.012), Vector3(0, 0.01, 0.006), steel2)
	hm.rotation.x = -0.4
	# grip
	var grip := _box(_gun, Vector3(0.03, 0.105, 0.042), Vector3(0, -0.042, 0.05), wood)
	grip.rotation.x = -0.32
	var cap := _box(_gun, Vector3(0.031, 0.012, 0.044), Vector3(0, -0.093, 0.068), steel)
	cap.rotation.x = -0.32
	# trigger guard + trigger
	var guard := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.016
	tm.outer_radius = 0.02
	guard.mesh = tm
	guard.material_override = steel
	guard.position = Vector3(0, -0.018, 0.0)
	guard.rotation.z = PI * 0.5
	guard.layers = VIEW_LAYER
	guard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gun.add_child(guard)
	var trig := _box(_gun, Vector3(0.005, 0.022, 0.007), Vector3(0, -0.016, 0.004), steel2)
	trig.rotation.x = 0.3
	_gun.scale = Vector3.ONE * 1.05
	# viewmodel-only light so the gun is readable in the dark
	var vl := OmniLight3D.new()
	vl.light_cull_mask = VIEW_LAYER
	vl.light_color = Color(0.9, 0.92, 1.0)
	vl.light_energy = 0.3
	vl.omni_range = 1.2
	vl.position = Vector3(-0.15, 0.2, 0.1)
	add_child(vl)
	# muzzle flash
	_flash = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.22, 0.22)
	_flash.mesh = qm
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = load("res://assets/textures/flash.jpg")
	fm.albedo_color = Color(1, 0.8, 0.5)
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.no_depth_test = true
	_flash.material_override = fm
	_flash.position = Vector3(0, 0.05, -0.32)
	_flash.visible = false
	_flash.layers = VIEW_LAYER
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gun.add_child(_flash)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1, 0.75, 0.4)
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = 9.0
	_flash_light.position = Vector3(0, 0.05, -0.5)
	add_child(_flash_light)

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.layers = VIEW_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _cylinder(parent: Node3D, r: float, length: float, pos: Vector3, mat: Material, along_z: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = 18
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	if along_z:
		mi.rotation.x = PI * 0.5
	mi.layers = VIEW_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func add_ammo(n: int) -> void:
	reserve += n
	ammo_changed.emit(mag, reserve)

func can_fire() -> bool:
	return _cool <= 0.0 and not reloading

func try_fire(cam: Camera3D, aim_assist: bool) -> void:
	if not can_fire():
		return
	if mag <= 0:
		_cool = 0.3
		Sfx.play("interact_leverflip", -6.0, 1.6)
		if reserve > 0:
			try_reload()
		return
	mag -= 1
	_cool = FIRE_DELAY
	ammo_changed.emit(mag, reserve)
	Sfx.play("general_gunshot" if randf() < 0.5 else "general_gunshot2", 2.0, randf_range(0.9, 1.0))
	_kick = 1.0
	_flash.visible = true
	_flash.rotation.z = randf() * TAU
	_flash_light.light_energy = 4.0
	var tw := create_tween()
	tw.tween_interval(0.05)
	tw.tween_callback(func() -> void: _flash.visible = false)
	var tw2 := create_tween()
	tw2.tween_property(_flash_light, "light_energy", 0.0, 0.08)
	var tw3 := create_tween()
	tw3.tween_property(_hammer, "rotation:x", 0.0, 0.03)
	tw3.tween_property(_cyl, "rotation:z", _cyl.rotation.z + TAU / 6.0, 0.08)
	_shoot(cam, aim_assist)
	fired.emit()

func _shoot(cam: Camera3D, aim_assist: bool) -> void:
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	if aim_assist:
		var best_dot := cos(deg_to_rad(4.5))
		for n in get_tree().get_nodes_in_group("shootable"):
			var npc := n as Node3D
			if npc == null or not npc.is_inside_tree() or not bool(npc.get("alive")):
				continue
			var target: Vector3 = npc.call("aim_point")
			var to := target - from
			if to.length() > 25.0:
				continue
			var d := to.normalized().dot(dir)
			if d > best_dot:
				var g := get_tree().get_first_node_in_group("game")
				if g and bool(g.call("has_los", from, target)):
					best_dot = d
					dir = dir.lerp(to.normalized(), 0.75).normalized()
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.004).normalized()
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * RANGE, 1 | 8)
	if player:
		q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit["collider"]
	var pos: Vector3 = hit["position"]
	var nrm: Vector3 = hit["normal"]
	if col is Node and (col as Node).has_meta("npc"):
		var npc: Node = (col as Node).get_meta("npc")
		npc.call("take_damage", 45.0, pos, dir)
		_blood(pos, nrm)
	else:
		_bullet_hole(pos, nrm)

func _bullet_hole(pos: Vector3, nrm: Vector3) -> void:
	var root := get_tree().current_scene
	var d := Decal.new()
	d.texture_albedo = load("res://assets/textures/bullethole1.png")
	d.size = Vector3(0.14, 0.2, 0.14)
	d.cull_mask = 1
	root.add_child(d)
	d.global_position = pos
	var y := nrm.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var x := y.cross(ref).normalized()
	d.global_basis = Basis(x, y, x.cross(y).normalized()).rotated(y, randf() * TAU)
	get_tree().create_timer(40.0).timeout.connect(d.queue_free)
	_particles(pos + nrm * 0.03, nrm, Color(0.8, 0.7, 0.5), 10)

func _blood(pos: Vector3, nrm: Vector3) -> void:
	_particles(pos, nrm, Color(0.5, 0.02, 0.02), 18)

func _particles(pos: Vector3, nrm: Vector3, col: Color, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = nrm
	p.spread = 35.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.02
	p.scale_amount_max = 0.05
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = m
	p.mesh = qm
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)

func try_reload() -> void:
	if reloading or mag >= MAG_SIZE or reserve <= 0:
		return
	reloading = true
	Sfx.play("interact_leverflip", -2.0, 0.8)
	if _reload_tw:
		_reload_tw.kill()
	_reload_tw = create_tween()
	_reload_tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_reload_tw.tween_property(_gun, "rotation", Vector3(0.35, 0.3, 0.9), 0.35)
	_reload_tw.parallel().tween_property(_cyl, "position:x", -0.035, 0.3)
	_reload_tw.tween_callback(func() -> void: Sfx.play("interact_pickitem1", -4.0, 1.4))
	_reload_tw.tween_property(_cyl, "rotation:z", _cyl.rotation.z + TAU * 2.0, 1.1)
	_reload_tw.tween_callback(func() -> void: Sfx.play("interact_pickitem2", -4.0, 1.5))
	_reload_tw.tween_property(_cyl, "position:x", 0.0, 0.2)
	_reload_tw.tween_callback(func() -> void: Sfx.play("interact_leverflip", -2.0, 1.2))
	_reload_tw.tween_property(_gun, "rotation", Vector3.ZERO, 0.3)
	_reload_tw.tween_callback(_finish_reload)

func _finish_reload() -> void:
	var need := MAG_SIZE - mag
	var take := mini(need, reserve)
	mag += take
	reserve -= take
	reloading = false
	_hammer.rotation.x = 0.0
	ammo_changed.emit(mag, reserve)

func update_view(delta: float, move_speed: float, sprinting: bool, near_wall: bool, look_delta: Vector2) -> void:
	_cool = maxf(0.0, _cool - delta)
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	_lower = move_toward(_lower, 1.0 if (near_wall or sprinting) else 0.0, delta * 4.0)
	_bob_t += delta * (move_speed * 1.6)
	var bob := Vector3(sin(_bob_t) * 0.008, -absf(cos(_bob_t)) * 0.008, 0) * clampf(move_speed / 4.0, 0, 1.5)
	var sway := Vector3(-look_delta.x, look_delta.y, 0) * 0.00025
	position = position.lerp(_rest + bob + sway + Vector3(0, -0.09 * _lower, 0.04 * _kick + 0.03 * _lower), clampf(delta * 14.0, 0, 1))
	if not reloading:
		var target_rot := Vector3(0.28 * _kick - 0.5 * _lower, 0.25 * _lower, 0.3 * _lower)
		_gun.rotation = _gun.rotation.lerp(target_rot, clampf(delta * 16.0, 0, 1))
