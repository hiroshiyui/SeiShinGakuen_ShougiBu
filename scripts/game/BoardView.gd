class_name BoardView
extends AspectRatioContainer

signal square_tapped(file: int, rank: int)

const SquareScene := preload("res://scenes/game/Square.tscn")
const SquareScript := preload("res://scripts/game/Square.gd")
const PieceScript := preload("res://scripts/game/Piece.gd")

@onready var _grid: GridContainer = %GridMargin/Grid
@onready var _margin_container: MarginContainer = %GridMargin

var _squares: Dictionary = {}
var _selected_key: Vector2i = Vector2i.ZERO
var _hint_keys: Array = []
var _last_move_keys: Array = []

func _ready() -> void:
	resized.connect(_on_resized)
	_build_grid()
	_on_resized()

func _on_resized() -> void:
	var s := size
	# Match the 0.04 MARGIN_PERCENT in BoardBackground.gd
	var margin_x := int(s.x * 0.04)
	var margin_y := int(s.y * 0.04)
	
	_margin_container.add_theme_constant_override("margin_left", margin_x)
	_margin_container.add_theme_constant_override("margin_right", margin_x)
	_margin_container.add_theme_constant_override("margin_top", margin_y)
	_margin_container.add_theme_constant_override("margin_bottom", margin_y)

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

# Blue-tinted overlay showing the from/to squares of the most recently
# applied move so the player can spot what the opponent did at a glance.
# `from == Vector2i.ZERO` is treated as "drop" and skipped.
func show_last_move(from: Vector2i, to: Vector2i) -> void:
	clear_last_move()
	if from != Vector2i.ZERO and _squares.has(from):
		_squares[from].set_last_move_hint(true)
		_last_move_keys.append(from)
	if to != Vector2i.ZERO and _squares.has(to):
		_squares[to].set_last_move_hint(true)
		_last_move_keys.append(to)

func clear_last_move() -> void:
	for k in _last_move_keys:
		if _squares.has(k):
			_squares[k].set_last_move_hint(false)
	_last_move_keys.clear()

func _on_square_tapped(file: int, rank: int) -> void:
	square_tapped.emit(file, rank)
