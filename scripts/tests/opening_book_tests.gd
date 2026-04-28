extends SceneTree

# Sanity-test the shipped opening book (assets/opening_book.json):
#  - parses as JSON with the expected shape
#  - includes the standard starting position
#  - every keyed position parses as a valid SFEN
#  - every USI candidate is a legal move at its keyed position
#  - weights are positive integers
#  - candidates within an entry have unique USIs
#
# Run:
#   ~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 --headless \
#     -s res://scripts/tests/opening_book_tests.gd --path .

const PieceScript := preload("res://scripts/game/Piece.gd")
const BOOK_PATH := "res://assets/opening_book.json"
const STARTING_KEY := "lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b -"

var _fails: int = 0

func _initialize() -> void:
	if not ClassDB.class_exists("ShogiCore"):
		push_error("ShogiCore class not registered — GDExtension not loaded")
		quit(1)
		return
	var book: Variant = _load_book()
	if typeof(book) != TYPE_DICTIONARY:
		quit(1)
		return
	_run("book contains the starting position", _test_starting.bind(book))
	_run("entries have the expected shape", _test_shape.bind(book))
	_run("every position parses as SFEN", _test_positions_parse.bind(book))
	_run("every candidate is legal at its position", _test_candidates_legal.bind(book))
	_run("weights are positive integers", _test_weights.bind(book))
	_run("candidates within each entry have unique USIs", _test_unique.bind(book))
	if _fails > 0:
		push_error("FAILED %d test(s)" % _fails)
		quit(1)
	else:
		print("All tests passed.")
		quit()

func _load_book() -> Variant:
	if not FileAccess.file_exists(BOOK_PATH):
		push_error("missing %s" % BOOK_PATH)
		return null
	var f := FileAccess.open(BOOK_PATH, FileAccess.READ)
	var src := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(src)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("opening book root is not a Dictionary (got type %d)" % typeof(parsed))
		return null
	return parsed

func _run(name: String, fn: Callable) -> void:
	var err: String = fn.call()
	if err == "":
		print("  ok  — %s" % name)
	else:
		_fails += 1
		push_error("FAIL — %s\n       %s" % [name, err])

# -----------------------------------------------------------------------------

func _test_starting(book: Dictionary) -> String:
	if not book.has(STARTING_KEY):
		return "starting position key missing from book"
	var cands: Array = book[STARTING_KEY]
	if cands.is_empty():
		return "starting position has no candidates"
	return ""

func _test_shape(book: Dictionary) -> String:
	for key in book.keys():
		if typeof(key) != TYPE_STRING:
			return "non-string key: %s" % key
		var cands: Variant = book[key]
		if typeof(cands) != TYPE_ARRAY:
			return "candidates for %s is not an Array" % key
		if (cands as Array).is_empty():
			return "empty candidate list at %s" % key
		for cand in cands:
			if typeof(cand) != TYPE_DICTIONARY:
				return "candidate at %s is not a Dictionary" % key
			if not cand.has("usi") or not cand.has("weight"):
				return "candidate at %s missing usi/weight: %s" % [key, cand]
	return ""

func _test_positions_parse(book: Dictionary) -> String:
	for key in book.keys():
		var c: Object = ClassDB.instantiate("ShogiCore")
		# position_key omits the ply counter; load_sfen requires it.
		if not bool(c.load_sfen("%s 1" % key)):
			return "load_sfen failed for: %s" % key
	return ""

func _test_candidates_legal(book: Dictionary) -> String:
	for key in book.keys():
		for cand in book[key]:
			var c: Object = ClassDB.instantiate("ShogiCore")
			if not bool(c.load_sfen("%s 1" % key)):
				return "setup load_sfen failed for: %s" % key
			var mv: Dictionary = _parse_usi(String(cand.usi))
			if mv.is_empty():
				return "unparseable USI %s at %s" % [cand.usi, key]
			if not bool(c.apply_move(mv)):
				return "illegal move %s at %s" % [cand.usi, key]
	return ""

func _test_weights(book: Dictionary) -> String:
	for key in book.keys():
		for cand in book[key]:
			var w: Variant = cand.weight
			if typeof(w) != TYPE_INT and typeof(w) != TYPE_FLOAT:
				return "non-numeric weight on %s @ %s" % [cand.usi, key]
			if int(w) <= 0:
				return "non-positive weight %d on %s @ %s" % [int(w), cand.usi, key]
	return ""

func _test_unique(book: Dictionary) -> String:
	for key in book.keys():
		var seen: Dictionary = {}
		for cand in book[key]:
			var u := String(cand.usi)
			if seen.has(u):
				return "duplicate USI %s at %s" % [u, key]
			seen[u] = true
	return ""

# -----------------------------------------------------------------------------

# Mirrors tools/gen_opening_book.gd's _apply_usi parser, but returns a
# move dict instead of mutating a board. The two stay in lockstep — if
# you teach the generator a new USI shape, teach this one too.
func _parse_usi(usi: String) -> Dictionary:
	var bytes := usi.to_ascii_buffer()
	if bytes.size() < 4:
		return {}
	if bytes[1] == 0x2A:  # '*' → drop, e.g. "P*5e"
		var kind := -1
		match bytes[0]:
			0x50: kind = PieceScript.Kind.PAWN
			0x4C: kind = PieceScript.Kind.LANCE
			0x4E: kind = PieceScript.Kind.KNIGHT
			0x53: kind = PieceScript.Kind.SILVER
			0x47: kind = PieceScript.Kind.GOLD
			0x42: kind = PieceScript.Kind.BISHOP
			0x52: kind = PieceScript.Kind.ROOK
			_:    return {}
		var to := _square(bytes[2], bytes[3])
		if to == Vector2i.ZERO:
			return {}
		return {drop_kind = kind, to = to}
	var from := _square(bytes[0], bytes[1])
	var to := _square(bytes[2], bytes[3])
	if from == Vector2i.ZERO or to == Vector2i.ZERO:
		return {}
	return {from = from, to = to, promote = bytes.size() == 5 and bytes[4] == 0x2B}

func _square(file_byte: int, rank_byte: int) -> Vector2i:
	if file_byte < 0x31 or file_byte > 0x39 or rank_byte < 0x61 or rank_byte > 0x69:
		return Vector2i.ZERO
	return Vector2i(file_byte - 0x30, rank_byte - 0x60)
