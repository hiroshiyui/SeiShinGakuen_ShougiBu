---
name: cleanup-build-artifacts
description: Free disk space by deleting regenerable build artefacts of 清正学園将棋部 — the cargo target directory, old versioned APK / AppImage outputs in build/, export staging folders. Use when the user asks to clean up build artefacts, free or reclaim disk space, says the disk is full, or asks why the repository folder is so large.
argument-hint: optional "deep" (also drop release/Android cargo caches) or "report" (list sizes only)
---

# cleanup-build-artifacts

Delete build output that the build scripts can regenerate. All of it is
gitignored, so nothing here ever shows up in `git status`. The work is
done by `scripts/cleanup.sh` next to this file; use it rather than
hand-written `rm` commands, because it knows what must be kept.

## Steps

1. **Report first** (deletes nothing):
   ```bash
   .claude/skills/cleanup-build-artifacts/scripts/cleanup.sh
   ```
2. **Delete the safe tier.** Invoking this skill is the go-ahead; no need
   to ask again:
   ```bash
   .claude/skills/cleanup-build-artifacts/scripts/cleanup.sh --apply
   ```
3. **Deep tier only when asked** — `$ARGUMENTS` contains "deep" / "all" /
   "everything", or the user asks for more space after seeing the result:
   ```bash
   .claude/skills/cleanup-build-artifacts/scripts/cleanup.sh --apply --deep
   ```
4. **Reply in a few lines**: how much was freed, what the deep tier would
   still free (if it was not run), and the rebuild cost below.

If `$ARGUMENTS` is "report" / "dry run", stop after step 1.

## What goes in each tier

| Tier | Path | Cost of deleting |
|------|------|------------------|
| safe | `native/shogi_core/target/debug` | next `cargo test` recompiles (a few minutes) |
| safe | `build/seishingakuen-*` of versions other than the current one | none — released files are on GitHub Releases |
| safe | `build/linux/`, `build/appimage/` | rebuilt by `build_all.sh --linux` |
| safe | `tools/__pycache__/` | none |
| deep | `native/shogi_core/target/release`, `.../aarch64-linux-android` | next `build_all.sh` does a full Rust rebuild for desktop and Android |
| deep | `tools/.cache/` | AppImage tooling is downloaded again (needs network) |
| deep | podman volume `seishingakuen-linux-target` | next AppImage build recompiles in the container |

The current version is read from `config/version` in `project.godot`;
its APK / AppImage files are kept in both tiers.

## Never delete

- `native/bin/` — the editor, the tests and every export load
  `libshogi_core.so` from here. Without it the project does not open.
- `android/build/` — the Godot Gradle build template, installed once by
  hand from the editor; `build_all.sh` cannot recreate it.
- `.godot/` — import cache. Regenerable, but every asset is re-imported
  and the editor must be opened once before a headless export works.
- `*.keystore`, `*.jks`, `.android-release-pass` — signing material,
  not artefacts. Losing the release keystore means no more updates for
  installed copies.
- Podman volume `seishingakuen-cargo-registry` and the builder image —
  small relative to the rest and need network to restore.

If the user explicitly asks to remove one of these, confirm first and
say what restoring it takes.

## Edge cases

- **Godot editor is open**: fine — the script does not touch `.godot/`
  or `native/bin/`.
- **A build is running** (`pgrep -f 'cargo|build_all.sh'`): wait or ask;
  deleting `target/` under a running cargo breaks that build.
- **A version was bumped but not yet built**: the old version's files
  are then the only local copies. They are still on GitHub Releases if
  tagged; mention it in the reply if the report shows no file for the
  current version.

## Task: $ARGUMENTS
