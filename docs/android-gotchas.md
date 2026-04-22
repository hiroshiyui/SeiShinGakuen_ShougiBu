# Android-specific gotchas

Things that cost real time during Phase 6. Written as *symptom → cause →
fix* so a future reader can grep for the symptom.

## Orientation ignored — app stays landscape

**Symptom:** `project.godot` says `window/handheld/orientation="portrait"`
but the APK launches in landscape. `aapt2 dump xmltree` shows
`android:screenOrientation=0` (= `LANDSCAPE`).

**Cause:** Godot 4.6's Android export reads the orientation setting as an
`int` (via `GLOBAL_GET`). A string value silently fails the cast and
returns the default, which is `0` = landscape.

**Fix:** use the integer form:
```
[display]
window/handheld/orientation=1
```
Mapping: `0` = landscape, `1` = portrait, `2` = reverse_landscape,
`3` = reverse_portrait, `4` = sensor, `5` = sensor_landscape,
`6` = sensor_portrait. *Do not* use `"portrait"` even though the editor
UI accepts it.

## Non-resource files (`.onnx`, binary blobs) missing from APK

**Symptom:** file is in the repo at `res://models/foo.onnx`, works in the
editor, but doesn't exist at runtime on-device. `unzip -l app.apk`
doesn't list it.

**Cause:** the default export filter `all_resources` only exports files
Godot recognises as resources. Unknown extensions are silently dropped.

**Fix:** export preset → *Resources → Filters to export non-resource
files/folders* → add `*.onnx` (or the relevant glob). In
`export_presets.cfg`:
```
export_filter="all_resources"
include_filter="*.onnx"
```

## Third-party native code can't read `res://`

**Symptom:** inference / asset library returns "file not found" pointing
at something that exists inside the APK.

**Cause:** `res://` is a Godot-virtual filesystem. In exported builds it
lives inside the PCK (or the APK's `assets/`), which third-party native
code (tract, ort, libpng, a custom C++ loader, …) can't mmap or open.

**Fix:** in Godot, copy the asset to `user://` on first launch and hand
the native code `ProjectSettings.globalize_path("user://foo.bin")`. That
path is on the OS filesystem and any library can open it. See
`Settings.gd::model_absolute_path()` for the pattern. No-op in the editor
since `res://` is already a real OS path there.

## Every tap fires twice / immediate deselect after select

**Symptom:** tapping a piece selects it and *instantly* deselects it, so
it looks like taps don't work at all. `print` in the `_gui_input`
handler shows the same `(file, rank)` pair twice per tap.

**Cause:** Godot's default `input_devices/pointing/emulate_mouse_from_touch
= true`. A real touch fires **both** an `InputEventScreenTouch` **and**
an emulated `InputEventMouseButton`; a handler that matches both emits
the event twice. The second emission lands with the piece already
selected and triggers the "tap on selected piece = cancel" path.

**Fix:** dispatch on platform instead of accepting both event types.
```gdscript
if OS.has_feature("mobile"):
    if event is InputEventScreenTouch and event.pressed: …
else:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: …
```

## Layout drifts / board shifts between moves

**Symptom:** board is centred at launch but nudges left/right each time a
move is made, sometimes a few pixels, sometimes dozens.

**Cause:** a descendant `Label` with `size_flags_horizontal = 3` and
content-derived min-width (e.g. a status label showing the SFEN, whose
text length changes every ply). The label reports a wider minimum, the
`VBoxContainer` row grows, the parent `Control` grows, `CenterContainer`
re-centres against the new parent width → board visibly moves.

**Fix (pick one, or combine):**
- Put the label in an `HBoxContainer` with `clip_text = true` +
  `text_overrun_behavior = TRIM_ELLIPSIS`.
- Keep label content **fixed-width** (show only things whose text
  length is stable).
- Bound the label with an explicit `custom_minimum_size` / max via a
  wrapping container.

Diagnose with a one-liner on the board node:
```gdscript
item_rect_changed.connect(func():
    print("[board] %s@%s parent=%s" % [size, position, get_parent().size]))
```

## APK is much bigger than you expected

**Current contributors** (58 MB total):
- `libgodot_android.so` — ~70 MB raw, compressed by APK zip.
- `libshogi_core.so` (Rust + tract) — 14 MB raw.
- Vendored Japanese font — 40 MB raw, ~18 MB imported.
- ONNX model — 1.3 MB.

**Cheap wins:**
- Subset the font to only used glyphs. A ~15-glyph piece-kanji subset
  drops the font to tens of KB. See `ROADMAP.md` Phase 7 entries for
  both the static-text and scan-driven approaches.
- Ship arm64-v8a only (already doing). Adding armeabi-v7a ≈ +14 MB
  Rust `.so` per architecture.
- `strip = "symbols"` is already in `Cargo.toml`'s release profile —
  don't remove it.
- The `libgodot_android.so` size is mostly engine; can only avoid with
  a custom build.

## Layout is off on devices with a different aspect ratio than the base

**Symptom:** fine on one phone, clipped / dead-spaced on another. Desktop
dev looks fine.

**Cause:** hardcoded sizes like `custom_minimum_size = Vector2(720, 720)`
baked against the project's base viewport. Devices don't share the base
viewport's aspect ratio, so with `stretch/aspect = "expand"` the
effective viewport height (or width on landscape) differs per device.

**Fix:** compute sizes at runtime from `get_viewport_rect().size`, hook
`get_viewport().size_changed` to re-fit on rotate / resize /
split-screen / foldable unfold. Pattern in `GameController._refit_board`.

## cargo-ndk: `Failed to load Cargo.toml in current directory`

**Symptom:** `cargo ndk … --manifest-path native/shogi_core/Cargo.toml`
errors out.

**Cause:** `cargo-ndk` (unlike plain `cargo`) does not accept
`--manifest-path`; it insists on running in the crate directory.

**Fix:**
```bash
(cd native/shogi_core && cargo ndk --platform 24 -t arm64-v8a \
   --output-dir ../../native/bin/android build --release)
```

## Debug log filter for Godot

`adb logcat` floods with system noise. Godot prints to the `godot` tag:
```bash
adb logcat -c                         # clear buffer first
# run the app, reproduce the issue, then:
adb logcat -d godot:V '*:S'           # only godot lines
# or live:
adb logcat godot:V '*:S'
```
Include `:V` (verbose) — `print` lands at `I` (info) but errors at `E`.
`*:S` silences all other tags.
