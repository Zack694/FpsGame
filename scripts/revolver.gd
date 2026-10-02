extends Node3D
class_name Revolver
## First-person .357 revolver (detailed CSG model baked to meshes), firing, reload, ADS, viewmodel motion.

signal fired
signal ammo_changed(mag: int, reserve: int)

const MAG_SIZE := 6
const FIRE_DELAY := 0.42
const RANGE := 70.0
const VIEW_LAYER := 2
const U := 0.04 # model units -> metres (model is built in "profile units", barrel along +X)
const SIGHT_Y := 1.04 # height of the sight line in model units

var mag := 6
var reserve := 12
var player: Node # Player
var reloading := false
var infinite_ammo: bool:
	get:
		return Settings.cheat("inf_ammo")
	set(v):
		pass
var aiming := false
var ads := 0.0 # 0 hip .. 1 aimed

var _cool := 0.0
var _model: Node3D # rotated so the barrel points -Z
var _gun: Node3D # kick / tilt pivot
var _cyl_crane: Node3D
var _cyl: Node3D
var _hammer: Node3D
var _trigger: Node3D
var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _kick := 0.0
var _bob_t := 0.0
var _hip := Vector3(0.15, -0.15, -0.36)
var _ads_pos := Vector3(0.0, -SIGHT_Y * U - 0.004, -0.42)
var _lower := 0.0
var _reload_tw: Tween
var _mat_steel: StandardMaterial3D
var _mat_dark: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_brass: StandardMaterial3D
var _mat_copper: StandardMaterial3D

func _ready() -> void:
	position = _hip
	_gun = Node3D.new()
	add_child(_gun)
	_model = Node3D.new()
	_model.rotation.y = PI * 0.5 # +X (profile forward) -> -Z
	_model.scale = Vector3.ONE * U
	_gun.add_child(_model)
	_make_materials()
	_build_frame()
	_build_barrel()
	_build_cylinder()
	_build_action()
	_build_grip()
	_set_layers(_model)
	# viewmodel-only key + rim lights (only affect layer 2 = the gun)
	for l: Array in [[Vector3(-0.25, 0.25, 0.15), 0.9, Color(1.0, 0.95, 0.88)], [Vector3(0.3, 0.1, -0.35), 0.5, Color(0.7, 0.8, 1.0)]]:
		var vl := OmniLight3D.new()
		vl.light_cull_mask = VIEW_LAYER
		vl.light_color = l[2]
		vl.light_energy = l[1]
		vl.light_specular = 1.0
		vl.omni_range = 1.5
		vl.position = l[0]
		add_child(vl)
	# muzzle flash
	_flash = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.15, 0.15)
	_flash.mesh = qm
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = load("res://assets/textures/flash.jpg")
	fm.albedo_color = Color(1, 0.8, 0.5)
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flash.material_override = fm
	_flash.position = Vector3(0, BORE_Y() * U, -5.5 * U)
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

static func BORE_Y() -> float:
	return 0.45

# ------------------------------------------------------------------ materials
func _make_materials() -> void:
	_mat_steel = StandardMaterial3D.new()
	_mat_steel.albedo_color = Color(0.27, 0.3, 0.35)
	_mat_steel.metallic = 0.75
	_mat_steel.roughness = 0.28
	_mat_steel.metallic_specular = 0.8
	_mat_steel.rim_enabled = true
	_mat_steel.rim = 0.25
	_mat_steel.rim_tint = 0.6
	_mat_dark = StandardMaterial3D.new()
	_mat_dark.albedo_color = Color(0.13, 0.135, 0.15)
	_mat_dark.metallic = 0.7
	_mat_dark.roughness = 0.4
	_mat_wood = StandardMaterial3D.new()
	_mat_wood.albedo_texture = load("res://assets/textures/wood.jpg")
	_mat_wood.albedo_color = Color(0.62, 0.36, 0.2)
	_mat_wood.uv1_triplanar = true
	_mat_wood.uv1_scale = Vector3(0.35, 0.35, 0.35)
	_mat_wood.roughness = 0.35
	_mat_wood.clearcoat_enabled = true
	_mat_wood.clearcoat = 0.6
	_mat_brass = StandardMaterial3D.new()
	_mat_brass.albedo_color = Color(0.85, 0.66, 0.28)
	_mat_brass.metallic = 0.9
	_mat_brass.roughness = 0.25
	_mat_copper = StandardMaterial3D.new()
	_mat_copper.albedo_color = Color(0.72, 0.42, 0.26)
	_mat_copper.metallic = 0.9
	_mat_copper.roughness = 0.3

