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

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		pressed.emit()
		accept_event()
