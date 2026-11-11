class_name GameController
extends Control

const PieceScript := preload("res://scripts/game/Piece.gd")
const Analyzer := preload("res://scripts/KifuAnalyzer.gd")
const BoardViewScript := preload("res://scripts/game/BoardView.gd")
const HandViewScript := preload("res://scripts/game/HandView.gd")

@onready var _board_view: BoardViewScript = %BoardView
@onready var _sente_hand: HandViewScript = %SenteHand
@onready var _gote_hand: HandViewScript = %GoteHand
@onready var _status: Label = %StatusLabel
@onready var _review_banner: Button = %ReviewBanner
@onready var _history_btn: Button = %HistoryButton
@onready var _history_dialog: Control = %MoveHistoryDialog
@onready var _promo_dialog: ConfirmationDialog = %PromotionDialog
@onready var _gameover_dialog: AcceptDialog = %GameOverDialog
var _gameover_text: String = ""
# KIF closing line for the finished game ("" while in progress → 中断).
var _gameover_terminator: String = ""
# Guards the per-character record against counting one game twice.
var _result_recorded: bool = false
# True when this game continued a save, even one with no move log.
var _resumed: bool = false
@onready var _speech_bubble: PanelContainer = %OpponentSpeech
@onready var _speech_label: Label = %OpponentSpeechText
var _speech_tween: Tween = null
const SPEECH_HOLD_SEC := 3.5
const SPEECH_FADE_SEC := 0.25
@onready var _undo_btn: Button = %UndoButton
@onready var _exit_btn: Button = %ExitButton
@onready var _jishogi_btn: Button = %JishogiButton
@onready var _jishogi_info_dialog: AcceptDialog = %JishogiInfoDialog
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
# Opponent portrait expressions (see CharacterProfile.portrait_dir).
# The AI looks happy / worried when the search rates its own move above
# / below these win rates, and neutral in between.
const EXPR_HAPPY_WIN_RATE := 0.62
const EXPR_WORRIED_WIN_RATE := 0.38
var _expression: String = "neutral"
var _expression_textures: Dictionary = {}
# Copy of the portrait node that holds the outgoing face on top while it
# fades out, giving a cross-fade between expressions.
const EXPR_FADE_SEC := 0.25
# The search's rating of a single move is noisy at the low playout
# counts weak characters use, so the mood follows a running blend of it
# rather than each raw value (weight of the newest move).
const EXPR_WIN_RATE_BLEND := 0.6
var _mood_win_rate: float = -1.0
# How long the opponent's flinch at a strong player move (check, or
# losing a 飛 / 角) stays up before the thinking face takes over.
const EXPR_REACTION_SEC := 0.9
const EXPR_MAJOR_KINDS := [
	PieceScript.Kind.ROOK, PieceScript.Kind.BISHOP,
	PieceScript.Kind.DRAGON, PieceScript.Kind.HORSE,
]
var _reaction_until_msec: int = 0
# Large portrait + text shown inside the 対局終了 dialog (the modal blur
# hides the avatar strip behind it).
var _gameover_portrait: TextureRect = null
var _gameover_label: Label = null
# 加藤先生's post-game comment (ROADMAP "post-game comment"). While the
# game runs, each AI search leaves the AI's own win rate here, keyed by
# the move number of that AI move. A sharp rise between two of them
# points at the player move in between; at game end the few sharpest
# candidates get a proper analysis on a worker thread and the worst
# becomes the comment. A whole-game analysis would take a minute or
# more on a phone, far too long for a dialog.
const COMMENT_MAX_CANDIDATES := 3
const COMMENT_MIN_JUMP := 0.08
var _ai_evals: Dictionary = {}
var _gameover_comment: Label = null
var _gameover_review_btn: Button = null
var _gameover_kif_path: String = ""
var _comment_thread: Thread = null
var _comment_cancel: bool = false
var _comment_ply: int = -1
var _portrait_fade: TextureRect = null
var _portrait_fade_tween: Tween = null
var _teacher_thread: Thread
var _thinking: bool = false
var _teacher_thinking: bool = false
var _ai_enabled: bool = false
# 通信対戦 (ROADMAP Phase 8): the other side is a person on another device,
# reached through the NetSession autoload. `_lan_waiting` is true while
# the connection is down and NetSession is trying to restore it.
var _lan: bool = false
var _lan_waiting: bool = false
# After a LAN game: whether 再戦 can still be offered (false once the
# peer has left or the session broke), and the status line meanwhile.
var _rematch_ok: bool = false
var _rematch_status: String = ""


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
	_lan = NetSession.in_game
	_load_ai_if_needed()
	_resumed = not Settings.resume_packed.is_empty() or Settings.resume_sfen != ""
	if not Settings.resume_packed.is_empty():
		# Prefer replay-from-start so the kifu panel + sennichite history
		# rebuild correctly. Falls back to SFEN-load if the packed log
		# doesn't apply cleanly (e.g. a future engine change rejected an
		# older move).
		if not bool(_core.apply_packed(Settings.resume_packed)):
			push_warning("resume: apply_packed failed; falling back to SFEN. SFEN was: %s" % Settings.resume_sfen)
			if Settings.resume_sfen != "" and not bool(_core.load_sfen(Settings.resume_sfen)):
				push_warning("resume: load_sfen also failed; starting fresh.")
				_core.reset_starting()
				_resumed = false
			elif Settings.resume_sfen == "":
				_core.reset_starting()
				_resumed = false
		Settings.resume_packed = PackedInt32Array()
		Settings.resume_sfen = ""
	elif Settings.resume_sfen != "":
		if not bool(_core.load_sfen(Settings.resume_sfen)):
			push_warning("resume: load_sfen failed; starting fresh. SFEN was: %s" % Settings.resume_sfen)
		Settings.resume_sfen = ""
	_board_view.square_tapped.connect(_on_board_tapped)
	# Each hand panel reports the side it currently shows, which swaps
	# when the board is flipped (see _apply_board_orientation).
	_sente_hand.piece_tapped.connect(func(kind: int): _on_hand_tapped(kind, _sente_hand.is_gote))
	_gote_hand.piece_tapped.connect(func(kind: int): _on_hand_tapped(kind, _gote_hand.is_gote))
	_promo_dialog.confirmed.connect(_on_promo_confirmed)
	_promo_dialog.canceled.connect(_on_promo_canceled)
	_promo_dialog.close_requested.connect(_on_promo_canceled)
	_gameover_dialog.confirmed.connect(_on_restart)
	# The built-in close X is hidden via theme (small hitbox + tricky to
	# tap on mobile). Give players a clear way to dismiss the post-game
	# dialog without re-matching by adding a sibling cancel button.
	_gameover_dialog.add_cancel_button("閉じる")
	# The auto-saved KIF path line can be ~90 chars on Android; wrap it
	# instead of letting the dialog grow past the 720 px viewport.
	# The dialog's own label stays empty; a custom column carries the
	# opponent's victory / defeat portrait above the result text.
	var gameover_box := VBoxContainer.new()
	gameover_box.add_theme_constant_override("separation", 16)
	_gameover_portrait = TextureRect.new()
	_gameover_portrait.custom_minimum_size = Vector2(220, 220)
	_gameover_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_gameover_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_gameover_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_gameover_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gameover_portrait.visible = false
	var round_mat := (_opponent_portrait.material as ShaderMaterial).duplicate() as ShaderMaterial
	round_mat.set_shader_parameter("size", _gameover_portrait.custom_minimum_size)
	round_mat.set_shader_parameter("radius", 12.0)
	_gameover_portrait.material = round_mat
	gameover_box.add_child(_gameover_portrait)
	_gameover_label = Label.new()
	_gameover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gameover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gameover_label.custom_minimum_size.x = 560
	gameover_box.add_child(_gameover_label)
	_gameover_comment = Label.new()
	_gameover_comment.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gameover_comment.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Room for three lines up front so the dialog doesn't jump when the
	# comment arrives.
	_gameover_comment.custom_minimum_size = Vector2(560, 96)
	_gameover_comment.add_theme_color_override("font_color", Color(0.98, 0.85, 0.45, 1))
	_gameover_comment.visible = false
	gameover_box.add_child(_gameover_comment)
	_gameover_review_btn = _gameover_dialog.add_button("検討", false, "review")
	_gameover_review_btn.visible = false
	_gameover_dialog.custom_action.connect(_on_gameover_action)
	_gameover_dialog.add_child(gameover_box)
	for d: Window in [_promo_dialog, _gameover_dialog, _quit_dialog, _jishogi_info_dialog]:
		ModalBlur.attach(d)
	_undo_btn.pressed.connect(_on_undo)
	_exit_btn.pressed.connect(_on_exit_pressed)
	_jishogi_btn.pressed.connect(_on_jishogi_pressed)
	_history_btn.pressed.connect(_on_history_pressed)
	_history_dialog.ply_selected.connect(_on_history_ply_selected)
	_history_dialog.return_to_live.connect(_on_history_back_to_live)
	_history_dialog.closed.connect(_on_history_closed)
	_history_dialog.share_requested.connect(_on_history_share_requested)
	_review_banner.pressed.connect(_on_history_back_to_live)
	_quit_dialog.confirmed.connect(_on_quit_confirmed)
	_teacher_btn.pressed.connect(_on_teacher_pressed)
	_close_suggestions_btn.pressed.connect(_close_suggestions)
	_apply_teacher_side()
	_teacher_row.visible = _ai_enabled
	if _lan:
		_setup_lan()
	_apply_board_orientation()
	get_viewport().size_changed.connect(_refit_board)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_refit_board()
	_refresh_all()
	if not _resumed:
		_say("start")
	if Settings.mode != Settings.Mode.H_VS_H and not _ai_enabled and not _lan:
		_show_ai_load_error.call_deferred()
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
	# Hands (2×72) + status bar (72, ≈41 dp tap height) + fixed breathing
	# pad (16). TeacherRow and SuggestionsPanel are measured live since
	# they toggle visibility.
	var base: float = 72.0 + 72.0 + 72.0 + 16.0
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
	if not animate or Settings.reduce_motion:
		_board_view.custom_minimum_size = target
		_place_thinking_label.call_deferred()
		return
	_board_resize_tween = create_tween()
	_board_resize_tween.set_trans(Tween.TRANS_SINE)
	_board_resize_tween.set_ease(Tween.EASE_OUT)
	_board_resize_tween.tween_property(
		_board_view, "custom_minimum_size", target, _BOARD_RESIZE_DURATION)
	_board_resize_tween.tween_callback(_place_thinking_label)

