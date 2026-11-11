extends Node

# 通信対戦 session (ROADMAP Phase 8). One TCP connection between two copies
# of the game on the same LAN, carrying one JSON object per line. Lives as
# an autoload so the connection survives the lobby → game scene switch.
#
# Roles: the HOST listens and decides who plays 先手; the GUEST connects.
# Discovery (how the guest finds the host) is LanDiscovery's job.
#
# Messages (`t` = type):
#   hello   {proto, app, name, game_id, moves}  both ways, first message.
#           game_id/moves are empty for a new game and filled when a
#           guest reconnects to a game in progress.
#   start   {game_id, host_is_sente}            host → guest, new game.
#   sync    {moves}                             host → guest, after a
#           reconnect: the agreed move list both sides replay.
#   move    {seq, usi}                          1-based ply number + USI.
#   resign / declare / abort                    game end by the sender
#           (投了, 入玉宣言, left the game).
#   ping / pong                                 keepalive.
#   error   {reason}                            sender is closing.
#
# The receiver never trusts a move: GameController checks every one with
# ShogiCore.is_legal_move before applying it.

signal handshake_done
signal game_started
signal move_received(usi: String)
signal resign_received
signal declare_received
signal abort_received
# Mid-game connection drop; a reconnect is being attempted.
signal peer_lost
# Reconnected. `moves` is the agreed USI list to replay from the start.
signal peer_restored(moves: PackedStringArray)
# The session is over without a game result (lost for good, version
# mismatch, protocol error). `reason` is shown to the player.
signal session_failed(reason: String)

const PROTO := 1
const APP_ID := "seishin-shogi"
const GAME_PORT := 47124
const PORT_TRIES := 10
const PING_SEC := 2.0
const TIMEOUT_SEC := 8.0
const RECONNECT_WINDOW_SEC := 60.0
const RECONNECT_RETRY_SEC := 2.0
const MAX_LINE := 65536

enum Role { NONE, HOST, GUEST }

var role: int = Role.NONE
var local_name: String = ""
var remote_name: String = ""
var local_is_gote: bool = false
var game_id: String = ""
# USI of every move played so far, in order. The resync source of truth.
var moves: PackedStringArray = PackedStringArray()
# True from `start` until the game ends or the session closes.
var in_game: bool = false
var listen_port: int = 0

var _server: TCPServer = null
var _peer: StreamPeerTCP = null
var _buf: PackedByteArray = PackedByteArray()
var _handshaken: bool = false
# The guest's hello waits until the TCP connection is actually up.
var _hello_pending: bool = false
var _last_rx_msec: int = 0
var _last_ping_msec: int = 0
var _host_address: String = ""
var _host_port: int = 0
# >0 while waiting for the peer to come back after a mid-game drop.
var _lost_since_msec: int = 0
var _next_retry_msec: int = 0

static func default_name() -> String:
	var n := OS.get_model_name()
	if n == "" or n == "GenericDevice":
		n = OS.get_environment("HOSTNAME")
	return n if n != "" else "PC"

func is_active() -> bool:
	return role != Role.NONE

# --- starting / stopping ---------------------------------------------------

# Opens the game port (trying a few in a row if one is taken). Returns
# false if none could be opened.
func host(name: String) -> bool:
	close()
	_server = TCPServer.new()
	for i in PORT_TRIES:
		if _server.listen(GAME_PORT + i) == OK:
			listen_port = GAME_PORT + i
			role = Role.HOST
			local_name = name
			return true
	_server = null
	return false

func join(address: String, port: int, name: String) -> bool:
	close()
	role = Role.GUEST
	local_name = name
	_host_address = address
	_host_port = port
	return _connect_to_host()

# Ends the session. `notify` sends a final message to the peer first.
func close(notify: String = "") -> void:
	if notify != "" and _peer != null and _handshaken:
		_send({"t": notify})
		_peer.poll()
	if _peer != null:
		_peer.disconnect_from_host()
	if _server != null:
		_server.stop()
	_peer = null
	_server = null
	_buf.clear()
	_handshaken = false
	_lost_since_msec = 0
	role = Role.NONE
	in_game = false
	game_id = ""
	moves = PackedStringArray()
	remote_name = ""
	listen_port = 0

# --- game actions ----------------------------------------------------------

func send_move(usi: String) -> void:
	moves.append(usi)
	_send({"t": "move", "seq": moves.size(), "usi": usi})

func send_resign() -> void:
	_send({"t": "resign"})

func send_declare() -> void:
	_send({"t": "declare"})

func finish_game() -> void:
	in_game = false

# --- polling ---------------------------------------------------------------

func _process(_delta: float) -> void:
	if role == Role.NONE:
		return
	var now := Time.get_ticks_msec()
	if role == Role.HOST and _server != null and _server.is_connection_available():
		var incoming := _server.take_connection()
		if _peer == null or _lost_since_msec > 0:
			_adopt_peer(incoming)
		else:
			incoming.disconnect_from_host()  # already have an opponent
	if _peer == null:
		if role == Role.GUEST and _lost_since_msec > 0 and now >= _next_retry_msec:
			_connect_to_host()
		_check_reconnect_window(now)
		return
	_peer.poll()
	match _peer.get_status():
		StreamPeerTCP.STATUS_CONNECTING:
			if now - _last_rx_msec >= int(TIMEOUT_SEC * 1000.0):
				_on_connection_dropped()
			return
		StreamPeerTCP.STATUS_CONNECTED:
			if _hello_pending:
				_hello_pending = false
				_send_hello()
		_:
			_on_connection_dropped()
			return
	_read_available()
	if _peer == null:
		return
	if now - _last_ping_msec >= int(PING_SEC * 1000.0):
		_last_ping_msec = now
		_send({"t": "ping"})
	if now - _last_rx_msec >= int(TIMEOUT_SEC * 1000.0):
		_on_connection_dropped()

