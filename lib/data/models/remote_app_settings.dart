import 'package:flutter/material.dart';
import 'package:mini_kickers/data/models/ai_difficulty_option.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/models/team_palette.dart';

/// Parsed snapshot of the `app_settings` document from Firestore.
///
/// Schema (single document inside the `app_settings` collection):
///   • `default_game_duration` — int (seconds). Initial match length when
///     the user has not picked one.
///   • `game_durations`        — array of int. The allowed values shown in
///     the Settings → Match Duration picker.
///   • `team_name.player1` / `.player2` — strings (default team names).
///   • `team_colors` — array of `{id, name, primary1, primary1_light,
///     primary2, primary2_light}`, where `primary*` values are
///     `0xAARRGGBB` hex strings.
///   • `show_ads` — bool. Master kill switch. When false, all AdMob
///     surfaces (banners + interstitials) are suppressed. The in-house
///     Amazon-promo overlay is unaffected.
///   • `show_guide_banner` / `show_settings_banner` — bool. Per-screen
///     toggles for the bottom banner ad.
///   • `show_interstitial_on_goal` / `show_interstitial_on_play_again` /
///     `show_interstitial_on_restart_game` /
///     `show_interstitial_on_screen_naviagtion` (sic — typo preserved
///     to match the Firestore key) — bool. Per-slot interstitial
///     toggles.
///   • `show_interstitial_on_every_Nth_goal` /
///     `show_interstitial_every_Nth_nav_push` — int. Frequency
///     thresholds for the goal-based and navigation-based interstitial
///     triggers respectively.
///   • `show_amazon_ad_overlay` — bool. Master switch for the in-house
///     "Buy on Amazon" promo overlay shown on goal slots that aren't
///     consumed by a paid interstitial. Independent of `show_ads`
///     (the paid AdMob switch).
///   • `amazon_ad_duration_second` — int (seconds). How long the
///     Amazon overlay stays visible before auto-dismissing. Defaults
///     to 10 when missing or invalid.
class RemoteAppSettings {
  const RemoteAppSettings({
    this.defaultGameDuration,
    this.gameDurations = const <int>[],
    this.teamColors = const <TeamPalette>[],
    this.player1Name,
    this.player2Name,
    this.showAds,
    this.showGuideBanner,
    this.showSettingsBanner,
    this.showInterstitialOnGoal,
    this.showInterstitialOnPlayAgain,
    this.showInterstitialOnRestartGame,
    this.showInterstitialOnScreenNavigation,
    this.interstitialOnEveryNthGoal,
    this.interstitialEveryNthNavPush,
    this.showAmazonAdOverlay,
    this.amazonAdDurationSeconds,
    this.ai = const RemoteAiSettings(),
  });

  final int? defaultGameDuration;
  final List<int> gameDurations;
  final List<TeamPalette> teamColors;
  final String? player1Name;
  final String? player2Name;

  // ── Ad config (all nullable — `null` means "fall back to default") ────
  final bool? showAds;
  final bool? showGuideBanner;
  final bool? showSettingsBanner;
  final bool? showInterstitialOnGoal;
  final bool? showInterstitialOnPlayAgain;
  final bool? showInterstitialOnRestartGame;
  final bool? showInterstitialOnScreenNavigation;
  final int? interstitialOnEveryNthGoal;
  final int? interstitialEveryNthNavPush;

  // ── Amazon promo overlay (in-house, separate from AdMob) ──────────────
  final bool? showAmazonAdOverlay;
  final int? amazonAdDurationSeconds;

  /// AI tuning sub-tree, parsed from the nested `ai_settings` map. Falls
  /// back to an empty [RemoteAiSettings] when absent so callers always
  /// get sensible defaults.
  final RemoteAiSettings ai;

