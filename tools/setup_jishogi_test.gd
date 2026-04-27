extends SceneTree

# Build the "qualified sente declarer" position from rules.rs's tests
# (sente king at 5-1 + 12 own pieces in rank 1-2 worth 28 pts) and write
# it as a saved_game.cfg so the running app can load it via 続きから.
#
# Run headless:
#   godot --headless -s res://tools/setup_jishogi_test.gd --path .
#
# Output:
#   user://saved_game.cfg
#     (= ~/.local/share/godot/app_userdata/<proj>/saved_game.cfg on Linux)
#
# Push to device with:
#   cat <output> | adb shell "run-as org.seishingakuen.shougibu sh -c 'cat > files/saved_game.cfg'"
#
# Then on the device: tap 続きから → board loads at the test position.
# Tap 入玉宣言 → game ends with "入玉宣言 — 先手の勝ち".

func _initialize() -> void:
	if not ClassDB.class_exists("ShogiCore"):
		push_error("ShogiCore not registered — build the desktop .so first")
		quit(1)
		return
	var core = ClassDB.instantiate("ShogiCore")
	core.clear_board()
	# Sente king at 5-1
	core.place(5, 1, 7, false)  # Kind::King = 7, is_gote = false
	# Big pieces (5 pts each) — rooks / bishops / dragon / horse
	core.place(1, 1, 6, false)   # Rook
	core.place(9, 1, 5, false)   # Bishop
	core.place(1, 2, 13, false)  # Dragon
	core.place(9, 2, 12, false)  # Horse
	# Small pieces (1 pt each)
	core.place(2, 1, 4, false)   # Gold
	core.place(3, 1, 4, false)   # Gold
	core.place(4, 1, 3, false)   # Silver
	core.place(6, 1, 3, false)   # Silver
	core.place(7, 1, 2, false)   # Knight
	core.place(8, 1, 2, false)   # Knight
	core.place(2, 2, 1, false)   # Lance
	core.place(8, 2, 1, false)   # Lance
	# Lone gote king out of any sente attack range
	core.place(5, 9, 7, true)
	core.set_side_to_move_gote(false)
	core.seal_initial_position()

	var sfen: String = String(core.to_sfen())
	print("constructed SFEN: ", sfen)
	print("can_declare_jishogi(false) = ", core.can_declare_jishogi(false))

	# Mirror Settings.save_game so the file shape matches what
	# load_saved_game expects. mode=0 = H_VS_H (no AI thinking on launch).
	var cfg := ConfigFile.new()
	cfg.set_value("game", "sfen", sfen)
	cfg.set_value("game", "mode", 0)
	cfg.set_value("game", "level", 4)
	cfg.set_value("game", "character_id", "")
	cfg.set_value("game", "packed_log", PackedInt32Array())
	var out_path := "user://saved_game.cfg"
	var err := cfg.save(out_path)
	if err != OK:
		push_error("failed to save: %d" % err)
		quit(1)
		return
	print("wrote ", ProjectSettings.globalize_path(out_path))
	quit()
