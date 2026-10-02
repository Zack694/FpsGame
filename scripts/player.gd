extends CharacterBody3D
class_name Player
## First-person player: movement, look, flashlight, blinking, stamina, health, interaction.

signal died(cause: String)
signal damaged(amount: float)

const WALK := 3.6
const SPRINT := 6.3
const CROUCH_SPEED := 1.8
const EYE := 1.62
const EYE_CROUCH := 1.0

var game: Node
var health := 100.0
var stamina := 100.0
var blink_meter := 100.0
var blink_time := 0.0
var battery := 100.0
var flashlight_on := true
var alive := true
var crouching := false
var blink_period := 9.0

# touch input (set by TouchControls)
var touch_move := Vector2.ZERO
var touch_sprint := false
var _look_accum := Vector2.ZERO
var _fire_held := false

var head: Node3D
var camera: Camera3D
var flashlight: SpotLight3D
var revolver: Revolver
var interact_ray: RayCast3D
var wall_ray: RayCast3D
var _col: CollisionShape3D
var _capsule: CapsuleShape3D
var _step_t := 0.0
var _stamina_lock := false
var _regen_delay := 0.0
var _shake := 0.0
var _pitch := 0.0
var _bob_t := 0.0
var _last_look := Vector2.ZERO
var _breath_cd := 0.0
var _heartbeat: AudioStreamPlayer
var _low_batt_flicker := 0.0

func _ready() -> void:
	add_to_group("actors")
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4
	floor_snap_length = 0.3
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.38
	_capsule.height = 1.8
	_col = CollisionShape3D.new()
	_col.shape = _capsule
	_col.position.y = 0.9
	add_child(_col)
	head = Node3D.new()
	head.position.y = EYE
	add_child(head)
	camera = Camera3D.new()
	camera.near = 0.03
	camera.far = 80.0
	camera.fov = Settings.f("fov")
	camera.cull_mask = 1 | 2
	head.add_child(camera)
	camera.current = true
	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(0.12, -0.08, -0.05)
	flashlight.spot_range = 24.0
	flashlight.spot_angle = 30.0
	flashlight.spot_angle_attenuation = 0.9
	flashlight.spot_attenuation = 1.1
	flashlight.light_energy = 3.2
	flashlight.light_color = Color(1.0, 0.96, 0.88)
	flashlight.light_cull_mask = 1
	flashlight.shadow_enabled = Settings.b("flashlight_shadows")
	flashlight.shadow_bias = 0.04
	flashlight.light_specular = 0.6
	camera.add_child(flashlight)
	revolver = Revolver.new()
	revolver.player = self
	camera.add_child(revolver)
	interact_ray = RayCast3D.new()
	interact_ray.target_position = Vector3(0, 0, -2.4)
	interact_ray.collision_mask = 1 | MapBuilder.LAYER_INTERACT
	interact_ray.collide_with_areas = false
	interact_ray.add_exception(self)
	camera.add_child(interact_ray)
	wall_ray = RayCast3D.new()
	wall_ray.target_position = Vector3(0, 0, -0.75)
	wall_ray.collision_mask = 1
	wall_ray.add_exception(self)
	camera.add_child(wall_ray)
	_heartbeat = AudioStreamPlayer.new()
	var hb: AudioStream = Sfx.stream("character_d9341_heartbeat")
	if hb is AudioStreamOggVorbis:
		hb = hb.duplicate()
		(hb as AudioStreamOggVorbis).loop = true
	_heartbeat.stream = hb
	_heartbeat.bus = "SFX"
	_heartbeat.volume_db = -80.0
	add_child(_heartbeat)
	_heartbeat.play()
	Settings.changed.connect(_on_settings)

func _on_settings() -> void:
	camera.fov = Settings.f("fov")
	flashlight.shadow_enabled = Settings.b("flashlight_shadows")

# ------------------------------------------------------------------ input
func add_look(rel: Vector2, touch: bool) -> void:
	var sens := (0.0042 * Settings.f("look_sensitivity")) if touch else (0.0022 * Settings.f("mouse_sensitivity"))
	_look_accum += rel * sens

