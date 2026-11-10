extends TextureRect
## Picks one of `variants` at random each time the scene is entered.
## The scene's own `texture` stays as the editor preview / fallback.

@export var variants: Array[Texture2D] = []


func _ready() -> void:
	if not variants.is_empty():
		texture = variants.pick_random()
