class_name BoardView
extends AspectRatioContainer

signal square_tapped(file: int, rank: int)

const SquareScene := preload("res://scenes/game/Square.tscn")
const SquareScript := preload("res://scripts/game/Square.gd")
const PieceScript := preload("res://scripts/game/Piece.gd")
const PieceViewScene := preload("res://scenes/game/PieceView.tscn")

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

# Slide the piece across the board from `from` to `to`. Caller invokes this
# AFTER _core.apply_move + render(), so `to` already shows the landed piece;
# we hide it for the duration of the tween, float a ghost copy from `from`
# to `to`, then restore the square. Fire-and-forget — the short duration is
# well under the AI's own 1–2 s natural-pause delay, so animations don't
# stack across turns.
func animate_move(from: Vector2i, to: Vector2i, text: String, is_gote: bool, duration: float = 0.22) -> void:
	if not _squares.has(from) or not _squares.has(to):
		return
	var from_sq: SquareScript = _squares[from]
	var to_sq: SquareScript = _squares[to]
	to_sq.clear_piece()
	var ghost: Control = PieceViewScene.instantiate()
	add_child(ghost)
	ghost.top_level = true
	ghost.size = to_sq.size
	ghost.global_position = from_sq.global_position
	ghost.text = text
	ghost.is_gote = is_gote
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(ghost, "global_position", to_sq.global_position, duration)
	await tween.finished
	ghost.queue_free()
	to_sq.set_piece(text, is_gote)
