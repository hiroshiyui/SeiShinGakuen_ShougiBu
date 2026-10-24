# A11y checklist for 清正学園将棋部

Thresholds are in **Godot px** at the project's 720-wide logical
viewport. Conversions assume a 412 dp-wide phone (Pixel 8a, Pixel 7,
most mid-range Android). Narrower 360 dp phones make every Godot px
slightly smaller in dp, so these thresholds err generous.

| Guideline (dp)                  | Godot px (720 / 412) |
|---------------------------------|----------------------|
| 48 dp touch target (Material)   | ~84 px               |
| 44 pt touch target (Apple HIG)  | ~77 px               |
| 24 dp absolute minimum target   | ~42 px               |
| 16 sp body text floor           | ~28 px               |
| 14 sp secondary text floor      | ~24 px               |
| 12 sp caption floor             | ~21 px               |
| 8 dp spacing between targets    | ~14 px               |

The theme default is 26 px (≈15 sp) — body text is already at the
floor, so never override below it for anything a player must read.

## 1. Touch targets

- Every `Button`, `TextureButton`, `OptionButton`, `CheckBox` and every
  `Control` with a `gui_input` tap handler (`Square.gd`, hand piece
  slots) must present a hit area ≥ 84 px on its short side.
- Containers can stretch a node past its `custom_minimum_size`; check
  `size_flags_*`. A `0, 56` button in an `HBoxContainer` with
  `size_flags_vertical = 3` inside a tall row may be fine. One in a
  40 px `StatusBar` row is not.
- Board squares are what they are (board width / 9 ≈ 69 px). That is
  below 84 but squares tile edge-to-edge, so mis-taps land on a
  neighbour rather than nothing. Accept it; don't try to grow squares.
- Hand piece slots (`Hand.tscn`): confirm the slot, not just the piece
  glyph, is the tap target.
- Adjacent targets with no gap (StatusBar buttons) need ≥ 14 px
  separation or a visible border so the thumb can tell them apart.

## 2. Text size and weight

- Overrides < 26 px: justify or raise. Common offenders are badges,
  "v1.0.8" version label, suggestion rows in 先生モード, dialog body.
- Decorative/caption text (credits roles, version) may go to 21 px.
- Prefer weight over size when space is tight: Noto Serif JP Bold is
  shipped as a subset.
- Dialogs: `min_size` on `AcceptDialog` / `ConfirmationDialog` must fit
  the longest string at theme size without clipping. Check Japanese
  strings, which don't wrap at spaces.

## 3. Contrast and legibility over busy backgrounds

- Any text drawn directly over `in_game_bg.webp` / the menu classroom
  photo needs an outline (≥ 6 px for 26 px text, ≥ 12 px for 34 px) or
  a solid panel. Approved overlay style: bold + thick outline, no
  panel.
- Button labels on the gold/dark theme: verify with a device
  screenshot, not hex math. Wood grain and the photo blur vary.
- Disabled state must be visibly different *and* still readable — the
  greyed 待った button should read as "unavailable", not "invisible".
- Piece kanji: 後手 pieces are rotated 180°; make sure the texture
  contrast is identical for both orientations (same asset, so usually
  yes — but check modulate on the rotated path).

## 4. Colour is never the only cue

| Cue                     | Current colour signal        | Needs a second channel      |
|-------------------------|------------------------------|-----------------------------|
| Selected square         | highlight modulate           | border or scale             |
| Legal-move hints        | dot / tint                   | shape (dot) — OK if present |
| Last move from/to       | tint                         | outline or marker           |
| Check (王手)            | red text                     | text itself — OK            |
| Side to move            | status text                  | OK                          |
| 先生モード win-rate      | number                       | OK                          |
| Promotion-eligible move | dialog                       | OK                          |

Red/green pairs are the worst case for deuteranopia; this project's
palette is red/gold/wood, which is safer, but a red highlight on
amber wood is low-saturation-contrast for protanopes. Prefer adding a
border or marker over changing hue.

## 5. Motion

- Board zoom tween (`_refit_board_smooth`), piece slide
  (`BoardView.animate_move`), panel fades. Each should be short
  (≤ 250 ms) and never block input it doesn't need to.
- A "reduce motion" preference is a *decision item*, not something to
  add unilaterally. If proposing it, it belongs in `Settings` next to
  `sound_enabled`, persisted in `prefs.cfg`, and honoured by the three
  sites above by setting duration to 0.

## 6. Feedback redundancy

- Move committed: sound + haptic + visual slide. Haptic currently dead
  (missing VIBRATE permission in `export_presets.cfg`); fix is
  `permissions/vibrate=true`.
- Illegal tap (e.g. 二歩, moving into check): must produce *some*
  visible response — a shake or flash on the square, not just silence.
- AI thinking: 思考中 label (visual). Fine.
- Game over: dialog (visual) + sound. Fine.
- Sound off → every sound-only cue above needs a visual twin.

## 7. Safe area and cutouts

- Every fullscreen scene either uses `SafeAreaLayout.gd` or computes
  the inset itself (`GameController`, `CharacterPicker`). New scenes
  without either are a finding.
- Root-level overlays (anything not under `Layout`) must not anchor to
  the screen top or bottom with fixed fractions. Position relative to
  the board via `_place_above_board()` or offset from
  `Settings.safe_area_insets()`.
- Landscape is locked out? Check `orientation` in `project.godot`; if
  portrait-only, say so in the report so no one audits landscape.

## 8. Screen reader (TalkBack) readiness

Godot 4.7's AccessKit bridge exposes `Control` nodes. What it reads:

- `Button.text`, `Label.text`, `CheckBox.text` — automatic.
- Icon-only `TextureButton` / `Button` with `icon` and empty `text` —
  **nothing**, unless `tooltip_text` or `accessibility_name` is set.
- `TextureRect` portraits — decorative, should be ignored; set
  `mouse_filter = 2` and leave unnamed.
- Board squares — set a name like "７六 歩 先手" when a piece renders,
  "７六 空" when empty, so a TalkBack user can at least browse the
  board. This is a larger feature; list under "needs a decision".
- Focus order follows tree order; `focus_neighbor_*` is unset
  everywhere. Fine for touch, a finding only if the user asks about
  keyboard/D-pad play.

## 9. Language and strings

- All strings are Japanese; the audience is Japanese. Don't propose
  English fallbacks.
- Kanji with uncommon readings in UI (入玉, 千日手, 打ち歩詰め) are
  domain terms the audience knows. Don't add furigana unless asked.
- Error/explanation strings (`"玉が王手にかかっているため宣言できません。"`)
  must be full sentences — they are read aloud by TalkBack verbatim.

## 10. Things that look like findings but aren't

- Piece kanji at ~40 px on a 69 px square: that is the game; the fix
  is zoom (bigger board), which `_compute_board_side` already
  maximises.
- The 投了 button being always-enabled: intentional, resigning must be
  reachable at all times.
- 後手 pieces upside-down: standard Shogi convention; a flip option
  is a design decision, not an a11y defect.
