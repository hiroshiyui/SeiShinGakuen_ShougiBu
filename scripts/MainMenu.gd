extends Control

@onready var _title: Label = %Title
@onready var _mode: OptionButton = %ModeSelect
@onready var _opponent_btn: Button = %OpponentButton
# The button's own text/icon stay empty: Godot can't centre an icon
# next to centred text, so a centred icon + label row sits inside it.
@onready var _opponent_icon: TextureRect = %OpponentIcon
@onready var _opponent_name: Label = %OpponentName
@onready var _start_btn: Button = %StartButton
@onready var _resume_btn: Button = %ResumeButton
@onready var _settings_btn: Button = %SettingsButton
@onready var _kifu_library_btn: Button = %KifuLibraryButton
@onready var _tsume_btn: Button = %TsumeButton
@onready var _quit_dialog: ConfirmationDialog = %QuitDialog
@onready var _version_label: Label = %VersionLabel

# Hidden credits trigger: 10 taps on the title within _TITLE_TAP_WINDOW
# seconds of each other opens the credits scene. The window resets the
# counter on a stale gap so a stray double-tap a minute ago doesn't
# accumulate forever.
const _TITLE_TAPS_NEEDED := 10
const _TITLE_TAP_WINDOW := 3.0
var _title_tap_count: int = 0
var _title_tap_last: float = 0.0

func _ready() -> void:
	_mode.clear()
	_mode.add_item("人対人", Settings.Mode.H_VS_H)
	_mode.add_item("先手(人) 対 後手(AI)", Settings.Mode.H_VS_AI_GOTE)
	_mode.add_item("先手(AI) 対 後手(人)", Settings.Mode.H_VS_AI_SENTE)
	_mode.select(_mode.get_item_index(Settings.mode))
	_opponent_btn.pressed.connect(_on_opponent_pressed)
	_start_btn.pressed.connect(_on_start)
	_resume_btn.pressed.connect(_on_resume)
	_resume_btn.visible = Settings.has_saved_game()
	_settings_btn.pressed.connect(_on_settings_pressed)
	_kifu_library_btn.pressed.connect(_on_kifu_library_pressed)
	_tsume_btn.pressed.connect(func(): SceneTransition.go_to("res://scenes/TsumeShogi.tscn"))
	_quit_dialog.confirmed.connect(_on_quit_confirmed)
	ModalBlur.attach(_quit_dialog)
	_title.gui_input.connect(_on_title_gui_input)
	_ensure_default_character()
	_refresh_opponent_label()
	var version: String = ProjectSettings.get_setting("application/config/version", "")
	_version_label.text = ("v%s" % version) if version != "" else ""

func _on_title_gui_input(event: InputEvent) -> void:
	# Android emits both InputEventScreenTouch and a synthesised
	# InputEventMouseButton for every finger-tap, so listening to both
	# would double-count. Mirror Square.gd's split: touch on mobile,
	# mouse on desktop.
	var pressed := false
	if OS.has_feature("mobile"):
		if event is InputEventScreenTouch and event.pressed:
			pressed = true
	else:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pressed = true
	if not pressed:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _title_tap_last > _TITLE_TAP_WINDOW:
		_title_tap_count = 0
	_title_tap_last = now
	_title_tap_count += 1
	if _title_tap_count >= _TITLE_TAPS_NEEDED:
		_title_tap_count = 0
		SceneTransition.go_to("res://scenes/Credits.tscn")

# First-run convenience: if nothing is selected yet, pick the character
# whose level matches Settings.ai_level (default Lv 4 = 伊藤明) so an AI
# game started from the title screen always has a real opponent on
# screen, not just the LEVEL_NAMES fallback.
func _ensure_default_character() -> void:
	if Settings.selected_character_id != "":
		return
	var chars := Settings.list_characters()
	if chars.is_empty():
		return
	for c in chars:
		if c.level == Settings.ai_level:
			Settings.select_character(c)
			return
	Settings.select_character(chars[0])

# Esc on desktop / back on Android pops a confirm dialog instead of
# letting Godot fall through to the OS-level quit. Re-pressing while
# the dialog is already open is ignored (popup_centered re-centers but
# that's fine).
#
# Two paths: real key event via _unhandled_input, and Android
# WM_GO_BACK_REQUEST via _notification. _back_handled_frame dedupes
# same-frame double-fires.
var _back_handled_frame: int = -1

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_handle_back()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()

