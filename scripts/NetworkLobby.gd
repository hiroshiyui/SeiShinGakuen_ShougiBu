extends Control

# 通信対戦 lobby — placeholder for ROADMAP Phase 8 (Human vs Human on
# LAN). Today it only explains that the mode is coming and offers 戻る.
# The nodes the real lobby needs already exist so later work only
# fills in behaviour:
#
#   HostButton  → start a TCP server and the UDP broadcast beacon
#                 (Phase 8 "Discovery, v1" + "Transport"), then wait.
#   JoinButton  → listen for beacons and fill GameList with the games
#                 found; picking one connects over TCP.
#   GameList    → hidden until discovery exists.
#   Status      → state text (待機中 / 接続中 / 切断 …).
#
# Networking itself (discovery, the wire protocol, validating peer moves
# in ShogiCore, reconnect) belongs in its own scripts, not in this UI
# script. Android also needs the multicast-lock plugin and network
# permissions before HostButton / JoinButton can be enabled.

enum State { UNAVAILABLE, IDLE, HOSTING, BROWSING, CONNECTING, CONNECTED }

@onready var _status: Label = %Status
@onready var _game_list: ItemList = %GameList
@onready var _host_btn: Button = %HostButton
@onready var _join_btn: Button = %JoinButton
@onready var _back_btn: Button = %BackButton

var _state: State = State.UNAVAILABLE
var _back_handled_frame: int = -1

func _ready() -> void:
	_back_btn.pressed.connect(_back_to_title)
	_host_btn.pressed.connect(_on_host_pressed)
	_join_btn.pressed.connect(_on_join_pressed)
	_apply_state()

func _apply_state() -> void:
	var available := _state != State.UNAVAILABLE
	_host_btn.disabled = not available
	_join_btn.disabled = not available
	_game_list.visible = _state == State.BROWSING

func _on_host_pressed() -> void:
	pass # Phase 8: start hosting.

func _on_join_pressed() -> void:
	pass # Phase 8: start browsing for hosts.

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_handle_back()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()

# Esc and the Android back gesture can both fire in one frame.
func _handle_back() -> void:
	var f: int = Engine.get_process_frames()
	if _back_handled_frame == f:
		return
	_back_handled_frame = f
	_back_to_title()

func _back_to_title() -> void:
	SceneTransition.go_to("res://scenes/MainMenu.tscn")
