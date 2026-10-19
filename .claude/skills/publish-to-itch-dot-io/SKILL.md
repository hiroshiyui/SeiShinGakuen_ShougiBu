---
name: publish-to-itch-dot-io
description: Walk the user through uploading the signed release APK to the itch.io page (hiroshiyui/seishingakuen-shougibu) by hand in the web UI. Use when the user asks to publish / upload a release to itch.io, or after a GitHub Release when they want itch.io updated too.
argument-hint: optional version (defaults to version/name in export_presets.cfg)
---

# Publish to itch.io

You are helping publish a release of **清正学園将棋部** on its itch.io
page, <https://hiroshiyui.itch.io/seishingakuen-shougibu>. itch.io is a
**secondary** channel: GitHub Releases is the primary one (see
`release-engineering`), so itch.io only ever gets an APK that has
already been tagged and published there.

**The upload itself is done by the user in the web UI.** You prepare
and verify the file, then hand them the checklist.

## Why not butler

itch.io has no REST endpoint for uploads; its CLI, butler, is the only
automated path. It was tried for 1.0.7 (2026-10-19): the push itself
took seconds, but the first build on the new `android` channel sat in
itch.io's server-side processing for 20+ minutes without ever showing
up (`butler status` kept reporting "No channel found"; a re-push was
refused with "latest build is still processing"). A manual upload took
seconds. butler, the SOPS-encrypted API key and `.sops.yaml` were
removed afterwards. Don't reintroduce butler unless the user asks.

## Workflow

1. **Resolve the version.** Use the argument if given, otherwise
   `version/name` from `export_presets.cfg`.
2. **Gate on the GitHub Release.** All of these must hold, otherwise
   stop and point the user at `release-engineering`:
   - tag `<X.Y.Z>` exists and is pushed (`git ls-remote --tags origin <X.Y.Z>`);
   - `gh release view <X.Y.Z>` succeeds;
   - `build/seishingakuen-release-v<X.Y.Z>.apk` exists locally.
3. **Verify it's the release-signed APK**, not a debug build:
   ```bash
   ~/Android/Sdk/build-tools/36.0.0/apksigner verify --print-certs build/seishingakuen-release-v<X.Y.Z>.apk \
     | grep -E 'Signer #1 certificate (DN|SHA-256)'
   ```
   Expected: `CN=Hiroshi Y.` and SHA-256
   `a00c27ca1d929a25f129d4c6bb6b6c36212e9f2c049628325caca4e3ec5fed8d`.
   If it says `Android Debug` or the digest differs, **stop**.
   Also confirm it matches what's on GitHub: download the release asset
   with `gh release download <X.Y.Z> -p '*.apk' -D <scratch dir>` and
   compare `sha256sum`. On a mismatch, tell the user to upload the
   GitHub copy instead — never a different binary under the same
   version.
4. **Hand the user this checklist** (itch.io → Edit game → Uploads),
   with the absolute path to the APK filled in:
   1. **Upload files** → `~/MyProjects/SeiShinGakuen_ShougiBu/build/seishingakuen-release-v<X.Y.Z>.apk`.
      Upload the APK only, not the `.idsig`.
   2. Keep the type **Executable** and tick **Android**.
   3. On the previous version's file, tick **Hide this file and prevent
      it from being downloaded** (older files stay hidden, not deleted,
      so their download counts survive).
   4. **Save**.
   5. Optional: post a Devlog announcing `<X.Y.Z>` — followers get
      notified. The Japanese highlights in
      `docs/release-notes/<X.Y.Z>.md` are a ready source.
   6. If the feature list changed, update the page text from
      `docs/distribution.md`.
5. If the user shares a screenshot of the Uploads section afterwards,
   check: exactly one visible APK, it's `<X.Y.Z>`, Android ticked.

## Don'ts

- Don't publish to itch.io before the GitHub Release exists.
- Don't hand over a debug-signed APK — sideloaders who got the release
  cert from GitHub couldn't update over it.
- Don't add uploads for other platforms — the game is Android-only.