# ------------------------------------------------------------------ CSG helpers (profile in XY, extruded along Z)
func _bake(csg: CSGShape3D, parent: Node3D, mat: Material) -> CSGShape3D:
	# CSG roots are evaluated once (the gun never changes shape) and then render as a plain mesh.
	if csg.get_parent() == null:
		parent.add_child(csg)
	if mat:
		csg.material_override = mat
	return csg

func _poly(pts: Array, depth: float, mat: Material, parent: Node3D, z: float = 0.0) -> CSGPolygon3D:
	var c := CSGPolygon3D.new()
	var arr := PackedVector2Array()
	for p: Vector2 in pts:
		arr.append(p)
	c.polygon = arr
	c.depth = depth
	c.position.z = z + depth # CSGPolygon3D extrudes along -Z
	c.material = mat
	c.smooth_faces = false
	parent.add_child(c)
	return c

func _cyl_x(r: float, length: float, pos: Vector3, mat: Material, parent: Node3D, sides: int = 28, op: int = 0) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.radius = r
	c.height = length
	c.sides = sides
	c.position = pos
	c.rotation.z = PI * 0.5
	c.material = mat
	c.operation = op
	c.smooth_faces = true
	parent.add_child(c)
	return c

func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D, op: int = 0) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.material = mat
	b.operation = op
	parent.add_child(b)
	return b

func _arc(cx: float, cy: float, r: float, a0: float, a1: float, n: int) -> Array:
	var out: Array = []
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		out.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
	return out

# ------------------------------------------------------------------ parts
func _build_frame() -> void:
	var comb := CSGCombiner3D.new()
	_model.add_child(comb)
	var outline: Array = [Vector2(1.25, 0.95), Vector2(-1.0, 0.95)]
	outline += _arc(-1.0, 0.6, 0.35, PI * 0.5, PI * 0.95, 6)
	outline += [Vector2(-1.55, 0.6), Vector2(-1.75, 0.25), Vector2(-2.05, -0.45), Vector2(-1.35, -0.6),
		Vector2(-1.1, -0.9), Vector2(-0.85, -0.95), Vector2(1.25, -0.95)]
	_poly(outline, 0.62, _mat_steel, comb, -0.31)
	# cylinder window
	_box(Vector3(1.72, 1.62, 1.0), Vector3(0, 0.01, 0), _mat_steel, comb, CSGShape3D.OPERATION_SUBTRACTION)
	# top strap groove for the rear sight
	_box(Vector3(0.6, 0.08, 0.12), Vector3(-0.75, 0.97, 0), _mat_steel, comb, CSGShape3D.OPERATION_SUBTRACTION)
	# rear sight
	for zz: float in [-0.085, 0.085]:
		_box(Vector3(0.28, 0.13, 0.07), Vector3(-0.75, 1.02, zz), _mat_dark, comb)
	# side plate screws + cylinder release latch
	for p: Vector2 in [Vector2(-0.95, -0.65), Vector2(-1.25, 0.05), Vector2(1.05, -0.6)]:
		var sc := CSGCylinder3D.new()
		sc.radius = 0.05
		sc.height = 0.66
		sc.sides = 12
		sc.rotation.x = PI * 0.5
		sc.position = Vector3(p.x, p.y, 0)
		sc.material = _mat_dark
		comb.add_child(sc)
	_box(Vector3(0.34, 0.14, 0.7), Vector3(-1.22, 0.35, 0.02), _mat_dark, comb)
	_bake(comb, _model, null)
	# trigger guard (torus in the XY plane)
	var tg := CSGTorus3D.new()
	tg.inner_radius = 0.36
	tg.outer_radius = 0.48
	tg.sides = 28
	tg.ring_sides = 10
	tg.rotation.x = PI * 0.5
	tg.scale = Vector3(1.22, 1.0, 1.0)
	tg.position = Vector3(-0.6, -1.3, 0)
	_bake(tg, _model, _mat_steel)

