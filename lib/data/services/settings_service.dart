import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:mini_kickers/data/models/ai_difficulty_option.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/models/remote_app_settings.dart';
import 'package:mini_kickers/data/models/team_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent user settings.
///
/// Every preference resolves through three layers, in order:
///   1. **User override** — the value the user explicitly set in-app.
///      Tracked by a per-key `*.userSet` boolean in [SharedPreferences] so
///      we can distinguish "user picked this" from "default happened to be
///      this".
///   2. **Remote default** — the value fetched from the Firestore
///      `app_settings` collection on app start (cached locally so the app
///      works offline). When a user has not overridden a value, they
///      always pick up the latest remote default at next launch.
///   3. **Hardcoded fallback** — the values baked into the app
///      ([_fallbackMatchSeconds], [TeamPalettes.all], etc.). Used on a
///      brand-new install with no network and no cache.
///
/// Setters always promote a setting to "user override" — once a user has
/// chosen a value, remote defaults stop affecting them for that key.
class SettingsService extends ChangeNotifier {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  // ── Pref keys ─────────────────────────────────────────────────────────
  static const String _kSound = 'pref.soundEnabled';
  static const String _kMusic = 'pref.musicEnabled';
  static const String _kHaptics = 'pref.hapticsEnabled';
  static const String _kCommentary = 'pref.commentaryEnabled';
  static const String _kMatchSeconds = 'pref.matchSeconds';
  static const String _kPalette = 'pref.paletteId';
  static const String _kRedName = 'pref.redName';
  static const String _kBlueName = 'pref.blueName';
  static const String _kAiDifficulty = 'pref.aiDifficulty';

  // "User override" flags — distinguishes an explicit user choice from a
  // value that just happened to be stored. Without these, every user would
  // be permanently locked to the first remote default they ever saw.
  static const String _kMatchSecondsUserSet = 'pref.matchSeconds.userSet';
  static const String _kPaletteUserSet = 'pref.paletteId.userSet';
  static const String _kRedNameUserSet = 'pref.redName.userSet';
  static const String _kBlueNameUserSet = 'pref.blueName.userSet';
  static const String _kAiDifficultyUserSet = 'pref.aiDifficulty.userSet';

  /// Cached JSON of the last successful Firestore `app_settings` document.
  static const String _kRemoteCache = 'pref.remoteSettings.cache';

  // ── Hardcoded fallbacks (only used if both override and remote miss) ──
  static const int _fallbackMatchSeconds = 900;
  static const String _fallbackRedName = 'RED';
  static const String _fallbackBlueName = 'BLUE';

  SharedPreferences? _prefs;

  // Local user-override storage.
  bool _soundEnabled = true;
  bool _musicEnabled = false;
  bool _hapticsEnabled = true;
  bool _commentaryEnabled = true;

  int _matchSeconds = _fallbackMatchSeconds;
  bool _matchSecondsUserSet = false;

  String _paletteId = TeamPalettes.classic.id;
  bool _paletteIdUserSet = false;

  String _redName = _fallbackRedName;
  bool _redNameUserSet = false;

  String _blueName = _fallbackBlueName;
  bool _blueNameUserSet = false;

  AiDifficulty _aiDifficulty = AiDifficulty.medium;
  bool _aiDifficultyUserSet = false;

  /// Per-match game mode — **not** persisted across launches. The home
  /// screen sets this to [GameMode.vsAi] when the user picks the VS AI
  /// card and back to [GameMode.vsHuman] otherwise. We deliberately
  /// don't save it: every match is a fresh choice from the home screen.
  GameMode _gameMode = GameMode.vsHuman;

  RemoteAppSettings? _remote;

  // ── Getters: audio / haptics (no remote layer) ────────────────────────
  bool get soundEnabled => _soundEnabled;
  bool get musicEnabled => _musicEnabled;
  bool get hapticsEnabled => _hapticsEnabled;
  bool get commentaryEnabled => _commentaryEnabled;

  // ── Getters: layered (override → remote → fallback) ───────────────────

