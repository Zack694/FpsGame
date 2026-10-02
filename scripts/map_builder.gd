extends Node3D
class_name MapBuilder
## Builds the facility from MapData.LAYOUT: chunked meshes, collision, doors,
## lights, props, item/spawn markers and an A* navigation grid.

const CELL := 3.0
const CEIL := 3.2
const CHUNK := 7
const LAYER_WORLD := 1
const LAYER_INTERACT := 16

const FLOOR_CH := ".cowskehgdqvLPN146zab+KxftSCTBDH"
const BLOCK_CH := "xfSCTKB"
const MARK_CH := "LPN146zab+KxftSCTB"

# theme -> [floor, wall, ceiling] material keys
const THEMES := {
	".": ["concrete_floor", "white_wall", "ceiling"],
	"c": ["dirty_metal", "concrete_wall", "metal_panels"],
	"o": ["tile_floor", "office_wall", "ceiling"],
	"s": ["metal_panels", "metal_panels2", "metal_panels"],
	"k": ["metal_panels2", "concrete_wall", "metal_panels"],
	"w": ["concrete_floor", "concrete_wall", "metal_ceiling"],
	"e": ["tile_floor", "white_wall", "ceiling"],
	"h": ["tile_floor", "office_wall", "ceiling"],
	"g": ["dirty_metal", "concrete_wall", "metal_ceiling"],
	"d": ["concrete_floor", "white_wall", "ceiling"],
	"q": ["dirty_metal", "concrete_wall", "metal_panels"],
	"v": ["concrete_floor", "concrete_wall", "metal_panels"],
	"door": ["dirty_metal", "metal_panels2", "metal_panels"],
}
const ROOM_NAMES := {
	"c": "SCP-173 Containment", "o": "Offices", "s": "Server Room", "k": "Control Room",
	"w": "Storage", "e": "Medical Bay", "h": "Cafeteria", "g": "Generator Room",
	"d": "Class-D Dormitory", "q": "SCP-049 Containment", "v": "SCP-096 Containment", ".": "Corridor",
}
const LIGHT_COLORS := {
	".": Color(1.0, 0.9, 0.75), "c": Color(0.85, 0.9, 1.0), "o": Color(1.0, 0.95, 0.85),
	"s": Color(0.6, 0.8, 1.0), "k": Color(0.9, 0.95, 1.0), "w": Color(1.0, 0.85, 0.65),
	"e": Color(0.9, 1.0, 1.0), "h": Color(1.0, 0.92, 0.8), "g": Color(1.0, 0.75, 0.5),
	"d": Color(1.0, 0.9, 0.8), "q": Color(0.95, 0.9, 0.8), "v": Color(1.0, 0.35, 0.3),
}

var w: int = 0
var h: int = 0
var rows: PackedStringArray
var theme: Array = [] # [y][x] -> theme char ("" for solid)
var astar := AStarGrid2D.new()
var markers: Dictionary = {} # char -> Array[Vector2i]
var doors: Array = [] # Door nodes
var door_at: Dictionary = {} # Vector2i -> Door
var lights: Array[OmniLight3D] = []
var flicker: Array = [] # [light, fixture_mesh, base_energy, phase]
var keypad_cell := Vector2i(-1, -1)
var keypad_node: Node3D
var control_door: Node3D

var _mats: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _alarm := false
var _alarm_t := 0.0

func build(seed_value: int) -> void:
	_rng.seed = seed_value
	rows = MapData.LAYOUT
	h = rows.size()
	w = rows[0].length()
	_make_materials()
	_compute_themes()
	_build_geometry()
	_build_collision()
	_build_nav()
	_build_doors()
	_build_lights()
	_build_props()

# ---------------------------------------------------------------- helpers
func ch(c: Vector2i) -> String:
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return "#"
	return rows[c.y][c.x]

func is_floor(c: Vector2i) -> bool:
	return FLOOR_CH.contains(ch(c))

func is_walkable(c: Vector2i) -> bool:
	var s := ch(c)
	return FLOOR_CH.contains(s) and not BLOCK_CH.contains(s)

