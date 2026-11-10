class_name BackgroundSet
extends Resource
## A shareable list of background images for `RandomBackground`.
##
## Images are referenced by path, not preloaded, so a scene only loads the
## one it actually shows. Keep one `.tres` per rotation and point every
## scene that uses that rotation at it, so the lists can't drift apart.
##
## `weights` is optional: leave it empty for a uniform pick, or give one
## relative weight per path (e.g. 1.0 for the regulars, 0.3 for a rarer
## "special" image).

@export_file("*.webp", "*.png", "*.jpg") var paths: Array[String] = []
@export var weights: Array[float] = []


## Returns the index of a randomly chosen path, honouring `weights`.
## -1 when there is nothing to pick from.
func pick_index() -> int:
	if paths.is_empty():
		return -1
	if weights.is_empty():
		return randi() % paths.size()
	if weights.size() != paths.size():
		push_warning("BackgroundSet %s: %d weights for %d paths; picking uniformly"
				% [resource_path, weights.size(), paths.size()])
		return randi() % paths.size()
	var total := 0.0
	for w in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		push_warning("BackgroundSet %s: all weights are zero; picking uniformly" % resource_path)
		return randi() % paths.size()
	var roll := randf() * total
	for i in paths.size():
		roll -= maxf(weights[i], 0.0)
		if roll < 0.0:
			return i
	return paths.size() - 1
