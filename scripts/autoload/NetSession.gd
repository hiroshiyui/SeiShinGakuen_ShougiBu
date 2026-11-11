extends Node

# 通信対戦 session (ROADMAP Phase 8). One TCP connection between two copies
# of the game on the same LAN, carrying one JSON object per line. Lives as
# an autoload so the connection survives the lobby → game scene switch.
#
# Roles: the HOST listens and decides who plays 先手; the GUEST connects.
# Discovery (how the guest finds the host) is LanDiscovery's job.
#
# Messages (`t` = type):
#   hello   {proto, app, name, game_id, token, moves}  both ways, first
#           message. game_id/token/moves are empty for a new game and
#           filled when a guest reconnects to a game in progress.
#   start   {game_id, token, host_is_sente}     host → guest, new game.
#           `token` is a random secret only the guest learns; a
#           reconnect must present it, so knowing the game id (which a
#           LAN eavesdropper could see) isn't enough to take the seat.
#   sync    {moves}                             host → guest, after a
#           reconnect: the agreed move list both sides replay.
#   move    {seq, usi}                          1-based ply number + USI.
#   resign / declare / abort                    game end by the sender
#           (投了, 入玉宣言, left the game).
#   rematch                                     after a game: the sender
#           wants another. Once both have asked, the host sends a new
#           `start` with the sides swapped.
#   ping / pong                                 keepalive.
#   error   {reason}                            sender is closing.
#
# The receiver never trusts a move: GameController checks every one with
# ShogiCore.is_legal_move before applying it. NetSession itself checks
# the shape of every message (types, sizes, ordering) and drops a
# connection that doesn't say hello within HELLO_TIMEOUT_SEC.

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
# The peer asked for a rematch (after a finished game).
signal rematch_requested
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
const HELLO_TIMEOUT_SEC := 5.0
# Longest game we accept from a peer (a real game is a few hundred plies).
const MAX_MOVES := 1000
const NAME_MAX := 40
# Host: connections that haven't said hello yet wait here, each with its
# own deadline, instead of taking the seat. A flood of junk connections
# then can't bump a real guest that is mid-handshake.
const MAX_PENDING := 4

enum Role { NONE, HOST, GUEST }

var role: int = Role.NONE
var local_name: String = ""
var remote_name: String = ""
var local_is_gote: bool = false
var game_id: String = ""
var _resume_token: String = ""
# USI of every move played so far, in order. The resync source of truth.
var moves: PackedStringArray = PackedStringArray()
# True from `start` until the game ends or the session closes.
var in_game: bool = false
var listen_port: int = 0
# Between a finished game and the next `start`: the connection is only
# kept for a rematch, so losing it ends the session.
var post_game: bool = false
var _rematch_local: bool = false
var _rematch_remote: bool = false

var _server: TCPServer = null
# Host only: [{peer: StreamPeerTCP, buf: PackedByteArray, since: int}]
var _pending: Array = []
var _peer: StreamPeerTCP = null
var _buf: PackedByteArray = PackedByteArray()
var _handshaken: bool = false
# The guest's hello waits until the TCP connection is actually up.
var _hello_pending: bool = false
var _last_rx_msec: int = 0
var _adopted_msec: int = 0
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
	for p in _pending:
		(p["peer"] as StreamPeerTCP).disconnect_from_host()
	_pending.clear()
	_peer = null
	_server = null
	_buf.clear()
	_handshaken = false
	_lost_since_msec = 0
	role = Role.NONE
	in_game = false
	post_game = false
	_rematch_local = false
	_rematch_remote = false
	game_id = ""
	_resume_token = ""
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
	post_game = true
	_rematch_local = false
	_rematch_remote = false

func request_rematch() -> void:
	if not post_game or _rematch_local:
		return
	_rematch_local = true
	_send({"t": "rematch"})
	_maybe_start_rematch()

# Host only: both players asked, so start the next game with the sides
# swapped (whoever had 後手 now moves first).
func _maybe_start_rematch() -> void:
	if role != Role.HOST or not (_rematch_local and _rematch_remote):
		return
	_begin_game(local_is_gote)

func _begin_game(host_is_sente: bool) -> void:
	game_id = "%08x" % (randi() & 0x7fffffff)
	_resume_token = _random_token()
	local_is_gote = not host_is_sente
	moves = PackedStringArray()
	in_game = true
	post_game = false
	_rematch_local = false
	_rematch_remote = false
	_send({"t": "start", "game_id": game_id, "token": _resume_token,
		"host_is_sente": host_is_sente})
	game_started.emit()

# --- polling ---------------------------------------------------------------

func _process(_delta: float) -> void:
	if role == Role.NONE:
		return
	var now := Time.get_ticks_msec()
	if role == Role.HOST:
		_poll_pending(now)
		if role == Role.NONE:
			return
	# Checked every frame, so a connection that never completes a
	# handshake can't keep a lost game waiting forever.
	_check_reconnect_window(now)
	if role == Role.NONE:
		return
	if _peer == null:
		if role == Role.GUEST and _lost_since_msec > 0 and now >= _next_retry_msec:
			_connect_to_host()
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
	if not _handshaken:
		if now - _adopted_msec >= int(HELLO_TIMEOUT_SEC * 1000.0):
			_drop_stranger()
		return
	if now - _last_ping_msec >= int(PING_SEC * 1000.0):
		_last_ping_msec = now
		_send({"t": "ping"})
	if now - _last_rx_msec >= int(TIMEOUT_SEC * 1000.0):
		_on_connection_dropped()

