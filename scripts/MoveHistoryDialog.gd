extends Control

# Fullscreen modal listing every ply of the current game in 棋譜 notation.
# Tapping a row emits `ply_selected(ply)` so the host can replay-from-start
# to that ply on a scratch core (read-only review). `return_to_live` /
# `closed` exit review mode and dismiss the dialog respectively.

signal ply_selected(ply: int)
signal return_to_live
signal closed
signal share_requested

@onready var _list: VBoxContainer = %RowList
@onready var _scroll: ScrollContainer = %ScrollContainer
@onready var _share_btn: Button = %ShareButton
@onready var _back_to_live_btn: Button = %BackToLiveButton
@onready var _close_btn: Button = %CloseButton
@onready var _empty_hint: Label = %EmptyHint
@onready var _save_status: Label = %SaveStatus

const _SHARE_LABEL := "保存"
const _SHARE_DONE := "保存しました"

var _live_ply: int = 0  # which ply is "current" — bolded in the list

func _ready() -> void:
	# When this scene is instanced as a child of Main.tscn, the root
	# Control sometimes lays out at its content's min size instead of the
	# parent rect — force the full-screen preset so the backdrop and
	# panel both stretch as intended.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_share_btn.pressed.connect(_on_share_pressed)
	_back_to_live_btn.pressed.connect(_on_back_to_live)
	_close_btn.pressed.connect(_on_close)

# Show the dialog populated with the supplied kifu lines (one per ply,
# already 1-indexed by the Rust formatter). `live_ply` tells us which
# row to highlight — usually the latest played ply.
func show_with(lines: PackedStringArray, live_ply: int) -> void:
	_live_ply = live_ply
	# Reset any leftover save status from the previous open.
	_save_status.visible = false
	_share_btn.text = _SHARE_LABEL
	for child in _list.get_children():
		child.queue_free()
	if lines.is_empty():
		_empty_hint.visible = true
		_list.visible = false
	else:
		_empty_hint.visible = false
		_list.visible = true
		for i in range(lines.size()):
			var ply := i + 1  # match the kifu's 1-based ply number
			var btn := Button.new()
			btn.text = lines[i]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.custom_minimum_size = Vector2(0, 56)
			btn.add_theme_font_size_override("font_size", 22)
			if ply == _live_ply:
				btn.add_theme_color_override("font_color", Color(0.98, 0.85, 0.45, 1))
			btn.pressed.connect(_on_row_pressed.bind(ply))
			_list.add_child(btn)
	visible = true
	# Defer scroll-to-bottom one frame so ScrollContainer has measured the
	# fresh row list before we ask for its height.
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func _on_row_pressed(ply: int) -> void:
	# Auto-dismiss so the rewound board is actually visible. Re-open from
	# the StatusBar 棋譜 button to pick another ply.
	hide()
	ply_selected.emit(ply)

func _on_back_to_live() -> void:
	return_to_live.emit()
	hide()

func _on_close() -> void:
	hide()
	closed.emit()

func _on_share_pressed() -> void:
	# Disable so a double-tap doesn't trigger two writes.
	_share_btn.disabled = true
	share_requested.emit()
	# GameController calls show_save_result() synchronously from within
	# the signal handler, so by the time we re-enable the button the
	# label already reflects the save outcome.
	_share_btn.disabled = false

# Called by GameController after attempting the file write. `success`
# false displays the message in a muted red so the user notices it
# wasn't a path they should look for.
func show_save_result(success: bool, message: String) -> void:
	_save_status.text = message
	_save_status.add_theme_color_override(
		"font_color",
		Color(0.98, 0.85, 0.45, 1) if success else Color(1, 0.55, 0.45, 1))
	_save_status.visible = true
	_share_btn.text = _SHARE_DONE if success else _SHARE_LABEL

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_close()
