extends Node

# Session-wide user settings. Read by Main.tscn's GameController on start.
# Populated by MainMenu.tscn when the user picks a mode.

enum Mode { H_VS_H, H_VS_AI_SENTE, H_VS_AI_GOTE }

var mode: int = Mode.H_VS_AI_GOTE
var ai_playouts: int = 128
var model_res_path: String = "res://models/bonanza.onnx"

func ai_plays_gote() -> bool:
	return mode == Mode.H_VS_AI_GOTE

func ai_plays_sente() -> bool:
	return mode == Mode.H_VS_AI_SENTE

func side_is_ai(is_gote: bool) -> bool:
	return (is_gote and ai_plays_gote()) or (not is_gote and ai_plays_sente())

# Return an absolute OS path to the ONNX model that `tract` can mmap.
#
# In the editor, `res://` is the real filesystem and we can globalize
# directly. In exported builds (Android especially), `res://` lives inside
# the PCK/APK and cannot be opened by native code — we extract to `user://`
# on first launch and hand back that path thereafter.
func model_absolute_path() -> String:
	var res_path: String = model_res_path
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path(res_path)
	var user_path: String = "user://%s" % res_path.get_file()
	if not FileAccess.file_exists(user_path):
		var src: FileAccess = FileAccess.open(res_path, FileAccess.READ)
		if src == null:
			push_error("model: cannot open %s" % res_path)
			return ""
		var bytes: PackedByteArray = src.get_buffer(src.get_length())
		src.close()
		var dst: FileAccess = FileAccess.open(user_path, FileAccess.WRITE)
		if dst == null:
			push_error("model: cannot write %s" % user_path)
			return ""
		dst.store_buffer(bytes)
		dst.close()
	return ProjectSettings.globalize_path(user_path)
