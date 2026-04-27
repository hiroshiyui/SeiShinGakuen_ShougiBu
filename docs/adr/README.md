# Architecture Decision Records

Numbered, immutable once accepted. Each file answers "why is the code
this way?" for a specific design choice where the easy-looking
alternative was rejected for non-obvious reasons.

| # | Title | Status |
|---|---|---|
| [0001](./0001-onnx-runtime-tract.md) | ONNX inference runtime — tract | Accepted |
| [0002](./0002-async-ai-via-godot-thread.md) | Run AI MCTS on a Godot Thread, not a Rust-owned thread | Accepted |
| [0003](./0003-mailbox-board-representation.md) | Mailbox board representation, defer bitboards | Accepted |
| [0004](./0004-model-and-fonts-via-user-copy.md) | Extract runtime-opened blobs from res:// to user:// on Android | Accepted |
| [0005](./0005-font-subset-pipeline.md) | Keep full upstream fonts in-repo, subset at build time | Accepted |
| [0006](./0006-character-driven-difficulty.md) | AI strength is chosen by picking a character, not a level | Accepted |
| [0007](./0007-font-subsetter-scans-tres.md) | Font subsetter scans `assets/**/*.tres`, not just code/scenes | Accepted |
| [0008](./0008-review-mode-scratch-core.md) | Review mode keeps a separate `_review_core` instead of rewinding the live core | Accepted |
| [0009](./0009-kif-library-app-private-storage.md) | KIF library writes to app-private external Documents, not shared storage | Accepted |

## Authoring a new ADR

- One decision per file. Numbered. Immutable once accepted.
- Use the template below. Drop the unused sections if they don't apply.
- Never rewrite an accepted ADR — supersede it with a new one whose
  `Status` says `Supersedes ADR-NNNN`, and update the old one's
  `Status` to `Superseded by ADR-MMMM`.

```markdown
# ADR-NNNN: <short title>

## Status
Proposed | Accepted | Superseded by ADR-MMMM

## Context
What forces are at play? What constraints? What did we try?

## Decision
What we're doing. Present tense, active voice.

## Consequences
What this makes easy, what it makes hard, what we're giving up.

## See also
Links to the code that implements the decision.
```
