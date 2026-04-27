extends Control

# Pure-review viewer for a saved .kif file. Replays from start to ply N
# on a private ShogiCore each step — no AI, no input on the board.
# v1 ships with first/prev/next/last buttons; tap-a-row jumping via the
# MoveHistoryDialog can land in v2 once the share/return-to-live buttons
# learn a "review-only" mode.

const PieceScript := preload("res://scripts/game/Piece.gd")

@onready var _board_view = %BoardView
@onready var _sente_hand = %SenteHand
@onready var _gote_hand = %GoteHand
@onready var _layout: VBoxContainer = $Layout
@onready var _filename_label: Label = %FilenameLabel
@onready var _ply_label: Label = %PlyLabel
@onready var _analysis_label: Label = %AnalysisLabel
@onready var _back_btn: Button = %BackButton
@onready var _analyze_btn: Button = %AnalyzeButton
@onready var _first_btn: Button = %FirstButton
@onready var _prev_btn: Button = %PrevButton
@onready var _next_btn: Button = %NextButton
@onready var _last_btn: Button = %LastButton

# Heuristics for the per-move classification badge. Tuned conservatively
# so a casual blunder shows as 疑問手 (yellow) and an obvious giveaway
# shows as 悪手 (red) — Piyo Shogi uses similar bands.
const _BAD_MOVE_THRESHOLD := 0.30
const _QUESTIONABLE_THRESHOLD := 0.15
const _GOOD_MOVE_THRESHOLD := 0.05
# Per-ply MCTS budget. 128 keeps the whole-game pass under ~30s on a
# mid-range phone while still giving the value head enough rollouts to
# differentiate top moves.
const _ANALYSIS_PLAYOUTS := 128

# Match Rust kifu::piece_kanji + the FILE_DIGITS / RANK_KANJI tables so
# engine-recommended moves render in the same notation as the played
# moves in the rest of the UI.
const _PIECE_KANJI := {
	0: "歩", 1: "香", 2: "桂", 3: "銀", 4: "金", 5: "角", 6: "飛", 7: "玉",
	8: "と", 9: "成香", 10: "成桂", 11: "成銀", 12: "馬", 13: "龍",
}
const _FILE_DIGIT := ["", "１", "２", "３", "４", "５", "６", "７", "８", "９"]
const _RANK_KANJI := ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

var _core: Object
var _packed: PackedInt32Array = PackedInt32Array()
var _ply: int = 0
# One entry per played move (so size == _packed.size()) once analysis
# completes; null entries mark plies the search couldn't evaluate (e.g.
# terminal positions returning no legal moves).
var _analyses: Array = []
var _analyzing: bool = false

func _ready() -> void:
	if not ClassDB.class_exists("ShogiCore"):
		push_error("ShogiCore GDExtension not loaded")
		_pop_back()
		return
	if Settings.review_kif_path == "":
		push_warning("kifu reviewer: no path; returning to library")
		_pop_back()
		return
	var path: String = Settings.review_kif_path
	Settings.review_kif_path = ""  # consume
	_filename_label.text = path.get_file()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("kifu reviewer: cannot open %s" % path)
		_pop_back()
		return
	var text := f.get_as_text()
	f.close()

	_core = ClassDB.instantiate("ShogiCore")
	_packed = _core.parse_kif_to_packed(text)
	# Start at the final position so the user sees the latest game state
	# first, then can rewind for study.
	_ply = _packed.size()
	_replay_to_ply()

	_back_btn.pressed.connect(_pop_back)
	_analyze_btn.pressed.connect(_on_analyze)
	_analyze_btn.disabled = _packed.is_empty()
	_first_btn.pressed.connect(func(): _set_ply(0))
	_prev_btn.pressed.connect(func(): _set_ply(_ply - 1))
	_next_btn.pressed.connect(func(): _set_ply(_ply + 1))
	_last_btn.pressed.connect(func(): _set_ply(_packed.size()))

	get_viewport().size_changed.connect(_refit_board)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_refit_board()

func _apply_safe_area() -> void:
	var insets: Rect2 = Settings.safe_area_insets(get_viewport_rect().size)
	_layout.offset_left = insets.position.x
	_layout.offset_top = insets.position.y
	_layout.offset_right = -insets.size.x
	_layout.offset_bottom = -insets.size.y

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_pop_back()

func _pop_back() -> void:
	get_tree().change_scene_to_file("res://scenes/KifuLibrary.tscn")

func _set_ply(n: int) -> void:
	var clamped: int = clamp(n, 0, _packed.size())
	if clamped == _ply:
		return
	_ply = clamped
	_replay_to_ply()

