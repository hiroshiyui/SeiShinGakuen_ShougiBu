class_name ModalBlur
extends CanvasLayer

# Full-screen blurred backdrop that tracks a modal Window dialog's
# visibility. Built-in AcceptDialog / ConfirmationDialog are embedded
# subwindows, which Godot draws on its own top canvas layer — so a
# CanvasLayer here sits above the whole scene but still beneath the
# dialog. Usage, from the owning scene's `_ready`:
#
#     ModalBlur.attach(_quit_dialog)

const _SHADER := preload("res://assets/shaders/backdrop_blur.gdshader")
const _FADE_SEC := 0.15

var _rect: ColorRect
var _mat: ShaderMaterial
var _tween: Tween

static func attach(dialog: Window) -> ModalBlur:
	var blur := ModalBlur.new()
	dialog.add_sibling(blur)
	dialog.visibility_changed.connect(func() -> void: blur._set_shown(dialog.visible))
	return blur

func _init() -> void:
	layer = 100
	visible = false
	_mat = ShaderMaterial.new()
	_mat.shader = _SHADER
	_mat.set_shader_parameter("amount", 0.0)
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)

func _set_shown(shown: bool) -> void:
	if _tween != null:
		_tween.kill()
	if shown:
		visible = true
	_tween = create_tween()
	_tween.tween_method(_set_amount, float(_mat.get_shader_parameter("amount")),
			1.0 if shown else 0.0, _FADE_SEC)
	if not shown:
		_tween.tween_callback(hide)

func _set_amount(v: float) -> void:
	_mat.set_shader_parameter("amount", v)
