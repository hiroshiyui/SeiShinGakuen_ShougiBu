# ADR-0009: KIF library writes to app-private external Documents, not shared storage

## Status

Accepted.

## Context

Phase 7's KIF export feature needed an on-disk location for saved
games that the user could reach from outside the app — to open in a
KIF viewer, attach to email, push to a cloud drive, etc. The obvious
target is `/storage/emulated/0/Documents/` (the public "Documents"
folder every Android file manager surfaces by default).

Modern Android (10+, API 29+) restricts writes to that path under
**scoped storage**:

- `WRITE_EXTERNAL_STORAGE` is silently ignored on API 29+ for paths
  outside the app's own external storage.
- The supported paths are MediaStore (via `ContentResolver`) or the
  Storage Access Framework (`Intent.ACTION_OPEN_DOCUMENT_TREE`).
  Neither is exposed by Godot 4 without writing a custom Android
  plugin.
- The escape hatch is `MANAGE_EXTERNAL_STORAGE`, which prompts the
  user with the scary "全てのファイルへのアクセスを許可" system dialog and
  is rejected by Google Play policy for non-file-manager apps.

Three viable paths for a single-player offline shogi app:

1. **Add an Android plugin for SAF / MediaStore.** Heavyweight: new
   Java module in `android/`, new build dependency, more `.so` /
   `.aar` plumbing through `tools/build_all.sh`. Justifiable for a
   media-centric app; overkill for a 1 KB text file we save once a
   game.
2. **Request `MANAGE_EXTERNAL_STORAGE` and write to
   `/sdcard/Documents/`.** Universal file-manager visibility, but the
   permission dialog is alarming for a shogi game and Google Play
   would reject it (we're sideload-only, but the optics still matter).
3. **Write to app-private external Documents
   (`OS.SYSTEM_DIR_DOCUMENTS, shared_storage=false`).** Resolves to
   `/storage/emulated/0/Android/data/<package>/files/Documents/` on
   Android 11+ — writable without any permission, *visible to file
   managers* that browse `Android/data/...` (Material Files, FX File
   Explorer, MiXplorer; Google's stock Files app has limited
   visibility there). On Linux desktop the same call returns
   `~/Documents`, which is fully shared and convenient.

## Decision

Option 3.
[`GameController._save_kif`](../../scripts/game/GameController.gd)
tries `OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS, false)` first and
falls back to `user://` if that path can't be created or written. The
absolute saved path is shown back to the user in the dialog so they
can find the file. KifuLibrary scans both candidate roots (deduped
via the absolute paths) so a save that ended up in either spot still
appears in the library.

The 共有 / share-intent flow that Phase 7's roadmap entry mentioned
is **explicitly out of scope** — same rationale as Option 1. KIF text
on the clipboard was tried first but Godot's `DisplayServer.clipboard_set`
is finicky on Android (works for some target apps, silently no-ops in
others), so we landed on file-on-disk + file-manager-mediated share
sheet as the actual UX.

## Consequences

**Makes easy:**

- Zero permission prompts. The 保存 button works on first launch with
  no system dialog.
- One code path covers desktop and Android. The desktop fallback to
  `~/Documents` keeps round-trip testing of `to_kif` ↔ `parse_kif` on
  the developer machine straightforward.
- Uninstalling the app cleans up its KIF library too — `Android/data/<pkg>/`
  is wiped on uninstall by the system. No orphaned files in the user's
  shared Documents folder.

**Makes harder / accepts:**

- Google's stock Files app on Android won't browse
  `Android/data/<pkg>/files/`. Power-user file managers see it
  immediately; casual users may not realise the file is there. Mitigated
  by showing the absolute path in the save dialog so they can paste it
  into a file manager directly.
- KIF files don't survive uninstall. Acceptable trade-off — same caveat
  as `user://prefs.cfg` and `user://saved_game.cfg` (see ROADMAP
  Open Questions: cloud save / cross-device persistence is out of scope).
- If we later want true OS share-sheet integration, we'll need an
  Android plugin (Option 1). The current architecture doesn't preclude
  it; the share button can call a new platform method without changing
  the save path.

## See also

- [`scripts/game/GameController.gd`](../../scripts/game/GameController.gd)
  — `_save_kif()` for the path-resolution logic.
- [`scripts/KifuLibrary.gd`](../../scripts/KifuLibrary.gd) —
  `_scan_kif_files()` mirrors the same candidate roots.
- [ADR-0004](./0004-model-and-fonts-via-user-copy.md) — earlier
  trade-off where we extract resources out of the APK into `user://`,
  same family of "Android storage gymnastics" decisions.
