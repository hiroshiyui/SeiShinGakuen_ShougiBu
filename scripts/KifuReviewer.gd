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
@onready var _back_btn: Button = %BackButton
@onready var _first_btn: Button = %FirstButton
@onready var _prev_btn: Button = %PrevButton
@onready var _next_btn: Button = %NextButton
@onready var _last_btn: Button = %LastButton

var _core: Object
var _packed: PackedInt32Array = PackedInt32Array()
var _ply: int = 0

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
	_first_btn.pressed.connect(func(): _set_ply(0))
	_prev_btn.pressed.connect(func(): _set_ply(_ply - 1))
	_next_btn.pressed.connect(func(): _set_ply(_ply + 1))
	_last_btn.pressed.connect(func(): _set_ply(_packed.size()))

	get_viewport().size_changed.connect(_refit_board)
	_refit_board()

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
	_first_btn.disabled = _ply == 0
	_prev_btn.disabled = _ply == 0
	_next_btn.disabled = _ply == _packed.size()
	_last_btn.disabled = _ply == _packed.size()

# Match GameController's board-fit math so the reviewer board respects
# the same hand / nav padding budget. Simpler than reusing the live
# controller's heuristic — the reviewer only has a fixed set of rows.
func _refit_board() -> void:
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	var reserved: float = 56.0 + 72.0 + 72.0 + 40.0 + 64.0 + 32.0
	var side: float = clamp(min(vw - 40.0, vh - reserved), 240.0, 1600.0)
	_board_view.custom_minimum_size = Vector2(side, side)
