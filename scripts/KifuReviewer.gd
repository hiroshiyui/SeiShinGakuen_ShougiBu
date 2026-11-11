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
@onready var _filename_label: Label = %FilenameLabel
@onready var _ply_label: Label = %PlyLabel
@onready var _analysis_label: Label = %AnalysisLabel
@onready var _eval_graph: Control = %EvalGraph
@onready var _back_btn: Button = %BackButton
@onready var _analyze_btn: Button = %AnalyzeButton
@onready var _first_btn: Button = %FirstButton
@onready var _prev_btn: Button = %PrevButton
@onready var _next_btn: Button = %NextButton
@onready var _last_btn: Button = %LastButton

const Analyzer := preload("res://scripts/KifuAnalyzer.gd")

var _core: Object
var _packed: PackedInt32Array = PackedInt32Array()
var _ply: int = 0
# One entry per played move (so size == _packed.size()) once analysis
# completes; null entries mark plies the search couldn't evaluate (e.g.
# terminal positions returning no legal moves).
var _analyses: Array = []
var _analyzing: bool = false
# Whole-game analysis runs on this worker with its own ShogiCore, so the
# screen stays responsive. Progress is a plain int the UI polls.
var _analysis_thread: Thread = null
var _analysis_cancel: bool = false
var _analysis_progress: int = 0
# Shown instead of the analysis line when the file can't be read or
# replayed; empty when all is well.
var _load_error: String = ""

func _ready() -> void:
	# Consume the one-shot start ply up front, so an early return below
	# can't leave it for the next file the player opens.
	var start_ply: int = Settings.review_start_ply
	Settings.review_start_ply = -1
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
	if _packed.is_empty():
		_load_error = "棋譜を読み込めませんでした"
	# Start at the final position so the user sees the latest game state
	# first, then can rewind for study.
	_ply = _packed.size()
	if start_ply >= 0:
		# Opened from the 対局終了 dialog on a specific move.
		_ply = clampi(start_ply, 0, _packed.size())
	_replay_to_ply()

	_back_btn.pressed.connect(_pop_back)
	_analyze_btn.pressed.connect(_on_analyze)
	_analyze_btn.disabled = _packed.is_empty()
	_first_btn.pressed.connect(func(): _set_ply(0))
	_prev_btn.pressed.connect(func(): _set_ply(_ply - 1))
	_next_btn.pressed.connect(func(): _set_ply(_ply + 1))
	_last_btn.pressed.connect(func(): _set_ply(_packed.size()))
	_eval_graph.ply_selected.connect(_on_graph_ply_selected)

	get_viewport().size_changed.connect(_refit_board)
	_refit_board()

var _back_handled_frame: int = -1

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_handle_back()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()

func _handle_back() -> void:
	var f: int = Engine.get_process_frames()
	if _back_handled_frame == f:
		return
	_back_handled_frame = f
	_pop_back()

func _pop_back() -> void:
	_stop_analysis()
	SceneTransition.go_to("res://scenes/KifuLibrary.tscn")

func _exit_tree() -> void:
	_stop_analysis()

# Abandon a running analysis and join its thread (at most one search away).
func _stop_analysis() -> void:
	_analysis_cancel = true
	if _analysis_thread != null:
		_analysis_thread.wait_to_finish()
		_analysis_thread = null
		_analyzing = false

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
		_load_error = "この棋譜は再生できません"
	elif not _packed.is_empty():
		_load_error = ""
	_board_view.render(_core)
	_sente_hand.render(_core)
	_gote_hand.render(_core)
	# Highlight the move that brought us to this ply, same blue overlay
	# the in-game scene uses. Drops surface only the to-square (matching
	# GameController._refresh_last_move_hint).
	if _ply == 0:
		_board_view.clear_last_move()
	else:
		var last: Dictionary = Analyzer.decode_packed_move(_packed[_ply - 1])
		var from: Vector2i = Vector2i.ZERO
		if not last.has("drop_kind"):
			from = Vector2i(last["from"])
		_board_view.show_last_move(from, Vector2i(last["to"]))
	_ply_label.text = "%d / %d 手目" % [_ply, _packed.size()]
	_first_btn.disabled = _ply == 0 or _analyzing
	_prev_btn.disabled = _ply == 0 or _analyzing
	_next_btn.disabled = _ply == _packed.size() or _analyzing
	_last_btn.disabled = _ply == _packed.size() or _analyzing
	_refresh_analysis_label()
	_eval_graph.set_ply(_ply)