func _build_barrel() -> void:
	var comb := CSGCombiner3D.new()
	_model.add_child(comb)
	_cyl_x(0.3, 4.4, Vector3(3.1, BORE_Y(), 0), _mat_steel, comb, 32)
	# crowned muzzle ring
	_cyl_x(0.27, 0.06, Vector3(5.32, BORE_Y(), 0), _mat_steel, comb, 32)
	# full-length underlug
	var lug := CSGBox3D.new()
	lug.size = Vector3(4.3, 0.5, 0.5)
	lug.position = Vector3(3.05, 0.16, 0)
	comb.add_child(lug)
	_cyl_x(0.25, 4.3, Vector3(3.05, 0.0, 0), _mat_steel, comb, 24)
	# ventilated rib
	_box(Vector3(4.3, 0.1, 0.2), Vector3(3.15, 0.76, 0), _mat_steel, comb)
	_box(Vector3(4.3, 0.07, 0.22), Vector3(3.15, 0.885, 0), _mat_steel, comb)
	var x := 1.4
	while x < 5.0:
		_box(Vector3(0.24, 0.06, 0.3), Vector3(x, 0.82, 0), _mat_steel, comb, CSGShape3D.OPERATION_SUBTRACTION)
		x += 0.42
	# bore + ejector rod hole
	_cyl_x(0.11, 1.0, Vector3(5.0, BORE_Y(), 0), _mat_steel, comb, 20, CSGShape3D.OPERATION_SUBTRACTION)
	_cyl_x(0.065, 0.3, Vector3(5.2, 0.0, 0), _mat_steel, comb, 12, CSGShape3D.OPERATION_SUBTRACTION)
	_bake(comb, _model, _mat_steel)
	# front sight ramp + red insert
	var fs := CSGPolygon3D.new()
	fs.polygon = PackedVector2Array([Vector2(0, 0), Vector2(0.34, 0), Vector2(0.32, 0.17), Vector2(0.16, 0.16), Vector2(0, 0.02)])
	fs.depth = 0.07
	fs.position = Vector3(4.86, 0.92, 0.035)
	_bake(fs, _model, _mat_steel)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(1, 0.12, 0.06)
	red.emission_enabled = true
	red.emission = Color(1, 0.1, 0.03)
	red.emission_energy_multiplier = 2.0
	var ins := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 0.05, 0.075)
	ins.mesh = bm
	ins.material_override = red
	ins.position = Vector3(5.1, 1.06, 0)
	_model.add_child(ins)

