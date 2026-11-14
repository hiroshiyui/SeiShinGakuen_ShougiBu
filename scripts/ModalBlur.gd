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
const _THEME := preload("res://assets/themes/ui.tres")
const _FRAME_PAD := 2.0  # frame border sits just outside the dialog's own panel

var _rect: ColorRect
var _mat: ShaderMaterial
var _tween: Tween
# Framed panel drawn behind the dialog, covering its title bar too.
# The embedded window border doesn't render on Android, so without it
# the dialog title floated above the box on the blurred backdrop.
var _dialog: Window
var _frame: Panel

static func attach(dialog: Window) -> ModalBlur:
	if dialog is AcceptDialog:
		DialogStyle.apply(dialog as AcceptDialog)
	var blur := ModalBlur.new()
	blur._dialog = dialog
	if not dialog.borderless:
		blur._frame = Panel.new()
		blur._frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		blur._frame.add_theme_stylebox_override("panel",
			_THEME.get_stylebox(&"dialog_frame", &"ModalBlur"))
		blur.add_child(blur._frame)
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

# Follows the dialog every frame while shown: popup_centered and content
# reflow can move or resize it after it opens.
func _process(_delta: float) -> void:
	if _frame == null or _dialog == null or not _dialog.visible:
		return
	var title_h: float = float(_dialog.get_theme_constant(&"title_height"))
	var r := Rect2(Vector2(_dialog.position), Vector2(_dialog.size))
	r.position.y -= title_h
	r.size.y += title_h
	r = r.grow(_FRAME_PAD)
	_frame.position = r.position
	_frame.size = r.size

func _set_amount(v: float) -> void:
	_mat.set_shader_parameter("amount", v)
