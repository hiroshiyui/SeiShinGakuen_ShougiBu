extends Control

# 詰将棋 — mate problems as "club homework". The player is always the
# attacker (先手, bottom) and must give check with every move; the
# defender's replies come from the Rust mate solver
# (ShogiCore.tsume_defense), which also judges each move, so any
# sequence that mates within the stated length is accepted, not just one
# stored line. Problems live in assets/tsume.json (tools/gen_tsume.gd).

const PieceScript := preload("res://scripts/game/Piece.gd")
const BoardViewScript := preload("res://scripts/game/BoardView.gd")
const HandViewScript := preload("res://scripts/game/HandView.gd")

const PROBLEMS_PATH := "res://assets/tsume.json"
const LEVELS := [1, 3, 5]
# Pause before the defender replies / before a wrong line is taken back,
# so the player sees their own move land first.
const REPLY_DELAY_SEC := 0.55
const RESET_DELAY_SEC := 1.3

enum SelState { IDLE, BOARD, HAND }

@onready var _board_view: BoardViewScript = %BoardView
@onready var _sente_hand: HandViewScript = %SenteHand
@onready var _gote_hand: HandViewScript = %GoteHand
@onready var _title_label: Label = %TitleLabel
@onready var _status: Label = %StatusLabel
@onready var _back_btn: Button = %BackButton
@onready var _level_row: HBoxContainer = %LevelRow
@onready var _daily_btn: Button = %DailyButton
@onready var _retry_btn: Button = %RetryButton
@onready var _hint_btn: Button = %HintButton
@onready var _prev_btn: Button = %PrevButton
@onready var _next_btn: Button = %NextButton
@onready var _promo_dialog: ConfirmationDialog = %PromotionDialog

var _core: Object
# plies -> Array of {sfen, plies}
var _problems: Dictionary = {}
var _level_buttons: Dictionary = {}
var _plies: int = 1
var _index: int = 0
var _plies_left: int = 0
var _solved: bool = false
# Input is locked while the defender replies or a wrong line resets.
var _busy: bool = false
# Bumped on every problem load so a pending delayed reply / reset from
# the previous problem can tell it is stale.
var _epoch: int = 0
var _sel_state: int = SelState.IDLE
var _sel_from: Vector2i = Vector2i.ZERO
var _sel_drop_kind: int = -1
var _pending_move: Dictionary = {}

func _ready() -> void:
	if not ClassDB.class_exists("ShogiCore"):
		push_error("ShogiCore GDExtension not loaded")
		_pop_back()
		return
	_core = ClassDB.instantiate("ShogiCore")
	_load_problems()
	_board_view.square_tapped.connect(_on_board_tapped)
	_sente_hand.piece_tapped.connect(_on_hand_tapped)
	_promo_dialog.confirmed.connect(_on_promo_confirmed)
	_promo_dialog.canceled.connect(_on_promo_canceled)
	_promo_dialog.close_requested.connect(_on_promo_canceled)
	ModalBlur.attach(_promo_dialog)
	_back_btn.pressed.connect(_pop_back)
	_retry_btn.pressed.connect(_restart_problem)
	_hint_btn.pressed.connect(_on_hint)
	_prev_btn.pressed.connect(func(): _open(_plies, _index - 1))
	_next_btn.pressed.connect(func(): _open(_plies, _index + 1))
	_daily_btn.pressed.connect(_open_daily)
	for plies in LEVELS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 72)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_on_level_pressed.bind(plies))
		_level_row.add_child(b)
		_level_buttons[plies] = b
	_level_row.move_child(_daily_btn, _level_row.get_child_count() - 1)
	get_viewport().size_changed.connect(_refit_board)
	_refit_board()
	if _total() == 0:
		_title_label.text = "詰将棋"
		_status.text = "問題が見つかりません"
		_set_controls_enabled(false)
		return
	var start: int = Settings.tsume_plies if _count(Settings.tsume_plies) > 0 else _first_level()
	_open(start, _first_unsolved(start))

func _load_problems() -> void:
	for plies in LEVELS:
		_problems[plies] = []
	var f := FileAccess.open(PROBLEMS_PATH, FileAccess.READ)
	if f == null:
		push_warning("tsume: cannot open %s" % PROBLEMS_PATH)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Array):
		push_warning("tsume: %s is not a list" % PROBLEMS_PATH)
		return
	for entry in data:
		if not (entry is Dictionary) or not entry.has("sfen"):
			continue
		var plies := int(entry.get("plies", 0))
		if _problems.has(plies):
			_problems[plies].append(entry)

func _count(plies: int) -> int:
	return (_problems.get(plies, []) as Array).size()

func _total() -> int:
	var n := 0
	for plies in LEVELS:
		n += _count(plies)
	return n

func _first_level() -> int:
	for plies in LEVELS:
		if _count(plies) > 0:
			return plies
	return LEVELS[0]

# Position part of an SFEN (board, side, hands) — the identity of a
# problem for the solved list; the move counter is irrelevant.
static func _key(sfen: String) -> String:
	return sfen.rsplit(" ", true, 1)[0]

