# Android build

How to build the Android APK for 清正学園将棋部.

## Prerequisites (one-time)

1. **Android SDK + NDK** — this repo assumes:
   - SDK: `~/Android/Sdk`
   - NDK: `~/Android/Sdk/ndk/28.1.13356709`

2. **Rust target** — `aarch64-linux-android` (already pinned in
   `native/shogi_core/rust-toolchain.toml`, installed on first `cargo ndk`).

3. **cargo-ndk** —
   ```bash
   cargo install cargo-ndk
   ```

4. **Godot export templates** for the exact engine version (4.6.2-stable):
   - Open Godot editor
   - Project → Export → *Manage Export Templates*
   - Click **Download and Install** — fetches a ~800 MB `.tpz` to
     `~/.local/share/godot/export_templates/4.6.2.stable/`

5. **Godot editor settings** (user-local, not in repo):
   - Editor → Editor Settings → *Export → Android*
     - **Android SDK path:** `/home/yhh/Android/Sdk`
     - **Debug keystore:** leave blank (Godot auto-generates
       `~/.android/debug.keystore` on first export if missing), or point
       at an existing keystore.

6. **Android export preset** (committed once, then stable):
   - Project → Export → Add… → Android
   - Name: `Android arm64`
   - Architectures: **only** `arm64-v8a` (untick the others)
   - Resources → Filters to export non-resource files/folders:
     `*.onnx` (required — Godot's default `all_resources` filter skips
     `.onnx`, which means the model silently doesn't land in the APK)
   - Options → Screen → Orientation: **Portrait**
   - Options → Package → Unique name: `org.seishingakuen.shougibu`
   - Export path: `build/seishingakuen-debug.apk`
   - Save. Godot writes `export_presets.cfg` — commit that file.

## Build the native library (arm64-v8a)

```bash
cd native/shogi_core
ANDROID_NDK_HOME=~/Android/Sdk/ndk/28.1.13356709 \
  cargo ndk --platform 24 -t arm64-v8a \
  --output-dir ../../native/bin/android \
  build --release
```

Output lands at `native/bin/android/arm64-v8a/libshogi_core.so`
(~14 MB). The `.gdextension` manifest already points at it.

## Build the APK

```bash
~/.local/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless --path . \
  --export-debug "Android arm64" build/seishingakuen-debug.apk
```

(Use `--export-release` for a signed release APK — requires a release
keystore configured in editor settings.)

## Install on device

```bash
~/Android/Sdk/platform-tools/adb install -r build/seishingakuen-debug.apk
```

## Notes

- The ONNX model (`models/bonanza.onnx`) is packed into the APK and
  extracted to `user://` on first launch by `Settings.model_absolute_path()`.
  tract mmaps it from the OS filesystem; reading inside the PCK is not
  supported by third-party native code.
- Fonts under `assets/fonts/**` are vendored twice — `<name>-full.otf`
  (upstream source, excluded from the APK by `export_presets.cfg`'s
  `exclude_filter`) and `<name>.otf` (subset, shipped). Re-run
  `./tools/build_font_subsets.py` after editing UI strings so newly
  introduced Japanese glyphs make it into the subsets. See
  [ADR-0005](./adr/0005-font-subset-pipeline.md).
- `/build/` and any `*.keystore` are gitignored — don't commit APKs or
  signing material.