  factory RemoteAppSettings.fromMap(final Map<String, dynamic> data) {
    final List<dynamic> colors = (data['team_colors'] as List<dynamic>?) ??
        const <dynamic>[];
    final List<dynamic> durations =
        (data['game_durations'] as List<dynamic>?) ?? const <dynamic>[];
    final Map<String, dynamic>? teamName =
        (data['team_name'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>();

    return RemoteAppSettings(
      defaultGameDuration:
          (data['default_game_duration'] as num?)?.toInt(),
      gameDurations: durations
          .whereType<num>()
          .map((final num n) => n.toInt())
          .toList(),
      teamColors: colors
          .whereType<Map<dynamic, dynamic>>()
          .map((final Map<dynamic, dynamic> raw) =>
              raw.cast<String, dynamic>())
          .map(_paletteFromMap)
          .toList(),
      player1Name: teamName?['player1'] as String?,
      player2Name: teamName?['player2'] as String?,
      showAds: data['show_ads'] as bool?,
      showGuideBanner: data['show_guide_banner'] as bool?,
      showSettingsBanner: data['show_settings_banner'] as bool?,
      showInterstitialOnGoal: data['show_interstitial_on_goal'] as bool?,
      showInterstitialOnPlayAgain:
          data['show_interstitial_on_play_again'] as bool?,
      showInterstitialOnRestartGame:
          data['show_interstitial_on_restart_game'] as bool?,
      // NB: Firestore key is misspelled (`naviagtion`); we mirror the
      // misspelling here so the lookup succeeds. Rename in Firestore +
      // here together when convenient.
      showInterstitialOnScreenNavigation:
          data['show_interstitial_on_screen_naviagtion'] as bool?,
      interstitialOnEveryNthGoal:
          (data['show_interstitial_on_every_Nth_goal'] as num?)?.toInt(),
      interstitialEveryNthNavPush:
          (data['show_interstitial_every_Nth_nav_push'] as num?)?.toInt(),
      showAmazonAdOverlay: data['show_amazon_ad_overlay'] as bool?,
      amazonAdDurationSeconds:
          (data['amazon_ad_duration_second'] as num?)?.toInt(),
      ai: RemoteAiSettings.fromMap(
        (data['ai_settings'] as Map<dynamic, dynamic>?)
            ?.cast<String, dynamic>(),
      ),
    );
  }

  static TeamPalette _paletteFromMap(final Map<String, dynamic> m) =>
      TeamPalette(
        id: (m['id'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        redPrimary: _parseHexColor(m['primary1']),
        redLight: _parseHexColor(m['primary1_light']),
        bluePrimary: _parseHexColor(m['primary2']),
        blueLight: _parseHexColor(m['primary2_light']),
      );

  static Color _parseHexColor(final Object? raw) {
    if (raw is num) return Color(raw.toInt());
    if (raw is! String) return const Color(0xFF000000);
    String s = raw.trim();
    if (s.toLowerCase().startsWith('0x')) s = s.substring(2);
    if (s.startsWith('#')) s = s.substring(1);
    final int? parsed = int.tryParse(s, radix: 16);
    if (parsed == null) return const Color(0xFF000000);
    // RGB (no alpha) → assume opaque.
    if (s.length == 6) return Color(0xFF000000 | parsed);
    return Color(parsed);
  }
}

/// AI-specific tuning, parsed from the nested `ai_settings` map.
///
/// Schema (under `app_settings.ai_settings`):
///   • `ai_default_difficulty` — string, one of `easy`/`medium`/`hard`.
///   • `ai_difficulty_levels` — array of `{id, name, subtitle?, emoji?}`
///     used to populate the picker. See [AiDifficultyOption].
///   • `ai_<tier>_random_factor` — number 0.0–1.0, per-tier noise.
///   • `ai_<tier>_think_delay_ms` — number, milliseconds.
///   • `ai_hard_use_lookahead` — bool.
///   • `ai_weight_*` — optional advanced scoring weights (six fields).
///
/// Every field is nullable; consumers (in [SettingsService]) layer
/// hardcoded defaults on top.
class RemoteAiSettings {
  const RemoteAiSettings({
    this.defaultDifficulty,
    this.difficultyLevels = const <AiDifficultyOption>[],
    this.easyRandomFactor,
    this.mediumRandomFactor,
    this.hardRandomFactor,
    this.easyThinkDelayMs,
    this.mediumThinkDelayMs,
    this.hardThinkDelayMs,
    this.hardUseLookahead,
    this.weightChaseBall,
    this.weightPushToGoal,
    this.weightBlockOpponent,
    this.weightCaptureBall,
    this.weightScoreGoal,
    this.weightAvoidCapture,
  });

  final AiDifficulty? defaultDifficulty;
  final List<AiDifficultyOption> difficultyLevels;

  // Per-tier knobs.
  final double? easyRandomFactor;
  final double? mediumRandomFactor;
  final double? hardRandomFactor;
  final int? easyThinkDelayMs;
  final int? mediumThinkDelayMs;
  final int? hardThinkDelayMs;
  final bool? hardUseLookahead;

  // Advanced scoring weights (shared across tiers).
  final double? weightChaseBall;
  final double? weightPushToGoal;
  final double? weightBlockOpponent;
  final double? weightCaptureBall;
  final double? weightScoreGoal;
  final double? weightAvoidCapture;

  factory RemoteAiSettings.fromMap(final Map<String, dynamic>? data) {
    if (data == null) return const RemoteAiSettings();

    final List<dynamic> levelsRaw =
        (data['ai_difficulty_levels'] as List<dynamic>?) ?? const <dynamic>[];
    final List<AiDifficultyOption> levels = levelsRaw
        .whereType<Map<dynamic, dynamic>>()
        .map((final Map<dynamic, dynamic> raw) =>
            AiDifficultyOption.fromMap(raw.cast<String, dynamic>()))
        .whereType<AiDifficultyOption>()
        .toList();

    return RemoteAiSettings(
      defaultDifficulty:
          AiDifficultyX.fromId(data['ai_default_difficulty'] as String?),
      difficultyLevels: levels,
      easyRandomFactor: _toDouble(data['ai_easy_random_factor']),
      mediumRandomFactor: _toDouble(data['ai_medium_random_factor']),
      hardRandomFactor: _toDouble(data['ai_hard_random_factor']),
      easyThinkDelayMs: (data['ai_easy_think_delay_ms'] as num?)?.toInt(),
      mediumThinkDelayMs:
          (data['ai_medium_think_delay_ms'] as num?)?.toInt(),
      hardThinkDelayMs: (data['ai_hard_think_delay_ms'] as num?)?.toInt(),
      hardUseLookahead: data['ai_hard_use_lookahead'] as bool?,
      weightChaseBall: _toDouble(data['ai_weight_chase_ball']),
      weightPushToGoal: _toDouble(data['ai_weight_push_to_goal']),
      weightBlockOpponent: _toDouble(data['ai_weight_block_opponent']),
      weightCaptureBall: _toDouble(data['ai_weight_capture_ball']),
      weightScoreGoal: _toDouble(data['ai_weight_score_goal']),
      weightAvoidCapture: _toDouble(data['ai_weight_avoid_capture']),
    );
  }

  static double? _toDouble(final Object? raw) {
    if (raw is num) return raw.toDouble();
    return null;
  }
}
