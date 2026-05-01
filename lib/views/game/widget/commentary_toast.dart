import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mini_kickers/bloc/game/game_bloc.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/utils/responsive.dart';

class CommentaryToast extends StatefulWidget {
  const CommentaryToast({super.key});

  @override
  State<CommentaryToast> createState() => _CommentaryToastState();
}

class _CommentaryToastState extends State<CommentaryToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Timer? _autoHide;
  String? _currentMessage;
  bool _isBallAlert = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
  }

  @override
  void dispose() {
    _autoHide?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _showMessage(final String text, {required final bool ballAlert}) {
    _autoHide?.cancel();
    setState(() {
      _currentMessage = text;
      _isBallAlert = ballAlert;
    });
    _ctrl.forward(from: 0);
    _autoHide = Timer(const Duration(milliseconds: 2200), _hide);
  }

  void _hide() {
    _autoHide?.cancel();
    _ctrl.reverse().whenComplete(() {
      if (!mounted) return;
      setState(() {
        _currentMessage = null;
      });
    });
  }

  String _iconFor(final String txt, {required final bool ballAlert}) {
    if (ballAlert) return '⚽';
    final String t = txt.toLowerCase();
    if (RegExp(r'goal|scores|net|unstoppable').hasMatch(t)) return '⚽';
    if (RegExp(r'roll|dice|fate|tension|breath|air').hasMatch(t)) return '🎲';
    if (RegExp(r'ball control|possession').hasMatch(t)) return '🏃';
    if (RegExp(r'blocked|stuck|nowhere|no.*move').hasMatch(t)) return '🚫';
    if (RegExp(r'win|champion|trophy|victory').hasMatch(t)) return '🏆';
    if (RegExp(r'draw|equal|square').hasMatch(t)) return '🤝';
    if (RegExp(r'time|whistle|full time').hasMatch(t)) return '🎙️';
    if (RegExp(r'kick.?off|welcome|game on').hasMatch(t)) return '🟢';
    return '📣';
  }

  @override
  Widget build(final BuildContext context) {
    return BlocListener<GameBloc, GameState>(
      listenWhen: (final GameState p, final GameState n) =>
          p.message != n.message && n.message.isNotEmpty,
      listener: (final BuildContext context, final GameState state) {
        if (!SettingsService.instance.commentaryEnabled) return;
        final bool ballAlert = state.phase == GamePhase.moveBall;
        _showMessage(state.message, ballAlert: ballAlert);
      },
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (final BuildContext context, final Widget? child) {
          if (_currentMessage == null) return const SizedBox.shrink();
          final double t = _ctrl.value.clamp(0.0, 1.0);
          final double ease = Curves.easeOutCubic.transform(t);
          final bool compact = Responsive.isCompact(context);
          final bool wide = Responsive.isWide(context);
          // Inset from board edges. Smaller on phones (every pixel
          // matters in landscape), larger on tablets (more breathing
          // room around the bar).
          final double inset = compact ? 6 : (wide ? 14 : 10);
          // Slide-up distance scales with screen size so the motion
          // feels proportional, not jarring on large displays.
          final double riseDistance = compact ? 12 : (wide ? 22 : 16);
          return Positioned(
            left: inset,
            right: inset,
            bottom: inset,
            child: Opacity(
              opacity: ease,
              child: Transform.translate(
                offset: Offset(0, riseDistance * (1 - ease)),
                child: child,
              ),
            ),
          );
        },
        child: _ToastBubble(
          message: _currentMessage ?? '',
          icon: _iconFor(_currentMessage ?? '', ballAlert: _isBallAlert),
          isBallAlert: _isBallAlert,
        ),
      ),
    );
  }
}

/// Full-width "lower-third" caption pinned to the bottom of the board.
///
/// Sized adaptively for three screen classes (see [Responsive]):
///   • compact (landscape phones, height < 520) — slim 1-line bar,
///     small padding, smaller font, tighter shadow
///   • regular phone — moderate padding and font
///   • wide (tablet / iPad) — taller padding, larger font, allows
///     up to 2 lines of text before truncating
class _ToastBubble extends StatelessWidget {
  const _ToastBubble({
    required this.message,
    required this.icon,
    required this.isBallAlert,
  });

  final String message;
  final String icon;
  final bool isBallAlert;

  @override
  Widget build(final BuildContext context) {
    final bool compact = Responsive.isCompact(context);
    final bool wide = Responsive.isWide(context);

    final double fontSize = compact ? 11.5 : (wide ? 13.5 : 12.5);
    final double iconSize = compact ? 14 : (wide ? 18 : 16);
    final EdgeInsets pad = compact
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 7)
        : (wide
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 11)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 9));
    final double radius = compact ? 8 : (wide ? 12 : 10);
    final double borderWidth = compact ? 1.4 : 1.8;
    final double iconGap = compact ? 8 : (wide ? 12 : 10);
    // Tablets get 2 lines for long lines like "GOOOOAL! BLUE finds the
    // back of the net!" — phones stay 1-line + ellipsis to keep the
    // bar from eating into the pitch.
    final int maxLines = wide ? 2 : 1;

    final Color border = isBallAlert
        ? const Color(0xFFFFCC00)
        : AppColors.accent;
    final Color textColor = isBallAlert
        ? const Color(0xFFFFE066)
        : Colors.white;
    final Color bg = isBallAlert
        ? const Color(0xF21E1400)
        : const Color(0xF20A1205);

    return Container(
      padding: pad,
      decoration: BoxDecoration(
        // Subtle horizontal sheen — feels broadcast-y without being busy.
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            bg,
            Color.alphaBlend(border.withValues(alpha: 0.06), bg),
            bg,
          ],
        ),
        border: Border.all(color: border, width: borderWidth),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: border.withValues(alpha: 0.32),
            blurRadius: compact ? 10 : 14,
            spreadRadius: 1,
          ),
          const BoxShadow(
            color: Colors.black87,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(icon, style: TextStyle(fontSize: iconSize, height: 1.2)),
          SizedBox(width: iconGap),
          Expanded(
            child: Text(
              message,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                height: 1.35,
                shadows: const <Shadow>[
                  Shadow(color: Colors.black87, blurRadius: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