func _build_cylinder() -> void:
	# crane pivot below/left of the cylinder axis (swings out to the left for reloading)
	_cyl_crane = Node3D.new()
	_cyl_crane.position = Vector3(0, -0.6, -0.15)
	_model.add_child(_cyl_crane)
	_cyl = Node3D.new()
	_cyl.position = Vector3(0, 0.6, 0.15)
	_cyl_crane.add_child(_cyl)
	var comb := CSGCombiner3D.new()
	_cyl.add_child(comb)
	_cyl_x(0.74, 1.6, Vector3(0.02, 0, 0), _mat_steel, comb, 36)
	for k in 6:
		var a := TAU * k / 6.0
		var fa := a + TAU / 12.0
		# flutes
		_cyl_x(0.17, 1.0, Vector3(0.18, sin(fa) * 0.8, cos(fa) * 0.8), _mat_steel, comb, 14, CSGShape3D.OPERATION_SUBTRACTION)
		# chambers (open at the front)
		_cyl_x(0.17, 0.5, Vector3(0.62, sin(a) * 0.44, cos(a) * 0.44), _mat_steel, comb, 14, CSGShape3D.OPERATION_SUBTRACTION)
	# front chamfer
	_cyl_x(0.08, 0.4, Vector3(0.8, 0, 0), _mat_steel, comb, 12, CSGShape3D.OPERATION_SUBTRACTION)
	_bake(comb, _cyl, _mat_steel)
	# bullet tips visible in the chambers + brass rims at the back
	for k in 6:
		var a := TAU * k / 6.0
		var tip := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.15
		sm.height = 0.3
		sm.radial_segments = 12
		sm.rings = 6
		tip.mesh = sm
		tip.material_override = _mat_copper
		tip.position = Vector3(0.55, sin(a) * 0.44, cos(a) * 0.44)
		tip.scale = Vector3(1.3, 1, 1)
		tip.name = "Round%d" % k
		_cyl.add_child(tip)
		var rim := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.19
		cm.bottom_radius = 0.19
		cm.height = 0.04
		cm.radial_segments = 14
		rim.mesh = cm
		rim.material_override = _mat_brass
		rim.rotation.z = PI * 0.5
		rim.position = Vector3(-0.8, sin(a) * 0.44, cos(a) * 0.44)
		_cyl.add_child(rim)
	# ejector star + rod
	var rod := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 0.06
	rc.bottom_radius = 0.06
	rc.height = 1.2
	rod.mesh = rc
	rod.material_override = _mat_dark
	rod.rotation.z = PI * 0.5
	rod.position = Vector3(1.3, 0, 0)
	_cyl.add_child(rod)

func _build_action() -> void:
	_hammer = Node3D.new()
	_hammer.position = Vector3(-1.2, 0.55, 0)
	_model.add_child(_hammer)
	var hs: Array = [Vector2(0.12, -0.3), Vector2(0.2, 0.1), Vector2(0.2, 0.32), Vector2(-0.05, 0.5),
		Vector2(-0.25, 0.66), Vector2(-0.45, 0.78), Vector2(-0.62, 0.74), Vector2(-0.55, 0.62),
		Vector2(-0.3, 0.42), Vector2(-0.18, 0.1), Vector2(-0.15, -0.3)]
	var hp := _poly(hs, 0.24, _mat_dark, _hammer, -0.12)
	_bake(hp, _hammer, _mat_dark)
	_trigger = Node3D.new()
	_trigger.position = Vector3(-0.5, -0.88, 0)
	_model.add_child(_trigger)
	var ts: Array = [Vector2(0.06, 0), Vector2(0.06, -0.12), Vector2(0.03, -0.32), Vector2(-0.05, -0.48),
		Vector2(-0.22, -0.62), Vector2(-0.27, -0.6), Vector2(-0.14, -0.44), Vector2(-0.1, -0.2), Vector2(-0.1, 0)]
	var tp := _poly(ts, 0.12, _mat_dark, _trigger, -0.06)
	_bake(tp, _trigger, _mat_dark)