# Host: new connections queue in `_pending` until they send a line. Only
# a hello gets the seat (and only while it is free); anything else, or
# silence past HELLO_TIMEOUT_SEC, is dropped. The seat holder is never
# bumped by a newcomer.
func _poll_pending(now: int) -> void:
	while _server != null and _server.is_connection_available():
		var incoming := _server.take_connection()
		if _pending.size() >= MAX_PENDING:
			(_pending.pop_front()["peer"] as StreamPeerTCP).disconnect_from_host()
		incoming.set_no_delay(true)
		_pending.append({"peer": incoming, "buf": PackedByteArray(), "since": now})
	var i := 0
	while i < _pending.size():
		var entry: Dictionary = _pending[i]
		var p: StreamPeerTCP = entry["peer"]
		p.poll()
		var status := p.get_status()
		var expired := now - int(entry["since"]) >= int(HELLO_TIMEOUT_SEC * 1000.0)
		if status == StreamPeerTCP.STATUS_CONNECTED and not expired:
			# PackedByteArray is a value type: work on a copy, store it back.
			var buf: PackedByteArray = entry["buf"]
			var n := mini(p.get_available_bytes(), MAX_LINE + 1 - buf.size())
			if n > 0:
				var res: Array = p.get_partial_data(n)
				if int(res[0]) == OK:
					buf.append_array(res[1])
					entry["buf"] = buf
			var nl := buf.find(10)
			if nl < 0 and buf.size() <= MAX_LINE:
				i += 1
				continue  # still waiting for its first line
			_pending.remove_at(i)
			var seat_free := _peer == null or _lost_since_msec > 0
			var msg: Variant = JSON.parse_string(buf.slice(0, nl).get_string_from_utf8()) if nl >= 0 else null
			if not seat_free or not (msg is Dictionary) or str(msg.get("t", "")) != "hello":
				p.disconnect_from_host()
				continue
			if _peer != null:
				_peer.disconnect_from_host()
			_adopt_peer(p)
			_buf = buf.slice(nl + 1)
			_handle(msg)
			if role == Role.NONE:
				return
			continue
		_pending.remove_at(i)
		p.disconnect_from_host()

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
	_adopted_msec = _last_rx_msec
	# The guest speaks first; on a reconnect it carries the game so far.
	_hello_pending = role == Role.GUEST

func _send_hello() -> void:
	_send({
		"t": "hello", "proto": PROTO, "app": APP_ID, "name": local_name,
		"game_id": game_id if in_game else "",
		"token": _resume_token if in_game else "",
		"moves": Array(moves) if in_game else [],
	})

# A connection that didn't complete the handshake. On the host this only
# frees the seat (the lobby keeps listening, a lost game keeps waiting);
# on the guest it counts as a drop.
func _drop_stranger() -> void:
	if role == Role.HOST:
		if _peer != null:
			_peer.disconnect_from_host()
		_peer = null
		_handshaken = false
		_buf.clear()
	else:
		_on_connection_dropped()

static func _random_token() -> String:
	return "%08x%08x%08x%08x" % [randi(), randi(), randi(), randi()]

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
	if role == Role.HOST and not post_game:
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
	# Never buffer more than one line's worth; a longer line is an error
	# whether or not its newline arrived in the same read.
	var n := mini(_peer.get_available_bytes(), MAX_LINE + 1 - _buf.size())
	if n > 0:
		var res: Array = _peer.get_partial_data(n)
		if int(res[0]) == OK:
			_buf.append_array(res[1])
	while _peer != null:
		var nl := _buf.find(10)  # '\n'
		if nl > MAX_LINE or (nl < 0 and _buf.size() > MAX_LINE):
			_fail("受信データが不正です")
			return
		if nl < 0:
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
	if t == "error":
		if not _handshaken and role == Role.HOST:
			_drop_stranger()
			return
		close()
		session_failed.emit(_clean_text(msg.get("reason"), 80, "相手が接続を終了しました"))
		return
	if not _handshaken:
		# Nothing but hello before the handshake — not even ping, which
		# would otherwise keep a silent connection alive.
		if t != "hello":
			if role == Role.HOST:
				_drop_stranger()
			else:
				_fail("受信データが不正です")
			return
		_on_hello(msg)
		return
	match t:
		"ping":
			_send({"t": "pong"})
		"pong":
			pass
		"start":
			if role != Role.GUEST or in_game:
				return  # a start in the middle of a game would reset the board
			var gid: Variant = msg.get("game_id")
			var token: Variant = msg.get("token")
			var sente: Variant = msg.get("host_is_sente")
			if not (gid is String and token is String and sente is bool) \
					or gid.length() > 32 or token.length() > 64:
				_fail("受信データが不正です")
				return
			game_id = gid
			_resume_token = token
			local_is_gote = sente
			moves = PackedStringArray()
			in_game = true
			post_game = false
			_rematch_local = false
			_rematch_remote = false
			game_started.emit()
		"sync":
			if role != Role.GUEST or not in_game:
				return
			var agreed: Variant = _resync_list(msg.get("moves"))
			if agreed == null:
				_fail("指し手の記録が合いません")
				return
			moves = agreed
			_lost_since_msec = 0
			peer_restored.emit(moves)
		"move":
			if not in_game:
				return
			var seq_v: Variant = msg.get("seq")
			var usi_v: Variant = msg.get("usi")
			if not (seq_v is int or seq_v is float) or not _is_usi(usi_v):
				_fail("受信データが不正です")
				return
			var seq := int(seq_v)
			if seq <= moves.size():
				return  # duplicate after a resync
			if seq != moves.size() + 1 or moves.size() >= MAX_MOVES:
				_fail("指し手の順番が合いません")
				return
			moves.append(usi_v)
			move_received.emit(usi_v)
		"resign":
			resign_received.emit()
		"declare":
			declare_received.emit()
		"abort":
			abort_received.emit()
		"rematch":
			if not post_game or _rematch_remote:
				return
			_rematch_remote = true
			rematch_requested.emit()
			_maybe_start_rematch()

