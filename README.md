# 清正学園将棋部

A single-player mobile Shogi (本将棋) game for Android: tap-and-play 9×9
board, full rule enforcement, and an AlphaZero-style AI opponent
running on-device.

## Status

Pre-1.0 playable. Runs on desktop Linux for dev; Android arm64-v8a APK
builds and installs. Rules (check, 二歩, 打ち歩詰め, 千日手) and AI are
functional; Play-Store release polish is ongoing — see
[`ROADMAP.md`](./ROADMAP.md) Phase 7.

## Quickstart

Clone, then open in Godot or build the APK.

### Desktop dev (Linux)

Prerequisites: Godot 4.6.2 at `~/.local/bin/Godot_v4.6.2-stable_linux.x86_64`,
Rust 1.93 (pinned in `native/shogi_core/rust-toolchain.toml`).

```bash
# 1. Build the native GDExtension
cargo build --release --manifest-path native/shogi_core/Cargo.toml
cp native/shogi_core/target/release/libshogi_core.so \
   native/bin/linux/x86_64/

# 2. Open the project
~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 --editor --path .
```

### Tests

```bash
# Rust: unit + encoding-parity + perft
cargo test --manifest-path native/shogi_core/Cargo.toml

# GDScript: FFI-driven rule fixtures
~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless -s res://scripts/tests/rules_tests.gd
```

Encoding-parity fixtures are regenerated with
`tools/gen_fixtures.py` (requires ShogiDojo's venv).

### Android APK

See [`docs/android-build.md`](./docs/android-build.md) for the one-time
setup. Once configured:

```bash
~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless --path . \
  --export-debug "Android arm64" build/seishingakuen-debug.apk
~/Android/Sdk/platform-tools/adb install -r build/seishingakuen-debug.apk
```

## Docs

- [`ROADMAP.md`](./ROADMAP.md) — phased delivery plan, what's done, what's left.
- [`docs/architecture.md`](./docs/architecture.md) — how the pieces fit together.
- [`docs/android-build.md`](./docs/android-build.md) — Android build recipe.
- [`docs/android-gotchas.md`](./docs/android-gotchas.md) — known gotchas, symptom → cause → fix.
- [`docs/adr/`](./docs/adr/) — architecture decision records.
- [`CLAUDE.md`](./CLAUDE.md) — orientation for the AI pair-programmer and new contributors.

## License & attribution

Code is unlicensed pending release. Vendored fonts carry their own
licenses — see each font directory:

- [`assets/fonts/fude-goshirae/`](./assets/fonts/fude-goshirae/) — SIL OFL 1.1.
- [`assets/fonts/noto-serif-jp/`](./assets/fonts/noto-serif-jp/) — SIL OFL 1.1.

The AI model `models/bonanza.onnx` is copied from
[ShogiDojo](../ShogiDojo/) (sibling project). Retraining happens there.