  /// Active match duration in seconds.
  ///
  /// Resolution:
  ///   1. If the user has a saved pick **and** that value is still in
  ///      [availableMatchDurations], use it.
  ///   2. Otherwise, use the remote `default_game_duration`.
  ///   3. Otherwise, hardcoded fallback.
  ///
  /// The "still offered" check means an admin can drop a duration from
  /// the Firestore `game_durations` array and any user who had picked
  /// that value silently rolls back to the default — without losing
  /// their pref permanently. If the value reappears in Firestore later,
  /// their override comes back.
  int get matchSeconds {
    if (_matchSecondsUserSet) {
      final bool stillOffered = availableMatchDurations.any(
        (final ({int seconds, String label}) d) => d.seconds == _matchSeconds,
      );
      if (stillOffered) return _matchSeconds;
    }
    return _remote?.defaultGameDuration ?? _fallbackMatchSeconds;
  }

  /// Match-duration options shown in the Settings picker. Sourced from
  /// the remote `game_durations` array if non-empty, otherwise a
  /// hardcoded fallback. Labels are generated from the second value
  /// (clean minute multiples become "5 MIN", "10 MIN", etc.; non-minute
  /// values fall back to a "Ns" / "Nm Ns" form).
  List<({int seconds, String label})> get availableMatchDurations {
    final List<int> remote = _remote?.gameDurations ?? const <int>[];
    if (remote.isEmpty) return _fallbackMatchDurations;
    return remote
        .map((final int s) => (seconds: s, label: _durationLabel(s)))
        .toList();
  }

  static String _durationLabel(final int seconds) {
    if (seconds <= 0) return '0';
    if (seconds < 60) return '${seconds}s';
    if (seconds % 60 == 0) return '${seconds ~/ 60} MIN';
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    return '${m}m ${s}s';
  }

  String get redName {
    if (_redNameUserSet) return _redName;
    return _remote?.player1Name ?? _fallbackRedName;
  }

  String get blueName {
    if (_blueNameUserSet) return _blueName;
    return _remote?.player2Name ?? _fallbackBlueName;
  }

  /// Fixed display label for the AI opponent. v1 ships as a constant;
  /// can be promoted to a remote-tunable Firestore field in the
  /// future if needed (see [docs/vs_ai_feature_spec.md] §12).
  static const String _aiDisplayName = 'AI';

  /// In VS AI matches Blue is the bot — show a single fixed label so
  /// the user isn't presented with a confusing editable name for an
  /// opponent they can't customise. In VS Human matches this returns
  /// the user's saved [blueName]. Their custom Blue name is preserved
  /// across mode switches.
  String get displayBlueName =>
      _gameMode == GameMode.vsAi ? _aiDisplayName : blueName;

  /// Symmetric helper. Red is always the player so this just returns
  /// [redName]; provided so call sites can route through a uniform
  /// `display*` API.
  String get displayRedName => redName;

  // ── Ad config (all remote-driven, with safe defaults) ────────────────
  //
  // Defaults match the live Firestore values — so an offline first-launch
  // user sees the same behaviour the team is shipping today. Flip any
  // value remotely to override without an app update.

  /// Master ad kill switch. When false, all AdMob surfaces (banners +
  /// interstitials) are suppressed. The in-house Amazon-promo overlay
  /// shown after goals is **not** gated by this flag — it's owned media,
  /// not a paid ad.
  bool get showAds => _remote?.showAds ?? false;

  bool get showGuideBanner => _remote?.showGuideBanner ?? false;

  bool get showSettingsBanner => _remote?.showSettingsBanner ?? false;

  bool get showInterstitialOnGoal => _remote?.showInterstitialOnGoal ?? false;

  bool get showInterstitialOnPlayAgain =>
      _remote?.showInterstitialOnPlayAgain ?? false;

  bool get showInterstitialOnRestartGame =>
      _remote?.showInterstitialOnRestartGame ?? false;

