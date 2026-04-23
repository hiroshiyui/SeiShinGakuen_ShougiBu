# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**清正学園将棋部** — a mobile Shogi (本将棋) game for Android. Godot 4.6.2
Mobile renderer, Rust GDExtension for rules + AI, AlphaZero-style
policy+value network (Bonanza) with PUCT MCTS. Single-player vs. AI,
offline.

Read [`ROADMAP.md`](./ROADMAP.md) before planning new work — phase
ordering and "shipped differently" notes under each completed phase are
the canonical log of what the code actually does.

## Current architecture (live)

Two-layer with a narrow FFI:

- **GDScript** (`scripts/`, `scenes/`) — UI, input, scene graph, turn
  orchestration, MCTS Thread management.
- **Rust GDExtension** (`native/shogi_core/`, cdylib loaded via
  `addons/shogi_core.gdextension`) — owns: board / hands /
  move log, move generation, rule enforcement (check, 二歩, 打ち歩詰め,
  千日手 incl. perpetual-check variant, 入玉 detection), SFEN parse +
  serialize, 45-plane position encoder + 139-plane move index (byte-parity
  with ShogiDojo's Python encoder), tract-driven ONNX inference, and
  single-threaded PUCT MCTS.

The same compiled `.so` serves desktop (`x86_64-unknown-linux-gnu`)
and Android (`aarch64-linux-android`).

Full walkthrough: [`docs/architecture.md`](./docs/architecture.md).
Decisions with rationale: [`docs/adr/`](./docs/adr/).

## External dependencies

- **Godot engine:** `~/.local/bin/Godot_v4.6.2-stable_linux.x86_64`.
- **AI model:** `models/bonanza.onnx` (1.3 MB). On Android,
  `Settings.model_absolute_path()` extracts it from the APK asset dir
  into `user://` on first launch because tract can't open resources
  inside the PCK.
- **ShogiDojo** (`/home/yhh/MyProjects/ShogiDojo/`) — reference
  implementation for the 45-plane + 139-plane encoding. Rust encoder is
  byte-parity-tested against it via `tools/gen_fixtures.py` →
  `native/shogi_core/src/parity_tests.rs`. Encoding drift silently
  breaks the AI; don't change encoding logic without regenerating the
  fixtures and running `cargo test`.
- **Android NDK 28.1** at `~/Android/Sdk/ndk/28.1.13356709`, used
  through `cargo-ndk` for Android builds.

## Commands

Godot is not on PATH — always invoke by full path.

```bash
# Open editor
~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 --editor --path .

# Headless smoke run
~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 --headless --quit-after 60 --path .

# GDScript tests (rules via FFI)
~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless -s res://scripts/tests/rules_tests.gd
```

Rust:

```bash
# Desktop dev build + deploy
cargo build --release --manifest-path native/shogi_core/Cargo.toml
cp native/shogi_core/target/release/libshogi_core.so \
   native/bin/linux/x86_64/

# Unit + parity + perft tests
cargo test --manifest-path native/shogi_core/Cargo.toml

# Android cross-compile — see docs/android-build.md
(cd native/shogi_core && \
 ANDROID_NDK_HOME=~/Android/Sdk/ndk/28.1.13356709 \
 cargo ndk --platform 24 -t arm64-v8a \
 --output-dir ../../native/bin/android build --release)
```

Font subsets (re-run after touching UI strings):

```bash
./tools/build_font_subsets.sh
```

APK export: [`docs/android-build.md`](./docs/android-build.md).

## Conventions

- LF line endings, UTF-8, enforced via `.gitattributes` + `.editorconfig`.
- `.godot/`, `/build/`, `/android/`, `native/**/target`, `native/bin/`,
  and keystores are gitignored — see `.gitignore`.
- Piece orientation: 先手 bottom / upright, 後手 top / rotated 180°
  (per-Square rotation in `Square.gd`).
- Piece kanji render in `Fude Goshirae` via a per-node theme override in
  `Square.gd`; everything else inherits `assets/themes/ui.tres` which
  uses Noto Serif JP.
- Fonts live in-repo twice: `<name>-full.otf` (source, excluded from
  APK by `export_presets.cfg`'s `exclude_filter`) and `<name>.otf`
  (subset, shipped).
- Asset folders under `assets/` are organised by purpose, not by
  filetype: `textures/` (piece + board wood grain), `backgrounds/`
  (gutter / full-screen decoration), `ui/` (icons, buttons),
  `branding/` (title / splash / logo), `characters/{teachers,students}/`
  (将棋部 character portraits), `sounds/`, `fonts/`, `themes/`.
  Prefer `.webp` for photographic / AI-generated imagery (smaller APK
  than PNG at equivalent quality); use `.png` only when lossless edges
  matter (pixel-art icons). Commit the source image *and* its Godot
  `.import` sidecar.

## When working here

- **Android-only gotchas** are collected in
  [`docs/android-gotchas.md`](./docs/android-gotchas.md) —
  orientation-as-int, touch-event double-fire,
  `include_filter="*.onnx"`, res:// extraction, etc. Grep there before
  debugging a platform-specific issue.
- **Don't change the encoder** (`native/shogi_core/src/encode.rs`,
  `move_index.rs`) without regenerating fixtures and running parity
  tests. The model silently plays garbage if the encoding drifts.
- **The ROADMAP's "Open Questions"** section flags decisions not yet
  made (千日手 variant, sprite atlas, Play Store distribution, etc.).
  Don't invent answers — surface the question.
- **New UI strings must round-trip through the font subset script.**
  `tools/build_font_subsets.sh` greps `scripts/` and `scenes/` for
  Japanese characters. If you add text via code composition (`"... %s"
  % x`) make sure the injected characters are in its safety-list.
