# Sound Assets

Drop these files in this directory. The app loads them via `AudioHelper`
(see `lib/utils/audio_helper.dart`). Missing files fall back to haptic-only.

| File | Length | Suggested vibe |
|------|--------|----------------|
| `dice_roll.mp3` | ~1 sec | Plastic dice rattle / shake |
| `dice_land.mp3` | ~0.3 sec | Crisp dice settle on table |
| `kick.mp3` | ~0.3 sec | Football kick punt |
| `select.mp3` | ~0.1 sec | Clean UI tap |
| `move.mp3` | ~0.2 sec | Soft step / chess piece slide |
| `ball_control.mp3` | ~0.4 sec | Whoosh + brief crowd "ooh" |
| `goal.mp3` | ~2 sec | Crowd cheer + ref whistle |
| `whistle.mp3` | ~0.6 sec | Single ref whistle blast |
| `coin_flip.mp3` | ~1 sec | Coin spin + landing chime |
| `turn_switch.mp3` | ~0.3 sec | Subtle chime / pop |
| `no_moves.mp3` | ~0.6 sec | Sad trombone / blocked buzz |

## Free sources (commercial-OK)

- **Freesound.org** — search "dice roll", "stadium cheer", "whistle" — most CC0
- **Mixkit.co/free-sound-effects/sport/** — pre-categorised sport SFX
- **Zapsplat.com** — large library (free with attribution)
- **Pixabay** — sound effects section, royalty-free

## Format notes

- MP3 recommended (smallest, plays everywhere)
- Mono is fine for SFX (saves ~50% size)
- Keep individual files under ~50 KB so the bundle stays light
- 44.1 kHz / 128 kbps is plenty for game SFX

## Testing

After dropping files in, no rebuild config needed — `flutter run` will pick
them up because `pubspec.yaml` already includes `assets/sounds/`. If a file
is malformed, you'll see a debug log: `AudioHelper: missing or unplayable
asset <name>` and the haptic fallback still fires.
