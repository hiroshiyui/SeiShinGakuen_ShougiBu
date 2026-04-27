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
@onready var _review_banner: Button = %ReviewBanner
@onready var _history_btn: Button = %HistoryButton
@onready var _history_dialog: Control = %MoveHistoryDialog
@onready var _promo_dialog: ConfirmationDialog = %PromotionDialog
@onready var _gameover_dialog: AcceptDialog = %GameOverDialog
@onready var _undo_btn: Button = %UndoButton
@onready var _exit_btn: Button = %ExitButton
@onready var _quit_dialog: ConfirmationDialog = %QuitDialog
@onready var _thinking_label: Label = %ThinkingLabel
@onready var _layout: VBoxContainer = $Layout
@onready var _opponent_label: Label = %OpponentLabel
@onready var _opponent_strip: HBoxContainer = %OpponentStrip
@onready var _opponent_portrait: TextureRect = %OpponentPortrait
@onready var _opponent_portrait_frame: Control = %OpponentPortraitFrame
@onready var _teacher_row: HBoxContainer = %TeacherRow
@onready var _teacher_btn: Button = %TeacherButton
@onready var _teacher_left_spacer: Control = %LeftSpacer
@onready var _teacher_right_spacer: Control = %RightSpacer
@onready var _suggestions_panel: PanelContainer = %SuggestionsPanel
@onready var _suggestions_list: VBoxContainer = %SuggestionsList
@onready var _close_suggestions_btn: Button = %CloseSuggestionsButton

var _think_thread: Thread
var _teacher_thread: Thread
var _thinking: bool = false
var _teacher_thinking: bool = false
var _ai_enabled: bool = false

const _RANK_KANJI := ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

enum SelState { IDLE, BOARD, HAND }

var _core: Object
# Set to a scratch ShogiCore replaying ply 1..N when the player opens the
# history dialog and taps a row. Read-only — all mutations still target
# `_core`. `_active_core()` picks whichever the views should render from.
var _review_core: Object = null
var _in_review: bool = false
var _last_move: Dictionary = {}
var _sel_state: int = SelState.IDLE
var _sel_from: Vector2i = Vector2i.ZERO
var _sel_drop_kind: int = -1
var _pending_move: Dictionary = {}
var _game_over: bool = false
var _suggestion_preview_from: Vector2i = Vector2i.ZERO
var _suggestion_preview_to: Vector2i = Vector2i.ZERO
var _character: CharacterProfile = null
var _suggestions_tween: Tween = null
var _board_resize_tween: Tween = null
# Set when the player commits a move while the suggestions panel is open.
# The panel fades out immediately but the board stays at its smaller size
# through the AI's reply; once both sides have moved (= it's the player's
# turn again, or the game is over), we tween back to full size.
var _pending_zoom_back: bool = false

const _SUGGESTIONS_FADE := 0.18
# Slower than the panel fade so the shogi-ban zooms back smoothly after a
# move (the player has just committed → suggestions auto-close, then the
# board grows over ~0.8 s, drawing the eye back to the next position).
const _BOARD_RESIZE_DURATION := 0.8

func _ready() -> void:
	if not ClassDB.class_exists("ShogiCore"):
		push_error("ShogiCore GDExtension not loaded — check addons/shogi_core.gdextension and native/bin")
		return
	_core = ClassDB.instantiate("ShogiCore")
	_load_ai_if_needed()
	if not Settings.resume_packed.is_empty():
		# Prefer replay-from-start so the kifu panel + sennichite history
		# rebuild correctly. Falls back to SFEN-load if the packed log
		# doesn't apply cleanly (e.g. a future engine change rejected an
		# older move).
		if not bool(_core.apply_packed(Settings.resume_packed)):
			push_warning("resume: apply_packed failed; falling back to SFEN. SFEN was: %s" % Settings.resume_sfen)
			if Settings.resume_sfen != "" and not bool(_core.load_sfen(Settings.resume_sfen)):
				push_warning("resume: load_sfen also failed; starting fresh.")
		Settings.resume_packed = PackedInt32Array()
		Settings.resume_sfen = ""
	elif Settings.resume_sfen != "":
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
	_history_btn.pressed.connect(_on_history_pressed)
	_history_dialog.ply_selected.connect(_on_history_ply_selected)
	_history_dialog.return_to_live.connect(_on_history_back_to_live)
	_history_dialog.closed.connect(_on_history_closed)
	_review_banner.pressed.connect(_on_history_back_to_live)
	_quit_dialog.confirmed.connect(_on_quit_confirmed)
	_teacher_btn.pressed.connect(_on_teacher_pressed)
	_close_suggestions_btn.pressed.connect(_close_suggestions)
	_apply_teacher_side()
	_teacher_row.visible = _ai_enabled
	_sente_hand.is_gote = false
	_gote_hand.is_gote = true
	get_viewport().size_changed.connect(_refit_board)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_refit_board()
	_refresh_all()
	_maybe_start_ai_turn()

