---
name: docs-engineering
description: Writing/updating project documentation (README, ROADMAP, CLAUDE.md, docs/architecture.md, ADRs, asset-folder READMEs) for SeiShinGakuen_ShougiBu. Use when the user asks to update docs, draft an ADR, write a changelog, or update GitHub Release notes.
argument-hint: task description
---

# Documentation Engineering

You are performing documentation tasks for **清正学園将棋部** (SeiShinGakuen_ShougiBu) — a single-player Android Shogi (本将棋) game built with Godot 4.7.2 (Mobile renderer) and a Rust GDExtension (`shogi_core`) for rules + AI.

## Current state of project documentation

Read this before assuming files exist. The repo has solid technical documentation plus store-listing material for F-Droid and itch.io.

**Currently exists:**

| File | Status | Purpose |
|---|---|---|
| [README.md](../../README.md) | ✅ exists (Japanese) | Project overview, download badges, screenshots, build instructions, tech stack |
| [CLAUDE.md](../../CLAUDE.md) | ✅ exists | Project context for Claude Code; what to read before planning |
| [ROADMAP.md](../../ROADMAP.md) | ✅ exists | Phased plan; completed phases condensed to digests with "shipped differently" notes |
| [docs/architecture.md](../../docs/architecture.md) | ✅ exists | Two-layer architecture walkthrough (GDScript ↔ Rust GDExtension) |
| [docs/adr/](../../docs/adr/) | ✅ has entries | Architecture Decision Records, e.g. `0005-font-subset-pipeline.md` |
| [docs/android-build.md](../../docs/android-build.md) | ✅ exists | APK export pipeline notes |
| [docs/android-gotchas.md](../../docs/android-gotchas.md) | ✅ exists | Android-only behaviour notes (orientation int, touch double-fire, …) |
| Per-asset READMEs | ✅ partial | `assets/fonts/{fude-goshirae,noto-serif-jp}/README.md` |
| [CHANGELOG.md](../../CHANGELOG.md) | ✅ exists | Keep a Changelog, Japanese bullets; one section per release |
| [docs/release-notes/](../../docs/release-notes/) | ✅ one file per release | Japanese highlights + commit list; doubles as the GitHub Release body |
| [docs/distribution.md](../../docs/distribution.md) | ✅ exists (Japanese) | Distribution channels and the itch.io page text |
| [fastlane/metadata/android/](../../fastlane/metadata/android/) | ✅ `ja` + `en-US` | F-Droid listing: title, descriptions, screenshots, per-versionCode changelogs |
| [LICENSE](../../LICENSE) | ✅ exists | GPL-3.0-or-later |