# The 王手 banner is a root-level overlay (so it never perturbs the VBox)
# but is positioned relative to the board: centred horizontally, sitting
# just above the shogi-ban's top edge. Anchoring it to the screen top put
# it under the front-camera cutout on devices like the Pixel 8a.
# ThinkingLabel follows the same scheme, right-aligned to the board's
# top-right corner so it never collides with the StatusBar buttons.
func _place_thinking_label() -> void:
	if _board_view == null:
		return
	var board_rect: Rect2 = _board_view.visual_global_rect()
	if _thinking_label.visible:
		_place_above_board(_thinking_label, board_rect, HORIZONTAL_ALIGNMENT_RIGHT)

# Shrink `node` to its content size (so the alignment edge is the text's
# real edge, not a stale/oversized box) and park it just above the
# board, flush to the requested edge. Using get_combined_minimum_size()
# instead of `size` matters because this runs via call_deferred right
# after a text/visibility change, before the Control has re-laid out.
func _place_above_board(node: Control, board_rect: Rect2, align: int) -> void:
	const GAP := 4.0
	var sz: Vector2 = node.get_combined_minimum_size()
	node.size = sz
	var x: float
	match align:
		HORIZONTAL_ALIGNMENT_LEFT:
			x = board_rect.position.x
		HORIZONTAL_ALIGNMENT_RIGHT:
			x = board_rect.end.x - sz.x
		_:
			x = board_rect.position.x + (board_rect.size.x - sz.x) * 0.5
	node.global_position = Vector2(x, board_rect.position.y - sz.y - GAP)

# Inset Layout so GoteHand / StatusBar don't sit under the Android
# status bar, gesture-nav bar, or rounded-corner cutouts. The math
# (DisplayServer safe-area scaled to Control coordinates + a fixed
# extra pad) lives in Settings.apply_safe_area_to / safe_area_insets,
# shared with KifuLibrary / KifuReviewer.
func _apply_safe_area() -> void:
	Settings.apply_safe_area_to(_layout)
	# ReviewBanner is a root-level overlay outside Layout, so it must
	# honour the status-bar / camera-cutout inset itself.
	var insets: Rect2 = Settings.safe_area_insets(get_viewport_rect().size)
	const BANNER_H := 56.0
	_review_banner.offset_top = insets.position.y
	_review_banner.offset_bottom = insets.position.y + BANNER_H

func _load_ai_if_needed() -> void:
	if Settings.mode == Settings.Mode.H_VS_H or _lan:
		_ai_enabled = false
		return
	var abs_path: String = Settings.model_absolute_path()
	if abs_path == "" or not bool(_core.load_model(abs_path)):
		push_error("load_model failed: %s" % abs_path)
		_ai_enabled = false
		return
	_ai_enabled = true
	# Load the opening book once. Small JSON, FileAccess works on
	# Android; failure is non-fatal — the AI just always thinks via MCTS.
	_load_opening_book()
	_character = Settings.load_character(Settings.selected_character_id)
	# Prefer the selected character's display name over LEVEL_NAMES so
	# the strip stays in sync with the picker — LEVEL_NAMES is a fallback
	# table for cases where no character was ever picked.
	_opponent_label.text = (_character.display_name if _character != null
		else Settings.level_name(Settings.ai_level))
	_set_opponent_portrait(_character)
	_opponent_strip.visible = true

func _show_ai_load_error() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "AI エラー"
	dialog.dialog_text = "AI の読み込みに失敗しました。\n人対人で続行します。"
	add_child(dialog)
	ModalBlur.attach(dialog)
	dialog.popup_centered()

