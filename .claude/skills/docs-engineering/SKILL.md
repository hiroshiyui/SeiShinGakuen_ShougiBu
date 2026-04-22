---
name: docs-engineering
description: Write, review, or revise technical documentation (README, architecture notes, ADRs, guides, doc comments) with engineering rigor — accuracy, structure, and no drift from code. Use when the user asks to "write docs", "improve the README", "document this module", "add an ADR", or to review existing docs for staleness. Not for code comments on a single function (just edit the code).
---

# docs-engineering

Treat documentation as code: precise, reviewed, kept in sync with what it describes.

## When to use

- Writing or rewriting a README, CONTRIBUTING, architecture overview, or module guide.
- Authoring an ADR (Architecture Decision Record).
- Reviewing existing docs for accuracy after code changes.
- Structuring a `docs/` tree from scratch.
- Not for a one-line comment fix — just edit the file.

## Core principles

1. **Accuracy beats completeness.** A short doc that's right is more valuable than a long one that's half-stale. If you can't verify a claim, don't make it.
2. **Write for the reader, not the author.** Name the audience (new contributor? operator? API consumer?) and answer *their* questions. Cut anything written only to flatter the author or the project.
3. **Don't duplicate what code already says.** Identifiers, types, and signatures belong in code. Docs explain the *why*, constraints, trade-offs, and non-obvious invariants.
4. **Every example must be runnable.** If you show a command, it should work as written. If you show code, it should compile (or be clearly marked as pseudocode).
5. **Link, don't retype.** Reference code with path and line (`src/foo.rs:42`) instead of pasting it — the paste will rot.
6. **Prune aggressively.** Outdated docs are worse than missing docs because they mislead. When in doubt, delete.

## Document types and shapes

### README

Answers "what is this, why should I care, how do I get started?" — in that order. Aim for one screen before the first heading jump.

Structure:
1. **One-sentence pitch** — what the project *is*, not what it aspires to be.
2. **Status** — alpha / beta / production, supported platforms. Honest.
3. **Quickstart** — shortest path to a working result. Copy-pasteable.
4. **Pointers** — links to deeper docs (architecture, contributing, reference). README is a table of contents, not a manual.

Avoid: marketing adjectives, feature lists that duplicate the code, changelogs (use `CHANGELOG.md`), roadmaps (use `ROADMAP.md`).

### ROADMAP

Answers "what order are we building this in, and what's the current slice?" — for contributors and stakeholders who want to know what comes next without reading the issue tracker.

Structure:
1. **Intro** — one paragraph on the sequencing philosophy (e.g. "small shippable slices, don't start N+1 until N works").
2. **Numbered slices** — each slice has a short title, a goal stated in terms of observable behavior, and any load-bearing constraints that must be designed in at that slice (not bolted on later).
3. **Out of scope** — optional, but useful if the project attracts "why don't you just…" suggestions.

Rules:
- One roadmap per repo. Don't fork it into `docs/roadmap-v2.md` — edit in place.
- Slices are ordered by dependency, not priority. If slice 5 depends on slice 3, it must come after.
- Don't put dates on slices unless there's a real external deadline. Fighting-game-engine time is not calendar time.
- Decisions that affect *every* slice (determinism, licensing, input abstraction in this repo) belong in the intro or in slice 1, not scattered.

**When a slice (or sub-task inside a slice) is done:** update `ROADMAP.md` in the same change that delivers the work. Don't defer it to a follow-up commit — the roadmap drifts out of sync within days otherwise.

1. **Mark it done** in the heading: `## 1. Rust GDExtension scaffold ✅` (or `[done]` — pick one convention and keep it consistent across the file).
2. **Summarize what actually shipped** in 1–3 bullets directly under the heading, replacing the forward-looking prose. Focus on what a future reader needs to know:
   - Concrete deliverables (classes, files, crates added).
   - Decisions that were made during the slice and are now load-bearing (e.g. "picked `I32F32` as the sim numeric type"). These may also warrant an ADR.
   - Any scope that was *deferred* out of the slice — note it explicitly so it isn't lost.