func set_fire_held(v: bool) -> void:
	_fire_held = v

func _unhandled_input(event: InputEvent) -> void:
	if not alive or get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		add_look((event as InputEventMouseMotion).relative, false)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and not Settings.use_touch():
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("flashlight"):
		toggle_flashlight()
	elif event.is_action_pressed("reload"):
		revolver.try_reload()
	elif event.is_action_pressed("interact"):
		interact()
	elif event.is_action_pressed("blink"):
		blink()
	elif event.is_action_pressed("crouch"):
		toggle_crouch()

func toggle_flashlight() -> void:
	if battery <= 0.0:
		Sfx.play("interact_leverflip", -8.0, 2.0)
		return
	flashlight_on = not flashlight_on
	Sfx.play("interact_leverflip", -8.0, 1.8)

func toggle_crouch() -> void:
	if crouching:
		# only stand if there is room (ceiling is 3.2 m, always true in this map)
		crouching = false
	else:
		crouching = true

func blink() -> void:
	if blink_time <= 0.0:
		blink_time = 0.2
		blink_meter = 100.0

func is_blinking() -> bool:
	return blink_time > 0.0

func interact() -> void:
	var t := get_interact_target()
	if t:
		t.call("interact", self)

func get_interact_target() -> Object:
	if not interact_ray.is_colliding():
		return null
	var col := interact_ray.get_collider()
	if col is Node and (col as Node).has_meta("interact"):
		return (col as Node).get_meta("interact")
	return null

# ------------------------------------------------------------------ helpers
func eye_position() -> Vector3:
	return camera.global_position

## True if the given world point is on screen, unobstructed and the eyes are open.
func can_see_point(p: Vector3, max_dist: float = 45.0) -> bool:
	if is_blinking() or not alive:
		return false
	var e := camera.global_position
	if e.distance_to(p) > max_dist:
		return false
	if not camera.is_position_in_frustum(p):
		return false
	return bool(game.call("has_los", e, p))

func damage(amount: float, cause: String) -> void:
	if not alive:
		return
	var mult := [0.6, 1.0, 1.4][Settings.difficulty] as float
	health -= amount * mult
	_shake = 0.35
	damaged.emit(amount)
	Sfx.play(Sfx.pick(["character_d9341_damage1", "character_d9341_damage2", "character_d9341_damage3", "character_d9341_damage4"]), 0.0)
	if health <= 0.0:
		die(cause)

func heal(amount: float) -> void:
	health = minf(100.0, health + amount)

