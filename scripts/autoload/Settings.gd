extends Node

# Session-wide user settings. Read by Main.tscn's GameController on start.
# Populated by MainMenu.tscn when the user picks a mode.

enum Mode { H_VS_H, H_VS_AI_SENTE, H_VS_AI_GOTE }

var mode: int = Mode.H_VS_AI_GOTE
var ai_playouts: int = 128
var model_res_path: String = "res://models/bonanza.onnx"

# Populated by MainMenu when the user picks 続きから; consumed once by
# GameController._ready. Empty string = start from the standard position.
var resume_sfen: String = ""

const SAVE_PATH := "user://saved_game.cfg"
const PREFS_PATH := "user://prefs.cfg"

# User preferences that outlive a single game. Loaded once in _ready
# and written back via set_teacher_side().
var teacher_side: String = "right"  # "left" or "right"

func _ready() -> void:
	_load_prefs()

func set_teacher_side(side: String) -> void:
	if side != "left" and side != "right":
		return
	if side == teacher_side:
		return
	teacher_side = side
	_save_prefs()

func _load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PREFS_PATH) != OK:
		return
	var side := str(cfg.get_value("ui", "teacher_side", "right"))
	if side == "left" or side == "right":
		teacher_side = side

func _save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "teacher_side", teacher_side)
	var err: int = cfg.save(PREFS_PATH)
	if err != OK:
		push_warning("save_prefs: ConfigFile.save returned %d" % err)

func ai_plays_gote() -> bool:
	return mode == Mode.H_VS_AI_GOTE

func ai_plays_sente() -> bool:
	return mode == Mode.H_VS_AI_SENTE

func side_is_ai(is_gote: bool) -> bool:
	return (is_gote and ai_plays_gote()) or (not is_gote and ai_plays_sente())

# --- save / resume ---------------------------------------------------------

func has_saved_game() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game(sfen: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "sfen", sfen)
	cfg.set_value("game", "mode", mode)
	cfg.set_value("game", "playouts", ai_playouts)
	var err: int = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("save_game: ConfigFile.save returned %d" % err)

# Returns {sfen, mode, playouts} on success, or an empty Dictionary on
# failure (corrupt / missing file).
func load_saved_game() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return {}
	return {
		sfen = str(cfg.get_value("game", "sfen", "")),
		mode = int(cfg.get_value("game", "mode", Mode.H_VS_AI_GOTE)),
		playouts = int(cfg.get_value("game", "playouts", 128)),
	}

func clear_saved_game() -> void:
	if has_saved_game():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

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
