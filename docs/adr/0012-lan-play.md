# ADR-0012: Human vs human over the local network (通信対戦)

## Status

Accepted. 2026-11-11.

## Context

The game was scoped as single-player vs. AI, offline, with online
multiplayer a non-goal, and the app requested no network permission.
Players asked for a way to play a friend sitting nearby, each on their
own phone. That needs networking, but not a server.

Choices to make:

- **Scope:** LAN only, or anything wider.
- **Discovery:** how one phone finds the other. UDP broadcast is pure
  GDScript; mDNS / DNS-SD (Bonjour) is the OS-level standard but needs
  Android's `NsdManager` through a Kotlin plugin, or a Rust crate plus a
  Java-side multicast lock, either of which complicates the F-Droid
  from-source build.
- **Fallback** for networks that isolate Wi-Fi clients (manual IP,
  QR code).
- **Trust:** the peer is another copy of the app, but its moves arrive
  over a socket.

## Decision

- **LAN only, no server.** One device hosts, the other joins; the
  connection is a direct TCP link. Nothing leaves the local network.
  The "online multiplayer" non-goal stands.
- **Discovery by UDP broadcast** (`scripts/net/LanDiscovery.gd`). The
  host sends a JSON beacon about once a second to 255.255.255.255, each
  local /24 broadcast address and loopback; the joiner listens on port
  47123. mDNS stays an optional upgrade if broadcast proves unreliable.
- **No Android multicast-lock plugin.** A Nokia G50 (Android 13)
  receives the beacons without one, so the plugin is left out until a
  device shows it is needed.
- **No manual-IP / QR fallback.** On client-isolated networks 通信対戦
  is simply unavailable.
- **Session in an autoload** (`scripts/autoload/NetSession.gd`) so the
  connection survives the lobby → game scene change. One JSON object per
  line; moves travel as USI with a ply number. The host picks 先手 at
  random.
- **Every received move is checked** with the new
  `ShogiCore.is_legal_move` (full legality: own king safe, 二歩,
  打ち歩詰め, forced promotion) before it is applied. A bad move ends the
  game as 中断. Received 入玉宣言 is re-checked the same way.
- **Reconnect for 60 seconds.** On a drop, the guest redials every two
  seconds and the host keeps listening. On reconnect the guest sends
  its move list; the longer of the two lists wins (the other is always
  a prefix of it) and both sides replay it, checking each move.
- **Request `INTERNET`.** Android needs it for any socket, local or
  not. The privacy policy and store descriptions say what the traffic
  is and that it stays on the LAN.

## Consequences

- Two phones on the same Wi-Fi can play each other with no setup
  beyond tapping 対局を作る and 対局に参加する.
- The app now holds a network permission; the "no network permission"
  line in the store listings is replaced by a precise description.
- Guest / hotel / some home routers that isolate clients make 通信対戦
  unavailable, with no workaround in the app.
- A desktop firewall (e.g. firewalld) blocks the host's beacon port and
  game port by default; desktop testing needs those ports opened.
- LAN games don't use the 続きから save slot: a game can't be resumed
  alone. 待った, the teacher hints and the AI-only features are off.
- The player with 後手 sees the board turned round, as in the
  先手(AI) 対 後手(人) mode, which gained the same flip.
- Not done yet: rematch from the 対局終了 dialog (it returns to the
  title) and a draw offer.
