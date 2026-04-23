class_name GameController
extends Control

const PieceScript := preload("res://scripts/game/Piece.gd")
const BoardViewScript := preload("res://scripts/game/BoardView.gd")
const HandViewScript := preload("res://scripts/game/HandView.gd")

@onready var _board_view: BoardViewScript = %BoardView
@onready var _sente_hand: HandViewScript = %SenteHand
@onready var _gote_hand: HandViewScript = %GoteHand
@onready var _status: Label = %StatusLabel
@onready var _check_banner: Label = %CheckBanner
@onready var _promo_dialog: ConfirmationDialog = %PromotionDialog
@onready var _gameover_dialog: AcceptDialog = %GameOverDialog
@onready var _undo_btn: Button = %UndoButton
@onready var _exit_btn: Button = %ExitButton
@onready var _quit_dialog: ConfirmationDialog = %QuitDialog
@onready var _thinking_label: Label = %ThinkingLabel
@onready var _layout: VBoxContainer = $Layout

var _think_thread: Thread
var _thinking: bool = false
var _ai_enabled: bool = false

const _RANK_KANJI := ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

enum SelState { IDLE, BOARD, HAND }

var _core: Object
var _last_move: Dictionary = {}
var _sel_state: int = SelState.IDLE
var _sel_from: Vector2i = Vector2i.ZERO
var _sel_drop_kind: int = -1
var _pending_move: Dictionary = {}
var _game_over: bool = false

func _ready() -> void:
	if not ClassDB.class_exists("ShogiCore"):
		push_error("ShogiCore GDExtension not loaded — check addons/shogi_core.gdextension and native/bin")
		return
	_core = ClassDB.instantiate("ShogiCore")
	_load_ai_if_needed()
	if Settings.resume_sfen != "":
		if not bool(_core.load_sfen(Settings.resume_sfen)):
			push_warning("resume: load_sfen failed; starting fresh. SFEN was: %s" % Settings.resume_sfen)
		Settings.resume_sfen = ""
	_board_view.square_tapped.connect(_on_board_tapped)
	_sente_hand.piece_tapped.connect(_on_hand_tapped.bind(false))
	_gote_hand.piece_tapped.connect(_on_hand_tapped.bind(true))
	_promo_dialog.confirmed.connect(_on_promo_confirmed)
	_promo_dialog.canceled.connect(_on_promo_canceled)
	_promo_dialog.close_requested.connect(_on_promo_canceled)
	_gameover_dialog.confirmed.connect(_on_restart)
	_undo_btn.pressed.connect(_on_undo)
	_exit_btn.pressed.connect(_on_exit_pressed)
	_quit_dialog.confirmed.connect(_on_quit_confirmed)
	_sente_hand.is_gote = false
	_gote_hand.is_gote = true
	get_viewport().size_changed.connect(_refit_board)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_refit_board()
	_refresh_all()
	_maybe_start_ai_turn()

# Board is a square sized to the smaller of (viewport_w - 2*gutter) and the
# vertical slot left after the two hands + status bar. Recomputed on every
# viewport size change so orientation / window-resize / split-screen stay fit.
func _refit_board() -> void:
	const GUTTER := 4.0
	const VERTICAL_RESERVED := 72.0 + 72.0 + 40.0 + 8.0 * 3 + 16.0
	var vp: Vector2 = get_viewport_rect().size
	var side: float = min(vp.x - 2.0 * GUTTER, vp.y - VERTICAL_RESERVED)
	side = clamp(side, 240.0, 1600.0)
	_board_view.custom_minimum_size = Vector2(side, side)

# Inset Layout so GoteHand / StatusBar don't sit under the Android status
# bar, gesture-nav bar, or rounded-corner cutouts. DisplayServer
# safe-area is in screen pixels; scale to Control coordinates via the
# viewport/screen ratio. A fixed extra pad on every edge gives rounded
# corners some breathing room. On desktop the OS-reported safe area is
# the full window so only the fixed pad applies.
func _apply_safe_area() -> void:
	if _layout == null:
		return
	const EXTRA_H := 12.0
	const EXTRA_TOP := 16.0
	const EXTRA_BOTTOM := 32.0
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	var top := EXTRA_TOP
	var bottom := EXTRA_BOTTOM
	var left := EXTRA_H
	var right := EXTRA_H
	if safe.size != Vector2i.ZERO and screen_size != Vector2i.ZERO:
		var vp: Vector2 = get_viewport_rect().size
		var sx: float = vp.x / float(screen_size.x)
		var sy: float = vp.y / float(screen_size.y)
		top += float(safe.position.y) * sy
		left += float(safe.position.x) * sx
		bottom += float(screen_size.y - safe.position.y - safe.size.y) * sy
		right += float(screen_size.x - safe.position.x - safe.size.x) * sx
	_layout.offset_left = left
	_layout.offset_top = top
	_layout.offset_right = -right
	_layout.offset_bottom = -bottom

