class_name BoardView
extends AspectRatioContainer

signal square_tapped(file: int, rank: int)

const SquareScene := preload("res://scenes/game/Square.tscn")
const SquareScript := preload("res://scripts/game/Square.gd")
const PieceScript := preload("res://scripts/game/Piece.gd")

@onready var _grid: GridContainer = $Grid

var _squares: Dictionary = {}
var _selected_key: Vector2i = Vector2i.ZERO
var _hint_keys: Array = []

func _ready() -> void:
	_build_grid()

func _build_grid() -> void:
	for row in 9:
		for col in 9:
			var file := 9 - col
			var rank := row + 1
			var sq: SquareScript = SquareScene.instantiate()
			sq.file = file
			sq.rank = rank
			sq.tapped.connect(_on_square_tapped)
			_grid.add_child(sq)
			_squares[Vector2i(file, rank)] = sq

func render(core: Object) -> void:
	for key in _squares.keys():
		var sq: SquareScript = _squares[key]
		var piece: Variant = core.piece_at(key.x, key.y)
		if piece == null:
			sq.clear_piece()
		else:
			var kind: int = int(piece["kind"])
			var is_gote: bool = bool(piece["is_gote"])
			sq.set_piece(PieceScript.kanji_for(kind, is_gote), is_gote)

func set_selected(key: Vector2i) -> void:
	if _selected_key != Vector2i.ZERO and _squares.has(_selected_key):
		_squares[_selected_key].set_highlight(false)
	_selected_key = key
	if key != Vector2i.ZERO and _squares.has(key):
		_squares[key].set_highlight(true)

func clear_selected() -> void:
	set_selected(Vector2i.ZERO)

func show_move_hints(keys: Array) -> void:
	clear_move_hints()
	for k in keys:
		if _squares.has(k):
			_squares[k].set_move_hint(true)
			_hint_keys.append(k)

func clear_move_hints() -> void:
	for k in _hint_keys:
		if _squares.has(k):
			_squares[k].set_move_hint(false)
	_hint_keys.clear()

func _on_square_tapped(file: int, rank: int) -> void:
	square_tapped.emit(file, rank)