  bool get showInterstitialOnScreenNavigation =>
      _remote?.showInterstitialOnScreenNavigation ?? false;

  /// Every Nth goal swaps the house Amazon promo for a paid interstitial.
  /// Clamped to ≥ 1 so a misconfigured `0` doesn't fire on every goal.
  int get interstitialOnEveryNthGoal {
    final int n = _remote?.interstitialOnEveryNthGoal ?? 5;
    return n < 1 ? 1 : n;
  }

  /// Every Nth navigation push fires an interstitial.
  int get interstitialEveryNthNavPush {
    final int n = _remote?.interstitialEveryNthNavPush ?? 5;
    return n < 1 ? 1 : n;
  }

  // ── Amazon promo overlay (in-house, separate from paid AdMob) ────────

  /// Master switch for the "Buy on Amazon" overlay shown after goals
  /// that aren't consumed by a paid interstitial. Defaults to `false`
  /// so first-launch users never see the overlay before remote config
  /// arrives — flip on in Firestore when ready.
  bool get showAmazonAdOverlay => _remote?.showAmazonAdOverlay ?? false;

  /// How long the Amazon overlay stays visible before it auto-dismisses.
  /// Clamped to a sane range (3–60 s) so a misconfigured `0` doesn't
  /// flash-and-vanish and a runaway `9999` doesn't trap the user.
  Duration get amazonAdDuration {
    final int n = _remote?.amazonAdDurationSeconds ?? 10;
    final int clamped = n.clamp(3, 60);
    return Duration(seconds: clamped);
  }

  /// Available palettes: remote list if non-empty, otherwise the
  /// hardcoded set. Consumers (e.g. PalettePicker) should iterate this
  /// rather than [TeamPalettes.all] directly.
  List<TeamPalette> get availablePalettes {
    final List<TeamPalette> remote =
        _remote?.teamColors ?? const <TeamPalette>[];
    return remote.isNotEmpty ? remote : TeamPalettes.all;
  }

  // ── AI config (remote-driven with safe defaults) ─────────────────────
  //
  // The home screen sets [gameMode] when the user taps "VS AI" or
  // "VS HUMAN"; mode itself is in-memory only. Difficulty IS persisted
  // (so a returning solo player gets their last-picked tier preselected
  // in the picker). Every other AI knob — random factor, think delay,
  // lookahead, scoring weights — is sourced from the remote
  // `app_settings.ai_settings` map with hardcoded fallbacks.

  GameMode get gameMode => _gameMode;

  set gameMode(final GameMode value) {
    if (_gameMode == value) return;
    _gameMode = value;
    notifyListeners();
  }

  /// User's chosen / last-used AI difficulty. Falls back to the remote
  /// `ai_default_difficulty` then [AiDifficulty.medium].
  AiDifficulty get aiDifficulty {
    if (_aiDifficultyUserSet) return _aiDifficulty;
    return _remote?.ai.defaultDifficulty ?? AiDifficulty.medium;
  }

  /// Difficulty options shown in the picker. Sourced from the remote
  /// `ai_difficulty_levels` array if non-empty, otherwise the hardcoded
  /// fallback in [AiDifficultyOption.fallback]. Iterating this rather
  /// than the [AiDifficulty] enum lets you change the labels (and even
  /// the order) from Firestore without an app update.
  List<AiDifficultyOption> get availableAiDifficulties {
    final List<AiDifficultyOption> remote =
        _remote?.ai.difficultyLevels ?? const <AiDifficultyOption>[];
    return remote.isNotEmpty ? remote : AiDifficultyOption.fallback;
  }

  /// Per-tier randomness (0.0–1.0). Higher = more chaotic / easier.
  /// Clamped defensively so a remote misconfiguration can't break the
  /// AI. See [docs/vs_ai_feature_spec.md] §3.4.
  double get aiRandomFactor {
    final double? remote;
    switch (aiDifficulty) {
      case AiDifficulty.easy:
        remote = _remote?.ai.easyRandomFactor;
        break;
      case AiDifficulty.medium:
        remote = _remote?.ai.mediumRandomFactor;
        break;
      case AiDifficulty.hard:
        remote = _remote?.ai.hardRandomFactor;
        break;
    }
    final double resolved = remote ?? _fallbackRandomFor(aiDifficulty);
    return resolved.clamp(0.0, 1.0);
  }