func _load_ai_if_needed() -> void:
	if Settings.mode == Settings.Mode.H_VS_H:
		_ai_enabled = false
		return
	var abs_path: String = Settings.model_absolute_path()
	if abs_path == "" or not bool(_core.load_model(abs_path)):
		push_error("load_model failed: %s" % abs_path)
		_ai_enabled = false
		return
	_ai_enabled = true

func _maybe_start_ai_turn() -> void:
	if _game_over or _thinking or not _ai_enabled:
		return
	var stm_gote: bool = _core.side_to_move_gote()
	if not Settings.side_is_ai(stm_gote):
		return
	_thinking = true
	_thinking_label.visible = true
	_undo_btn.disabled = true
	_think_thread = Thread.new()
	_think_thread.start(_run_ai_think.bind(Settings.ai_playouts))

func _run_ai_think(playouts: int) -> Variant:
	return _core.think_best_move(playouts)

func _process(_delta: float) -> void:
	if _thinking and _think_thread != null and not _think_thread.is_alive():
		var mv: Variant = _think_thread.wait_to_finish()
		_thinking = false
		_thinking_label.visible = false
		if mv == null:
			push_warning("AI returned no move")
			_refresh_all()
			return
		_commit_move(mv)

func _refresh_all() -> void:
	_board_view.render(_core)
	_sente_hand.render(_core)
	_gote_hand.render(_core)
	var side_gote: bool = _core.side_to_move_gote()
	var mover := "後手" if side_gote else "先手"
	var in_check: bool = _core.is_check()
	_check_banner.visible = in_check and not _game_over
	var ply: int = int(_core.move_log_size()) + 1
	_status.text = "%s の手番 (%d手目)" % [mover, ply]
	_undo_btn.disabled = int(_core.move_log_size()) == 0 or _game_over

func _clear_selection() -> void:
	_sel_state = SelState.IDLE
	_sel_from = Vector2i.ZERO
	_sel_drop_kind = -1
	_board_view.clear_selected()
	_board_view.clear_move_hints()
	_sente_hand.clear_selected_kind()
	_gote_hand.clear_selected_kind()
	_sente_hand.render(_core)
	_gote_hand.render(_core)

func _on_board_tapped(file: int, rank: int) -> void:
	if _game_over or _thinking:
		return
	if _ai_enabled and Settings.side_is_ai(_core.side_to_move_gote()):
		return
	var key := Vector2i(file, rank)
	match _sel_state:
		SelState.IDLE:
			_try_select_board(key)
		SelState.BOARD:
			_handle_board_target(key)
		SelState.HAND:
			_handle_drop_target(key)

func _on_hand_tapped(kind: int, is_gote: bool) -> void:
	if _game_over or _thinking or is_gote != _core.side_to_move_gote():
		return
	if _ai_enabled and Settings.side_is_ai(is_gote):
		return
	_clear_selection()
	var drops: Array = _core.legal_drops(kind)
	if drops.is_empty():
		return
	_sel_state = SelState.HAND
	_sel_drop_kind = kind
	var hv: HandViewScript = _gote_hand if is_gote else _sente_hand
	hv.set_selected_kind(kind)
	hv.render(_core)
	var targets: Array = []
	for m in drops:
		targets.append(Vector2i(m["to"]))
	_board_view.show_move_hints(targets)

func _try_select_board(key: Vector2i) -> void:
	var piece = _core.piece_at(key.x, key.y)
	if piece == null or bool(piece["is_gote"]) != _core.side_to_move_gote():
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
	if tp != null and bool(tp["is_gote"]) == _core.side_to_move_gote():
		_clear_selection()
		_try_select_board(to)
		return
	var moves: Array = _core.legal_moves_from(_sel_from.x, _sel_from.y)
	var candidates: Array = []
	for m in moves:
		if Vector2i(m["to"]) == to:
			candidates.append(m)
	if candidates.is_empty():
		return
	var has_promo := false
	var has_plain := false
	for m in candidates:
		if bool(m.get("promote", false)):
			has_promo = true
		else:
			has_plain = true
	if has_promo and has_plain:
		var plain: Dictionary = {}
		for m in candidates:
			if not bool(m.get("promote", false)):
				plain = m
				break
		_pending_move = plain
		_prompt_promotion()
	else:
		_commit_move(candidates[0])

func _handle_drop_target(to: Vector2i) -> void:
	var tp = _core.piece_at(to.x, to.y)
	if tp != null:
		if bool(tp["is_gote"]) == _core.side_to_move_gote():
			_clear_selection()
			_try_select_board(to)
		return
	var drops: Array = _core.legal_drops(_sel_drop_kind)
	for m in drops:
		if Vector2i(m["to"]) == to:
			_commit_move(m)
			return

func _prompt_promotion() -> void:
	var to: Vector2i = Vector2i(_pending_move["to"])
	_promo_dialog.dialog_text = "%d%s で成りますか?" % [to.x, _RANK_KANJI[to.y]]
	_promo_dialog.popup_centered()