func cell_center(c: Vector2i, y: float = 0.0) -> Vector3:
	return Vector3(c.x * CELL + CELL * 0.5, y, c.y * CELL + CELL * 0.5)

func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))

func theme_at(c: Vector2i) -> String:
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return ""
	return theme[c.y][c.x]

func room_name_at(p: Vector3) -> String:
	var t := theme_at(world_to_cell(p))
	if t == "door":
		return ""
	return ROOM_NAMES.get(t, "")

func cells_of(marker: String) -> Array:
	return markers.get(marker, [])

func nearest_walkable(c: Vector2i) -> Vector2i:
	if is_walkable(c):
		return c
	for r in range(1, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if is_walkable(n):
					return n
	return c

## Path of world points (cell centres) from a to b.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := nearest_walkable(world_to_cell(from))
	var b := nearest_walkable(world_to_cell(to))
	var out := PackedVector3Array()
	if not astar.is_in_boundsv(a) or not astar.is_in_boundsv(b):
		return out
	var ids := astar.get_id_path(a, b)
	for i in range(1, ids.size()):
		out.append(cell_center(ids[i]))
	if out.size() > 0:
		out[out.size() - 1] = Vector3(to.x, 0, to.z)
	return out

func random_walkable_cell() -> Vector2i:
	for n in 200:
		var c := Vector2i(_rng.randi_range(1, w - 2), _rng.randi_range(1, h - 2))
		if is_walkable(c) and not ("DH".contains(ch(c))):
			return c
	return Vector2i(1, 1)

## Random walkable cell inside a room theme (or corridor if "").
func random_cell_of_theme(t: String) -> Vector2i:
	var cand: Array = []
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			if theme[y][x] == t and is_walkable(c):
				cand.append(c)
	if cand.is_empty():
		return random_walkable_cell()
	return cand[_rng.randi() % cand.size()]

# ---------------------------------------------------------------- materials
func _tex(n: String) -> Texture2D:
	for ext in [".jpg", ".png"]:
		var p := "res://assets/textures/%s%s" % [n, ext]
		if ResourceLoader.exists(p):
			return load(p)
	return null

func _mat(albedo: String, normal: String = "", rough: float = 0.85, metal: float = 0.0, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(albedo)
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = metal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if normal != "":
		m.normal_enabled = true
		m.normal_texture = _tex(normal)
		m.normal_scale = 1.0
	return m

func _make_materials() -> void:
	_mats["concrete_floor"] = _mat("concretefloor", "concretefloorbump", 0.9, 0.0, Color(1.15, 1.15, 1.15))
	_mats["white_wall"] = _mat("whitewall", "whitewallbump", 0.8)
	_mats["ceiling"] = _mat("ceiling", "", 0.9, 0.0, Color(0.75, 0.75, 0.75))
	_mats["dirty_metal"] = _mat("dirtymetal", "dirtymetalbump", 0.65, 0.12, Color(1.2, 1.2, 1.2))
	_mats["concrete_wall"] = _mat("concretewall", "concretewallbump", 0.9)
	_mats["metal_panels"] = _mat("metalpanels", "", 0.6, 0.15, Color(1.5, 1.5, 1.5))
	_mats["metal_panels2"] = _mat("metalpanels2", "", 0.6, 0.15, Color(1.3, 1.3, 1.3))
	_mats["tile_floor"] = _mat("tilefloor", "tilebump", 0.35)
	_mats["office_wall"] = _mat("officewall", "", 0.85)
	_mats["metal_ceiling"] = _mat("metal", "", 0.7, 0.1, Color(0.7, 0.7, 0.7))
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1, 0.97, 0.9)
	lamp.emission_enabled = true
	lamp.emission = Color(1, 0.95, 0.85)
	lamp.emission_energy_multiplier = 2.5
	_mats["lamp"] = lamp
	var lamp_off := StandardMaterial3D.new()
	lamp_off.albedo_color = Color(0.25, 0.25, 0.25)
	lamp_off.roughness = 0.4
	_mats["lamp_off"] = lamp_off

# ---------------------------------------------------------------- themes
func _compute_themes() -> void:
	theme = []
	for y in h:
		var row: Array = []
		for x in w:
			row.append("")
		theme.append(row)
	for y in h:
		for x in w:
			var c := rows[y][x]
			var cell := Vector2i(x, y)
			if c == "#":
				continue
			if "DH".contains(c):
				theme[y][x] = "door"
			elif THEMES.has(c):
				theme[y][x] = c
			elif c == "L":
				theme[y][x] = "."
			if MARK_CH.contains(c):
				if not markers.has(c):
					markers[c] = []
				markers[c].append(cell)
			if "DH".contains(c):
				if not markers.has(c):
					markers[c] = []
				markers[c].append(cell)
	# markers inherit the most common neighbouring theme
	for it in 4:
		for y in h:
			for x in w:
				if rows[y][x] != "#" and theme[y][x] == "":
					var cnt := {}
					for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var t := theme_at(Vector2i(x, y) + d)
						if t != "" and t != "door":
							cnt[t] = int(cnt.get(t, 0)) + 1
					var best := ""
					var bn := 0
					for k: String in cnt.keys():
						if int(cnt[k]) > bn:
							bn = int(cnt[k])
							best = k
					theme[y][x] = best
	for y in h:
		for x in w:
			if rows[y][x] != "#" and theme[y][x] == "":
				theme[y][x] = "."
	keypad_cell = cells_of("K")[0] if cells_of("K").size() > 0 else Vector2i(-1, -1)

# ---------------------------------------------------------------- geometry
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2, uvd: Vector2) -> void:
	# a b c d counter-clockwise seen from the normal side; Godot front faces are clockwise
	for v in [[a, uva], [c, uvc], [b, uvb], [a, uva], [d, uvd], [c, uvc]]:
		st.set_normal(n)
		st.set_uv(v[1])
		st.add_vertex(v[0])

