class_name HandView
extends PanelContainer

signal piece_tapped(kind: int)

const PieceScript := preload("res://scripts/game/Piece.gd")

@export var is_gote: bool = false

@onready var _row: HBoxContainer = $Row

var _selected_kind: int = -1

func _ready() -> void:
	if is_gote:
		_row.pivot_offset = size * 0.5
		_row.rotation = PI
		resized.connect(func(): _row.pivot_offset = size * 0.5)

func render(core: Object) -> void:
	for child in _row.get_children():
		child.queue_free()
	var h: Dictionary = core.hand(is_gote)
	for kind in PieceScript.HAND_ORDER:
		var n: int = int(h.get(kind, 0))
		if n <= 0:
			continue
		var btn := Button.new()
		btn.text = PieceScript.KANJI[kind] + (" ×%d" % n if n > 1 else "")
		btn.custom_minimum_size = Vector2(48, 56)
		btn.add_theme_font_size_override("font_size", 24)
		if kind == _selected_kind:
			btn.modulate = Color(1.0, 0.9, 0.4)
		btn.pressed.connect(_on_btn_pressed.bind(kind))
		_row.add_child(btn)

func set_selected_kind(kind: int) -> void:
	_selected_kind = kind

func clear_selected_kind() -> void:
	_selected_kind = -1

func _on_btn_pressed(kind: int) -> void:
	piece_tapped.emit(kind)
