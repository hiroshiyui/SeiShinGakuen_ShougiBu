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
# Companion to resume_sfen — packed move log (one i32/move) so resumed
# games rebuild their full 棋譜 history. Empty = legacy save / no log;
# GameController falls back to load_sfen and the kifu panel starts blank.
var resume_packed: PackedInt32Array = PackedInt32Array()
# Set by KifuLibrary when the player opens a saved game; consumed once
# by KifuReviewer._ready. Empty = no file selected (shouldn't happen in
# the supported flows but the reviewer will pop back to the library).
var review_kif_path: String = ""

# Path defaults for production. Tests override these via the
# `_set_storage_paths_for_test` seam below so they can round-trip
# through a sandboxed user://test_*.cfg file without trampling the
# real save / prefs.
var SAVE_PATH := "user://saved_game.cfg"
var PREFS_PATH := "user://prefs.cfg"

# Test-only seam. Production code must never call this.
func _set_storage_paths_for_test(save: String, prefs: String) -> void:
	SAVE_PATH = save
	PREFS_PATH = prefs

# User preferences that outlive a single game. Loaded once in _ready
# and written back via setter methods.
var teacher_side: String = "right"  # "left" or "right"
var selected_character_id: String = ""  # empty = no character picked yet (first launch)
var sound_enabled: bool = true

const CHARACTERS_DIR := "res://assets/characters"

func _ready() -> void:
	_load_prefs()

# Bridge Android's hardware/gesture back into the same `ui_cancel` action
# scenes already listen to via _unhandled_input. Without this, Godot 4's
# default `quit_on_go_back=true` would short-circuit straight to
# get_tree().quit(); we set quit_on_go_back=false in project.godot and
# synthesize the event here so MainMenu / GameController / KifuLibrary /
# etc. don't each need their own _notification handler.
#
# Why an InputEventKey(KEY_ESCAPE) and not InputEventAction("ui_cancel"):
# in Godot 4, parse_input_event for InputEventAction updates polling
# state but doesn't reliably propagate to _unhandled_input, so the
# Game / MainMenu handlers that check is_action_pressed never fired and
# the back gesture appeared to dump the player straight out of the app.
# A real key event is routed through the standard input pipeline and
# matches the desktop Esc binding for ui_cancel.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	var press := InputEventKey.new()
	press.keycode = KEY_ESCAPE
	press.physical_keycode = KEY_ESCAPE
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.keycode = KEY_ESCAPE
	release.physical_keycode = KEY_ESCAPE
	release.pressed = false
	Input.parse_input_event(release)

func set_teacher_side(side: String) -> void:
	if side != "left" and side != "right":
		return
	if side == teacher_side:
		return
	teacher_side = side
	_save_prefs()

func set_sound_enabled(enabled: bool) -> void:
	if enabled == sound_enabled:
		return
	sound_enabled = enabled
	_save_prefs()

func set_selected_character_id(cid: String) -> void:
	if cid == selected_character_id:
		return
	selected_character_id = cid
	_save_prefs()

# Cached at first scan — character .tres files are bundled in the APK
# and don't change at runtime, so re-walking the dir on every lookup is
# wasted work (matters more once load_character is on hot paths like
# scene change or label refresh).
var _characters_cache: Array[CharacterProfile] = []
var _characters_loaded: bool = false