func _load_opening_book() -> void:
	const BOOK_PATH := "res://assets/opening_book.json"
	if not ResourceLoader.exists(BOOK_PATH) and not FileAccess.file_exists(BOOK_PATH):
		# Optional asset — nothing shipped means MCTS-only behaviour,
		# which is the same as before the book existed.
		return
	var f := FileAccess.open(BOOK_PATH, FileAccess.READ)
	if f == null:
		push_warning("opening book: cannot open %s (%d)" % [BOOK_PATH, FileAccess.get_open_error()])
		return
	var json := f.get_as_text()
	f.close()
	if not bool(_core.load_opening_book_json(json)):
		push_warning("opening book: parse failed")
		return
	print("[ai] opening book loaded — %d positions" % int(_core.opening_book_size()))

func _set_opponent_portrait(profile: CharacterProfile) -> void:
	# Hide the avatar slot entirely when there's no portrait — keeps the
	# label centered in the strip instead of showing an empty 96×96 box.
	_expression_textures.clear()
	_expression = "neutral"
	var tex: Texture2D = _expression_texture("neutral")
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

# Portrait for `expr` (neutral / thinking / happy / worried / victory /
# defeat), cached per game. Characters without that variant fall back
# to their neutral portrait; null when there is no portrait at all.
func _expression_texture(expr: String) -> Texture2D:
	if _expression_textures.has(expr):
		return _expression_textures[expr]
	var tex: Texture2D = null
	if _character != null and _character.portrait_dir != "":
		var path := _character.portrait_dir.path_join("%s.webp" % expr)
		if ResourceLoader.exists(path):
			tex = load(path)
		elif expr != "neutral":
			tex = _expression_texture("neutral")
	_expression_textures[expr] = tex
	return tex

func _set_opponent_expression(expr: String) -> void:
	if expr == _expression or not _ai_enabled:
		return
	var tex := _expression_texture(expr)
	if tex == null:
		return
	_expression = expr
	_crossfade_portrait(tex)

# Swap the avatar to `tex` with a short cross-fade: the old face stays
# on an overlay copy and fades out over the new one. Instant when
# アニメーションを減らす is on.
func _crossfade_portrait(tex: Texture2D) -> void:
	var old_tex := _opponent_portrait.texture
	_opponent_portrait.texture = tex
	var duration: float = Settings.anim(EXPR_FADE_SEC)
	if old_tex == null or old_tex == tex or duration <= 0.0:
		return
	if _portrait_fade == null:
		# Same material instance, so the rounded-corner shader's `size`
		# uniform stays in sync with the real portrait.
		_portrait_fade = _opponent_portrait.duplicate() as TextureRect
		_portrait_fade.unique_name_in_owner = false
		_portrait_fade.name = "OpponentPortraitFade"
		_opponent_portrait_frame.add_child(_portrait_fade)
	if _portrait_fade_tween != null and _portrait_fade_tween.is_valid():
		_portrait_fade_tween.kill()
	_portrait_fade.texture = old_tex
	_portrait_fade.modulate.a = 1.0
	_portrait_fade.visible = true
	_portrait_fade_tween = create_tween()
	_portrait_fade_tween.tween_property(_portrait_fade, "modulate:a", 0.0, duration)
	_portrait_fade_tween.tween_callback(_portrait_fade.hide)

# Expression after the AI has moved, from how the search rated that
# move. `win_rate` < 0 means unknown (opening-book move) → neutral.
func _expression_for_win_rate(win_rate: float) -> String:
	if win_rate < 0.0:
		return "neutral"
	if win_rate >= EXPR_HAPPY_WIN_RATE:
		return "happy"
	if win_rate <= EXPR_WORRIED_WIN_RATE:
		return "worried"
	return "neutral"

# Face after an AI move: the running mood, lifted to happy when the
# move it just played gives check and it isn't already in trouble.
func _expression_after_ai_move(win_rate: float) -> String:
	if win_rate >= 0.0:
		_mood_win_rate = win_rate if _mood_win_rate < 0.0 \
			else lerpf(_mood_win_rate, win_rate, EXPR_WIN_RATE_BLEND)
	var expr := _expression_for_win_rate(_mood_win_rate if win_rate >= 0.0 else -1.0)
	if expr == "neutral" and bool(_core.is_check()):
		expr = "happy"
	return expr

# Flinch at a strong move by the player, held briefly before the
# thinking face replaces it.
func _react_to_player_move(gives_check: bool, captured_kind: int) -> void:
	if not (gives_check or captured_kind in EXPR_MAJOR_KINDS):
		return
	_set_opponent_expression("worried")
	_reaction_until_msec = Time.get_ticks_msec() + int(EXPR_REACTION_SEC * 1000.0)
	await get_tree().create_timer(EXPR_REACTION_SEC).timeout
	if is_inside_tree() and _thinking and not _game_over:
		_set_opponent_expression("thinking")

# Thinking face for the AI's turn, unless a flinch is still showing (its
# timer switches to thinking when it runs out).
func _show_thinking_expression() -> void:
	if Time.get_ticks_msec() >= _reaction_until_msec:
		_set_opponent_expression("thinking")

# Game-over face for `winner` ("先手" / "後手", "" on a draw): victory
# or defeat from the AI's side, neutral for a draw.
func _expression_for_winner(winner: String) -> String:
	if winner == "":
		return "neutral"
	return "victory" if (winner == "後手") == Settings.ai_plays_gote() else "defeat"

# Shows one of the opponent's lines beside their portrait, then fades it.
func _say(moment: String) -> void:
	if not _ai_enabled or _character == null:
		return
	var line := _character.random_line(moment)
	if line == "":
		return
	_hide_speech()
	_speech_label.text = line
	_speech_bubble.modulate.a = 1.0
	_speech_tween = create_tween()
	_speech_tween.tween_interval(SPEECH_HOLD_SEC)
	_speech_tween.tween_property(_speech_bubble, "modulate:a", 0.0, Settings.anim(SPEECH_FADE_SEC))

func _hide_speech() -> void:
	if _speech_tween != null and _speech_tween.is_valid():
		_speech_tween.kill()
	_speech_bubble.modulate.a = 0.0

# Parks the balloon just below the portrait, over the 持ち駒 row, with
# its tail on the portrait's centre. Runs every frame while it shows, so
# it follows layout changes and resizes to the current line.
func _place_speech_bubble() -> void:
	const EDGE := 12.0
	var frame: Rect2 = _opponent_portrait_frame.get_global_rect()
	var sz: Vector2 = _speech_bubble.get_combined_minimum_size()
	var center_x: float = frame.get_center().x
	var x: float = clampf(center_x - sz.x * 0.5, EDGE,
		maxf(EDGE, get_viewport_rect().size.x - sz.x - EDGE))
	_speech_bubble.size = sz
	_speech_bubble.global_position = Vector2(x, frame.end.y + _speech_bubble.TAIL_LENGTH)
	_speech_bubble.set_tail_x(center_x - x)

