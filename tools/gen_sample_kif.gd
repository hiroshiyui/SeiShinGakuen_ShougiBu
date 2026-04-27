extends SceneTree

# Drive the engine in self-play to produce a realistic mid-length game
# for KifuReviewer / analysis testing. Run headless:
#
#   godot --headless -s res://tools/gen_sample_kif.gd --path .
#
# Output:
#   user://sample_game.kif  (= ~/.local/share/godot/app_userdata/<proj>/sample_game.kif on Linux)
#
# Push to a connected Android device with:
#   adb push <output> /storage/emulated/0/Android/data/org.seishingakuen.shougibu/files/Documents/

const PLIES := 60
const PLAYOUTS := 96

func _initialize() -> void:
	if not ClassDB.class_exists("ShogiCore"):
		push_error("ShogiCore not registered — build the desktop .so first")
		quit(1)
		return
	var core = ClassDB.instantiate("ShogiCore")
	var model_path := ProjectSettings.globalize_path("res://models/bonanza.onnx")
	if not bool(core.load_model(model_path)):
		push_error("load_model failed: %s" % model_path)
		quit(1)
		return

	for i in range(PLIES):
		var mv = core.think_best_move(PLAYOUTS)
		if mv == null:
			print("no legal move at ply %d — game over" % (i + 1))
			break
		if not bool(core.apply_move(mv)):
			print("apply_move rejected at ply %d — aborting" % (i + 1))
			break
		if bool(core.is_checkmate()):
			print("checkmate at ply %d" % (i + 1))
			break

	var kif: String = String(core.to_kif("先手AI(Lv.4)", "後手AI(Lv.4)", "2026/04/28 23:00:00"))
	var out_path := "user://sample_game.kif"
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("cannot open %s for write" % out_path)
		quit(1)
		return
	f.store_string(kif)
	f.close()
	var abs_path := ProjectSettings.globalize_path(out_path)
	print("wrote %d bytes to %s" % [kif.length(), abs_path])
	quit()
