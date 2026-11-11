# TODOs — making the game more interesting & charming

Ideas backlog, written 2026-11-09. Nothing here is committed scope; move
an item into [`ROADMAP.md`](../ROADMAP.md) when it is picked up.

The theme behind most of these: the rules, AI and polish are solid, but
the school-club premise is only skin-deep. The eight characters have
portraits and bios, yet once a game starts they are just an avatar and a
strength dial.

**Selected for implementation (2026-11-09): 1, 2, 4, 7, 8, 9.** They
are marked ★ below. Done so far: 1, 4, 7, 8, 9. Still to do: 2.
Items 3, 5, 6, 10 and 11 stay in the backlog.

## Make the characters come alive

- [x] **★ 1. In-game reactions.** Done 2026-11-09 — see the Phase 7
  entry in `ROADMAP.md` and "Opponent expressions" in
  `docs/architecture.md`. All eight characters have `thinking / happy /
  worried / victory / defeat` portraits and the opponent strip swaps
  them from the AI's search-backed mood. Left for later: tune the
  62 % / 38 % thresholds by feel, and the variants sit a hair off the
  neutral portraits' framing (visible as a slight jump in the
  cross-fade).
- [ ] **★ 2. Short speech bubbles.** A few lines per character for game
  start, check, losing a major piece, winning and losing — アリス is
  cold, すず is cheerful, テリー mixes in English. New characters must go
  through `tools/build_font_subsets.py`.
- [ ] **3. Per-character playing style.** The opening book is one shared
  weighted table. Give each character a bias (e.g. 明 always plays
  振り飛車, 加藤師範 plays classical 矢倉) so they differ in style as
  well as strength.

## Give the player a reason to come back

- [x] **★ 4. Win/loss record on each character's profile.** Done
  2026-11-11 — the picker's detail panel shows あなたの戦績 per character,
  stored in `prefs.cfg`. Rescoped from a club ranking with "beaten"
  stamps on the picker cards.
- [ ] **5. Unlockables tied to wins.** Beating a character unlocks a
  second bio paragraph, a victory portrait, or a short club-room scene.
  Rewards progress without a full story mode.
- [ ] **6. 駒落ち (handicap games).** Natural for a school club: the
  teachers offer 二枚落ち or 飛車落ち to beginners. Caveat: Bonanza was
  trained on even games, so its play in handicap positions may be weak
  or odd — test before committing.

## Deepen the shogi itself

- [x] **★ 7. 詰将棋 (mate problems) as "club homework".** Done
  2026-11-10 — 160 engine-mined 1 / 3 / 5 手詰 problems, solver-judged,
  with 今日の一問 and a hint button. See `ROADMAP.md` Phase 7.
- [x] **★ 8. Post-game comment from 加藤先生.** Done 2026-11-10 — the
  対局終了 dialog names the player's costliest move and offers 検討.
- [x] **★ 9. Evaluation graph in 棋譜検討.** Done 2026-11-10 —
  形勢グラフ under the analysis label, tap to jump.

## Atmosphere

- [ ] **10. Ambient sound or BGM.** Only move effects exist today. A
  quiet club-room loop (clock, distant school yard, soft koto) with a
  settings toggle.
- [ ] **11. Time-of-day or seasonal backgrounds.** Afternoon sun,
  sunset, cherry blossoms in April, driven by the device clock. Costs
  APK size: each background is another image.

## Notes

- Items 1, 5 and 11 need new AI-generated art in a consistent style.
  If that is too much, 2 and 4 alone still deliver most of the charm.