# The opponent's closing line for the 対局終了 dialog; "" on a draw.
func _result_speech(result_expr: String) -> String:
	if not _ai_enabled or _character == null or result_expr == "neutral":
		return ""
	var line := _character.random_line("win" if result_expr == "victory" else "lose")
	return "" if line == "" else "%s「%s」" % [_character.display_name, line]

# Adds a finished game to the opponent's win/loss record. Draws and
# games with no moves don't count.
func _record_character_result(winner: String) -> void:
	if not _ai_enabled or _result_recorded:
		return
	if int(_core.move_log_size()) == 0 and not _resumed:
		return
	var expr := _expression_for_winner(winner)
	if expr == "neutral":
		return
	_result_recorded = true
	Settings.record_character_result(Settings.selected_character_id, expr == "defeat")

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
	# Rolled fresh each move so a character's "mood" can vary turn to
	# turn (see CharacterProfile.moods).
	var params: Dictionary = Settings.ai_dials()
	var temperature: float = float(params["temperature"])
	# Try the opening book first — for known positions this skips the
	# ~150 ms MCTS search entirely and gives the AI varied openings
	# without the policy net's bias toward a single line. `null` =
	# position not in book → fall through to MCTS as before.
	var book_move: Variant = _core.opening_book_pick(temperature)
	if book_move != null:
		_thinking = true  # so _refresh_all disables player input
		_thinking_label.visible = true
		_place_thinking_label.call_deferred()
		_undo_btn.disabled = true
		_teacher_btn.disabled = true
		_history_btn.disabled = true
		_show_thinking_expression()
		_run_book_move_with_pause(book_move)
		return
	_thinking = true
	_thinking_label.visible = true
	_show_thinking_expression()
	_place_thinking_label.call_deferred()
	_undo_btn.disabled = true
	_teacher_btn.disabled = true
	_history_btn.disabled = true
	var playouts: int = int(params["playouts"])
	_think_thread = Thread.new()
	_think_thread.start(_run_ai_think.bind(playouts, temperature))

# Same natural-pause delay the MCTS path uses so a book-driven move
# doesn't snap onto the board instantly while the human is still
# absorbing their last move.
func _run_book_move_with_pause(mv: Dictionary) -> void:
	await get_tree().create_timer(randf_range(0.6, 1.4)).timeout
	if not is_inside_tree() or _game_over:
		return
	_thinking = false
	_thinking_label.visible = false
	_commit_move(mv)
	if not _game_over:
		_set_opponent_expression("neutral")

func _run_ai_think(playouts: int, temperature: float) -> Variant:
	return _core.think_sampled(playouts, temperature)

func _process(_delta: float) -> void:
	if _speech_bubble.modulate.a > 0.0:
		_place_speech_bubble()
	if _comment_thread != null and not _comment_thread.is_alive():
		_finish_gameover_comment()
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
			# Null usually means the AI side has no legal move. Surface
			# that as a game end so the UI doesn't freeze waiting for a
			# move that will never come. Fall back to a warning if the
			# core disagrees (e.g. model failed to load).
			if not bool(_core.has_any_legal_move()):
				_check_end_state()
			else:
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
		var win_rate := float(_core.last_think_win_rate())
		_commit_move(mv)
		if win_rate >= 0.0:
			_ai_evals[int(_core.move_log_size())] = win_rate
		if not _game_over:
			_set_opponent_expression(_expression_after_ai_move(win_rate))

func _refresh_all() -> void:
	var view_core: Object = _active_core()
	_board_view.render(view_core)
	_sente_hand.render(view_core)
	_gote_hand.render(view_core)
	var side_gote: bool = view_core.side_to_move_gote()
	var mover := "後手" if side_gote else "先手"
	var in_check: bool = view_core.is_check()
	if in_check and not _game_over and not _in_review:
		_board_view.show_check(view_core, side_gote)
	else:
		_board_view.clear_check()
	if _thinking_label.visible:
		_place_thinking_label.call_deferred()
	if _lan and _game_over and _rematch_status != "" and not _in_review:
		_status.text = _rematch_status
	elif _in_review:
		var review_ply: int = int(_review_core.move_log_size())
		var live_ply: int = int(_core.move_log_size())
		_status.text = "%d手目 / %d手目 (棋譜閲覧中)" % [review_ply, live_ply]
	elif _lan_waiting and not _game_over:
		_status.text = "接続が切れました。再接続を待っています…"
	else:
		var ply: int = int(_core.move_log_size()) + 1
		if _lan and not _game_over:
			mover = "相手" if _is_remote_turn() else "あなた"
		_status.text = "%s の手番 (%d手目)" % [mover, ply]
	_undo_btn.disabled = int(_core.move_log_size()) == 0 or _game_over or _in_review or _lan
	_history_btn.disabled = int(_core.move_log_size()) == 0 or _thinking
	var ai_turn := _ai_enabled and Settings.side_is_ai(side_gote)
	_teacher_btn.disabled = _game_over or _thinking or ai_turn or not _ai_enabled or _in_review
	# 入玉宣言: button is shown to whichever human side has their king
	# in the opponent's promotion zone on their own turn. The actual
	# 27/28-point check fires on tap so the player can see *why* it
	# isn't accepted yet (and so we don't quietly hide the button when
	# only one rule is unmet).
	_jishogi_btn.visible = (
		not _game_over
		and not _in_review
		and not _thinking
		and not ai_turn
		and not _is_remote_turn()
		and not _lan_waiting
		and bool(view_core.king_entered(side_gote))
	)

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
	if _is_remote_turn() or _lan_waiting:
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
	if _is_remote_turn() or _lan_waiting:
		return
	_clear_suggestion_preview()
	_clear_selection()
	var drops: Array = _core.legal_drops(kind)
	if drops.is_empty():
		return
	_sel_state = SelState.HAND
	_sel_drop_kind = kind
	var hv: HandViewScript = _hand_view(is_gote)
	hv.set_selected_kind(kind)
	hv.render(_core)
	var targets: Array = []
	for m in drops:
		targets.append(Vector2i(m["to"]))
	_board_view.show_move_hints(targets)

func _try_select_board(key: Vector2i) -> void:
	var piece = _core.piece_at(key.x, key.y)
	if piece == null:
		return
	if bool(piece["is_gote"]) != _core.side_to_move_gote():
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
		_reject_tap(to)
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
	_reject_tap(to)

# Visual + haptic "no" for a tap the rules refused. Both channels so it
# still registers with sound off or in bright sunlight.
func _reject_tap(key: Vector2i) -> void:
	_board_view.flash_invalid(key)
	Input.vibrate_handheld(20)

