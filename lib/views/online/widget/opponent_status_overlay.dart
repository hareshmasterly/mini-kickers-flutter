import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mini_kickers/data/models/match_player.dart';
import 'package:mini_kickers/data/services/online_game_controller.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/utils/handle_generator.dart';

/// In-game overlay that surfaces non-fatal opponent-state changes:
///   • [OnlineMatchEvent.opponentDisconnected] → top-of-screen amber
///     banner with a countdown until forfeit. Auto-clears on
///     [OnlineMatchEvent.opponentReconnected].
///   • [OnlineMatchEvent.opponentForfeited] → centred "OPPONENT
///     LEFT THE MATCH" celebration. Auto-pops the game route after
///     a few seconds via [onForfeitConfirmed].
///   • [OnlineMatchEvent.matchCompleted] → no overlay (the existing
///     [GameOverWidget] already handles game-over UI). The
///     [OnlineGameController] still emits this event so analytics +
///     stats can fire from the game screen.
///   • [OnlineMatchEvent.syncError] → centred "Lost connection"
///     overlay with a single "GO HOME" button.
///
/// Listens to [controller.events] internally and rebuilds itself on
/// each event. Stateless from the parent's point of view — just place
/// it inside the game screen's stack.
class OpponentStatusOverlay extends StatefulWidget {
  const OpponentStatusOverlay({
    super.key,
    required this.controller,
    required this.opponent,
    required this.forfeitCountdown,
    required this.onForfeitConfirmed,
    required this.onSyncErrorAck,
  });

  final OnlineGameController controller;
  final MatchPlayer opponent;

  /// Time the opponent has to reconnect before we forfeit. Mirrors
  /// [OnlineGameController.forfeitTimeout] minus the disconnect
  /// trigger so the visible countdown lines up. In Pass 4 we hard-
  /// code 30 seconds (the default).
  final Duration forfeitCountdown;

  /// Called when the opponent-forfeit splash auto-dismisses, so the
  /// game screen can pop back to home with a "you win by default"
  /// snackbar.
  final VoidCallback onForfeitConfirmed;

  /// Called when the user taps "GO HOME" on the sync-error overlay.
  final VoidCallback onSyncErrorAck;

  @override
  State<OpponentStatusOverlay> createState() => _OpponentStatusOverlayState();
}

class _OpponentStatusOverlayState extends State<OpponentStatusOverlay> {
  StreamSubscription<OnlineMatchEvent>? _sub;
  bool _showDisconnected = false;
  bool _showForfeited = false;
  bool _showSyncError = false;
  int _secondsLeft = 0;
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    _sub = widget.controller.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _countdown?.cancel();
    super.dispose();
  }

  void _onEvent(final OnlineMatchEvent event) {
    if (!mounted) return;
    switch (event) {
      case OnlineMatchEvent.opponentDisconnected:
        setState(() {
          _showDisconnected = true;
          _secondsLeft = widget.forfeitCountdown.inSeconds;
        });
        _countdown?.cancel();
        _countdown = Timer.periodic(const Duration(seconds: 1), (final _) {
          if (!mounted) return;
          setState(() {
            _secondsLeft = (_secondsLeft - 1).clamp(0, 999);
          });
          if (_secondsLeft <= 0) _countdown?.cancel();
        });
      case OnlineMatchEvent.opponentReconnected:
        setState(() => _showDisconnected = false);
        _countdown?.cancel();
      case OnlineMatchEvent.opponentForfeited:
        _countdown?.cancel();
        setState(() {
          _showDisconnected = false;
          _showForfeited = true;
        });
        // Auto-confirm after a short celebration so the user always
        // gets booted back home — even if they've put the device
        // down. Pass 6 will replace this with a "rematch?" prompt.
        Timer(const Duration(seconds: 4), () {
          if (mounted) widget.onForfeitConfirmed();
        });
      case OnlineMatchEvent.matchCompleted:
        // No-op visually — the existing GameOverWidget already covers
        // it. The controller still emits this so the game screen's
        // listener can fire stats / analytics.
        break;
      case OnlineMatchEvent.syncError:
        _countdown?.cancel();
        setState(() => _showSyncError = true);
    }
  }

  @override
  Widget build(final BuildContext context) {
    if (_showSyncError) {
      return _SyncErrorOverlay(onGoHome: widget.onSyncErrorAck);
    }
    if (_showForfeited) {
      return _ForfeitOverlay(opponent: widget.opponent);
    }
    if (_showDisconnected) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 64,
            left: 16,
            right: 16,
          ),
          child: _DisconnectBanner(
            opponent: widget.opponent,
            secondsLeft: _secondsLeft,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _DisconnectBanner extends StatelessWidget {
  const _DisconnectBanner({
    required this.opponent,
    required this.secondsLeft,
  });
  final MatchPlayer opponent;
  final int secondsLeft;

  @override
  Widget build(final BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.brandYellow.withValues(alpha: 0.12),
            border: Border.all(
              color: AppColors.brandYellow.withValues(alpha: 0.6),
              width: 1.4,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.brandYellow.withValues(alpha: 0.32),
                blurRadius: 20,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                HandleGenerator.emojiFor(opponent.avatarId),
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${opponent.displayName.toUpperCase()} DISCONNECTED',
                      style: AppFonts.bebasNeue(
                        fontSize: 16,
                        letterSpacing: 1.6,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Forfeit in ${secondsLeft}s if they don’t come back',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForfeitOverlay extends StatelessWidget {
  const _ForfeitOverlay({required this.opponent});
  final MatchPlayer opponent;

  @override
  Widget build(final BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(color: Colors.black.withValues(alpha: 0.6)),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  HandleGenerator.emojiFor(opponent.avatarId),
                  style: const TextStyle(fontSize: 64),
                ),
                const SizedBox(height: 14),
                Text(
                  'OPPONENT LEFT',
                  textAlign: TextAlign.center,
                  style: AppFonts.bebasNeue(
                    fontSize: 36,
                    letterSpacing: 4,
                    color: Colors.white,
                    shadows: <Shadow>[
                      Shadow(
                        color: AppColors.brandYellow.withValues(alpha: 0.55),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${opponent.displayName} disconnected. You win by default!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SyncErrorOverlay extends StatelessWidget {
  const _SyncErrorOverlay({required this.onGoHome});
  final VoidCallback onGoHome;

  @override
  Widget build(final BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(color: Colors.black.withValues(alpha: 0.7)),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 56,
                  color: Colors.white70,
                ),
                const SizedBox(height: 14),
                Text(
                  'LOST CONNECTION',
                  style: AppFonts.bebasNeue(
                    fontSize: 30,
                    letterSpacing: 4,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "We couldn't reach the match. Please head back\n"
                  "to the home screen and try a fresh game.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: onGoHome,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandYellow,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: Text(
                    'GO HOME',
                    style: AppFonts.bebasNeue(
                      fontSize: 18,
                      letterSpacing: 2,
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
