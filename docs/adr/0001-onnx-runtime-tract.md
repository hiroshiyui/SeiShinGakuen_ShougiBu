# ADR-0001: ONNX inference runtime — tract

## Status

Accepted.

## Context

Phase 5 needed an ONNX runtime callable from a Rust cdylib loaded by
Godot, targeting both `x86_64-unknown-linux-gnu` for dev and
`aarch64-linux-android` for ship. The Bonanza model is small
(1.3 MB, policy + value head).

First attempt: `ort = "2.0.0-rc.*"` (Rust bindings over ONNX Runtime
C++). Two blockers surfaced inside a single afternoon:

1. `download-binaries` feature pulled transitive `ort-sys` whose build
   script called a `tls_config` method missing from the `ureq` version
   it pinned. No combination of features rescued it.
2. Disabling `download-binaries` and trying `load-dynamic` against the
   system `libonnxruntime.so` hit a second mismatch: `ort` lib
   `2.0.0-rc.12` referenced `ort-sys::OrtApi` fields
   (`SessionOptionsAppendExecutionProvider_VitisAI`) that the crate's
   current `ort-sys` version didn't expose.

Either blocker on its own would be a known-good pinning exercise; both
together, during an `rc` series known to ship breakage between patch
versions, meant the effort to ship `ort` reliably exceeded the effort
to evaluate alternatives.

## Decision

Use [`tract-onnx`](https://crates.io/crates/tract-onnx) (pure-Rust ONNX
runtime by snipsco) for all ONNX inference.

## Consequences

**Makes easy:**

- Android cross-compilation is one `cargo-ndk` command with no external
  libraries to bundle. `libshogi_core.so` is the only `.so` in the APK.
- Reproducible builds: no network download step at compile time, no
  shared library vs. linker headaches.
- Rust 2024 + Rust 1.93 toolchain support with no weird pinning.

**Makes harder / accepts:**

- Per-forward-pass cost is ~5 ms on desktop and ~1-2 ms on arm64 —
  roughly 2× slower than `ort` would be on CUDA, but the model runs
  CPU-only anyway and the MCTS playout budget is bounded by UI
  responsiveness, not inference throughput.
- `libshogi_core.so` is larger (14 MB release-stripped, vs. ~2.6 MB for
  a stub). The tract runtime is statically linked into our cdylib.
- If we ever want GPU inference or DirectML / Core ML, we'd have to
  revisit.

**Revisit when:** Phase 6 arm64 throughput is inadequate, or if we add
a second larger model whose inference cost dominates.

## See also

- `native/shogi_core/src/nn.rs` — the wrapper.
- `native/shogi_core/Cargo.toml` — `tract-onnx = "0.21"`.
