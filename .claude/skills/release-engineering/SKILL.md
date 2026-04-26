---
name: release-engineering
description: Release engineering tasks including version bumping, building signed release APKs / AABs, creating git tags, and preparing Google Play / GitHub Release artefacts. Use when the user asks to prepare a release, bump the version, tag a release, or build for distribution.
argument-hint: task description
---

# Release Engineering

You are performing release engineering tasks for **清正学園将棋部** (SeiShinGakuen_ShougiBu) — a single-player Android Shogi game built with Godot 4.6.2 (Mobile renderer) and a Rust GDExtension. Distribution target is **Google Play** (AAB).

## Current state of the project

Read this before assuming anything. The repo's release infrastructure is real and tested — confirm anything that looks ambiguous against the actual files rather than this skill.

- **Build pipeline.** [`tools/build_all.sh`](../../tools/build_all.sh) drives the whole pipeline (Rust desktop + Android cross-compile, font subsets, Godot export). Flags: `--release` for a signed APK, `--aab` for a signed AAB (implies `--release`), `--skip-{desktop,android,fonts,apk}`, `--test` for `cargo test`.
- **Versioning.** `version/code` and `version/name` live in [`export_presets.cfg`](../../export_presets.cfg) under `[preset.0.options]`. They are the single source of truth — the script reads `version/name` to tag output filenames (`build/seishingakuen-release-v0.1.0.apk`).
- **Signing — release.** Keystore lives outside the repo at `~/.local/share/godot/keystores/seishingakuen-release.keystore`, alias `seishingakuen`. The password sits in `.android-release-pass` at the repo root (gitignored). The script reads it and exports `GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD}` for the duration of one export — **no signing secrets in `export_presets.cfg`**, **no patches to Godot's global `editor_settings-4.6.tres`**.
- **Signing — debug.** Standard Android debug keystore, configured globally in `editor_settings-4.6.tres`. No password file required.
- **Tags.** Zero tags exist in the repo today. The convention below is a *proposal* — confirm with the user before the first one.
- **Distribution.** Google Play is the primary target. F-Droid is **not** currently set up (no `fastlane/`); only mention it if the user explicitly asks.
- **Tests.** Rust core has unit + parity + perft tests in `native/shogi_core/src/{tests.rs,parity_tests.rs}`. GDScript headless test suites live under `scripts/tests/`: `rules_tests.gd` (FFI rules), `characters_tests.gd` (character roster + `.tres` validity), `persistence_tests.gd` (save/resume + atomic model copy), plus the older `core_smoke.gd` and `ai_smoke.gd`. **Every release must pass all four real test suites** — see "Test Gate" below.

Current version (verify in [`export_presets.cfg`](../../export_presets.cfg) before acting — these go stale):

```
version/code=1
version/name="0.1.0"
```

`package/unique_name="org.seishingakuen.shougibu"` — this is the **immutable** Play Store package id. Never change it.

## Version Scheme

- **`version/name`**: SemVer `MAJOR.MINOR.PATCH` (e.g. `0.1.0`, `0.1.1`, `0.2.0`). Cosmetic; shown to users.
- **`version/code`**: monotonically increasing positive 32-bit integer, **+1 per Play Store upload**. Once a `code` is uploaded to a track, you can never reuse it or anything lower. Bumping `name` without bumping `code` will be rejected.
- Both live in [`export_presets.cfg`](../../export_presets.cfg) and nowhere else.

To bump:

1. Edit `version/code` (+1) and `version/name` per the user's choice in [`export_presets.cfg`](../../export_presets.cfg).
2. (Optional sanity) `./tools/build_all.sh --skip-desktop --skip-android --skip-fonts` — confirms the preset still parses by exporting a debug APK with the new filename suffix.
3. Commit the bump with type `chore(release):` — see "Git Conventions" below. Bundle with the release tag, not as a standalone commit two days later.

## Release Process

The general shape, in order. Confirm at each step that's user-visible.

1. **Confirm intent.** Ask the user what version they're cutting (patch / minor / major) and which artefacts they need (APK for sideloading, AAB for Play Store, both).
2. **Working tree clean** on `main`. `git status` must be empty before bumping.
3. **Run all test suites — hard gate.** See "Test Gate" below for the
   full command list. Every suite must pass. The parity tests in
   particular guard against silent encoder drift; shipping a broken
   encoder produces an AI that plays garbage. **Stop and report if
   anything fails — never bypass with `--no-verify`-style shortcuts.**