func _prompt_promotion() -> void:
	var to: Vector2i = Vector2i(_pending_move["to"])
	_promo_dialog.dialog_text = "%d%s で成りますか?" % [to.x, Settings.RANK_KANJI[to.y]]
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
	var mover_is_ai: bool = _ai_enabled and Settings.side_is_ai(_core.side_to_move_gote())
	# A local move in a LAN game goes to the peer once it is applied.
	var lan_usi: String = ""
	if _lan and not _is_remote_turn():
		lan_usi = str(_core.move_to_usi(m))
	
	if not bool(_core.apply_move(m)):
		print("[game] rejected: %s" % m)
		return
	if lan_usi != "":
		NetSession.send_move(lan_usi)
	
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
			_board_view.animate_move(from_key, to_key, text, bool(landed["is_gote"]), Settings.anim(0.22))
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(50)
	_check_end_state()
	if _ai_enabled and not mover_is_ai and not _game_over:
		var captured_kind: int = int(target_piece["kind"]) if is_capture else -1
		_react_to_player_move(bool(_core.is_check()), captured_kind)
		if captured_kind in EXPR_MAJOR_KINDS:
			_say("lose_piece")
	elif _ai_enabled and mover_is_ai and not _game_over and bool(_core.is_check()):
		_say("check")
	# If the player committed a move while suggestions were open, the
	# board has been held small through this turn. Once it's the player's
	# turn again (= AI has replied) — or the game ended — zoom back.
	if _pending_zoom_back and (_game_over or not Settings.side_is_ai(_core.side_to_move_gote())):
		_pending_zoom_back = false
		_zoom_back_after_slide()
	# A LAN game can't be resumed alone, so it never takes the 続きから slot.
	if not _game_over and not _lan:
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
		_end_game("詰み\n%s の勝ち (%s を詰ました)" % [winner, loser], "詰み", winner)
		return
	# 手詰まり: side to move has no legal reply but isn't in check. In
	# practice nearly impossible with drops in play, but if it ever does
	# arise (e.g. bare-king AI with every escape square attacked) the
	# rules treat it as a loss for the side to move — match that here so
	# the game ends instead of the AI thread spinning on a null move.
	if not bool(_core.has_any_legal_move()):
		var loser2 := "後手" if _core.side_to_move_gote() else "先手"
		var winner2 := "先手" if _core.side_to_move_gote() else "後手"
		_end_game("手詰まり\n%s の勝ち (%s に指す手なし)" % [winner2, loser2], "詰み", winner2)
		return
	match str(_core.detect_sennichite()):
		"draw":
			_end_game("千日手 — 引き分け", "千日手")
			return
		"sente_loses":
			_end_game("連続王手の千日手 — 後手の勝ち", "千日手", "後手")
			return
		"gote_loses":
			_end_game("連続王手の千日手 — 先手の勝ち", "千日手", "先手")
			return
	# 持将棋 / AI auto-declaration. 持将棋 fires as soon as both sides
	# qualify; the AI, like a player, may only declare on its own turn.
	var sente_ok: bool = bool(_core.can_declare_jishogi(false)["ok"])
	var gote_ok: bool = bool(_core.can_declare_jishogi(true)["ok"])
	if sente_ok and gote_ok:
		_end_game("持将棋 — 引き分け", "持将棋")
		return
	if _ai_enabled:
		var ai_is_gote: bool = Settings.ai_plays_gote()
		var ai_qualifies: bool = (gote_ok if ai_is_gote else sente_ok)
		if ai_qualifies and bool(_core.side_to_move_gote()) == ai_is_gote:
			var winner := "後手" if ai_is_gote else "先手"
			_end_game("入玉宣言 — %s の勝ち" % winner, "入玉勝ち", winner)

# `winner` is "先手" / "後手", or "" for a draw.
func _end_game(text: String, terminator: String, winner: String = "") -> void:
	_game_over = true
	if _lan:
		NetSession.finish_game()
		_rematch_ok = NetSession.post_game
		_rematch_status = ""
		_gameover_dialog.ok_button_text = "再戦" if _rematch_ok else "タイトルへ"
	_gameover_terminator = terminator
	_board_view.clear_check()
	_undo_btn.disabled = true
	_gameover_text = text
	var result_expr := _expression_for_winner(winner)
	_set_opponent_expression(result_expr)
	var result_tex := _expression_texture(result_expr) if _ai_enabled else null
	_gameover_portrait.texture = result_tex
	_gameover_portrait.visible = result_tex != null
	_record_character_result(winner)
	Settings.clear_saved_game()
	print("[game] %s" % text.replace("\n", " "))
	# Every finished game is archived to the 棋譜検討 library
	# automatically; the dialog just reports where it went.
	_hide_speech()
	var parts := PackedStringArray([text])
	for part in [_result_speech(result_expr), _auto_save_kif_message()]:
		if part != "":
			parts.append(part)
	_gameover_label.text = "\n\n".join(parts)
	_gameover_review_btn.visible = _gameover_kif_path != ""
	_start_gameover_comment()
	_gameover_dialog.reset_size()
	_gameover_dialog.popup_centered()

# --- 加藤先生's post-game comment -----------------------------------------

# Player moves most likely to have been the turning point, as 1-based
# move numbers: those followed by the sharpest rises in the AI's own
# win rate. Only moves from this session are known (the record isn't
# saved with the game).
func _comment_candidates() -> Array[int]:
	var plies: Array = _ai_evals.keys()
	plies.sort()
	var jumps: Array = []
	for i in range(1, plies.size()):
		var a: int = plies[i - 1]
		var b: int = plies[i]
		if b - a != 2:
			continue  # not consecutive AI moves (undo, book move between)
		var jump: float = float(_ai_evals[b]) - float(_ai_evals[a])
		if jump >= COMMENT_MIN_JUMP:
			jumps.append([jump, b - 1])
	jumps.sort_custom(func(x, y): return x[0] > y[0])
	var out: Array[int] = []
	for j in jumps.slice(0, COMMENT_MAX_CANDIDATES):
		out.append(int(j[1]))
	return out

func _start_gameover_comment() -> void:
	_comment_ply = -1
	_gameover_comment.visible = false
	if not _ai_enabled or _ai_evals.size() < 2:
		return
	var candidates := _comment_candidates()
	_gameover_comment.visible = true
	if candidates.is_empty():
		_gameover_comment.text = "加藤先生「大きな悪手のない、良い将棋でした。」"
		return
	_gameover_comment.text = "加藤先生が検討中…"
	_comment_cancel = false
	_comment_thread = Thread.new()
	_comment_thread.start(_run_gameover_comment.bind(
		_core.move_log_packed(), candidates, Settings.model_absolute_path()))

# Worker thread: analyses each candidate move on a private ShogiCore
# and returns the worst one as an Analyzer entry (with `ply`), or {}.
func _run_gameover_comment(packed: PackedInt32Array, candidates: Array[int],
		model_path: String) -> Dictionary:
	var core: Object = ClassDB.instantiate("ShogiCore")
	if model_path == "" or not bool(core.load_model(model_path)):
		return {}
	var analyses: Array = []
	analyses.resize(packed.size())
	analyses.fill({})
	for ply in candidates:
		if _comment_cancel:
			return {}
		analyses[ply - 1] = Analyzer.analyze_ply(core, packed, ply - 1)
	return Analyzer.biggest_mistake(analyses, not Settings.ai_plays_gote())

