---
name: snap-screenshot
description: Capture a screenshot from the connected Android device via adb and save it under docs/screenshots/. Trigger on "snap", "take a screenshot", "screenshot via adb", or any request to capture the device's screen — typical use is grabbing app screens for the README, Play Store listing, or bug reports.
argument-hint: optional output filename (defaults to docs/screenshots/<timestamp>.png)
---

# snap-screenshot

Capture the current screen of the connected Android device via `adb` and save the PNG under `docs/screenshots/`. Designed for the rapid loop where the user manipulates the device and says "snap" each time they have a frame they want — keep responses short.

## When to use

- User says "snap", "snap a screenshot", "screenshot", "take a screenshot via adb".
- User is preparing Play Store screenshots, README imagery, or bug-report attachments and wants captures from the device they're holding.
- **Skip** if the user wants desktop screenshots (Spectacle / grim / scrot territory) — this skill is adb-only.

## Steps

1. **Ensure the daemon is running and a device is attached.**
   ```bash
   adb start-server
   adb devices
   ```
   If `adb devices` lists no device (or only `unauthorized` / `offline`), stop and tell the user — don't try to capture from nothing. If multiple devices are listed, ask which `-s <serial>` to target rather than guessing.

2. **Capture with a timestamped filename** (so back-to-back snaps don't overwrite each other):
   ```bash
   OUT=docs/screenshots/$(date +%Y%m%d-%H%M%S).png
   adb exec-out screencap -p > "$OUT"
   ```
   `exec-out` (not `shell`) avoids CRLF mangling on the binary PNG stream — using `adb shell screencap` will produce a corrupt file on most setups.

3. **Confirm the file landed** — single line is enough, the user is iterating fast:
   ```bash
   ls -la "$OUT"
   ```

4. **Reply tersely.** "Snapped — `docs/screenshots/<filename>.png`." A one-liner. The user is going to say "snap" again in five seconds and doesn't want a paragraph each time.

## Conventions

- **Output path**: `docs/screenshots/<YYYYMMDD-HHMMSS>.png` by default. The directory is auto-created if missing (`mkdir -p docs/screenshots` on the first call).
- **Filename override**: if `$ARGUMENTS` looks like a path/name, use it instead. Pass an extension or default to `.png`. E.g. user says "snap title-screen" → `docs/screenshots/title-screen.png`. If the file already exists, append a timestamp suffix rather than overwriting.
- **No `--quiet` / no truncation**: the PNG is a few MB; that's fine. Don't pipe through `pngcrush` or convert to WebP automatically — the user wants the raw capture.

## Edge cases

- **`cannot connect to daemon`**: `adb start-server` first, then retry. If still failing, the device cable / USB authorization is the issue — tell the user, don't loop.
- **Permissions on `/sdcard/...`**: not used; we capture via `exec-out` which keeps the PNG in stdout, never touching device storage. No `pull` needed.
- **Locked screen / black screenshot**: capture still succeeds, but the PNG is mostly black. Mention it once if you see a likely-locked image and let the user unlock; don't lecture.
- **Wayland / X11 / desktop screenshots**: out of scope. Tell the user this skill is adb-only and suggest `spectacle` (KDE) or `grim` (Wayland generic) if they want desktop captures.

## Task: $ARGUMENTS
