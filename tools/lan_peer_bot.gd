extends SceneTree

# Headless 通信対戦 opponent for testing against a phone on the same Wi-Fi.
# Plays a random legal move about a second after each of the phone's.
#
#   # bot hosts, phone taps 対局に参加する:
#   godot --headless -s res://tools/lan_peer_bot.gd --path . -- host
#   # phone taps 対局を作る, bot joins the first game it hears:
#   godot --headless -s res://tools/lan_peer_bot.gd --path . -- join
#
# Add `mdns-only` (with host) to announce over mDNS without the broadcast
# beacon. Add `rematch` to stay for 再戦 after the game. Add
# `addr=<phone ip>` to join without discovery. Add `drop` to drop the
# connection once after the third move, to watch the phone wait for the
# reconnect. Add `name=<text>` to show the phone a name other than "Bot"
# (e.g. for screenshots).

const Net := preload("res://scripts/autoload/NetSession.gd")
const Discovery := preload("res://scripts/net/LanDiscovery.gd")

var _net: Node
var _disc: Node
var _core: Object
var _drop_once: bool = false
var _rematch: bool = false
var _mdns_ad: Object = null
var _move_at_msec: int = -1
var _name: String = "Bot"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_drop_once = "drop" in args
	_rematch = "rematch" in args
	_core = ClassDB.instantiate("ShogiCore")
	_net = Net.new()
	root.add_child(_net)
	_disc = Discovery.new()
	root.add_child(_disc)
	_net.game_started.connect(_on_started)
	_net.move_received.connect(_on_move)
	_net.peer_lost.connect(func(): print("[bot] peer lost, waiting"))
	_net.peer_restored.connect(_on_restored)
	_net.resign_received.connect(func(): _game_over("opponent resigned"))
	_net.declare_received.connect(func(): _game_over("opponent declared 入玉"))
	_net.rematch_requested.connect(func():
		print("[bot] phone asks for a rematch")
		_net.request_rematch())
	_net.abort_received.connect(func(): _finish("opponent left"))
	_net.session_failed.connect(func(r): _finish("session failed: " + r))
	var direct := ""
	for a in args:
		if a.begins_with("addr="):
			direct = a.substr(5)
		elif a.begins_with("name="):
			_name = a.substr(5)
	if direct != "":
		# Skips discovery, e.g. when this computer's firewall drops the
		# phone's beacon: `-- join addr=192.168.1.23`.
		print("[bot] joining %s directly" % direct)
		_net.join(direct, Net.GAME_PORT, _name)
	elif "join" in args:
		_disc.hosts_changed.connect(_on_hosts)
		if not _disc.start_browse():
			_finish("beacon port busy")
			return
		print("[bot] browsing for a host…")
	else:
		if not _net.host(_name):
			_finish("cannot open game port")
			return
		if "mdns-only" in args:
			# No broadcast beacon: the phone can only find this over mDNS.
			_mdns_ad = ClassDB.instantiate("LanMdns")
			if not bool(_mdns_ad.advertise(_name + " (mDNS)", _net.listen_port, Net.PROTO)):
				_finish("mDNS advertise failed")
				return
		else:
			_disc.start_beacon(_net.listen_port, _name)
		print("[bot] hosting on port %d" % _net.listen_port)

func _on_hosts() -> void:
	var hosts: Array = _disc.hosts()
	if hosts.is_empty() or _net.is_active():
		return
	var h: Dictionary = hosts[0]
	print("[bot] joining %s at %s:%d" % [h["name"], h["address"], h["port"]])
	_disc.stop()
	_net.join(str(h["address"]), int(h["port"]), _name)

func _on_started() -> void:
	_disc.stop()
	_core.reset_starting()
	print("[bot] game started, bot plays %s vs %s" % [
		"後手" if _net.local_is_gote else "先手", _net.remote_name])
	_schedule_if_my_turn()

func _on_move(usi: String) -> void:
	var m: Variant = _core.usi_to_move(usi)
	if m == null or not bool(_core.is_legal_move(m)):
		_finish("illegal move from phone: " + usi)
		return
	_core.apply_move(m)
	print("[bot] phone played %s" % usi)
	_schedule_if_my_turn()

func _on_restored(moves: PackedStringArray) -> void:
	_core.reset_starting()
	for usi in moves:
		_core.apply_move(_core.usi_to_move(usi))
	print("[bot] restored at move %d" % moves.size())
	_schedule_if_my_turn()

func _schedule_if_my_turn() -> void:
	if bool(_core.side_to_move_gote()) == _net.local_is_gote:
		_move_at_msec = Time.get_ticks_msec() + 1000

func _process(_delta: float) -> bool:
	if _move_at_msec >= 0 and Time.get_ticks_msec() >= _move_at_msec:
		_move_at_msec = -1
		_play_random()
	return false

func _play_random() -> void:
	var gote := bool(_core.side_to_move_gote())
	var options: Array = []
	for f in range(1, 10):
		for r in range(1, 10):
			var p: Variant = _core.piece_at(f, r)
			if p != null and bool(p["is_gote"]) == gote:
				options.append_array(_core.legal_moves_from(f, r))
	var hand: Dictionary = _core.hand(gote)
	for kind in hand.keys():
		if int(hand[kind]) > 0:
			options.append_array(_core.legal_drops(int(kind)))
	if options.is_empty():
		_finish("bot has no legal move")
		return
	var m: Dictionary = options.pick_random()
	var usi := str(_core.move_to_usi(m))
	_core.apply_move(m)
	_net.send_move(usi)
	print("[bot] played %s" % usi)
	if _drop_once and _net.moves.size() >= 3:
		_drop_once = false
		print("[bot] dropping the connection once")
		_net._on_connection_dropped()

# With `rematch`, stay connected and agree to the next game.
func _game_over(why: String) -> void:
	_move_at_msec = -1
	if not _rematch:
		_finish(why)
		return
	print("[bot] %s — asking for a rematch" % why)
	_net.finish_game()
	_net.request_rematch()

func _finish(why: String) -> void:
	print("[bot] %s" % why)
	_net.close()
	quit()
