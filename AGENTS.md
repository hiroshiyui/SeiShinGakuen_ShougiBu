# Repository Guidelines

## Project Structure & Module Organization

清正学園将棋部 is a Godot 4.6.2 Android Shogi game with a Rust GDExtension.
GDScript UI, scenes, and tests live in `scripts/` and `scenes/`. The native
rules, encoder, MCTS, and ONNX inference layer lives in `native/shogi_core/`;
its compiled libraries are copied to `native/bin/` and are not tracked.
Assets are grouped by purpose under `assets/` (`fonts/`, `themes/`, `ui/`,
`characters/`, `sounds/`, etc.). Documentation is in `docs/`, with ADRs in
`docs/adr/`. The bundled AI model is `models/bonanza.onnx`.

## Build, Test, and Development Commands

Use the full Godot path; it is not assumed to be on `PATH`.

```bash
# Open the Godot editor
~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 --editor --path .

# Build the Rust GDExtension for desktop development
cargo build --release --manifest-path native/shogi_core/Cargo.toml

# Full local pipeline: Rust, Android cross-build, fonts, APK export
./tools/build_all.sh

# Signed release APK
./tools/build_all.sh --release
```

Run `./tools/build_font_subsets.py` after adding Japanese UI strings.

## Coding Style & Naming Conventions

Use UTF-8 and LF line endings. GDScript uses tabs as in the existing files,
`snake_case` for variables/functions, `PascalCase` for classes, and
`ALL_CAPS` for constants. Rust follows standard `rustfmt` conventions. Keep
FFI-facing APIs in `native/shogi_core/src/lib.rs` narrow and Godot-friendly.
Commit Godot asset files together with their `.import` sidecars.

## Testing Guidelines

Rust tests cover unit behavior, perft, and ShogiDojo encoder byte parity:

```bash
cargo test --manifest-path native/shogi_core/Cargo.toml
```

GDScript headless suites live in `scripts/tests/`:

```bash
~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 --headless -s res://scripts/tests/rules_tests.gd --path .
~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 --headless -s res://scripts/tests/characters_tests.gd --path .
~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 --headless -s res://scripts/tests/persistence_tests.gd --path .
~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 --headless -s res://scripts/tests/opening_book_tests.gd --path .
```

Any change to `encode.rs` or `move_index.rs` must regenerate fixtures with
`tools/gen_fixtures.py` and pass parity tests.

## Commit & Pull Request Guidelines

History uses Conventional Commits, often with scopes: `fix(android): ...`,
`feat(ui): ...`, `docs: ...`, `chore(release): version 1.0.4`. Keep subjects
imperative, lowercase after the colon, and omit trailing periods. PRs should
describe behavior changes, list tests run, link issues when relevant, and add
screenshots for UI changes.

## Security & Configuration Tips

Never commit `.android-release-pass`, keystores, `build/`, `.godot/`,
`android/`, `native/**/target`, or `native/bin/`. Android package id
`org.seishingakuen.shougibu` is effectively immutable. Release builds are
distributed as signed APKs via GitHub Releases unless the release plan changes.
