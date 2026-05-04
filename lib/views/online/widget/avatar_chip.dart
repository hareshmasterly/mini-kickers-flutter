import 'package:flutter/material.dart';
import 'package:mini_kickers/data/models/match_player.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/utils/handle_generator.dart';

/// Reusable "player chip" used across the online flow — avatar emoji
/// in a glowing circle, handle text below.
///
/// Two layouts via [orientation]:
///   • [Axis.vertical]   — stacked (avatar above handle). Used in the
///                         lobby header and matchmaking screens.
///   • [Axis.horizontal] — side-by-side (avatar left, handle right).
///                         Used in tight rows like the room-create
///                         "host: someone" line.
///
/// The emoji is resolved via [HandleGenerator.emojiFor] which consults
/// the live [AvatarService] catalog, so editor-side avatar swaps are
/// reflected immediately without an app update.
class AvatarChip extends StatelessWidget {
  const AvatarChip({
    super.key,
    required this.player,
    this.size = 56,
    this.orientation = Axis.vertical,
    this.glowColor,
    this.dimmed = false,
  });

  /// The player whose avatar + handle to render.
  final MatchPlayer player;

  /// Diameter of the avatar circle. Handle text auto-scales relative
  /// to this so the chip stays visually balanced.
  final double size;

  /// Stacked vs side-by-side. Defaults to stacked.
  final Axis orientation;

  /// Optional glow tint. Defaults to the brand yellow used elsewhere
  /// in the home/lobby UI. Pass [Colors.transparent] to disable the
  /// glow entirely (useful in dense lists).
  final Color? glowColor;

  /// When true, drops opacity to ~50%. Used to indicate a "waiting"
  /// or "disconnected" peer.
  final bool dimmed;

  @override
  Widget build(final BuildContext context) {
    final Color glow = glowColor ?? AppColors.brandYellow;
    final double handleFont = (size * 0.22).clamp(11.0, 18.0);
    final Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[
            glow.withValues(alpha: 0.32),
            glow.withValues(alpha: 0.05),
            Colors.transparent,
          ],
        ),
        border: Border.all(
          color: glow.withValues(alpha: 0.6),
          width: 2,
        ),
        boxShadow: glow == Colors.transparent
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: glow.withValues(alpha: 0.45),
                  blurRadius: size * 0.4,
                  spreadRadius: 1,
                ),
              ],
      ),
      child: Center(
        child: Text(
          HandleGenerator.emojiFor(player.avatarId),
          style: TextStyle(fontSize: size * 0.55),
        ),
      ),
    );
    final Widget handle = Text(
      player.displayName.toUpperCase(),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: handleFont,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        height: 1.15,
      ),
    );

    final Widget content = orientation == Axis.vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              avatar,
              SizedBox(height: size * 0.14),
              handle,
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              avatar,
              SizedBox(width: size * 0.22),
              Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: handle,
                ),
              ),
            ],
          );

    return Opacity(
      opacity: dimmed ? 0.5 : 1.0,
      child: content,
    );
  }
}
