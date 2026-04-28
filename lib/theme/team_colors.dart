import 'package:flutter/material.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/services/settings_service.dart';

/// Reads team colors live from the user's selected palette in [SettingsService].
/// Wrap any widget that should react to palette changes in
/// `ListenableBuilder(listenable: SettingsService.instance, ...)`.
class TeamColors {
  TeamColors._();

  static Color red() => SettingsService.instance.palette.redPrimary;
  static Color redLight() => SettingsService.instance.palette.redLight;
  static Color blue() => SettingsService.instance.palette.bluePrimary;
  static Color blueLight() => SettingsService.instance.palette.blueLight;

  static Color primary(final Team team) =>
      team == Team.red ? red() : blue();

  static Color light(final Team team) =>
      team == Team.red ? redLight() : blueLight();

  static String name(final Team team) =>
      team == Team.red
          ? SettingsService.instance.redName
          : SettingsService.instance.blueName;

  static String labelWithEmoji(final Team team) =>
      team == Team.red ? '🔴 ${name(team)}' : '🔵 ${name(team)}';

  static String otherLabelWithEmoji(final Team team) =>
      team == Team.red ? '🔵 ${name(Team.blue)}' : '🔴 ${name(Team.red)}';
}