func _on_hello(msg: Dictionary) -> void:
	var proto: Variant = msg.get("proto")
	if str(msg.get("app", "")) != APP_ID or not (proto is int or proto is float) \
			or int(proto) != PROTO:
		if role == Role.HOST:
			_send({"t": "error", "reason": "相手のアプリのバージョンが違います"})
			_drop_stranger()
		else:
			_fail("相手のアプリのバージョンが違います")
		return
	var their_name := _clean_text(msg.get("name"), NAME_MAX, "相手")
	if role == Role.GUEST:
		remote_name = their_name
		_handshaken = true
		# The host's hello answers ours; `start` or `sync` follows.
		handshake_done.emit()
		return
	var their_game: Variant = msg.get("game_id")
	var their_token: Variant = msg.get("token")
	if in_game and their_game is String and their_game == game_id \
			and their_token is String and _resume_token != "" and their_token == _resume_token:
		# Reconnect of our own guest. One side may be a move ahead; the
		# other's list must be a prefix of it, or the peer is lying.
		var agreed: Variant = _resync_list(msg.get("moves"))
		if agreed == null:
			_send({"t": "error", "reason": "指し手の記録が合いません"})
			_drop_stranger()
			return
		remote_name = their_name
		_handshaken = true
		_send_hello()
		moves = agreed
		_lost_since_msec = 0
		_send({"t": "sync", "moves": Array(moves)})
		peer_restored.emit(moves)
		return
	if in_game or post_game:
		# Anyone else while our game waits for its own player (or after
		# it): turn them away but keep waiting.
		_send({"t": "error", "reason": "対局中です"})
		_drop_stranger()
		return
	remote_name = their_name
	_handshaken = true
	_send_hello()
	handshake_done.emit()
	_begin_game(randi() % 2 == 0)

# --- validation ------------------------------------------------------------

static func _is_usi(v: Variant) -> bool:
	return v is String and v.length() >= 4 and v.length() <= 5

# Text from the peer, shown in the UI: a string, no control characters,
# at most `max_len` characters; `fallback` otherwise.
static func _clean_text(v: Variant, max_len: int, fallback: String) -> String:
	if not (v is String):
		return fallback
	# Cut first so a huge string costs nothing; keep some slack for the
	# control characters dropped below.
	var parts := PackedStringArray()
	for ch in (v as String).left(max_len * 2):
		var c := ch.unicode_at(0)
		if c >= 0x20 and c != 0x7f:
			parts.append(ch)
	var out := "".join(parts).strip_edges().left(max_len)
	return out if out != "" else fallback

# The move list both sides continue from after a reconnect, or null if
# the peer's list doesn't fit ours. One list must be a prefix of the
# other and they may differ by at most one move: the one that was in
# flight when the connection dropped.
func _resync_list(theirs_v: Variant) -> Variant:
	if not (theirs_v is Array) or theirs_v.size() > MAX_MOVES:
		return null
	for m in theirs_v:
		if not _is_usi(m):
			return null
	var theirs := PackedStringArray(theirs_v)
	var peer_ahead := theirs.size() > moves.size()
	var shorter := moves if peer_ahead else theirs
	var longer := theirs if peer_ahead else moves
	if longer.size() - shorter.size() > 1:
		return null
	for i in shorter.size():
		if shorter[i] != longer[i]:
			return null
	# The one extra move the peer has must be the peer's own: ply i is
	# 先手's when i is even (games always start from the initial
	# position). Otherwise a reconnect could play a move for us.
	if peer_ahead:
		var extra_is_sente := (longer.size() - 1) % 2 == 0
		var peer_is_sente := local_is_gote
		if extra_is_sente != peer_is_sente:
			return null
	return longer
