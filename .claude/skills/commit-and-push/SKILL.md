---
name: commit-and-push
description: Commit code changes and push via Git. Use when the user asks to commit, push, or save their work to the repository.
argument-hint: commit message or description of changes
---

# Commit and Push

You are committing and pushing code changes for **清正学園将棋部** (SeiShinGakuen_ShougiBu) — a single-player Android Shogi game built with Godot 4.6.2 (Mobile renderer) and a Rust GDExtension for rules + AI.

## Commit Message Convention

This project uses **Conventional Commits**-style prefixes. Look at `git log` before writing a message — every existing commit follows this pattern, often with a scope.

- **Subject line**: `<type>(<scope>): <imperative summary>`. Lowercase after the colon, no trailing period. Scope is optional but encouraged (`feat(ui):`, `feat(ai):`, `build(tools):`, `chore(audio):`, etc.).
- **Body** (optional, blank line after subject): explain *why*, not just *what*. Reference past incidents, constraints, or rationale that wouldn't survive a year. Wrap to ~72 chars.
- **`Co-Authored-By` trailer**: this project's recent commits **do** carry one when Claude collaborated on the work. Append:
  ```
  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```
  Look at the most recent commit to mirror the exact identity string — adjust if the user is on a different model.
- **No GPG signing.** `git log --show-signature` reports `signed: N` across the existing history. Don't pass `-S`, and don't add `--signoff` either (this project does not use DCO).

### Allowed types and scopes seen in the log

```
feat:     new user-visible feature                  scopes: ui, ai, audio, menu, ui/menu
fix:      bug fix                                   scopes: ui, android
docs:     README / ROADMAP / docs/ / ADR            scopes: assets, audio
chore:    tooling, assets, branding, audio swaps    scopes: ui, audio, branding, release
refactor: code restructure, no behavior change      scopes: tools
build:    build pipeline / tools that produce       scopes: tools
          binaries (build_all.sh, font subsetter,
          release plumbing)
test:     adding or fixing tests
perf:     performance work
```

If a change spans multiple types, pick the dominant one. If you can't, that's a hint to split — see the `commit-changes-by-topic` skill.

### Examples from this repo

```
feat(ai): MCTS-backed 先生モード move suggestions
feat(ui): defer 先生モード zoom-back so animations don't fight
build(tools): --aab flag for Play-Store-ready bundle
build(tools): release APK pipeline with per-project keystore
refactor(tools): port font subsetter from shell to Python
chore(branding): app icon and 清正学園将棋部 display name
chore(release): version 0.1.0
```

Subjects often contain Japanese terms when the change is about a game-side feature (`先生モード` = teacher mode, `加藤先生` = the Lv 8 AI character). That's fine — UTF-8 throughout.

## Workflow

1. **Review changes** — run `git status` and `git diff` (and `git diff --cached` if anything is already staged) to understand what will be committed. Read the actual diff before writing the message; don't infer from filenames.

2. **Stage by explicit path.** Never `git add -A` / `git add .`. Be careful **not** to stage:
   - `.android-release-pass` — release keystore password file (gitignored, but verify).
   - `*.keystore` / `*.jks` — signing keys (gitignored).
   - `build/` — APK / AAB outputs (gitignored).
   - `native/shogi_core/target/` — Rust build outputs (gitignored).
   - `native/bin/` — copied .so artifacts (gitignored — the .so is rebuilt by `tools/build_all.sh`, not tracked).
   - `.godot/` — Godot's local cache (gitignored).
   - `android/` — generated Android build template tree (gitignored).
   - `assets/fonts/**/*-full.otf` — vendored source fonts; only the small subset `.otf` next to them is shipped.
   - Anything resembling `.env`, `secrets.*`, `credentials.*`.

3. **Asset-pair invariant.** When committing image / sound / font assets, the `.import` sidecar Godot generates **must** land in the same commit as the binary it describes. Splitting them produces a broken checkout where Godot can't load the resource.

4. **Encoder byte-parity invariant.** Touching `native/shogi_core/src/encode.rs` or `move_index.rs` requires regenerating fixtures (`tools/gen_fixtures.py`) and re-running `cargo test --manifest-path native/shogi_core/Cargo.toml` *before* committing — the parity tests against ShogiDojo are the project's defense against silently-broken AI inference. Don't bypass them.

5. **Compose the message** — pick the right `type(scope)` prefix, write a concise imperative subject. Add a body for non-trivial changes; keep the *why* in front of the *what*.

6. **Commit** via HEREDOC for proper formatting:

   ```bash
   git commit -m "$(cat <<'EOF'
   feat(ui): <imperative summary>

   Optional body explaining why.

   Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
   EOF
   )"
   ```

7. **Verify** — `git log -1 --oneline` and a quick `git show HEAD --stat` to confirm the right paths landed.

## Push

- **Always confirm with the user before pushing.** Pushing is visible to others and hard to revert; do not push automatically just because a commit succeeded.
- Single remote: `origin → git@github.com:hiroshiyui/SeiShinGakuen_ShougiBu.git`.
- Default (and currently only) branch: `main`. There is no `master`, no `develop`.
- Push with `git push origin main` (or the user's current branch name on a feature branch).
- **Never force-push to `main`** without an explicit, unmistakable request. Prefer `--force-with-lease` over `--force` when force is genuinely needed on a feature branch.
- **Never `--no-verify`.** If a pre-push hook fails, investigate the underlying issue.

## Branching

`main` is the only branch today. Feature branches with descriptive `lowercase-with-dashes` names are fine (e.g. `mcts-perf`, `aab-release-plumbing`). Branch off `main`, target `main`.

## Task: $ARGUMENTS
