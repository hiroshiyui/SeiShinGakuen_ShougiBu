extends SceneTree

# Sanity-test the shipped 詰将棋 set (assets/tsume.json) against the
# mate solver, so a bad regeneration can't ship an unsolvable problem:
#  - parses as a non-empty JSON list of {sfen, plies}
#  - every length is 1, 3 or 5 and every position parses as SFEN
#  - the attacker (先手) is to move and is not in check
#  - the shortest forced mate is exactly the stated length
#  - exactly one first move works (no 余詰 at move one)
#  - no position appears twice
#  - following the solver's line through tsume_defense ends in mate
#
# Run:
#   ~/.local/bin/Godot_v4.7.2-stable_linux.x86_64 --headless \
#     -s res://scripts/tests/tsume_tests.gd --path .

const PROBLEMS_PATH := "res://assets/tsume.json"

var _fails: int = 0
var _core: Object

func _initialize() -> void:
	if not ClassDB.class_exists("ShogiCore"):
		push_error("ShogiCore class not registered — GDExtension not loaded")
		quit(1)
		return
	_core = ClassDB.instantiate("ShogiCore")
	var problems: Variant = _load()
	if typeof(problems) != TYPE_ARRAY:
		quit(1)
		return
	_run("set is non-empty and well-formed", _test_shape.bind(problems))
	_run("every position parses, 先手 to move, not in check", _test_positions.bind(problems))
	_run("no duplicate positions", _test_unique.bind(problems))
	_run("shortest mate matches the stated length, one first move", _test_solutions.bind(problems))
	_run("solver line through tsume_defense ends in mate", _test_playthrough.bind(problems))
	if _fails > 0:
		push_error("FAILED %d test(s)" % _fails)
		quit(1)
	else:
		print("All tsume tests passed.")
		quit(0)

func _load() -> Variant:
	var f := FileAccess.open(PROBLEMS_PATH, FileAccess.READ)
	if f == null:
		push_error("cannot open %s" % PROBLEMS_PATH)
		return null
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return data

func _run(name: String, fn: Callable) -> void:
	var err: String = fn.call()
	if err == "":
		print("  ok  — %s" % name)
	else:
		_fails += 1
		print("  FAIL — %s: %s" % [name, err])

func _test_shape(problems: Array) -> String:
	if problems.is_empty():
		return "no problems"
	for i in problems.size():
		var p: Variant = problems[i]
		if typeof(p) != TYPE_DICTIONARY or not p.has("sfen") or not p.has("plies"):
			return "entry %d is not {sfen, plies}" % i
		if not (int(p["plies"]) in [1, 3, 5]):
			return "entry %d: plies %s" % [i, p["plies"]]
	return ""

func _test_positions(problems: Array) -> String:
	for i in problems.size():
		var sfen := str(problems[i]["sfen"])
		if not bool(_core.load_sfen(sfen)):
			return "entry %d: bad sfen %s" % [i, sfen]
		if bool(_core.side_to_move_gote()):
			return "entry %d: 後手 to move" % i
		if bool(_core.is_check()):
			return "entry %d: attacker starts in check" % i
	return ""

func _test_unique(problems: Array) -> String:
	var seen := {}
	for i in problems.size():
		var key := str(problems[i]["sfen"]).rsplit(" ", true, 1)[0]
		if seen.has(key):
			return "entry %d repeats entry %d" % [i, seen[key]]
		seen[key] = i
	return ""

func _test_solutions(problems: Array) -> String:
	for i in problems.size():
		_core.load_sfen(str(problems[i]["sfen"]))
		var want := int(problems[i]["plies"])
		var r: Dictionary = _core.tsume_solve(want, 0)
		if int(r["plies"]) != want:
			return "entry %d: stated %d手, solver found %d" % [i, want, int(r["plies"])]
		if not bool(r["unique"]):
			return "entry %d: more than one first move mates" % i
	return ""

func _test_playthrough(problems: Array) -> String:
	for i in problems.size():
		_core.load_sfen(str(problems[i]["sfen"]))
		var left := int(problems[i]["plies"])
		var mated := false
		while left > 0 and not mated:
			var r: Dictionary = _core.tsume_solve(left, 0)
			var line: Array = r["solution"]
			if line.is_empty():
				return "entry %d: no line with %d plies left" % [i, left]
			_core.apply_move(line[0])
			left -= 1
			var verdict: Dictionary = _core.tsume_defense(left)
			match str(verdict["status"]):
				"mate":
					mated = true
				"continue":
					_core.apply_move(verdict["reply"])
					left -= 1
				_:
					return "entry %d: solver move judged %s" % [i, verdict["status"]]
		if not mated:
			return "entry %d: ran out of plies without mate" % i
	return ""
