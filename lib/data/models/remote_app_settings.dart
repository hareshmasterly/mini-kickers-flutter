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
class RemoteAppSettings {
  const RemoteAppSettings({
    this.defaultGameDuration,
    this.gameDurations = const <int>[],
    this.teamColors = const <TeamPalette>[],
    this.player1Name,
    this.player2Name,
  });

  final int? defaultGameDuration;
  final List<int> gameDurations;
  final List<TeamPalette> teamColors;
  final String? player1Name;
  final String? player2Name;

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
