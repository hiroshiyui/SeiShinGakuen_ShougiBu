class_name Square
extends Control

signal tapped(file: int, rank: int)

@export var file: int = 0
@export var rank: int = 0

@onready var _label: Label = $PieceLabel
@onready var _highlight: ColorRect = $Highlight
@onready var _move_hint: ColorRect = $MoveHint

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_highlight.visible = false
	_move_hint.visible = false

	var shogi_font: FontFile = load("res://assets/fonts/fude-goshirae/fude-goshirae.otf")
	_label.add_theme_font_override("font", shogi_font)
	_label.add_theme_color_override("font_color", Color.BLACK)

	resized.connect(_refresh_label_metrics)
	_refresh_label_metrics()

func _gui_input(event: InputEvent) -> void:
	# On touchscreens `emulate_mouse_from_touch` also fires an
	# InputEventMouseButton for each real InputEventScreenTouch, so we'd
	# get two taps per gesture and the second one would deselect the
	# first. Listen only to the native event type per platform.
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
	_label.text = text
	_label.rotation = PI if is_gote else 0.0
	_refresh_label_metrics()

func clear_piece() -> void:
	_label.text = ""
	_label.rotation = 0.0

func set_highlight(on: bool) -> void:
	_highlight.visible = on

func set_move_hint(on: bool) -> void:
	_move_hint.visible = on

func _refresh_label_metrics() -> void:
	if _label == null:
		return
	var side: float = minf(size.x, size.y)
	_label.add_theme_font_size_override("font_size", int(side * 0.72))
	_label.pivot_offset = _label.size * 0.5
