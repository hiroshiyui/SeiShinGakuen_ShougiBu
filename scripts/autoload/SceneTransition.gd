extends CanvasLayer

# Fade-to-black between top-level scenes. Autoloaded as `SceneTransition`
# so it survives the scene swap; every screen switch goes through
# `SceneTransition.go_to(path)` instead of `get_tree().change_scene_to_file`.
#
# Sits on a high canvas layer above the scene but beneath embedded
# dialogs (which Godot draws on its own top layer). The overlay swallows
# input while visible so a tap during the fade can't hit the outgoing
# or incoming screen. Honours Settings.reduce_motion with an instant cut.

const LAYER := 100
const FADE_OUT_SEC := 0.18
const FADE_IN_SEC := 0.22

var _rect: ColorRect
var _tween: Tween
var _busy: bool = false
# True once the new scene is in place but still fading in. A go_to then
# comes from the new scene itself (e.g. its _ready bailing out on a
# missing file) and must not be lost: it runs when this one finishes.
var _swapped: bool = false
var _queued_path: String = ""

func _ready() -> void:
	layer = LAYER
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.modulate.a = 0.0
	_rect.visible = false
	add_child(_rect)

func is_busy() -> bool:
	return _busy

# Fade out, swap the scene, fade back in. A second call during the fade
# out is ignored (a double tap); one made by the new scene while it fades
# in is queued and runs afterwards. Callers already disable their
# buttons, this is the belt to that suspenders.
func go_to(scene_path: String) -> void:
	if _busy:
		if _swapped:
			_queued_path = scene_path
		return
	_busy = true
	_swapped = false
	var tree := get_tree()
	if Settings.reduce_motion:
		tree.change_scene_to_file(scene_path)
		_swapped = true
		await tree.process_frame
		_finish()
		return
	await _fade(1.0, FADE_OUT_SEC)
	tree.change_scene_to_file(scene_path)
	_swapped = true
	# Let the new scene run _ready and lay out once behind the cover
	# before revealing it, so the first visible frame is settled.
	await tree.process_frame
	await tree.process_frame
	await _fade(0.0, FADE_IN_SEC)
	_finish()

func _finish() -> void:
	_busy = false
	_swapped = false
	if _queued_path != "":
		var next := _queued_path
		_queued_path = ""
		go_to(next)

func _fade(target_alpha: float, seconds: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_rect.visible = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_tween = create_tween()
	_tween.tween_property(_rect, "modulate:a", target_alpha, seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _tween.finished
	if target_alpha <= 0.0:
		_rect.visible = false
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
