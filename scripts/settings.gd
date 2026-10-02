extends Node
## Global settings (autoload "Settings"). Persists to user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"

const DEFAULTS := {
	# controls
	"look_sensitivity": 1.0,
	"mouse_sensitivity": 1.0,
	"invert_y": false,
	"joystick_size": 1.0,
	"button_size": 1.0,
	"button_opacity": 0.55,
	"touch_controls": 0, # 0 auto, 1 always, 2 never
	"left_handed": false,
	# gameplay
	"head_bob": true,
	"show_fps": false,
	"aim_assist": true,
	# graphics
	"quality": 1, # 0 low 1 medium 2 high
	"render_scale": 0.85,
	"fov": 75.0,
	"flashlight_shadows": true,
	"glow": true,
	"fps_cap": 60,
	"brightness": 1.0,
	# audio
	"master_volume": 0.9,
	"music_volume": 0.6,
	"sfx_volume": 0.9,
}

var values: Dictionary = {}
## Cheats (persisted). ESP per SCP + godmode / infinite ammo / stamina / battery / no blink.
const CHEAT_KEYS := ["esp_173", "esp_096", "esp_049", "esp_0492", "god", "inf_ammo", "inf_stamina", "inf_battery", "no_blink"]
var cheats: Dictionary = {}
var difficulty: int = 1 # chosen per new game: 0 easy, 1 normal, 2 hard
var best_time: float = -1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_buses()
	_setup_input()
	load_settings()
	apply()

func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))

func f(key: String) -> float:
	return float(get_value(key))

func b(key: String) -> bool:
	return bool(get_value(key))

func i(key: String) -> int:
	return int(get_value(key))

func set_value(key: String, v: Variant) -> void:
	values[key] = v
	apply()
	save_settings()
	changed.emit()

func reset_defaults() -> void:
	values = DEFAULTS.duplicate()
	apply()
	save_settings()
	changed.emit()

func load_settings() -> void:
	values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k: String in DEFAULTS.keys():
			values[k] = cfg.get_value("settings", k, DEFAULTS[k])
		best_time = float(cfg.get_value("stats", "best_time", -1.0))
		for k: String in CHEAT_KEYS:
			cheats[k] = bool(cfg.get_value("cheats", k, false))
		difficulty = int(cfg.get_value("stats", "last_difficulty", 1))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k: String in values.keys():
		cfg.set_value("settings", k, values[k])
	cfg.set_value("stats", "best_time", best_time)
	for k: String in cheats.keys():
		cfg.set_value("cheats", k, cheats[k])
	cfg.set_value("stats", "last_difficulty", difficulty)
	cfg.save(PATH)

func cheat(key: String) -> bool:
	return bool(cheats.get(key, false))

func set_cheat(key: String, on: bool) -> void:
	cheats[key] = on
	save_settings()
	changed.emit()

func any_cheat() -> bool:
	for k: String in cheats.keys():
		if bool(cheats[k]):
			return true
	return false

func use_touch() -> bool:
	match i("touch_controls"):
		1:
			return true
		2:
			return false
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")

func apply() -> void:
	_set_bus("Master", f("master_volume"))
	_set_bus("Music", f("music_volume"))
	_set_bus("SFX", f("sfx_volume"))
	Engine.max_fps = i("fps_cap")
	var vp := get_viewport()
	if vp:
		var q := i("quality")
		vp.scaling_3d_scale = clampf(f("render_scale"), 0.4, 1.0)
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.msaa_3d = Viewport.MSAA_2X if q >= 2 else Viewport.MSAA_DISABLED
		vp.mesh_lod_threshold = 2.0 if q == 0 else 1.0

func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)

func _setup_audio_buses() -> void:
	for bus_name: String in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT],
		"crouch": [KEY_CTRL, KEY_C],
		"interact": [KEY_E],
		"reload": [KEY_R],
		"flashlight": [KEY_F],
		"blink": [KEY_SPACE],
		"pause": [KEY_ESCAPE, KEY_P],
		"map": [KEY_M, KEY_TAB],
		"aim": [KEY_Q],
		"cheats": [KEY_F1],
	}
	for action: String in keys.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k: int in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k as Key
			InputMap.action_add_event(action, ev)
	for pair: Array in [["fire", MOUSE_BUTTON_LEFT], ["aim", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var mb := InputEventMouseButton.new()
		mb.button_index = pair[1]
		InputMap.action_add_event(pair[0], mb)
	var lt := InputEventJoypadMotion.new()
	lt.axis = JOY_AXIS_TRIGGER_LEFT
	lt.axis_value = 1.0
	InputMap.action_add_event("aim", lt)
	var rt := InputEventJoypadMotion.new()
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 1.0
	InputMap.action_add_event("fire", rt)
	# gamepad
	var pad := {
		"fire": JOY_BUTTON_RIGHT_SHOULDER, "interact": JOY_BUTTON_A, "reload": JOY_BUTTON_X,
		"flashlight": JOY_BUTTON_Y, "blink": JOY_BUTTON_LEFT_SHOULDER, "pause": JOY_BUTTON_START,
		"sprint": JOY_BUTTON_LEFT_STICK, "map": JOY_BUTTON_BACK, "crouch": JOY_BUTTON_B,
	}
	for action: String in pad.keys():
		var jb := InputEventJoypadButton.new()
		jb.button_index = pad[action]
		InputMap.action_add_event(action, jb)
