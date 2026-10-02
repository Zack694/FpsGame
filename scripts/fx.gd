extends RefCounted
class_name FX
## Textured particle / decal effects (blood, dust, sparks, smoke).

static var _mats: Dictionary = {}
static var _tex: Dictionary = {}

static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load("res://assets/textures/%s.png" % name)
	return _tex[name]

static func _mat(texture: String, additive: bool, unshaded: bool) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [texture, additive, unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(texture)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mats[key] = m
	return m

static func _fade_ramp(c: Color, start_alpha: float = 1.0) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(c.r, c.g, c.b, start_alpha))
	g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	return g

static func _grow(from: float, to: float) -> Curve:
	var cv := Curve.new()
	cv.max_value = maxf(from, to)
	cv.add_point(Vector2(0, from))
	cv.add_point(Vector2(1, to))
	return cv

static func _emit(root: Node, pos: Vector3, dir: Vector3, texture: String, size: float, amount: int, life: float,
		spread: float, vmin: float, vmax: float, gravity: float, color: Color, grow_to: float = 1.0,
		additive: bool = false, unshaded: bool = false, damping: float = 0.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.randomness = 0.5
	p.local_coords = false
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector3(0, -gravity, 0)
	p.damping_min = damping
	p.damping_max = damping
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.scale_amount_curve = _grow(1.0, grow_to) if grow_to != 1.0 else null
	p.color_ramp = _fade_ramp(color, color.a)
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	qm.material = _mat(texture, additive, unshaded)
	p.mesh = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	root.get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)

## Bullet hitting concrete/metal: dust puff, debris and sparks.
static func impact(root: Node, pos: Vector3, nrm: Vector3) -> void:
	_emit(root, pos + nrm * 0.02, nrm, "fx_smoke", 0.18, 5, 0.9, 25.0, 0.3, 1.0, -0.15, Color(0.72, 0.68, 0.6, 0.8), 3.0, false, false, 1.5)
	_emit(root, pos + nrm * 0.02, nrm, "fx_smoke", 0.03, 10, 0.5, 40.0, 1.5, 4.0, 9.8, Color(0.35, 0.32, 0.28), 1.0)
	_emit(root, pos + nrm * 0.02, nrm, "fx_spark", 0.06, 6, 0.18, 50.0, 3.0, 7.0, 4.0, Color(1.0, 0.85, 0.5), 0.5, true, true)

## Bullet hitting flesh: blood spray + droplets, splat decal on the wall behind.
static func blood(root: Node, pos: Vector3, dir: Vector3, space: PhysicsDirectSpaceState3D) -> void:
	_emit(root, pos, -dir * 0.3 + Vector3.UP * 0.2, "fx_blood1", 0.22, 4, 0.5, 40.0, 0.4, 1.2, 1.0, Color(0.55, 0.02, 0.02, 0.9), 2.2)
	_emit(root, pos, dir, "fx_blood2", 0.07, 14, 0.6, 30.0, 2.0, 5.0, 9.8, Color(0.45, 0.0, 0.0), 0.8)
	var q := PhysicsRayQueryParameters3D.create(pos, pos + dir * 3.0, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		decal(root, hit["position"], hit["normal"], "fx_bloodsplat%d" % (1 + randi() % 2), randf_range(0.5, 0.9), 90.0)

static func blood_pool(root: Node, pos: Vector3) -> void:
	decal(root, pos + Vector3(0, 0.05, 0), Vector3.UP, "fx_bloodpool", randf_range(1.2, 1.7), 120.0)

static func muzzle_smoke(root: Node, pos: Vector3, dir: Vector3) -> void:
	_emit(root, pos, dir, "fx_smoke", 0.05, 3, 0.7, 15.0, 0.6, 1.4, -0.2, Color(0.75, 0.75, 0.75, 0.6), 2.5, false, false, 2.5)

static func decal(root: Node, pos: Vector3, nrm: Vector3, texture: String, size: float, life: float) -> void:
	var d := Decal.new()
	d.texture_albedo = tex(texture)
	d.size = Vector3(size, 0.3, size)
	d.cull_mask = 1
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	root.add_child(d)
	d.global_position = pos
	var y := nrm.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var x := y.cross(ref).normalized()
	d.global_basis = Basis(x, y, x.cross(y).normalized()).rotated(y, randf() * TAU)
	root.get_tree().create_timer(life).timeout.connect(d.queue_free)