**Does not yet exist** (don't pretend they do; ask before creating):

- `NOTICES.md` / third-party attribution document
- `PRIVACY-POLICY.md` — intentionally absent. The app requests no network permission and none of its channels (F-Droid, itch.io, GitHub Releases) requires one; Google Play, which would, is out of scope (see ROADMAP Open Questions). Don't propose creating it unless the user reopens that decision.

When the user asks about one of the missing files, confirm whether to create it before writing — do not silently scaffold a tree of new docs.

## Tone and writing style

- README is maintained entirely in Japanese: clear technical prose with a few opinionated turns of phrase. Match it, and don't draft README sections in English.
- ROADMAP is structured by phase, with "shipped differently" callouts under completed phases that note what changed from the original plan. Maintain that pattern.
- ADRs are short — context, decision, consequences — not essays. Number sequentially.
- **Bilingual content is welcome.** Game UI and character names are Japanese; documentation can mix English prose with Japanese terms (`先生モード`, `加藤先生`, etc.) where they're the natural label. The user is comfortable in both.
- **Traditional Chinese (zh-TW)** is occasionally used in the user's other projects. This repo doesn't have zh-TW docs yet; only add them if explicitly asked. If asked, use **Traditional Chinese characters only** (no Simplified) — the user is Taiwanese.
- **Do not add emojis** unless the user explicitly asks. Existing docs have none.

## Project facts to keep accurate

When writing or editing docs, double-check these from the source rather than copying from another project. They've gone stale before.

- **App name**: 清正学園将棋部 (SeiShinGakuen_ShougiBu in roman). Use the kanji form in user-facing copy; either is fine in technical prose.
- **Package id (Android)**: `org.seishingakuen.shougibu` — set in [`export_presets.cfg`](../../export_presets.cfg) `package/unique_name`. Effectively **immutable**: changing it makes Android treat any new install as an unrelated app, breaks "update existing install" for sideloaders, and orphans every saved game in `user://`.
- **Display name (Android launcher)**: 清正学園将棋部, set in `package/name`.
- **Version**: read [`export_presets.cfg`](../../export_presets.cfg) `version/name` and `version/code` — single source of truth.
- **Engine**: Godot 4.7.2 (Mobile renderer, Vulkan backend on Android), `~/.local/bin/Godot_v4.7.2-stable_linux.x86_64`.
- **Native layer**: Rust GDExtension at [`native/shogi_core/`](../../native/shogi_core/), shipped as a cdylib loaded via [`addons/shogi_core.gdextension`](../../addons/shogi_core.gdextension). Same `.so` serves desktop (`x86_64-unknown-linux-gnu`) and Android (`aarch64-linux-android`).
- **Inference**: AlphaZero-style policy + value network, Bonanza-trained, 1.3 MB ONNX at [`models/bonanza.onnx`](../../models/bonanza.onnx). Runs via the `tract` crate in Rust; on Android the model is extracted from the APK to `user://` on first launch.
- **Encoder invariant**: 45-plane position + 139-plane move index, byte-parity-tested against ShogiDojo's Python implementation via `tools/gen_fixtures.py` → `native/shogi_core/src/parity_tests.rs`. Don't describe the encoder casually — the project's defense against silent AI breakage is "the bytes are identical."
- **Search**: single-threaded PUCT MCTS (no virtual loss, no transposition table) with Dirichlet noise at the root. Temperature-sampled — `tools/build_all.sh` and the Lv 1–8 strength presets in `Settings.gd` drive the playouts/τ pair.
- **Rules**: full board + hand handling, check, 二歩, 打ち歩詰め, 千日手 (incl. perpetual-check variant), 入玉 detection. SFEN parse + serialize.
- **Distribution**: three channels. **F-Droid** (accepted 2026-11; built from source and signed by F-Droid, updated automatically from release tags), **GitHub Releases** (signed APK + `.idsig` sidecar, the primary source of the sideload APK) and **itch.io** (the same APK, uploaded by hand). The F-Droid build carries a different signature, so it cannot update over, or be updated by, the sideload APK. Google Play is explicitly out of scope (see ROADMAP Open Questions).
- **License**: not yet declared. The repo has no `LICENSE` file. Don't quote a license unless one lands.
- **Author**: `Hui-Hong You` per `git log`.
- **GitHub remote**: `git@github.com:hiroshiyui/SeiShinGakuen_ShougiBu.git`.

When updating any "Third-party" / dependency content, verify against [`native/shogi_core/Cargo.toml`](../../native/shogi_core/Cargo.toml) and the Godot export — don't trust this skill or the README to be in sync indefinitely.

## Specific document guidance

### README.md

The existing README covers: tagline → screenshots → features → tech stack → build → deploy → tests. When updating it:

- Preserve that structure.
- Update the "Features" section in lockstep with code changes — it's currently the project's most authoritative description of behaviour for a casual reader.
- The "Tech Stack" section names Godot 4.7.2 + Rust GDExtension + tract + bonanza.onnx. Keep the version numbers accurate.
- Avoid over-promising AI strength. Lv 8 (2048 playouts) is strong for casual players but won't beat a kyu-ranked human — describe it honestly.

### ROADMAP.md

Phased plan. Each completed phase has a "shipped differently" subsection capturing where the implementation diverged from the original plan. **That's the canonical log of what the code actually does** — keep it accurate when phases complete or pivot.

**Condense completed phases.** Completed phases (✅) are kept as short digests, not full checklists. The full original text stays in git history, and the Phase Plan intro points readers there. When a phase completes, or a completed phase has grown long, condense it:

1. Mark the heading ✅ once every item is checked.
2. Write one paragraph on what shipped. For a large phase, use a few themed bullets instead (e.g. Phase 7: look & feel, game flow, characters, game records).
3. Keep the "shipped differently" divergences that are **still true**, especially ones a future reader would otherwise get wrong (e.g. `tract` not `ort`, mailbox not bitboards). Fold each into one line.
4. Drop notes that later work made obsolete (e.g. "not implemented yet" for a feature that later landed), interim numbers (old APK sizes), and planned API shapes that never shipped. Before dropping a note, check the code to confirm it is really stale.
5. Keep cross-references (ADR numbers, `docs/android-gotchas.md`, `docs/architecture.md`, test scripts) so the detail stays findable. If a gotcha or rationale would be lost, move it into the right doc first.
6. Leave in-progress and proposed phases, and the sections after the Phase Plan, untouched.
7. Commit the condensing on its own, with a `docs(roadmap): …` message, so the full text can be found with `git log -p ROADMAP.md`.

Don't rewrite history in any other way. Divergences are recorded as notes, and condensing only shortens them.

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

Project has no changelog file yet — release notes live in GitHub
Releases (see release-engineering skill). When the user asks for a
proper `CHANGELOG.md`:

1. Ask whether they want Keep-a-Changelog at the repo root in addition
   to the GitHub Release notes, or as a replacement for them.
2. Once they choose, stick with it.

To gather material since the previous tag:

```bash
git log --oneline <previous-tag>..HEAD     # since the previous tag
git log --oneline                          # before the first tag
```

Commit prefixes (`feat(scope):`, `fix(scope):`, `docs:`, `chore:`, `refactor:`, `build:`, `test:`) map cleanly onto changelog sections.

### GitHub Release notes

The shipping changelog channel today. The release-engineering skill
owns the `gh release create` invocation; this skill is responsible for
the prose. Structure used by 0.2.0:

- `## Highlights` — 1–3 user-visible bullets, in Japanese (the audience
  for this app reads Japanese; technical commit-level details are not
  the headline).
- `## Changes` grouped by Conventional Commit type (Features /
  Fixes & refactors / Tooling & docs / Tests).
- `**Full Changelog**: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/compare/<prev>...<X.Y.Z>`
  — auto-link to the GitHub compare view; omit on the first release
  and use `commits/<X.Y.Z>` instead.

## Task: $ARGUMENTS
