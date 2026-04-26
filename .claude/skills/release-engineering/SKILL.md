---
name: release-engineering
description: Release engineering tasks including version bumping, building signed release APKs, creating git tags, and preparing GitHub Release artefacts. Use when the user asks to prepare a release, bump the version, tag a release, or build for distribution.
argument-hint: task description
---

# Release Engineering

You are performing release engineering tasks for **清正学園将棋部** (SeiShinGakuen_ShougiBu) — a single-player Android Shogi game built with Godot 4.6.2 (Mobile renderer) and a Rust GDExtension. Distribution target is **GitHub Releases** (signed APK, sideload). **Google Play is explicitly out of scope** — see ROADMAP Open Questions for the rationale (avoiding Play developer-account dependencies, mandatory privacy-policy URLs, upload-key custody, and the policy-compliance ratchet for a single-player offline game). Don't suggest Play Store steps unless the user reopens that decision.

## Current state of the project

Read this before assuming anything. The repo's release infrastructure is real and tested — confirm anything that looks ambiguous against the actual files rather than this skill.

- **Build pipeline.** [`tools/build_all.sh`](../../tools/build_all.sh) drives the whole pipeline (Rust desktop + Android cross-compile, font subsets, Godot export). Flags: `--release` for a signed APK, `--skip-{desktop,android,fonts,apk}`, `--test` for `cargo test`. (`--aab` exists for completeness but produces a Play-Store-only artefact we don't ship — leave it alone unless the user reopens the Play Store decision.)
- **Versioning.** `version/code` and `version/name` live in [`export_presets.cfg`](../../export_presets.cfg) under `[preset.0.options]`. They are the single source of truth — the script reads `version/name` to tag output filenames (`build/seishingakuen-release-v0.1.0.apk`).
- **Signing — release.** Keystore lives outside the repo at `~/.local/share/godot/keystores/seishingakuen-release.keystore`, alias `seishingakuen`. The password sits in `.android-release-pass` at the repo root (gitignored). The script reads it and exports `GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD}` for the duration of one export — **no signing secrets in `export_presets.cfg`**, **no patches to Godot's global `editor_settings-4.6.tres`**.
- **Signing — debug.** Standard Android debug keystore, configured globally in `editor_settings-4.6.tres`. No password file required.
- **Tags.** Annotated, no `v` prefix (e.g. `0.2.0`); each release tag points at the same commit as its `chore(release):` commit. Established convention — keep it.
- **Distribution.** GitHub Releases (signed APK + `.idsig`) for sideloading. No Play Store, no F-Droid (no `fastlane/`). Don't mention either unless the user reopens the decision.
- **Tests.** Rust core has unit + parity + perft tests in `native/shogi_core/src/{tests.rs,parity_tests.rs}`. GDScript headless test suites live under `scripts/tests/`: `rules_tests.gd` (FFI rules), `characters_tests.gd` (character roster + `.tres` validity), `persistence_tests.gd` (save/resume + atomic model copy), plus the older `core_smoke.gd` and `ai_smoke.gd`. **Every release must pass all four real test suites** — see "Test Gate" below.

Current version (verify in [`export_presets.cfg`](../../export_presets.cfg) before acting — these go stale):

```
version/code=4
version/name="0.2.0"
```

`package/unique_name="org.seishingakuen.shougibu"` — Android package id. Effectively immutable: changing it makes Android treat any new install as an unrelated app, breaks "update existing install" for sideloading users, and orphans every saved game in `user://`. Don't change it.

## Version Scheme

- **`version/name`**: SemVer `MAJOR.MINOR.PATCH` (e.g. `0.1.0`, `0.1.1`, `0.2.0`). Cosmetic; shown to users.
- **`version/code`**: monotonically increasing positive 32-bit integer, **+1 per release**. Android refuses to install a build whose `versionCode` is ≤ the currently-installed one (treats it as a downgrade), so an APK published to GitHub Releases without bumping `code` won't update existing sideloaders.
- Both live in [`export_presets.cfg`](../../export_presets.cfg) and nowhere else.

To bump:

1. Edit `version/code` (+1) and `version/name` per the user's choice in [`export_presets.cfg`](../../export_presets.cfg).
2. (Optional sanity) `./tools/build_all.sh --skip-desktop --skip-android --skip-fonts` — confirms the preset still parses by exporting a debug APK with the new filename suffix.
3. Commit the bump with type `chore(release):` — see "Git Conventions" below. Bundle with the release tag, not as a standalone commit two days later.

## Release Process

The general shape, in order. Confirm at each step that's user-visible.

1. **Confirm intent.** Ask the user what version they're cutting (patch / minor / major). The artefact is always a signed APK (no AAB unless they explicitly reopen the Play Store decision).
2. **Working tree clean** on `main`. `git status` must be empty before bumping.
3. **Run all test suites — hard gate.** See "Test Gate" below for the
   full command list. Every suite must pass. The parity tests in
   particular guard against silent encoder drift; shipping a broken
   encoder produces an AI that plays garbage. **Stop and report if
   anything fails — never bypass with `--no-verify`-style shortcuts.**
4. **Bump version** in [`export_presets.cfg`](../../export_presets.cfg).
5. **Build the APK.** `./tools/build_all.sh --release` → `build/seishingakuen-release-v<X.Y.Z>.apk` (+ `.idsig` sidecar). Confirm `.android-release-pass` exists before invoking — the script reads it for the keystore password.
6. **Verify the signature** matches the user's release certificate (not the global Android debug cert — that would mean signing fell back to debug):
   ```bash
   ~/Android/Sdk/build-tools/35.0.0/apksigner verify --print-certs build/seishingakuen-release-v<X.Y.Z>.apk \
     | grep -E 'Signer #1 (certificate DN|certificate SHA-256)'
   ```
   The CN should be the user's, not `Android Debug`. The SHA-256 should match `keytool -list -keystore ~/.local/share/godot/keystores/seishingakuen-release.keystore -alias seishingakuen`.
7. **Smoke-install** (if a device is connected): `adb install -r build/seishingakuen-release-v<X.Y.Z>.apk`. Launch, play one move, confirm the AI replies — proves the bundled `libshogi_core.so` and `models/bonanza.onnx` are intact in the signed bundle. If the device has a debug-signed copy installed, the install will fail with a signature mismatch — uninstall first (`adb uninstall org.seishingakuen.shougibu`), warning the user this wipes saved game + prefs.
8. **Release commit + tag** — see below.
9. **Push** only after the user explicitly confirms (`git push origin main && git push origin <X.Y.Z>`).
10. **Publish a GitHub Release** with the APK + `.idsig` attached — see "GitHub Release" below.

### Git Conventions

- Release commit message: `chore(release): version <X.Y.Z>` (matches the convention already in the log, e.g. `chore(release): version 0.1.0`).
- See the `commit-and-push` skill for full workflow details. **No GPG signing** in this repo. Include the `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` trailer when Claude collaborated on the bump.

### Tag Convention

Established by 0.1.1 / 0.1.2 / 0.2.0:

- Annotated tag, no `v` prefix: `git tag -a 0.X.Y -m "0.X.Y"` on the release commit.
- Tag points at the same commit as the `chore(release):` commit, *not* a separate commit.
- Push with `git push origin <X.Y.Z>` after pushing `main`.

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

# Signed release APK (the only artefact we ship)
./tools/build_all.sh --release

# Run cargo tests as part of the build
./tools/build_all.sh --test
```

Outputs land in `build/seishingakuen-{debug,release}[-vX.Y.Z].apk`. The `-vX.Y.Z` suffix is auto-derived from `version/name` — empty `version/name` skips the suffix.

The `--aab` flag exists in `build_all.sh` but produces a Play-Store-only bundle we don't distribute; ignore it unless the user reopens that decision.

## Signature & Keystore Verification

Independent commands worth knowing:

```bash
# Inspect the keystore (alias, certificate DN, SHA-256)
keytool -list -v -keystore ~/.local/share/godot/keystores/seishingakuen-release.keystore -storepass "$(cat .android-release-pass)" -alias seishingakuen

# Verify a signed APK
~/Android/Sdk/build-tools/35.0.0/apksigner verify --print-certs build/seishingakuen-release-v<X.Y.Z>.apk

# Confirm the APK contains the native lib + ONNX model
unzip -l build/seishingakuen-release-v<X.Y.Z>.apk | grep -E 'libshogi_core|bonanza'
```

The keystore at `~/.local/share/godot/keystores/seishingakuen-release.keystore` is irreplaceable: every release of this `package/unique_name` must be signed with the same cert, otherwise existing sideloaders can't update without uninstalling first (which wipes their saved game). Back it up offline.

## GitHub Release

The shipping channel. Always upload both the APK and its `.idsig`
sidecar so users can verify the signature independently:

```bash
gh release create <X.Y.Z> \
  --title "<X.Y.Z>" \
  --notes "$(cat <<'EOF'
<release notes body>
EOF
)" \
  build/seishingakuen-release-v<X.Y.Z>.apk \
  build/seishingakuen-release-v<X.Y.Z>.apk.idsig
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
- GitHub Release notes only (the current practice — see "GitHub Release" above).