4. **Bump version** in [`export_presets.cfg`](../../export_presets.cfg).
5. **Build the artefacts.** Always uses the user's keystore — confirm `.android-release-pass` exists.
   - APK: `./tools/build_all.sh --release` → `build/seishingakuen-release-v<X.Y.Z>.apk`
   - AAB: `./tools/build_all.sh --aab` → `build/seishingakuen-release-v<X.Y.Z>.aab`
   - Both: run them sequentially.
6. **Verify the signature** matches the user's release certificate (not the global Android debug cert — that would mean signing fell back to debug):
   ```bash
   ~/Android/Sdk/build-tools/35.0.0/apksigner verify --print-certs build/seishingakuen-release-v<X.Y.Z>.apk \
     | grep -E 'Signer #1 (certificate DN|certificate SHA-256)'
   ```
   The CN should be the user's, not `Android Debug`. The SHA-256 should match `keytool -list -keystore ~/.local/share/godot/keystores/seishingakuen-release.keystore -alias seishingakuen`.
7. **Smoke-install** (if a device is connected): `adb install -r build/seishingakuen-release-v<X.Y.Z>.apk`. Launch, play one move, confirm the AI replies — proves the bundled `libshogi_core.so` and `models/bonanza.onnx` are intact in the signed bundle.
8. **Release commit + tag** — see below.
9. **Push** only after the user explicitly confirms.
10. **Upload** to Play Console (AAB) and/or **GitHub Release** (APK + signature) per the user's choice.

### Git Conventions

- Release commit message: `chore(release): version <X.Y.Z>` (matches the convention already in the log, e.g. `chore(release): version 0.1.0`).
- See the `commit-and-push` skill for full workflow details. **No GPG signing** in this repo. Include the `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` trailer when Claude collaborated on the bump.

### Tag Convention

Zero tags exist today, so there is **no precedent**. Propose this and let the user confirm:

- Annotated tag, no `v` prefix: `git tag -a 0.1.0 -m "0.1.0"` on the release commit.
- Tag points at the same commit as the release commit, *not* a separate commit.

Once the user picks, stick with it for future releases.

## Test Gate

Before any release tag, all four real test suites must pass. Run them
exactly in this order — Rust first because parity failures invalidate
everything downstream:

```bash
# 1. Rust: unit + parity (encoder ↔ ShogiDojo) + perft
cargo test --manifest-path native/shogi_core/Cargo.toml --release

# 2. GDScript: rules via FFI (check, pin, 二歩, 打ち歩詰め, undo, ...)
~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless -s res://scripts/tests/rules_tests.gd --path .

# 3. GDScript: character roster + .tres validity
~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless -s res://scripts/tests/characters_tests.gd --path .

# 4. GDScript: save/resume + prefs + atomic model copy
~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless -s res://scripts/tests/persistence_tests.gd --path .
```

Each GDScript suite prints `All <name> tests passed.` on success and
exits 0; on failure it `push_error`s the failing case names and exits
1, so a wrapping `&&` chain is enough to gate the rest of the release.

If any suite fails:

- **Stop.** Do not bump version, do not build artefacts, do not tag.
- Report the failing case to the user verbatim — don't paraphrase.
- Diagnose and fix on a separate commit (or revert the change that
  introduced the failure). Re-run the gate from the top before
  resuming the release flow.

The two smoke files (`core_smoke.gd`, `ai_smoke.gd`) are not part of
the gate — they cover boot-up sanity that the four real suites already
encompass. Skip them unless investigating something specific.

## Build Commands Reference

```bash
# Debug APK — no signing setup needed
./tools/build_all.sh

# Skip what you don't need to rebuild
./tools/build_all.sh --skip-desktop --skip-android --skip-fonts

# Signed release APK (sideloading / GitHub Release)
./tools/build_all.sh --release

# Signed AAB (Play Store)
./tools/build_all.sh --aab

# Run cargo tests as part of the build
./tools/build_all.sh --test
```