func _st(chunks: Dictionary, key: String) -> SurfaceTool:
	if not chunks.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		chunks[key] = st
	return chunks[key]

func _build_geometry() -> void:
	var by_chunk: Dictionary = {}
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			if not is_floor(c):
				continue
			var ck := Vector2i(x / CHUNK, y / CHUNK)
			if not by_chunk.has(ck):
				by_chunk[ck] = {}
			var chunks: Dictionary = by_chunk[ck]
			var t: String = theme[y][x]
			var tm: Array = THEMES.get(t, THEMES["."])
			var x0 := x * CELL
			var z0 := y * CELL
			var x1 := x0 + CELL
			var z1 := z0 + CELL
			# floor (normal up) : uv tiles once per cell
			var fs := _st(chunks, tm[0])
			_quad(fs, Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3(x1, 0, z0), Vector3(x0, 0, z0), Vector3.UP,
				Vector2(x, y + 1), Vector2(x + 1, y + 1), Vector2(x + 1, y), Vector2(x, y))
			# ceiling (normal down)
			var cs := _st(chunks, tm[2])
			_quad(cs, Vector3(x0, CEIL, z0), Vector3(x1, CEIL, z0), Vector3(x1, CEIL, z1), Vector3(x0, CEIL, z1), Vector3.DOWN,
				Vector2(x, y), Vector2(x + 1, y), Vector2(x + 1, y + 1), Vector2(x, y + 1))
			# walls towards solid neighbours
			var ws := _st(chunks, tm[1])
			var vt := CEIL / CELL
			if not is_floor(c + Vector2i(0, -1)): # north wall at z0, normal +z
				_quad(ws, Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, CEIL, z0), Vector3(x0, CEIL, z0), Vector3(0, 0, 1),
					Vector2(x, vt), Vector2(x + 1, vt), Vector2(x + 1, 0), Vector2(x, 0))
			if not is_floor(c + Vector2i(0, 1)): # south wall at z1, normal -z
				_quad(ws, Vector3(x1, 0, z1), Vector3(x0, 0, z1), Vector3(x0, CEIL, z1), Vector3(x1, CEIL, z1), Vector3(0, 0, -1),
					Vector2(x, vt), Vector2(x + 1, vt), Vector2(x + 1, 0), Vector2(x, 0))
			if not is_floor(c + Vector2i(-1, 0)): # west wall at x0, normal +x
				_quad(ws, Vector3(x0, 0, z1), Vector3(x0, 0, z0), Vector3(x0, CEIL, z0), Vector3(x0, CEIL, z1), Vector3(1, 0, 0),
					Vector2(y, vt), Vector2(y + 1, vt), Vector2(y + 1, 0), Vector2(y, 0))
			if not is_floor(c + Vector2i(1, 0)): # east wall at x1, normal -x
				_quad(ws, Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x1, CEIL, z1), Vector3(x1, CEIL, z0), Vector3(-1, 0, 0),
					Vector2(y, vt), Vector2(y + 1, vt), Vector2(y + 1, 0), Vector2(y, 0))
	for ck: Vector2i in by_chunk.keys():
		var chunks: Dictionary = by_chunk[ck]
		var mesh := ArrayMesh.new()
		for key: String in chunks.keys():
			var st: SurfaceTool = chunks[key]
			st.generate_tangents()
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _mats[key])
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = "Chunk_%d_%d" % [ck.x, ck.y]
		add_child(mi)

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "WorldCollision"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	# floor and ceiling slabs
	var size := Vector3(w * CELL, 1.0, h * CELL)
	for yy: float in [-0.5, CEIL + 0.5]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = Vector3(size.x * 0.5, yy, size.z * 0.5)
		body.add_child(cs)
	# solid cells merged in horizontal runs
	for y in h:
		var x := 0
		while x < w:
			if rows[y][x] == "#":
				var x_start := x
				while x < w and rows[y][x] == "#":
					x += 1
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3((x - x_start) * CELL, CEIL, CELL)
				cs.shape = bs
				cs.position = Vector3((x_start + x) * 0.5 * CELL, CEIL * 0.5, y * CELL + CELL * 0.5)
				body.add_child(cs)
			else:
				x += 1

