extends Control

@onready var _mode: OptionButton = %ModeSelect
@onready var _budget: SpinBox = %PlayoutBudget
@onready var _start_btn: Button = %StartButton
@onready var _resume_btn: Button = %ResumeButton

func _ready() -> void:
	_mode.clear()
	_mode.add_item("人対人", Settings.Mode.H_VS_H)
	_mode.add_item("先手(人) 対 後手(AI)", Settings.Mode.H_VS_AI_GOTE)
	_mode.add_item("先手(AI) 対 後手(人)", Settings.Mode.H_VS_AI_SENTE)
	_mode.select(_mode.get_item_index(Settings.mode))
	_budget.value = Settings.ai_playouts
	_start_btn.pressed.connect(_on_start)
	_resume_btn.pressed.connect(_on_resume)
	_resume_btn.visible = Settings.has_saved_game()

func _on_start() -> void:
	Settings.mode = _mode.get_selected_id()
	Settings.ai_playouts = int(_budget.value)
	Settings.resume_sfen = ""
	Settings.clear_saved_game()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_resume() -> void:
	var saved: Dictionary = Settings.load_saved_game()
	if saved.is_empty() or str(saved.get("sfen", "")) == "":
		push_warning("resume: saved game missing or corrupt")
		Settings.clear_saved_game()
		_resume_btn.visible = false
		return
	Settings.mode = int(saved["mode"])
	Settings.ai_playouts = int(saved["playouts"])
	Settings.resume_sfen = str(saved["sfen"])
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
