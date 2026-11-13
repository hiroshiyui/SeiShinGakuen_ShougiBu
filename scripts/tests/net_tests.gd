extends SceneTree

# 通信対戦 session + discovery over loopback. Run headless:
#   godot --headless -s res://scripts/tests/net_tests.gd --path .
#
# Two NetSession instances in one process play the host and the guest.
# Uses the real ports (47123 / 47124+), so close any running copy of the
# game that is hosting or browsing first.

const Net := preload("res://scripts/autoload/NetSession.gd")
const Discovery := preload("res://scripts/net/LanDiscovery.gd")

var _fails: int = 0
var _host: Node
var _guest: Node
var _events: Array[String] = []

func _initialize() -> void:
	_main.call_deferred()

func _main() -> void:
	await _test_handshake_and_move()
	await _test_reconnect_resyncs_longer_list()
	await _test_rematch_swaps_sides()
	await _test_leaving_after_game_ends_session()
	await _test_version_mismatch_rejected()
	await _test_silent_stranger_cannot_block_host()
	await _test_resync_rejects_rewritten_history()
	await _test_reconnect_needs_token()
	await _test_resync_rejects_move_for_other_side()
	await _test_flood_does_not_bump_guest()
	await _test_bad_types_end_session()
	await _test_oversized_line_ends_session()
	await _test_start_mid_game_ignored()
	await _test_avatars_exchanged()
	await _test_discovery_finds_beacon()
	await _test_discovery_finds_mdns()
	for n: Node in [_host, _guest]:
		if n != null:
			n.close()
	print("net_tests: %s" % ("OK" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)

func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   %s" % what)
	else:
		_fails += 1
		print("  FAIL %s" % what)

func _wait_for(cond: Callable, seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if cond.call():
			return true
		await process_frame
	return bool(cond.call())

func _make(tag: String) -> Node:
	var n: Node = Net.new()
	root.add_child(n)
	n.game_started.connect(func(): _events.append(tag + ":started"))
	n.move_received.connect(func(u): _events.append(tag + ":move:" + u))
	n.peer_lost.connect(func(): _events.append(tag + ":lost"))
	n.peer_restored.connect(func(m): _events.append(tag + ":restored:" + ",".join(m)))
	n.session_failed.connect(func(r): _events.append(tag + ":failed:" + r))
	n.rematch_requested.connect(func(): _events.append(tag + ":rematch?"))
	return n

func _test_handshake_and_move() -> void:
	print("handshake + move")
	_host = _make("host")
	_guest = _make("guest")
	_check(_host.host("Host"), "host opens a port")
	_check(_guest.join("127.0.0.1", _host.listen_port, "Guest"), "guest starts connecting")
	var both := await _wait_for(func():
		return "host:started" in _events and "guest:started" in _events, 3.0)
	_check(both, "both sides get game_started")
	_check(_host.remote_name == "Guest" and _guest.remote_name == "Host", "names exchanged")
	_check(_host.local_is_gote != _guest.local_is_gote, "one side each")
	_check(_host.game_id != "" and _host.game_id == _guest.game_id, "shared game id")
	var sente: Node = _guest if _host.local_is_gote else _host
	var gote: Node = _host if sente == _guest else _guest
	var gote_tag := "host" if gote == _host else "guest"
	sente.send_move("7g7f")
	var got := await _wait_for(func(): return (gote_tag + ":move:7g7f") in _events, 2.0)
	_check(got, "move arrives at the other side")
	_check(Array(gote.moves) == ["7g7f"] and Array(sente.moves) == ["7g7f"], "both logs agree")

func _test_avatars_exchanged() -> void:
	print("avatars")
	var h: Node = _make("aH")
	var g: Node = _make("aG")
	h.host("H", "girl-03")
	g.join("127.0.0.1", h.listen_port, "G", "boy-05")
	var ok := await _wait_for(func(): return h.in_game and g.in_game, 3.0)
	_check(ok, "pair with avatars connects")
	_check(h.remote_avatar == "boy-05" and g.remote_avatar == "girl-03", "avatar ids exchanged")
	await _close_pair([h, g])
	# A made-up id (or a path) must not get through as an avatar.
	h = _make("bH")
	g = _make("bG")
	h.host("H", "../../etc/passwd")
	g.join("127.0.0.1", h.listen_port, "G")
	ok = await _wait_for(func(): return h.in_game and g.in_game, 3.0)
	_check(ok, "pair without valid avatars connects")
	_check(g.remote_avatar == "" and h.remote_avatar == "", "unknown or missing avatar ids are dropped")
	await _close_pair([h, g])

func _test_reconnect_resyncs_longer_list() -> void:
	print("reconnect")
	_events.clear()
	var gote: Node = _host if _host.local_is_gote else _guest
	# Drop the guest's socket as if Wi-Fi blinked, then let 後手 move
	# while the link is down: that side ends up one move ahead.
	_guest._on_connection_dropped()
	_check("guest:lost" in _events, "guest reports peer_lost")
	gote.send_move("3c3d")
	var ok := await _wait_for(func():
		return _events.any(func(e): return e.begins_with("host:restored")) \
			and _events.any(func(e): return e.begins_with("guest:restored")), 12.0)
	_check(ok, "both sides restored")
	_check(Array(_host.moves) == ["7g7f", "3c3d"], "host has the longer list")
	_check(Array(_guest.moves) == ["7g7f", "3c3d"], "guest has the longer list")
	_check(_host.in_game and _guest.in_game, "game continues")

func _test_rematch_swaps_sides() -> void:
	print("rematch")
	_events.clear()
	var host_was_gote: bool = _host.local_is_gote
	var old_id: String = _host.game_id
	_host.finish_game()
	_guest.finish_game()
	_guest.request_rematch()
	var asked := await _wait_for(func(): return "host:rematch?" in _events, 2.0)
	_check(asked, "host hears the rematch request")
	_check(not _host.in_game, "no new game until both ask")
	_host.request_rematch()
	var both := await _wait_for(func():
		return "host:started" in _events and "guest:started" in _events, 2.0)
	_check(both, "both sides start the rematch")
	_check(_host.local_is_gote == not host_was_gote, "sides swapped")
	_check(_guest.local_is_gote == host_was_gote, "guest has the other side")
	_check(_host.game_id != old_id and _host.game_id == _guest.game_id, "new shared game id")
	_check(_host.moves.is_empty() and _guest.moves.is_empty(), "move lists cleared")

func _test_leaving_after_game_ends_session() -> void:
	print("leaving after the game")
	_events.clear()
	_host.finish_game()
	_guest.finish_game()
	_guest.close()
	var told := await _wait_for(func():
		return _events.any(func(e): return e.begins_with("host:failed")), TIMEOUT_WAIT)
	_check(told, "host learns the guest left")
	_check(not _host.is_active(), "host session closed")

const TIMEOUT_WAIT := 10.0

func _test_version_mismatch_rejected() -> void:
	print("version mismatch")
	var h: Node = _make("h2")
	_check(h.host("H2"), "second host opens a port")
	var raw := StreamPeerTCP.new()
	raw.connect_to_host("127.0.0.1", h.listen_port)
	var sent := false
	var reply := ""
	var until := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < until and reply == "":
		raw.poll()
		if raw.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				raw.put_data((JSON.stringify({"t": "hello", "proto": 99, "app": Net.APP_ID, "name": "old"}) + "\n").to_utf8_buffer())
				sent = true
			var n := raw.get_available_bytes()
			if n > 0:
				reply = (raw.get_partial_data(n)[1] as PackedByteArray).get_string_from_utf8()
		await process_frame
	_check(reply.contains("\"error\""), "host answers an old client with an error")
	raw.disconnect_from_host()
	h.close()
	h.queue_free()

func _test_discovery_finds_beacon() -> void:
	print("discovery")
	var browser: Node = Discovery.new()
	var beacon: Node = Discovery.new()
	root.add_child(browser)
	root.add_child(beacon)
	if not browser.start_browse():
		_check(false, "beacon port free (is a copy of the game browsing?)")
		return
	beacon.start_beacon(47999, "Beacon")
	var found := await _wait_for(func():
		return browser.hosts().any(func(h): return int(h["port"]) == 47999 and h["name"] == "Beacon"), 3.0)
	_check(found, "browser hears the beacon")
	beacon.stop()
	var gone := await _wait_for(func():
		return not browser.hosts().any(func(h): return int(h["port"]) == 47999), Discovery.HOST_TTL_SEC + 2.0)
	_check(gone, "host drops off after it goes quiet")
	browser.stop()

# A host announced only over mDNS (no broadcast beacon) still shows up.
func _test_discovery_finds_mdns() -> void:
	print("discovery (mDNS)")
	if not ClassDB.class_exists("LanMdns"):
		_check(false, "LanMdns class loaded")
		return
	var browser: Node = Discovery.new()
	root.add_child(browser)
	browser.start_browse()
	var ad: Object = ClassDB.instantiate("LanMdns")
	_check(bool(ad.advertise("MdnsHost", 47998, Net.PROTO)), "advertise over mDNS")
	var found := await _wait_for(func():
		return browser.hosts().any(func(h): return int(h["port"]) == 47998 and h["name"] == "MdnsHost"), 6.0)
	_check(found, "browser finds the mDNS-only host")
	ad.stop()
	var gone := await _wait_for(func():
		return not browser.hosts().any(func(h): return int(h["port"]) == 47998), 6.0)
	_check(gone, "host drops off when the announcement is withdrawn")
	browser.stop()

# --- hardening -------------------------------------------------------------

# A fresh host + guest that have started a game. Returns [host, guest].
func _pair(tag: String) -> Array:
	var h: Node = _make(tag + "H")
	var g: Node = _make(tag + "G")
	h.host("H")
	g.join("127.0.0.1", h.listen_port, "G")
	await _wait_for(func(): return h.in_game and g.in_game, 3.0)
	return [h, g]

func _close_pair(pair: Array) -> void:
	for n: Node in pair:
		n.close()
		n.queue_free()
	await process_frame

# Sends raw lines from a plain TCP client; returns the client.
func _raw_client(port: int) -> StreamPeerTCP:
	var raw := StreamPeerTCP.new()
	raw.connect_to_host("127.0.0.1", port)
	await _wait_for(func():
		raw.poll()
		return raw.get_status() == StreamPeerTCP.STATUS_CONNECTED, 2.0)
	return raw

func _test_silent_stranger_cannot_block_host() -> void:
	print("silent stranger")
	var h: Node = _make("sH")
	h.host("H")
	var raw := await _raw_client(h.listen_port)
	# Pings before hello used to keep the connection alive forever.
	raw.put_data("{\"t\":\"ping\"}\n".to_utf8_buffer())
	for i in 10:
		await process_frame
	var g: Node = _make("sG")
	g.join("127.0.0.1", h.listen_port, "G")
	var ok := await _wait_for(func(): return h.in_game and g.in_game, 3.0)
	_check(ok, "real guest still gets in while a stranger is connected")
	raw.disconnect_from_host()
	await _close_pair([h, g])

func _test_resync_rejects_rewritten_history() -> void:
	print("rewritten history")
	var pair: Array = await _pair("r")
	var h: Node = pair[0]
	var g: Node = pair[1]
	var sente: Node = g if h.local_is_gote else h
	sente.send_move("7g7f")
	await _wait_for(func(): return h.moves.size() == 1 and g.moves.size() == 1, 2.0)
	# The guest drops and comes back claiming a different game.
	_events.clear()
	g._on_connection_dropped()
	g.moves = PackedStringArray(["2g2f", "8c8d"])
	await _wait_for(func(): return _events.any(func(e): return e.begins_with("rG:failed")), 12.0)
	_check(Array(h.moves) == ["7g7f"], "host keeps its own history")
	_check(not _events.any(func(e): return e.begins_with("rH:restored")), "host does not adopt it")
	await _close_pair(pair)

func _test_reconnect_needs_token() -> void:
	print("reconnect token")
	var pair: Array = await _pair("t")
	var h: Node = pair[0]
	var g: Node = pair[1]
	# The guest's link drops; a third party that knows the game id (but
	# not the token) tries to take the seat.
	g.close()
	await _wait_for(func(): return h._lost_since_msec > 0, 12.0)
	var raw := await _raw_client(h.listen_port)
	var hello := {"t": "hello", "proto": Net.PROTO, "app": Net.APP_ID, "name": "X",
		"game_id": h.game_id, "token": "deadbeef", "moves": []}
	raw.put_data((JSON.stringify(hello) + "\n").to_utf8_buffer())
	for i in 30:
		await process_frame
	_check(not h._handshaken and h.remote_name == "G", "wrong token does not take the seat")
	_check(h._lost_since_msec > 0 and h.in_game, "host keeps waiting for its own guest")
	raw.disconnect_from_host()
	await _close_pair(pair)

func _test_bad_types_end_session() -> void:
	print("bad types")
	var pair: Array = await _pair("b")
	var h: Node = pair[0]
	var g: Node = pair[1]
	_events.clear()
	g._send({"t": "move", "seq": "one", "usi": 7})
	var failed := await _wait_for(func(): return _events.any(func(e): return e.begins_with("bH:failed")), 2.0)
	_check(failed, "a move with wrong field types ends the session")
	_check(h.moves.is_empty(), "and nothing was recorded")
	await _close_pair(pair)

func _test_oversized_line_ends_session() -> void:
	print("oversized line")
	var pair: Array = await _pair("o")
	_events.clear()
	var g: Node = pair[1]
	var big := "x".repeat(Net.MAX_LINE + 100)
	g._peer.put_data(("{\"t\":\"ping\",\"pad\":\"" + big + "\"}\n").to_utf8_buffer())
	var failed := await _wait_for(func(): return _events.any(func(e): return e.begins_with("oH:failed")), 3.0)
	_check(failed, "a line longer than MAX_LINE ends the session")
	await _close_pair(pair)

func _test_start_mid_game_ignored() -> void:
	print("start mid-game")
	var pair: Array = await _pair("m")
	var h: Node = pair[0]
	var g: Node = pair[1]
	var sente: Node = g if h.local_is_gote else h
	sente.send_move("7g7f")
	await _wait_for(func(): return g.moves.size() == 1, 2.0)
	var gid: String = g.game_id
	h._send({"t": "start", "game_id": "ffffffff", "token": "x", "host_is_sente": true})
	for i in 20:
		await process_frame
	_check(g.game_id == gid and g.moves.size() == 1, "guest ignores a start during a game")
	await _close_pair(pair)

# A reconnecting guest one move ahead is fine only if that move is its
# own; one more move for the host's side must be refused.
func _test_resync_rejects_move_for_other_side() -> void:
	print("resync: extra move for the wrong side")
	var pair: Array = await _pair("w")
	var h: Node = pair[0]
	var g: Node = pair[1]
	var sente: Node = g if h.local_is_gote else h
	var gote: Node = h if sente == g else g
	sente.send_move("7g7f")
	await _wait_for(func(): return gote.moves.size() == 1, 2.0)
	gote.send_move("3c3d")
	await _wait_for(func(): return sente.moves.size() == 2, 2.0)
	_events.clear()
	g._on_connection_dropped()
	# Ply 3 is 先手's. Legit only if the guest is 先手.
	g.moves = PackedStringArray(["7g7f", "3c3d", "2g2f"])
	var guest_is_sente: bool = not g.local_is_gote
	await _wait_for(func():
		return _events.any(func(e): return e.begins_with("wH:restored") or e.begins_with("wG:failed")), 12.0)
	if guest_is_sente:
		_check(Array(h.moves) == ["7g7f", "3c3d", "2g2f"], "guest's own extra move is accepted")
	else:
		_check(Array(h.moves) == ["7g7f", "3c3d"], "an extra move for the host's side is refused")
	await _close_pair(pair)

# Junk connections arriving while a real guest connects must not bump it.
func _test_flood_does_not_bump_guest() -> void:
	print("connection flood")
	var h: Node = _make("fH")
	h.host("H")
	var junk: Array = []
	for i in 6:
		junk.append(await _raw_client(h.listen_port))
	var g: Node = _make("fG")
	g.join("127.0.0.1", h.listen_port, "G")
	for i in 6:
		junk.append(await _raw_client(h.listen_port))
	var ok := await _wait_for(func(): return h.in_game and g.in_game, 4.0)
	_check(ok, "guest gets in despite a flood of silent connections")
	for c: StreamPeerTCP in junk:
		c.disconnect_from_host()
	await _close_pair([h, g])
