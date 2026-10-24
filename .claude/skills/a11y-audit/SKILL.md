---
name: a11y-audit
description: Audit and fix accessibility (a11y) issues in the 清正学園将棋部 Godot/Android game — touch-target size, text size and contrast, colour-only cues, motion, haptic/sound redundancy, safe-area and camera-cutout collisions, and screen-reader readiness. Use this whenever the user mentions accessibility, a11y, readability, legibility, contrast, "hard to see", "hard to tap", colour blindness, font size, text scaling, or asks to make the UI friendlier for older players or small screens — even if they don't say "accessibility". Also run it before a release when the UI changed.
argument-hint: optional scope — a scene (Main.tscn), a screen (settings), or "all"
---

# Accessibility Audit

You are auditing **清正学園将棋部** (SeiShinGakuen_ShougiBu), a single-player
Android Shogi game: Godot 4.7.2 Mobile renderer, GDScript UI, Rust rules
core. There is no web DOM here, so WCAG applies by analogy: the targets
are touch size, text legibility, non-colour cues, motion, and feedback
redundancy. The output is a short findings list ranked by impact, with
fixes applied (or proposed, if the user only asked for a check).

## Why this matters here

The player base skews toward people who learn Shogi from a club
teacher, including older players and kids. The game runs on phones held
at arm's length, often outdoors. Kanji piece glyphs are already small.
Any UI text or tap target that is marginal on a desktop monitor is
unusable on a 6-inch screen in sunlight.

## Project-specific facts you need

- **Logical resolution is 720×1280, stretch `canvas_items` / `expand`.**
  One Godot px is **not** one Android dp. On a 412 dp-wide phone (Pixel
  8a), 1 Godot px ≈ 0.57 dp. Material's 48 dp minimum touch target is
  therefore **~84 Godot px**. A `custom_minimum_size = Vector2(0, 56)`
  button is only ~32 dp tall. Use `references/checklist.md` for the
  conversion table.
- **Theme default font is 26 px** in `assets/themes/ui.tres` (Noto Serif
  JP Medium). 26 px ≈ 15 dp, which is the floor for body text. Anything
  with a `theme_override_font_sizes/font_size` below 26 needs a reason.
- **Safe area** is handled by `Settings.safe_area_insets()` and
  `SafeAreaLayout.gd`. Root-level overlays outside `Layout` must either
  honour that inset or be positioned relative to the board via
  `GameController._place_above_board()`. Screen-top anchors collide
  with the front camera on punch-hole devices (this already bit the
  王手 banner once).
- **Overlay text style** the user has approved: bold Noto Serif JP, deep
  red or light colour, thick white/black outline, **no** backdrop panel.
  Don't propose translucent panels for overlay text again.
- **Haptics**: `Input.vibrate_handheld()` is called on moves, but the
  export preset has no VIBRATE permission, so it silently does nothing
  on device (logcat: `SecurityException: VIBRATE permission not found`).
  Check `permissions/vibrate` in `export_presets.cfg`.
- **Sound** is togglable (`Settings.sound_enabled`); haptics are not.
  Any cue that exists only as sound needs a visual or haptic twin.
- **Fonts are subset.** New UI strings must round-trip through
  `tools/build_font_subsets.py` or they render as tofu on device.
- **Godot 4.7 has AccessKit screen-reader support** on desktop and
  partially on Android. Controls get names from `text`; icon-only
  buttons and `TextureRect` need `tooltip_text` or
  `accessibility_name` set so TalkBack has something to read.

## Workflow

1. **Scope.** If the user gave a scene or screen, audit that. Otherwise
   audit `scenes/` and `scripts/` wholesale. Read
   `references/checklist.md` before looking at code so you know what
   you're hunting for and what thresholds apply.

2. **Static scan.** Run the bundled scanner first; it is fast and finds
   the mechanical issues (small targets, small fonts, icon-only
   controls without a label, missing VIBRATE permission):

   ```bash
   python3 .claude/skills/a11y-audit/scripts/a11y_scan.py            # whole project
   python3 .claude/skills/a11y-audit/scripts/a11y_scan.py scenes/Main.tscn
   python3 .claude/skills/a11y-audit/scripts/a11y_scan.py --json     # machine-readable
   ```

   Treat its output as leads, not verdicts. A 40 px-tall node inside a
   container that stretches it to 90 px is fine; a 40 px node with
   `size_flags_vertical = 0` is not. Confirm in the `.tscn` / script.

3. **Manual pass** for what a scanner can't see — read the checklist
   sections on colour-only cues (last-move highlight, check indicator,
   selected square), motion (board zoom tween, piece animation),
   dialog text length, and feedback redundancy. Grep for `modulate`,
   `Color(`, `create_tween`, `vibrate_handheld`, and `SoundManager` to
   find the relevant sites.

4. **Device check when one is attached.** `adb devices`; if a phone is
   connected, build and install (`./tools/build_all.sh --skip-desktop
   --skip-android --skip-fonts` when only scenes/scripts changed), then
   screenshot with `adb exec-out screencap -p`. Crop with Pillow and
   look at it. A contrast ratio computed from hex values says less than
   one screenshot over the real wood-grain and classroom background.
   To reach a specific position (e.g. check), push a `saved_game.cfg`
   with an SFEN via `adb shell run-as org.seishingakuen.shougibu` and
   tap 続きから; delete it afterwards so the menu returns to normal.

5. **Fix.** Apply fixes for anything clear-cut (font size bumps, outline
   additions, `tooltip_text`, min-size increases, permission flag).
   For anything that changes layout math (`_compute_board_side`
   constants, hand strip heights) or adds a user-facing setting (text
   scale toggle, reduce-motion), stop and present the option with a
   one-line cost — those are design decisions the user owns. If you
   touched UI strings, run `./tools/build_font_subsets.py` and don't
   pass `--skip-fonts` on the next build.

6. **Verify** on device if available, re-run the scanner, and run the
   GDScript test suites the change could affect (persistence tests if
   you touched `Settings`, rules tests never — a11y work shouldn't reach
   the FFI).

## Report format

Keep it short. Rank by impact on a real player, not by count.

```
## A11y audit — <scope>

### Fixed
- <what> — <where> — <why it mattered>

### Needs a decision
- <option> — <cost in one line>

### Checked, fine
- <area> — one line each; this is so the user knows what was covered
```

Do not pad "Checked, fine" with generic WCAG items that don't apply to a
native game (no alt text on `<img>`, no heading hierarchy, etc.).

## Pitfalls

- Don't shrink or move the board to make room for larger UI. The board
  is the product; chrome yields to it. If a target can't grow without
  stealing board height, grow it horizontally or increase its hit area
  with a transparent margin instead.
- Don't add outlines to the piece kanji in `Square.gd`; they use the
  brush font and lose their shape. Improve piece legibility via
  contrast of the piece texture, not text effects.
- Font subset: if you change text on screen and skip the subset step,
  the device shows tofu and the user will think you broke rendering.
- Android `tooltip_text` doesn't show on touch; it still feeds the
  accessibility tree, which is the point.