# Board is a square sized to fit within the Layout. The Layout itself is
# inset LAYOUT_H px on each side (from _apply_safe_area's EXTRA_H). Board
# side must be ≤ Layout width or the CenterContainer overflows to the right,
# causing an off-centre shift. Recomputed on every viewport size change.
func _refit_board() -> void:
	_apply_board_side(_compute_board_side(), false)

# Animated variant — tweens custom_minimum_size from current to target so
# the shogi-ban zooms instead of snapping. Used when the suggestions panel
# toggles. `panel_visible_override` lets callers compute the target as if
# the panel had already toggled (the close path needs this since the
# panel is still visible during its fade-out).
func _refit_board_smooth(panel_visible_override: Variant = null) -> void:
	_apply_board_side(_compute_board_side(panel_visible_override), true)

func _compute_board_side(panel_visible_override: Variant = null) -> float:
	const GUTTER := 4.0        # breathing room inside BoardHolder
	const LAYOUT_H := 12.0     # must match EXTRA_H in _apply_safe_area
	# Hands (2×72) + status bar (40) + fixed breathing pad (16). TeacherRow
	# and SuggestionsPanel are measured live since they toggle visibility.
	var base: float = 72.0 + 72.0 + 56.0 + 16.0
	var teacher_visible := _teacher_row != null and _teacher_row.visible
	var panel_visible: bool
	if panel_visible_override == null:
		panel_visible = _suggestions_panel != null and _suggestions_panel.visible
	else:
		panel_visible = bool(panel_visible_override)
	var opponent_visible := _opponent_strip != null and _opponent_strip.visible
	var extras: float = 0.0
	if teacher_visible:
		extras += max(_teacher_row.size.y, _teacher_row.custom_minimum_size.y)
	if panel_visible and _suggestions_panel != null:
		extras += _suggestions_panel.size.y
	if opponent_visible:
		extras += max(_opponent_strip.size.y, _opponent_strip.custom_minimum_size.y)
	# VBox separation (8) between every pair of visible children.
	var visible_items := 4  # GoteHand, Board, SenteHand, StatusBar
	if teacher_visible: visible_items += 1
	if panel_visible: visible_items += 1
	if opponent_visible: visible_items += 1
	var separators: float = 8.0 * max(0, visible_items - 1)
	var vp: Vector2 = get_viewport_rect().size
	var side: float = min(vp.x - 2.0 * (GUTTER + LAYOUT_H), vp.y - base - extras - separators)
	return clamp(side, 240.0, 1600.0)

