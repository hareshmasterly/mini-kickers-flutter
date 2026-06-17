import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:vibration/vibration.dart';

/// Audio + haptic helper.
///
/// Haptic strategy (most reliable possible):
///   • Calls the platform method **directly** (no async closure wrapping —
///     that was deferring iOS haptics outside the gesture window).
///   • On Android, also fires the `vibration` package (50–80 ms pulse) which
///     uses the OS Vibrator service directly. Belt-and-braces — at least one
///     channel always fires even if the other is muted by system settings.
///   • Capability is detected once at startup and cached.
class AudioHelper {
  AudioHelper._();

  // ── Audio player pool ──
  static final List<AudioPlayer> _pool = <AudioPlayer>[];
  static int _poolIndex = 0;
  static const int _poolSize = 6;
  static bool _initialized = false;

  static AudioPlayer? _musicPlayer;
  static bool _musicPlaying = false;
  /// True when [stopMusic] paused the loop (so the next [startMusic]
  /// can resume from the same position rather than restarting the
  /// asset from the beginning — much smoother on rapid toggles).
  static bool _musicPaused = false;
  /// Target volume the fade-in animates toward. Tuned for "soft
  /// background" — quiet enough that commentary + SFX stay foreground.
  static const double _musicTargetVolume = 0.30;
  static const String _assetPrefix = 'sounds/';

  // ── Vibration capability cache ──
  static bool? _hasVibrator;
  static bool? _hasAmplitudeControl;

  /// Probe device for vibration support. Call once at app startup
  /// (we lazy-call from first haptic if not yet probed).
  static Future<void> _probeVibration() async {
    if (_hasVibrator != null) return;
    try {
      _hasVibrator = await Vibration.hasVibrator();
      _hasAmplitudeControl = await Vibration.hasAmplitudeControl();
      if (kDebugMode) {
        debugPrint(
          'AudioHelper: vibrator=$_hasVibrator amplitude=$_hasAmplitudeControl',
        );
      }
    } catch (_) {
      _hasVibrator = false;
      _hasAmplitudeControl = false;
    }
  }

  static void _ensureInit() {
    if (_initialized) return;
    _initialized = true;
    for (int i = 0; i < _poolSize; i++) {
      final AudioPlayer p = AudioPlayer();
      p.setPlayerMode(PlayerMode.lowLatency);
      _pool.add(p);
    }
    // Kick off vibration probe in the background
    unawaited(_probeVibration());
  }

