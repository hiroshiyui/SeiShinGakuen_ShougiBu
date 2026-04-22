# ADR-0004: Extract runtime-opened blobs from res:// to user:// on Android

## Status

Accepted.

## Context

On desktop, `res://` paths globalize to the real filesystem — any
library can `open()` them. On Android (and other Godot exports) `res://`
lives inside the PCK, which is packed into the APK's `assets/` dir.
Godot's `FileAccess` handles the virtual filesystem transparently, but
third-party native code (tract, future sprite loaders, font loaders
called outside Godot's font system, anything using
`std::fs::File::open` or `mmap`) can only see OS-level paths.

`tract_onnx::onnx().model_for_path(path)` reads from the filesystem
via `std::fs`. Pointing it at `res://models/bonanza.onnx` returns
"file not found" in an exported build.

## Decision

Wrap blob-like resources behind a helper that, on exported builds,
copies from `res://` to `user://` on first access and returns the
globalized `user://` path. In the editor, globalizes `res://`
directly (no copy needed). Exposed as
`Settings.model_absolute_path()`.

## Consequences

**Makes easy:**

- One pattern for any future third-party native asset reader: SFX,
  KIF importers, ONNX variants, etc.
- Copy happens exactly once per install (checked with
  `FileAccess.file_exists`), ~100 ms overhead at first launch.
- Editor and export both pass the same path shape to native code; the
  native code stays platform-agnostic.

**Makes harder / accepts:**

- Doubles blob storage at install time (PCK copy + user-data copy).
  For a 1.3 MB model this is trivial; for a 100 MB asset we'd want to
  stream-decompress from PCK via `FileAccess` → temp path instead.
- App data wipe forces re-extraction. Acceptable.
- If the blob upgrades between releases, the helper needs a version
  check before trusting the cached copy. Current model is static; the
  check is not yet implemented.

## See also

- `scripts/autoload/Settings.gd::model_absolute_path`.
- `scripts/game/GameController.gd::_load_ai_if_needed`.
- [`android-gotchas.md`](../android-gotchas.md) — "Third-party native
  code can't read `res://`".
