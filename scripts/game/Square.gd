class_name Square
extends Control

signal tapped(file: int, rank: int)

@export var file: int = 0
@export var rank: int = 0

@onready var _piece_view: Control = $PieceView
@onready var _highlight: ColorRect = $Highlight
@onready var _move_hint: ColorRect = $MoveHint
@onready var _last_move_hint: ColorRect = $LastMoveHint

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_highlight.visible = false
	_move_hint.visible = false
	_last_move_hint.visible = false

func _gui_input(event: InputEvent) -> void:
	var is_press := false
	if OS.has_feature("mobile"):
		if event is InputEventScreenTouch and event.pressed:
			is_press = true
	else:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			is_press = true
	if is_press:
		tapped.emit(file, rank)
		accept_event()

func set_piece(text: String, is_gote: bool) -> void:
	_piece_view.text = text
	_piece_view.is_gote = is_gote
	_piece_view.visible = true

func clear_piece() -> void:
	_piece_view.text = ""
	_piece_view.visible = false

func set_highlight(on: bool) -> void:
	_highlight.visible = on

func set_move_hint(on: bool) -> void:
	_move_hint.visible = on

func set_last_move_hint(on: bool) -> void:
	_last_move_hint.visible = on
