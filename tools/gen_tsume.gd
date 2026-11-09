extends SceneTree

# Build assets/tsume.json: 詰将棋 problems mined from self-play.
#
# Plays fast, sloppy games by sampling the policy network (no search),
# and at every position asks the mate solver (ShogiCore.tsume_solve)
# whether the side to move has a forced mate in 1, 3 or 5 with exactly
# one correct first move. Matches are stored attacker-as-先手 (the board
# is flipped when 後手 was the attacker). These are 実戦詰め — positions
# from real play, not composed problems — so the whole board is shown.
#
# Only the position and the length are stored; the game re-solves at
# runtime to judge the player's moves and to pick the defender's reply.
#
# Run (takes a few minutes; output is random, so commit the result):
#   godot --headless -s res://tools/gen_tsume.gd --path .

const OUT_PATH := "res://assets/tsume.json"
const MODEL_PATH := "res://models/bonanza.onnx"
const TARGETS := {1: 40, 3: 60, 5: 60}
const MAX_GAMES := 4000
const MAX_PLIES := 220
# Don't look for mates in the opening, and after taking a problem skip
# ahead so one game doesn't yield the same mate at 5, 3 and 1.
const FIRST_PLY := 30
const SKIP_AFTER_HIT := 8
# Sample among the policy's top moves; higher temperature = sloppier
# play = more mating chances.
# Search effort per position. Small on purpose: it keeps generation
# fast and biases the set toward clean mates the phone can re-verify
# instantly.
const SOLVE_NODES := 4000
const TOP_K := 6
const TEMPERATURE := 1.3

func _initialize() -> void:
	var core: Object = ClassDB.instantiate("ShogiCore")
	if not bool(core.load_model(ProjectSettings.globalize_path(MODEL_PATH))):
		push_error("cannot load %s" % MODEL_PATH)
		quit(1)
		return
	var found := {1: [], 3: [], 5: []}
	var seen := {}
	var games := 0
	while games < MAX_GAMES and not _done(found):
		games += 1
		core.reset_starting()
		var skip_until := FIRST_PLY
		for ply in MAX_PLIES:
			if ply >= skip_until and not bool(core.is_check()):
				var r: Dictionary = core.tsume_solve(5, SOLVE_NODES)
				var n := int(r["plies"])
				if n > 0 and bool(r["unique"]) and found[n].size() < int(TARGETS[n]):
					var sfen := str(core.sfen_flipped()) if bool(core.side_to_move_gote()) \
						else str(core.to_sfen())
					var key := sfen.rsplit(" ", true, 1)[0]
					if not seen.has(key):
						seen[key] = true
						found[n].append({sfen = sfen, plies = n})
						skip_until = ply + SKIP_AFTER_HIT
			var mv: Variant = _sample_move(core)
			if mv == null or not bool(core.apply_move(mv)):
				break
		if games % 25 == 0:
			print("games=%d  1手=%d 3手=%d 5手=%d" % [
				games, found[1].size(), found[3].size(), found[5].size()])
	var out: Array = []
	for n in [1, 3, 5]:
		out.append_array(found[n])
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  ") + "\n")
	f.close()
	print("wrote %d problems to %s after %d games" % [out.size(), OUT_PATH, games])
	quit()

func _done(found: Dictionary) -> bool:
	for n in TARGETS:
		if found[n].size() < int(TARGETS[n]):
			return false
	return true

func _sample_move(core: Object) -> Variant:
	var top: Array = core.suggest_moves(TOP_K)
	if top.is_empty():
		return null
	var weights: Array[float] = []
	var total := 0.0
	for m in top:
		var w := pow(maxf(float(m.get("score", 0.0)), 1e-6), 1.0 / TEMPERATURE)
		weights.append(w)
		total += w
	var r := randf() * total
	for i in top.size():
		r -= weights[i]
		if r <= 0.0:
			return top[i]
	return top[top.size() - 1]
