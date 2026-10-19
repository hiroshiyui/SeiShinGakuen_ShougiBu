---
name: release-engineering
description: Release engineering tasks including version bumping, building signed release APKs, creating git tags, and preparing GitHub Release artefacts. Use when the user asks to prepare a release, bump the version, tag a release, or build for distribution.
argument-hint: task description
---

# Release Engineering

You are performing release engineering tasks for **清正学園将棋部** (SeiShinGakuen_ShougiBu) — a single-player Android Shogi game built with Godot 4.7.2 (Mobile renderer) and a Rust GDExtension. The same signed APK is distributed through **GitHub Releases** (primary) and **itch.io** (secondary, uploaded by hand) — see [`docs/distribution.md`](../../docs/distribution.md). **Google Play is explicitly out of scope** — see ROADMAP Open Questions for the rationale (Play developer-account dependencies, mandatory privacy-policy URLs, upload-key custody, the policy-compliance ratchet for a single-player offline game). Don't suggest Play Store steps unless the user reopens that decision.

## Current state of the project

The release infrastructure is real and tested — confirm anything that looks ambiguous against the actual files rather than this skill. The previous release (`git describe --tags --abbrev=0`, and its `chore(release):` commit via `git show <tag> --stat`) is the best template for what a release touches.

- **Build pipeline.** [`tools/build_all.sh`](../../tools/build_all.sh) drives everything (Rust desktop + Android cross-compile, font subsets, Godot export). Flags: `--release` for a signed APK, `--skip-{desktop,android,fonts,apk}`, `--test` for `cargo test`. (`--aab` produces a Play-Store-only artefact we don't ship — leave it alone.)
- **Versioning.** Three fields, kept in sync by the release commit:
  - `version/code` and `version/name` in [`export_presets.cfg`](../../export_presets.cfg) (`[preset.0.options]`) — what Android sees; `version/name` also suffixes the output filename.
  - `config/version` in [`project.godot`](../../project.godot) — the runtime source for the on-screen `v<X.Y.Z>` badge on the main menu.
- **Signing — release.** Keystore outside the repo at `~/.local/share/godot/keystores/seishingakuen-release.keystore`, alias `seishingakuen`. Password in `.android-release-pass` at the repo root (gitignored). The script exports `GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD}` for one export only — **no signing secrets in `export_presets.cfg`** (its `keystore/*` fields stay empty), **no patches to Godot's global `editor_settings-4.7.tres`**. Expected cert: `CN=Hiroshi Y., …, C=TW`, SHA-256 `a00c27ca1d929a25f129d4c6bb6b6c36212e9f2c049628325caca4e3ec5fed8d`.
- **Signing — debug.** Godot's own debug keystore (`CN=Godot, OU=Godot Engine, O=Stichting Godot, C=NL`), configured globally. Because it's a **different cert** from release, a device that has a debug build can't `adb install -r` a release build (and vice versa) — see the smoke-install step.
- **Tags.** Annotated, no `v` prefix (e.g. `1.0.7`); each tag points at its `chore(release):` commit.
- **Release docs** (all updated in the release commit — see "Release Docs" below): `CHANGELOG.md`, `docs/release-notes/<X.Y.Z>.md`, `fastlane/metadata/android/ja/changelogs/<versionCode>.txt`.
- **Tests.** Rust unit + parity + perft in `native/shogi_core/src/`; GDScript headless suites in `scripts/tests/`. All five must pass — see "Test Gate".

`package/unique_name="org.seishingakuen.shougibu"` — Android package id. Effectively immutable: changing it makes Android treat any new install as an unrelated app, breaks updates for sideloaders, and orphans every saved game in `user://`. Don't change it.

## Version Scheme

- **`version/name`**: SemVer `MAJOR.MINOR.PATCH`. In practice small user-visible features and fixes ship as **patch** releases (1.0.6 = new icon, 1.0.7 = dialog blur + splash fix); ask the user, recommending patch unless the change is substantial.
- **`version/code`**: +1 per release, never reused or decremented. Android refuses an install whose `versionCode` ≤ the installed one, so an un-bumped APK won't update existing sideloaders. It also names the fastlane changelog file.

## Release Process

Confirm at each step that's user-visible.

1. **Confirm intent.** Ask which version (patch / minor / major). Show what's landed since the last tag (`git log --oneline <prev-tag>..HEAD`) so the user can judge.
2. **Working tree clean** on `main`, in sync with `origin/main`.
3. **Run the Test Gate — hard gate.** Stop and report verbatim if anything fails.
4. **Bump version** — all three fields:
   ```bash
   sed -i 's/^version\/code=<N>$/version\/code=<N+1>/; s/^version\/name="<old>"$/version\/name="<X.Y.Z>"/' export_presets.cfg
   sed -i 's/^config\/version="<old>"$/config\/version="<X.Y.Z>"/' project.godot
   ```
   Then `git grep -n '<old>'` to catch stragglers (ignore third-party versions in `Cargo.lock`).
5. **Write the release docs** — see "Release Docs".
6. **Build:** `./tools/build_all.sh --release` (full pipeline; don't skip fonts) → `build/seishingakuen-release-v<X.Y.Z>.apk` + `.apk.idsig`. Needs `.android-release-pass`.
7. **Font-subset noise.** The build regenerates the subset `.otf` files and they often come out byte-different with identical glyphs. If `git status` shows them modified, compare cmaps against `HEAD` (fontTools `getBestCmap()`); if no codepoints were added or removed, `git checkout -- assets/fonts`. If glyphs *did* change, that's a real UI-string change that should have been committed earlier — surface it rather than folding it into the release commit.
8. **Verify the artefact:**
   ```bash
   A=build/seishingakuen-release-v<X.Y.Z>.apk
   ~/Android/Sdk/build-tools/36.0.0/apksigner verify --print-certs $A | grep -E 'Signer #1 certificate (DN|SHA-256)'
   unzip -l $A | grep -E 'libshogi_core|bonanza'
   ~/Android/Sdk/build-tools/36.0.0/aapt2 dump badging $A | head -1   # versionCode / versionName
   ```
   Cert must be `CN=Hiroshi Y.` with the SHA-256 above — `CN=Godot` means signing fell back to debug: **stop**. Both `lib/arm64-v8a/libshogi_core.so` and `assets/models/bonanza.onnx` must be present.
9. **Smoke-install** if `adb devices` shows a device:
   - `adb install -r $A`. If it fails with a signature mismatch (the device has a debug build), uninstall and reinstall without asking (per user preference) — but **tell the user plainly that this wiped the on-device saved game and settings**. Check the actual `adb install` output; don't infer success from a fallback branch.
   - Wake the screen first if needed (`adb shell input keyevent KEYCODE_WAKEUP; adb shell wm dismiss-keyguard`) — a black screencap usually means the display is dozing, not a crash.
   - First launch after a fresh install sits on the Godot boot splash ~10 s while the model is extracted to `user://`.
   - Confirm the menu badge shows `v<X.Y.Z>`, start a game vs AI, play a move (e.g. 7六歩), and confirm the AI replies — proves the native lib and model work in the signed bundle.
10. **Release commit + tag** (see "Git Conventions"). Commit exactly: `export_presets.cfg`, `project.godot`, `CHANGELOG.md`, `docs/release-notes/<X.Y.Z>.md`, `fastlane/metadata/android/ja/changelogs/<code>.txt`.
11. **Push** only after explicit confirmation: `git push origin main && git push origin <X.Y.Z>`.
12. **Publish the GitHub Release** (see below) — confirm first.
13. **itch.io** — once the GitHub Release is live, use the `publish-to-itch-dot-io` skill: it verifies the APK, then the user uploads it by hand in the web UI.

### Git Conventions

- Release commit: `chore(release): version <X.Y.Z>`, no body needed.
- **No GPG signing**, no `--signoff`. Add a `Co-Authored-By:` trailer when Claude collaborated — mirror the identity string from the most recent Claude-co-authored commit (`git log -5 --format=%B | grep Co-Authored-By`), adjusting for the current model.
- See the `commit-and-push` skill for general commit workflow.

### Tag Convention

- `git tag -a <X.Y.Z> -m "<X.Y.Z>"` on the release commit. No `v` prefix.
- Push `main` first, then the tag.

## Release Docs

Gather material with `git log --oneline <prev-tag>..HEAD`. User-facing prose is **Japanese**; commit lists stay in their original English.

1. **`CHANGELOG.md`** (Keep a Changelog). Insert a section right under `## [Unreleased]`:
   ```markdown
   ## [<X.Y.Z>] — <YYYY-MM-DD>

   ### Added | Changed | Fixed
   - <Japanese bullet, wrapped ~70 cols>

   [Full release notes](./docs/release-notes/<X.Y.Z>.md) ·
   [GitHub Release](https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/releases/tag/<X.Y.Z>)
   ```
   And in the link footer: point `[Unreleased]` at `compare/<X.Y.Z>...HEAD` and add `[<X.Y.Z>]: …/compare/<prev>...<X.Y.Z>`.
2. **`docs/release-notes/<X.Y.Z>.md`** — this file is also the GitHub Release body. Structure (copy the previous one):
   ```markdown
   # <X.Y.Z> — <Japanese subtitle>

   <one-line Japanese summary>

   ## ハイライト

   - **<Japanese headline>** <1–3 sentences>

   ## Changes

   ### Features / Fixes / Tooling & docs
   - <conventional-commit subject> (<short hash>)

   **Full Changelog**: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/compare/<prev>...<X.Y.Z>
   ```
   Commit hashes are of the commits being released (they exist before the release commit).
3. **`fastlane/metadata/android/ja/changelogs/<versionCode>.txt`** — short Japanese bullets prefixed `・`, one line each. (F-Droid-format metadata kept in-repo; it isn't a live distribution channel — don't claim the app is on F-Droid.)

## Test Gate

Before any version bump, all five must pass — Rust first, because parity failures invalidate everything downstream:

```bash
G=~/.local/bin/Godot_v4.7.2-stable_linux.x86_64

# 1. Rust: unit + parity (encoder ↔ ShogiDojo) + perft
cargo test --manifest-path native/shogi_core/Cargo.toml --release

# 2–5. GDScript suites
$G --headless -s res://scripts/tests/rules_tests.gd --path .         # FFI rules: check, pin, 二歩, 打ち歩詰め, undo, …
$G --headless -s res://scripts/tests/characters_tests.gd --path .    # roster + .tres validity
$G --headless -s res://scripts/tests/persistence_tests.gd --path .   # save/resume, prefs, atomic model copy
$G --headless -s res://scripts/tests/opening_book_tests.gd --path .  # every book USI legal, etc.
```

Each GDScript suite prints `All … tests passed.` and exits 0, or `push_error`s the failing cases and exits 1. The `ObjectDB instances were leaked` / `resources still in use at exit` warnings at shutdown are pre-existing noise, not failures.

If anything fails: **stop** (no bump, no build, no tag), report the failing case verbatim, fix on a separate commit, and re-run the gate from the top.

`core_smoke.gd` / `ai_smoke.gd` aren't part of the gate.

## GitHub Release

Upload both the APK and its `.idsig`, with the release-notes file as the body:

```bash
gh release create <X.Y.Z> --title "<X.Y.Z>" \
  --notes-file docs/release-notes/<X.Y.Z>.md \
  build/seishingakuen-release-v<X.Y.Z>.apk \
  build/seishingakuen-release-v<X.Y.Z>.apk.idsig
gh release view <X.Y.Z> --json isDraft,isPrerelease,assets   # confirm public + both assets
```

## Signature & Keystore Reference

```bash
# Keystore fingerprint (compare with the APK's Signer #1 SHA-256)
keytool -list -keystore ~/.local/share/godot/keystores/seishingakuen-release.keystore \
  -storepass "$(cat .android-release-pass)" -alias seishingakuen
```

The keystore is irreplaceable: every release of this package id must carry the same cert, or existing sideloaders (from GitHub *or* itch.io) can't update without uninstalling and losing their saved game. Backups are the user's responsibility.

## Important Reminders

- **Confirm before any push, tag push, GitHub Release, or anything public.**
- **Never ship a debug-signed APK.** `CN=Godot` in `apksigner` output = stop.
- **`version/code` only goes up**, and all three version fields move together.
- **Same binary everywhere.** itch.io gets the exact APK attached to the GitHub Release (the itch skill checks the SHA-256).
- **Report device side effects honestly** — an uninstall during smoke-testing wipes the user's on-device save; say so.
