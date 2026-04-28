extends SceneTree

# Build assets/opening_book.json from a hand-authored tree of common
# 平手 openings. Each entry pairs:
#   - reach: list of USI plies that start from the standard position and
#     end at the position we want to author candidates FOR (so reach=[]
#     is the starting position itself).
#   - candidates: list of {usi, weight} pairs the AI may sample at that
#     position. Weights are positive integers; sampled proportionally.
#     Greedy at temperature τ = 0.
#
# v1 covers the first 4–5 plies of the most common 居飛車 / 振り飛車
# starts. Extending the book is just appending entries here and re-
# running the script. Run:
#   godot --headless -s res://tools/gen_opening_book.gd --path .

const ENTRIES := [
	# --- starting position: sente's opening choice ---
	{
		reach = [],
		candidates = [
			{usi = "7g7f", weight = 50},   # 居飛車 / 矢倉系
			{usi = "2g2f", weight = 35},   # 飛車先突き
			{usi = "5g5f", weight = 10},   # 中飛車志向
			{usi = "6g6f", weight = 5},    # 四間飛車志向
		],
	},

	# --- after ☗7六歩: gote's reply ---
	{
		reach = ["7g7f"],
		candidates = [
			{usi = "8c8d", weight = 45},   # 相居飛車
			{usi = "3c3d", weight = 45},   # 矢倉 / 角換わり志向
			{usi = "4a3b", weight = 10},   # 雁木準備
		],
	},

	# --- after ☗7六歩 ☖8四歩: sente continues ---
	{
		reach = ["7g7f", "8c8d"],
		candidates = [
			{usi = "2g2f", weight = 50},   # 飛車先伸ばし
			{usi = "6g6f", weight = 25},   # 矢倉志向
			{usi = "7i7h", weight = 15},   # 角道止め
			{usi = "5g5f", weight = 10},
		],
	},

	# --- after ☗7六歩 ☖8四歩 ☗2六歩: gote ---
	{
		reach = ["7g7f", "8c8d", "2g2f"],
		candidates = [
			{usi = "8d8e", weight = 40},   # 相がかり / 横歩取り志向
			{usi = "3c3d", weight = 35},
			{usi = "4a3b", weight = 25},   # 矢倉志向
		],
	},

	# --- after ☗7六歩 ☖3四歩: sente ---
	{
		reach = ["7g7f", "3c3d"],
		candidates = [
			{usi = "2g2f", weight = 40},   # 角換わり狙い
			{usi = "6g6f", weight = 25},   # 矢倉
			{usi = "2g2f", weight = 0},    # placeholder removed
			{usi = "7i6h", weight = 20},   # 角道維持
			{usi = "5g5f", weight = 15},
		],
	},

	# --- after ☗7六歩 ☖3四歩 ☗2六歩: gote ---
	{
		reach = ["7g7f", "3c3d", "2g2f"],
		candidates = [
			{usi = "4a3b", weight = 35},
			{usi = "8c8d", weight = 35},
			{usi = "8b4b", weight = 30},   # 振り飛車志向 (gote's 4-file rook)
		],
	},

	# --- after ☗2六歩: gote ---
	{
		reach = ["2g2f"],
		candidates = [
			{usi = "8c8d", weight = 50},   # 相がかり
			{usi = "3c3d", weight = 40},
			{usi = "8b4b", weight = 10},
		],
	},

	# --- after ☗2六歩 ☖8四歩: sente ---
	{
		reach = ["2g2f", "8c8d"],
		candidates = [
			{usi = "2f2e", weight = 50},   # 飛車先伸ばし
			{usi = "7g7f", weight = 35},
			{usi = "9g9f", weight = 15},
		],
	},

	# --- after ☗5六歩 (中飛車志向): gote ---
	{
		reach = ["5g5f"],
		candidates = [
			{usi = "3c3d", weight = 40},
			{usi = "8c8d", weight = 40},
			{usi = "5c5d", weight = 20},   # 相中飛車
		],
	},

	# --- after ☗5六歩 ☖8四歩: sente sets up 中飛車 ---
	{
		reach = ["5g5f", "8c8d"],
		candidates = [
			{usi = "2h5h", weight = 60},   # 中飛車 振り
			{usi = "5i6h", weight = 20},
			{usi = "7g7f", weight = 20},
		],
	},

	# --- after ☗6六歩 (四間飛車志向): gote ---
	{
		reach = ["6g6f"],
		candidates = [
			{usi = "8c8d", weight = 45},
			{usi = "3c3d", weight = 45},
			{usi = "5c5d", weight = 10},
		],
	},

	# --- after ☗6六歩 ☖3四歩: sente振る ---
	{
		reach = ["6g6f", "3c3d"],
		candidates = [
			{usi = "2h6h", weight = 60},   # 四間飛車
			{usi = "7g7f", weight = 30},
			{usi = "5g5f", weight = 10},
		],
	},
]