func _build_grip() -> void:
	var g: Array = [Vector2(-1.35, -0.52), Vector2(-2.02, -0.4), Vector2(-2.18, -0.75), Vector2(-2.32, -1.2),
		Vector2(-2.45, -1.7), Vector2(-2.55, -2.2), Vector2(-2.5, -2.5), Vector2(-2.38, -2.62),
		Vector2(-1.8, -2.66), Vector2(-1.62, -2.5), Vector2(-1.6, -2.1), Vector2(-1.64, -1.65),
		Vector2(-1.5, -1.25), Vector2(-1.36, -0.95)]
	var comb := CSGCombiner3D.new()
	_model.add_child(comb)
	_poly(g, 0.92, _mat_wood, comb, -0.46)
	# finger grooves on the front strap
	for yy: float in [-1.45, -1.85, -2.25]:
		var cut := CSGCylinder3D.new()
		cut.radius = 0.14
		cut.height = 1.2
		cut.sides = 12
		cut.rotation.x = PI * 0.5
		cut.position = Vector3(-1.52, yy, 0)
		cut.operation = CSGShape3D.OPERATION_SUBTRACTION
		comb.add_child(cut)
	_bake(comb, _model, _mat_wood)
	# grip frame strap (steel backstrap visible between grip panels)
	var strap := CSGPolygon3D.new()
	strap.polygon = PackedVector2Array([Vector2(-2.02, -0.4), Vector2(-2.12, -0.38), Vector2(-2.6, -2.25), Vector2(-2.52, -2.3)])
	strap.depth = 0.5
	strap.position.z = 0.25
	_bake(strap, _model, _mat_steel)
	# grip screw + medallions
	var med := StandardMaterial3D.new()
	med.albedo_color = Color(0.85, 0.68, 0.25)
	med.metallic = 1.0
	med.roughness = 0.2
	for zz: float in [0.475, -0.475]:
		var m := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.09
		cm.bottom_radius = 0.09
		cm.height = 0.03
		m.mesh = cm
		m.material_override = med
		m.rotation.x = PI * 0.5
		m.position = Vector3(-2.0, -1.0, zz)
		_model.add_child(m)

func _set_layers(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).layers = VIEW_LAYER
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_set_layers(c)

# ------------------------------------------------------------------ gameplay
func add_ammo(n: int) -> void:
	reserve += n
	ammo_changed.emit(mag, reserve)

func can_fire() -> bool:
	return _cool <= 0.0 and not reloading

func try_fire(cam: Camera3D, aim_assist: bool) -> void:
	if not can_fire():
		return
	if mag <= 0 and not infinite_ammo:
		_cool = 0.3
		Sfx.play("interact_leverflip", -6.0, 1.6)
		if reserve > 0:
			try_reload()
		return
	if not infinite_ammo:
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
	# double action: hammer back + trigger pull, then drop and advance the cylinder
	var tw3 := create_tween()
	tw3.tween_property(_hammer, "rotation:z", 0.0, 0.03)
	tw3.parallel().tween_property(_trigger, "rotation:z", 0.0, 0.08)
	tw3.parallel().tween_property(_cyl, "rotation:x", _cyl.rotation.x + TAU / 6.0, 0.1)
	_update_rounds()
	_shoot(cam, aim_assist)
	FX.muzzle_smoke(get_tree().current_scene, _flash.global_position - cam.global_transform.basis.z * 0.25, -cam.global_transform.basis.z)
	_flash.scale = Vector3.ONE * lerpf(1.0, 0.6, ads)
	fired.emit()

func _update_rounds() -> void:
	# hide fired rounds' bullet tips (shown again after reloading)
	for k in 6:
		var r := _cyl.get_node_or_null("Round%d" % k) as Node3D
		if r:
			r.visible = infinite_ammo or k < mag

func _shoot(cam: Camera3D, aim_assist: bool) -> void:
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	if aim_assist and ads < 0.5:
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
	var spread := lerpf(0.006, 0.0008, ads)
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
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
	var root := get_tree().current_scene
	if col is Node and (col as Node).has_meta("npc"):
		var npc: Node = (col as Node).get_meta("npc")
		npc.call("take_damage", 45.0, pos, dir)
		if npc.get_script() and str(npc.get_script().resource_path).ends_with("scp173.gd"):
			FX.impact(root, pos, nrm)
		else:
			FX.blood(root, pos, dir, space)
	else:
		_bullet_hole(pos, nrm)
		FX.impact(root, pos, nrm)

func _bullet_hole(pos: Vector3, nrm: Vector3) -> void:
	FX.decal(get_tree().current_scene, pos, nrm, "bullethole1", 0.12, 40.0)