func _finish_gameover_comment() -> void:
	var worst: Dictionary = _comment_thread.wait_to_finish()
	_comment_thread = null
	if _comment_cancel or not _game_over:
		return
	if worst.is_empty():
		_gameover_comment.text = "加藤先生「大きな悪手のない、良い将棋でした。」"
		return
	_comment_ply = int(worst["ply"])
	var lines: PackedStringArray = _core.move_log_kifu_lines()
	var played: String = lines[_comment_ply - 1] if _comment_ply - 1 < lines.size() else ""
	# Lines read "3 ☗４八銀"; the move number is already in the sentence.
	var marker_at: int = maxi(played.find("☗"), played.find("☖"))
	if marker_at > 0:
		played = played.substr(marker_at)
	_gameover_comment.text = "加藤先生「%d手目の %s が惜しかったですね。%s が良かったと思います。」" % [
		_comment_ply, played, String(worst["best_kifu"])]

# Abandon a running comment analysis and join its thread (at most one
# search away) so the scene can restart or tear down cleanly.
func _stop_gameover_comment() -> void:
	_comment_cancel = true
	if _comment_thread != null:
		_comment_thread.wait_to_finish()
		_comment_thread = null

# 検討: open the just-saved game in the 棋譜検討 reviewer, on the move
# the comment is about when there is one.
func _on_gameover_action(action: StringName) -> void:
	if action != &"review" or _gameover_kif_path == "":
		return
	_stop_gameover_comment()
	Settings.review_kif_path = _gameover_kif_path
	Settings.review_start_ply = _comment_ply
	_gameover_dialog.hide()
	SceneTransition.go_to("res://scenes/KifuReviewer.tscn")

# Writes the finished game's KIF and returns a one-line status for the
# player. Requires _game_over so the closing line + 結果 header are set.
func _auto_save_kif_message() -> String:
	_gameover_kif_path = ""
	if int(_core.move_log_size()) == 0:
		return ""
	var saved_path := _export_kif()
	if saved_path == "":
		return "棋譜の保存に失敗しました"
	_gameover_kif_path = saved_path
	return "棋譜を保存しました：%s" % saved_path.get_file()

func _on_restart() -> void:
	if _lan:
		if _rematch_ok and NetSession.post_game:
			NetSession.request_rematch()
			if NetSession.post_game:  # not already started by the host
				_rematch_status = "再戦の返事を待っています…"
				_refresh_all()
		else:
			_back_to_title()
		return
	_reset_game()

func _reset_game() -> void:
	_stop_gameover_comment()
	_ai_evals.clear()
	_core.reset_starting()
	_game_over = false
	_result_recorded = false
	_resumed = false
	_gameover_terminator = ""
	_gameover_text = ""
	_pending_move = {}
	_last_move = {}
	_mood_win_rate = -1.0
	_reaction_until_msec = 0
	_set_opponent_expression("neutral")
	_say("start")
	_clear_selection()
	_refresh_all()
	_refresh_last_move_hint()
	# The AI may be 先手; nothing else starts its first move.
	_maybe_start_ai_turn()

func _on_undo() -> void:
	if _game_over or _thinking:
		return
	if not bool(_core.undo_move()):
		return
	# In vs-AI modes the player expects 待った to revert their *own* last
	# move, but the move log's tail is the AI's reply — undo a second ply
	# so the position is restored to just before the human moved.
	if _ai_enabled \
			and Settings.side_is_ai(_core.side_to_move_gote()) \
			and int(_core.move_log_size()) > 0:
		_core.undo_move()
	# No single-level cache of the move *before* the one we just undid;
	# simplest correct behaviour is to blank the highlight until the
	# next move is committed.
	_last_move = {}
	# The reaction belonged to the move that was just taken back.
	_set_opponent_expression("neutral")
	_hide_speech()
	for ply in _ai_evals.keys():
		if int(ply) > int(_core.move_log_size()):
			_ai_evals.erase(ply)
	_clear_selection()
	_refresh_all()
	_refresh_last_move_hint()
	# Keep the saved game in sync with the live board, otherwise 続きから
	# would resume from the *pre-undo* position.
	if not _game_over:
		Settings.save_game(str(_core.to_sfen()), _core.move_log_packed())
	# If the undo lands on the AI's turn (e.g. AI-as-sente undone before
	# the human had a chance to move), kick the AI back to life — nothing
	# else triggers _maybe_start_ai_turn outside of _ready / _commit_move.
	_maybe_start_ai_turn()

func _on_exit_pressed() -> void:
	if _lan:
		_quit_dialog.dialog_text = ("タイトル画面に戻りますか?" if _game_over
			else "投了しますか?")
	_quit_dialog.popup_centered()

# 入玉宣言: query the rule. Ok → end the game with the declarer winning.
# Otherwise pop an info dialog explaining what's missing so the player
# can keep playing toward the threshold.
func _on_jishogi_pressed() -> void:
	if _game_over or _in_review or _thinking:
		return
	var side_gote: bool = _core.side_to_move_gote()
	var result: Dictionary = _core.can_declare_jishogi(side_gote)
	if bool(result["ok"]):
		var winner := "後手" if side_gote else "先手"
		if _lan:
			NetSession.send_declare()
		_end_game("入玉宣言 — %s の勝ち" % winner, "入玉勝ち", winner)
		return
	_jishogi_info_dialog.dialog_text = _jishogi_info_text(result)
	_jishogi_info_dialog.popup_centered()

func _jishogi_info_text(result: Dictionary) -> String:
	match String(result["reason"]):
		"king_not_entered":
			return "玉が敵陣に入っていません。"
		"in_check":
			return "玉が王手にかかっているため宣言できません。"
		"insufficient_pieces":
			return "敵陣の自駒が足りません (%d枚 / 必要 %d枚)。" % [
				int(result["pieces_have"]), int(result["pieces_need"])]
		"insufficient_points":
			return "持ち点が足りません (%d点 / 必要 %d点)。\n大駒・成大駒は5点、その他の駒は1点です (玉は除く)。" % [
				int(result["points_have"]), int(result["points_need"])]
		_:
			return "宣言できません。"

# Esc on desktop / Android back button-or-swipe (both map to ui_cancel by
# default) closes the suggestions panel if it's open, otherwise leaves
# the game and returns to the main menu. The board is auto-saved after
# every move so 続きから will pick up where the player left off.
# Both desktop Esc (real InputEventKey) and the autoload's synthesized
# Esc (Settings.gd's WM_GO_BACK_REQUEST bridge) come in here. We also
# handle WM_GO_BACK_REQUEST directly in _notification below — release
# builds have been seen to drop the synthesized press/release pair, so
# the direct notification is the reliable Android path. _back_handled_frame
# dedupes when both paths fire on the same frame.
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
	# Layered dismiss: close whichever popup is on top before falling
	# through to scene-back. Mirrors the implicit behaviour we used to
	# get from Godot's built-in popup Esc handling — the autoload no
	# longer synthesizes Esc, so we close popups explicitly here.
	if _history_dialog.visible:
		_history_dialog.hide()
		_on_history_closed()
		return
	if _promo_dialog.visible:
		_promo_dialog.hide()
		_on_promo_canceled()
		return
	var popups: Array[Window] = [_gameover_dialog, _quit_dialog, _jishogi_info_dialog]
	for popup in popups:
		if popup.visible:
			popup.hide()
			return
	if _suggestions_panel.visible:
		_close_suggestions()
		return
	if _lan and not _game_over:
		# Leaving a LAN game resigns it, so ask first.
		_quit_dialog.popup_centered()
		return
	_back_to_title()

