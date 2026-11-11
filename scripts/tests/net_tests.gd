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
	await _test_version_mismatch_rejected()
	await _test_discovery_finds_beacon()
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