  /// "BLUE is thinking…" delay before the AI fires its events.
  /// Clamped to [0, 5000] so a misconfigured huge value can't hang the
  /// game.
  int get aiThinkDelayMs {
    final int? remote;
    switch (aiDifficulty) {
      case AiDifficulty.easy:
        remote = _remote?.ai.easyThinkDelayMs;
        break;
      case AiDifficulty.medium:
        remote = _remote?.ai.mediumThinkDelayMs;
        break;
      case AiDifficulty.hard:
        remote = _remote?.ai.hardThinkDelayMs;
        break;
    }
    final int resolved = remote ?? _fallbackThinkDelayFor(aiDifficulty);
    return resolved.clamp(0, 5000);
  }

  /// Whether 1-ply opponent lookahead is enabled. Only Hard ever uses
  /// it; Easy + Medium always return `false`.
  bool get aiUseLookahead {
    if (aiDifficulty != AiDifficulty.hard) return false;
    return _remote?.ai.hardUseLookahead ?? true;
  }

  // Base scoring weights — only meaningful inside the AI scorer.
  // Default values match the spec; remote overrides for fine-tuning.
  double get aiWeightChaseBall => _remote?.ai.weightChaseBall ?? 1.5;

  double get aiWeightPushToGoal => _remote?.ai.weightPushToGoal ?? 1.0;

  double get aiWeightBlockOpponent => _remote?.ai.weightBlockOpponent ?? 0.8;

  double get aiWeightCaptureBall => _remote?.ai.weightCaptureBall ?? 10.0;

  double get aiWeightScoreGoal => _remote?.ai.weightScoreGoal ?? 1000.0;

  double get aiWeightAvoidCapture => _remote?.ai.weightAvoidCapture ?? 0.5;

  static double _fallbackRandomFor(final AiDifficulty d) {
    switch (d) {
      case AiDifficulty.easy:
        return 0.6;
      case AiDifficulty.medium:
        return 0.2;
      case AiDifficulty.hard:
        return 0.05;
    }
  }

  static int _fallbackThinkDelayFor(final AiDifficulty d) {
    switch (d) {
      case AiDifficulty.easy:
        return 700;
      case AiDifficulty.medium:
        return 900;
      case AiDifficulty.hard:
        return 1100;
    }
  }

  /// Currently active palette: the user's pick if they have one,
  /// otherwise the first entry of [availablePalettes].
  TeamPalette get palette {
    final List<TeamPalette> list = availablePalettes;
    if (list.isEmpty) return TeamPalettes.classic;
    final String activeId = _paletteIdUserSet ? _paletteId : list.first.id;
    return list.firstWhere(
      (final TeamPalette p) => p.id == activeId,
      orElse: () => list.first,
    );
  }

  // ── Init ──────────────────────────────────────────────────────────────

  /// Loads everything we already have locally (prefs + cached remote
  /// snapshot). Call this before [runApp]. Does **not** hit the network —
  /// see [fetchRemoteDefaults] for that.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    _soundEnabled = _prefs!.getBool(_kSound) ?? true;
    _musicEnabled = _prefs!.getBool(_kMusic) ?? false;
    _hapticsEnabled = _prefs!.getBool(_kHaptics) ?? true;
    _commentaryEnabled = _prefs!.getBool(_kCommentary) ?? true;

