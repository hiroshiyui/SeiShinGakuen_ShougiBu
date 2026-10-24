class_name Square
extends Control

signal tapped(file: int, rank: int)

@export var file: int = 0
@export var rank: int = 0

@onready var _piece_view: Control = $PieceView
@onready var _highlight: ColorRect = $Highlight
@onready var _move_hint: ColorRect = $MoveHint
@onready var _last_move_hint: ColorRect = $LastMoveHint
@onready var _highlight_border: Panel = $HighlightBorder
@onready var _move_hint_dot: Panel = $MoveHintDot
@onready var _invalid_flash: ColorRect = $InvalidFlash
var _flash_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_highlight.visible = false
	_highlight_border.visible = false
	_move_hint.visible = false
	_move_hint_dot.visible = false
	_last_move_hint.visible = false
	_invalid_flash.visible = false

func _gui_input(event: InputEvent) -> void:
	var is_press := false
	if OS.has_feature("mobile"):
		if event is InputEventScreenTouch and event.pressed:
			is_press = true
	else:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			is_press = true
	if is_press:
		tapped.emit(file, rank)
		accept_event()

const _FILE_ZENKAKU: Array[String] = ["", "１", "２", "３", "４", "５", "６", "７", "８", "９"]

func set_piece(text: String, is_gote: bool) -> void:
	_piece_view.text = text
	_piece_view.is_gote = is_gote
	_piece_view.visible = true
	_update_accessibility_name(text, is_gote)

func clear_piece() -> void:
	_piece_view.text = ""
	_piece_view.visible = false
	_update_accessibility_name("", false)

# Screen readers (TalkBack via Godot's AccessKit bridge) get nothing from
# a bare Control, so name each square "７六 歩 先手" / "７六 空" as the
# position changes. Cheap, and it lets a blind player at least browse
# the board.
func _update_accessibility_name(text: String, is_gote: bool) -> void:
	var sq := "%s%s" % [_FILE_ZENKAKU[file], Settings.RANK_KANJI[rank]]
	if text == "":
		accessibility_name = "%s 空" % sq
	else:
		accessibility_name = "%s %s %s" % [sq, text, "後手" if is_gote else "先手"]

# Selection and legal-move cues each carry a shape channel (border /
# dot) in addition to the translucent tint, so they stay readable for
# colour-blind players and over sun-washed amber wood where a 30%
# tint alone disappears.
func set_highlight(on: bool) -> void:
	_highlight.visible = on
	_highlight_border.visible = on

func set_move_hint(on: bool) -> void:
	_move_hint.visible = on
	_move_hint_dot.visible = on

# Brief red flash for a tap the rules rejected (opponent piece, illegal
# target). Silence on a wrong tap reads as "the game froze"; a visible
# "no" tells the player the tap landed and was refused.
func flash_invalid() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_invalid_flash.modulate.a = 1.0
	_invalid_flash.visible = true
	_flash_tween = create_tween()
	_flash_tween.tween_property(_invalid_flash, "modulate:a", 0.0, 0.3)
	_flash_tween.tween_callback(func(): _invalid_flash.visible = false)

func set_last_move_hint(on: bool) -> void:
	_last_move_hint.visible = on
