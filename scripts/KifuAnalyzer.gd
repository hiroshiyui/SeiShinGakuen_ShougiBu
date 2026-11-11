extends RefCounted

# Per-move MCTS analysis shared by the 棋譜検討 reviewer (whole game,
# evaluation graph) and the in-game 対局終了 dialog (加藤先生's comment
# on the player's moves). Stateless: every function takes the ShogiCore
# to work on, which must already have the model loaded.

# Heuristics for the per-move classification badge. Tuned conservatively
# so a casual blunder shows as 疑問手 (yellow) and an obvious giveaway
# shows as 悪手 (red) — Piyo Shogi uses similar bands.
const BAD_MOVE_THRESHOLD := 0.30
const QUESTIONABLE_THRESHOLD := 0.15
const GOOD_MOVE_THRESHOLD := 0.05
# Per-ply MCTS budget. 128 keeps the whole-game pass under ~30s on a
# mid-range phone while still giving the value head enough rollouts to
# differentiate top moves.
const PLAYOUTS := 128
const UNVISITED := -1.0

# Match Rust kifu::piece_kanji + the FILE_DIGITS / RANK_KANJI tables so
# engine-recommended moves render in the same notation as the played
# moves in the rest of the UI.
const PIECE_KANJI := {
	0: "歩", 1: "香", 2: "桂", 3: "銀", 4: "金", 5: "角", 6: "飛", 7: "玉",
	8: "と", 9: "成香", 10: "成桂", 11: "成銀", 12: "馬", 13: "龍",
}
const FILE_DIGIT := ["", "１", "２", "３", "４", "５", "６", "７", "８", "９"]

# Analyse the position before move `n` (0-based) of `packed`: replays
# the first n moves on `core`, searches, and rates the move actually
# played against the engine's best. Returns {} when the position can't
# be evaluated (replay failed, or no legal moves). Otherwise:
#   sente_winrate   0..1, the engine's evaluation before the move
#   delta           how much win rate the played move gave up (>= 0)
#   classification  "good" / "neutral" / "questionable" / "blunder"
#   best_kifu       the engine's pick in 棋譜 notation
#   mover_is_gote   who played the move
# Blocks for one search — call from a Thread or between frames.
static func analyze_ply(core: Object, packed: PackedInt32Array, n: int,
		playouts: int = PLAYOUTS) -> Dictionary:
	if not bool(core.apply_packed(packed.slice(0, n))):
		push_warning("analysis: apply_packed failed at ply %d" % n)
		return {}
	var stm_is_gote: bool = bool(core.side_to_move_gote())
	var top: Array = core.suggest_moves_mcts(32, playouts)
	if top.is_empty():
		return {}
	var best_q: float = float(top[0]["win_rate"])
	# best_q is from the perspective of whoever's about to move; project
	# back to sente so the graph reads consistently across both colours.
	var sente_winrate: float = best_q if not stm_is_gote else (1.0 - best_q)
	# Format the engine's pick while `core` is still at this position so
	# piece_at(from) returns the right kanji. A suggested recapture
	# renders as 同, same convention as the played kifu lines.
	var prev_dest: Variant = null
	if n > 0:
		prev_dest = Vector2i(decode_packed_move(packed[n - 1])["to"])
	var best_kifu: String = format_move_kifu(core, top[0], stm_is_gote, prev_dest)
	var actual_q: float = find_q_for_move(top, decode_packed_move(packed[n]))
	if actual_q < 0.0:
		actual_q = _q_after_move(core, packed, n, playouts)
	var delta: float = max(0.0, best_q - actual_q)
	return {
		sente_winrate = sente_winrate,
		delta = delta,
		classification = classify_delta(delta),
		best_kifu = best_kifu,
		mover_is_gote = stm_is_gote,
	}

# Evaluates move `n` by searching the position after it, for a move the
# root search never visited. Moves `core` past the analysed position.
static func _q_after_move(core: Object, packed: PackedInt32Array, n: int,
		playouts: int) -> float:
	if not bool(core.apply_packed(packed.slice(0, n + 1))):
		push_warning("analysis: apply_packed failed after ply %d" % n)
		return 0.0
	var replies: Array = core.suggest_moves_mcts(1, playouts)
	if replies.is_empty():
		# The move ended the game. Mate (or 手詰まり) is a win for the
		# mover, but the search also stops at 千日手: a draw, or a loss
		# for the side that kept checking.
		var mover_is_gote := not bool(core.side_to_move_gote())
		match str(core.detect_sennichite()):
			"draw":
				return 0.5
			"sente_loses":
				return 0.0 if not mover_is_gote else 1.0
			"gote_loses":
				return 0.0 if mover_is_gote else 1.0
		return 1.0
	return 1.0 - float(replies[0]["win_rate"])