func _connect_to_host() -> bool:
	_next_retry_msec = Time.get_ticks_msec() + int(RECONNECT_RETRY_SEC * 1000.0)
	var p := StreamPeerTCP.new()
	if p.connect_to_host(_host_address, _host_port) != OK:
		return false
	_adopt_peer(p)
	return true

func _adopt_peer(p: StreamPeerTCP) -> void:
	_peer = p
	_peer.set_no_delay(true)
	_buf.clear()
	_handshaken = false
	_last_rx_msec = Time.get_ticks_msec()
	_last_ping_msec = _last_rx_msec
	# The guest speaks first; on a reconnect it carries the game so far.
	_hello_pending = role == Role.GUEST

func _send_hello() -> void:
	_send({
		"t": "hello", "proto": PROTO, "app": APP_ID, "name": local_name,
		"game_id": game_id if in_game else "",
		"moves": Array(moves) if in_game else [],
	})

func _on_connection_dropped() -> void:
	if _peer != null:
		_peer.disconnect_from_host()
	_peer = null
	_handshaken = false
	if in_game:
		if _lost_since_msec == 0:
			_lost_since_msec = Time.get_ticks_msec()
			peer_lost.emit()
		return
	if role == Role.HOST:
		return  # a guest left the lobby; keep listening for the next one
	var was_role := role
	close()
	if was_role != Role.NONE:
		session_failed.emit("接続が切れました")

func _check_reconnect_window(now: int) -> void:
	if _lost_since_msec > 0 and now - _lost_since_msec >= int(RECONNECT_WINDOW_SEC * 1000.0):
		close()
		session_failed.emit("相手との接続が戻りませんでした")

# --- framing ---------------------------------------------------------------

func _send(msg: Dictionary) -> void:
	if _peer == null or _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	_peer.put_data((JSON.stringify(msg) + "\n").to_utf8_buffer())

func _read_available() -> void:
	var n := _peer.get_available_bytes()
	if n > 0:
		var res: Array = _peer.get_partial_data(n)
		if int(res[0]) == OK:
			_buf.append_array(res[1])
	while _peer != null:
		var nl := _buf.find(10)  # '\n'
		if nl < 0:
			if _buf.size() > MAX_LINE:
				_fail("受信データが不正です")
			return
		var line := _buf.slice(0, nl).get_string_from_utf8()
		_buf = _buf.slice(nl + 1)
		_last_rx_msec = Time.get_ticks_msec()
		var msg: Variant = JSON.parse_string(line)
		if msg is Dictionary:
			_handle(msg)
		else:
			_fail("受信データが不正です")

func _fail(reason: String) -> void:
	_send({"t": "error", "reason": reason})
	if _peer != null:
		_peer.poll()
	close()
	session_failed.emit(reason)

# --- protocol --------------------------------------------------------------

func _handle(msg: Dictionary) -> void:
	var t := str(msg.get("t", ""))
	if t == "ping":
		_send({"t": "pong"})
		return
	if t == "pong":
		return
	if t == "error":
		close()
		session_failed.emit(str(msg.get("reason", "相手が接続を終了しました")))
		return
	if not _handshaken:
		if t != "hello":
			_fail("受信データが不正です")
			return
		_on_hello(msg)
		return
	match t:
		"start":
			if role != Role.GUEST:
				return
			game_id = str(msg.get("game_id", ""))
			local_is_gote = bool(msg.get("host_is_sente", true))
			moves = PackedStringArray()
			in_game = true
			game_started.emit()
		"sync":
			if role != Role.GUEST:
				return
			moves = PackedStringArray(msg.get("moves", []))
			_lost_since_msec = 0
			peer_restored.emit(moves)
		"move":
			if not in_game:
				return
			var seq := int(msg.get("seq", 0))
			if seq <= moves.size():
				return  # duplicate after a resync
			if seq != moves.size() + 1:
				_fail("指し手の順番が合いません")
				return
			var usi := str(msg.get("usi", ""))
			moves.append(usi)
			move_received.emit(usi)
		"resign":
			resign_received.emit()
		"declare":
			declare_received.emit()
		"abort":
			abort_received.emit()

func _on_hello(msg: Dictionary) -> void:
	if str(msg.get("app", "")) != APP_ID or int(msg.get("proto", -1)) != PROTO:
		_fail("相手のアプリのバージョンが違います")
		return
	remote_name = str(msg.get("name", "相手"))
	_handshaken = true
	if role == Role.GUEST:
		# The host's hello answers ours; `start` or `sync` follows.
		handshake_done.emit()
		return
	_send_hello()
	var their_game := str(msg.get("game_id", ""))
	if in_game and their_game == game_id:
		# Reconnect: the longer move list is ahead (the other is a prefix
		# of it); both sides replay it and carry on.
		var theirs := PackedStringArray(msg.get("moves", []))
		if theirs.size() > moves.size():
			moves = theirs
		_lost_since_msec = 0
		_send({"t": "sync", "moves": Array(moves)})
		peer_restored.emit(moves)
		return
	if in_game:
		# A different guest while our game waits for its own player:
		# turn this one away but keep waiting.
		_send({"t": "error", "reason": "対局中です"})
		_peer.poll()
		_peer.disconnect_from_host()
		_peer = null
		_handshaken = false
		return
	handshake_done.emit()
	game_id = "%08x" % (randi() & 0x7fffffff)
	var host_is_sente := randi() % 2 == 0
	local_is_gote = not host_is_sente
	moves = PackedStringArray()
	in_game = true
	_send({"t": "start", "game_id": game_id, "host_is_sente": host_is_sente})
	game_started.emit()
