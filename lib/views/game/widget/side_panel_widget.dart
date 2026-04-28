import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/bloc/game/game_bloc.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/team_colors.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/utils/responsive.dart';
import 'package:mini_kickers/views/game/widget/animated_score_box.dart';
import 'package:mini_kickers/views/game/widget/dice_3d_cube.dart';

class SidePanelWidget extends StatelessWidget {
  const SidePanelWidget({super.key});

  @override
  Widget build(final BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (final BuildContext context, final Widget? child) {
        return BlocBuilder<GameBloc, GameState>(
          builder: (final BuildContext context, final GameState state) {
            final Color teamColor = TeamColors.primary(state.turn);
            return LayoutBuilder(
              builder: (final BuildContext ctx, final BoxConstraints cons) {
                // Compact mode when vertical space is tight (landscape phones).
                // Uses BoxConstraints (not MediaQuery) because the side panel
                // gets less vertical room than the full screen on narrow
                // layouts where it's stacked under the board.
                final bool compact = Responsive.isCompactBox(cons);
                final double gap = compact ? 8 : 14;
                return Container(
                  constraints: const BoxConstraints(maxWidth: 260, minWidth: 200),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _TimerWidget(timeLeft: state.timeLeft, compact: compact),
                        SizedBox(height: gap),
                        _ScoreRowWidget(
                          red: state.redScore,
                          blue: state.blueScore,
                          compact: compact,
                        ),
                        SizedBox(height: gap),
                        _TurnAndDiceWidget(
                          turn: state.turn,
                          dice: state.dice,
                          isRolling: state.isRolling,
                          teamColor: teamColor,
                          compact: compact,
                        ),
                        SizedBox(height: gap),
                        _ButtonsWidget(
                          canRoll: state.phase == GamePhase.roll &&
                              !state.isRolling,
                          teamColor: teamColor,
                          compact: compact,
                        ),
                        SizedBox(height: gap),
                        if (!compact)
                          _CommentaryWidget(message: state.message),
                      ],
                    ),
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

class _TimerWidget extends StatelessWidget {
  const _TimerWidget({required this.timeLeft, this.compact = false});
  final int timeLeft;
  final bool compact;

  @override
  Widget build(final BuildContext context) {
    final bool low = timeLeft <= 60;
    final String m = (timeLeft ~/ 60).toString();
    final String s = (timeLeft % 60).toString().padLeft(2, '0');
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1.0, end: low ? 1.06 : 1.0),
      duration: const Duration(milliseconds: 600),
      builder: (final BuildContext context, final double scale, final Widget? child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Center(
        child: Text(
          '$m:$s',
          style: AppFonts.bebasNeue(
            fontSize: compact ? 38 : 56,
            letterSpacing: 4,
            color: low ? const Color(0xFFFF5555) : AppColors.accent,
            shadows: <Shadow>[
              Shadow(
                color: (low ? const Color(0xFFFF5555) : AppColors.accent)
                    .withValues(alpha: 0.45),
                blurRadius: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreRowWidget extends StatelessWidget {
  const _ScoreRowWidget({
    required this.red,
    required this.blue,
    required this.compact,
  });
  final int red;
  final int blue;
  final bool compact;

  @override
  Widget build(final BuildContext context) {
    return Row(
      mainAxisAlignment: .center,
      children: <Widget>[
        Expanded(
          child: AnimatedScoreBox(
            label: SettingsService.instance.redName,
            score: red,
            borderColor: TeamColors.red(),
            textColor: TeamColors.redLight(),
            compact: compact,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AnimatedScoreBox(
            label: SettingsService.instance.blueName,
            score: blue,
            borderColor: TeamColors.blue(),
            textColor: TeamColors.blueLight(),
            compact: compact,
          ),
        ),
      ],
    );
  }
}

class _TurnAndDiceWidget extends StatelessWidget {
  const _TurnAndDiceWidget({
    required this.turn,
    required this.dice,
    required this.isRolling,
    required this.teamColor,
    this.compact = false,
  });
  final Team turn;
  final int? dice;
  final bool isRolling;
  final Color teamColor;
  final bool compact;

  @override
  Widget build(final BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: EdgeInsets.all(compact ? 8 : 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  AppColors.cardBg,
                  Color.lerp(AppColors.cardBg, teamColor, 0.18)!,
                ],
              ),
              border: Border.all(color: teamColor.withValues(alpha: 0.7), width: 1.5),
              borderRadius: BorderRadius.circular(12),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: teamColor.withValues(alpha: 0.4),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              children: <Widget>[
                Text(
                  'TURN',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: compact ? 9 : 11,
                    letterSpacing: 2,
                  ),
                ),
                SizedBox(height: compact ? 2 : 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (
                    final Widget child,
                    final Animation<double> animation,
                  ) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.4, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: Text(
                    "${TeamColors.name(turn)}'s turn",
                    key: ValueKey<Team>(turn),
                    style: TextStyle(
                      color: TeamColors.light(turn),
                      fontWeight: FontWeight.w800,
                      fontSize: compact ? 12 : 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: compact ? 8 : 12),
        Dice3DCube(
          value: dice,
          isRolling: isRolling,
          glowColor: teamColor,
          size: compact ? 60 : 84,
        ),
      ],
    );
  }
}

class _ButtonsWidget extends StatelessWidget {
  const _ButtonsWidget({
    required this.canRoll,
    required this.teamColor,
    this.compact = false,
  });
  final bool canRoll;
  final Color teamColor;
  final bool compact;

  @override
  Widget build(final BuildContext context) {
    final double pad = compact ? 9 : 14;
    return Row(
      children: <Widget>[
        Expanded(
          flex: 2,
          child: _GlowingRollButton(
            canRoll: canRoll,
            teamColor: teamColor,
            compact: compact,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              AudioHelper.select();
              context.read<GameBloc>().add(const ResetGameEvent());
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.muted,
              side: const BorderSide(color: AppColors.cardBorder),
              padding: EdgeInsets.symmetric(vertical: pad),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Restart',
              style: TextStyle(fontSize: compact ? 11 : 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlowingRollButton extends StatefulWidget {
  const _GlowingRollButton({
    required this.canRoll,
    required this.teamColor,
    this.compact = false,
  });
  final bool canRoll;
  final Color teamColor;
  final bool compact;

  @override
  State<_GlowingRollButton> createState() => _GlowingRollButtonState();
}

class _GlowingRollButtonState extends State<_GlowingRollButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (final BuildContext context, final Widget? child) {
        final double t = widget.canRoll ? _pulse.value : 0;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: widget.teamColor.withValues(alpha: 0.5 + t * 0.5),
                blurRadius: 14 + t * 22,
                spreadRadius: 1 + t * 4,
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: widget.canRoll
                ? () {
                    AudioHelper.select();
                    context.read<GameBloc>().add(const RollDiceEvent());
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.teamColor,
              disabledBackgroundColor: widget.teamColor.withValues(alpha: 0.35),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: widget.compact ? 11 : 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: Text(
              'ROLL DICE',
              style: TextStyle(
                fontSize: widget.compact ? 12 : 14,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CommentaryWidget extends StatelessWidget {
  const _CommentaryWidget({required this.message});
  final String message;

  @override
  Widget build(final BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppColors.cardBg,
            Color(0xFF142214),
          ],
        ),
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      constraints: const BoxConstraints(minHeight: 76),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const Text(
            '📣 COMMENTARY',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (
              final Widget child,
              final Animation<double> animation,
            ) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.4),
                  end: Offset.zero,
                ).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: Text(
              message,
              key: ValueKey<String>(message),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 13.5,
                fontStyle: FontStyle.italic,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