3. **Keep the slice in place.** Don't renumber, don't move to a separate "done" section. The roadmap is also a log; order and numbering are stable references.
4. **Don't delete the original intent.** If the original description is useful context, move it under a `Original plan:` sub-bullet rather than overwriting it.
5. If the slice shipped *differently* than planned (scope changed, approach pivoted), say so in one line. Silent rewrites hide useful history.

Avoid: vague aspirations ("better performance"), marketing bullets, anything that belongs in an ADR (decisions) or CHANGELOG (what already shipped, with dates).

### Architecture doc

Answers "how is this system put together and why?" — for a reader who will modify it.

Structure:
1. **Scope** — what this doc covers and what it doesn't.
2. **Invariants** — the properties the system must preserve (e.g. "sim is bit-deterministic across platforms"). Lead with these; everything else is in service of them.
3. **Layers / boundaries** — the hard lines, with one paragraph per layer on responsibility.
4. **Data flow** — how a request / tick / frame moves through the system.
5. **Extension points** — where contributors are expected to add code, and where they aren't.

ASCII diagrams are fine and survive version control. Binary-format diagrams (draw.io exports, PNGs) rot — avoid unless the source is checked in next to them.

### ADR (Architecture Decision Record)

One decision per file. Numbered, immutable once accepted.

```
# ADR-NNNN: <short title>

## Status
Proposed | Accepted | Superseded by ADR-MMMM

## Context
What forces are at play? What constraints? What did we try?

## Decision
What we're doing. Present tense, active voice.

## Consequences
What this makes easy, what it makes hard, what we're giving up.
```

Never rewrite an accepted ADR — supersede it with a new one that links back.

### Module / package docs

Answers "what does this module do, what's the entry point, what are the gotchas?" — for someone about to import it.

Keep it adjacent to the code (doc comment at the top of the module, or `README.md` in the folder). If it's more than a screen long, it probably belongs in `docs/`.

### Doc comments (rustdoc, GDScript docstrings, etc.)

- Public API: explain intent, invariants, panics/errors, and at least one example.
- Internal: only when behavior is non-obvious. A good name beats a comment.
- Never restate the signature.

## Writing mechanics

- **Voice:** active, present tense, second person ("you") for instructions.
- **Sentence length:** short. If a sentence has more than one clause, consider splitting.
- **Headings:** imperative or noun phrases, not questions. Readers scan headings; make them informative.
- **Lists:** parallel structure. If one bullet starts with a verb, all should.
- **Code blocks:** always language-tagged (` ```rust `, ` ```bash `). Never tag as `text` when a real language applies.
- **Links:** use relative paths within the repo, absolute URLs only for external.
- **No emojis** unless the user explicitly wants them.
- **No marketing language:** "blazingly fast," "robust," "powerful," "seamless." Say what it actually does.

## Review checklist

When reviewing or updating existing docs:

- [ ] Every code reference (path, symbol, flag, command) still exists — grep to confirm.
- [ ] Every example runs / compiles as written.
- [ ] No dead links (internal or external).
- [ ] Scope statement still matches what the system does.
- [ ] Nothing contradicts CLAUDE.md, README, or ADRs.
- [ ] Terminology matches the rest of the codebase (same concept → same word everywhere).
- [ ] No duplicated content that would need to be updated in two places.

If a doc fails more than two of these, consider rewriting rather than patching.

## Anti-patterns to avoid

- **Aspirational docs:** describing features that don't exist yet as if they did. If it's planned, say "planned" explicitly and link to the roadmap.
- **Tutorials that drift:** step-by-step guides with version-specific commands and no verification. Prefer short quickstarts; defer long tutorials to CI-tested example projects.
- **Docs-as-blog-post:** narrative voice, first-person anecdotes, "let's" phrasing. Readers want a reference, not a story.
- **Copying code into prose:** any code pasted inline will diverge from source. Link instead.
- **Comment graveyards:** `// TODO from 2021`, `// old impl kept for reference`. Delete or file an issue.
- **Over-structuring:** a three-paragraph doc doesn't need six H2s.

## Output

When writing a new doc, produce the file and stop. Don't also write a summary blog post, a changelog entry, or an announcement — those are separate asks.

When revising, show the diff via Edit; don't rewrite unchanged sections.
