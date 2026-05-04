import 'package:flutter/material.dart';
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
