extends Control

@onready var _mode: OptionButton = %ModeSelect
@onready var _budget: SpinBox = %PlayoutBudget
@onready var _start_btn: Button = %StartButton

func _ready() -> void:
	_mode.clear()
	_mode.add_item("人対人", Settings.Mode.H_VS_H)
	_mode.add_item("先手(人) 対 後手(AI)", Settings.Mode.H_VS_AI_GOTE)
	_mode.add_item("先手(AI) 対 後手(人)", Settings.Mode.H_VS_AI_SENTE)
	_mode.select(_mode.get_item_index(Settings.mode))
	_budget.value = Settings.ai_playouts
	_start_btn.pressed.connect(_on_start)

func _on_start() -> void:
	Settings.mode = _mode.get_selected_id()
	Settings.ai_playouts = int(_budget.value)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
