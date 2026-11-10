extends TextureRect
## Picks one of `variants` at random each time the scene is entered.
## The scene's own `texture` stays as the editor preview / fallback.
##
## `weights` is optional: leave it empty for a uniform pick, or give one
## relative weight per variant (e.g. 1.0 for the regulars, 0.3 for a
## rarer "special" image). A size mismatch falls back to uniform.

@export var variants: Array[Texture2D] = []
@export var weights: Array[float] = []


func _ready() -> void:
	if variants.is_empty():
		return
	if weights.size() != variants.size():
		texture = variants.pick_random()
		return
	var total := 0.0
	for w in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		texture = variants.pick_random()
		return
	var roll := randf() * total
	for i in variants.size():
		roll -= maxf(weights[i], 0.0)
		if roll < 0.0:
			texture = variants[i]
			return
	texture = variants[-1]
