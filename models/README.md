# AI model

`bonanza.onnx` — the policy + value network the in-game AI and the
kifu analyser run on. It is a data asset, not executable code: the
Rust GDExtension (`native/shogi_core`, via tract) loads it at runtime.

| | |
|---|---|
| Architecture | AlphaZero-style residual net, 10 blocks × 128 filters ("Bonanza v2") |
| Input / output | 45-plane position encoding → 139-plane move policy + scalar value |
| Format | ONNX, ~12 MB, exported from PyTorch |
| Training | Bonanza-method supervised learning (policy cross-entropy against the move played, value MSE against the game result) |
| Training code | [ShogiDojo](https://github.com/hiroshiyui/ShogiDojo) (`train_bonanza.py`), by the same author |
| Training data | Shogi game records in CSA format; ShogiDojo's Bonanza pipeline is set up for the public Floodgate (wdoor) archive |

The encoder on the Rust side is byte-parity-tested against ShogiDojo's
Python encoder (`tools/gen_fixtures.py` → `tools/fixtures/fixtures.bin`),
so the two must be kept in lock-step — see `CLAUDE.md`.

## License

The model weights are distributed under the same terms as the rest of
this repository, **GPL-3.0-or-later** (see [`LICENSE`](../LICENSE)).
They were trained by the project author; no third-party model weights
are included.

## Packaging notes

- Godot's `all_resources` export filter skips `.onnx`, so
  `export_presets.cfg` adds `include_filter="*.onnx"`.
- On Android the file is extracted from the APK to `user://` on first
  launch (`Settings.model_absolute_path()`) because tract cannot read
  from inside the PCK.
- Re-training happens in ShogiDojo; copy the exported `.onnx` here and
  regenerate the parity fixtures if the encoding changed.
