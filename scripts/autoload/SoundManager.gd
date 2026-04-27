extends Node

var _sound_cache := {}

func _ready() -> void:
	# Auto-wire a click SFX on every BaseButton (Button, CheckButton,
	# OptionButton, the 投了/待った/閉じる buttons, suggestion rows, etc.)
	# so we don't have to touch each call site. `node_added` only fires for
	# future additions, so we also sweep the already-live tree once.
	get_tree().node_added.connect(_on_node_added)
	_hook_subtree(get_tree().root)

func _hook_subtree(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_hook_subtree(child)

func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.pressed.is_connected(_play_click):
		node.pressed.connect(_play_click)

func _play_click() -> void:
	play("click")

func play(sound_name: String) -> void:
	if not Settings.sound_enabled:
		return
	var stream = _get_sound(sound_name)
	if stream == null:
		return
	
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.stream = stream
	player.play()
	player.finished.connect(player.queue_free)

func _get_sound(sound_name: String) -> AudioStream:
	if _sound_cache.has(sound_name):
		return _sound_cache[sound_name]
	
	# FileAccess.file_exists() is false on Android for sound-file paths —
	# the APK only carries the imported .sample / .oggvorbisstr.
	# ResourceLoader.exists() works on both platforms (same gotcha as
	# PieceView's texture load).
	var path := ""
	for ext in [".ogg", ".wav"]:
		var candidate := "res://assets/sounds/%s%s" % [sound_name, ext]
		if ResourceLoader.exists(candidate):
			path = candidate
			break
	if path == "":
		push_error("Sound file does not exist: assets/sounds/%s.{ogg,wav}" % sound_name)
		return null

	var stream = load(path)
	if stream == null:
		# If load fails, it might be because the .import file isn't ready.
		# In Godot 4, .wav files are imported as AudioStreamWAV.
		push_error("Failed to load sound: " + path + ". (Wait for Godot to import it if you just added it)")
		return null
		
	_sound_cache[sound_name] = stream
	return stream
