extends Node

# Session-wide user settings. Read by Main.tscn's GameController on start.
# Populated by MainMenu.tscn when the user picks a mode.

enum Mode { H_VS_H, H_VS_AI_SENTE, H_VS_AI_GOTE }

var mode: int = Mode.H_VS_AI_GOTE
var ai_level: int = 4  # 1..8, see LEVEL_PARAMS
var model_res_path: String = "res://models/bonanza.onnx"

const MIN_LEVEL := 1
const MAX_LEVEL := 8

# Strength presets for the menu's Lv1–Lv8 selector. Visit count grows
# geometrically (deeper search = stronger play); temperature decays from
# very-random at Lv1 to greedy at Lv8 so weaker levels actually make
# plausible-looking mistakes instead of just playing slower.
const LEVEL_PARAMS := [
	{},                                              # 0 unused (1-indexed)
	{playouts = 16,   temperature = 2.0},  # Lv 1
	{playouts = 32,   temperature = 1.5},  # Lv 2
	{playouts = 64,   temperature = 1.2},  # Lv 3
	{playouts = 128,  temperature = 0.8},  # Lv 4
	{playouts = 256,  temperature = 0.5},  # Lv 5
	{playouts = 512,  temperature = 0.3},  # Lv 6
	{playouts = 1024, temperature = 0.1},  # Lv 7
	{playouts = 2048, temperature = 0.0},  # Lv 8
]

# Display names for each strength tier, shown on the main-title level
# picker and (future) in-game opponent labels. Aligned 1:1 with LEVEL_PARAMS.
const LEVEL_NAMES := [
	"",                    # 0 unused
	"佐藤竜太郎",           # Lv 1
	"鈴木すず",             # Lv 2
	"高橋ゆり子",           # Lv 3
	"伊藤明",               # Lv 4
	"中村アリス",           # Lv 5
	"テリー・クラーク",     # Lv 6
	"吉田なな",             # Lv 7
	"加藤よしこ",           # Lv 8
]

func clamp_level(lvl: int) -> int:
	return clampi(lvl, MIN_LEVEL, MAX_LEVEL)

func level_params(lvl: int) -> Dictionary:
	return LEVEL_PARAMS[clamp_level(lvl)]

func level_name(lvl: int) -> String:
	return LEVEL_NAMES[clamp_level(lvl)]

func set_ai_level(lvl: int) -> void:
	var l := clamp_level(lvl)
	if l == ai_level:
		return
	ai_level = l
	_save_prefs()

# Populated by MainMenu when the user picks 続きから; consumed once by
# GameController._ready. Empty string = start from the standard position.
var resume_sfen: String = ""

const SAVE_PATH := "user://saved_game.cfg"
const PREFS_PATH := "user://prefs.cfg"

# User preferences that outlive a single game. Loaded once in _ready
# and written back via setter methods.
var teacher_side: String = "right"  # "left" or "right"
var selected_character_id: String = ""  # empty = use Settings.ai_playouts default

const CHARACTERS_DIR := "res://assets/characters"

func _ready() -> void:
	_load_prefs()

func set_teacher_side(side: String) -> void:
	if side != "left" and side != "right":
		return
	if side == teacher_side:
		return
	teacher_side = side
	_save_prefs()

func set_selected_character_id(cid: String) -> void:
	if cid == selected_character_id:
		return
	selected_character_id = cid
	_save_prefs()

# Walk CHARACTERS_DIR for every .tres and return a typed list.
# Missing dir / corrupt files are skipped silently (no characters yet
# on a fresh checkout is a valid state).
func list_characters() -> Array[CharacterProfile]:
	var out: Array[CharacterProfile] = []
	var roots := ["teachers", "students"]
	for sub in roots:
		var dir := "%s/%s" % [CHARACTERS_DIR, sub]
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
			continue
		var d := DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			if name.ends_with(".tres") and not d.current_is_dir():
				var res = load("%s/%s" % [dir, name])
				if res is CharacterProfile:
					out.append(res)
			name = d.get_next()
	return out

func load_character(cid: String) -> CharacterProfile:
	if cid == "":
		return null
	for c in list_characters():
		if c.id == cid:
			return c
	return null

func _load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PREFS_PATH) != OK:
		return
	var side := str(cfg.get_value("ui", "teacher_side", "right"))
	if side == "left" or side == "right":
		teacher_side = side
	selected_character_id = str(cfg.get_value("ai", "character_id", ""))
	ai_level = clamp_level(int(cfg.get_value("ai", "level", ai_level)))

func _save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "teacher_side", teacher_side)
	cfg.set_value("ai", "character_id", selected_character_id)
	cfg.set_value("ai", "level", ai_level)
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
	cfg.set_value("game", "level", ai_level)
	var err: int = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("save_game: ConfigFile.save returned %d" % err)

# Returns {sfen, mode, level} on success, or an empty Dictionary on
# failure (corrupt / missing file). Older saves only carried `playouts` —
# fall back to the current setting in that case.
func load_saved_game() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return {}
	return {
		sfen = str(cfg.get_value("game", "sfen", "")),
		mode = int(cfg.get_value("game", "mode", Mode.H_VS_AI_GOTE)),
		level = clamp_level(int(cfg.get_value("game", "level", ai_level))),
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