# Deeper mainlines authored as a single ply sequence + optional alternate
# branches at specific depths. _explode_lines() turns each LINE into one
# entry per position along the way, with the next ply as the primary
# candidate (weight = LINE_PRIMARY_WEIGHT) and any `alts[i]` listed
# alongside. Entries that converge on the same position key are merged
# in _initialize() so converging lines union their candidate lists.
#
# Plies start from the standard initial position. Even-indexed plies
# are sente moves, odd-indexed are gote replies.
const LINE_PRIMARY_WEIGHT := 60

const LINES := [
	# ─ 矢倉本線 (居飛車相懸 矢倉) ─────────────────────────────
	{
		plies = ["7g7f","8c8d","6g6f","8d8e","7i7h","3c3d","7h7g","4a3b","5g5f","5c5d","4i5h","5a4b","3i4h","6a5b","5i6h","7a7b"],
		alts = {
			3: [{usi="3c3d",weight=20}],
			5: [{usi="6c6d",weight=15}],
			11: [{usi="7a6b",weight=20}],
		},
	},
	# ─ 角換わり (角道を開けてからの構え) ─────────────────────
	# Book ends before the bishop trade — the actual 8h2b+ recapture
	# move depends on which gote piece is on 3b/3a at trade time, and
	# coding the variation is more error-prone than letting MCTS take
	# over with a sound development pattern.
	{
		plies = ["7g7f","3c3d","2g2f","4a3b","2f2e","3a4b"],
		alts = {
			5: [{usi="2c2d",weight=15}],
		},
	},
	# ─ 横歩取り ─────────────────────────────────────────────
	{
		plies = ["7g7f","8c8d","2g2f","8d8e","2f2e","3c3d","2e2d","2c2d","2h2d","8e8f","8g8f","8b8f","2d3d","2b3c"],
		alts = {
			11: [{usi="P*8g",weight=20}],
		},
	},
	# ─ 中飛車 (▲5六歩からの中飛車) ────────────────────────────
	{
		plies = ["5g5f","3c3d","2h5h","8c8d","5i4h","4a3b","4h3h","5a4b","3h2h","6a5b","6i7h","6c6d"],
		alts = {
			1: [{usi="8c8d",weight=30},{usi="5c5d",weight=15}],
		},
	},
	# ─ 四間飛車 (vs 居飛車) ─────────────────────────────────
	{
		plies = ["7g7f","3c3d","6g6f","8c8d","2h6h","6a5b","6i7h","4a3b","4i5h","5a4b","5i6i","6c6d"],
		alts = {
			3: [{usi="3c3d",weight=15}],
		},
	},
	# ─ 三間飛車 ─────────────────────────────────────────────
	{
		plies = ["7g7f","3c3d","6g6f","8c8d","2h7h","4a3b","5i6h","5a4b"],
	},
	# ─ 早石田 ─────────────────────────────────────────────
	{
		plies = ["7g7f","3c3d","7f7e","4a3b","8h7g","8c8d","2h7h","8d8e"],
	},
	# ─ 雁木 (居飛車左美濃〜雁木) ──────────────────────────────
	{
		plies = ["7g7f","8c8d","6g6f","3c3d","2g2f","4a3b","5g5f","5c5d","6i7h","6a5b","4i5h","5a4b"],
	},
	# ─ 端歩・脇道への gote 受け ─────────────────────────────
	# Off-book sente moves the AI-as-gote should reply sensibly to.
	# `start_at = 1` means we don't emit an entry for the *root*
	# position (we don't want the AI-as-sente to *play* 1g1f); only
	# the depth-1 entry (the gote reply) ends up in the book.
	{plies = ["1g1f","8c8d"], start_at = 1},
	{plies = ["9g9f","8c8d"], start_at = 1},
	{plies = ["4g4f","8c8d"], start_at = 1},
	{plies = ["3g3f","8c8d"], start_at = 1},
	{plies = ["1g1f","1c1d"], start_at = 1},  # alt: gote mirrors
	{plies = ["9g9f","9c9d"], start_at = 1},
]

