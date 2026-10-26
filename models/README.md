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
| Training code | [ShogiDojo](https://github.com/hiroshiyui/ShogiDojo) (`train_bonanza.py`, GPL-3.0-or-later), by the same author |
| Training data | Floodgate game records (shogi-server "wdoor" CSA archives, `wdoor2011` – `wdoor2026`), published by the [shogi-server project](https://github.com/shogi-server/shogi-server) — release [2026-04-10](https://github.com/shogi-server/shogi-server/releases/tag/2026-04-10) |

The encoder on the Rust side is byte-parity-tested against ShogiDojo's
Python encoder (`tools/gen_fixtures.py` → `tools/fixtures/fixtures.bin`),
so the two must be kept in lock-step — see `CLAUDE.md`.

## License

The model weights are distributed under the same terms as the rest of
this repository, **GPL-3.0-or-later** (see [`LICENSE`](../LICENSE)).
They were trained by the project author with ShogiDojo, which is itself
GPL-3.0-or-later; no third-party model weights are included.

## Training-data attribution

The weights were derived from game records played on **Floodgate**, the
computer-Shogi server run by the shogi-server project at the University
of Tokyo (`wdoor.c.u-tokyo.ac.jp`). The records are the output of
engines (and some humans) that connected to the server; the shogi-server
release page states no separate licence for the archives, so treat them
as provided for research use and credit the project when publishing
results. Full attribution, including which archives and release were
used, is in ShogiDojo's
[`NOTICE.md`](https://github.com/hiroshiyui/ShogiDojo/blob/main/NOTICE.md).
The raw records are not part of this repository.

## Packaging notes

- Godot's `all_resources` export filter skips `.onnx`, so
  `export_presets.cfg` adds `include_filter="*.onnx"`.
- On Android the file is extracted from the APK to `user://` on first
  launch (`Settings.model_absolute_path()`) because tract cannot read
  from inside the PCK.
- Re-training happens in ShogiDojo; copy the exported `.onnx` here and
  regenerate the parity fixtures if the encoding changed.
