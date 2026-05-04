import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mini_kickers/bloc/game/game_bloc.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/theme/team_colors.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/views/game/widget/dice_3d_cube.dart';

/// Per-team broadcast-scoreboard "lower third" panel, designed to be
/// rendered INSIDE a [RotatedBox] so it faces its physical player on a
/// flat shared device.
///
/// Internally laid out as a HORIZONTAL row:
///   `[ TEAM strip ] [ SCORE block ] [ LIVE pip ] [ DICE + caption ]`
///
/// After being wrapped in `RotatedBox(quarterTurns: 1)` (left panel,
/// 90° clockwise) or `quarterTurns: 3` (right panel, 90° counter-
/// clockwise), the row appears as a vertical strip at the screen edge
/// with the team name at the player's top-left corner of their view —
/// reading naturally top-to-bottom from THEIR side of the device.
///
/// The row is sized for the rotated frame: its `width` equals the slot's
/// vertical space (full screen height) and its `height` equals the
/// slot's panel-width (80–170 px depending on device tier).
class TeamSidePanel extends StatelessWidget {
  const TeamSidePanel({super.key, required this.team});

  /// Which team this panel belongs to. Drives colour, name, score,
  /// active-state binding, and which dice tap-event fires.
  final Team team;

  @override
  Widget build(final BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (final BuildContext context, final Widget? _) {
        return BlocBuilder<GameBloc, GameState>(
          builder: (final BuildContext context, final GameState state) {
            return LayoutBuilder(
              builder:
                  (final BuildContext ctx, final BoxConstraints cons) {
                // We're inside a RotatedBox(quarterTurns: 1 or 3), so
                // dimensions are SWAPPED relative to the on-screen slot:
                //   maxWidth  = slot's vertical space (screen height)
                //   maxHeight = slot's panel width   (80–170 px)
                final double thickness = cons.maxHeight;
                final bool compact = thickness < 100;
                final bool wide = thickness >= 150;

                final Color teamColor = TeamColors.primary(team);
                final Color teamLight = TeamColors.light(team);
                // TeamColors.name routes through SettingsService's
                // displayRedName / displayBlueName, so this resolves to
                // "AI" for the bot side in VS AI mode automatically.
                final String teamName = TeamColors.name(team);
                final int score = team == Team.red
                    ? state.redScore
                    : state.blueScore;

                final bool isMyTurn = state.turn == team;
                // True when THIS panel belongs to the AI in a VS AI
                // match (the AI plays Blue per AiController). Used to
                // suppress tap affordances and to swap captions to
                // AI-specific copy ("AI THINKING…" instead of "TAP TO
                // ROLL"). In VS Human mode this is always false and
                // the panel behaves identically to before.
                final bool isAiTeam =
                    SettingsService.instance.gameMode == GameMode.vsAi &&
                        team == Team.blue;
                // True when this panel belongs to the OPPONENT in an
                // online 1v1. The dice on their side must never be
                // tappable — only the active local player rolls. Their
                // dice value still updates via remote sync.
                final bool isOnlineOpponentTeam =
                    state.online != null &&
                        state.online!.localTeam != team;
                // Dice is tappable only for HUMAN turns — in VS AI mode
                // the AiController dispatches RollDiceEvent itself and
                // we must never let the user manually roll on the bot's
                // behalf. In online mode we additionally suppress tap
                // affordances on the opponent's panel.
                final bool canTap = isMyTurn &&
                    !isAiTeam &&
                    !isOnlineOpponentTeam &&
                    state.phase == GamePhase.roll &&
                    !state.isRolling;

                return _PanelChrome(
                  isActive: isMyTurn,
                  teamColor: teamColor,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _TeamStrip(
                        teamName: teamName,
                        teamColor: teamColor,
                        teamLight: teamLight,
                        thickness: thickness,
                        compact: compact,
                        wide: wide,
                      ),
                      _ScoreBlock(
                        score: score,
                        teamColor: teamColor,
                        thickness: thickness,
                        compact: compact,
                        wide: wide,
                      ),
                      _LivePip(
                        isLive: isMyTurn,
                        compact: compact,
                        wide: wide,
                      ),
                      Expanded(
                        child: _DiceZone(
                          state: state,
                          team: team,
                          isMyTurn: isMyTurn,
                          canTap: canTap,
                          isAiTeam: isAiTeam,
                          teamColor: teamColor,
                          teamLight: teamLight,
                          thickness: thickness,
                          compact: compact,
                          wide: wide,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ─── Outer chrome ───────────────────────────────────────────────────────

/// Panel background + outer border. Switches between "active" (bright
/// team-color border, broadcast scanline) and "idle" (muted) states.
class _PanelChrome extends StatelessWidget {
  const _PanelChrome({
    required this.child,
    required this.isActive,
    required this.teamColor,
  });

  final Widget child;
  final bool isActive;
  final Color teamColor;

  @override
  Widget build(final BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          decoration: BoxDecoration(
            // Slightly darker base so the "TEAM strip" gradient block
            // and "SCORE block" both stand off the panel cleanly.
            color: const Color(0xEE0A150A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: teamColor.withValues(alpha: isActive ? 0.85 : 0.18),
              width: isActive ? 1.6 : 1.0,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: teamColor.withValues(alpha: isActive ? 0.35 : 0.05),
                blurRadius: isActive ? 26 : 8,
                spreadRadius: isActive ? 1 : 0,
              ),
              const BoxShadow(
                color: Colors.black87,
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─── Section 1: Team strip ──────────────────────────────────────────────

/// Solid team-color block with the team name in BebasNeue. First thing
/// the player sees when reading their panel left→right (which is
/// top-to-bottom after rotation, from their physical viewpoint).
class _TeamStrip extends StatelessWidget {
  const _TeamStrip({
    required this.teamName,
    required this.teamColor,
    required this.teamLight,
    required this.thickness,
    required this.compact,
    required this.wide,
  });

  final String teamName;
  final Color teamColor;
  final Color teamLight;
  final double thickness;
  final bool compact;
  final bool wide;

  @override
  Widget build(final BuildContext context) {
    final double width = compact ? 60 : (wide ? 92 : 80);
    final double fontSize = compact ? 16 : (wide ? 24 : 22);
    return Container(
      width: width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            teamColor,
            Color.lerp(teamColor, Colors.black, 0.35)!,
          ],
        ),
        border: Border(
          right: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              teamName,
              maxLines: 1,
              style: AppFonts.bebasNeue(
                fontSize: fontSize,
                color: Colors.white,
                letterSpacing: 2,
                shadows: const <Shadow>[
                  Shadow(color: Colors.black54, blurRadius: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Section 2: Score block ─────────────────────────────────────────────

/// Big bold score number, broadcast-graphic style. Score has a thin
/// team-color underline so it's tied visually to the team strip.
class _ScoreBlock extends StatelessWidget {
  const _ScoreBlock({
    required this.score,
    required this.teamColor,
    required this.thickness,
    required this.compact,
    required this.wide,
  });

  final int score;
  final Color teamColor;
  final double thickness;
  final bool compact;
  final bool wide;

  @override
  Widget build(final BuildContext context) {
    final double width = compact ? 64 : (wide ? 105 : 90);
    final double fontSize = compact ? 36 : (wide ? 62 : 56);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        border: Border(
          right: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
          bottom: BorderSide(
            color: teamColor.withValues(alpha: 0.6),
            width: 2,
          ),
        ),
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder:
              (final Widget child, final Animation<double> anim) {
            return ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            );
          },
          child: Text(
            '$score',
            key: ValueKey<int>(score),
            style: AppFonts.bebasNeue(
              fontSize: fontSize,
              color: Colors.white,
              letterSpacing: 1,
              shadows: <Shadow>[
                Shadow(
                  color: teamColor.withValues(alpha: 0.7),
                  blurRadius: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Section 3: LIVE pip ────────────────────────────────────────────────

/// Pulsing red dot + "LIVE" label, only visible when this team is active.
/// Carbon-copy of the indicator on a TV broadcast bug — makes the
/// active player unmistakable from across the table.
class _LivePip extends StatefulWidget {
  const _LivePip({
    required this.isLive,
    required this.compact,
    required this.wide,
  });

  final bool isLive;
  final bool compact;
  final bool wide;

  @override
  State<_LivePip> createState() => _LivePipState();
}

class _LivePipState extends State<_LivePip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.isLive) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant final _LivePip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLive && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!widget.isLive && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final double width = widget.compact ? 38 : (widget.wide ? 52 : 48);
    final double dotSize = widget.compact ? 8 : (widget.wide ? 10 : 10);
    final double fontSize = widget.compact ? 8 : (widget.wide ? 10 : 9);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        border: Border(
          right: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: widget.isLive ? 1.0 : 0.18,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedBuilder(
              animation: _pulse,
              builder: (final BuildContext context, final Widget? _) {
                final double t = _pulse.value;
                final double scale = widget.isLive ? 1.0 + t * 0.6 : 1.0;
                final double glowAlpha =
                    widget.isLive ? (1 - t) * 0.85 : 0;
                return SizedBox(
                  width: dotSize * 2.2,
                  height: dotSize * 2.2,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      // Outward pulse halo
                      Transform.scale(
                        scale: scale,
                        child: Container(
                          width: dotSize * 1.6,
                          height: dotSize * 1.6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFFF3344)
                                .withValues(alpha: glowAlpha * 0.5),
                          ),
                        ),
                      ),
                      // Solid centre dot
                      Container(
                        width: dotSize,
                        height: dotSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.isLive
                              ? const Color(0xFFFF3344)
                              : Colors.white.withValues(alpha: 0.3),
                          boxShadow: widget.isLive
                              ? const <BoxShadow>[
                                  BoxShadow(
                                    color: Color(0xCCFF3344),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 2),
            Text(
              'LIVE',
              style: TextStyle(
                color: widget.isLive
                    ? const Color(0xFFFF6677)
                    : Colors.white.withValues(alpha: 0.4),
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section 4: Dice + caption (interactive) ────────────────────────────

/// The interactive end of the panel: dice cube + status caption. The dice
/// is the roll button — tappable when [canTap]. Caption animates between
/// "TAP TO ROLL", "ROLLING…", "YOUR MOVE", "KICK THE BALL", "WAITING".
class _DiceZone extends StatelessWidget {
  const _DiceZone({
    required this.state,
    required this.team,
    required this.isMyTurn,
    required this.canTap,
    required this.isAiTeam,
    required this.teamColor,
    required this.teamLight,
    required this.thickness,
    required this.compact,
    required this.wide,
  });

  final GameState state;
  final Team team;
  final bool isMyTurn;
  final bool canTap;
  /// True when this panel belongs to the AI in a VS AI match. The dice
  /// must NOT be tappable in that case (AiController owns the rolls)
  /// and the caption shows AI-specific copy.
  final bool isAiTeam;
  final Color teamColor;
  final Color teamLight;
  final double thickness;
  final bool compact;
  final bool wide;

  @override
  Widget build(final BuildContext context) {
    // The dice is sized to fit within the panel's "thickness" (the short
    // axis after rotation), leaving room for the caption underneath.
    // Dice cube size scales with panel thickness, but capped. 80 keeps
    // the cube readable from across the table without stealing focus
    // from the score / team strip on tablet. The clamp floor (46)
    // prevents it from getting unreadable on the smallest landscape
    // phones.
    final double diceSize = (thickness * 0.62).clamp(46.0, 80.0);
    final double captionFont = compact ? 9 : (wide ? 12 : 11);
    final double horizontalPad = compact ? 8 : 14;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPad, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Dice3DCube(
            // Read THIS team's persisted last-rolled value, not the
            // shared `state.dice` — otherwise rolling on one side
            // updates both panels' cubes (the bug being fixed).
            value: team == Team.red ? state.redDice : state.blueDice,
            isRolling: state.isRolling && isMyTurn,
            glowColor: teamColor,
            size: diceSize,
            isEnabled: isMyTurn,
            onTap: canTap ? () => _onDiceTap(context) : null,
          ),
          SizedBox(width: compact ? 6 : 12),
          Flexible(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              transitionBuilder:
                  (final Widget child, final Animation<double> anim) {
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.15, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                );
              },
              child: Text(
                _captionFor(state, isMyTurn),
                key: ValueKey<String>(_captionFor(state, isMyTurn)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: canTap
                      ? teamLight
                      : (isMyTurn
                          ? Colors.white.withValues(alpha: 0.7)
                          : Colors.white.withValues(alpha: 0.35)),
                  fontSize: captionFont,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  height: 1.15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onDiceTap(final BuildContext context) {
    AudioHelper.select();
    context.read<GameBloc>().add(const RollDiceEvent());
  }

  String _captionFor(final GameState state, final bool isMyTurn) {
    if (!isMyTurn) return 'WAITING';
    // AI-specific copy — no "TAP" prompt because the bot owns its
    // own actions and we don't want to invite player taps that would
    // be ignored. The animated dots in the active LIVE pip already
    // signal "something is happening on this side".
    if (isAiTeam) {
      switch (state.phase) {
        case GamePhase.roll:
          return state.isRolling ? 'ROLLING…' : 'AI\nTHINKING…';
        case GamePhase.move:
          return 'AI\nMOVING…';
        case GamePhase.moveBall:
          return 'AI\nKICKING…';
        case GamePhase.coinToss:
          return '—';
        case GamePhase.gameOver:
          return 'FULL\nTIME';
      }
    }
    switch (state.phase) {
      case GamePhase.roll:
        return state.isRolling ? 'ROLLING…' : 'TAP\nTO ROLL';
      case GamePhase.move:
        return 'YOUR\nMOVE';
      case GamePhase.moveBall:
        return 'KICK\nTHE BALL';
      case GamePhase.coinToss:
        return '—';
      case GamePhase.gameOver:
        return 'FULL\nTIME';
    }
  }
}