static func classify_delta(delta: float) -> String:
	if delta < GOOD_MOVE_THRESHOLD:
		return "good"
	if delta < QUESTIONABLE_THRESHOLD:
		return "neutral"
	if delta < BAD_MOVE_THRESHOLD:
		return "questionable"
	return "blunder"

# Mirror of Rust kifu::pack_move so we can cheaply recover the move
# parameters on the GD side without round-tripping through apply_packed.
static func decode_packed_move(packed: int) -> Dictionary:
	var d: Dictionary = {}
	if packed & 1 != 0:
		d["drop_kind"] = (packed >> 1) & 0x0f
		d["to"] = _idx_to_square((packed >> 8) & 0x7f)
	else:
		d["from"] = _idx_to_square((packed >> 1) & 0x7f)
		d["to"] = _idx_to_square((packed >> 8) & 0x7f)
		d["promote"] = (packed >> 15) & 1 != 0
	return d

static func _idx_to_square(idx: int) -> Vector2i:
	return Vector2i(idx / 9 + 1, idx % 9 + 1)

# Render a single move (from suggest_moves_mcts output) as a kifu string
# in the same style as the played move log. No disambiguator, matching
# the v1 Rust formatter. `core` must still be at the pre-move position.
static func format_move_kifu(core: Object, mv: Dictionary, mover_is_gote: bool,
		prev_dest: Variant) -> String:
	var marker: String = "☖" if mover_is_gote else "☗"
	var to: Vector2i = Vector2i(mv["to"])
	var dest: String
	if prev_dest != null and Vector2i(prev_dest) == to:
		dest = "同　"
	else:
		dest = "%s%s" % [FILE_DIGIT[to.x], Settings.RANK_KANJI[to.y]]
	if mv.has("drop_kind"):
		var kind: int = int(mv["drop_kind"])
		return "%s%s%s打" % [marker, dest, PIECE_KANJI.get(kind, "?")]
	var from: Vector2i = Vector2i(mv["from"])
	var piece = core.piece_at(from.x, from.y)
	var piece_kanji: String = "?"
	if piece != null:
		piece_kanji = PIECE_KANJI.get(int(piece["kind"]), "?")
	var promote_marker: String = "成" if bool(mv["promote"]) else ""
	return "%s%s%s%s" % [marker, dest, piece_kanji, promote_marker]

# Walks suggest_moves_mcts output looking for the move actually played.
# Returns UNVISITED when the search has no value for it: the rows for
# unvisited moves carry a placeholder 50 %, not an evaluation.
static func find_q_for_move(top: Array, target: Dictionary) -> float:
	var target_is_drop: bool = target.has("drop_kind")
	for entry in top:
		var entry_is_drop: bool = entry.has("drop_kind")
		if entry_is_drop != target_is_drop:
			continue
		if Vector2i(entry["to"]) != Vector2i(target["to"]):
			continue
		if target_is_drop:
			if int(entry["drop_kind"]) == int(target["drop_kind"]):
				return _visited_q(entry)
		else:
			if Vector2i(entry["from"]) == Vector2i(target["from"]) \
					and bool(entry["promote"]) == bool(target["promote"]):
				return _visited_q(entry)
	return UNVISITED

static func _visited_q(entry: Dictionary) -> float:
	return float(entry["win_rate"]) if int(entry["visits"]) > 0 else UNVISITED

# The move worth talking about after a game: among the analysed moves
# played by `for_gote`'s side, the one that gave up the most win rate,
# provided it reached 疑問手. `analyses` is indexed by ply (0-based) with
# {} for plies that were not analysed. Returns {} when that side made no
# such mistake, else the analysis entry plus `ply` (1-based move number).
static func biggest_mistake(analyses: Array, for_gote: bool) -> Dictionary:
	var worst: Dictionary = {}
	for n in analyses.size():
		var e = analyses[n]
		if e == null or (e as Dictionary).is_empty():
			continue
		if bool(e["mover_is_gote"]) != for_gote:
			continue
		if float(e["delta"]) < QUESTIONABLE_THRESHOLD:
			continue
		if worst.is_empty() or float(e["delta"]) > float(worst["delta"]):
			worst = (e as Dictionary).duplicate()
			worst["ply"] = n + 1
	return worst