    // Stored values + override flags. Migration: if a value-key exists
    // but its userSet flag does not, treat it as a user override (it must
    // have been set before the userSet-flag scheme existed).
    if (_prefs!.containsKey(_kMatchSeconds)) {
      _matchSeconds = _prefs!.getInt(_kMatchSeconds)!;
      _matchSecondsUserSet = _prefs!.getBool(_kMatchSecondsUserSet) ?? true;
    }
    if (_prefs!.containsKey(_kPalette)) {
      _paletteId = _prefs!.getString(_kPalette)!;
      _paletteIdUserSet = _prefs!.getBool(_kPaletteUserSet) ?? true;
    }
    if (_prefs!.containsKey(_kRedName)) {
      _redName = _prefs!.getString(_kRedName)!;
      _redNameUserSet = _prefs!.getBool(_kRedNameUserSet) ?? true;
    }
    if (_prefs!.containsKey(_kBlueName)) {
      _blueName = _prefs!.getString(_kBlueName)!;
      _blueNameUserSet = _prefs!.getBool(_kBlueNameUserSet) ?? true;
    }
    if (_prefs!.containsKey(_kAiDifficulty)) {
      final AiDifficulty? parsed = AiDifficultyX.fromId(
        _prefs!.getString(_kAiDifficulty),
      );
      if (parsed != null) {
        _aiDifficulty = parsed;
        _aiDifficultyUserSet = _prefs!.getBool(_kAiDifficultyUserSet) ?? true;
      }
    }

    _loadRemoteCache();
    notifyListeners();
  }

  void _loadRemoteCache() {
    final String? cached = _prefs?.getString(_kRemoteCache);
    if (cached == null) return;
    try {
      final Map<String, dynamic> map =
          json.decode(cached) as Map<String, dynamic>;
      _remote = RemoteAppSettings.fromMap(map);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SettingsService: stale remote cache discarded ($e)');
      }
    }
  }

  /// Pulls the latest `app_settings` document from Firestore. Caches the
  /// raw map locally on success so we still have defaults next launch
  /// without a network round-trip.
  ///
  /// Behaviour:
  ///   • If we already have a cached snapshot, the fetch runs in the
  ///     background — the app starts immediately with cached defaults.
  ///   • If we have no cache yet (first launch, no network), the caller
  ///     can `await` this and we'll wait up to [timeout] before falling
  ///     back to hardcoded defaults.
  Future<void> fetchRemoteDefaults({
    final Duration timeout = const Duration(seconds: 5),
  }) async {
    final bool hasCache = _remote != null;
    final Future<void> fetch = _runRemoteFetch(timeout);
    if (hasCache) {
      // Refresh in the background, don't block startup.
      unawaited(fetch);
      return;
    }
    await fetch;
  }

  Future<void> _runRemoteFetch(final Duration timeout) async {
    try {
      final QuerySnapshot<Map<String, dynamic>> q = await FirebaseFirestore
          .instance
          .collection('app_settings')
          .limit(1)
          .get()
          .timeout(timeout);
      if (q.docs.isEmpty) {
        if (kDebugMode) {
          debugPrint('SettingsService: app_settings collection is empty');
        }
        return;
      }
      final Map<String, dynamic> raw = q.docs.first.data();
      _remote = RemoteAppSettings.fromMap(raw);
      await _prefs?.setString(_kRemoteCache, json.encode(raw));
      if (kDebugMode) {
        debugPrint(
          'SettingsService: remote defaults loaded — '
          'default=${_remote?.defaultGameDuration} '
          'durations=${_remote?.gameDurations} '
          'palettes=${_remote?.teamColors.length} '
          'p1=${_remote?.player1Name} p2=${_remote?.player2Name}',
        );
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('SettingsService: remote fetch failed ($e)');
    }
  }

  // ── Setters ───────────────────────────────────────────────────────────

  Future<void> setSoundEnabled(final bool value) async {
    _soundEnabled = value;
    await _prefs?.setBool(_kSound, value);
    notifyListeners();
  }

  Future<void> setMusicEnabled(final bool value) async {
    _musicEnabled = value;
    await _prefs?.setBool(_kMusic, value);
    notifyListeners();
  }

  Future<void> setHapticsEnabled(final bool value) async {
    _hapticsEnabled = value;
    await _prefs?.setBool(_kHaptics, value);
    notifyListeners();
  }

  Future<void> setCommentaryEnabled(final bool value) async {
    _commentaryEnabled = value;
    await _prefs?.setBool(_kCommentary, value);
    notifyListeners();
  }

  Future<void> setMatchSeconds(final int seconds) async {
    _matchSeconds = seconds;
    _matchSecondsUserSet = true;
    await _prefs?.setInt(_kMatchSeconds, seconds);
    await _prefs?.setBool(_kMatchSecondsUserSet, true);
    notifyListeners();
  }

  Future<void> setPalette(final String paletteId) async {
    _paletteId = paletteId;
    _paletteIdUserSet = true;
    await _prefs?.setString(_kPalette, paletteId);
    await _prefs?.setBool(_kPaletteUserSet, true);
    notifyListeners();
  }

  Future<void> setRedName(final String name) async {
    final String trimmed = name.trim();
    _redName = trimmed.isEmpty ? _fallbackRedName : trimmed.toUpperCase();
    _redNameUserSet = true;
    await _prefs?.setString(_kRedName, _redName);
    await _prefs?.setBool(_kRedNameUserSet, true);
    notifyListeners();
  }

  Future<void> setBlueName(final String name) async {
    final String trimmed = name.trim();
    _blueName = trimmed.isEmpty ? _fallbackBlueName : trimmed.toUpperCase();
    _blueNameUserSet = true;
    await _prefs?.setString(_kBlueName, _blueName);
    await _prefs?.setBool(_kBlueNameUserSet, true);
    notifyListeners();
  }

  /// Persist the user's AI difficulty pick. Promotes the value to a
  /// "user override" so the remote `ai_default_difficulty` no longer
  /// overrides it.
  Future<void> setAiDifficulty(final AiDifficulty value) async {
    if (_aiDifficulty == value && _aiDifficultyUserSet) return;
    _aiDifficulty = value;
    _aiDifficultyUserSet = true;
    await _prefs?.setString(_kAiDifficulty, value.id);
    await _prefs?.setBool(_kAiDifficultyUserSet, true);
    notifyListeners();
  }

  /// Hardcoded fallback for the duration picker — only used if remote
  /// `game_durations` is missing or empty. Mirrors the original list.
  static const List<({int seconds, String label})> _fallbackMatchDurations =
      <({int seconds, String label})>[
        (seconds: 300, label: '5 MIN'),
        (seconds: 600, label: '10 MIN'),
        (seconds: 900, label: '15 MIN'),
        (seconds: 1200, label: '20 MIN'),
      ];
}

