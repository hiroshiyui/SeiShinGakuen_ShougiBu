---
name: docs-engineering
description: Writing/updating project documentation (README, ROADMAP, CLAUDE.md, docs/architecture.md, ADRs, asset-folder READMEs) for SeiShinGakuen_ShougiBu. Use when the user asks to update docs, draft an ADR, write a changelog, or update a Play Store / GitHub Release listing.
argument-hint: task description
---

# Documentation Engineering

You are performing documentation tasks for **清正学園将棋部** (SeiShinGakuen_ShougiBu) — a single-player Android Shogi (本将棋) game built with Godot 4.6.2 (Mobile renderer) and a Rust GDExtension (`shogi_core`) for rules + AI.

## Current state of project documentation

Read this before assuming files exist. The repo has solid technical documentation; user-facing / store-listing material is lighter.

**Currently exists:**

| File | Status | Purpose |
|---|---|---|
| [README.md](../../README.md) | ✅ exists (English) | Project overview, screenshot, build instructions, tech stack |
| [CLAUDE.md](../../CLAUDE.md) | ✅ exists | Project context for Claude Code; what to read before planning |
| [ROADMAP.md](../../ROADMAP.md) | ✅ exists | Phased plan + "shipped differently" notes per completed phase |
| [docs/architecture.md](../../docs/architecture.md) | ✅ exists | Two-layer architecture walkthrough (GDScript ↔ Rust GDExtension) |
| [docs/adr/](../../docs/adr/) | ✅ has entries | Architecture Decision Records, e.g. `0005-font-subset-pipeline.md` |
| [docs/android-build.md](../../docs/android-build.md) | ✅ exists | APK export pipeline notes |
| [docs/android-gotchas.md](../../docs/android-gotchas.md) | ✅ exists | Android-only behaviour notes (orientation int, touch double-fire, …) |
| Per-asset READMEs | ✅ partial | `assets/fonts/{fude-goshirae,noto-serif-jp}/README.md` |

