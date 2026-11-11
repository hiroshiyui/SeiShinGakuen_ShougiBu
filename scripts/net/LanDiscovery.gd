class_name LanDiscovery
extends Node

# Finds 通信対戦 hosts on the local network (ROADMAP Phase 8).
#
# Two mechanisms run side by side and feed one list:
# - UDP broadcast: a hosting game sends a small beacon about once a
#   second; a joining game listens on BEACON_PORT. Hosts that go quiet
#   for HOST_TTL_SEC drop off.
# - mDNS / DNS-SD (Bonjour), through the Rust `LanMdns` class: the host
#   registers `_seishinshogi._tcp`, the joiner browses it. These hosts
#   stay listed until their announcement is withdrawn.
# Some networks pass one and not the other, so either is enough.
#
# On Android, many devices drop incoming multicast unless the app holds
# a WifiManager.MulticastLock; it is taken through Godot's Java bridge
# (no plugin) while discovery runs.
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
# "ip:port" → {name, address, port, seen_msec, mdns_key}. `seen_msec`
# is the last broadcast beacon (-1 if none); `mdns_key` is the mDNS full
# name while that announcement is alive ("" otherwise).
var _hosts: Dictionary = {}
var _mdns: Object = null
var _multicast_lock: Object = null

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
	_acquire_multicast_lock()
	var m := _mdns_instance()
	if m != null and not bool(m.advertise(name, game_port, Net.PROTO)):
		push_warning("LanDiscovery: mDNS advertise failed; broadcast only")

# Returns false if the beacon port is taken (e.g. another copy of the
# game is already browsing on this machine).
# Returns false only if neither broadcast nor mDNS could start.
func start_browse() -> bool:
	stop()
	_udp = PacketPeerUDP.new()
	if _udp.bind(BEACON_PORT) != OK:
		_udp = null  # e.g. another copy is browsing; mDNS may still work
	_acquire_multicast_lock()
	var m := _mdns_instance()
	var mdns_ok := m != null and bool(m.browse())
	if _udp == null and not mdns_ok:
		_release_multicast_lock()
		return false
	_mode = Mode.BROWSE
	return true

func stop() -> void:
	if _udp != null:
		_udp.close()
	_udp = null
	if _mdns != null:
		_mdns.stop()
	_release_multicast_lock()
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
	if _udp == null:
		return
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
	var changed := _poll_mdns()
	var now := Time.get_ticks_msec()
	while _udp != null and _udp.get_available_packet_count() > 0:
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
			_hosts[key] = {"address": address, "port": port, "mdns_key": ""}
		_hosts[key]["name"] = str(msg.get("name", "?")).left(40)
		_hosts[key]["seen_msec"] = now
	for key in _hosts.keys():
		var h: Dictionary = _hosts[key]
		if str(h["mdns_key"]) != "":
			continue  # kept alive by its mDNS announcement
		if now - int(h["seen_msec"]) > int(HOST_TTL_SEC * 1000.0):
			_hosts.erase(key)
			changed = true
	if changed:
		hosts_changed.emit()

# --- mDNS ------------------------------------------------------------------

func _mdns_instance() -> Object:
	if _mdns == null and ClassDB.class_exists("LanMdns"):
		_mdns = ClassDB.instantiate("LanMdns")
	return _mdns

# Folds the mDNS events since the last frame into `_hosts`. Returns true
# if the list changed.
func _poll_mdns() -> bool:
	if _mdns == null:
		return false
	var changed := false
	for ev: Dictionary in _mdns.poll():
		var mkey := str(ev.get("key", ""))
		if str(ev.get("type", "")) == "lost":
			for key in _hosts.keys():
				var h: Dictionary = _hosts[key]
				if str(h["mdns_key"]) != mkey:
					continue
				h["mdns_key"] = ""
				# Still beaconing? Keep it until the beacon goes quiet too.
				if int(h["seen_msec"]) < 0:
					_hosts.erase(key)
					changed = true
			continue
		if int(ev.get("proto", -1)) != Net.PROTO:
			continue
		var port := int(ev.get("port", 0))
		if port <= 0 or port > 65535:
			continue
		var address := str(ev.get("address", ""))
		var key := "%s:%d" % [address, port]
		if not _hosts.has(key):
			changed = true
			_hosts[key] = {"address": address, "port": port, "seen_msec": -1}
		_hosts[key]["name"] = str(ev.get("name", "?")).left(40)
		_hosts[key]["mdns_key"] = mkey
	return changed

# --- Android multicast lock ------------------------------------------------

func _acquire_multicast_lock() -> void:
	if _multicast_lock != null or not OS.has_feature("android"):
		return
	if not Engine.has_singleton("AndroidRuntime"):
		return
	var ctx: Object = Engine.get_singleton("AndroidRuntime").getApplicationContext()
	if ctx == null:
		return
	var wifi: Object = ctx.getSystemService("wifi")
	if wifi == null:
		return
	var lock: Object = wifi.createMulticastLock("seishin-shogi")
	if lock == null:
		return
	lock.setReferenceCounted(false)
	lock.acquire()
	_multicast_lock = lock

func _release_multicast_lock() -> void:
	if _multicast_lock != null:
		_multicast_lock.release()
	_multicast_lock = null

func _exit_tree() -> void:
	stop()
