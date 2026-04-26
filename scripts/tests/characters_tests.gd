extends SceneTree

# Character roster + profile validity. Run headless:
#   godot --headless -s res://scripts/tests/characters_tests.gd
#
# Catches regressions in:
# - _settings.list_characters discovery (Android-specific .tres.remap
#   handling already broke the picker once; a test would have caught
#   it instantly)
# - profile field shape (level in 1..8, playouts > 0, portrait_dir
#   pointing at a real directory)
# - _settings.load_character lookup
# - sort order (weakest -> strongest)

const _EXPECTED_LEVELS := [1, 2, 3, 4, 5, 6, 7, 8]
const _SettingsScript := preload("res://scripts/autoload/Settings.gd")

var _fails: int = 0
var _settings: Node

func _initialize() -> void:
	# SceneTree subclasses run without the project's autoloads bound, so
	# instantiate Settings directly rather than reaching for a global.
	_settings = _SettingsScript.new()
	_run("list_characters returns 8 entries", _test_count)
	_run("list_characters is sorted by level ascending", _test_sort_order)
	_run("each level 1..8 has exactly one character", _test_levels_unique)
	_run("every profile has non-empty id and display_name", _test_required_fields)
	_run("playouts > 0 and temperature in [0, 2]", _test_strength_dials)
	_run("portrait_dir points at an existing directory", _test_portrait_dirs)
	_run("load_character round-trips by id", _test_load_by_id)
	_run("load_character returns null for unknown id", _test_load_unknown)
	if _fails > 0:
		push_error("FAILED %d test(s)" % _fails)
		quit(1)
	else:
		print("All character tests passed.")
		quit()

func _run(name: String, fn: Callable) -> void:
	var err: String = fn.call()
	if err == "":
		print("  ok    %s" % name)
	else:
		_fails += 1
		push_error("  FAIL  %s — %s" % [name, err])

func _test_count() -> String:
	var chars: Array[CharacterProfile] = _settings.list_characters()
	if chars.size() != 8:
		return "expected 8 characters, got %d" % chars.size()
	return ""

func _test_sort_order() -> String:
	var chars: Array[CharacterProfile] = _settings.list_characters()
	for i in chars.size() - 1:
		if chars[i].level > chars[i + 1].level:
			return "out of order at index %d: Lv%d > Lv%d" % [
				i, chars[i].level, chars[i + 1].level]
	return ""

func _test_levels_unique() -> String:
	var chars: Array[CharacterProfile] = _settings.list_characters()
	var seen := {}
	for c in chars:
		if seen.has(c.level):
			return "duplicate Lv%d (%s and %s)" % [
				c.level, seen[c.level], c.id]
		seen[c.level] = c.id
	for lvl in _EXPECTED_LEVELS:
		if not seen.has(lvl):
			return "no character at Lv%d" % lvl
	return ""

func _test_required_fields() -> String:
	for c in _settings.list_characters():
		if c.id == "":
			return "empty id on a profile (display_name=%s)" % c.display_name
		if c.display_name == "":
			return "empty display_name on id=%s" % c.id
	return ""

func _test_strength_dials() -> String:
	for c in _settings.list_characters():
		if c.playouts <= 0:
			return "%s: playouts=%d" % [c.id, c.playouts]
		if c.temperature < 0.0 or c.temperature > 2.0:
			return "%s: temperature=%.2f outside [0, 2]" % [c.id, c.temperature]
	return ""

func _test_portrait_dirs() -> String:
	for c in _settings.list_characters():
		if c.portrait_dir == "":
			return "%s: empty portrait_dir" % c.id
		if not DirAccess.dir_exists_absolute(c.portrait_dir):
			return "%s: portrait_dir missing on disk: %s" % [
				c.id, c.portrait_dir]
	return ""

func _test_load_by_id() -> String:
	for c in _settings.list_characters():
		var loaded: CharacterProfile = _settings.load_character(c.id)
		if loaded == null:
			return "load_character(%s) returned null" % c.id
		if loaded.id != c.id:
			return "load_character(%s) returned id=%s" % [c.id, loaded.id]
	return ""

func _test_load_unknown() -> String:
	if _settings.load_character("definitely-not-a-real-character") != null:
		return "expected null for unknown id"
	if _settings.load_character("") != null:
		return "expected null for empty id"
	return ""