func _on_graph_ply_selected(ply: int) -> void:
	if not _analyzing:
		_set_ply(ply)

# Picks the analysis row matching the move that brought us to `_ply`
# (i.e. _packed[_ply - 1]) and renders the badge / win-rate. Hides the
# label while at the starting position or when no analysis has run yet.
func _refresh_analysis_label() -> void:
	if _load_error != "":
		_analysis_label.text = _load_error
		_analysis_label.add_theme_color_override("font_color", Color(1, 0.55, 0.5, 1))
		_analysis_label.visible = true
		return
	if _analyses.is_empty() or _ply == 0 or _ply > _analyses.size():
		_analysis_label.visible = false
		return
	var entry: Dictionary = _analyses[_ply - 1] if _analyses[_ply - 1] != null else {}
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
	_first_btn.disabled = true
	_prev_btn.disabled = true
	_next_btn.disabled = true
	_last_btn.disabled = true

	_analysis_cancel = false
	_analysis_progress = 0
	_analysis_thread = Thread.new()
	_analysis_thread.start(_run_analysis.bind(_packed, Settings.model_absolute_path()))

# Worker thread. Returns one entry per move, or null when the model
# could not be loaded or the analysis was cancelled.
func _run_analysis(packed: PackedInt32Array, model_path: String) -> Variant:
	var core: Object = ClassDB.instantiate("ShogiCore")
	if model_path == "" or not bool(core.load_model(model_path)):
		return null
	var out: Array = []
	out.resize(packed.size())
	out.fill({})
	for n in packed.size():
		if _analysis_cancel:
			return null
		out[n] = Analyzer.analyze_ply(core, packed, n)
		_analysis_progress = n + 1
	return out

func _process(_delta: float) -> void:
	if _analysis_thread == null:
		return
	_analyze_btn.text = "解析中… %d / %d" % [_analysis_progress, _packed.size()]
	if not _analysis_thread.is_alive():
		_finish_analysis()

func _finish_analysis() -> void:
	var result: Variant = _analysis_thread.wait_to_finish()
	_analysis_thread = null
	_analyzing = false
	if result == null:
		_analyze_btn.text = "解析失敗"
		_analyze_btn.add_theme_color_override("font_color", Color(1, 0.55, 0.5, 1))
		_replay_to_ply()
		return
	_analyses = result
	_analyze_btn.text = "解析済"
	# Running it again would only repeat the same ~30 s search.
	_analyze_btn.disabled = true
	# Settle on the theme's idle gold so the button reads as "done".
	_analyze_btn.remove_theme_color_override("font_color")
	_eval_graph.set_analyses(_analyses)
	_eval_graph.visible = true
	_refit_board()
	# Restore the user's view + re-render with the fresh analysis label.
	_replay_to_ply()

# Match GameController's board-fit math so the reviewer board respects
# the same hand / nav padding budget. Simpler than reusing the live
# controller's heuristic — the reviewer only has a fixed set of rows.
func _refit_board() -> void:
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	var reserved: float = 72.0 + 72.0 + 72.0 + 40.0 + 72.0 + 32.0  # header, hands×2, status, nav, pad
	if _analysis_label.visible or not _analyses.is_empty():
		reserved += 56.0
	if _eval_graph.visible:
		reserved += _eval_graph.custom_minimum_size.y + 8.0
	var side: float = clamp(min(vw - 40.0, vh - reserved), 240.0, 1600.0)
	_board_view.custom_minimum_size = Vector2(side, side)
