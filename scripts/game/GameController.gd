class_name GameController
extends Control

const PieceScript := preload("res://scripts/game/Piece.gd")
const BoardStateScript := preload("res://scripts/game/BoardState.gd")
const MoveGenScript := preload("res://scripts/game/MoveGen.gd")
const RulesScript := preload("res://scripts/game/Rules.gd")
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

const _RANK_KANJI := ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

enum SelState { IDLE, BOARD, HAND }

var _state: BoardStateScript
var _sel_state: int = SelState.IDLE
var _sel_from: Vector2i = Vector2i.ZERO
var _sel_drop_kind: int = -1
var _pending_move: Dictionary = {}
var _game_over: bool = false

func _ready() -> void:
	_state = BoardStateScript.new()
	_board_view.square_tapped.connect(_on_board_tapped)
	_sente_hand.piece_tapped.connect(_on_hand_tapped.bind(false))
	_gote_hand.piece_tapped.connect(_on_hand_tapped.bind(true))
	_promo_dialog.confirmed.connect(_on_promo_confirmed)
	_promo_dialog.canceled.connect(_on_promo_canceled)
	_promo_dialog.close_requested.connect(_on_promo_canceled)
	_gameover_dialog.confirmed.connect(_on_restart)
	_undo_btn.pressed.connect(_on_undo)
	_sente_hand.is_gote = false
	_gote_hand.is_gote = true
	_refresh_all()

func _refresh_all() -> void:
	_board_view.render(_state)
	_sente_hand.render(_state)
	_gote_hand.render(_state)
	var mover := "後手" if _state.side_to_move_gote else "先手"
	var in_check := RulesScript.is_check(_state, _state.side_to_move_gote)
	_check_banner.visible = in_check and not _game_over
	_status.text = "%s の手番 | SFEN: %s" % [mover, _state.to_sfen()]
	_undo_btn.disabled = _state.move_log.is_empty() or _game_over

func _clear_selection() -> void:
	_sel_state = SelState.IDLE
	_sel_from = Vector2i.ZERO
	_sel_drop_kind = -1
	_board_view.clear_selected()
	_board_view.clear_move_hints()
	_sente_hand.clear_selected_kind()
	_gote_hand.clear_selected_kind()
	_sente_hand.render(_state)
	_gote_hand.render(_state)

func _on_board_tapped(file: int, rank: int) -> void:
	if _game_over:
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
	if _game_over or is_gote != _state.side_to_move_gote:
		return
	_clear_selection()
	if int(_state.hand(is_gote).get(kind, 0)) <= 0:
		return
	var drops := RulesScript.legal_drops(_state, kind)
	if drops.is_empty():
		return
	_sel_state = SelState.HAND
	_sel_drop_kind = kind
	var hv: HandViewScript = _gote_hand if is_gote else _sente_hand
	hv.set_selected_kind(kind)
	hv.render(_state)
	var targets: Array = []
	for m in drops:
		targets.append(m["to"])
	_board_view.show_move_hints(targets)

func _try_select_board(key: Vector2i) -> void:
	var piece: PieceScript = _state.piece_at(key.x, key.y)
	if piece == null or piece.is_gote != _state.side_to_move_gote:
		return
	var moves := RulesScript.legal_moves_from(_state, key)
	if moves.is_empty():
		return
	_sel_state = SelState.BOARD
	_sel_from = key
	_board_view.set_selected(key)
	var targets: Array = []
	var seen: Dictionary = {}
	for m in moves:
		var to: Vector2i = m["to"]
		if not seen.has(to):
			seen[to] = true
			targets.append(to)
	_board_view.show_move_hints(targets)

func _handle_board_target(to: Vector2i) -> void:
	if to == _sel_from:
		_clear_selection()
		return
	var target_piece: PieceScript = _state.piece_at(to.x, to.y)
	if target_piece != null and target_piece.is_gote == _state.side_to_move_gote:
		_clear_selection()
		_try_select_board(to)
		return
	var moves := RulesScript.legal_moves_from(_state, _sel_from)
	var candidates: Array = []
	for m in moves:
		if m["to"] == to:
			candidates.append(m)
	if candidates.is_empty():
		return
	var has_promo := false
	var has_plain := false
	for m in candidates:
		if m.get("promote", false):
			has_promo = true
		else:
			has_plain = true
	if has_promo and has_plain:
		var plain: Dictionary = {}
		for m in candidates:
			if not m.get("promote", false):
				plain = m
				break
		_pending_move = plain
		_prompt_promotion()
	else:
		_commit_move(candidates[0])

func _handle_drop_target(to: Vector2i) -> void:
	if _state.piece_at(to.x, to.y) != null:
		if _state.piece_at(to.x, to.y).is_gote == _state.side_to_move_gote:
			_clear_selection()
			_try_select_board(to)
		return
	var drops := RulesScript.legal_drops(_state, _sel_drop_kind)
	for m in drops:
		if m["to"] == to:
			_commit_move(m)
			return

func _prompt_promotion() -> void:
	var to: Vector2i = _pending_move["to"]
	_promo_dialog.dialog_text = "%d%s で成りますか?" % [to.x, _RANK_KANJI[to.y]]
	_promo_dialog.popup_centered()

func _on_promo_confirmed() -> void:
	if _pending_move.is_empty():
		return
	var m := _pending_move.duplicate()
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
	var mover := "後手" if _state.side_to_move_gote else "先手"
	if not _state.apply_move(m):
		print("[game] rejected: %s" % m)
		return
	# Tag the just-applied record with check + position fingerprint so
	# Rules can detect sennichite / perpetual check later.
	var rec: Dictionary = _state.move_log[-1]
	rec["was_check"] = RulesScript.is_check(_state, _state.side_to_move_gote)
	rec["position_key_after"] = _state.position_key()
	_log_move(mover, m)
	_clear_selection()
	_refresh_all()
	_check_end_state()

func _check_end_state() -> void:
	if RulesScript.is_checkmate(_state):
		var loser := "後手" if _state.side_to_move_gote else "先手"
		var winner := "先手" if _state.side_to_move_gote else "後手"
		_end_game("詰み\n%s の勝ち (%s を詰ました)" % [winner, loser])
		return
	match RulesScript.detect_sennichite(_state):
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
	print("[game] %s" % text.replace("\n", " "))

func _on_restart() -> void:
	_state.reset_starting()
	_game_over = false
	_pending_move = {}
	_clear_selection()
	_refresh_all()

func _on_undo() -> void:
	if _game_over:
		return
	if _state.undo_move():
		_clear_selection()
		_refresh_all()

func _log_move(mover: String, m: Dictionary) -> void:
	if m.has("drop_kind"):
		var to: Vector2i = m["to"]
		print("[game] %s %s%s打" % [mover, _square_str(to), PieceScript.KANJI[m["drop_kind"]]])
	else:
		var from: Vector2i = m["from"]
		var to2: Vector2i = m["to"]
		var suffix := "成" if m.get("promote", false) else ""
		print("[game] %s %s→%s%s" % [mover, _square_str(from), _square_str(to2), suffix])

func _square_str(v: Vector2i) -> String:
	return "%d%s" % [v.x, _RANK_KANJI[v.y]]