**Does not yet exist** (don't pretend they do; ask before creating):

- `CHANGELOG.md`
- `LICENSE` — *no license file in the repo today*; copyright is implicit. Don't fabricate one. If the user wants to add a license, that's a deliberate decision worth a separate conversation.
- `PRIVACY-POLICY.md` (Play Store will require a URL once the app goes live)
- `NOTICES.md` / third-party attribution document
- `fastlane/` directory (no Play Store / F-Droid metadata tree yet)

When the user asks about one of the missing files, confirm whether to create it before writing — do not silently scaffold a tree of new docs.

## Tone and writing style

- README is clear English technical prose with a few opinionated turns of phrase. Match it.
- ROADMAP is structured by phase, with "shipped differently" callouts under completed phases that note what changed from the original plan. Maintain that pattern.
- ADRs are short — context, decision, consequences — not essays. Number sequentially.
- **Bilingual content is welcome.** Game UI and character names are Japanese; documentation can mix English prose with Japanese terms (`先生モード`, `加藤先生`, etc.) where they're the natural label. The user is comfortable in both.
- **Traditional Chinese (zh-TW)** is occasionally used in the user's other projects. This repo doesn't have zh-TW docs yet; only add them if explicitly asked. If asked, use **Traditional Chinese characters only** (no Simplified) — the user is Taiwanese.
- **Do not add emojis** unless the user explicitly asks. Existing docs have none.

## Project facts to keep accurate

When writing or editing docs, double-check these from the source rather than copying from another project. They've gone stale before.

- **App name**: 清正学園将棋部 (SeiShinGakuen_ShougiBu in roman). Use the kanji form in user-facing copy; either is fine in technical prose.
- **Package id (Android)**: `org.seishingakuen.shougibu` — set in [`export_presets.cfg`](../../export_presets.cfg) `package/unique_name`. **Immutable** for Play Store continuity.
- **Display name (Android launcher)**: 清正学園将棋部, set in `package/name`.
- **Version**: read [`export_presets.cfg`](../../export_presets.cfg) `version/name` and `version/code` — single source of truth.
- **Engine**: Godot 4.6.2 (Mobile renderer, Vulkan backend on Android), `~/.local/bin/Godot_v4.6.2-stable_linux.x86_64`.
- **Native layer**: Rust GDExtension at [`native/shogi_core/`](../../native/shogi_core/), shipped as a cdylib loaded via [`addons/shogi_core.gdextension`](../../addons/shogi_core.gdextension). Same `.so` serves desktop (`x86_64-unknown-linux-gnu`) and Android (`aarch64-linux-android`).
- **Inference**: AlphaZero-style policy + value network, Bonanza-trained, 1.3 MB ONNX at [`models/bonanza.onnx`](../../models/bonanza.onnx). Runs via the `tract` crate in Rust; on Android the model is extracted from the APK to `user://` on first launch.
- **Encoder invariant**: 45-plane position + 139-plane move index, byte-parity-tested against ShogiDojo's Python implementation via `tools/gen_fixtures.py` → `native/shogi_core/src/parity_tests.rs`. Don't describe the encoder casually — the project's defense against silent AI breakage is "the bytes are identical."
- **Search**: single-threaded PUCT MCTS (no virtual loss, no transposition table) with Dirichlet noise at the root. Temperature-sampled — `tools/build_all.sh` and the Lv 1–8 strength presets in `Settings.gd` drive the playouts/τ pair.
- **Rules**: full board + hand handling, check, 二歩, 打ち歩詰め, 千日手 (incl. perpetual-check variant), 入玉 detection. SFEN parse + serialize.
- **Distribution**: Google Play (AAB). F-Droid is **not** currently set up.
- **License**: not yet declared. The repo has no `LICENSE` file. Don't quote a license unless one lands.
- **Author**: `Hui-Hong You` per `git log`.
- **GitHub remote**: `git@github.com:hiroshiyui/SeiShinGakuen_ShougiBu.git`.

When updating any "Third-party" / dependency content, verify against [`native/shogi_core/Cargo.toml`](../../native/shogi_core/Cargo.toml) and the Godot export — don't trust this skill or the README to be in sync indefinitely.

## Specific document guidance

### README.md

The existing README covers: tagline → screenshots → features → tech stack → build → deploy → tests. When updating it:

- Preserve that structure.
- Update the "Features" section in lockstep with code changes — it's currently the project's most authoritative description of behaviour for a casual reader.
- The "Tech Stack" section names Godot 4.6.2 + Rust GDExtension + tract + bonanza.onnx. Keep the version numbers accurate.
- Avoid over-promising AI strength. Lv 8 (2048 playouts) is strong for casual players but won't beat a kyu-ranked human — describe it honestly.

### ROADMAP.md

Phased plan. Each completed phase has a "shipped differently" subsection capturing where the implementation diverged from the original plan. **That's the canonical log of what the code actually does** — keep it accurate when phases complete or pivot. Don't rewrite history; add notes.

### CLAUDE.md

Project context for Claude Code itself. Keep it short and load-bearing: project layout, tech stack, what files are byte-parity-sensitive (encoder fixtures), what Godot path to use, where Android gotchas are documented. The current file is well-tuned — minor edits, not rewrites.

### docs/architecture.md

The walkthrough of the GDScript ↔ Rust split. Key sections to keep faithful:

- The FFI surface is in [`native/shogi_core/src/lib.rs`](../../native/shogi_core/src/lib.rs) — everything else (board, encoder, MCTS, NN, rules) is internal.
- GDScript owns scenes, input, turn orchestration, the MCTS Thread; Rust owns rules, encoding, MCTS, ONNX inference.
- The same compiled `.so` serves Linux desktop and Android (`aarch64-linux-android`) via `cargo-ndk`.

### docs/adr/

Numbered Architecture Decision Records, e.g. `0005-font-subset-pipeline.md`. New ADRs:

1. Use the next sequential number (`ls docs/adr/` for the latest).
2. Keep them short: **Context** (why we needed a decision), **Decision** (what we picked), **Consequences** (good and bad). One page is plenty.
3. ADRs are not retroactive — record the decision when it's made; don't backfill old decisions unless the user wants a history pass.

### Asset-folder READMEs

`assets/fonts/{fude-goshirae,noto-serif-jp}/README.md` describe vendored fonts and how the subset pipeline ([`tools/build_font_subsets.py`](../../tools/build_font_subsets.py)) trims them. If the subset pipeline changes (e.g. another font lands), update both READMEs in lockstep.

### CHANGELOG.md (if/when created)

Project has no changelog yet. When the user asks for one:

1. Ask whether they want Keep-a-Changelog at the repo root, Play Store "What's new" copy only, GitHub Release notes only, or some combination.
2. Once they choose, stick with it.

To gather material since the previous tag:

```bash
git log --oneline <previous-tag>..HEAD     # if a previous tag exists
git log --oneline                          # for the very first version (currently true)
```

Commit prefixes (`feat(scope):`, `fix(scope):`, `docs:`, `chore:`, `refactor:`, `build:`) map cleanly onto changelog sections.

### PRIVACY-POLICY.md (if/when created)

Play Store will require a privacy policy URL before publication. The honest privacy story is short:

- The app **makes no network requests** — all inference is on-device via `tract` against `models/bonanza.onnx`.
- The **only** writable persistence is `user://prefs.cfg` (UI prefs + AI level) and `user://saved_game.cfg` (current SFEN + mode + level). No analytics, no telemetry, no ads, no crash reporting.
- The bundled ONNX model is extracted from the APK to `user://` on first launch (Android limitation: `tract` can't open files inside the PCK/APK). It is not modified after.
- Permissions declared: none beyond what Godot's mobile template ships with — no INTERNET, no storage, no biometric.

Verify each claim against the code before publishing — claims must be true.

### Play Store store listing (if/when uploading)

Required text fields:

- **App name**: 清正学園将棋部 (50 chars max). Already fits.
- **Short description**: 80 chars max. Hand-written.
- **Full description**: 4000 chars max. Mirror the README's "Features" plus a sentence on the AI character roster (Lv 1 佐藤竜太郎 … Lv 8 加藤よしこ).
- **Screenshots**: at least 2, ideally 4–8. Use Godot debug builds, hide the FPS counter.
- **Feature graphic**: 1024×500.
- **What's new**: per-version, max 500 chars per language.

If the user wants Japanese + English store listings, mirror the text fields under both locales in Play Console.

## Task: $ARGUMENTS
