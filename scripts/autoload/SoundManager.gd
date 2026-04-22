extends Node

var sounds := {
	"move": preload("res://assets/sounds/move.wav"),
	"capture": preload("res://assets/sounds/capture.wav"),
	"promote": preload("res://assets/sounds/promote.wav"),
	"check": preload("res://assets/sounds/check.wav"),
	"checkmate": preload("res://assets/sounds/checkmate.wav"),
}

func play(sound_name: String) -> void:
	if not sounds.has(sound_name):
		push_error("Sound not found: " + sound_name)
		return
	
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.stream = sounds[sound_name]
	player.play()
	player.finished.connect(player.queue_free)
