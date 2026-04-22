extends SceneTree

const PieceScript := preload("res://scripts/game/Piece.gd")
const BoardStateScript := preload("res://scripts/game/BoardState.gd")
const MoveGenScript := preload("res://scripts/game/MoveGen.gd")
const RulesScript := preload("res://scripts/game/Rules.gd")

var _fails: int = 0

func _initialize() -> void:
	_run("starting position is not check", _test_starting_not_check)
	_run("pinned piece cannot move off line", _test_pin)
	_run("nifu: cannot drop pawn on file with own unpromoted pawn", _test_nifu)
	_run("uchifuzume: pawn drop that would mate is rejected", _test_uchifuzume)
	_run("non-pawn drop delivering mate is legal", _test_silver_drop_mate_legal)
	_run("undo restores SFEN after capture + promote", _test_undo_capture_promote)
	if _fails > 0:
		push_error("FAILED %d test(s)" % _fails)
		quit(1)
	else:
		print("All tests passed.")
		quit()

func _run(name: String, fn: Callable) -> void:
	var err: String = fn.call()
	if err == "":
		print("  ok  — %s" % name)
	else:
		_fails += 1
		push_error("FAIL — %s\n       %s" % [name, err])

# -----------------------------------------------------------------------------

func _test_starting_not_check() -> String:
	var s := BoardStateScript.new()
	if RulesScript.is_check(s, false):
		return "sente unexpectedly in check at start"
	if RulesScript.is_check(s, true):
		return "gote unexpectedly in check at start"
	if not RulesScript.has_any_legal_move(s):
		return "sente has no legal moves at start"
	return ""

# Sente rook at 1-5 pins gote silver at 3-5 against gote king at 5-5.
# The silver geometrically could move to several squares, but every move
# opens the file and exposes the king — so no legal moves from 3-5.
func _test_pin() -> String:
	var s := BoardStateScript.new()
	s.clear_board()
	s.place(5, 9, PieceScript.Kind.KING, false)     # sente king (off to the side)
	s.place(5, 5, PieceScript.Kind.KING, true)      # gote king
	s.place(3, 5, PieceScript.Kind.SILVER, true)    # pinned gote silver
	s.place(1, 5, PieceScript.Kind.ROOK, false)     # pinning sente rook
	s.set_side_to_move(true)  # gote to move
	s.seal_initial_position()
	var moves := RulesScript.legal_moves_from(s, Vector2i(3, 5))
	if not moves.is_empty():
		return "pinned silver produced %d legal moves; expected 0" % moves.size()
	return ""

func _test_nifu() -> String:
	var s := BoardStateScript.new()
	s.clear_board()
	s.place(5, 9, PieceScript.Kind.KING, false)
	s.place(5, 1, PieceScript.Kind.KING, true)
	s.place(5, 7, PieceScript.Kind.PAWN, false)     # sente pawn on file 5
	s.set_hand_count(false, PieceScript.Kind.PAWN, 1)
	s.set_side_to_move(false)
	s.seal_initial_position()
	var drops := RulesScript.legal_drops(s, PieceScript.Kind.PAWN)
	for m in drops:
		if m["to"].x == 5:
			return "pawn drop allowed on file 5 despite own pawn at 5-7"
	return ""

# Classic uchifuzume fixture: dropping P at 5-2 would be mate, which is illegal.
func _test_uchifuzume() -> String:
	var s := BoardStateScript.new()
	s.clear_board()
	s.place(9, 9, PieceScript.Kind.KING, false)     # sente king (far)
	s.place(5, 1, PieceScript.Kind.KING, true)      # gote king
	s.place(4, 1, PieceScript.Kind.GOLD, true)      # gote blocker, pinned by rook
	s.place(6, 1, PieceScript.Kind.KNIGHT, true)    # gote blocker, can't reach 5-2
	s.place(4, 2, PieceScript.Kind.PAWN, true)      # gote blocker, can't reach 5-2
	s.place(6, 2, PieceScript.Kind.PAWN, true)      # gote blocker, can't reach 5-2
	s.place(1, 1, PieceScript.Kind.ROOK, false)     # pins 4-1 gold
	s.place(4, 3, PieceScript.Kind.BISHOP, false)   # defends 5-2
	s.set_hand_count(false, PieceScript.Kind.PAWN, 1)
	s.set_side_to_move(false)
	s.seal_initial_position()
	# Sanity: starting position is not check.
	if RulesScript.is_check(s, true):
		return "fixture pre-check: gote already in check before drop"
	var drops := RulesScript.legal_drops(s, PieceScript.Kind.PAWN)
	for m in drops:
		if m["to"] == Vector2i(5, 2):
			return "pawn drop at 5-2 allowed; should be refused by uchifuzume"
	return ""

# Same squeeze, but dropping a silver (not a pawn) to deliver mate is legal.
func _test_silver_drop_mate_legal() -> String:
	var s := BoardStateScript.new()
	s.clear_board()
	s.place(9, 9, PieceScript.Kind.KING, false)
	s.place(5, 1, PieceScript.Kind.KING, true)
	s.place(4, 1, PieceScript.Kind.GOLD, true)
	s.place(6, 1, PieceScript.Kind.KNIGHT, true)
	s.place(4, 2, PieceScript.Kind.PAWN, true)
	s.place(6, 2, PieceScript.Kind.PAWN, true)
	s.place(1, 1, PieceScript.Kind.ROOK, false)
	s.place(4, 3, PieceScript.Kind.BISHOP, false)
	s.set_hand_count(false, PieceScript.Kind.SILVER, 1)
	s.set_side_to_move(false)
	s.seal_initial_position()
	var drops := RulesScript.legal_drops(s, PieceScript.Kind.SILVER)
	var found := false
	for m in drops:
		if m["to"] == Vector2i(5, 2):
			found = true
			break
	if not found:
		return "silver drop at 5-2 refused; only pawn drops should be uchifuzume"
	return ""

func _test_undo_capture_promote() -> String:
	var s := BoardStateScript.new()  # starting position
	var before := s.to_sfen()
	# Sente plays 2六歩 (pawn push), gote plays 3四歩, sente plays 2五歩,
	# gote plays 8四歩 — then sente plays 角 capture? Skip the whole sequence;
	# instead fabricate a simpler capture+promote by hand.
	s.clear_board()
	s.place(5, 9, PieceScript.Kind.KING, false)
	s.place(5, 1, PieceScript.Kind.KING, true)
	s.place(3, 4, PieceScript.Kind.PAWN, false)     # sente pawn
	s.place(3, 3, PieceScript.Kind.SILVER, true)    # gote silver (capturable)
	s.set_side_to_move(false)
	s.seal_initial_position()
	before = s.to_sfen()
	var move := {from = Vector2i(3, 4), to = Vector2i(3, 3), promote = true}
	if not s.apply_move(move):
		return "apply_move rejected the capture+promote"
	if not s.undo_move():
		return "undo_move returned false"
	if s.to_sfen() != before:
		return "SFEN mismatch after undo\n  before: %s\n  after:  %s" % [before, s.to_sfen()]
	return ""
