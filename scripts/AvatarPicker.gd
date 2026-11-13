class_name AvatarPicker
extends Control

# Grid of the player-avatar portraits (Settings.AVATAR_IDS). Opened once
# on first launch from MainMenu (with 「あとで」 to skip) and from the
# 設定 screen. Tapping a tile selects it; 決定 saves, なし clears the
# avatar, and 戻る / back leaves without saving.

const _COLUMNS := 4
const _TILE := Vector2(132, 176)  # the portraits' 3:4 aspect
const _BORDER := 4
const _SELECTED_COLOR := Color(1.0, 0.82, 0.3)

# Where 決定 / 戻る lead. Set by the opener before switching scene.
static var return_to: String = "res://scenes/MainMenu.tscn"
static var first_launch: bool = false

static func open(from_scene: String, is_first_launch: bool = false) -> void:
	return_to = from_scene
	first_launch = is_first_launch
	SceneTransition.go_to("res://scenes/AvatarPicker.tscn")

@onready var _title: Label = %Title
@onready var _hint: Label = %Hint
@onready var _grid: GridContainer = %Grid
@onready var _scroll: ScrollContainer = %Scroll
@onready var _none_btn: Button = %NoneButton
@onready var _back_btn: Button = %BackButton
@onready var _ok_btn: Button = %OkButton

var _selected: String = ""
var _tiles: Dictionary = {}  # avatar id -> Button

func _ready() -> void:
	_selected = Settings.avatar_id
	if first_launch:
		_title.text = "アバターを選んでください"
		_hint.text = "将棋部でのあなたの姿です。\n設定からいつでも変更できます。"
		_back_btn.text = "あとで"
	_grid.columns = _COLUMNS
	var normal := StyleBoxFlat.new()
	normal.draw_center = false
	normal.set_border_width_all(_BORDER)
	normal.border_color = Color(1, 1, 1, 0)
	normal.set_corner_radius_all(10)
	var picked := normal.duplicate() as StyleBoxFlat
	picked.border_color = _SELECTED_COLOR
	for i in Settings.AVATAR_IDS.size():
		var aid: String = Settings.AVATAR_IDS[i]
		var btn := Button.new()
		btn.custom_minimum_size = _TILE + Vector2(_BORDER, _BORDER) * 2
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.accessibility_name = "アバター %d" % (i + 1)
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("hover", normal)
		btn.add_theme_stylebox_override("pressed", picked)
		btn.add_theme_stylebox_override("hover_pressed", picked)
		var pic := RoundedPortrait.new()
		pic.texture = RoundedPortrait.thumbnail(Settings.avatar_path(aid), int(_TILE.x) * 2)
		pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pic.offset_left = _BORDER + 2
		pic.offset_top = _BORDER + 2
		pic.offset_right = -_BORDER - 2
		pic.offset_bottom = -_BORDER - 2
		btn.add_child(pic)
		btn.pressed.connect(_select.bind(aid))
		_grid.add_child(btn)
		_tiles[aid] = btn
	_refresh()
	get_viewport().size_changed.connect(_fit_scroll)
	_fit_scroll()
	_none_btn.pressed.connect(func() -> void: _select(""))
	_back_btn.pressed.connect(_leave)
	_ok_btn.pressed.connect(_on_ok)

# Inside the CenterContainer the scroll area would collapse to nothing,
# so give it the whole grid's height, or whatever the screen leaves
# after the title, hint, buttons and margins (it scrolls then).
func _fit_scroll() -> void:
	const CHROME := 440.0
	var grid := _grid.get_combined_minimum_size()
	var avail := get_viewport_rect().size.y - CHROME
	_scroll.custom_minimum_size = Vector2(grid.x, clampf(avail, _TILE.y, grid.y))

func _select(aid: String) -> void:
	_selected = aid
	_refresh()

func _refresh() -> void:
	for aid in _tiles:
		(_tiles[aid] as Button).set_pressed_no_signal(aid == _selected)
	_none_btn.disabled = _selected == ""

func _on_ok() -> void:
	Settings.set_avatar_id(_selected)
	_leave()

func _leave() -> void:
	first_launch = false
	SceneTransition.go_to(return_to)

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
	_leave()
