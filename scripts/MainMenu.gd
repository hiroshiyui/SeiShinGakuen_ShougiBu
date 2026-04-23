extends Control

@onready var _mode: OptionButton = %ModeSelect
@onready var _budget: SpinBox = %PlayoutBudget
@onready var _start_btn: Button = %StartButton
@onready var _resume_btn: Button = %ResumeButton
@onready var _teacher_side: OptionButton = %TeacherSideSelect
@onready var _bgm: AudioStreamPlayer = $BGM

const _FADE_SEC := 1.5
const _BGM_VOLUME_DB := -6.0
const _BGM_SILENT_DB := -80.0
const _GAP_SEC := 2.0
const _BGM_TRACKS := [
	preload("res://assets/music/Paper_Lantern_Study.mp3"),
]

var _bgm_index: int = 0
var _bgm_leaving: bool = false
var _bgm_tween: Tween = null

const _TEACHER_RIGHT_ID := 0
const _TEACHER_LEFT_ID := 1

func _ready() -> void:
	_mode.clear()
	_mode.add_item("人対人", Settings.Mode.H_VS_H)
	_mode.add_item("先手(人) 対 後手(AI)", Settings.Mode.H_VS_AI_GOTE)
	_mode.add_item("先手(AI) 対 後手(人)", Settings.Mode.H_VS_AI_SENTE)
	_mode.select(_mode.get_item_index(Settings.mode))
	_budget.value = Settings.ai_playouts
	_teacher_side.clear()
	_teacher_side.add_item("右側", _TEACHER_RIGHT_ID)
	_teacher_side.add_item("左側", _TEACHER_LEFT_ID)
	_teacher_side.select(_teacher_side.get_item_index(
		_TEACHER_LEFT_ID if Settings.teacher_side == "left" else _TEACHER_RIGHT_ID))
	_teacher_side.item_selected.connect(_on_teacher_side_changed)
	_start_btn.pressed.connect(_on_start)
	_resume_btn.pressed.connect(_on_resume)
	_resume_btn.visible = Settings.has_saved_game()
	_bgm.finished.connect(_on_bgm_track_finished)
	_play_current_track()

func _play_current_track() -> void:
	if _BGM_TRACKS.is_empty() or _bgm_leaving:
		return
	var stream: AudioStream = _BGM_TRACKS[_bgm_index]
	_bgm.stream = stream
	_bgm.volume_db = _BGM_SILENT_DB
	_bgm.play()
	# Chain fade-in → hold → fade-out across the track's full length so
	# the exit fade lines up with the audio ending naturally. If the
	# track is shorter than 2×_FADE_SEC, compress proportionally.
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	var length: float = stream.get_length()
	var fade_in: float = _FADE_SEC
	var fade_out: float = _FADE_SEC
	var hold: float = length - fade_in - fade_out
	if hold < 0.0:
		var scale: float = length / (fade_in + fade_out)
		fade_in *= scale
		fade_out *= scale
		hold = 0.0
	_bgm_tween = create_tween()
	_bgm_tween.tween_property(_bgm, "volume_db", _BGM_VOLUME_DB, fade_in)
	if hold > 0.0:
		_bgm_tween.tween_interval(hold)
	_bgm_tween.tween_property(_bgm, "volume_db", _BGM_SILENT_DB, fade_out)

func _on_bgm_track_finished() -> void:
	if _bgm_leaving:
		return
	_bgm_index = (_bgm_index + 1) % _BGM_TRACKS.size()
	await get_tree().create_timer(_GAP_SEC).timeout
	_play_current_track()

func _on_teacher_side_changed(idx: int) -> void:
	var id: int = _teacher_side.get_item_id(idx)
	Settings.set_teacher_side("left" if id == _TEACHER_LEFT_ID else "right")

func _on_start() -> void:
	Settings.mode = _mode.get_selected_id()
	Settings.ai_playouts = int(_budget.value)
	Settings.resume_sfen = ""
	Settings.clear_saved_game()
	await _fade_out_and_change("res://scenes/Main.tscn")

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
	await _fade_out_and_change("res://scenes/Main.tscn")

# Disable the action buttons so the user can't trigger another scene
# change while the fade is in flight, then tween BGM volume down to
# silence before freeing this scene.
func _fade_out_and_change(scene_path: String) -> void:
	_start_btn.disabled = true
	_resume_btn.disabled = true
	_bgm_leaving = true  # suppress _on_bgm_track_finished → next track
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()  # otherwise our tween fights with the exit tween
	if _bgm != null and _bgm.playing:
		var tw := create_tween()
		tw.tween_property(_bgm, "volume_db", _BGM_SILENT_DB, _FADE_SEC)
		await tw.finished
	get_tree().change_scene_to_file(scene_path)