func _build_nav() -> void:
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in h:
		for x in w:
			astar.set_point_solid(Vector2i(x, y), not is_walkable(Vector2i(x, y)))

# ---------------------------------------------------------------- doors
func _build_doors() -> void:
	var door_script: GDScript = load("res://scripts/door.gd")
	for kind: String in ["D", "H"]:
		for c: Vector2i in cells_of(kind):
			var ns := is_floor(c + Vector2i(0, -1)) and is_floor(c + Vector2i(0, 1))
			var d: Node3D = door_script.new()
			d.heavy = kind == "H"
			d.cell = c
			d.position = cell_center(c)
			# door plane spans x by default (passage along z). Rotate if passage is along x.
			if not ns:
				d.rotation.y = PI * 0.5
			add_child(d)
			doors.append(d)
			door_at[c] = d
			if c == Vector2i(30, 4):
				control_door = d

func door_in_cell(c: Vector2i) -> Node3D:
	return door_at.get(c, null)

# ---------------------------------------------------------------- lights
func _build_lights() -> void:
	var fixture := BoxMesh.new()
	fixture.size = Vector3(1.4, 0.06, 0.3)
	var housing := BoxMesh.new()
	housing.size = Vector3(1.55, 0.08, 0.42)
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			var r := rows[y][x]
			if not is_floor(c) or "DH".contains(r):
				continue
			var t: String = theme[y][x]
			var place := false
			var dark := r == "L"
			if t == ".":
				place = (x + y) % 3 == 0
			elif t == "v":
				place = x == 33 and y == 20
			else:
				place = (x % 3 == 1) and (y % 3 == 1)
			if not place:
				continue
			# orient fixture along corridor
			var along_x := is_floor(c + Vector2i(1, 0)) or is_floor(c + Vector2i(-1, 0))
			if t == "." and is_floor(c + Vector2i(0, 1)) and is_floor(c + Vector2i(0, -1)) and not along_x:
				along_x = false
			var pos := cell_center(c, CEIL - 0.04)
			var hmi := MeshInstance3D.new()
			hmi.mesh = housing
			hmi.material_override = _mats["metal_panels"]
			hmi.position = pos + Vector3(0, -0.0, 0)
			hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(hmi)
			var fmi := MeshInstance3D.new()
			fmi.mesh = fixture
			fmi.position = pos + Vector3(0, -0.05, 0)
			fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(fmi)
			if not along_x:
				hmi.rotation.y = PI * 0.5
				fmi.rotation.y = PI * 0.5
			if dark:
				fmi.material_override = _mats["lamp_off"]
				continue
			var lamp_mat: StandardMaterial3D = _mats["lamp"].duplicate()
			var col: Color = LIGHT_COLORS.get(t, Color.WHITE)
			lamp_mat.emission = col
			fmi.material_override = lamp_mat
			var l := OmniLight3D.new()
			l.position = pos + Vector3(0, -0.35, 0)
			l.light_color = col
			l.omni_range = 7.5 if t == "." else 8.0
			l.light_energy = 0.9 if t == "." else 1.1
			if t == "v":
				l.light_energy = 0.5
			l.omni_attenuation = 1.4
			l.shadow_enabled = false
			l.light_specular = 0.3
			add_child(l)
			lights.append(l)
			if _rng.randf() < 0.18:
				flicker.append([l, lamp_mat, l.light_energy, _rng.randf() * 10.0])

