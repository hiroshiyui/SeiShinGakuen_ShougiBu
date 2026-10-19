---
name: publish-to-itch-dot-io
description: Upload the signed release APK to the itch.io page (hiroshiyui/seishingakuen-shougibu) with butler. Use when the user asks to publish / push / upload a release to itch.io, or after a GitHub Release when they want itch.io updated too.
argument-hint: optional version (defaults to version/name in export_presets.cfg)
---

# Publish to itch.io

You are uploading a release of **清正学園将棋部** to its itch.io page,
<https://hiroshiyui.itch.io/seishingakuen-shougibu>. itch.io is a
**secondary** channel: GitHub Releases is the primary one (see
`release-engineering`), so itch.io only ever gets an APK that has
already been tagged and published there.

itch.io has no web/REST endpoint for uploading builds. The only
supported path is **butler**, itch.io's CLI, which pushes to a
*channel* of the game page.

## Fixed facts

| What | Value |
|---|---|
| butler target | `hiroshiyui/seishingakuen-shougibu:android` |
| Channel name | `android` — the name makes itch.io tag the upload with the Android platform automatically. Don't rename it; a new channel name creates a second, separate download on the page. |
| Artefact | `build/seishingakuen-release-v<X.Y.Z>.apk` only. Don't push the `.idsig` — it's only meaningful next to the APK on GitHub Releases. |
| `--userversion` | `<X.Y.Z>`, same as the git tag and `version/name` in `export_presets.cfg`. |

## Prerequisites

1. **butler installed.** Check with `butler -V`. If missing, install it
   into `~/.local/bin` (already on PATH here):
   ```bash
   d=$(mktemp -d) && \
   curl -fL -o "$d/butler.zip" https://broth.itch.zone/butler/linux-amd64/LATEST/archive/default && \
   unzip -o "$d/butler.zip" -d "$d/butler" && \
   install -m 755 "$d/butler/butler" ~/.local/bin/butler && \
   install -m 644 "$d"/butler/*.so ~/.local/bin/ 2>/dev/null; butler -V
   ```
   (Downloaded archive is untrusted data — unpack it in its own temp
   dir, as above, not in the repo.)
2. **API key in SOPS.** The itch.io API key lives SOPS-encrypted in
   `secrets/itch.sops.yml` (GPG, rule in `.sops.yaml`; shape in
   `secrets/itch.sops.yml.example`). Check it exists. If not, the user
   creates it **in their own terminal** — `sops edit` opens `$EDITOR`,
   which doesn't work through Claude Code, and the plaintext key must
   never pass through this conversation:
   ```bash
   sops edit secrets/itch.sops.yml   # add: butler_api_key: <key>
   ```
   Don't use `butler login`; the SOPS file is the single source.

   Feed the key to butler only via the environment of the one command,
   so it's never printed, written to disk, or echoed:
   ```bash
   BUTLER_API_KEY="$(sops decrypt --extract '["butler_api_key"]' secrets/itch.sops.yml)" \
     butler <subcommand> ...
   ```
   Never `cat`/`echo` the decrypted value, never `sops decrypt` the whole
   file to stdout, and never write the key into the repo, a skill, a
   script, or a commit. If decryption fails (gpg-agent can't prompt for
   the passphrase), ask the user to unlock the key, e.g. by running
   `! sops decrypt --extract '["butler_api_key"]' secrets/itch.sops.yml >/dev/null`.

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
   compare `sha256sum`. A mismatch means the local build was redone
   after publishing — push the GitHub copy instead, never a different
   binary under the same version.
4. **Dry run**, then show the user what will happen:
   ```bash
   BUTLER_API_KEY="$(sops decrypt --extract '["butler_api_key"]' secrets/itch.sops.yml)" \
     butler push --dry-run build/seishingakuen-release-v<X.Y.Z>.apk \
     hiroshiyui/seishingakuen-shougibu:android --userversion <X.Y.Z>
   BUTLER_API_KEY="$(sops decrypt --extract '["butler_api_key"]' secrets/itch.sops.yml)" \
     butler status hiroshiyui/seishingakuen-shougibu:android
   ```
5. **Confirm with the user before the real push** — it's public as soon
   as processing finishes.
6. **Push:**
   ```bash
   BUTLER_API_KEY="$(sops decrypt --extract '["butler_api_key"]' secrets/itch.sops.yml)" \
     butler push build/seishingakuen-release-v<X.Y.Z>.apk \
     hiroshiyui/seishingakuen-shougibu:android --userversion <X.Y.Z>
   ```
7. **Verify:** `butler status hiroshiyui/seishingakuen-shougibu:android` (same `BUTLER_API_KEY` prefix)
   until the build shows as processed with version `<X.Y.Z>`.
8. **Hand off the manual steps** (no API exists for these):
   - Optional Devlog post on itch.io announcing `<X.Y.Z>` — followers
     get notified. The Japanese highlights in
     `docs/release-notes/<X.Y.Z>.md` are a ready source.
   - If the feature list changed, update the page text from
     `docs/distribution.md` in Edit game.

## First push only

Earlier releases were uploaded by hand in the web UI, so the first
`butler push` adds a *second* file next to the old manual upload.
Tell the user to delete the old manual upload in Edit game → Uploads
after the push is processed (and check the butler upload is marked
Android). After that, every push just replaces the `android` channel.

## Don'ts

- Don't push to itch.io before the GitHub Release exists.
- Don't push a debug-signed APK — sideloaders who got the release cert
  from GitHub couldn't update over it.
- Don't reuse `--userversion` for a different binary.
- Don't add other channels (`windows`, `linux`, …) — the game is
  Android-only.
