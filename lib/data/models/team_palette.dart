import 'package:flutter/material.dart';

class TeamPalette {
  const TeamPalette({
    required this.id,
    required this.name,
    required this.redPrimary,
    required this.redLight,
    required this.bluePrimary,
    required this.blueLight,
  });

  final String id;
  final String name;
  final Color redPrimary;
  final Color redLight;
  final Color bluePrimary;
  final Color blueLight;
}

class TeamPalettes {
  TeamPalettes._();

  static const TeamPalette classic = TeamPalette(
    id: 'classic',
    name: 'Classic',
    redPrimary: Color(0xFFD63030),
    redLight: Color(0xFFFF7070),
    bluePrimary: Color(0xFF2060CC),
    blueLight: Color(0xFF70AAFF),
  );

  static const TeamPalette fireIce = TeamPalette(
    id: 'fire_ice',
    name: 'Fire vs Ice',
    redPrimary: Color(0xFFE64A19),
    redLight: Color(0xFFFF8A65),
    bluePrimary: Color(0xFF00838F),
    blueLight: Color(0xFF4DD0E1),
  );

  static const TeamPalette pitchVsPro = TeamPalette(
    id: 'pitch',
    name: 'Pitch vs Pro',
    redPrimary: Color(0xFFFB8C00),
    redLight: Color(0xFFFFB74D),
    bluePrimary: Color(0xFF388E3C),
    blueLight: Color(0xFF81C784),
  );

  static const TeamPalette royal = TeamPalette(
    id: 'royal',
    name: 'Royal vs Gold',
    redPrimary: Color(0xFFF9A825),
    redLight: Color(0xFFFFD54F),
    bluePrimary: Color(0xFF6A1B9A),
    blueLight: Color(0xFFBA68C8),
  );

  static const TeamPalette cherryMint = TeamPalette(
    id: 'cherry',
    name: 'Cherry vs Mint',
    redPrimary: Color(0xFFC2185B),
    redLight: Color(0xFFF06292),
    bluePrimary: Color(0xFF00897B),
    blueLight: Color(0xFF4DB6AC),
  );

  static const List<TeamPalette> all = <TeamPalette>[
    classic,
    fireIce,
    pitchVsPro,
    royal,
    cherryMint,
  ];

  static TeamPalette byId(final String id) =>
      all.firstWhere((final TeamPalette p) => p.id == id, orElse: () => classic);
}
