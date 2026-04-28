extends Control

@onready var _back_btn: Button = %BackButton

func _ready() -> void:
	_back_btn.pressed.connect(_back_to_title)
	Settings.apply_safe_area_to($Layout)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back_to_title()

func _back_to_title() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
