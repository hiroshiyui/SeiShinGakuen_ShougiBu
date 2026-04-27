extends Control

@onready var _mode: OptionButton = %ModeSelect
@onready var _opponent_btn: Button = %OpponentButton
@onready var _start_btn: Button = %StartButton
@onready var _resume_btn: Button = %ResumeButton
@onready var _settings_btn: Button = %SettingsButton
@onready var _quit_dialog: ConfirmationDialog = %QuitDialog

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
	_quit_dialog.confirmed.connect(_on_quit_confirmed)
	_ensure_default_character()
	_refresh_opponent_label()

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
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if not _quit_dialog.visible:
		_quit_dialog.popup_centered()

func _on_quit_confirmed() -> void:
	get_tree().quit()

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/SettingsScreen.tscn")

func _refresh_opponent_label() -> void:
	var profile := Settings.load_character(Settings.selected_character_id)
	if profile == null:
		_opponent_btn.text = "選んでください"
	else:
		_opponent_btn.text = "%s (Lv.%d %s)" % [
			profile.display_name, profile.level, profile.strength_label]

func _on_opponent_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/CharacterPicker.tscn")

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
	_go_to("res://scenes/Main.tscn")

func _go_to(scene_path: String) -> void:
	_start_btn.disabled = true
	_resume_btn.disabled = true
	get_tree().change_scene_to_file(scene_path)
