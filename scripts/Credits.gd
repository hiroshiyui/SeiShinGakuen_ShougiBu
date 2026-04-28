extends Control

@onready var _back_btn: Button = %BackButton
@onready var _hide_btn: Button = %HideButton
@onready var _header: PanelContainer = %HeaderPanel
@onready var _scroll: PanelContainer = %ScrollPanel

var _hidden: bool = false

func _ready() -> void:
	_back_btn.pressed.connect(_back_to_title)
	_hide_btn.pressed.connect(_toggle_hidden)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		# If the panels are hidden, ui_cancel reveals them again before
		# the next press exits to the title — saves a step on Android
		# where the back gesture is the natural "undo" affordance.
		if _hidden:
			_toggle_hidden()
		else:
			_back_to_title()
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
