import 'package:flutter/widgets.dart';

/// Single source of truth for screen-size breakpoints across the app.
///
/// We have three logical "device buckets":
///   • **Wide**     — width ≥ [kWideWidth]. Tablets/iPads in landscape, large
///     foldables. Side-by-side ("board on left, panel on right") layouts.
///   • **Compact**  — height < [kCompactHeight]. Phones in landscape. Used by
///     the game screen to tighten typography, paddings, and switch the
///     promo overlay into its horizontal split.
///   • **Short**    — height < [kShortHeight]. Even tighter cutoff used by
///     screens with less content (the home hero), so they can keep their
///     spacious look a bit longer than the game screen.
///
/// **Two reader styles** for each predicate:
///   • `isXxx(BuildContext)`     — reads `MediaQuery.of(context).size`.
///     Use this when the widget cares about the *whole screen*.
///   • `isXxxBox(BoxConstraints)` — reads the local box you got from a
///     `LayoutBuilder`. Use this when the widget cares about the *space it
///     was actually given* (e.g. inside a panel, dialog, or split layout).
///
/// All breakpoints live here as `static const`, so changing a threshold is a
/// one-line edit that updates every consuming widget.
class Responsive {
  Responsive._();

  // ── Breakpoint constants ──────────────────────────────────────────────

  /// Heights below this (landscape phones, ~360–480 dp tall) trigger the
  /// game screen's "compact" mode — smaller header, tighter side panel,
  /// horizontal promo card.
  static const double kCompactHeight = 520;

  /// Even tighter height cutoff used by the home screen (which has less
  /// content than the game screen, so it can stay roomy until ~460 dp).
  static const double kShortHeight = 460;

  /// Widths at or above this enable side-by-side layouts (board + panel
  /// row, tablet-style hero). Tablets/iPads in landscape are typically
  /// 1024 dp+; large phones in landscape are typically 800–900 dp.
  static const double kWideWidth = 720;

  // ── MediaQuery-based readers (whole screen) ───────────────────────────

  /// `true` on phones in landscape — height-driven cutoff for the game
  /// screen's tighter typography and padding scheme.
  static bool isCompact(final BuildContext context) =>
      MediaQuery.of(context).size.height < kCompactHeight;

  /// Tighter cutoff for the home screen's compact mode.
  static bool isShort(final BuildContext context) =>
      MediaQuery.of(context).size.height < kShortHeight;

  /// `true` on tablets/iPads in landscape and large foldables — enables
  /// side-by-side layouts.
  static bool isWide(final BuildContext context) =>
      MediaQuery.of(context).size.width >= kWideWidth;

  // ── BoxConstraints-based readers (local space) ────────────────────────

  /// As [isCompact], but reads from a `LayoutBuilder`'s constraints. Use
  /// this when the widget's available height differs from the screen
  /// height (e.g. inside a dialog or split layout).
  static bool isCompactBox(final BoxConstraints cons) =>
      cons.maxHeight < kCompactHeight;

  /// As [isShort], but reads from a `LayoutBuilder`'s constraints.
  static bool isShortBox(final BoxConstraints cons) =>
      cons.maxHeight < kShortHeight;

  /// As [isWide], but reads from a `LayoutBuilder`'s constraints.
  static bool isWideBox(final BoxConstraints cons) =>
      cons.maxWidth >= kWideWidth;
}