func _exit_tree() -> void:
	_stop_gameover_comment()
	if _lan and NetSession.in_game:
		NetSession.close("abort")

func _back_to_title() -> void:
	_stop_gameover_comment()
	_join_workers()
	if _lan:
		NetSession.close("abort" if NetSession.in_game else "")
	SceneTransition.go_to("res://scenes/MainMenu.tscn")

# Join every search thread before touching _core or tearing down the
# scene. is_started() also catches a worker that has finished but has
# not been joined yet; abandoning its handle would leak.
func _join_workers() -> void:
	for worker: Thread in [_think_thread, _teacher_thread]:
		if worker != null and worker.is_started():
			worker.wait_to_finish()
	_think_thread = null
	_teacher_thread = null
	_thinking = false
	_teacher_thinking = false

func _on_quit_confirmed() -> void:
	# A finished game already has its result and KIF; the exit button
	# stays reachable after Back closes the 対局終了 dialog.
	if _game_over:
		_back_to_title()
		return
	_join_workers()
	var resigner := _resignation_side()
	var winner := "後手" if resigner == "先手" else "先手"
	print("[game] %s の投了 — %s の勝ち" % [resigner, winner])
	if _lan:
		# Stay on the board so the two players can agree on a rematch.
		NetSession.send_resign()
		_end_game("投了 — %s の勝ち (あなたが投了しました)" % winner, "投了", winner)
		return
	# A resignation ends the game too: archive it with 投了 as the
	# closing line so the library shows who won.
	_game_over = true
	_gameover_terminator = "投了"
	_gameover_text = "投了 — %s の勝ち" % winner
	_record_character_result(winner)
	_auto_save_kif_message()
	Settings.clear_saved_game()
	SceneTransition.go_to("res://scenes/MainMenu.tscn")

# Best-effort attribution of who resigned. In AI modes the human is the
# only one who can tap 投了, so we attribute to the human side. In H-v-H
# we attribute to whoever's turn it currently is.
func _resignation_side() -> String:
	if _lan:
		return "後手" if NetSession.local_is_gote else "先手"
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
	return "%d%s" % [v.x, Settings.RANK_KANJI[v.y]]

# --- 先生モード (teacher mode) ---------------------------------------------

func _apply_teacher_side() -> void:
	# Both spacers carry size_flags_horizontal=3; disabling the expand
	# flag on one side pushes the button there.
	var right: bool = Settings.teacher_side == "right"
	_teacher_left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL if right else 0
	_teacher_right_spacer.size_flags_horizontal = 0 if right else Control.SIZE_EXPAND_FILL
	# Hide the unused spacer so the HBox doesn't insert a trailing
	# separator after the button — otherwise the row's right edge sits
	# a few px shy of the StatusBar's right edge below it.
	_teacher_left_spacer.visible = right
	_teacher_right_spacer.visible = not right

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
	_place_thinking_label.call_deferred()
	_undo_btn.disabled = true
	_teacher_btn.disabled = true
	_history_btn.disabled = true
	_jishogi_btn.visible = false
	var playouts: int = int(Settings.ai_base_dials()["playouts"])
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
		btn.custom_minimum_size = Vector2(0, 56)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 24)
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
		_suggestions_panel, "modulate:a", 1.0, Settings.anim(_SUGGESTIONS_FADE))

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
		_suggestions_panel, "modulate:a", 0.0, Settings.anim(_SUGGESTIONS_FADE))
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
	await get_tree().create_timer(Settings.anim(0.28) + 0.02).timeout
	if not is_inside_tree():
		return
	_refit_board_smooth()

# --- 棋譜 history dialog ---------------------------------------------------

func _on_history_pressed() -> void:
	if _thinking:
		return
	var lines: PackedStringArray = _core.move_log_kifu_lines()
	# Highlight the row matching whatever ply is currently visible — the
	# live tip if not in review, or the rewound ply if reopened mid-review.
	var ply: int = int(_review_core.move_log_size()) if _in_review and _review_core != null else int(_core.move_log_size())
	_history_dialog.show_with(lines, ply)

# Build a scratch core, replay ply 1..N from the live log, and swap the
# views over to it. _active_core() now returns the scratch — interactive
# inputs are gated by _in_review and refuse to fire.
func _on_history_ply_selected(ply: int) -> void:
	if _thinking:
		return
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

func _on_history_share_requested() -> void:
	if _thinking:
		return
	var saved_path := _export_kif()
	if saved_path == "":
		_history_dialog.show_save_result(false, "保存に失敗しました")
	else:
		_history_dialog.show_save_result(true, "保存先：%s" % saved_path)

# Renders the current game to KIF and writes it to disk. Returns the
# saved path, or "" on failure. Shared by the mid-game 棋譜 dialog's
# 保存 button and the post-game 棋譜を保存 button.
func _export_kif() -> String:
	var sente_name := _player_name_for_side(false)
	var gote_name := _player_name_for_side(true)
	# Local time in KIF's canonical YYYY/MM/DD HH:MM:SS format. The export
	# itself is offline so the timestamp is a wall-clock note for the
	# human reader, not a synchronised game-clock entry.
	var dt := Time.get_datetime_dict_from_system()
	var started_at := "%04d/%02d/%02d %02d:%02d:%02d" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
	var stamp := "%04d%02d%02d_%02d%02d%02d" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
	# Finished games get the real closing line + a 結果 header so the
	# 棋譜検討 library can show the outcome; mid-game saves end in 中断.
	var terminator := _gameover_terminator if _game_over else ""
	var result := _short_result(_gameover_text) if _game_over else ""
	var kif: String = String(_core.to_kif(sente_name, gote_name, started_at, terminator, result))
	var filename := "kifu_%s.kif" % stamp
	return _save_kif(filename, kif)

# Writes `body` into a file named `filename` and returns the on-disk
# path the user can browse to (empty string on failure). Tries the
# user-visible Documents dir first; on Android that's the app-private
# external Documents (`Android/data/<pkg>/files/Documents/`) which is
# accessible to file managers without requesting any permission. Falls
# back to user:// (always writable, but not file-manager-visible on
# Android without root) so a save never silently disappears.
func _save_kif(filename: String, body: String) -> String:
	var candidates: Array[String] = []
	var docs_dir := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS, false)
	if docs_dir != "":
		candidates.append("%s/%s" % [docs_dir, filename])
	candidates.append("user://%s" % filename)
	for path in candidates:
		var globalized: String = path
		if path.begins_with("user://"):
			globalized = ProjectSettings.globalize_path(path)
		var dir_path := globalized.get_base_dir()
		DirAccess.make_dir_recursive_absolute(dir_path)
		var f := FileAccess.open(globalized, FileAccess.WRITE)
		if f == null:
			push_warning("save_kif: cannot open %s (err %d)" % [globalized, FileAccess.get_open_error()])
			continue
		f.store_string(body)
		f.close()
		return globalized
	return ""

