---
name: commit-changes-by-topic
description: Split pending working-tree changes into multiple topic-scoped commits. Use when the user has a mix of unrelated edits staged or unstaged and wants them committed as separate, logically coherent commits rather than one big blob. Examples- "commit these by topic", "split this into commits", "break this up into proper commits".
---

# commit-changes-by-topic

Group pending changes by topic and create one commit per topic, in an order that keeps each commit independently coherent.

## When to use

- The working tree has unrelated changes mixed together (e.g. a bug fix, a refactor, and a doc tweak).
- The user asks to "commit by topic", "split into commits", "break this up", or similar.
- Not for a single focused change — that's just a normal commit.

## Steps

### 1. Survey the working tree

Run these in parallel:

- `git status` (never `-uall` — memory issues on large repos)
- `git diff` (unstaged)
- `git diff --cached` (staged)
- `git log -n 10 --oneline` (match existing commit-message style)

For any untracked file whose purpose isn't obvious from its name, `Read` it before assigning a topic.

### 2. Propose a commit plan

Group hunks/files into topics. A topic is a change that would make sense as a standalone PR description. Typical topics:

- Feature addition (`feat:`)
- Bug fix (`fix:`)
- Refactor with no behavior change (`refactor:`)
- Docs / comments (`docs:`)
- Tests only (`test:`)
- Build / tooling / config (`chore:` or `build:`)

Order commits so each one leaves the tree in a buildable state when possible (e.g. add a helper before the caller that uses it). If two topics touch the same hunk and can't be cleanly separated, say so and ask the user how to handle it — don't silently bundle.

Present the plan to the user as a numbered list:

```
1. fix: <subject>     — <files>
2. refactor: <subject> — <files>
3. docs: <subject>    — <files>
```

Wait for confirmation before committing. The user may redirect (merge topics, reorder, drop a file, reword a subject).

### 3. Commit each topic sequentially

For each topic, in order:

1. Reset the index so only the current topic is staged: `git reset` (if anything is pre-staged from earlier), then `git add <specific paths>` — never `git add -A` or `git add .`.
2. If a single file contains hunks belonging to multiple topics, split at the hunk level. Prefer the non-interactive path: capture the diff (`git diff -- <file> > /tmp/topic.patch`), edit the patch to keep only this topic's hunks, then `git apply --cached /tmp/topic.patch`. `git add -p` driven by a heredoc of `y`/`n` responses is possible but fragile (prompt order is not stable across hunk counts) — use only if the patch-file approach fails. Never use `git add -i` (interactive menu). Always prefer splitting at the file boundary when feasible; intra-file splits are a last resort.
3. Verify the staged diff matches the topic: `git diff --cached`.
4. Create the commit with a HEREDOC message:

   ```
   git commit -m "$(cat <<'EOF'
   <type>: <subject>

   <optional body explaining why, not what>

   Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
   EOF
   )"
   ```

5. If a pre-commit hook fails, fix the underlying issue and create a NEW commit — never `--amend`, never `--no-verify`.

### 4. Report

After all commits land, show `git log -n <N> --oneline` so the user can see the resulting history. If any changes remain unstaged (intentionally left out, or a hunk split stumbled), call that out explicitly.

## Rules

- Never commit files that look like secrets (`.env`, `credentials.*`, private keys). Flag them and skip.
- Never include unrelated files in a topic to "round it out."
- Never `git add -A` / `git add .` — stage by explicit path.
- Never `--amend` a prior commit in this flow; each topic is a fresh commit.
- Never `--no-verify` to bypass a failing hook.
- Don't push. This skill only creates local commits. If the user wants to push, they'll ask.
- Match the repo's existing commit-message style (conventional commits, sentence case, etc.) as seen in `git log`. The examples above use conventional-commits; adapt if the repo uses something else.

## Edge cases

- **Nothing to commit:** say so and stop. Don't create an empty commit.
- **One topic only:** confirm with the user that a single commit is fine, then make it — no need to invoke the full plan-and-confirm dance.
- **Entangled hunks that can't be cleanly split:** surface the conflict, propose the smallest bundling that still tells a coherent story, and let the user decide.
- **Generated files (lockfiles, build artifacts):** group with the change that caused them (e.g. `Cargo.lock` goes with the dep bump), not as their own topic.