func _handle_back() -> void:
	var f: int = Engine.get_process_frames()
	if _back_handled_frame == f:
		return
	_back_handled_frame = f
	if _quit_dialog.visible:
		_quit_dialog.hide()
	else:
		_quit_dialog.popup_centered()

func _on_quit_confirmed() -> void:
	get_tree().quit()

func _on_settings_pressed() -> void:
	SceneTransition.go_to("res://scenes/SettingsScreen.tscn")

func _on_kifu_library_pressed() -> void:
	SceneTransition.go_to("res://scenes/KifuLibrary.tscn")

func _refresh_opponent_label() -> void:
	var profile := Settings.load_character(Settings.selected_character_id)
	# Match the label to the button's own text style.
	_opponent_name.add_theme_font_override("font", _opponent_btn.get_theme_font("font"))
	_opponent_name.add_theme_font_size_override("font_size",
		_opponent_btn.get_theme_font_size("font_size"))
	_opponent_name.add_theme_color_override("font_color",
		_opponent_btn.get_theme_color("font_color"))
	if profile == null:
		_opponent_name.text = "選んでください"
		_opponent_icon.texture = null
	else:
		_opponent_name.text = "%s (Lv.%d %s)" % [
			profile.display_name, profile.level, profile.strength_label]
		_opponent_icon.texture = _round_portrait_icon(profile)
	_opponent_icon.visible = _opponent_icon.texture != null

# Size of the generated icon texture. Twice the 48 px display size
# (`OpponentIcon`'s minimum size) so it stays sharp on dense screens.
const _ICON_PX := 96

# A round head-and-shoulders icon cut from the character's neutral
# portrait, matching the pre-made 加藤先生 icon on the in-game
# TeacherButton. Crop: a square 80 % of the portrait's width,
# centred, starting 10 % from the top (tuned against all eight
# portraits so every face sits in the middle of the circle).
func _round_portrait_icon(profile: CharacterProfile) -> Texture2D:
	if profile.portrait_dir == "":
		return null
	var path := profile.portrait_dir.path_join("neutral.webp")
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	var side := int(img.get_width() * 0.8)
	var x := (img.get_width() - side) / 2
	var y := int(img.get_height() * 0.10)
	side = mini(side, img.get_height() - y)
	img = img.get_region(Rect2i(x, y, side, side))
	img.convert(Image.FORMAT_RGBA8)
	img.resize(_ICON_PX, _ICON_PX, Image.INTERPOLATE_LANCZOS)
	# Circular alpha mask with a one-pixel soft edge.
	var r := _ICON_PX / 2.0
	for py in _ICON_PX:
		for px in _ICON_PX:
			var d := Vector2(px + 0.5 - r, py + 0.5 - r).length()
			var a := clampf(r - d, 0.0, 1.0)
			if a < 1.0:
				var c := img.get_pixel(px, py)
				c.a *= a
				img.set_pixel(px, py, c)
	return ImageTexture.create_from_image(img)

func _on_opponent_pressed() -> void:
	SceneTransition.go_to("res://scenes/CharacterPicker.tscn")

func _on_start() -> void:
	Settings.mode = _mode.get_selected_id()
	# ai_level is set by the character picker (Settings.select_character)
	# so we don't touch it here.
	Settings.resume_sfen = ""
	Settings.clear_saved_game()
	_go_to("res://scenes/Main.tscn")

func _on_resume() -> void:
	var saved: Dictionary = Settings.load_saved_game()
	if saved.is_empty() or str(saved.get("sfen", "")) == "":
		push_warning("resume: saved game missing or corrupt")
		Settings.clear_saved_game()
		_resume_btn.visible = false
		return
	Settings.mode = int(saved["mode"])
	# Prefer the character recorded in the save (added 2026-04-27); fall
	# back to syncing ai_level alone for older save files that don't
	# carry character_id.
	var saved_cid := str(saved.get("character_id", ""))
	if saved_cid != "":
		var profile := Settings.load_character(saved_cid)
		if profile != null:
			Settings.select_character(profile)
		else:
			Settings.set_ai_level(int(saved.get("level", Settings.ai_level)))
	else:
		Settings.set_ai_level(int(saved.get("level", Settings.ai_level)))
	Settings.resume_sfen = str(saved["sfen"])
	Settings.resume_packed = PackedInt32Array(saved.get("packed_log", PackedInt32Array()))
	_go_to("res://scenes/Main.tscn")

func _go_to(scene_path: String) -> void:
	_start_btn.disabled = true
	_resume_btn.disabled = true
	SceneTransition.go_to(scene_path)
