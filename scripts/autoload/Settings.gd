extends Node

# Session-wide user settings. Read by Main.tscn's GameController on start.
# Populated by MainMenu.tscn when the user picks a mode.

enum Mode { H_VS_H, H_VS_AI_SENTE, H_VS_AI_GOTE }

var mode: int = Mode.H_VS_AI_GOTE
var ai_level: int = 4  # 1..8, see LEVEL_PARAMS
var model_res_path: String = "res://models/bonanza.onnx"

const MIN_LEVEL := 1
const MAX_LEVEL := 8

# Fallback strength ladder, used only when no character profile is
# selected (first launch before the picker). Normally the selected
# CharacterProfile's own dials drive play — see ai_dials() below.
# Visit count grows geometrically (deeper search = stronger play);
# temperature decays from loose at Lv1 to greedy at Lv8 so weaker
# levels make plausible-looking mistakes instead of random ones.
#
# Budgets are sized for Bonanza v2 (10×128 residual net, ~5 ms per
# forward pass on desktop, several times that on arm64). The v1 ladder
# topped out at 2048 playouts; v2 is ~8× more expensive per playout but
# beat v1 208–0 at equal budgets, so the ladder was cut to keep Lv 8
# inside a few seconds per move while still being far stronger overall.
# The floor was raised (Lv1 8→32 playouts, temperature capped at 1.2)
# because 8 playouts at temperature 2.0 is close to picking a random
# legal move, which reads as broken rather than beginner-like.
const LEVEL_PARAMS := [
	{},                                              # 0 unused (1-indexed)
	{playouts = 32,   temperature = 1.2},  # Lv 1
	{playouts = 48,   temperature = 1.0},  # Lv 2
	{playouts = 64,   temperature = 0.8},  # Lv 3
	{playouts = 96,   temperature = 0.6},  # Lv 4
	{playouts = 128,  temperature = 0.4},  # Lv 5
	{playouts = 160,  temperature = 0.2},  # Lv 6
	{playouts = 192,  temperature = 0.1},  # Lv 7
	{playouts = 256,  temperature = 0.0},  # Lv 8
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

# Dials for the AI's next move: the selected character's weighted mood
# roll, or the fixed ladder entry when no character is selected.
func ai_dials() -> Dictionary:
	var profile := load_character(selected_character_id)
	if profile != null:
		return profile.roll_dials()
	return level_params(ai_level)

# The selected character's baseline (no mood roll) — for the teacher
# hint search, which should be steady rather than moody.
func ai_base_dials() -> Dictionary:
	var profile := load_character(selected_character_id)
	if profile != null:
		return profile.base_dials()
	return level_params(ai_level)

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
# Move (1-based ply) the reviewer should open on; -1 = the final
# position. Set together with review_kif_path, consumed by KifuReviewer.
var review_start_ply: int = -1

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
# Accessibility: collapse decorative tweens (board zoom, piece slide,
# panel fades) to instant. Feedback flashes stay — they carry meaning.
var reduce_motion: bool = false

# 詰将棋 progress. `tsume_plies` is the set the player last had open
# (1 / 3 / 5 手詰); `tsume_solved` holds the position key of every
# problem solved so far, so progress survives a regenerated problem
# set as long as the positions themselves are kept.
var tsume_plies: int = 1
var tsume_solved: Dictionary = {}

func set_tsume_plies(plies: int) -> void:
	if plies == tsume_plies:
		return
	tsume_plies = plies
	_save_prefs()

func mark_tsume_solved(position_key: String) -> void:
	if tsume_solved.has(position_key):
		return
	tsume_solved[position_key] = true
	_save_prefs()

# Player's results against each character: id -> {wins, losses}.
# Draws are not counted.
var character_records: Dictionary = {}

func character_record(cid: String) -> Dictionary:
	return character_records.get(cid, {"wins": 0, "losses": 0})

func record_character_result(cid: String, player_won: bool) -> void:
	if cid == "":
		return
	var rec: Dictionary = character_record(cid).duplicate()
	rec["wins" if player_won else "losses"] += 1
	character_records[cid] = rec
	_save_prefs()

const CHARACTERS_DIR := "res://assets/characters"

# Player avatars: student portraits the player picks to stand for
# themselves (own side of the board, and shown to a 通信対戦 peer).
# Listed here rather than scanned, because an exported PCK holds only
# the `.webp.import` remaps, and because a peer-sent id is checked
# against this list before it is turned into a path.
const AVATAR_DIR := "res://assets/characters/player_avatars"
const AVATAR_IDS: Array[String] = [
	"girl-01", "girl-02", "girl-03", "girl-04", "girl-05", "girl-06", "girl-07", "girl-08",
	"boy-01", "boy-02", "boy-03", "boy-04", "boy-05", "boy-06", "boy-07", "boy-08",
]
# "" = no avatar.
var avatar_id: String = ""
# True once the first-launch avatar picker has been shown, so it is
# offered exactly once (picking or skipping both count).
var avatar_prompted: bool = false

static func is_avatar_id(v: Variant) -> bool:
	return v is String and AVATAR_IDS.has(v)

# Portrait path for `aid` (neutral, or one of the five expressions as
# `<id>_<expr>.webp` beside it), or "" when it isn't a known avatar. The
# file may be missing for an expression; callers fall back to neutral.
static func avatar_path(aid: String, expr: String = "neutral") -> String:
	if not is_avatar_id(aid):
		return ""
	if expr == "neutral":
		return "%s/%s.webp" % [AVATAR_DIR, aid]
	return "%s/%s_%s.webp" % [AVATAR_DIR, aid, expr]

# The player's speech bank, by the avatar's style ("girl-03" -> female);
# null for no avatar.
const AVATAR_VOICES := {
	"girl": "res://assets/characters/player_avatars/voice_female.tres",
	"boy": "res://assets/characters/player_avatars/voice_male.tres",
}

static func avatar_voice(aid: String) -> SpeechBank:
	if not is_avatar_id(aid):
		return null
	return load(AVATAR_VOICES[aid.get_slice("-", 0)]) as SpeechBank

func set_avatar_id(aid: String) -> void:
	if aid != "" and not is_avatar_id(aid):
		return
	if aid == avatar_id:
		return
	avatar_id = aid
	_save_prefs()

func mark_avatar_prompted() -> void:
	if avatar_prompted:
		return
	avatar_prompted = true
	_save_prefs()

func _ready() -> void:
	_load_prefs()

# Android back gesture is handled per-scene now — each scene that
# needs it implements `_notification(NOTIFICATION_WM_GO_BACK_REQUEST)`
# directly, alongside its existing `_unhandled_input(ui_cancel)` for
# desktop Esc. Earlier revisions tried to synthesize an InputEventAction
# (didn't propagate to _unhandled_input in Godot 4) and then an
# InputEventKey(KEY_ESCAPE) — the latter worked in debug builds but
# release APKs intermittently dropped the synthesized press/release
# pair, so in-game back appeared to fall through to the OS default
# (app exit). Per-scene WM_GO_BACK_REQUEST handlers bypass the input
# synthesis entirely and behave the same in debug and release.

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

func set_reduce_motion(enabled: bool) -> void:
	if enabled == reduce_motion:
		return
	reduce_motion = enabled
	_save_prefs()

# Duration helper for decorative animations: 0 when reduce_motion is on.
# A zero-length Tween still fires `finished`, so callers that await it
# keep working.
func anim(duration: float) -> float:
	return 0.0 if reduce_motion else duration

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
	ai_level = clamp_level(_cfg_int(cfg, "ai", "level", ai_level))
	sound_enabled = _cfg_bool(cfg, "audio", "sound_enabled", true)
	reduce_motion = _cfg_bool(cfg, "ui", "reduce_motion", false)
	var aid: Variant = cfg.get_value("player", "avatar", "")
	avatar_id = aid if is_avatar_id(aid) else ""
	avatar_prompted = _cfg_bool(cfg, "player", "avatar_prompted", false)
	tsume_plies = _cfg_int(cfg, "tsume", "plies", tsume_plies)
	var solved: Variant = cfg.get_value("tsume", "solved", [])
	tsume_solved.clear()
	if solved is Array:
		for key in solved:
			tsume_solved[str(key)] = true
	var records: Variant = cfg.get_value("records", "characters", {})
	character_records.clear()
	if records is Dictionary:
		for cid in records:
			var rec: Variant = records[cid]
			if rec is Dictionary:
				character_records[str(cid)] = {
					"wins": _record_count(rec.get("wins", 0)),
					"losses": _record_count(rec.get("losses", 0)),
				}

# Typed reads for user-editable .cfg files. A wrong-typed value falls
# back to the default; int() / bool() on it would abort the whole load.
func _cfg_int(cfg: ConfigFile, section: String, key: String, default: int) -> int:
	var value: Variant = cfg.get_value(section, key, default)
	return value if value is int else default

func _cfg_bool(cfg: ConfigFile, section: String, key: String, default: bool) -> bool:
	var value: Variant = cfg.get_value(section, key, default)
	return value if value is bool else default

# A win/loss count read from prefs; anything but a non-negative int is 0.
func _record_count(value: Variant) -> int:
	return maxi(value, 0) if value is int else 0

func _save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "teacher_side", teacher_side)
	cfg.set_value("ai", "character_id", selected_character_id)
	cfg.set_value("ai", "level", ai_level)
	cfg.set_value("audio", "sound_enabled", sound_enabled)
	cfg.set_value("ui", "reduce_motion", reduce_motion)
	cfg.set_value("player", "avatar", avatar_id)
	cfg.set_value("player", "avatar_prompted", avatar_prompted)
	cfg.set_value("tsume", "plies", tsume_plies)
	cfg.set_value("tsume", "solved", tsume_solved.keys())
	cfg.set_value("records", "characters", character_records)
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
	# The viewport (canvas) size, not root.size: with canvas_items
	# stretch the window is in physical pixels, and insets computed
	# against it come out too large by the stretch factor (~1.5× on a
	# 1080-wide phone). Matches GameController / MoveHistoryDialog.
	var insets: Rect2 = safe_area_insets(node.get_viewport_rect().size)
	node.offset_left = insets.position.x
	node.offset_top = insets.position.y
	node.offset_right = -insets.size.x
	node.offset_bottom = -insets.size.y

