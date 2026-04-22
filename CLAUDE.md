# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**清正学園将棋部** — a mobile Shogi (本将棋) game for Android, Godot 4.6.2 Mobile renderer. Single-player vs. an AlphaZero-style AI (policy+value network + MCTS). See `ROADMAP.md` for the full plan; treat it as the source of truth for scope and phase ordering.

At time of writing the repo is at **Phase 0** — only the empty Godot project skeleton exists (`project.godot`, `icon.svg`, `.godot/` cache). Nothing in `scenes/`, `scripts/`, or `native/` yet.

## Target Architecture (per ROADMAP)

Two-layer design, introduced incrementally:

- **GDScript layer** (`scripts/`, `scenes/`) — UI, input, scene graph, turn orchestration. Phases 1–3 keep rule logic here for fast iteration.
- **Rust GDExtension native core** (`native/shogi_core/`, built as `cdylib`) — introduced in Phase 4. Owns: board representation, move generation, rule enforcement (check, 二歩, 打ち歩詰め, 千日手, 入玉), SFEN, MCTS, ONNX inference via the `ort` crate. Exposed to GDScript as a `ShogiCore` class through `addons/shogi_core.gdextension`.

The same compiled `.so` serves desktop (`x86_64-unknown-linux-gnu`) and Android (`aarch64-linux-android`). Desktop build is the daily dev target; Android is the ship target.

## External Dependencies

- **Godot engine:** `~/.local/bin/Godot_v4.6.2-stable_linux.x86_64` (not in PATH)
- **AI model:** `/home/yhh/MyProjects/ShogiDojo/bonanza.onnx` — input `(B,45,9,9)`, outputs `policy_logits (B,139,9,9)` + `value (B,1)`. Will be copied to `models/bonanza.onnx` in Phase 5.
- **ShogiDojo repo** (`/home/yhh/MyProjects/ShogiDojo/`) — reference implementation for the 45-plane board encoding and 139-plane move index. **Any Rust encoder must be byte-exact against ShogiDojo's Python encoder**, verified via fixture tests (`tools/`). Encoding drift = model predicts wrong moves silently.

## Commands

Godot is not on PATH — always invoke by full path.

```bash
# Open editor
~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 --editor --path .

# Headless run (useful for smoke tests)
~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 --headless --path . <scene_or_script>
```

Rust / native (once Phase 4 lands):

```bash
# Desktop dev build — output goes to native/bin/linux/x86_64/
cargo build --release --manifest-path native/shogi_core/Cargo.toml

# Unit + perft tests
cargo test --manifest-path native/shogi_core/Cargo.toml

# Android cross-compile (Phase 6)
cargo ndk -t arm64-v8a build --release --manifest-path native/shogi_core/Cargo.toml
```

## Conventions

- LF line endings, UTF-8, enforced via `.gitattributes` + `.editorconfig`.
- `.godot/` (editor cache) and `/android/` (export keystore / build artifacts) are gitignored — never commit.
- Piece orientation in the UI: 先手 bottom / upright, 後手 top / rotated 180°.
- Kanji pieces are rendered as text `Label`s for now; sprite assets are a Phase 7 stretch goal.

## When Working Here

- Check `ROADMAP.md` before adding features — the phase plan is deliberate (GDScript rules first, Rust port later) to keep the game playable end-to-end at every step. Don't jump ahead to Rust/AI work during Phases 1–3.
- The "Open Questions" section at the bottom of `ROADMAP.md` lists decisions that are *not yet made* (千日手 variant, 入玉 rule, branding, distribution). Do not invent answers — surface the question.
