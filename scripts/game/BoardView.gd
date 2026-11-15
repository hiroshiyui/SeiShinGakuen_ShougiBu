class_name BoardView
extends AspectRatioContainer

signal square_tapped(file: int, rank: int)

const SquareScene := preload("res://scenes/game/Square.tscn")
const SquareScript := preload("res://scripts/game/Square.gd")
const PieceScript := preload("res://scripts/game/Piece.gd")
const PieceViewScene := preload("res://scenes/game/PieceView.tscn")

@onready var _grid: GridContainer = %GridMargin/Grid
@onready var _margin_container: MarginContainer = %GridMargin
@onready var _background: Control = $BoardBackground

var _squares: Dictionary = {}
var _selected_key: Vector2i = Vector2i.ZERO
var _hint_keys: Array = []
var _last_move_keys: Array = []
var _check_key: Vector2i = Vector2i.ZERO
# Shown from 後手's side: 1一 at the bottom-left, 9九 at the top-right.
# Squares keep their real (file, rank) keys, so only the grid order and
# piece orientation change; callers re-render afterwards.
var flipped: bool = false

func _ready() -> void:
	resized.connect(_on_resized)
	_build_grid()
	_on_resized()

# Global rect of the wooden board as actually drawn. The AspectRatio-
# Container itself can be wider/taller than the fitted child, so callers
# positioning overlays flush to the shogi-ban must use this, not
# get_global_rect() on the BoardView.
func visual_global_rect() -> Rect2:
	return _background.get_global_rect()

func flash_invalid(key: Vector2i) -> void:
	var sq: SquareScript = _squares.get(key)
	if sq != null:
		sq.flash_invalid()

# --- Zoom without re-layout ------------------------------------------------
#
# Tweening the board's size the plain way re-lays out all 81 squares and
# redraws every piece on every frame: cell edges snap to whole pixels at
# a different rate from the grid lines, and each new size rasterises the
# piece kanji at a new integer font size. That reads as shimmer, and the
# glyph work drops frames on phones.
#
# While frozen, the content keeps the layout it has at `side` and is
# only scaled (one canvas transform) to whatever size the container is
# given. Freeze at the larger end of a zoom so glyphs are only ever
# scaled down.
var _frozen_side: float = 0.0
var _frozen_child_size: Vector2 = Vector2.ZERO

func freeze_layout(side: float) -> void:
	var cur := minf(size.x, size.y)
	if side <= 0.0 or cur <= 0.0:
		return
	# The fitted child rect as it is on screen right now, frozen or not.
	var live: Vector2 = _background.size * _background.scale
	_frozen_side = side
	_frozen_child_size = live * (side / cur)
	_apply_frozen()
	_on_resized()

func unfreeze_layout() -> void:
	if _frozen_side == 0.0:
		return
	_frozen_side = 0.0
	for c: Control in _fitted_children():
		c.size = c.size * c.scale
		c.scale = Vector2.ONE
	_on_resized()
	queue_sort()

func _fitted_children() -> Array[Control]:
	var out: Array[Control] = []
	for child in get_children():
		var c := child as Control
		if c != null and not c.top_level:
			out.append(c)
	return out

func _apply_frozen() -> void:
	var k := minf(size.x, size.y) / _frozen_side
	for c: Control in _fitted_children():
		c.size = _frozen_child_size
		c.scale = Vector2(k, k)

# Runs after AspectRatioContainer's own sort (native notification
# handlers go first), which has just fitted the children at scale 1.
func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN and _frozen_side > 0.0:
		_apply_frozen()

func _on_resized() -> void:
	var s := size
	if _frozen_side > 0.0 and minf(s.x, s.y) > 0.0:
		# Margins belong to the frozen layout, not the on-screen size.
		s *= _frozen_side / minf(s.x, s.y)
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

func set_flipped(f: bool) -> void:
	if f == flipped:
		return
	flipped = f
	for key: Vector2i in _squares.keys():
		var sq: SquareScript = _squares[key]
		sq.flipped = f
		var row: int = (9 - key.y) if f else (key.y - 1)
		var col: int = (key.x - 1) if f else (9 - key.x)
		_grid.move_child(sq, row * 9 + col)

# Bumped by every render(); a running slide animation checks it so it
# doesn't put its piece back onto a board that has been redrawn since
# (undo, the next 詰将棋 problem, …).
var _render_gen: int = 0

func render(core: Object) -> void:
	_render_gen += 1
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

# Marks the square of the `is_gote` side's king as being in check.
func show_check(core: Object, is_gote: bool) -> void:
	clear_check()
	for key in _squares.keys():
		var piece: Variant = core.piece_at(key.x, key.y)
		if piece != null and int(piece["kind"]) == PieceScript.Kind.KING \
				and bool(piece["is_gote"]) == is_gote:
			_squares[key].set_check_hint(true)
			_check_key = key
			return

func clear_check() -> void:
	if _squares.has(_check_key):
		_squares[_check_key].set_check_hint(false)
	_check_key = Vector2i.ZERO

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
	# Squares are scaled while the board is mid-zoom (see freeze_layout).
	ghost.scale = _margin_container.scale
	ghost.global_position = from_sq.global_position
	ghost.text = text
	ghost.is_gote = is_gote != flipped
	var gen := _render_gen
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(ghost, "global_position", to_sq.global_position, duration)
	await tween.finished
	ghost.queue_free()
	if gen == _render_gen:
		to_sq.set_piece(text, is_gote)