func _apply_board_side(side: float, animate: bool) -> void:
	if _board_resize_tween != null and _board_resize_tween.is_valid():
		_board_resize_tween.kill()
	var target := Vector2(side, side)
	if not animate:
		_board_view.custom_minimum_size = target
		return
	_board_resize_tween = create_tween()
	_board_resize_tween.set_trans(Tween.TRANS_SINE)
	_board_resize_tween.set_ease(Tween.EASE_OUT)
	_board_resize_tween.tween_property(
		_board_view, "custom_minimum_size", target, _BOARD_RESIZE_DURATION)

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
	# Only apply safe-area insets vertically. In portrait mode phones have
	# no left/right hardware cutouts, and Android sometimes reports a
	# non-zero safe.position.x (gesture navigation, foldable hinge, etc.)
	# that would shift the layout sideways. Horizontal breathing room is
	# handled by the fixed EXTRA_H alone.
	if safe.size != Vector2i.ZERO and screen_size != Vector2i.ZERO:
		var vp: Vector2 = get_viewport_rect().size
		var sy: float = vp.y / float(screen_size.y)
		top += float(safe.position.y) * sy
		bottom += float(screen_size.y - safe.position.y - safe.size.y) * sy
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
	_character = Settings.load_character(Settings.selected_character_id)
	# Prefer the selected character's display name over LEVEL_NAMES so
	# the strip stays in sync with the picker — LEVEL_NAMES is a fallback
	# table for cases where no character was ever picked.
	_opponent_label.text = (_character.display_name if _character != null
		else Settings.level_name(Settings.ai_level))
	_set_opponent_portrait(_character)
	_opponent_strip.visible = true

func _set_opponent_portrait(profile: CharacterProfile) -> void:
	# Hide the avatar slot entirely when there's no portrait — keeps the
	# label centered in the strip instead of showing an empty 64×64 box.
	var tex: Texture2D = null
	if profile != null and profile.portrait_dir != "":
		var path := profile.portrait_dir.path_join("neutral.webp")
		if ResourceLoader.exists(path):
			tex = load(path)
	_opponent_portrait.texture = tex
	_opponent_portrait_frame.visible = tex != null
	# Sync the rounded-corner shader's `size` uniform whenever the rect
	# is laid out — its value is the rendered size in pixels, which the
	# shader needs because TEXTURE_PIXEL_SIZE only describes the source
	# image, not the on-screen rect.
	if tex != null and not _opponent_portrait.resized.is_connected(_sync_portrait_shader_size):
		_opponent_portrait.resized.connect(_sync_portrait_shader_size)
	# Defer the first sync — _set_opponent_portrait runs in _ready,
	# before layout has assigned the rect a size. Calling now would
	# push (0, 0) into the shader and discard every fragment until
	# the first `resized` signal lands. Deferring lets layout settle.
	_sync_portrait_shader_size.call_deferred()

func _sync_portrait_shader_size() -> void:
	var mat := _opponent_portrait.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("size", _opponent_portrait.size)

func _maybe_start_ai_turn() -> void:
	if _game_over or _thinking or not _ai_enabled:
		return
	var stm_gote: bool = _core.side_to_move_gote()
	if not Settings.side_is_ai(stm_gote):
		return
	_thinking = true
	_thinking_label.visible = true
	_undo_btn.disabled = true
	_teacher_btn.disabled = true
	var params: Dictionary = Settings.level_params(Settings.ai_level)
	var playouts: int = int(params["playouts"])
	var temperature: float = float(params["temperature"])
	_think_thread = Thread.new()
	_think_thread.start(_run_ai_think.bind(playouts, temperature))

func _run_ai_think(playouts: int, temperature: float) -> Variant:
	return _core.think_sampled(playouts, temperature)

func _process(_delta: float) -> void:
	if _teacher_thinking and _teacher_thread != null and not _teacher_thread.is_alive():
		_finish_teacher_think()
		return
	if _thinking and _think_thread != null and not _think_thread.is_alive():
		var mv: Variant = _think_thread.wait_to_finish()
		# Clear _thinking immediately so _process won't re-enter this branch
		# while we await the natural-pause timer below. Input is still gated
		# by side-to-move (it's the AI's turn until _commit_move flips it).
		_thinking = false
		_think_thread = null
		if mv == null:
			_thinking_label.visible = false
			push_warning("AI returned no move")
			_refresh_all()
			return
		# Natural pause — avoid the AI snapping a move instantly after a
		# fast search. Keep the 思考中 label up during the delay so the
		# transition reads as continuous deliberation.
		await get_tree().create_timer(randf_range(1.0, 2.0)).timeout
		_thinking_label.visible = false
		if _game_over:
			return
		_commit_move(mv)

