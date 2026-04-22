class_name Rules
extends RefCounted

const PieceScript := preload("res://scripts/game/Piece.gd")
const BoardStateScript := preload("res://scripts/game/BoardState.gd")
const MoveGenScript := preload("res://scripts/game/MoveGen.gd")

static func find_king(state: BoardStateScript, is_gote: bool) -> Vector2i:
	for f in range(1, 10):
		for r in range(1, 10):
			var p: PieceScript = state.piece_at(f, r)
			if p != null and p.kind == PieceScript.Kind.KING and p.is_gote == is_gote:
				return Vector2i(f, r)
	return Vector2i.ZERO

static func is_square_attacked(state: BoardStateScript, target: Vector2i, attacker_is_gote: bool) -> bool:
	for f in range(1, 10):
		for r in range(1, 10):
			var p: PieceScript = state.piece_at(f, r)
			if p == null or p.is_gote != attacker_is_gote:
				continue
			var from := Vector2i(f, r)
			for m in MoveGenScript.generate_moves_from(state, from):
				if m["to"] == target:
					return true
	return false

static func is_check(state: BoardStateScript, is_gote: bool) -> bool:
	var king := find_king(state, is_gote)
	if king == Vector2i.ZERO:
		return false
	return is_square_attacked(state, king, not is_gote)

static func legal_moves_from(state: BoardStateScript, from: Vector2i) -> Array:
	var piece: PieceScript = state.piece_at(from.x, from.y)
	if piece == null or piece.is_gote != state.side_to_move_gote:
		return []
	var out: Array = []
	for m in MoveGenScript.generate_moves_from(state, from):
		if not _leaves_king_safe(state, m):
			continue
		out.append(m)
	return out

static func legal_drops(state: BoardStateScript, kind: int) -> Array:
	var is_gote := state.side_to_move_gote
	if int(state.hand(is_gote).get(kind, 0)) <= 0:
		return []
	var out: Array = []
	for m in MoveGenScript.generate_drops(state, is_gote, kind):
		if kind == PieceScript.Kind.PAWN and _violates_nifu(state, m["to"].x, is_gote):
			continue
		if not _leaves_king_safe(state, m):
			continue
		if kind == PieceScript.Kind.PAWN and _is_uchifuzume(state, m):
			continue
		out.append(m)
	return out

static func has_any_legal_move(state: BoardStateScript) -> bool:
	var side := state.side_to_move_gote
	for f in range(1, 10):
		for r in range(1, 10):
			var p: PieceScript = state.piece_at(f, r)
			if p != null and p.is_gote == side:
				if not legal_moves_from(state, Vector2i(f, r)).is_empty():
					return true
	var h := state.hand(side)
	for kind in h.keys():
		if not legal_drops(state, kind).is_empty():
			return true
	return false

static func is_checkmate(state: BoardStateScript) -> bool:
	return is_check(state, state.side_to_move_gote) and not has_any_legal_move(state)

# --- sennichite -------------------------------------------------------------

# Returns one of: "none", "draw", "sente_loses", "gote_loses"
static func detect_sennichite(state: BoardStateScript) -> String:
	var key := state.position_key()
	if int(state.position_counts.get(key, 0)) < 4:
		return "none"
	# Find the oldest log index whose position_key_after == key; all moves
	# from there onward form the repeating cycle.
	var log: Array = state.move_log
	var start_idx := -1
	for i in log.size():
		if log[i].get("position_key_after", "") == key:
			start_idx = i
			break
	if start_idx < 0:
		return "draw"
	var sente_all_checks := true
	var gote_all_checks := true
	var sente_moved := false
	var gote_moved := false
	for i in range(start_idx + 1, log.size()):
		var m: Dictionary = log[i]
		var was_check: bool = m.get("was_check", false)
		if bool(m.get("by_gote", false)):
			gote_moved = true
			if not was_check:
				gote_all_checks = false
		else:
			sente_moved = true
			if not was_check:
				sente_all_checks = false
	if sente_moved and sente_all_checks and not (gote_moved and gote_all_checks):
		return "sente_loses"
	if gote_moved and gote_all_checks and not (sente_moved and sente_all_checks):
		return "gote_loses"
	return "draw"

# --- jishogi (入玉 / 持将棋) --------------------------------------------------

const _JISHOGI_VALUE := {
	PieceScript.Kind.ROOK: 5, PieceScript.Kind.BISHOP: 5,
	PieceScript.Kind.DRAGON: 5, PieceScript.Kind.HORSE: 5,
	PieceScript.Kind.PAWN: 1, PieceScript.Kind.LANCE: 1, PieceScript.Kind.KNIGHT: 1,
	PieceScript.Kind.SILVER: 1, PieceScript.Kind.GOLD: 1,
	PieceScript.Kind.PROMOTED_PAWN: 1, PieceScript.Kind.PROMOTED_LANCE: 1,
	PieceScript.Kind.PROMOTED_KNIGHT: 1, PieceScript.Kind.PROMOTED_SILVER: 1,
}

static func king_entered(state: BoardStateScript, is_gote: bool) -> bool:
	var k := find_king(state, is_gote)
	if k == Vector2i.ZERO:
		return false
	return (k.y >= 7) if not is_gote else (k.y <= 3)

static func jishogi_points(state: BoardStateScript, is_gote: bool) -> int:
	var total := 0
	for f in range(1, 10):
		for r in range(1, 10):
			var p: PieceScript = state.piece_at(f, r)
			if p == null or p.is_gote != is_gote or p.kind == PieceScript.Kind.KING:
				continue
			var in_opp_camp := (r <= 3) if not is_gote else (r >= 7)
			if in_opp_camp:
				total += int(_JISHOGI_VALUE.get(p.kind, 0))
	var h := state.hand(is_gote)
	for kind in h.keys():
		total += int(_JISHOGI_VALUE.get(kind, 0)) * int(h[kind])
	return total

# --- helpers ----------------------------------------------------------------

static func _leaves_king_safe(state: BoardStateScript, move: Dictionary) -> bool:
	var side := state.side_to_move_gote
	if not state.apply_move(move):
		return false
	var safe := not is_check(state, side)
	state.undo_move()
	return safe

static func _violates_nifu(state: BoardStateScript, file: int, is_gote: bool) -> bool:
	for r in range(1, 10):
		var p: PieceScript = state.piece_at(file, r)
		if p == null:
			continue
		if p.is_gote == is_gote and p.kind == PieceScript.Kind.PAWN:
			return true
	return false

# Dropped pawn giving checkmate is illegal (打ち歩詰め).
static func _is_uchifuzume(state: BoardStateScript, drop_move: Dictionary) -> bool:
	var dropper := state.side_to_move_gote
	state.apply_move(drop_move)
	var mate := is_check(state, state.side_to_move_gote) and not has_any_legal_move(state)
	state.undo_move()
	# Only relevant when the dropper delivers mate; return mate.
	return mate
