extends SceneTree

# FFI parity checks: drive the native ShogiCore from GDScript and verify
# the same fixtures the pure-GDScript implementation used to pass.

const PieceScript := preload("res://scripts/game/Piece.gd")

var _fails: int = 0

func _initialize() -> void:
	if not ClassDB.class_exists("ShogiCore"):
		push_error("ShogiCore class not registered — GDExtension not loaded")
		quit(1)
		return
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

func _core() -> Object:
	return ClassDB.instantiate("ShogiCore")

func _setup(c: Object, pieces: Array, hands: Array, side_gote: bool) -> void:
	c.clear_board()
	for p in pieces:
		c.place(p[0], p[1], p[2], p[3])
	for h in hands:
		c.set_hand_count(h[0], h[1], h[2])
	c.set_side_to_move_gote(side_gote)
	c.seal_initial_position()

func _test_starting_not_check() -> String:
	var c := _core()
	if bool(c.is_check()):
		return "starting side in check"
	return ""

func _test_pin() -> String:
	var c := _core()
	_setup(c, [
		[5, 9, PieceScript.Kind.KING,   false],
		[5, 5, PieceScript.Kind.KING,   true],
		[3, 5, PieceScript.Kind.SILVER, true],
		[1, 5, PieceScript.Kind.ROOK,   false],
	], [], true)
	var moves: Array = c.legal_moves_from(3, 5)
	if not moves.is_empty():
		return "pinned silver produced %d legal moves; expected 0" % moves.size()
	return ""

func _test_nifu() -> String:
	var c := _core()
	_setup(c, [
		[5, 9, PieceScript.Kind.KING, false],
		[5, 1, PieceScript.Kind.KING, true],
		[5, 7, PieceScript.Kind.PAWN, false],
	], [[false, PieceScript.Kind.PAWN, 1]], false)
	for m in c.legal_drops(PieceScript.Kind.PAWN):
		if int(Vector2i(m["to"]).x) == 5:
			return "pawn drop allowed on file 5 despite own pawn at 5-7"
	return ""

func _uchifuzume_fixture(c: Object, extra_hand: Array) -> void:
	var hands := [
		[false, PieceScript.Kind.PAWN, 1],
	]
	for e in extra_hand:
		hands.append(e)
	_setup(c, [
		[9, 9, PieceScript.Kind.KING,   false],
		[5, 1, PieceScript.Kind.KING,   true],
		[4, 1, PieceScript.Kind.GOLD,   true],
		[6, 1, PieceScript.Kind.KNIGHT, true],
		[4, 2, PieceScript.Kind.PAWN,   true],
		[6, 2, PieceScript.Kind.PAWN,   true],
		[1, 1, PieceScript.Kind.ROOK,   false],
		[4, 3, PieceScript.Kind.BISHOP, false],
	], hands, false)

func _test_uchifuzume() -> String:
	var c := _core()
	_uchifuzume_fixture(c, [])
	if bool(c.is_check()):
		return "fixture pre-check: sente side already in check"
	for m in c.legal_drops(PieceScript.Kind.PAWN):
		if Vector2i(m["to"]) == Vector2i(5, 2):
			return "pawn drop at 5-2 allowed; should be refused by uchifuzume"
	return ""

func _test_silver_drop_mate_legal() -> String:
	var c := _core()
	_uchifuzume_fixture(c, [[false, PieceScript.Kind.SILVER, 1]])
	for m in c.legal_drops(PieceScript.Kind.SILVER):
		if Vector2i(m["to"]) == Vector2i(5, 2):
			return ""
	return "silver drop at 5-2 refused; only pawn drops should be uchifuzume"

func _test_undo_capture_promote() -> String:
	var c := _core()
	_setup(c, [
		[5, 9, PieceScript.Kind.KING,   false],
		[5, 1, PieceScript.Kind.KING,   true],
		[3, 4, PieceScript.Kind.PAWN,   false],
		[3, 3, PieceScript.Kind.SILVER, true],
	], [], false)
	var before := str(c.to_sfen())
	var ok: bool = bool(c.apply_move({
		from = Vector2i(3, 4), to = Vector2i(3, 3), promote = true,
	}))
	if not ok:
		return "apply_move rejected the capture+promote"
	if not bool(c.undo_move()):
		return "undo_move returned false"
	if str(c.to_sfen()) != before:
		return "SFEN mismatch after undo\n  before: %s\n  after:  %s" % [before, str(c.to_sfen())]
	return ""