func _refresh_all() -> void:
	var view_core: Object = _active_core()
	_board_view.render(view_core)
	_sente_hand.render(view_core)
	_gote_hand.render(view_core)
	var side_gote: bool = view_core.side_to_move_gote()
	var mover := "後手" if side_gote else "先手"
	var in_check: bool = view_core.is_check()
	_check_banner.visible = in_check and not _game_over and not _in_review
	if _in_review:
		var review_ply: int = int(_review_core.move_log_size())
		var live_ply: int = int(_core.move_log_size())
		_status.text = "%d手目 / %d手目 (棋譜閲覧中)" % [review_ply, live_ply]
	else:
		var ply: int = int(_core.move_log_size()) + 1
		_status.text = "%s の手番 (%d手目)" % [mover, ply]
	_undo_btn.disabled = int(_core.move_log_size()) == 0 or _game_over or _in_review
	_history_btn.disabled = int(_core.move_log_size()) == 0
	var ai_turn := _ai_enabled and Settings.side_is_ai(side_gote)
	_teacher_btn.disabled = _game_over or _thinking or ai_turn or not _ai_enabled or _in_review

func _active_core() -> Object:
	return _review_core if _in_review and _review_core != null else _core

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
	if _game_over or _thinking or _in_review:
		return
	if _ai_enabled and Settings.side_is_ai(_core.side_to_move_gote()):
		return
	_clear_suggestion_preview()
	var key := Vector2i(file, rank)
	match _sel_state:
		SelState.IDLE:
			_try_select_board(key)
		SelState.BOARD:
			_handle_board_target(key)
		SelState.HAND:
			_handle_drop_target(key)

func _on_hand_tapped(kind: int, is_gote: bool) -> void:
	if _game_over or _thinking or _in_review or is_gote != _core.side_to_move_gote():
		return
	if _ai_enabled and Settings.side_is_ai(is_gote):
		return
	_clear_suggestion_preview()
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
	if _suggestions_panel.visible:
		# Defer the board zoom-back: panel fades out now, but the board
		# stays at its smaller size until the opponent has also replied.
		_close_suggestions(false)
		_pending_zoom_back = true
	_refresh_all()
	_refresh_last_move_hint()
	# Slide the piece from its origin square to the destination. Drops come
	# from the hand, not a board square, so we skip the animation there.
	if not m.has("drop_kind"):
		var from_key: Vector2i = Vector2i(m["from"])
		var to_key: Vector2i = Vector2i(m["to"])
		var landed = _core.piece_at(to_key.x, to_key.y)
		if landed != null:
			var text := PieceScript.kanji_for(int(landed["kind"]), bool(landed["is_gote"]))
			_board_view.animate_move(from_key, to_key, text, bool(landed["is_gote"]))
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(50)
	_check_end_state()
	# If the player committed a move while suggestions were open, the
	# board has been held small through this turn. Once it's the player's
	# turn again (= AI has replied) — or the game ended — zoom back.
	if _pending_zoom_back and (_game_over or not Settings.side_is_ai(_core.side_to_move_gote())):
		_pending_zoom_back = false
		_zoom_back_after_slide()
	if not _game_over:
		Settings.save_game(str(_core.to_sfen()), _core.move_log_packed())
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

# Esc on desktop / Android back button-or-swipe (both map to ui_cancel by
# default) closes the suggestions panel if it's open, otherwise leaves
# the game and returns to the main menu. The board is auto-saved after
# every move so 続きから will pick up where the player left off.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _suggestions_panel.visible:
		_close_suggestions()
	else:
		_back_to_title()
	get_viewport().set_input_as_handled()

func _back_to_title() -> void:
	# Drain any live worker threads so we don't leak join handles when the
	# scene tears down (same rationale as _on_quit_confirmed).
	if _thinking and _think_thread != null and _think_thread.is_alive():
		_think_thread.wait_to_finish()
	if _teacher_thinking and _teacher_thread != null and _teacher_thread.is_alive():
		_teacher_thread.wait_to_finish()
	_thinking = false
	_teacher_thinking = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

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

# --- 先生モード (teacher mode) ---------------------------------------------