func _is_solved(plies: int, index: int) -> bool:
	return Settings.tsume_solved.has(_key(str(_problems[plies][index]["sfen"])))

func _solved_count(plies: int) -> int:
	var n := 0
	for i in _count(plies):
		if _is_solved(plies, i):
			n += 1
	return n

func _first_unsolved(plies: int) -> int:
	for i in _count(plies):
		if not _is_solved(plies, i):
			return i
	return 0

# 今日の一問: the same problem for everyone on a given date, cycling
# through the whole set.
func _open_daily() -> void:
	var day := int(Time.get_unix_time_from_system() / 86400.0)
	var n := day % _total()
	for plies in LEVELS:
		if n < _count(plies):
			_open(plies, n)
			return
		n -= _count(plies)

func _on_level_pressed(plies: int) -> void:
	if _count(plies) == 0:
		_refresh_header()
		return
	_open(plies, _first_unsolved(plies))

func _open(plies: int, index: int) -> void:
	if _count(plies) == 0:
		return
	_plies = plies
	_index = posmod(index, _count(plies))
	Settings.set_tsume_plies(plies)
	_restart_problem()

func _restart_problem() -> void:
	_epoch += 1
	_busy = false
	_solved = false
	_pending_move = {}
	var problem: Dictionary = _problems[_plies][_index]
	if not bool(_core.load_sfen(str(problem["sfen"]))):
		push_warning("tsume: bad sfen %s" % problem["sfen"])
	_plies_left = _plies
	_board_view.clear_last_move()
	_clear_selection()
	_render()
	_status.text = "王手の連続で玉を詰ませてください"
	_status.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98, 1))
	_refresh_header()

func _refresh_header() -> void:
	# No problems at this level (tsume.json missing or corrupt): there is
	# no "current problem" to look up.
	var solved := _count(_plies) > 0 and _is_solved(_plies, _index)
	_title_label.text = "%d手詰  第%d問 / %d問%s" % [
		_plies, _index + 1, _count(_plies), "  【済】" if solved else ""]
	for plies in LEVELS:
		var b: Button = _level_buttons[plies]
		b.text = "%d手詰 %d/%d" % [plies, _solved_count(plies), _count(plies)]
		b.set_pressed_no_signal(plies == _plies)
		b.disabled = _count(plies) == 0
	_prev_btn.disabled = _count(_plies) < 2
	_next_btn.disabled = _count(_plies) < 2
	_hint_btn.disabled = _solved

func _set_controls_enabled(enabled: bool) -> void:
	for b: Button in [_retry_btn, _hint_btn, _prev_btn, _next_btn, _daily_btn]:
		b.disabled = not enabled

func _render() -> void:
	_board_view.render(_core)
	_sente_hand.render(_core)
	_gote_hand.render(_core)

# --- input (same two-tap flow as the main game) ----------------------------

func _can_input() -> bool:
	return not _busy and not _solved and _total() > 0 and not bool(_core.side_to_move_gote())

func _clear_selection() -> void:
	_sel_state = SelState.IDLE
	_sel_from = Vector2i.ZERO
	_sel_drop_kind = -1
	_board_view.clear_selected()
	_board_view.clear_move_hints()
	_sente_hand.clear_selected_kind()
	_sente_hand.render(_core)

func _on_board_tapped(file: int, rank: int) -> void:
	if not _can_input():
		return
	var key := Vector2i(file, rank)
	match _sel_state:
		SelState.IDLE:
			_try_select_board(key)
		SelState.BOARD:
			_handle_board_target(key)
		SelState.HAND:
			_handle_drop_target(key)

func _on_hand_tapped(kind: int) -> void:
	if not _can_input():
		return
	_clear_selection()
	var drops: Array = _core.legal_drops(kind)
	if drops.is_empty():
		return
	_sel_state = SelState.HAND
	_sel_drop_kind = kind
	_sente_hand.set_selected_kind(kind)
	_sente_hand.render(_core)
	var targets: Array = []
	for m in drops:
		targets.append(Vector2i(m["to"]))
	_board_view.show_move_hints(targets)

func _try_select_board(key: Vector2i) -> void:
	var piece = _core.piece_at(key.x, key.y)
	if piece == null:
		return
	if bool(piece["is_gote"]):
		_reject_tap(key)
		return
	var moves: Array = _core.legal_moves_from(key.x, key.y)
	if moves.is_empty():
		return
	_sel_state = SelState.BOARD
	_sel_from = key
	_board_view.set_selected(key)
	var targets: Array = []
	var seen: Dictionary = {}
	for m in moves:
		var to: Vector2i = Vector2i(m["to"])
		if not seen.has(to):
			seen[to] = true
			targets.append(to)
	_board_view.show_move_hints(targets)

