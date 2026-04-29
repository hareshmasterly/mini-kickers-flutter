# VS AI — Feature Implementation Spec

> Single-player mode where one human plays against a heuristic-based AI opponent.
> Target: ship in v1.1, ~1 week of work, alongside the v1.0 ads launch.

---

## 1. Overview

The home screen already has a "VS AI" card (currently `locked: true` in
`lib/views/home/home_screen.dart:335`). This spec covers everything needed to
unlock and ship that mode.

**Core experience**: tap "VS AI" → pick a difficulty (Easy / Medium / Hard) →
coin toss → match against an AI opponent that plays as Blue.

**Design philosophy**: heuristic scoring with tunable randomness. Not minimax,
not ML. Easy to reason about, easy to tune, fast to ship.

---

## 2. Decisions Locked In

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Which team is the AI? | **Always Blue** (player is always Red) | Simplest. No "choose your team" friction. |
| 2 | How many difficulty tiers? | **3** — Easy / Medium / Hard | Maps cleanly to age bands 5-7 / 8-10 / 10+. |
| 3 | When does difficulty picker appear? | **Every "VS AI" tap** | Lets two siblings pick different difficulties match-to-match without going to Settings. |
| 4 | Does difficulty persist? | **Yes** (last pick pre-selects) | Convenience for solo players. |
| 5 | Does game mode persist? | **No** — per-session | Mode is set fresh from the home card each time. |
| 6 | Show "AI thinking..." indicator? | **Yes**, with 700-1100ms delay | Robotic snap feels bad; deliberate pause feels intentional. |
| 7 | Can user rename Blue when it's the AI? | **Yes** (default to "AI" or "COMPUTER") | Fun customization — kids enjoy "DAD vs ROBO". |
| 8 | Remote-tunable difficulty weights? | **Yes**, via Firestore `app_settings` | Lets you rebalance post-launch without an app update. |

---

## 3. AI Architecture

### 3.1 High-level flow

1. `AiController` subscribes to `GameBloc` state changes.
2. When `mode == vsAi` AND `turn == Team.blue` AND `phase == roll`:
   - Wait `think_delay_ms`.
   - Fire `RollDiceEvent`.
3. After `DiceRolledEvent` (animation complete), evaluate every legal move:
   - Score each candidate with the heuristic formula.
   - Add randomness (the `random_factor` knob — see §3.4).
   - Pick the highest-scoring move.
   - Fire `SelectTokenEvent` → `MoveToEvent`.
4. If the AI lands on the ball, the bloc auto-rolls again. AI repeats step 3
   for ball movement (different scoring formula — see §3.3).

### 3.2 Token-move scoring formula

```
score = w_chase_ball       · (−distance_from_token_to_ball)
      + w_push_to_goal     · (−distance_from_ball_to_my_target_goal)
      + w_block_opponent   · (does_this_block_opponent ? 1 : 0)
      + w_capture_ball     · (lands_on_ball ? 10 : 0)
      + random_noise(random_factor, max_score)
```

### 3.3 Ball-move scoring formula (when AI has possession)

```
score = w_push_to_goal     · (−distance_from_ball_to_opponent_goal)
      + w_score_goal       · (lands_in_goal ? 1 : 0)
      + w_avoid_capture    · (will_opponent_capture_next_turn ? −1 : 0)
      + random_noise(random_factor, max_score)
```

### 3.4 The `random_factor` (the difficulty dial)

This is the single most important tuning knob. It's a noise multiplier added
to each move's score before picking the maximum.

For every legal move, the AI calculates a base score from the heuristic. Then
it adds noise: `noise = random(−1, +1) × random_factor × max_observed_score`.
The move with the highest `score + noise` wins.

**What different values feel like:**

