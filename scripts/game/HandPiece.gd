extends Control

signal pressed

@onready var _piece_view: Control = $PieceView
@onready var _count_label: Label = $CountLabel

var kind: int = 0
var count: int = 0:
	set(v):
		count = v
		_update_ui()

func _ready() -> void:
	_update_ui()

func setup(p_kind: int, p_text: String, p_is_gote: bool) -> void:
	kind = p_kind
	_piece_view.text = p_text
	_piece_view.is_gote = p_is_gote

func set_selected(on: bool) -> void:
	if on:
		modulate = Color(1.0, 0.9, 0.5)
	else:
		modulate = Color.WHITE

func _update_ui() -> void:
	if _count_label:
		_count_label.text = "×%d" % count if count > 1 else ""

# Android delivers a tap twice (touch + emulated mouse); listen to one
# source per platform, as Square.gd does (docs/android-gotchas.md).
func _gui_input(event: InputEvent) -> void:
	var is_press := false
	if OS.has_feature("mobile"):
		is_press = event is InputEventScreenTouch and event.pressed
	else:
		is_press = event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT
	if is_press:
		pressed.emit()
		accept_event()