Outputs land in `build/seishingakuen-{debug,release}[-vX.Y.Z].{apk,aab}`. The `-vX.Y.Z` suffix is auto-derived from `version/name` — empty `version/name` skips the suffix.

## Signature & Keystore Verification

Independent commands worth knowing:

```bash
# Inspect the keystore (alias, certificate DN, SHA-256)
keytool -list -v -keystore ~/.local/share/godot/keystores/seishingakuen-release.keystore -storepass "$(cat .android-release-pass)" -alias seishingakuen

# Verify a signed APK
~/Android/Sdk/build-tools/35.0.0/apksigner verify --print-certs build/seishingakuen-release-v<X.Y.Z>.apk

# Confirm the AAB is a valid bundle (it's a zip)
unzip -l build/seishingakuen-release-v<X.Y.Z>.aab | head
```

For Play App Signing, record the **upload key** SHA-256 (what `apksigner verify --print-certs` shows on a self-signed AAB) — Google Play stores this and rejects future uploads signed with anything else. The keystore at `~/.local/share/godot/keystores/seishingakuen-release.keystore` is therefore irreplaceable; back it up offline.

## Google Play Upload

1. Open Play Console → Internal testing (or Production) → Create new release.
2. Upload `build/seishingakuen-release-v<X.Y.Z>.aab`.
3. Add release notes (see "Changelogs" below).
4. Roll out per the user's policy. The first upload to a track defines the upload signing key; every subsequent upload to that app must be signed with the same key.

## GitHub Release

For users who want a sideloadable APK alongside the Play Store release:

```bash
gh release create <X.Y.Z> \
  --title "<X.Y.Z>" \
  --notes "$(cat <<'EOF'
<release notes body>
EOF
)" \
  build/seishingakuen-release-v<X.Y.Z>.apk
```

For release notes, prefer a hand-written summary over `--generate-notes` alone. A good structure:

```markdown
## Highlights

- (1–3 user-visible bullets)

## Changes

- (grouped by feat: / fix: / chore: from `git log`)

**Full Changelog**: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/compare/<previous-tag>...<X.Y.Z>
```

For the **first** release, omit the `compare` link and use `https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/commits/<X.Y.Z>` instead.

## Changelogs

The project has **no `CHANGELOG.md`** yet. When the user asks for one, ask whether they want:

- A `CHANGELOG.md` at the repo root (Keep-a-Changelog style — works well with this repo's Conventional Commits).
- Per-release Play Console "What's new" copy (max 500 chars per language).
- GitHub Release notes only.

To gather material since the previous tag:

```bash
git log --oneline <previous-tag>..HEAD     # since the previous tag
git log --oneline                          # for the very first release
```

The project's `<type>(<scope>):` prefixes map cleanly to changelog sections.

## Important Reminders

- **Confirm before any push, tag-push, Play Store upload, or GitHub Release publish.** All four are visible to others and hard to undo.
- **Never bypass signing.** A debug-signed APK shipped as "release" will be rejected by Play Store *and* lose the upload-key invariant. If `apksigner verify --print-certs` shows `CN=Android Debug`, stop.
- **`version/code` is sticky.** Once you upload `code=N`, you can never re-use `N` or anything lower for this `package/unique_name`. Bump it on every Play Store upload, even for re-uploads of "the same" build.
- **All four test suites must pass before tagging** — see "Test Gate". A red suite blocks the release; do not work around it. Encoder byte-parity is the most consequential failure (a broken encoder ships an AI that plays garbage), but the GDScript suites cover behaviour the user-facing app actually depends on (rules legality, character roster integrity, save/resume round-trip, atomic model copy) and a regression in any of them is a shipping bug.
- **Keystore loss = app death.** `~/.local/share/godot/keystores/seishingakuen-release.keystore` cannot be regenerated; backups are the user's responsibility.
- **Native `.so` size**: Confirm `lib/arm64-v8a/libshogi_core.so` and the bundled `models/bonanza.onnx` are present in the AAB before upload (`unzip -l build/seishingakuen-release-v<X.Y.Z>.aab | grep -E 'libshogi_core|bonanza'`). A missing `.so` produces a launch crash on real devices.

## Task: $ARGUMENTS
