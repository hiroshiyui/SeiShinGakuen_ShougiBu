extends Control

@onready var _sound: CheckButton = %SoundToggle
@onready var _teacher_side: OptionButton = %TeacherSideSelect
@onready var _back: Button = %BackButton

const _TEACHER_RIGHT_ID := 0
const _TEACHER_LEFT_ID := 1

func _ready() -> void:
	_sound.button_pressed = Settings.sound_enabled
	_sound.toggled.connect(_on_sound_toggled)

	_teacher_side.clear()
	_teacher_side.add_item("右側", _TEACHER_RIGHT_ID)
	_teacher_side.add_item("左側", _TEACHER_LEFT_ID)
	_teacher_side.select(_teacher_side.get_item_index(
		_TEACHER_LEFT_ID if Settings.teacher_side == "left" else _TEACHER_RIGHT_ID))
	_teacher_side.item_selected.connect(_on_teacher_side_changed)

	_back.pressed.connect(_on_back)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()

func _on_sound_toggled(pressed: bool) -> void:
	Settings.set_sound_enabled(pressed)

func _on_teacher_side_changed(idx: int) -> void:
	var id: int = _teacher_side.get_item_id(idx)
	Settings.set_teacher_side("left" if id == _TEACHER_LEFT_ID else "right")

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
