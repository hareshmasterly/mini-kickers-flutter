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
      await _musicPlayer!.setReleaseMode(ReleaseMode.loop);
      await _musicPlayer!.setVolume(0.45);
      await _musicPlayer!
          .play(AssetSource('${_assetPrefix}stadium_ambient.mp3'));
      _musicPlaying = true;
    } catch (e) {
      if (kDebugMode) debugPrint('AudioHelper: music failed ($e)');
    }
  }

  static Future<void> stopMusic() async {
    if (!_musicPlaying) return;
    try {
      await _musicPlayer?.stop();
    } catch (_) {}
    _musicPlaying = false;
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
    _initialized = false;
  }
}