func _handle_board_target(to: Vector2i) -> void:
	if to == _sel_from:
		_clear_selection()
		return
	var tp = _core.piece_at(to.x, to.y)
	if tp != null and not bool(tp["is_gote"]):
		_clear_selection()
		_try_select_board(to)
		return
	var candidates: Array = []
	for m in _core.legal_moves_from(_sel_from.x, _sel_from.y):
		if Vector2i(m["to"]) == to:
			candidates.append(m)
	if candidates.is_empty():
		_reject_tap(to)
		return
	var plain: Dictionary = {}
	var has_promo := false
	for m in candidates:
		if bool(m.get("promote", false)):
			has_promo = true
		else:
			plain = m
	if has_promo and not plain.is_empty():
		_pending_move = plain
		_promo_dialog.dialog_text = "%d%s で成りますか?" % [to.x, Settings.RANK_KANJI[to.y]]
		_promo_dialog.popup_centered()
	else:
		_play(candidates[0])

func _handle_drop_target(to: Vector2i) -> void:
	var tp = _core.piece_at(to.x, to.y)
	if tp != null:
		if not bool(tp["is_gote"]):
			_clear_selection()
			_try_select_board(to)
		return
	for m in _core.legal_drops(_sel_drop_kind):
		if Vector2i(m["to"]) == to:
			_play(m)
			return
	_reject_tap(to)

func _reject_tap(key: Vector2i) -> void:
	_board_view.flash_invalid(key)
	Input.vibrate_handheld(20)

func _on_promo_confirmed() -> void:
	if _pending_move.is_empty():
		return
	var m: Dictionary = _pending_move.duplicate()
	m["promote"] = true
	_pending_move = {}
	_play(m)

func _on_promo_canceled() -> void:
	if _pending_move.is_empty():
		return
	var m := _pending_move
	_pending_move = {}
	_play(m)

# --- solving ----------------------------------------------------------------

# Apply a move on the board with the same feedback as the main game.
func _apply(m: Dictionary, cue: String) -> bool:
	var to: Vector2i = Vector2i(m["to"])
	var was_capture: bool = _core.piece_at(to.x, to.y) != null
	if not bool(_core.apply_move(m)):
		return false
	_clear_selection()
	_render()
	var from := Vector2i.ZERO
	if not m.has("drop_kind"):
		from = Vector2i(m["from"])
		var landed = _core.piece_at(to.x, to.y)
		if landed != null:
			_board_view.animate_move(from, to,
				PieceScript.kanji_for(int(landed["kind"]), bool(landed["is_gote"])),
				bool(landed["is_gote"]), Settings.anim(0.22))
	_board_view.show_last_move(from, to)
	if cue == "":
		cue = "capture" if was_capture else "move"
	SoundManager.play(cue)
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(50)
	return true

func _play(m: Dictionary) -> void:
	var epoch := _epoch
	_busy = true
	_plies_left -= 1
	# Judge first (the solver looks at the position after the move), so
	# the move lands with the right sound.
	if not bool(_core.apply_move(m)):
		_busy = false
		_plies_left += 1
		return
	var verdict: Dictionary = _core.tsume_defense(_plies_left)
	_core.undo_move()
	var status := str(verdict["status"])
	_apply(m, "checkmate" if status == "mate" else ("check" if status != "not_check" else ""))
	match status:
		"mate":
			_on_solved()
		"continue":
			_status.text = "…"
			await get_tree().create_timer(REPLY_DELAY_SEC).timeout
			if epoch != _epoch or not is_inside_tree():
				return
			_apply(verdict["reply"], "")
			_plies_left -= 1
			_status.text = "あと%d手で詰みます" % _plies_left
			_busy = false
		_:
			_status.text = ("不正解：王手になっていません" if status == "not_check"
				else "不正解：この手では詰みません")
			_status.add_theme_color_override("font_color", Color(1, 0.55, 0.5, 1))
			await get_tree().create_timer(RESET_DELAY_SEC).timeout
			if epoch != _epoch or not is_inside_tree():
				return
			_restart_problem()

func _on_solved() -> void:
	_solved = true
	_busy = false
	Settings.mark_tsume_solved(_key(str(_problems[_plies][_index]["sfen"])))
	_status.text = "正解！ 詰みです"
	_status.add_theme_color_override("font_color", Color(0.6, 0.95, 0.55, 1))
	_refresh_header()

# ヒント: point at the piece to move (or the hand piece to drop) for the
# first move of a solution from the current position.
func _on_hint() -> void:
	if not _can_input():
		return
	var hint: Variant = _core.tsume_first_move(_plies_left)
	if hint == null:
		_status.text = "この局面からは詰みません。やり直してください"
		return
	_clear_selection()
	var first: Dictionary = hint
	if first.has("drop_kind"):
		_on_hand_tapped(int(first["drop_kind"]))
	else:
		_try_select_board(Vector2i(first["from"]))
	_status.text = "ヒント：この駒を使います"

# --- navigation -------------------------------------------------------------

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
	_epoch += 1
	SceneTransition.go_to("res://scenes/MainMenu.tscn")

func _refit_board() -> void:
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	# header, level row, hands ×2, status, nav, separations + padding
	var reserved: float = 72.0 + 72.0 + 72.0 + 72.0 + 56.0 + 72.0 + 72.0
	var side: float = clamp(min(vw - 40.0, vh - reserved), 240.0, 1600.0)
	_board_view.custom_minimum_size = Vector2(side, side)
