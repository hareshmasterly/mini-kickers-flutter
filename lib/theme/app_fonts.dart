import 'package:flutter/material.dart';

/// Bundled font helpers — replace `google_fonts` runtime downloads with
/// locally-shipped TrueType files (see `assets/fonts/`). This removes the
/// app's dependency on `fonts.gstatic.com` at runtime, so it works offline
/// and starts up faster.
class AppFonts {
  AppFonts._();

  static const String bebasNeueFamily = 'BebasNeue';
  static const String dmSansFamily = 'DMSans';

  /// Drop-in replacement for `GoogleFonts.bebasNeue(...)`.
  static TextStyle bebasNeue({
    final double? fontSize,
    final FontWeight? fontWeight,
    final Color? color,
    final double? letterSpacing,
    final double? height,
    final List<Shadow>? shadows,
    final FontStyle? fontStyle,
  }) =>
      TextStyle(
        fontFamily: bebasNeueFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        shadows: shadows,
        fontStyle: fontStyle,
      );

  /// Drop-in replacement for `GoogleFonts.dmSansTextTheme(...)`.
  static TextTheme dmSansTextTheme(final TextTheme base) {
    TextStyle? withFamily(final TextStyle? s) =>
        s?.copyWith(fontFamily: dmSansFamily);
    return base.copyWith(
      displayLarge: withFamily(base.displayLarge),
      displayMedium: withFamily(base.displayMedium),
      displaySmall: withFamily(base.displaySmall),
      headlineLarge: withFamily(base.headlineLarge),
      headlineMedium: withFamily(base.headlineMedium),
      headlineSmall: withFamily(base.headlineSmall),
      titleLarge: withFamily(base.titleLarge),
      titleMedium: withFamily(base.titleMedium),
      titleSmall: withFamily(base.titleSmall),
      bodyLarge: withFamily(base.bodyLarge),
      bodyMedium: withFamily(base.bodyMedium),
      bodySmall: withFamily(base.bodySmall),
      labelLarge: withFamily(base.labelLarge),
      labelMedium: withFamily(base.labelMedium),
      labelSmall: withFamily(base.labelSmall),
    );
  }
}
