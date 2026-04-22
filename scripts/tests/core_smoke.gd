extends SceneTree

func _initialize() -> void:
	if not ClassDB.class_exists("ShogiCore"):
		push_error("ShogiCore class not registered — GDExtension not loaded")
		quit(1)
		return
	var core: Object = ClassDB.instantiate("ShogiCore")
	var msg: String = str(core.call("ping"))
	print("ping: %s" % msg)
	if msg != "shogi_core online":
		push_error("unexpected ping response: %s" % msg)
		quit(1)
		return
	print("core smoke ok")
	quit()