# Compute the per-side inset (left, top, right, bottom) a fullscreen
# Control should apply so content clears the OS status bar / gesture
# nav / camera cutout. Top and bottom are symmetric in spirit: top
# clears the cutout, bottom clears the (hidden) navigation bar. Mirrors GameController._apply_safe_area; pulled
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
	# Physical height of the Android system navigation bar (3-button
	# mode; the gesture pill zone is smaller). With immersive_mode the
	# bar is hidden and DisplayServer's safe area only reports the top
	# camera cutout, so the bottom would otherwise get just EXTRA_BOTTOM
	# and content ends up under the gesture area. Reserve the bar height
	# as a floor so the bottom edge mirrors the top's cutout clearance.
	const NAV_BAR_DP := 48.0
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	if safe.size != Vector2i.ZERO and screen_size != Vector2i.ZERO and viewport_size.y > 0:
		var sy: float = viewport_size.y / float(screen_size.y)
		top += float(safe.position.y) * sy
		var reported_bottom: float = float(screen_size.y - safe.position.y - safe.size.y)
		var nav_bar_px: float = 0.0
		if OS.has_feature("android"):
			nav_bar_px = NAV_BAR_DP * DisplayServer.screen_get_dpi() / 160.0
		bottom += maxf(reported_bottom, nav_bar_px) * sy
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
	var saved_mode: int = _cfg_int(cfg, "game", "mode", Mode.H_VS_AI_GOTE)
	if not Mode.values().has(saved_mode):
		saved_mode = Mode.H_VS_AI_GOTE
	var packed: Variant = cfg.get_value("game", "packed_log", PackedInt32Array())
	return {
		sfen = str(cfg.get_value("game", "sfen", "")),
		mode = saved_mode,
		level = clamp_level(_cfg_int(cfg, "game", "level", ai_level)),
		character_id = str(cfg.get_value("game", "character_id", "")),
		packed_log = packed if packed is PackedInt32Array else PackedInt32Array(),
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
	if _needs_extract(res_path, user_path):
		if not _atomic_copy_resource(res_path, user_path):
			return ""
	return ProjectSettings.globalize_path(user_path)

# True when the user:// copy is missing or stale. "Stale" is decided
# by byte length: an app update that ships a different model under the
# same filename (v1 1.3 MB → v2 12 MB) must not keep serving the old
# extracted copy forever. Length is cheap and sufficient — two
# different trained networks with identical ONNX byte length is not a
# case worth hashing 12 MB on every launch for.
func _needs_extract(src_path: String, dst_path: String) -> bool:
	if not FileAccess.file_exists(dst_path):
		return true
	var src: FileAccess = FileAccess.open(src_path, FileAccess.READ)
	var dst: FileAccess = FileAccess.open(dst_path, FileAccess.READ)
	if src == null or dst == null:
		return true
	return src.get_length() != dst.get_length()

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
