# Release notes

One file per shipped version, named `<X.Y.Z>.md`. The body of each
file is what gets fed to `gh release create --notes-file …` (the
`release-engineering` skill takes care of that invocation).

The same prose is summarised in [`CHANGELOG.md`](../../CHANGELOG.md)
at the repo root, in [Keep a Changelog](https://keepachangelog.com)
format. Both should land in the same commit when you cut a release —
they're meant to stay in lockstep, not diverge.

## Convention

- Headline at the top: `# <X.Y.Z> — short title`.
- `## Highlights` (or `## ハイライト`) for 1–3 user-visible bullets in
  Japanese (the audience reads Japanese; the technical commit list is
  not the headline).
- `## Changes` grouped by Conventional Commit type (Features / Fixes
  & refactors / Tooling & docs / Tests).
- Trailing `**Full Changelog**:` link to the GitHub compare view, or
  `commits/<X.Y.Z>` on the first release in a chain.

## Style

No emojis (matches the rest of the docs). The back-filled
`0.1.2.md` originally shipped with a few decorative emojis on the
GitHub release body; they were stripped during back-fill so the
checked-in copy stays consistent with the rest of the repo's docs.
The original GitHub release body itself still has them — we're
choosing internal consistency over byte-for-byte mirror of history.