func _explode_lines() -> Array:
	# Expand each LINE into one {reach, candidates} entry per position.
	# alts at index i extend the candidate list for the entry whose
	# `reach` is plies[0..i]. `start_at` (default 0) lets a LINE skip
	# emitting entries for shallow depths — useful for "AI-as-gote
	# reply only" lines whose first ply belongs to the human, not to
	# the AI's repertoire.
	var out: Array = []
	for line in LINES:
		var plies: Array = line.plies
		var alts: Dictionary = line.get("alts", {})
		var start_at: int = int(line.get("start_at", 0))
		for i in range(start_at, plies.size()):
			var reach: Array = []
			for j in range(i):
				reach.append(plies[j])
			var cands: Array = [{usi = plies[i], weight = LINE_PRIMARY_WEIGHT}]
			if alts.has(i):
				for a in alts[i]:
					cands.append({usi = String(a.usi), weight = int(a.weight)})
			out.append({reach = reach, candidates = cands})
	return out

func _initialize() -> void:
	if not ClassDB.class_exists("ShogiCore"):
		push_error("ShogiCore not registered — build the desktop .so first")
		quit(1)
		return

	var book: Dictionary = {}
	var skipped: int = 0

	var all_entries: Array = []
	for e in ENTRIES:
		all_entries.append(e)
	for e in _explode_lines():
		all_entries.append(e)

	for entry in all_entries:
		var core = ClassDB.instantiate("ShogiCore")
		core.reset_starting()
		var ok := true
		for usi in entry.reach:
			if not _apply_usi(core, usi):
				push_warning("gen_opening_book: cannot apply `%s` from sequence %s — skipping entry" % [usi, entry.reach])
				ok = false
				break
		if not ok:
			skipped += 1
			continue
		var key: String = String(core.position_key())
		# Merge with whatever's already at this key — converging lines
		# (e.g. 矢倉 and 角換わり both touching the after-7g7f node) should
		# union their candidate lists instead of overwriting. For
		# duplicate USI moves, the *first* writer wins: ENTRIES is
		# processed before LINES so curated frequencies (e.g. the
		# starting position's 50/35/10/5 distribution) aren't clobbered
		# by LINE_PRIMARY_WEIGHT just because some line happens to
		# emit the same first ply.
		var existing: Array = book.get(key, [])
		var by_usi: Dictionary = {}
		for cand in existing:
			by_usi[String(cand.usi)] = int(cand.weight)
		for cand in entry.candidates:
			if int(cand.weight) <= 0:
				# Weight 0 = explicitly excluded from this revision.
				continue
			var u := String(cand.usi)
			if by_usi.has(u):
				continue
			by_usi[u] = int(cand.weight)
		var arr: Array = []
		for u in by_usi.keys():
			arr.append({usi = u, weight = int(by_usi[u])})
		if arr.is_empty():
			continue
		book[key] = arr

	var out := JSON.stringify(book, "  ", false)
	var dst := "res://assets/opening_book.json"
	var dst_abs := ProjectSettings.globalize_path(dst)
	var f := FileAccess.open(dst_abs, FileAccess.WRITE)
	if f == null:
		push_error("cannot open %s for write" % dst_abs)
		quit(1)
		return
	f.store_string(out + "\n")
	f.close()
	print("wrote %d positions (%d entries skipped) to %s" % [book.size(), skipped, dst_abs])
	quit()

# Minimal in-script USI parser so we don't need to expose one through FFI
# just for the build-side generator. Mirrors opening_book::parse_usi.
func _apply_usi(core, usi: String) -> bool:
	var bytes := usi.to_ascii_buffer()
	if bytes.size() < 4:
		return false
	var mv: Dictionary = {}
	if bytes[1] == 0x2A:  # '*'
		# Drop. Piece kinds keyed by USI letter (P/L/N/S/G/B/R), promoted
		# pieces aren't valid drops.
		var kind := -1
		match bytes[0]:
			0x50: kind = 0  # P → Pawn
			0x4C: kind = 1  # L → Lance
			0x4E: kind = 2  # N → Knight
			0x53: kind = 3  # S → Silver
			0x47: kind = 4  # G → Gold
			0x42: kind = 5  # B → Bishop
			0x52: kind = 6  # R → Rook
			_:    return false
		var to := _square(bytes[2], bytes[3])
		if to == Vector2i.ZERO:
			return false
		mv = {drop_kind = kind, to = to}
	else:
		var from := _square(bytes[0], bytes[1])
		var to := _square(bytes[2], bytes[3])
		if from == Vector2i.ZERO or to == Vector2i.ZERO:
			return false
		mv = {from = from, to = to, promote = bytes.size() == 5 and bytes[4] == 0x2B}
	return bool(core.apply_move(mv))

func _square(file_byte: int, rank_byte: int) -> Vector2i:
	if file_byte < 0x31 or file_byte > 0x39 or rank_byte < 0x61 or rank_byte > 0x69:
		return Vector2i.ZERO
	return Vector2i(file_byte - 0x30, rank_byte - 0x60)
