extends Node

var _sound_cache := {}

func play(sound_name: String) -> void:
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
	
	var path := "res://assets/sounds/%s.wav" % sound_name
	# FileAccess.file_exists() is false on Android for .wav paths — the
	# APK only carries the imported .sample. ResourceLoader.exists()
	# works on both platforms (same gotcha as PieceView's texture load).
	if not ResourceLoader.exists(path):
		push_error("Sound file does not exist: " + path)
		return null
	
	var stream = load(path)
	if stream == null:
		# If load fails, it might be because the .import file isn't ready.
		# In Godot 4, .wav files are imported as AudioStreamWAV.
		push_error("Failed to load sound: " + path + ". (Wait for Godot to import it if you just added it)")
		return null
		
	_sound_cache[sound_name] = stream
	return stream
