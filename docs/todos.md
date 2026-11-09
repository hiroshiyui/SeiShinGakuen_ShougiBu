# TODOs — making the game more interesting & charming

Ideas backlog, written 2026-11-09. Nothing here is committed scope; move
an item into [`ROADMAP.md`](../ROADMAP.md) when it is picked up.

The theme behind most of these: the rules, AI and polish are solid, but
the school-club premise is only skin-deep. The eight characters have
portraits and bios, yet once a game starts they are just an avatar and a
strength dial.

**Selected for implementation (2026-11-09): 1, 2, 4, 7, 8, 9.** They
are marked ★ below. Planned order: 1 → 4 → 2 → 9 → 8 → 7 (cheapest and
most visible first; 8 builds on 9's per-ply analysis; 7 is the largest
and needs a puzzle source). Items 3, 5, 6, 10 and 11 stay in the
backlog.

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

- [ ] **★ 4. Win/loss record and club ranking (部内ランキング).** Nothing
  tracks results today. Per-character records in `prefs.cfg`, plus a
  "beaten" stamp on the picker card, turn eight levels into a ladder.
- [ ] **5. Unlockables tied to wins.** Beating a character unlocks a
  second bio paragraph, a victory portrait, or a short club-room scene.
  Rewards progress without a full story mode.
- [ ] **6. 駒落ち (handicap games).** Natural for a school club: the
  teachers offer 二枚落ち or 飛車落ち to beginners. Caveat: Bonanza was
  trained on even games, so its play in handicap positions may be weak
  or odd — test before committing.

## Deepen the shogi itself

- [ ] **★ 7. 詰将棋 (mate puzzles) as "club homework".** A daily puzzle
  from a bundled set gives a two-minute session for when a full game is
  too long. The rules engine can already validate solutions.
- [ ] **★ 8. Post-game comment from 加藤先生.** The reviewer already
  classifies moves as 好手 / 疑問手 / 悪手. Surface the single biggest
  turning point on the game-over dialog ("42手目が惜しかったですね")
  with a button into the reviewer.
- [ ] **★ 9. Evaluation graph in 棋譜検討.** 先手勝率 is computed for
  every ply; plotting it as a line makes the story of a game visible at
  a glance.

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
