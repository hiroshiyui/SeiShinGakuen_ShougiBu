# ADR-0010: License the project under GPL-3.0-or-later

## Status

Accepted.

## Context

Through the 0.1.x and 0.2.x releases the repository carried no
`LICENSE` file. Practically that means "all rights reserved" by
default — visitors could read the code on GitHub but had no legal
right to fork, modify, redistribute, or contribute back. The README
explicitly noted "ライセンス未指定" (license not designated) and
deferred the decision to a deliberate moment.

Choosing a license for 0.3.0 needed to balance:

- **Author intent.** This is an open project the author wants others
  to be able to learn from, fork, and improve — but with the same
  obligations they themselves accepted: derivatives must remain open
  on the same terms, source must travel with binaries, no proprietary
  re-licensing.
- **Dependency compatibility.** Every shipped third-party piece must
  be GPL-compatible:
  | Component | License | Compatible? |
  |---|---|---|
  | Godot 4.6.2 (engine) | MIT | ✅ |
  | godot-rust / gdext | MPL-2.0 | ✅ (one-way: MPL → GPL) |
  | tract (`tract-onnx`) | MIT or Apache-2.0 | ✅ |
  | Other Rust crates | MIT / Apache-2.0 | ✅ |
  | Fude Goshirae (font) | SIL OFL 1.1 | ✅ |
  | Noto Serif JP (font) | SIL OFL 1.1 | ✅ |
  | `models/bonanza.onnx` | from sister project ShogiDojo | tracked separately |

  All bundled code/fonts are GPL-compatible. The model is the
  author's own asset from another repo; same-author cross-licensing.

- **Sibling project alignment.** The training-side counterpart
  [ShogiDojo](https://github.com/hiroshiyui/ShogiDojo/) is the same
  author's; matching the license here means the model + the engine
  that runs it can be redistributed as one consistent open work.

- **Forward compatibility.** "or later" gives future-FSF revisions of
  the GPL force without having to re-license every contributor's
  patches. A common pragmatic choice; rejected only if there's a
  specific incompatibility we want to lock in against.

We considered the obvious alternatives:

1. **MIT / Apache-2.0.** Maximum permissive. Lets anyone wrap the
   code in a closed-source product without giving back. Doesn't
   match the "share-alike" intent.
2. **MPL-2.0.** File-level copyleft; works well for libraries but
   weaker than GPL for an end-user application.
3. **AGPL-3.0-or-later.** Strongest copyleft, covers
   network-service derivatives. Not relevant for a single-player
   offline mobile app — there's no server SaaS loophole to close.
4. **GPL-3.0-only.** Locks out future revisions; no compelling
   reason to.

## Decision

License the entire repository under **GNU General Public License
version 3.0, or (at your option) any later version**
(`SPDX-License-Identifier: GPL-3.0-or-later`).

The canonical license text lives at [`LICENSE`](../../LICENSE) at the
repo root, fetched verbatim from
<https://www.gnu.org/licenses/gpl-3.0.txt>. The README's
"ライセンスとクレジット" section names GPL-3.0-or-later and links to
the file.

We're not adding per-file SPDX headers at this time. The repository-
level declaration is sufficient for an in-progress single-author
project; if external contributions arrive at scale we can reopen
that with a separate ADR.

## Consequences

**Makes easy:**

- Forks can take the code, modify it, and redistribute under the same
  GPL-3.0-or-later terms — the contribution loop the author wants.
- Anyone shipping a binary derived from this work must offer the
  corresponding source on the same terms. No "shogi engine wrapped in
  proprietary trial-locked launcher" derivatives.
- Compatible with every dependency we already ship; no third-party
  swap-outs needed.
- The sister project ShogiDojo can adopt the same license without
  conflict, keeping the training pipeline + the runtime engine as
  one coherent open work.

**Makes harder / accepts:**

- Closed-source forks are off the table — by design. If a downstream
  user wants to ship a proprietary derivative, they need a separate
  commercial agreement with the copyright holder.
- Any future dependency we bring in must be GPL-compatible. Watch out
  for crates that are GPL-incompatible (e.g. SSPL, BUSL, "source-
  available") — they're a non-starter under this license.
- Distribution channels that demand a non-GPL licensing surface
  (some app stores have specific terms about what end-users can do
  with the binary) need to be evaluated against the GPL's
  requirements before submitting. Currently moot — distribution is
  GitHub Releases sideload only — but worth knowing if Play Store
  re-enters scope.

## See also

- [`LICENSE`](../../LICENSE) — canonical license text.
- [README.md ライセンスとクレジット section](../../README.md) — user-
  visible license declaration + per-asset notes.
- [ROADMAP.md Open Questions](../../ROADMAP.md) — historical record
  of "license not yet declared" being explicitly deferred to a
  later ADR.
