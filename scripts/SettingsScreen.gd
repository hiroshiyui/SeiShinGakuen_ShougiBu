extends Control

@onready var _sound: CheckButton = %SoundToggle
@onready var _motion: CheckButton = %MotionToggle
@onready var _teacher_side: OptionButton = %TeacherSideSelect
@onready var _back: Button = %BackButton
@onready var _avatar_pic: TextureRect = %AvatarPortrait
@onready var _avatar_btn: Button = %AvatarButton

const _TEACHER_RIGHT_ID := 0
const _TEACHER_LEFT_ID := 1

func _ready() -> void:
	_sound.button_pressed = Settings.sound_enabled
	_sound.toggled.connect(_on_sound_toggled)
	_motion.button_pressed = Settings.reduce_motion
	_motion.toggled.connect(func(pressed: bool): Settings.set_reduce_motion(pressed))
	# Spell the state out next to the switch: the switch art alone was
	# too easy to misread.
	for t: CheckButton in [_sound, _motion]:
		_sync_switch_text(t, t.button_pressed)
		t.toggled.connect(func(on: bool) -> void: _sync_switch_text(t, on))
	BackGuard.watch(_teacher_side)

	_teacher_side.clear()
	_teacher_side.add_item("右側", _TEACHER_RIGHT_ID)
	_teacher_side.add_item("左側", _TEACHER_LEFT_ID)
	_teacher_side.select(_teacher_side.get_item_index(
		_TEACHER_LEFT_ID if Settings.teacher_side == "left" else _TEACHER_RIGHT_ID))
	_teacher_side.item_selected.connect(_on_teacher_side_changed)

	_avatar_pic.texture = RoundedPortrait.thumbnail(Settings.avatar_path(Settings.avatar_id), 192)
	_avatar_btn.text = "変更" if Settings.avatar_id != "" else "選ぶ"
	_avatar_btn.pressed.connect(func() -> void:
		AvatarPicker.open("res://scenes/SettingsScreen.tscn"))

	_back.pressed.connect(_on_back)

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
	if BackGuard.swallows_back([_teacher_side]):
		return
	_on_back()

func _sync_switch_text(t: CheckButton, on: bool) -> void:
	t.text = "オン" if on else "オフ"

func _on_sound_toggled(pressed: bool) -> void:
	Settings.set_sound_enabled(pressed)

func _on_teacher_side_changed(idx: int) -> void:
	var id: int = _teacher_side.get_item_id(idx)
	Settings.set_teacher_side("left" if id == _TEACHER_LEFT_ID else "right")

func _on_back() -> void:
	SceneTransition.go_to("res://scenes/MainMenu.tscn")
