extends Control

@onready var _mode: OptionButton = %ModeSelect
@onready var _level: OptionButton = %LevelSelect
@onready var _start_btn: Button = %StartButton
@onready var _resume_btn: Button = %ResumeButton
@onready var _teacher_side: OptionButton = %TeacherSideSelect

const _TEACHER_RIGHT_ID := 0
const _TEACHER_LEFT_ID := 1

func _ready() -> void:
	_mode.clear()
	_mode.add_item("人対人", Settings.Mode.H_VS_H)
	_mode.add_item("先手(人) 対 後手(AI)", Settings.Mode.H_VS_AI_GOTE)
	_mode.add_item("先手(AI) 対 後手(人)", Settings.Mode.H_VS_AI_SENTE)
	_mode.select(_mode.get_item_index(Settings.mode))
	_level.clear()
	for lvl in range(Settings.MIN_LEVEL, Settings.MAX_LEVEL + 1):
		_level.add_item("Lv %d - %s" % [lvl, Settings.level_name(lvl)], lvl)
	_level.select(_level.get_item_index(Settings.ai_level))
	_level.item_selected.connect(_on_level_changed)
	_teacher_side.clear()
	_teacher_side.add_item("右側", _TEACHER_RIGHT_ID)
	_teacher_side.add_item("左側", _TEACHER_LEFT_ID)
	_teacher_side.select(_teacher_side.get_item_index(
		_TEACHER_LEFT_ID if Settings.teacher_side == "left" else _TEACHER_RIGHT_ID))
	_teacher_side.item_selected.connect(_on_teacher_side_changed)
	_start_btn.pressed.connect(_on_start)
	_resume_btn.pressed.connect(_on_resume)
	_resume_btn.visible = Settings.has_saved_game()

func _on_teacher_side_changed(idx: int) -> void:
	var id: int = _teacher_side.get_item_id(idx)
	Settings.set_teacher_side("left" if id == _TEACHER_LEFT_ID else "right")

func _on_level_changed(idx: int) -> void:
	Settings.set_ai_level(_level.get_item_id(idx))

func _on_start() -> void:
	Settings.mode = _mode.get_selected_id()
	Settings.set_ai_level(_level.get_selected_id())
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
	Settings.set_ai_level(int(saved.get("level", Settings.ai_level)))
	Settings.resume_sfen = str(saved["sfen"])
	_go_to("res://scenes/Main.tscn")

func _go_to(scene_path: String) -> void:
	_start_btn.disabled = true
	_resume_btn.disabled = true
	get_tree().change_scene_to_file(scene_path)