func set_alarm(on: bool) -> void:
	_alarm = on
	for l in lights:
		if on:
			l.light_color = Color(1.0, 0.12, 0.08)

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	if _alarm:
		_alarm_t += delta
		var e := 0.4 + 1.3 * absf(sin(_alarm_t * 3.0))
		for l in lights:
			l.light_energy = e
		return
	for f: Array in flicker:
		var l: OmniLight3D = f[0]
		var m: StandardMaterial3D = f[1]
		var base: float = f[2]
		var ph: float = f[3]
		var n := sin(t * 13.0 + ph) * sin(t * 7.3 + ph * 2.0) + sin(t * 2.1 + ph)
		var on := n > -0.6
		l.light_energy = base * (1.0 if on else 0.05) * (0.85 + 0.15 * sin(t * 50.0 + ph))
		m.emission_energy_multiplier = 2.5 if on else 0.1

# ---------------------------------------------------------------- props
var _model_cache: Dictionary = {}

func _model(path: String) -> Node3D:
	if not _model_cache.has(path):
		_model_cache[path] = load(path)
	var ps: PackedScene = _model_cache[path]
	return ps.instantiate() as Node3D

static func node_aabb(n: Node3D) -> AABB:
	var res := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var xf := n.global_transform.affine_inverse() * mi.global_transform if n.is_inside_tree() else _rel_xf(n, mi)
		var bb := xf * mi.get_aabb()
		res = bb if first else res.merge(bb)
		first = false
	return res