# Walk CHARACTERS_DIR for every .tres and return a typed list.
# Missing dir / corrupt files are skipped silently (no characters yet
# on a fresh checkout is a valid state).
func list_characters() -> Array[CharacterProfile]:
	if _characters_loaded:
		return _characters_cache
	var out: Array[CharacterProfile] = []
	var roots := ["teachers", "students"]
	for sub in roots:
		var dir := "%s/%s" % [CHARACTERS_DIR, sub]
		# Operate on the res:// path directly. globalize_path returns a
		# non-existent OS path on Android because res:// lives inside the
		# PCK; DirAccess.open is the call that knows how to talk to the
		# virtual filesystem.
		var d := DirAccess.open(dir)
		if d == null:
			push_warning("list_characters: cannot open %s" % dir)
			continue
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			# On Android the on-disk file is `<name>.tres.remap` (Godot
			# rewrites resource paths during export); the load() call
			# still uses the original .tres path. Match either suffix.
			if (name.ends_with(".tres") or name.ends_with(".tres.remap")) \
					and not d.current_is_dir():
				var base := name.trim_suffix(".remap")
				var res = load("%s/%s" % [dir, base])
				if res is CharacterProfile:
					out.append(res)
			name = d.get_next()
	# Picker shows weakest → strongest (Lv 1 left-top, Lv 8 right-bottom).
	out.sort_custom(func(a, b): return a.level < b.level)
	_characters_cache = out
	_characters_loaded = true
	return _characters_cache

# Pick a character: persist the id and snap ai_level to the character's
# tier so the MCTS strength matches the avatar the player sees. Bypasses
# the per-field setters so prefs.cfg is rewritten once, not twice.
func select_character(profile: CharacterProfile) -> void:
	if profile == null:
		return
	var new_level := clamp_level(profile.level)
	if profile.id == selected_character_id and new_level == ai_level:
		return
	selected_character_id = profile.id
	ai_level = new_level
	_save_prefs()

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
	sound_enabled = bool(cfg.get_value("audio", "sound_enabled", true))

func _save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "teacher_side", teacher_side)
	cfg.set_value("ai", "character_id", selected_character_id)
	cfg.set_value("ai", "level", ai_level)
	cfg.set_value("audio", "sound_enabled", sound_enabled)
	var err: int = cfg.save(PREFS_PATH)
	if err != OK:
		push_warning("save_prefs: ConfigFile.save returned %d" % err)

# Rank-kanji table — index by 1..9 to convert a board rank into its
# 漢数字 form (``5 → "五"``). Indexed at 0 returns "" so the lookup is
# safe for "no rank" / placeholder inputs. Lives here because three
# scenes (GameController promo dialog + status, KifuReviewer kifu
# rendering) need the same table.
const RANK_KANJI: Array[String] = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

# Apply the safe-area inset (computed by safe_area_insets below) to a
# Control's offset_* properties. Pure boilerplate that every fullscreen
# scene needs after the autoload split — call this in `_ready` and on
# every `viewport.size_changed`. The node is typed loosely as Control
# so callers can pass a VBoxContainer / MarginContainer / plain Control
# without an upcast.
func apply_safe_area_to(node: Control) -> void:
	if node == null:
		return
	var insets: Rect2 = safe_area_insets(get_tree().root.size)
	node.offset_left = insets.position.x
	node.offset_top = insets.position.y
	node.offset_right = -insets.size.x
	node.offset_bottom = -insets.size.y

# Compute the per-side inset (left, top, right, bottom) a fullscreen
# Control should apply so content clears the OS status bar / gesture
# nav / camera cutout. Mirrors GameController._apply_safe_area; pulled
# onto Settings so KifuLibrary / KifuReviewer / future fullscreen
# screens can call the same logic without duplicating code.
func safe_area_insets(viewport_size: Vector2) -> Rect2:
	const EXTRA_H := 12.0
	const EXTRA_TOP := 16.0
	const EXTRA_BOTTOM := 32.0
	var top := EXTRA_TOP
	var bottom := EXTRA_BOTTOM
	var left := EXTRA_H
	var right := EXTRA_H
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	if safe.size != Vector2i.ZERO and screen_size != Vector2i.ZERO and viewport_size.y > 0:
		var sy: float = viewport_size.y / float(screen_size.y)
		top += float(safe.position.y) * sy
		bottom += float(screen_size.y - safe.position.y - safe.size.y) * sy
	# Horizontal inset stays fixed — Android sometimes reports a non-zero
	# safe.position.x for gesture nav / foldable hinges that would shift
	# layouts sideways in portrait mode.
	return Rect2(left, top, right, bottom)