func _apply_teacher_side() -> void:
	# Both spacers carry size_flags_horizontal=3; disabling the expand
	# flag on one side pushes the button there.
	var right: bool = Settings.teacher_side == "right"
	_teacher_left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL if right else 0
	_teacher_right_spacer.size_flags_horizontal = 0 if right else Control.SIZE_EXPAND_FILL

func _on_teacher_pressed() -> void:
	if _game_over or _thinking or _teacher_thinking or not _ai_enabled:
		return
	if Settings.side_is_ai(_core.side_to_move_gote()):
		return
	_clear_selection()
	_clear_suggestion_preview()
	# Reuse _thinking to block board/hand input while the search runs —
	# both threads mutate the shared _core board state (apply/undo during
	# playouts) so the main thread must not touch it concurrently.
	_thinking = true
	_teacher_thinking = true
	_thinking_label.text = "先生が考え中..."
	_thinking_label.visible = true
	_undo_btn.disabled = true
	_teacher_btn.disabled = true
	var playouts: int = int(Settings.level_params(Settings.ai_level)["playouts"])
	_teacher_thread = Thread.new()
	_teacher_thread.start(_run_teacher_think.bind(playouts))

func _run_teacher_think(playouts: int) -> Variant:
	return _core.suggest_moves_mcts(3, playouts)

func _finish_teacher_think() -> void:
	var result: Variant = _teacher_thread.wait_to_finish()
	_teacher_thread = null
	_teacher_thinking = false
	_thinking = false
	_thinking_label.visible = false
	_thinking_label.text = "思考中…"
	# Resync the UI with the authoritative Rust state. If the main thread
	# ever touched `_core` while the worker held `&mut self` (a deferred
	# signal, a resize callback, etc.), godot-rust may have returned default
	# values that left HandView / BoardView stale — forcing a render now
	# guarantees we match the real board.
	_refresh_all()
	var suggestions: Array = result if result is Array else []
	if suggestions.is_empty():
		_status.text = "先生: 有効な手が見つかりません"
		return
	_populate_suggestions(suggestions)

func _populate_suggestions(suggestions: Array) -> void:
	for child in _suggestions_list.get_children():
		child.queue_free()
	for m in suggestions:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 36)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 22)
		btn.text = _format_suggestion(m)
		btn.pressed.connect(_on_suggestion_tapped.bind(m))
		_suggestions_list.add_child(btn)
	_show_suggestions_panel()

# Fade the panel in and zoom the board to its smaller size in parallel.
# The panel is flipped to visible at alpha=0 so the VBox reserves space
# for it before we start the alpha tween. The board-resize tween is
# deferred so the panel has a frame to lay out — only then is its real
# size.y available for the target calculation.
func _show_suggestions_panel() -> void:
	if _suggestions_tween != null and _suggestions_tween.is_valid():
		_suggestions_tween.kill()
	_suggestions_panel.modulate.a = 0.0
	_suggestions_panel.visible = true
	_refit_board_smooth.bind(true).call_deferred()
	_suggestions_tween = create_tween()
	_suggestions_tween.tween_property(
		_suggestions_panel, "modulate:a", 1.0, _SUGGESTIONS_FADE)

func _format_suggestion(m: Dictionary) -> String:
	var win_rate: float = float(m.get("win_rate", m.get("score", 0.0)))
	var pct := int(round(win_rate * 100.0))
	var notation: String
	var to: Vector2i = Vector2i(m["to"])
	if m.has("drop_kind"):
		notation = "%s%s打" % [_square_str(to), PieceScript.KANJI[int(m["drop_kind"])]]
	else:
		var from: Vector2i = Vector2i(m["from"])
		var piece = _core.piece_at(from.x, from.y)
		var kanji := ""
		if piece != null:
			kanji = PieceScript.kanji_for(int(piece["kind"]), bool(piece["is_gote"]))
		var suffix := "成" if bool(m.get("promote", false)) else ""
		notation = "%s%s → %s%s" % [_square_str(from), kanji, _square_str(to), suffix]
	return "%s  勝率%d%%" % [notation, pct]