func die(cause: String) -> void:
	if not alive:
		return
	alive = false
	health = 0.0
	velocity = Vector3.ZERO
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(head, "position:y", 0.25, 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(camera, "rotation:z", 1.2, 0.7)
	tw.tween_property(revolver, "position:y", -0.6, 0.5)
	died.emit(cause)

# ------------------------------------------------------------------ update
func _physics_process(delta: float) -> void:
	if not alive:
		return
	# look
	var look := _look_accum
	_look_accum = Vector2.ZERO
	_last_look = _last_look.lerp(look / maxf(delta, 0.001) * 0.02, 0.3)
	rotation.y -= look.x
	var inv := -1.0 if Settings.b("invert_y") else 1.0
	_pitch = clampf(_pitch - look.y * inv, deg_to_rad(-85), deg_to_rad(85))
	head.rotation.x = _pitch
	# gamepad look
	var jl := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if jl.length() > 0.15:
		rotation.y -= jl.x * delta * 2.6 * Settings.f("look_sensitivity")
		_pitch = clampf(_pitch - jl.y * inv * delta * 2.0 * Settings.f("look_sensitivity"), deg_to_rad(-85), deg_to_rad(85))
	# movement
	var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var jm := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if jm.length() > 0.2:
		mv = jm
	if touch_move.length() > 0.05:
		mv = touch_move
	mv = mv.limit_length(1.0)
	var want_sprint := (Input.is_action_pressed("sprint") or touch_sprint) and mv.y < -0.3 and not crouching
	var sprinting := want_sprint and not _stamina_lock and stamina > 0.0
	var speed := CROUCH_SPEED if crouching else (SPRINT if sprinting else WALK)
	var dir := (global_transform.basis * Vector3(mv.x, 0, mv.y))
	dir.y = 0
	var target := dir * speed
	var accel := 10.0 if is_on_floor() else 4.0
	velocity.x = move_toward(velocity.x, target.x, accel * speed * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * speed * delta)
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	var hspeed := Vector2(velocity.x, velocity.z).length()
	# stamina
	if sprinting and hspeed > 1.0:
		stamina -= 17.0 * delta
		_regen_delay = 1.0
		if stamina <= 0.0:
			stamina = 0.0
			_stamina_lock = true
			Sfx.play(Sfx.pick(["character_d9341_breath1", "character_d9341_breath2"]), -4.0)
	else:
		_regen_delay -= delta
		if _regen_delay <= 0.0:
			stamina = minf(100.0, stamina + 13.0 * delta)
	if _stamina_lock and stamina > 30.0:
		_stamina_lock = false
	# crouch height
	var eye_target := EYE_CROUCH if crouching else EYE
	var bob := 0.0
	if Settings.b("head_bob") and hspeed > 0.5 and is_on_floor():
		_bob_t += delta * hspeed * 2.2
		bob = sin(_bob_t) * 0.035 * clampf(hspeed / 4.0, 0.0, 1.5)
	head.position.y = lerpf(head.position.y, eye_target + bob, clampf(delta * 10.0, 0, 1))
	_capsule.height = 1.2 if crouching else 1.8
	_col.position.y = _capsule.height * 0.5
	# footsteps / noise
	if hspeed > 0.8 and is_on_floor():
		_step_t -= delta * hspeed
		if _step_t <= 0.0:
			_step_t = 2.1
			if sprinting:
				Sfx.play(Sfx.pick(["step_run1", "step_run2", "step_run3", "step_run4"]), -6.0, randf_range(0.95, 1.05))
				game.call("make_noise", global_position, 11.0)
			elif not crouching:
				Sfx.play(Sfx.pick(["step_step1", "step_step2", "step_step3", "step_step4"]), -10.0, randf_range(0.95, 1.05))
				game.call("make_noise", global_position, 4.5)
	# blinking
	if blink_time > 0.0:
		blink_time -= delta
	else:
		blink_meter -= 100.0 / blink_period * delta
		if blink_meter <= 0.0:
			blink()
	# flashlight battery
	var drain := [0.22, 0.32, 0.45][Settings.difficulty] as float
	if flashlight_on and battery > 0.0:
		battery = maxf(0.0, battery - drain * delta)
		if battery <= 0.0:
			flashlight_on = false
	var fl_energy := 3.2
	if battery < 15.0:
		_low_batt_flicker -= delta
		if _low_batt_flicker <= 0.0:
			_low_batt_flicker = randf_range(0.05, 0.6)
		fl_energy *= 0.4 + 0.6 * float(_low_batt_flicker > 0.1)
	flashlight.visible = flashlight_on
	flashlight.light_energy = fl_energy
	# weapon
	if (Input.is_action_pressed("fire") and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED) or _fire_held:
		if revolver.can_fire():
			revolver.try_fire(camera, Settings.b("aim_assist") and Settings.use_touch())
			_pitch = minf(_pitch + 0.035, deg_to_rad(85))
			game.call("make_noise", global_position, 30.0)
	revolver.update_view(delta, hspeed, sprinting, wall_ray.is_colliding(), _last_look)
	# camera shake
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		camera.h_offset = randf_range(-1, 1) * _shake * 0.08
		camera.v_offset = randf_range(-1, 1) * _shake * 0.08
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	# low health heartbeat
	var hb_target := -80.0
	if health < 45.0:
		hb_target = lerpf(-6.0, -24.0, health / 45.0)
	_heartbeat.volume_db = lerpf(_heartbeat.volume_db, hb_target, clampf(delta * 3.0, 0, 1))

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)
