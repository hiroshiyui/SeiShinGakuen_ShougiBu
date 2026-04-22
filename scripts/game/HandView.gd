class_name HandView
extends PanelContainer

signal piece_tapped(kind: int)

const PieceScript := preload("res://scripts/game/Piece.gd")
const HandPieceScene := preload("res://scenes/game/HandPiece.tscn")

@export var is_gote: bool = false

@onready var _row: HBoxContainer = $Row

var _selected_kind: int = -1

func _ready() -> void:
	# Add a wood-like background to the hand area (Koma-dai)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#dcb35c") # Slightly darker/different wood for Koma-dai
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.shadow_size = 2
	style.shadow_offset = Vector2(0, 2)
	add_theme_stylebox_override("panel", style)

func render(core: Object) -> void:
	for child in _row.get_children():
		child.queue_free()
	
	var h: Dictionary = core.hand(is_gote)
	for kind in PieceScript.HAND_ORDER:
		var n: int = int(h.get(kind, 0))
		if n <= 0:
			continue
		
		var hp := HandPieceScene.instantiate()
		_row.add_child(hp)
		hp.setup(kind, PieceScript.kanji_for(kind, is_gote), is_gote)
		hp.count = n
		
		if kind == _selected_kind:
			hp.set_selected(true)
		
		hp.pressed.connect(_on_piece_pressed.bind(kind))

func set_selected_kind(kind: int) -> void:
	_selected_kind = kind

func clear_selected_kind() -> void:
	_selected_kind = -1

func _on_piece_pressed(kind: int) -> void:
	piece_tapped.emit(kind)