| `random_factor` | Picks the best move | Picks a mediocre move | Picks a bad move | Feel |
|---|---|---|---|---|
| `0.0` | 100% | 0% | 0% | Robot. Always optimal. Brutal. |
| `0.05` (Hard) | ~95% | ~3% | ~2% | Strong, occasional small slip. |
| `0.2` (Medium) | ~80% | ~12% | ~8% | Smart but beatable. |
| `0.6` (Easy) | ~50% | ~25% | ~25% | Often makes weird moves — kid-friendly. |
| `1.0` | ~33% | ~33% | ~33% | Pure random. AI ignores its brain. |

**Why this is the difficulty lever:** a 5-year-old needs to sometimes win
against Easy. With `random_factor = 0.6`, the AI regularly picks suboptimal
moves — those "huh, why did the AI do that?" moments — and the kid's smart
moves can outscore it. Without randomness, even Easy beats any 5-year-old
because the heuristic always picks the right move.

### 3.5 Hard-tier 1-ply lookahead

When `ai_hard_use_lookahead == true`, the Hard tier additionally considers:
"what's the opponent's best response to this move?" — and picks the move
where the opponent's best response hurts them least.

Cheap to compute (only N×N moves to evaluate, N ≤ ~9 here). Big quality jump.
Can be flipped off remotely if Hard feels too brutal.

---

## 4. Difficulty Tiers — Defaults

| Tier | random_factor | think_delay_ms | use_lookahead | Designed for | Expected adult win rate |
|---|---|---|---|---|---|
| **Easy** | 0.6 | 700 | No | Kids 5-7 | Adult wins ~80% |
| **Medium** | 0.2 | 900 | No | Kids 8-10 | ~50/50 |
| **Hard** | 0.05 | 1100 | Yes | Kids 10+ and adults | Adult wins ~30% |

Base scoring weights (shared across all tiers):

| Weight | Default | What it shapes |
|---|---|---|
| `w_chase_ball` | 1.5 | How strongly tokens move toward the ball |
| `w_push_to_goal` | 1.0 | How strongly the AI advances the ball |
| `w_block_opponent` | 0.8 | Defensive value of blocking the opponent |
| `w_capture_ball` | 10.0 | Bonus when a token can land on the ball |
| `w_score_goal` | 1000.0 | Massive bonus when a ball move scores |
| `w_avoid_capture` | 0.5 | Penalty for ball moves that let the opponent capture |

---

## 5. Firestore Schema (`app_settings` document)

All AI fields are **optional** — the app falls back to hardcoded defaults if
absent. Add only the fields you want to tune.

### 5.1 Recommended initial setup (8 fields)

Adds full difficulty + UX tuning without exposing the deeper weights.

```
ai_default_difficulty: "medium"
ai_easy_random_factor: 0.6
ai_medium_random_factor: 0.2
ai_hard_random_factor: 0.05
ai_easy_think_delay_ms: 700
ai_medium_think_delay_ms: 900
ai_hard_think_delay_ms: 1100
ai_hard_use_lookahead: true
```

### 5.2 Full field reference

#### Difficulty defaults

| Field | Type | Default | Purpose |
|---|---|---|---|
| `ai_default_difficulty` | string | `"medium"` | Pre-selected option in the difficulty picker. One of `easy` / `medium` / `hard`. |

#### Per-tier random factor (0.0–1.0)

Higher = easier/more chaotic. Lower = harder/more deterministic.
**Biggest lever for tuning post-launch.**

| Field | Type | Default |
|---|---|---|
| `ai_easy_random_factor` | number | `0.6` |
| `ai_medium_random_factor` | number | `0.2` |
| `ai_hard_random_factor` | number | `0.05` |

#### Per-tier "thinking" delay (ms)

How long "BLUE is thinking…" shows before the AI acts. Pure UX feel.

| Field | Type | Default |
|---|---|---|
| `ai_easy_think_delay_ms` | number | `700` |
| `ai_medium_think_delay_ms` | number | `900` |
| `ai_hard_think_delay_ms` | number | `1100` |

#### Hard-tier toggle

