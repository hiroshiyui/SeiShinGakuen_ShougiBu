extends Control

@onready var _back_btn: Button = %BackButton
@onready var _hide_btn: Button = %HideButton
@onready var _header: PanelContainer = %HeaderPanel
@onready var _scroll: PanelContainer = %ScrollPanel
@onready var _bg: TextureRect = $BackgroundImage

# Winter-holiday Easter egg: between Christmas Eve and New Year's Day
# the credits screen swaps to a warmer ramen-shop background.
const _WINTER_BG := preload("res://assets/backgrounds/credits_winter_bg.webp")

var _hidden: bool = false

func _ready() -> void:
	_back_btn.pressed.connect(_back_to_title)
	_hide_btn.pressed.connect(_toggle_hidden)
	if _is_winter_holiday():
		_bg.texture = _WINTER_BG

# True from Dec 24 (大晦日 / 年越しの一週間 lead-up) through Jan 1 in
# the device's local timezone.
func _is_winter_holiday() -> bool:
	var d: Dictionary = Time.get_datetime_dict_from_system()
	var month: int = int(d.get("month", 0))
	var day: int = int(d.get("day", 0))
	if month == 12 and day >= 24:
		return true
	if month == 1 and day == 1:
		return true
	return false

var _back_handled_frame: int = -1

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_handle_back()
		return
	# While the credits panels are hidden, any tap on the screen brings
	# them back so the player can use the 戻る button again.
	if not _hidden:
		return
	var pressed := false
	if OS.has_feature("mobile"):
		if event is InputEventScreenTouch and event.pressed:
			pressed = true
	else:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pressed = true
	if pressed:
		_toggle_hidden()
		get_viewport().set_input_as_handled()

func _toggle_hidden() -> void:
	_hidden = not _hidden
	_header.visible = not _hidden
	_scroll.visible = not _hidden

func _back_to_title() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()

# If the panels are hidden, the back gesture / Esc reveals them again
# before the next press exits to the title — saves a step on Android
# where the back gesture is the natural "undo" affordance.
func _handle_back() -> void:
	var f: int = Engine.get_process_frames()
	if _back_handled_frame == f:
		return
	_back_handled_frame = f
	if _hidden:
		_toggle_hidden()
	else:
		_back_to_title()