static func _rel_xf(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

## Places a model scaled so its largest horizontal dimension (or height) matches size.
func place_model(path: String, pos: Vector3, yaw: float, size: float, by_height: bool = false, collide: bool = true, parent: Node3D = null) -> Node3D:
	var holder := Node3D.new()
	var m := _model(path)
	holder.add_child(m)
	var bb := node_aabb(holder)
	var dim := bb.size.y if by_height else maxf(bb.size.x, bb.size.z)
	var s := size / maxf(dim, 0.0001)
	m.scale = Vector3.ONE * s
	m.position = -Vector3(bb.get_center().x, bb.position.y, bb.get_center().z) * s
	holder.position = pos
	holder.rotation.y = yaw
	(parent if parent else self).add_child(holder)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = LAYER_WORLD
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bb.size * s
		cs.shape = bs
		cs.position = Vector3(0, bb.size.y * s * 0.5, 0)
		body.add_child(cs)
		holder.add_child(body)
	return holder

func box_prop(pos: Vector3, yaw: float, size: Vector3, mat: Material, collide: bool = true) -> Node3D:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position.y = size.y * 0.5
	holder.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = LAYER_WORLD
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position.y = size.y * 0.5
		body.add_child(cs)
		holder.add_child(body)
	add_child(holder)
	return holder

## Yaw that makes a prop's front (+Z) face away from the nearest wall.
func wall_yaw(c: Vector2i) -> float:
	if not is_floor(c + Vector2i(0, -1)):
		return 0.0 # wall north -> face +z (south)
	if not is_floor(c + Vector2i(0, 1)):
		return PI
	if not is_floor(c + Vector2i(-1, 0)):
		return PI * 0.5
	if not is_floor(c + Vector2i(1, 0)):
		return -PI * 0.5
	return _rng.randf_range(-PI, PI)

## Offset towards the nearest wall so props hug it.
func wall_offset(c: Vector2i, amount: float) -> Vector3:
	if not is_floor(c + Vector2i(0, -1)):
		return Vector3(0, 0, -amount)
	if not is_floor(c + Vector2i(0, 1)):
		return Vector3(0, 0, amount)
	if not is_floor(c + Vector2i(-1, 0)):
		return Vector3(-amount, 0, 0)
	if not is_floor(c + Vector2i(1, 0)):
		return Vector3(amount, 0, 0)
	return Vector3.ZERO

func _build_props() -> void:
	var P := "res://assets/models/props/"
	var wood := _mat("wood", "", 0.6)
	var server_face := _mat("servers1", "", 0.5, 0.3)
	server_face.uv1_scale = Vector3(0.5, 0.5, 1)
	server_face.uv1_offset = Vector3(0.0, 0.5, 0)
	server_face.emission_enabled = true
	server_face.emission_texture = server_face.albedo_texture
	server_face.emission = Color(1, 1, 1)
	server_face.emission_energy_multiplier = 0.12
	server_face.albedo_color = Color(0.55, 0.55, 0.58)
	var rack_mat := _mat("metal", "", 0.5, 0.25, Color(0.35, 0.35, 0.38))
	var console_mat := _mat("controlpanel", "", 0.5, 0.3)
	console_mat.uv1_scale = Vector3(1.0, 0.5, 1)
	console_mat.emission_enabled = true
	console_mat.emission_texture = console_mat.albedo_texture
	console_mat.emission = Color(1, 1, 1)
	console_mat.emission_energy_multiplier = 0.12
	var frame_mat := _mat("metal", "", 0.4, 0.8, Color(0.6, 0.6, 0.6))
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.78, 0.78, 0.74)
	cloth.roughness = 1.0
	var screen_mat := _mat("screen", "", 0.3, 0.0, Color(0.4, 0.45, 0.42))
	screen_mat.emission_enabled = true
	screen_mat.emission_texture = screen_mat.albedo_texture
	screen_mat.emission = Color(0.35, 0.8, 0.55)
	screen_mat.emission_energy_multiplier = 0.35

	for c: Vector2i in cells_of("x"):
		var p := cell_center(c) + Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3))
		var path := P + ("crate1.glb" if _rng.randf() < 0.6 else "crate2.glb")
		place_model(path, p, _rng.randf_range(-0.4, 0.4) + (PI * 0.5 if _rng.randf() < 0.5 else 0.0), 2.0)
		if _rng.randf() < 0.4:
			place_model(P + "crate2.glb", p + Vector3(0, 1.0 if path.ends_with("2.glb") else 1.6, 0), _rng.randf_range(-0.6, 0.6), 1.5)
	for c: Vector2i in cells_of("f"):
		var yaw := wall_yaw(c)
		place_model(P + "cabinet_a.glb", cell_center(c) + wall_offset(c, 1.1), yaw, 2.0, true)
	for c: Vector2i in cells_of("t"):
		var yaw := wall_yaw(c) if wall_offset(c, 1).length() > 0 else 0.0
		var base := cell_center(c) + wall_offset(c, 0.6)
		var desk := box_prop(base, yaw, Vector3(1.9, 0.06, 0.9), wood, false)
		desk.get_child(0).position.y = 0.78
		for lx: float in [-0.85, 0.85]:
			for lz: float in [-0.38, 0.38]:
				var leg := MeshInstance3D.new()
				var lm := BoxMesh.new()
				lm.size = Vector3(0.05, 0.78, 0.05)
				leg.mesh = lm
				leg.material_override = frame_mat
				leg.position = Vector3(lx, 0.39, lz)
				desk.add_child(leg)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.9, 0.82, 0.9)
		cs.shape = bs
		cs.position.y = 0.41
		body.add_child(cs)
		desk.add_child(body)
		place_model(P + "monitor.glb", Vector3(0.2, 0.81, -0.15), PI, 0.55, false, false, desk)
		place_model(P + "keyboard.glb", Vector3(0.2, 0.81, 0.2), PI, 0.45, false, false, desk)
		if _rng.randf() < 0.6:
			place_model(P + "paper.glb", Vector3(-0.55, 0.815, 0.1), _rng.randf_range(-1, 1), 0.3, false, false, desk)
		if _rng.randf() < 0.4:
			place_model(P + "boxfile_a.glb", Vector3(-0.75, 0.81, -0.25), PI * 0.5, 0.3, true, false, desk)
		var chair := place_model(P + "officeseat_a.glb", Vector3(0.2 + _rng.randf_range(-0.2, 0.2), 0, 0.8), _rng.randf_range(-0.7, 0.7), 1.05, true, false, desk)
		chair.rotation.y += PI
	for c: Vector2i in cells_of("S"):
		var p := cell_center(c)
		var rack := box_prop(p, 0.0, Vector3(1.3, 2.3, 1.1), rack_mat)
		for side: float in [1.0, -1.0]:
			var face := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(1.2, 2.2)
			face.mesh = qm
			face.material_override = server_face
			face.position = Vector3(0, 1.15, 0.551 * side)
			if side < 0:
				face.rotation.y = PI
			rack.add_child(face)
	for c: Vector2i in cells_of("C") + cells_of("K"):
		var yaw := wall_yaw(c)
		var p := cell_center(c) + wall_offset(c, 0.9)
		var cons := box_prop(p, yaw, Vector3(2.4, 1.0, 1.0), rack_mat)
		var top := MeshInstance3D.new()
		var tq := QuadMesh.new()
		tq.size = Vector2(2.3, 0.9)
		top.mesh = tq
		top.material_override = console_mat
		top.position = Vector3(0, 1.005, 0)
		top.rotation.x = -PI * 0.5
		cons.add_child(top)
		for sx: float in [-0.6, 0.6]:
			var scr := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(0.9, 0.6, 0.06)
			scr.mesh = sm
			scr.material_override = screen_mat
			scr.position = Vector3(sx, 1.45, -0.3)
			scr.rotation.x = -0.15
			cons.add_child(scr)
		if ch(c) == "K":
			var kp: GDScript = load("res://scripts/keypad.gd")
			keypad_node = kp.new()
			keypad_node.position = Vector3(0, 1.0, 0.25)
			cons.add_child(keypad_node)
	for c: Vector2i in cells_of("T"):
		place_model(P + "Tank1.glb", cell_center(c) + wall_offset(c, 0.4), 0.0, 2.9, true)
	for c: Vector2i in cells_of("B"):
		var yaw := wall_yaw(c)
		var p := cell_center(c) + wall_offset(c, 0.45)
		var bed := box_prop(p, yaw, Vector3(1.0, 0.45, 2.0), frame_mat)
		var mattress := MeshInstance3D.new()
		var mm := BoxMesh.new()
		mm.size = Vector3(0.95, 0.15, 1.95)
		mattress.mesh = mm
		mattress.material_override = cloth
		mattress.position.y = 0.52
		bed.add_child(mattress)
	# wall decoration: electrical boxes / lamps in corridors
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			if theme[y][x] == "." and is_walkable(c) and not "DH".contains(rows[y][x]) and _rng.randf() < 0.06:
				var off := wall_offset(c, 1.45)
				if off.length() > 0.0:
					place_model(P + "ElecBox.glb", cell_center(c, 0.9) + off, wall_yaw(c), 0.6, true, false)