| Field | Type | Default | Purpose |
|---|---|---|---|
| `ai_hard_use_lookahead` | bool | `true` | Whether Hard does 1-ply opponent lookahead. Flip off if Hard feels brutal. |

#### Base scoring weights (advanced — usually leave alone)

Only tune if a specific behavior feels wrong.

| Field | Type | Default | Purpose |
|---|---|---|---|
| `ai_weight_chase_ball` | number | `1.5` | Tokens moving toward the ball |
| `ai_weight_push_to_goal` | number | `1.0` | Pushing ball toward opponent's goal |
| `ai_weight_block_opponent` | number | `0.8` | Defensive blocking |
| `ai_weight_capture_ball` | number | `10.0` | Bonus for capturing ball |
| `ai_weight_score_goal` | number | `1000.0` | Bonus for scoring |
| `ai_weight_avoid_capture` | number | `0.5` | Penalty for losing possession next turn |

### 5.3 Tuning playbook (post-launch)

| Symptom | Knob to turn |
|---|---|
| "My kid never wins on Easy" | Bump `ai_easy_random_factor` 0.6 → 0.75 |
| "Medium feels too hard" | Bump `ai_medium_random_factor` 0.2 → 0.3 |
| "Hard isn't challenging" | Drop `ai_hard_random_factor` to 0.0; keep lookahead on |
| "Hard is unbeatable" | Bump `ai_hard_random_factor` to 0.1, OR set `ai_hard_use_lookahead: false` |
| "AI ignores the ball" | Bump `ai_weight_chase_ball` 1.5 → 2.5 |
| "AI never plays defense" | Bump `ai_weight_block_opponent` 0.8 → 1.5 |
| "AI feels too snappy" | Bump all `_think_delay_ms` by 200-300 |

---

## 6. UI/UX Flows

### 6.1 Mode entry

```
Home screen
  └─ tap "VS AI" card (currently locked — unlock for v1.1)
     └─ DifficultyPickerDialog (always shown — every tap)
        ├─ Easy   "Just learning? Start here."   🌱
        ├─ Medium "A fair fight."                ⚖️
        └─ Hard   "Bring your A-game."           🔥
        + Cancel / Start
     └─ on Start: persist difficulty, push /game with mode=vsAi
        └─ Coin toss (AI plays through if it wins)
           └─ Match
```

### 6.2 In-game cues (AI mode only)

- **Side panel**: when `turn == Blue`, replace human prompts ("Tap a token",
  "Roll dice") with **"BLUE IS THINKING…"** + 3-dot pulse animation.
- **Coin toss strip**: Blue chip shows label like **"BLUE (AI)"** + small 🤖
  icon. Still tappable to rename if user wants to.
- **Restart / Exit**: same as today; `AiController` disposes cleanly.

### 6.3 Settings screen addition

New tile under the GAMEPLAY section, mirroring the existing
`_MatchDurationTile`:

```
🤖 AI Difficulty
   ( Easy ) ( Medium ✓ ) ( Hard )
```

This lets returning solo players change difficulty without going through
the home screen flow.

---

## 7. Code Structure

### 7.1 New files

| Path | Purpose | ~LOC |
|---|---|---|
| `lib/ai/ai_player.dart` | Pure scoring logic — input: `GameState`, output: best `Pos`. Stateless, easily unit-testable. | ~250 |
| `lib/ai/ai_controller.dart` | Subscribes to `GameBloc`, fires events on AI's turn. Owns the "thinking" delay timer. | ~120 |
| `lib/ai/ai_config.dart` | Reads tuning knobs from `SettingsService` with hardcoded defaults. | ~80 |
| `lib/views/home/widget/difficulty_picker_dialog.dart` | 3-card picker dialog matching the team-setup dialog visual language. | ~180 |
| `lib/views/settings/widget/ai_difficulty_tile.dart` | Settings tile mirroring `_MatchDurationTile`. | ~80 |
| `test/ai/ai_player_test.dart` | Deterministic move-selection tests with seeded random. | ~150 |