void debugLogSettings() {
  if (kDebugMode) {
    final SettingsService s = SettingsService.instance;
    debugPrint(
      'Settings — sound:${s.soundEnabled} music:${s.musicEnabled} '
      'haptics:${s.hapticsEnabled} commentary:${s.commentaryEnabled} '
      'matchSeconds:${s.matchSeconds} palette:${s.palette.name} '
      'red:${s.redName} blue:${s.blueName}',
    );
    debugPrint(
      'Settings/ads — showAds:${s.showAds} '
      'goalEvery:${s.interstitialOnEveryNthGoal} '
      'navEvery:${s.interstitialEveryNthNavPush} '
      'goal:${s.showInterstitialOnGoal} '
      'playAgain:${s.showInterstitialOnPlayAgain} '
      'restart:${s.showInterstitialOnRestartGame} '
      'nav:${s.showInterstitialOnScreenNavigation} '
      'guideBanner:${s.showGuideBanner} '
      'settingsBanner:${s.showSettingsBanner}',
    );
    debugPrint(
      'Settings/ai — mode:${s.gameMode.name} '
      'difficulty:${s.aiDifficulty.name} '
      'random:${s.aiRandomFactor} '
      'thinkMs:${s.aiThinkDelayMs} '
      'lookahead:${s.aiUseLookahead} '
      'levels:${s.availableAiDifficulties.map((final AiDifficultyOption o) => o.id.id).toList()}',
    );
  }
}