  static Future<void> _playAsset(final String filename) async {
    if (!SettingsService.instance.soundEnabled) return;
    _ensureInit();
    try {
      final AudioPlayer player = _pool[_poolIndex];
      _poolIndex = (_poolIndex + 1) % _poolSize;
      await player.stop();
      await player.play(AssetSource('$_assetPrefix$filename'));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioHelper: missing or unplayable asset $filename ($e)');
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // HAPTICS
  // ──────────────────────────────────────────────────────────────────────

  /// Light tap — UI selections, dice roll start, no-op events.
  static void hapticLight() {
    if (!SettingsService.instance.hapticsEnabled) return;
    _ensureInit();
    // 1) Direct platform call — fire-and-forget, no async wrapping.
    HapticFeedback.lightImpact();
    // 2) Android vibrate fallback (very short pulse) — guarantees at least
    //    one channel fires on devices where Flutter haptic might be muted.
    if (Platform.isAndroid) _vibratePulse(40, amplitude: 80);
  }

  /// Medium impact — coin land, score events, dice settle.
  static void hapticMedium() {
    if (!SettingsService.instance.hapticsEnabled) return;
    _ensureInit();
    HapticFeedback.mediumImpact();
    if (Platform.isAndroid) _vibratePulse(70, amplitude: 160);
  }

  /// Heavy thump — goals, ball control, big moments.
  static void hapticHeavy() {
    if (!SettingsService.instance.hapticsEnabled) return;
    _ensureInit();
    HapticFeedback.heavyImpact();
    if (Platform.isAndroid) _vibratePulse(120, amplitude: 240);
  }

  /// Selection tick — best UX feel for picking from a list.
  static void hapticSelection() {
    if (!SettingsService.instance.hapticsEnabled) return;
    _ensureInit();
    if (Platform.isIOS) {
      HapticFeedback.selectionClick();
    } else {
      // Android selectionClick is barely perceptible — use lightImpact
      // PLUS a vibration pulse so the user definitely feels it.
      HapticFeedback.lightImpact();
      _vibratePulse(30, amplitude: 90);
    }
  }

  /// Double-tap test pattern (Settings → "Tap to test").
  static void testHaptic() {
    if (!SettingsService.instance.hapticsEnabled) return;
    _ensureInit();
    hapticHeavy();
    Timer(const Duration(milliseconds: 180), hapticLight);
  }

  static void _vibratePulse(final int ms, {required final int amplitude}) {
    if (_hasVibrator == false) return;
    try {
      if (_hasAmplitudeControl == true) {
        Vibration.vibrate(duration: ms, amplitude: amplitude.clamp(1, 255));
      } else {
        Vibration.vibrate(duration: ms);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('AudioHelper: vibrate failed ($e)');
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // PUBLIC SFX TRIGGERS — each fires haptic + audio in parallel
  // ──────────────────────────────────────────────────────────────────────

  static Future<void> diceRoll() async {
    hapticLight();
    await _playAsset('dice_roll.mp3');
  }

  static Future<void> diceResult() async {
    hapticMedium();
    await _playAsset('dice_land.mp3');
  }

  static Future<void> tokenMove() async {
    hapticSelection();
    await _playAsset('move.mp3');
  }

  static Future<void> ballControl() async {
    hapticHeavy();
    await _playAsset('ball_control.mp3');
  }

  static Future<void> ballMove() async {
    hapticSelection();
    await _playAsset('kick.mp3');
  }

  static Future<void> goal() async {
    hapticHeavy();
    await _playAsset('goal.mp3');
  }

  static Future<void> turnSwitch() async {
    hapticSelection();
    await _playAsset('turn_switch.mp3');
  }

  static Future<void> noMoves() async {
    hapticLight();
    await _playAsset('no_moves.mp3');
  }

  static Future<void> select() async {
    hapticSelection();
    await _playAsset('select.mp3');
  }

  static Future<void> coinFlip() async {
    hapticMedium();
    await _playAsset('coin_flip.mp3');
  }

  static Future<void> whistle() async {
    hapticHeavy();
    await _playAsset('whistle.mp3');
  }

  // ──────────────────────────────────────────────────────────────────────
  // BACKGROUND MUSIC
  // ──────────────────────────────────────────────────────────────────────

  static Future<void> startMusic() async {
    if (_musicPlaying) return;
    if (!SettingsService.instance.musicEnabled) return;
    _musicPlayer ??= AudioPlayer();
    try {
      // Audio context — controls how this player interacts with the
      // OS audio system. `playback` (NOT `ambient`) plays even when
      // the iOS mute switch is on. The user expectation when they
      // toggle "Background Music ON" is that it plays unconditionally;
      // requiring them to also flip the side switch to hear it is
      // confusing. `mixWithOthers` keeps Spotify / podcasts running
      // alongside.
      await _musicPlayer!.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const <AVAudioSessionOptions>{
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
          android: const AudioContextAndroid(
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );
      await _musicPlayer!.setReleaseMode(ReleaseMode.loop);
      // Set volume directly to target. Earlier we tried fade-in from
      // 0 → target via an unawaited timer loop, but on some devices
      // the player ended up "stuck silent" if the audio session took
      // an extra beat to activate before the fade ticks ran. Direct
      // assignment is rock-solid and 0.30 is already soft enough for
      // a background loop that nobody will mistake for a startle.
      await _musicPlayer!.setVolume(_musicTargetVolume);
      if (_musicPaused) {
        await _musicPlayer!.resume();
      } else {
        await _musicPlayer!
            .play(AssetSource('${_assetPrefix}background_music.mp3'));
      }
      _musicPlaying = true;
      _musicPaused = false;
      if (kDebugMode) debugPrint('AudioHelper: music started');
    } catch (e) {
      if (kDebugMode) debugPrint('AudioHelper: music failed ($e)');
    }
  }

  static Future<void> stopMusic() async {
    if (!_musicPlaying) return;
    _musicPlaying = false;
    // Pause (not stop) so the next startMusic() resumes from the same
    // position — avoids the "track restarts from the top" feel on
    // every toggle. No fade-out: a hard pause is responsive and
    // matches the user expectation that "OFF means silent NOW".
    try {
      await _musicPlayer?.pause();
      _musicPaused = true;
    } catch (_) {}
  }

  static Future<void> setMusicEnabled({required final bool enabled}) async {
    if (enabled) {
      await startMusic();
    } else {
      await stopMusic();
    }
  }

  static Future<void> disposeAll() async {
    for (final AudioPlayer p in _pool) {
      await p.dispose();
    }
    _pool.clear();
    await _musicPlayer?.dispose();
    _musicPlayer = null;
    _musicPlaying = false;
    _musicPaused = false;
    _initialized = false;
  }
}