func _replay_to_ply() -> void:
	var prefix: PackedInt32Array = _packed.slice(0, _ply)
	if not bool(_core.apply_packed(prefix)):
		push_warning("kifu reviewer: apply_packed failed at ply %d" % _ply)
	_board_view.render(_core)
	_sente_hand.render(_core)
	_gote_hand.render(_core)
	_ply_label.text = "%d / %d 手目" % [_ply, _packed.size()]
	_first_btn.disabled = _ply == 0 or _analyzing
	_prev_btn.disabled = _ply == 0 or _analyzing
	_next_btn.disabled = _ply == _packed.size() or _analyzing
	_last_btn.disabled = _ply == _packed.size() or _analyzing
	_refresh_analysis_label()

# Picks the analysis row matching the move that brought us to `_ply`
# (i.e. _packed[_ply - 1]) and renders the badge / win-rate. Hides the
# label while at the starting position or when no analysis has run yet.
func _refresh_analysis_label() -> void:
	if _analyses.is_empty() or _ply == 0 or _ply > _analyses.size():
		_analysis_label.visible = false
		return
	var entry: Dictionary = _analyses[_ply - 1]
	if entry.is_empty():
		_analysis_label.visible = false
		return
	var badge_text: String = ""
	var color: Color = Color(0.95, 0.88, 0.6, 1)
	match String(entry["classification"]):
		"good":
			badge_text = "◎ 好手"
			color = Color(0.6, 0.95, 0.55, 1)
		"questionable":
			badge_text = "△ 疑問手"
			color = Color(0.95, 0.85, 0.45, 1)
		"blunder":
			badge_text = "× 悪手"
			color = Color(1, 0.55, 0.5, 1)
	var winrate_pct: int = roundi(float(entry["sente_winrate"]) * 100.0)
	var delta_pct: int = roundi(float(entry["delta"]) * 100.0)
	var parts: Array[String] = ["先手勝率 %d%%" % winrate_pct]
	if badge_text != "":
		parts.append(badge_text)
	if delta_pct >= 5:
		parts.append("(-%d%%)" % delta_pct)
	# Only nudge the user toward the engine's pick when their move was
	# meaningfully worse — surfacing 推奨 on every neutral move would be
	# nagging.
	var classification: String = String(entry["classification"])
	var best_kifu: String = String(entry.get("best_kifu", ""))
	if best_kifu != "" and (classification == "questionable" or classification == "blunder"):
		parts.append("推奨: %s" % best_kifu)
	_analysis_label.text = "  ".join(parts)
	_analysis_label.add_theme_color_override("font_color", color)
	_analysis_label.visible = true

# --- analysis -------------------------------------------------------------

func _on_analyze() -> void:
	if _analyzing or _packed.is_empty():
		return
	_analyzing = true
	# Keep the button visually enabled while running so the "解析中" text
	# stays bright against the dark theme; the _analyzing guard above
	# already swallows extra taps.
	_analyze_btn.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65, 1))
	_back_btn.disabled = true
	_first_btn.disabled = true
	_prev_btn.disabled = true
	_next_btn.disabled = true
	_last_btn.disabled = true

	var model_path: String = Settings.model_absolute_path()
	if model_path == "" or not bool(_core.load_model(model_path)):
		_analyze_btn.text = "解析失敗"
		_analyze_btn.add_theme_color_override("font_color", Color(1, 0.55, 0.5, 1))
		_analyzing = false
		_back_btn.disabled = false
		return

	_analyses.clear()
	_analyses.resize(_packed.size())
	var total: int = _packed.size()
	for n in range(total):
		var prefix: PackedInt32Array = _packed.slice(0, n)
		if not bool(_core.apply_packed(prefix)):
			push_warning("analysis: apply_packed failed at ply %d" % n)
			break
		var stm_is_gote: bool = bool(_core.side_to_move_gote())
		var top: Array = _core.suggest_moves_mcts(32, _ANALYSIS_PLAYOUTS)
		if top.is_empty():
			continue
		var best_q: float = float(top[0]["win_rate"])
		var actual_dict: Dictionary = _decode_packed_move(_packed[n])
		var actual_q: float = _find_q_for_move(top, actual_dict)
		var delta: float = max(0.0, best_q - actual_q)
		# best_q is from the perspective of whoever's about to move; project
		# back to sente so the per-ply bar reads consistently across both
		# colours' moves.
		var sente_winrate: float = best_q if not stm_is_gote else (1.0 - best_q)
		# Format the engine's pick BEFORE moving on; we need _core to still
		# be at this position so piece_at(from) returns the right kanji.
		# Use the previously played move's destination (if any) so a
		# suggested recapture renders as 同 — same convention the played
		# kifu lines use.
		var prev_dest: Variant = null
		if n > 0:
			prev_dest = Vector2i(_decode_packed_move(_packed[n - 1])["to"])
		var best_kifu: String = _format_move_kifu(top[0], stm_is_gote, prev_dest)
		_analyses[n] = {
			sente_winrate = sente_winrate,
			delta = delta,
			classification = _classify_delta(delta),
			best_kifu = best_kifu,
		}
		_analyze_btn.text = "解析中… %d / %d" % [n + 1, total]
		# Yield often enough that the UI stays responsive but not so often
		# we tank the playouts/sec from frame churn.
		if n % 2 == 0:
			await get_tree().process_frame
			if not is_inside_tree():
				return

	_analyze_btn.text = "解析済"
	# Settle on the theme's idle gold so the button reads as "done".
	_analyze_btn.remove_theme_color_override("font_color")
	_analyzing = false
	_back_btn.disabled = false
	# Restore the user's view + re-render with the fresh analysis label.
	_replay_to_ply()

