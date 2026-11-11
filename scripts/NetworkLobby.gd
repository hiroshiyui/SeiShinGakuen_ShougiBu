extends Control

# 通信対戦 lobby (ROADMAP Phase 8). Either host a game — open the game
# port and broadcast a beacon — or browse the beacons other copies send
# and join one. Once NetSession reports `game_started`, the game scene
# takes over; NetSession (an autoload) keeps the connection open.

enum State { IDLE, HOSTING, BROWSING, CONNECTING }

const IDLE_TEXT := "同じ Wi-Fi につないだ相手と対局します。\n片方が「対局を作る」、もう片方が\n「対局に参加する」を選んでください。"

@onready var _status: Label = %Status
@onready var _game_list: ItemList = %GameList
@onready var _host_btn: Button = %HostButton
@onready var _join_btn: Button = %JoinButton
@onready var _back_btn: Button = %BackButton

var _state: State = State.IDLE
var _discovery: LanDiscovery = null
var _back_handled_frame: int = -1

func _ready() -> void:
	# A game that ended (or was left) may still hold the session open.
	NetSession.close()
	_discovery = LanDiscovery.new()
	add_child(_discovery)
	_discovery.hosts_changed.connect(_refresh_list)
	NetSession.game_started.connect(_on_game_started)
	NetSession.session_failed.connect(_on_session_failed)
	_back_btn.pressed.connect(_back_to_title)
	_host_btn.pressed.connect(_on_host_pressed)
	_join_btn.pressed.connect(_on_join_pressed)
	_game_list.item_activated.connect(_on_game_chosen)
	_game_list.item_clicked.connect(func(i, _pos, _btn): _on_game_chosen(i))
	_set_state(State.IDLE, IDLE_TEXT)

func _set_state(s: State, text: String) -> void:
	_state = s
	_status.text = text
	_host_btn.text = "やめる" if s == State.HOSTING else "対局を作る"
	_join_btn.text = "やめる" if s == State.BROWSING else "対局に参加する"
	_host_btn.disabled = s == State.BROWSING or s == State.CONNECTING
	_join_btn.disabled = s == State.HOSTING or s == State.CONNECTING
	_game_list.visible = s == State.BROWSING
	if s == State.BROWSING:
		_refresh_list()

func _on_host_pressed() -> void:
	if _state == State.HOSTING:
		_cancel()
		return
	var name := NetSession.default_name()
	if not NetSession.host(name):
		_set_state(State.IDLE, "対局を作れませんでした。\n通信ポートを開けません。")
		return
	_discovery.start_beacon(NetSession.listen_port, name)
	_set_state(State.HOSTING, "相手の参加を待っています…\nこの端末の名前：%s" % name)

func _on_join_pressed() -> void:
	if _state == State.BROWSING:
		_cancel()
		return
	if not _discovery.start_browse():
		_set_state(State.IDLE, "対局を探せませんでした。\n通信ポートが使われています。")
		return
	_set_state(State.BROWSING, "対局を探しています…")

func _refresh_list() -> void:
	if _state != State.BROWSING:
		return
	_game_list.clear()
	for h: Dictionary in _discovery.hosts():
		var i := _game_list.add_item("%s  (%s)" % [h["name"], h["address"]])
		_game_list.set_item_metadata(i, h)
	_status.text = ("対局を探しています…" if _game_list.item_count == 0
		else "参加する対局をタップしてください。")

func _on_game_chosen(index: int) -> void:
	if _state != State.BROWSING:
		return
	var h: Dictionary = _game_list.get_item_metadata(index)
	_discovery.stop()
	if not NetSession.join(str(h["address"]), int(h["port"]), NetSession.default_name()):
		_set_state(State.IDLE, "接続できませんでした。")
		return
	_set_state(State.CONNECTING, "%s に接続しています…" % h["name"])

func _cancel() -> void:
	_discovery.stop()
	NetSession.close()
	_set_state(State.IDLE, IDLE_TEXT)

func _on_game_started() -> void:
	_discovery.stop()
	SceneTransition.go_to("res://scenes/Main.tscn")

func _on_session_failed(reason: String) -> void:
	_discovery.stop()
	_set_state(State.IDLE, reason)

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
	_discovery.stop()
	NetSession.close()
	SceneTransition.go_to("res://scenes/MainMenu.tscn")