func _on_suggestion_tapped(m: Dictionary) -> void:
	# Preview only — highlight from/to on the board without committing.
	# Tapping any square (board or hand) clears the preview via
	# _clear_suggestion_preview calls in the existing flow.
	_clear_suggestion_preview()
	var to: Vector2i = Vector2i(m["to"])
	var from: Vector2i = Vector2i.ZERO
	if not m.has("drop_kind"):
		from = Vector2i(m["from"])
	_suggestion_preview_from = from
	_suggestion_preview_to = to
	var hints: Array = []
	if from != Vector2i.ZERO:
		hints.append(from)
	hints.append(to)
	_board_view.show_move_hints(hints)

func _clear_suggestion_preview() -> void:
	if _suggestion_preview_from == Vector2i.ZERO and _suggestion_preview_to == Vector2i.ZERO:
		return
	_suggestion_preview_from = Vector2i.ZERO
	_suggestion_preview_to = Vector2i.ZERO
	_board_view.clear_move_hints()

func _close_suggestions(animate_board: bool = true) -> void:
	_clear_suggestion_preview()
	if not _suggestions_panel.visible:
		return
	if _suggestions_tween != null and _suggestions_tween.is_valid():
		_suggestions_tween.kill()
	_suggestions_tween = create_tween()
	_suggestions_tween.tween_property(
		_suggestions_panel, "modulate:a", 0.0, _SUGGESTIONS_FADE)
	_suggestions_tween.tween_callback(_finalize_close_suggestions)
	# Run the board zoom AFTER the panel is fully hidden. Tweening the
	# board's custom_minimum_size while the panel still occupies its VBox
	# slot makes the layout reflow every frame — visually "clicky". Once
	# the panel's `visible = false`, the slot is freed and the board can
	# grow into it cleanly. Callers that follow with a real move (commit
	# path) skip this and rely on the deferred zoom-back instead.
	if animate_board:
		_suggestions_tween.tween_callback(_refit_board_smooth)

func _finalize_close_suggestions() -> void:
	_suggestions_panel.visible = false
	_suggestions_panel.modulate.a = 1.0

# Wait for the piece-slide animation in BoardView.animate_move (~0.22 s)
# to land before tweening the board size — otherwise the slide and the
# zoom compete for attention. Called fire-and-forget from _commit_move;
# the body resumes when the timer fires.
func _zoom_back_after_slide() -> void:
	await get_tree().create_timer(0.28).timeout
	if not is_inside_tree():
		return
	_refit_board_smooth()

# --- 棋譜 history dialog ---------------------------------------------------

func _on_history_pressed() -> void:
	var lines: PackedStringArray = _core.move_log_kifu_lines()
	# Highlight the row matching whatever ply is currently visible — the
	# live tip if not in review, or the rewound ply if reopened mid-review.
	var ply: int = int(_review_core.move_log_size()) if _in_review and _review_core != null else int(_core.move_log_size())
	_history_dialog.show_with(lines, ply)

# Build a scratch core, replay ply 1..N from the live log, and swap the
# views over to it. _active_core() now returns the scratch — interactive
# inputs are gated by _in_review and refuse to fire.
func _on_history_ply_selected(ply: int) -> void:
	var packed: PackedInt32Array = _core.move_log_packed()
	var clamped: int = clamp(ply, 0, packed.size())
	var prefix: PackedInt32Array = packed.slice(0, clamped)
	if _review_core == null:
		_review_core = ClassDB.instantiate("ShogiCore")
	if not bool(_review_core.apply_packed(prefix)):
		push_warning("history: apply_packed failed for ply %d" % clamped)
		return
	_in_review = true
	_review_banner.visible = true
	# Hide stale highlights from the live game while reviewing.
	_board_view.clear_selected()
	_board_view.clear_move_hints()
	_refresh_all()

func _on_history_back_to_live() -> void:
	_exit_review()

func _on_history_closed() -> void:
	# Closing without explicitly tapping 現在に戻る still drops the user back
	# to the live position — leaving them stranded in scrub-mode after a
	# stray tap on 閉じる would be a footgun.
	if _in_review:
		_exit_review()

func _exit_review() -> void:
	_in_review = false
	_review_core = null
	_review_banner.visible = false
	_refresh_all()