### 7.2 Modified files

| Path | Change |
|---|---|
| `lib/data/models/game_models.dart` | Add `enum GameMode { vsHuman, vsAi }` and `enum AiDifficulty { easy, medium, hard }` |
| `lib/data/services/settings_service.dart` | Add `aiDifficulty` getter/setter (persisted), `gameMode` getter/setter (in-memory only), and new AI config getters reading from `_remote` |
| `lib/data/models/remote_app_settings.dart` | Parse the 13 new `ai_*` fields from Firestore |
| `lib/views/home/home_screen.dart` | Remove `locked: true` from VS AI card; tap → difficulty picker → start game |
| `lib/views/game/game_screen.dart` | Instantiate `AiController` when `mode == vsAi`; dispose on leave |
| `lib/views/game/widget/side_panel_widget.dart` | Show "BLUE is thinking…" pulse when AI is acting |
| `lib/views/game/widget/team_setup_strip.dart` | If AI mode, label Blue chip "BLUE (AI)" with a 🤖 icon |
| `lib/views/settings/settings_screen.dart` | Insert new `AiDifficultyTile` under GAMEPLAY section |

---

## 8. Settings & Persistence

### 8.1 New SharedPreferences keys

```dart
static const String _kAiDifficulty = 'pref.aiDifficulty';
static const String _kAiDifficultyUserSet = 'pref.aiDifficulty.userSet';
```

### 8.2 In-memory state (not persisted)

```dart
GameMode _gameMode = GameMode.vsHuman;  // Reset to vsHuman on app start
```

### 8.3 New SettingsService getters (sketch)

```dart
GameMode get gameMode => _gameMode;
set gameMode(GameMode m) { _gameMode = m; notifyListeners(); }

AiDifficulty get aiDifficulty {
  if (_aiDifficultyUserSet) return _aiDifficulty;
  return _parseAiDifficulty(_remote?.aiDefaultDifficulty) ?? AiDifficulty.medium;
}

double get aiRandomFactor {
  switch (aiDifficulty) {
    case AiDifficulty.easy:   return _remote?.aiEasyRandomFactor   ?? 0.6;
    case AiDifficulty.medium: return _remote?.aiMediumRandomFactor ?? 0.2;
    case AiDifficulty.hard:   return _remote?.aiHardRandomFactor   ?? 0.05;
  }
}

int get aiThinkDelayMs { /* same shape, 3 cases */ }
bool get aiUseLookahead =>
    aiDifficulty == AiDifficulty.hard &&
    (_remote?.aiHardUseLookahead ?? true);

double get aiWeightChaseBall    => _remote?.aiWeightChaseBall    ?? 1.5;
double get aiWeightPushToGoal   => _remote?.aiWeightPushToGoal   ?? 1.0;
double get aiWeightBlockOpponent => _remote?.aiWeightBlockOpponent ?? 0.8;
double get aiWeightCaptureBall  => _remote?.aiWeightCaptureBall  ?? 10.0;
double get aiWeightScoreGoal    => _remote?.aiWeightScoreGoal    ?? 1000.0;
double get aiWeightAvoidCapture => _remote?.aiWeightAvoidCapture ?? 0.5;
```

---

## 9. Edge Cases & Risks

| Risk | Handling |
|---|---|
| AI rolls before dice animation finishes | `AiController` listens for `DiceRolledEvent`, not `RollDiceEvent` |
| User exits mid-AI-turn | `AiController.dispose()` cancels timers + bloc subscription |
| Restart event during AI turn | Same disposal path; AI re-subscribes after reset |
| Interstitial fires during AI turn | AdManager is async; AI listener re-checks `phase` after each event |
| AI has no legal move | Bloc already auto-skips; AI controller observes and waits |
| Haptics firing for AI moves | AI fires events directly without `AudioHelper.select()` — no buzzes from AI actions |
| Commentary mentioning AI | Reuse existing team-name commentary; "BLUE rolls a 4" → "ROBO rolls a 4" if user renamed |
| AI stuck (defensive) | Hard timeout in `AiController` (3s) to bail and skip turn |
| User changes difficulty mid-match | Setting takes effect on the AI's next turn; mid-turn moves use the previous setting |

