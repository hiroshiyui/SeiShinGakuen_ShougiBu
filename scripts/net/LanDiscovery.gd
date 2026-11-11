class_name LanDiscovery
extends Node

# Finds 通信対戦 hosts on the local network (ROADMAP Phase 8, discovery v1).
#
# A hosting game broadcasts a small UDP beacon about once a second; a
# joining game listens on BEACON_PORT and lists every host it hears.
# Hosts that go quiet for HOST_TTL_SEC drop off the list.
#
# Networks that isolate Wi-Fi clients (some hotel / guest / router
# setups) drop broadcasts entirely; there is no fallback by design.

signal hosts_changed

# Preloaded rather than using the NetSession autoload so headless test
# scripts (which run without autoloads) can use this class too.
const Net := preload("res://scripts/autoload/NetSession.gd")

const BEACON_PORT := 47123
const BEACON_SEC := 1.0
const HOST_TTL_SEC := 4.0

enum Mode { IDLE, BEACON, BROWSE }

var _mode: int = Mode.IDLE
var _udp: PacketPeerUDP = null
var _beacon: PackedByteArray = PackedByteArray()
var _next_beacon_msec: int = 0
# "ip:port" → {name, address, port, seen_msec}
var _hosts: Dictionary = {}

func start_beacon(game_port: int, name: String) -> void:
	stop()
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	_beacon = JSON.stringify({
		"app": Net.APP_ID, "proto": Net.PROTO,
		"name": name, "port": game_port,
	}).to_utf8_buffer()
	_mode = Mode.BEACON
	_next_beacon_msec = 0

# Returns false if the beacon port is taken (e.g. another copy of the
# game is already browsing on this machine).
func start_browse() -> bool:
	stop()
	_udp = PacketPeerUDP.new()
	if _udp.bind(BEACON_PORT) != OK:
		_udp = null
		return false
	_mode = Mode.BROWSE
	return true

func stop() -> void:
	if _udp != null:
		_udp.close()
	_udp = null
	_mode = Mode.IDLE
	if not _hosts.is_empty():
		_hosts.clear()
		hosts_changed.emit()

# Sorted by name: [{name, address, port}]
func hosts() -> Array:
	var out: Array = []
	for h: Dictionary in _hosts.values():
		out.append({"name": h["name"], "address": h["address"], "port": h["port"]})
	out.sort_custom(func(a, b): return str(a["name"]) < str(b["name"]))
	return out

func _process(_delta: float) -> void:
	match _mode:
		Mode.BEACON:
			_send_beacon()
		Mode.BROWSE:
			_receive_beacons()

func _send_beacon() -> void:
	var now := Time.get_ticks_msec()
	if now < _next_beacon_msec:
		return
	_next_beacon_msec = now + int(BEACON_SEC * 1000.0)
	for target in _broadcast_targets():
		_udp.set_dest_address(target, BEACON_PORT)
		_udp.put_packet(_beacon)

# The limited broadcast address, each local IPv4 network's /24 broadcast
# (Android sometimes drops 255.255.255.255), and loopback so two copies on
# one computer can find each other during development.
func _broadcast_targets() -> PackedStringArray:
	var out := PackedStringArray(["255.255.255.255", "127.0.0.1"])
	for addr: String in IP.get_local_addresses():
		var parts := addr.split(".")
		if parts.size() != 4 or addr.begins_with("127.") or addr.begins_with("169.254."):
			continue
		var bcast := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if not bcast in out:
			out.append(bcast)
	return out

func _receive_beacons() -> void:
	var changed := false
	var now := Time.get_ticks_msec()
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var address := _udp.get_packet_ip()
		var msg: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if not (msg is Dictionary):
			continue
		if str(msg.get("app", "")) != Net.APP_ID:
			continue
		if int(msg.get("proto", -1)) != Net.PROTO:
			continue
		var port := int(msg.get("port", 0))
		if port <= 0 or port > 65535:
			continue
		var key := "%s:%d" % [address, port]
		if not _hosts.has(key):
			changed = true
		_hosts[key] = {
			"name": str(msg.get("name", "?")).left(40),
			"address": address, "port": port, "seen_msec": now,
		}
	for key in _hosts.keys():
		if now - int(_hosts[key]["seen_msec"]) > int(HOST_TTL_SEC * 1000.0):
			_hosts.erase(key)
			changed = true
	if changed:
		hosts_changed.emit()