# Condenses the game-over dialog text into the one-line 結果 header the
# library shows: drops the parenthetical detail and the spacing around
# の勝ち, e.g. "詰み\n先手 の勝ち (後手 を詰ました)" → "詰み 先手の勝ち".
func _short_result(text: String) -> String:
	var r := text.replace("\n", " ").replace(" — ", " ")
	var paren := r.find("(")
	if paren >= 0:
		r = r.substr(0, paren)
	r = r.replace(" の勝ち", "の勝ち")
	return r.strip_edges()

# Sente / Gote labels for KIF export. AI matches map the named side to
# the chosen character; the human side stays as a generic "プレイヤー".
# H_VS_H labels both sides as the generic player so the export still
# round-trips cleanly through any KIF viewer.
func _player_name_for_side(is_gote: bool) -> String:
	if _lan:
		return NetSession.local_name if is_gote == NetSession.local_is_gote else NetSession.remote_name
	if _ai_enabled and Settings.side_is_ai(is_gote) and _character != null:
		return "%s (Lv.%d)" % [_character.display_name, _character.level]
	return "プレイヤー"

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

# --- 通信対戦 (LAN) ---------------------------------------------------------

func _setup_lan() -> void:
	NetSession.move_received.connect(_on_lan_move)
	NetSession.resign_received.connect(_on_lan_resign)
	NetSession.declare_received.connect(_on_lan_declare)
	NetSession.abort_received.connect(_on_lan_abort)
	NetSession.peer_lost.connect(_on_lan_peer_lost)
	NetSession.peer_restored.connect(_on_lan_peer_restored)
	NetSession.session_failed.connect(_on_lan_failed)
	NetSession.rematch_requested.connect(_on_lan_rematch_requested)
	NetSession.game_started.connect(_on_lan_rematch_started)
	_opponent_label.text = "%s (%s)" % [NetSession.remote_name, _remote_side()]
	_opponent_portrait_frame.visible = false
	_opponent_strip.visible = true
	_undo_btn.visible = false
	_gameover_dialog.ok_button_text = "再戦"

func _local_side() -> String:
	return "後手" if NetSession.local_is_gote else "先手"

func _remote_side() -> String:
	return "先手" if NetSession.local_is_gote else "後手"

func _is_remote_turn() -> bool:
	return _lan and bool(_core.side_to_move_gote()) != NetSession.local_is_gote

# Every peer move is checked against the full rules before it touches the
# board; anything else ends the game.
func _on_lan_move(usi: String) -> void:
	if _game_over:
		return
	var m: Variant = _core.usi_to_move(usi)
	if m == null or not _is_remote_turn() or not bool(_core.is_legal_move(m)):
		_lan_protocol_error()
		return
	if _in_review:
		_exit_review()
	_commit_move(m)

# The peer wants another game. Bring the result dialog back so the
# player sees the request and can answer with 再戦.
func _on_lan_rematch_requested() -> void:
	if not _game_over or not _rematch_ok:
		return
	_rematch_status = "相手が再戦を希望しています"
	_add_gameover_note("相手が再戦を希望しています。")
	if not _gameover_dialog.visible:
		_gameover_dialog.popup_centered()
	_refresh_all()

# Adds a line under the result in the 対局終了 dialog, which covers the
# status line while it is open.
func _add_gameover_note(note: String) -> void:
	if not _gameover_label.text.ends_with(note):
		_gameover_label.text += "\n\n" + note
	_gameover_dialog.reset_size()

# Both asked: NetSession started a new game with the sides swapped.
func _on_lan_rematch_started() -> void:
	_rematch_ok = false
	_rematch_status = ""
	_lan_waiting = false
	_gameover_dialog.hide()
	if _in_review:
		_exit_review()
	_apply_board_orientation()
	_opponent_label.text = "%s (%s)" % [NetSession.remote_name, _remote_side()]
	_reset_game()

func _on_lan_resign() -> void:
	if _game_over:
		return
	var winner := _local_side()
	_end_game("投了 — %s の勝ち (相手が投了しました)" % winner, "投了", winner)

func _on_lan_declare() -> void:
	if _game_over:
		return
	var remote_gote := not NetSession.local_is_gote
	if not _is_remote_turn() or not bool(_core.can_declare_jishogi(remote_gote)["ok"]):
		_lan_protocol_error()
		return
	var winner := _remote_side()
	_end_game("入玉宣言 — %s の勝ち" % winner, "入玉勝ち", winner)

func _on_lan_abort() -> void:
	if _game_over:
		return
	_end_game("相手が対局をやめました — 中断", "")

func _on_lan_peer_lost() -> void:
	if _game_over:
		return
	_lan_waiting = true
	_clear_selection()
	_refresh_all()

# Replays the agreed move list from the start. On a reconnect either side
# may have been one move behind; the list is checked move by move.
func _on_lan_peer_restored(usi_moves: PackedStringArray) -> void:
	_lan_waiting = false
	if _game_over:
		return
	if usi_moves.size() != int(_core.move_log_size()):
		if _in_review:
			_exit_review()
		_core.reset_starting()
		var last: Dictionary = {}
		for usi in usi_moves:
			var m: Variant = _core.usi_to_move(usi)
			if m == null or not bool(_core.is_legal_move(m)) or not bool(_core.apply_move(m)):
				_lan_protocol_error()
				return
			last = m
		_last_move = last
		_clear_selection()
		_refresh_last_move_hint()
		_check_end_state()
	_refresh_all()

func _on_lan_failed(reason: String) -> void:
	_lan_waiting = false
	if _game_over:
		# The peer left after the game: no rematch any more.
		if _rematch_ok:
			_rematch_ok = false
			_rematch_status = "相手は対局を終えました"
			_gameover_dialog.ok_button_text = "タイトルへ"
			_add_gameover_note("相手は対局を終えました。")
			_refresh_all()
		return
	_end_game("%s — 中断" % reason, "")

func _lan_protocol_error() -> void:
	NetSession.close("abort")
	_end_game("相手から不正な指し手を受信しました — 中断", "")

# --- board orientation -----------------------------------------------------

# The player sits at the bottom of the screen. When the local human plays
# 後手 (vs. an AI 先手, or as 後手 in 通信対戦) the board is turned round:
# 後手's pieces upright at the bottom, 後手's hand below the board.
# Hot-seat 人対人 keeps 先手 at the bottom.
func _human_plays_gote() -> bool:
	if _lan:
		return NetSession.local_is_gote
	return Settings.mode == Settings.Mode.H_VS_AI_SENTE

func _apply_board_orientation() -> void:
	var flip := _human_plays_gote()
	_board_view.set_flipped(flip)
	# %SenteHand is the panel below the board, %GoteHand the one above.
	_sente_hand.is_gote = flip
	_gote_hand.is_gote = not flip
	_sente_hand.flipped = flip
	_gote_hand.flipped = flip

# The hand panel currently showing `is_gote`'s pieces.
func _hand_view(is_gote: bool) -> HandViewScript:
	return _gote_hand if _gote_hand.is_gote == is_gote else _sente_hand