---

## 10. Testing Plan

### 10.1 Unit tests (`test/ai/ai_player_test.dart`)

Feed crafted `GameState` snapshots, assert AI picks the obvious move:

- Ball is on Blue's goal line, Blue has possession → AI picks the goal cell
- Red token is one move from scoring → AI picks the blocking move (when
  `block_opponent` weight is significant)
- All else equal → AI moves toward the ball
- With `random_factor = 0`, AI is fully deterministic given a seed

Use seeded random so tests are reproducible.

### 10.2 Bot-vs-bot smoke test

Run Medium vs Hard for 100 simulated games. Hard should win ~70%. If not,
weights need tuning.

### 10.3 Manual playtest (Day 5 of timeline)

- **Easy**: a 5-7 yo should win at least 1 in 3 matches
- **Medium**: an attentive adult should be ~50/50
- **Hard**: an adult playing seriously should lose ~70%

Iterate `random_factor` and base weights until tiers feel distinct.

---

## 11. 7-Day Timeline

| Day | Work | Output |
|---|---|---|
| 1 | Add `GameMode` + `AiDifficulty` enums. Settings keys. Firestore parser for the 13 `ai_*` fields. Difficulty picker dialog skeleton. | Scaffolding compiles; picker shows 3 cards. |
| 2 | Implement `AiPlayer` heuristic scoring (token moves). Unit tests with mocked states. | Token AI picks reasonable moves in tests. |
| 3 | Implement ball-move scoring + 1-ply lookahead for Hard. Wire `AiController` to bloc. | AI plays a full match end-to-end. |
| 4 | UI polish: unlock home card, picker dialog visual final, "AI thinking" indicator, Settings tile, Blue-as-AI labeling. | All UX flows feel finished. |
| 5 | **Playtest day** — tune weights for each tier. Get a kid to test Easy. Get a colleague to test Hard. | Difficulty tiers feel right. |
| 6 | Edge cases: restart, exit, interstitial during AI turn. Regression test VS Human mode. | No regressions. AI handles all transitions. |
| 7 | Buffer for bugs / final polish. Last chance to back out the feature if any tier feels broken. | Ready to ship in v1.1. |

---

## 12. Future Enhancements (post v1.1)

Not in scope for the initial launch, but candidates for v1.2+:

- **Adaptive difficulty**: if player wins 3 in a row, auto-bump up. Auto-drop
  on losing streaks. Requires win-streak persistence.
- **Confidence commentary**: "BLUE seems unsure" / "BLUE looks dangerous"
  based on recent move scores. Adds personality.
- **AI cosmetics**: distinct robot avatar / different commentary tone for
  the AI team.
- **Tournament mode**: 3 matches, best of 3 vs AI.
- **Daily challenge**: a fixed seed + AI difficulty, leaderboards via
  Firestore.

---

## 13. Open Questions / Owner Decisions Needed

None at spec time — all 8 decisions in §2 are locked. Add new questions
here as they come up during implementation.

---

## 14. Implementation Status

- [x] Day 1 — Scaffolding (enums, settings, picker skeleton, Firestore parser)
- [x] Day 2 — Token-move scoring + unit tests
- [x] Day 3 — Ball-move scoring + lookahead + AiController
- [x] Day 4 — UI polish (home card, picker, indicator, settings tile, labels)
- [ ] Day 5 — Playtest + tuning ⚠️ **next: needs a kid + an adult playing real matches**
- [x] Day 6 — Edge cases (restart / exit / ad mid-turn handled in AiController)
- [ ] Day 7 — Buffer / polish (post-playtest)
