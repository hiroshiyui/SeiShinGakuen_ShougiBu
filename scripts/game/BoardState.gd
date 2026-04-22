class_name BoardState
extends RefCounted

const PieceScript := preload("res://scripts/game/Piece.gd")

const HAND_ORDER := [
	PieceScript.Kind.ROOK, PieceScript.Kind.BISHOP, PieceScript.Kind.GOLD,
	PieceScript.Kind.SILVER, PieceScript.Kind.KNIGHT, PieceScript.Kind.LANCE,
	PieceScript.Kind.PAWN,
]

var _board: Dictionary = {}
var _sente_hand: Dictionary = {}
var _gote_hand: Dictionary = {}
var side_to_move_gote: bool = false
var move_log: Array = []
var position_counts: Dictionary = {}

func _init() -> void:
	reset_starting()

func piece_at(file: int, rank: int) -> PieceScript:
	return _board.get(Vector2i(file, rank))

func hand(is_gote: bool) -> Dictionary:
	return _gote_hand if is_gote else _sente_hand

func _hand_add(is_gote: bool, kind: int) -> void:
	var h := hand(is_gote)
	h[kind] = int(h.get(kind, 0)) + 1

func _hand_remove(is_gote: bool, kind: int) -> bool:
	var h := hand(is_gote)
	var n: int = int(h.get(kind, 0))
	if n <= 0:
		return false
	if n == 1:
		h.erase(kind)
	else:
		h[kind] = n - 1
	return true

# Move dict shape:
#   board move: { from: Vector2i, to: Vector2i, promote: bool }
#   drop:       { drop_kind: int, to: Vector2i }
func apply_move(m: Dictionary) -> bool:
	var ok := false
	if m.has("drop_kind"):
		ok = _apply_drop(m)
	else:
		ok = _apply_board_move(m)
	if ok:
		_bump_position()
	return ok

func _apply_board_move(m: Dictionary) -> bool:
	var from: Vector2i = m["from"]
	var to: Vector2i = m["to"]
	var promote: bool = m.get("promote", false)
	var piece: PieceScript = _board.get(from)
	if piece == null or piece.is_gote != side_to_move_gote:
		return false
	var captured: PieceScript = _board.get(to)
	if captured != null and captured.is_gote == piece.is_gote:
		return false
	var record := {
		from = from, to = to, promote = promote,
		prev_kind = piece.kind, captured = captured, by_gote = side_to_move_gote,
	}
	if captured != null:
		_hand_add(side_to_move_gote, captured.base_kind())
	_board.erase(from)
	var new_kind: int = PieceScript.PROMOTES_TO[piece.kind] if promote and piece.can_promote() else piece.kind
	_board[to] = PieceScript.new(new_kind, piece.is_gote)
	side_to_move_gote = not side_to_move_gote
	move_log.append(record)
	return true

func _apply_drop(m: Dictionary) -> bool:
	var kind: int = m["drop_kind"]
	var to: Vector2i = m["to"]
	if _board.has(to):
		return false
	if not _hand_remove(side_to_move_gote, kind):
		return false
	_board[to] = PieceScript.new(kind, side_to_move_gote)
	move_log.append({drop_kind = kind, to = to, by_gote = side_to_move_gote})
	side_to_move_gote = not side_to_move_gote
	return true

func undo_move() -> bool:
	if move_log.is_empty():
		return false
	_unbump_position()
	var rec: Dictionary = move_log.pop_back()
	if rec.has("drop_kind"):
		_board.erase(rec.to)
		_hand_add(rec.by_gote, rec.drop_kind)
		side_to_move_gote = rec.by_gote
		return true
	_board.erase(rec.to)
	_board[rec.from] = PieceScript.new(rec.prev_kind, rec.by_gote)
	var captured: PieceScript = rec.captured
	if captured != null:
		_board[rec.to] = captured
		_hand_remove(rec.by_gote, captured.base_kind())
	side_to_move_gote = rec.by_gote
	return true

func clear_board() -> void:
	_board.clear()
	_sente_hand.clear()
	_gote_hand.clear()
	side_to_move_gote = false
	move_log.clear()
	position_counts.clear()

func place(file: int, rank: int, kind: int, is_gote: bool) -> void:
	_board[Vector2i(file, rank)] = PieceScript.new(kind, is_gote)

func set_hand_count(is_gote: bool, kind: int, count: int) -> void:
	var h := hand(is_gote)
	if count <= 0:
		h.erase(kind)
	else:
		h[kind] = count

func set_side_to_move(is_gote: bool) -> void:
	side_to_move_gote = is_gote

func seal_initial_position() -> void:
	position_counts.clear()
	_bump_position()

func reset_starting() -> void:
	_board.clear()
	_sente_hand.clear()
	_gote_hand.clear()
	side_to_move_gote = false
	move_log.clear()
	position_counts.clear()
	var back := [
		PieceScript.Kind.LANCE, PieceScript.Kind.KNIGHT, PieceScript.Kind.SILVER,
		PieceScript.Kind.GOLD, PieceScript.Kind.KING, PieceScript.Kind.GOLD,
		PieceScript.Kind.SILVER, PieceScript.Kind.KNIGHT, PieceScript.Kind.LANCE,
	]
	for i in 9:
		var f := 9 - i
		_board[Vector2i(f, 1)] = PieceScript.new(back[i], true)
		_board[Vector2i(f, 9)] = PieceScript.new(back[i], false)
		_board[Vector2i(f, 3)] = PieceScript.new(PieceScript.Kind.PAWN, true)
		_board[Vector2i(f, 7)] = PieceScript.new(PieceScript.Kind.PAWN, false)
	_board[Vector2i(8, 2)] = PieceScript.new(PieceScript.Kind.ROOK, true)
	_board[Vector2i(2, 2)] = PieceScript.new(PieceScript.Kind.BISHOP, true)
	_board[Vector2i(8, 8)] = PieceScript.new(PieceScript.Kind.BISHOP, false)
	_board[Vector2i(2, 8)] = PieceScript.new(PieceScript.Kind.ROOK, false)
	_bump_position()

func position_key() -> String:
	return "%s %s %s" % [_board_sfen(), "w" if side_to_move_gote else "b", _hand_sfen()]

func to_sfen() -> String:
	return "%s %d" % [position_key(), move_log.size() + 1]

func _bump_position() -> void:
	var key := position_key()
	position_counts[key] = int(position_counts.get(key, 0)) + 1

func _unbump_position() -> void:
	var key := position_key()
	var n: int = int(position_counts.get(key, 0))
	if n <= 1:
		position_counts.erase(key)
	else:
		position_counts[key] = n - 1

func _board_sfen() -> String:
	var rows: PackedStringArray = []
	for r in range(1, 10):
		var row := ""
		var empty := 0
		for f in range(9, 0, -1):
			var p: PieceScript = _board.get(Vector2i(f, r))
			if p == null:
				empty += 1
				continue
			if empty > 0:
				row += str(empty)
				empty = 0
			var letter: String = PieceScript.SFEN_LETTER[p.kind]
			row += letter.to_lower() if p.is_gote else letter
		if empty > 0:
			row += str(empty)
		rows.append(row)
	return "/".join(rows)

func _hand_sfen() -> String:
	var s := ""
	for is_gote in [false, true]:
		var h := hand(is_gote)
		for kind in HAND_ORDER:
			var n: int = int(h.get(kind, 0))
			if n == 0:
				continue
			var letter: String = PieceScript.SFEN_LETTER[kind]
			if is_gote:
				letter = letter.to_lower()
			s += (str(n) if n > 1 else "") + letter
	return s if s != "" else "-"