func _on_promo_confirmed() -> void:
	if _pending_move.is_empty():
		return
	var m: Dictionary = _pending_move.duplicate()
	m["promote"] = true
	_pending_move = {}
	_commit_move(m)

func _on_promo_canceled() -> void:
	if _pending_move.is_empty():
		return
	var m := _pending_move
	_pending_move = {}
	_commit_move(m)

func _commit_move(m: Dictionary) -> void:
	var mover := "後手" if _core.side_to_move_gote() else "先手"
	
	# Determine if it's a capture BEFORE applying the move
	var to_pos = m["to"]
	var target_piece = _core.piece_at(int(to_pos.x), int(to_pos.y))
	var is_capture: bool = target_piece != null
	
	if not bool(_core.apply_move(m)):
		print("[game] rejected: %s" % m)
		return
	
	# Sound Logic
	var sm = get_node_or_null("/root/SoundManager")
	if sm:
		if bool(_core.is_checkmate()):
			sm.play("checkmate")
		elif bool(_core.is_check()):
			sm.play("check")
		elif bool(m.get("promote", false)):
			sm.play("promote")
		elif is_capture:
			sm.play("capture")
		else:
			sm.play("move")
	else:
		push_warning("SoundManager not found")

	_log_move(mover, m)
	_last_move = m.duplicate()
	_clear_selection()
	_refresh_all()
	_refresh_last_move_hint()
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(50)
	_check_end_state()
	if not _game_over:
		Settings.save_game(str(_core.to_sfen()))
	_maybe_start_ai_turn()

func _refresh_last_move_hint() -> void:
	if _last_move.is_empty():
		_board_view.clear_last_move()
		return
	var from := Vector2i.ZERO
	if not _last_move.has("drop_kind"):
		from = Vector2i(_last_move["from"])
	_board_view.show_last_move(from, Vector2i(_last_move["to"]))

func _check_end_state() -> void:
	if bool(_core.is_checkmate()):
		var loser := "後手" if _core.side_to_move_gote() else "先手"
		var winner := "先手" if _core.side_to_move_gote() else "後手"
		_end_game("詰み\n%s の勝ち (%s を詰ました)" % [winner, loser])
		return
	match str(_core.detect_sennichite()):
		"draw":
			_end_game("千日手 — 引き分け")
		"sente_loses":
			_end_game("連続王手の千日手 — 後手の勝ち")
		"gote_loses":
			_end_game("連続王手の千日手 — 先手の勝ち")

func _end_game(text: String) -> void:
	_game_over = true
	_check_banner.visible = false
	_undo_btn.disabled = true
	_gameover_dialog.dialog_text = text
	_gameover_dialog.popup_centered()
	Settings.clear_saved_game()
	print("[game] %s" % text.replace("\n", " "))

func _on_restart() -> void:
	_core.reset_starting()
	_game_over = false
	_pending_move = {}
	_last_move = {}
	_clear_selection()
	_refresh_all()
	_refresh_last_move_hint()

func _on_undo() -> void:
	if _game_over:
		return
	if bool(_core.undo_move()):
		# No single-level cache of the move *before* the one we just undid;
		# simplest correct behaviour is to blank the highlight until the
		# next move is committed.
		_last_move = {}
		_clear_selection()
		_refresh_all()
		_refresh_last_move_hint()

func _on_exit_pressed() -> void:
	_quit_dialog.popup_centered()

func _on_quit_confirmed() -> void:
	# Ensure any AI worker thread has finished before tearing down the
	# scene — wait_to_finish on a live thread blocks, but abandoning a
	# JoinHandle leaks.
	if _thinking and _think_thread != null:
		_think_thread.wait_to_finish()
		_thinking = false
	var resigner := _resignation_side()
	var winner := "後手" if resigner == "先手" else "先手"
	print("[game] %s の投了 — %s の勝ち" % [resigner, winner])
	Settings.clear_saved_game()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# Best-effort attribution of who resigned. In AI modes the human is the
# only one who can tap 投了, so we attribute to the human side. In H-v-H
# we attribute to whoever's turn it currently is.
func _resignation_side() -> String:
	if Settings.mode == Settings.Mode.H_VS_AI_GOTE:
		return "先手"
	if Settings.mode == Settings.Mode.H_VS_AI_SENTE:
		return "後手"
	return "後手" if _core.side_to_move_gote() else "先手"

func _log_move(mover: String, m: Dictionary) -> void:
	if m.has("drop_kind"):
		var to: Vector2i = Vector2i(m["to"])
		print("[game] %s %s%s打" % [mover, _square_str(to), PieceScript.KANJI[int(m["drop_kind"])]])
	else:
		var from: Vector2i = Vector2i(m["from"])
		var to2: Vector2i = Vector2i(m["to"])
		var suffix := "成" if bool(m.get("promote", false)) else ""
		print("[game] %s %s→%s%s" % [mover, _square_str(from), _square_str(to2), suffix])

func _square_str(v: Vector2i) -> String:
	return "%d%s" % [v.x, _RANK_KANJI[v.y]]