func try_reload() -> void:
	if reloading or mag >= MAG_SIZE or reserve <= 0 or infinite_ammo:
		return
	reloading = true
	aiming = false
	Sfx.play("interact_leverflip", -2.0, 0.8)
	if _reload_tw:
		_reload_tw.kill()
	_reload_tw = create_tween()
	_reload_tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# tilt the gun, swing the cylinder out on its crane, spin, swing back
	_reload_tw.tween_property(_gun, "rotation", Vector3(0.25, 0.35, 0.75), 0.3)
	_reload_tw.tween_property(_cyl_crane, "rotation:x", -1.25, 0.25)
	_reload_tw.tween_callback(func() -> void:
		Sfx.play("interact_pickitem1", -4.0, 1.4)
		for k in 6:
			var r := _cyl.get_node_or_null("Round%d" % k) as Node3D
			if r:
				r.visible = false)
	_reload_tw.tween_property(_gun, "rotation", Vector3(0.6, 0.35, 0.75), 0.25)
	_reload_tw.tween_property(_gun, "rotation", Vector3(0.25, 0.35, 0.75), 0.25)
	_reload_tw.tween_property(_cyl, "rotation:x", _cyl.rotation.x + TAU * 1.5, 0.7)
	_reload_tw.tween_callback(func() -> void:
		Sfx.play("interact_pickitem2", -4.0, 1.5)
		for k in 6:
			var r := _cyl.get_node_or_null("Round%d" % k) as Node3D
			if r:
				r.visible = k < mini(MAG_SIZE, mag + reserve))
	_reload_tw.tween_property(_cyl_crane, "rotation:x", 0.0, 0.18)
	_reload_tw.tween_callback(func() -> void: Sfx.play("interact_leverflip", -2.0, 1.2))
	_reload_tw.tween_property(_gun, "rotation", Vector3.ZERO, 0.28)
	_reload_tw.tween_callback(_finish_reload)

func _finish_reload() -> void:
	var need := MAG_SIZE - mag
	var take := mini(need, reserve)
	mag += take
	reserve -= take
	reloading = false
	_update_rounds()
	ammo_changed.emit(mag, reserve)

func update_view(delta: float, move_speed: float, sprinting: bool, near_wall: bool, look_delta: Vector2) -> void:
	_cool = maxf(0.0, _cool - delta)
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	var want_ads := aiming and not reloading and not sprinting
	ads = move_toward(ads, 1.0 if want_ads else 0.0, delta * 6.0)
	var e := ads * ads * (3.0 - 2.0 * ads) # smoothstep
	_lower = move_toward(_lower, 1.0 if ((near_wall and ads < 0.5) or sprinting) else 0.0, delta * 4.0)
	_bob_t += delta * (move_speed * 1.6)
	var bob_amt := clampf(move_speed / 4.0, 0, 1.5) * lerpf(1.0, 0.15, e)
	var bob := Vector3(sin(_bob_t) * 0.008, -absf(cos(_bob_t)) * 0.008, 0) * bob_amt
	var sway := Vector3(-look_delta.x, look_delta.y, 0) * 0.00025 * lerpf(1.0, 0.2, e)
	var base := _hip.lerp(_ads_pos, e)
	var kick_back := lerpf(0.04, 0.02, e)
	position = position.lerp(base + bob + sway + Vector3(0, -0.09 * _lower, kick_back * _kick + 0.03 * _lower), clampf(delta * 16.0, 0, 1))
	if not reloading:
		var kick_rot := lerpf(0.28, 0.14, e)
		var target_rot := Vector3(kick_rot * _kick - 0.5 * _lower, 0.25 * _lower, 0.3 * _lower)
		_gun.rotation = _gun.rotation.lerp(target_rot, clampf(delta * 16.0, 0, 1))
	# cock the hammer slightly while aiming (single action look)
	if _cool <= 0.0 and not reloading:
		_hammer.rotation.z = lerpf(_hammer.rotation.z, 0.55 * e, clampf(delta * 10.0, 0, 1))
		_trigger.rotation.z = lerpf(_trigger.rotation.z, 0.12 * e, clampf(delta * 10.0, 0, 1))
