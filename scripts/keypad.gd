extends Node3D
## Alpha Warhead terminal keypad (sits on a console in the Control Room).

func _ready() -> void:
	var holder := Node3D.new()
	var m: Node3D = (load("res://assets/models/props/ButtonCode.glb") as PackedScene).instantiate()
	holder.add_child(m)
	var bb := MapBuilder.node_aabb(holder)
	var s := 0.42 / maxf(bb.size.y, 0.001)
	m.scale = Vector3.ONE * s
	m.position = -bb.get_center() * s
	holder.rotation.x = -PI * 0.5 + 0.35
	holder.position = Vector3(0, 0.02, 0.05)
	add_child(holder)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.3, 0.2)
	glow.light_energy = 0.8
	glow.omni_range = 2.5
	glow.position = Vector3(0, 0.4, 0.4)
	add_child(glow)
	var body := StaticBody3D.new()
	body.collision_layer = MapBuilder.LAYER_INTERACT
	body.collision_mask = 0
	body.set_meta("interact", self)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.4, 0.8, 0.9)
	cs.shape = bs
	body.add_child(cs)
	add_child(body)

func get_prompt() -> String:
	return "Use Alpha Warhead terminal"

func interact(player: Node) -> void:
	var g := get_tree().get_first_node_in_group("game")
	if g and g.has_method("open_keypad"):
		g.call("open_keypad")
