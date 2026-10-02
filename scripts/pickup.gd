extends Area3D
## Collectable item: "ammo", "battery", "medkit" or "note" (Alpha Warhead code fragment).

var kind := "ammo"
var amount := 6
var fragment := -1 # for notes: which code digit (0..3)
var _visual: Node3D
var _t := 0.0
var _base_y := 0.0

func _ready() -> void:
	collision_layer = 32
	collision_mask = 2
	monitoring = true
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.95
	cs.shape = sp
	cs.position.y = 0.5
	add_child(cs)
	body_entered.connect(_on_body)
	_visual = Node3D.new()
	add_child(_visual)
	var P := "res://assets/models/props/"
	match kind:
		"ammo":
			_ammo_box()
		"battery":
			_load(P + "Battery.glb", 0.22)
			_visual.rotation.z = PI * 0.5
		"medkit":
			_load(P + "firstaid.glb", 0.45)
		"note":
			_load(P + "clipboard.glb", 0.42)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.85, 0.5)
			l.light_energy = 0.6
			l.omni_range = 1.8
			l.position.y = 0.5
			add_child(l)
	_visual.position.y = 0.35 if kind != "note" else 0.9
	_base_y = _visual.position.y
	_t = randf() * 10.0

func _load(path: String, size: float) -> void:
	var holder := Node3D.new()
	var m: Node3D = (load(path) as PackedScene).instantiate()
	holder.add_child(m)
	var bb := MapBuilder.node_aabb(holder)
	var s := size / maxf(maxf(bb.size.x, bb.size.z), 0.0001)
	m.scale = Vector3.ONE * s
	m.position = -bb.get_center() * s
	_visual.add_child(holder)

func _ammo_box() -> void:
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.26, 0.12, 0.16)
	box.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.3, 0.18)
	m.roughness = 0.7
	box.material_override = m
	_visual.add_child(box)
	var lid := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.24, 0.02, 0.14)
	lid.mesh = lm
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.85, 0.65, 0.25)
	brass.metallic = 1.0
	brass.roughness = 0.3
	brass.emission_enabled = true
	brass.emission = Color(0.4, 0.3, 0.1)
	brass.emission_energy_multiplier = 0.4
	lid.material_override = brass
	lid.position.y = 0.07
	_visual.add_child(lid)

func _process(delta: float) -> void:
	_t += delta
	_visual.rotation.y += delta * 1.2
	_visual.position.y = _base_y + sin(_t * 2.2) * 0.04

func _on_body(body: Node) -> void:
	if not (body is Player):
		return
	var g := get_tree().get_first_node_in_group("game")
	if g and bool(g.call("collect", self)):
		queue_free()