func _classify_delta(delta: float) -> String:
	if delta < _GOOD_MOVE_THRESHOLD:
		return "good"
	if delta < _QUESTIONABLE_THRESHOLD:
		return "neutral"
	if delta < _BAD_MOVE_THRESHOLD:
		return "questionable"
	return "blunder"

# Mirror of Rust kifu::pack_move so we can cheaply recover the move
# parameters on the GD side without round-tripping through apply_packed.
func _decode_packed_move(packed: int) -> Dictionary:
	var d: Dictionary = {}
	if packed & 1 != 0:
		d["drop_kind"] = (packed >> 1) & 0x0f
		d["to"] = _idx_to_square((packed >> 8) & 0x7f)
	else:
		d["from"] = _idx_to_square((packed >> 1) & 0x7f)
		d["to"] = _idx_to_square((packed >> 8) & 0x7f)
		d["promote"] = (packed >> 15) & 1 != 0
	return d

func _idx_to_square(idx: int) -> Vector2i:
	return Vector2i(idx / 9 + 1, idx % 9 + 1)

# Render a single move (from suggest_moves_mcts output) as a kifu string
# in the same style as the played move log. Only used for the "推奨"
# hint, so kept minimal — no disambiguator either, matching the v1
# Rust formatter. `_core` must still be at the pre-move position.
func _format_move_kifu(mv: Dictionary, mover_is_gote: bool, prev_dest: Variant) -> String:
	var marker: String = "☖" if mover_is_gote else "☗"
	var to: Vector2i = Vector2i(mv["to"])
	var dest: String
	if prev_dest != null and Vector2i(prev_dest) == to:
		dest = "同　"
	else:
		dest = "%s%s" % [_FILE_DIGIT[to.x], _RANK_KANJI[to.y]]
	if mv.has("drop_kind"):
		var kind: int = int(mv["drop_kind"])
		return "%s%s%s打" % [marker, dest, _PIECE_KANJI.get(kind, "?")]
	var from: Vector2i = Vector2i(mv["from"])
	var piece = _core.piece_at(from.x, from.y)
	var piece_kanji: String = "?"
	if piece != null:
		piece_kanji = _PIECE_KANJI.get(int(piece["kind"]), "?")
	var promote_marker: String = "成" if bool(mv["promote"]) else ""
	return "%s%s%s%s" % [marker, dest, piece_kanji, promote_marker]

# Walks suggest_moves_mcts output looking for the move actually played.
# Returns 0.0 if it wasn't visited — that's the worst possible q anyway,
# so the delta heuristic still flags it as a blunder.
func _find_q_for_move(top: Array, target: Dictionary) -> float:
	var target_is_drop: bool = target.has("drop_kind")
	for entry in top:
		var entry_is_drop: bool = entry.has("drop_kind")
		if entry_is_drop != target_is_drop:
			continue
		if Vector2i(entry["to"]) != Vector2i(target["to"]):
			continue
		if target_is_drop:
			if int(entry["drop_kind"]) == int(target["drop_kind"]):
				return float(entry["win_rate"])
		else:
			if Vector2i(entry["from"]) == Vector2i(target["from"]) \
					and bool(entry["promote"]) == bool(target["promote"]):
				return float(entry["win_rate"])
	return 0.0

# Match GameController's board-fit math so the reviewer board respects
# the same hand / nav padding budget. Simpler than reusing the live
# controller's heuristic — the reviewer only has a fixed set of rows.
func _refit_board() -> void:
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	var reserved: float = 56.0 + 72.0 + 72.0 + 40.0 + 64.0 + 32.0
	var side: float = clamp(min(vw - 40.0, vh - reserved), 240.0, 1600.0)
	_board_view.custom_minimum_size = Vector2(side, side)
