extends TextureRect
## Shows one image from `background_set`, picked at random each time the
## scene is entered. Only the chosen image is loaded.
##
## The scene's own `texture` stays as the editor preview and as the
## fallback if the set is missing or the chosen image fails to load.

@export var background_set: BackgroundSet


func _ready() -> void:
	if background_set == null:
		return
	var i := background_set.pick_index()
	if i < 0:
		return
	var path := background_set.paths[i]
	var tex := load(path) as Texture2D
	if tex == null:
		push_warning("RandomBackground: could not load %s; keeping the preview texture" % path)
		return
	texture = tex
