extends Node
## Sound helper (autoload "Sfx"). Sounds are res://assets/audio/<name>.ogg

var _cache: Dictionary = {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_cur: AudioStreamPlayer
var _music_name: String = ""
var _ui_players: Array[AudioStreamPlayer] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a = _make_music()
	_music_b = _make_music()
	_music_cur = _music_a
	for n in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_ui_players.append(p)

func _make_music() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	add_child(p)
	return p

func stream(sound_name: String) -> AudioStream:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var path := "res://assets/audio/%s.ogg" % sound_name
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_cache[sound_name] = s
	return s

func pick(names: Array) -> String:
	return names[randi() % names.size()]

## Non-positional sound (UI, player).
func play(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	var s := stream(sound_name)
	if s == null:
		return null
	var p: AudioStreamPlayer = null
	for cand in _ui_players:
		if not cand.playing:
			p = cand
			break
	if p == null:
		p = _ui_players[randi() % _ui_players.size()]
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
	return p

## Positional one-shot sound in the 3D world.
func play_at(sound_name: String, pos: Vector3, volume_db: float = 0.0, max_dist: float = 30.0, pitch: float = 1.0) -> void:
	var s := stream(sound_name)
	var tree := get_tree()
	if s == null or tree == null or tree.current_scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "SFX"
	p.volume_db = volume_db
	p.max_distance = max_dist
	p.unit_size = 4.0
	p.pitch_scale = pitch
	p.attenuation_filter_cutoff_hz = 6000.0
	tree.current_scene.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

## Attach a looping 3D emitter to a node.
func make_loop(parent: Node3D, sound_name: String, volume_db: float = 0.0, max_dist: float = 20.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	var s := stream(sound_name)
	if s is AudioStreamOggVorbis:
		s = s.duplicate()
		(s as AudioStreamOggVorbis).loop = true
	p.stream = s
	p.bus = "SFX"
	p.volume_db = volume_db
	p.max_distance = max_dist
	p.unit_size = 4.0
	parent.add_child(p)
	return p

func music(sound_name: String, fade: float = 1.5, volume_db: float = 0.0) -> void:
	if sound_name == _music_name:
		return
	_music_name = sound_name
	var old := _music_cur
	var nxt := _music_b if old == _music_a else _music_a
	_music_cur = nxt
	if sound_name != "":
		var s := stream(sound_name)
		if s is AudioStreamOggVorbis:
			s = s.duplicate()
			(s as AudioStreamOggVorbis).loop = true
		nxt.stream = s
		nxt.volume_db = -40.0
		nxt.play()
		var tw := create_tween()
		tw.tween_property(nxt, "volume_db", volume_db, fade)
	if old.playing:
		var tw2 := create_tween()
		tw2.tween_property(old, "volume_db", -60.0, fade)
		tw2.tween_callback(old.stop)

func stop_music(fade: float = 1.0) -> void:
	music("", fade)
