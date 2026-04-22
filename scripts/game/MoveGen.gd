class_name MoveGen
extends RefCounted

const PieceScript := preload("res://scripts/game/Piece.gd")
const BoardStateScript := preload("res://scripts/game/BoardState.gd")

# All deltas are from sente's perspective — forward is -rank.
# For gote, multiply the rank-delta by -1.
const _GOLD_STEPS := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, -1),
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
]
const _KING_STEPS := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
const _SILVER_STEPS := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, -1),
	Vector2i(1, 1), Vector2i(-1, 1),
]
const _DIAG := [Vector2i(1, -1), Vector2i(-1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
const _ORTHO := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]

static func _steps_for(kind: int) -> Array:
	match kind:
		PieceScript.Kind.PAWN:
			return [Vector2i(0, -1)]
		PieceScript.Kind.KNIGHT:
			return [Vector2i(1, -2), Vector2i(-1, -2)]
		PieceScript.Kind.SILVER:
			return _SILVER_STEPS
		PieceScript.Kind.GOLD, PieceScript.Kind.PROMOTED_PAWN, \
		PieceScript.Kind.PROMOTED_LANCE, PieceScript.Kind.PROMOTED_KNIGHT, \
		PieceScript.Kind.PROMOTED_SILVER:
			return _GOLD_STEPS
		PieceScript.Kind.KING:
			return _KING_STEPS
		PieceScript.Kind.HORSE:
			return _ORTHO
		PieceScript.Kind.DRAGON:
			return _DIAG
		_:
			return []

static func _rays_for(kind: int) -> Array:
	match kind:
		PieceScript.Kind.LANCE:
			return [Vector2i(0, -1)]
		PieceScript.Kind.BISHOP, PieceScript.Kind.HORSE:
			return _DIAG
		PieceScript.Kind.ROOK, PieceScript.Kind.DRAGON:
			return _ORTHO
		_:
			return []

static func _in_bounds(v: Vector2i) -> bool:
	return v.x >= 1 and v.x <= 9 and v.y >= 1 and v.y <= 9

static func _in_promo_zone(is_gote: bool, rank: int) -> bool:
	return rank >= 7 if is_gote else rank <= 3

static func _would_be_dead(kind: int, is_gote: bool, to: Vector2i) -> bool:
	if is_gote:
		if kind == PieceScript.Kind.PAWN or kind == PieceScript.Kind.LANCE:
			return to.y == 9
		if kind == PieceScript.Kind.KNIGHT:
			return to.y >= 8
	else:
		if kind == PieceScript.Kind.PAWN or kind == PieceScript.Kind.LANCE:
			return to.y == 1
		if kind == PieceScript.Kind.KNIGHT:
			return to.y <= 2
	return false

static func _apply_flip(delta: Vector2i, is_gote: bool) -> Vector2i:
	return Vector2i(delta.x, -delta.y if is_gote else delta.y)

# Generate pseudo-legal moves originating at `from`.
# (Does not filter for self-check — Phase 3.)
static func generate_moves_from(state: BoardStateScript, from: Vector2i) -> Array:
	var piece: PieceScript = state.piece_at(from.x, from.y)
	if piece == null:
		return []
	var raw: Array = []
	for d in _steps_for(piece.kind):
		var to: Vector2i = from + _apply_flip(d, piece.is_gote)
		if not _in_bounds(to):
			continue
		var target: PieceScript = state.piece_at(to.x, to.y)
		if target != null and target.is_gote == piece.is_gote:
			continue
		raw.append(to)
	for d in _rays_for(piece.kind):
		var step: Vector2i = _apply_flip(d, piece.is_gote)
		var to: Vector2i = from + step
		while _in_bounds(to):
			var target: PieceScript = state.piece_at(to.x, to.y)
			if target == null:
				raw.append(to)
			else:
				if target.is_gote != piece.is_gote:
					raw.append(to)
				break
			to += step

	var out: Array = []
	for to in raw:
		var can_promo := piece.can_promote() and (_in_promo_zone(piece.is_gote, from.y) or _in_promo_zone(piece.is_gote, to.y))
		var dead_unless_promo := _would_be_dead(piece.kind, piece.is_gote, to)
		if not dead_unless_promo:
			out.append({from = from, to = to, promote = false})
		if can_promo:
			out.append({from = from, to = to, promote = true})
	return out

static func generate_drops(state: BoardStateScript, is_gote: bool, kind: int) -> Array:
	var out: Array = []
	for f in range(1, 10):
		for r in range(1, 10):
			if state.piece_at(f, r) != null:
				continue
			var to := Vector2i(f, r)
			if _would_be_dead(kind, is_gote, to):
				continue
			out.append({drop_kind = kind, to = to})
	return out
