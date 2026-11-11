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
	_run("replayed game counts repetitions like the live game", _test_replay_repetition_count)
	_run("analysis treats unvisited moves as having no value", _test_analyzer_unvisited)
	_run("replay rejects an illegal move from a save / KIF", _test_replay_rejects_illegal)
	_run("out-of-range squares are rejected, not wrapped", _test_out_of_range_square)
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

func _shuffle_move(ff: int, fr: int, tf: int, tr: int) -> Dictionary:
	return {"from": Vector2i(ff, fr), "to": Vector2i(tf, tr), "promote": false}

func _test_replay_repetition_count() -> String:
	var live := _core()
	for i in 2:
		live.apply_move(_shuffle_move(2, 8, 3, 8))
		live.apply_move(_shuffle_move(8, 2, 7, 2))
		live.apply_move(_shuffle_move(3, 8, 2, 8))
		live.apply_move(_shuffle_move(7, 2, 8, 2))
	var replay := _core()
	if not bool(replay.apply_packed(live.move_log_packed())):
		return "replay failed"
	if str(live.detect_sennichite()) != "none":
		return "live game: start seen 3 times must not be sennichite"
	if str(replay.detect_sennichite()) != "none":
		return "replay over-counted the starting position"
	return ""

func _test_analyzer_unvisited() -> String:
	var analyzer: GDScript = load("res://scripts/KifuAnalyzer.gd")
	var target := {"from": Vector2i(7, 7), "to": Vector2i(7, 6), "promote": false}
	var visited := target.duplicate()
	visited["visits"] = 3
	visited["win_rate"] = 0.7
	var unvisited := target.duplicate()
	unvisited["visits"] = 0
	unvisited["win_rate"] = 0.5
	if analyzer.find_q_for_move([visited], target) != 0.7:
		return "visited move should report its win rate"
	if analyzer.find_q_for_move([unvisited], target) != analyzer.UNVISITED:
		return "unvisited row must not report its placeholder 50%"
	if analyzer.find_q_for_move([], target) != analyzer.UNVISITED:
		return "missing move should be unvisited"
	return ""

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

# apply_move only checks geometry (the UI offers legal moves only), so it
# can record a pawn jumping 7七→1一. A save or KIF carrying that must not
# replay.
func _test_replay_rejects_illegal() -> String:
	var forged := _core()
	if not bool(forged.apply_move({"from": Vector2i(7, 7), "to": Vector2i(1, 1), "promote": false})):
		return "setup: geometry-only apply_move refused the forged move"
	var replay := _core()
	if bool(replay.apply_packed(forged.move_log_packed())):
		return "apply_packed accepted an illegal move"
	return ""

func _test_out_of_range_square() -> String:
	var c := _core()
	# 257 would wrap to file 1 with a plain i8 cast.
	if bool(c.apply_move({"from": Vector2i(7, 7), "to": Vector2i(257, 6), "promote": false})):
		return "apply_move accepted file 257"
	if c.piece_at(257, 7) != null:
		return "piece_at(257, 7) returned a piece"
	if bool(c.is_legal_move({"drop_kind": 256, "to": Vector2i(5, 5)})):
		return "drop_kind 256 accepted"
	return ""
