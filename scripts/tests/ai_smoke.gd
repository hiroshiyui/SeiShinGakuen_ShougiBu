extends SceneTree

# End-to-end AI smoke test: load model, ask for one move from the starting
# position with a tiny playout budget, assert the returned move is legal.

func _initialize() -> void:
	if not ClassDB.class_exists("ShogiCore"):
		push_error("ShogiCore not registered")
		quit(1); return
	var core: Object = ClassDB.instantiate("ShogiCore")
	var abs_path: String = Settings.model_absolute_path()
	print("loading model from: %s" % abs_path)
	var t0 := Time.get_ticks_msec()
	if not bool(core.load_model(abs_path)):
		push_error("load_model failed")
		quit(1); return
	print("model loaded in %d ms" % (Time.get_ticks_msec() - t0))

	t0 = Time.get_ticks_msec()
	var mv: Variant = core.think_best_move(32)
	var dt := Time.get_ticks_msec() - t0
	print("think_best_move(32) took %d ms -> %s" % [dt, mv])
	if mv == null:
		push_error("AI returned no move")
		quit(1); return
	# Verify the returned move is legal.
	var legal_ok := false
	if mv.has("drop_kind"):
		var drops: Array = core.legal_drops(int(mv["drop_kind"]))
		for m in drops:
			if Vector2i(m["to"]) == Vector2i(mv["to"]):
				legal_ok = true; break
	else:
		var from: Vector2i = Vector2i(mv["from"])
		var moves: Array = core.legal_moves_from(from.x, from.y)
		for m in moves:
			if Vector2i(m["to"]) == Vector2i(mv["to"]) and bool(m.get("promote", false)) == bool(mv.get("promote", false)):
				legal_ok = true; break
	if not legal_ok:
		push_error("AI returned an illegal move: %s" % mv)
		quit(1); return
	print("AI smoke ok")
	quit()