To gather material since the previous tag:

```bash
git log --oneline <previous-tag>..HEAD     # since the previous tag
git log --oneline                          # for the very first release
```

The project's `<type>(<scope>):` prefixes map cleanly to changelog sections.

## Important Reminders

- **Confirm before any push, tag-push, or GitHub Release publish.** All three are visible to others and hard to undo.
- **Never bypass signing.** A debug-signed APK shipped as "release" breaks the "update existing install" path for everyone who installed an earlier release (different cert → Android refuses the upgrade, user must uninstall + lose saved game). If `apksigner verify --print-certs` shows `CN=Android Debug`, stop.
- **`version/code` only goes up.** Android refuses installs whose `versionCode` is ≤ the currently installed one. Bump on every release, never reuse, never decrement.
- **Distribution is GitHub Releases sideload only.** Don't propose Play Store / Play Console / AAB upload steps unless the user explicitly reopens that decision (see ROADMAP). The `--aab` flag in `build_all.sh` is preserved but unused.
- **All four test suites must pass before tagging** — see "Test Gate". A red suite blocks the release; do not work around it. Encoder byte-parity is the most consequential failure (a broken encoder ships an AI that plays garbage), but the GDScript suites cover behaviour the user-facing app actually depends on (rules legality, character roster integrity, save/resume round-trip, atomic model copy) and a regression in any of them is a shipping bug.
- **Keystore loss = sideload-update death.** `~/.local/share/godot/keystores/seishingakuen-release.keystore` cannot be regenerated; backups are the user's responsibility. Without it, every existing sideloader has to uninstall + lose data to install any future build.
- **Native `.so` + model present**: Confirm `lib/arm64-v8a/libshogi_core.so` and the bundled `models/bonanza.onnx` are inside the APK before publishing (`unzip -l build/seishingakuen-release-v<X.Y.Z>.apk | grep -E 'libshogi_core|bonanza'`). A missing `.so` produces a launch crash on real devices.

## Task: $ARGUMENTS