func ai_plays_gote() -> bool:
	return mode == Mode.H_VS_AI_GOTE

func ai_plays_sente() -> bool:
	return mode == Mode.H_VS_AI_SENTE

func side_is_ai(is_gote: bool) -> bool:
	return (is_gote and ai_plays_gote()) or (not is_gote and ai_plays_sente())

# --- save / resume ---------------------------------------------------------

func has_saved_game() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game(sfen: String, packed_log: PackedInt32Array = PackedInt32Array()) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "sfen", sfen)
	cfg.set_value("game", "mode", mode)
	cfg.set_value("game", "level", ai_level)
	cfg.set_value("game", "character_id", selected_character_id)
	# Packed move log replays the entire game on resume so the 棋譜 panel
	# survives "続きから". Falling back to SFEN-only is harmless — review
	# just shows an empty kifu — so older saves keep loading.
	cfg.set_value("game", "packed_log", packed_log)
	var err: int = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("save_game: ConfigFile.save returned %d" % err)

# Returns {sfen, mode, level, character_id, packed_log} on success, or an
# empty Dictionary on failure (corrupt / missing file). Older saves omit
# `character_id` (added 2026-04-27) and `packed_log` (added 2026-04-28);
# the loader supplies "" / empty PackedInt32Array so callers can detect
# the legacy state and fall back to SFEN-only resume (no kifu history).
func load_saved_game() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return {}
	return {
		sfen = str(cfg.get_value("game", "sfen", "")),
		mode = int(cfg.get_value("game", "mode", Mode.H_VS_AI_GOTE)),
		level = clamp_level(int(cfg.get_value("game", "level", ai_level))),
		character_id = str(cfg.get_value("game", "character_id", "")),
		packed_log = PackedInt32Array(cfg.get_value("game", "packed_log", PackedInt32Array())),
	}

func clear_saved_game() -> void:
	# user:// is a real OS path on Android, but DirAccess accepts the
	# virtual URL directly — keeps the call symmetric with file_exists
	# above and avoids the trap of copying this pattern onto a res://
	# path (which would fail silently on device).
	if has_saved_game():
		DirAccess.remove_absolute(SAVE_PATH)

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
		if not _atomic_copy_resource(res_path, user_path):
			return ""
	return ProjectSettings.globalize_path(user_path)

# Atomic-ish copy of a res:// resource to a user:// destination.
# Writes <dst>.tmp first, then renames. If the process is killed
# mid-copy (Android can do this freely), the next launch sees no
# file at the canonical path and re-extracts instead of mmap'ing a
# partial blob — tract would error on a partial ONNX with no
# recovery short of clearing app data.
#
# Exposed at module scope so tests can drive it directly with
# arbitrary src/dst paths (model_absolute_path itself short-circuits
# on `editor` builds and isn't exercisable from a desktop test).
# Returns true on success.
func _atomic_copy_resource(src_path: String, dst_path: String) -> bool:
	var tmp_path: String = dst_path + ".tmp"
	var src: FileAccess = FileAccess.open(src_path, FileAccess.READ)
	if src == null:
		push_error("atomic_copy: cannot open %s" % src_path)
		return false
	var bytes: PackedByteArray = src.get_buffer(src.get_length())
	src.close()
	var dst: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if dst == null:
		push_error("atomic_copy: cannot write %s" % tmp_path)
		return false
	dst.store_buffer(bytes)
	dst.close()
	var rename_err: int = DirAccess.rename_absolute(tmp_path, dst_path)
	if rename_err != OK:
		push_error("atomic_copy: rename %s -> %s failed (%d)" %
			[tmp_path, dst_path, rename_err])
		DirAccess.remove_absolute(tmp_path)
		return false
	return true
