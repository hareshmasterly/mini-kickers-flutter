
// ── AI helpers ──────────────────────────────────────────────────────────

bool _isAiTurn(final GameState state) {
  if (SettingsService.instance.gameMode != GameMode.vsAi) return false;
  // The AI plays Blue. If we ever support player-as-Blue, expose
  // the AI's team via SettingsService and pass it down.
  return state.turn == Team.blue;
}

bool _isAiThinking(final GameState state) {
  if (!_isAiTurn(state)) return false;
  // Active AI phases. We hide the indicator while the dice is mid-roll
  // because the dice cube animation is already a strong "AI is doing
  // something" cue.
  if (state.isRolling) return false;
  return state.phase == GamePhase.roll ||
      state.phase == GamePhase.move ||
      state.phase == GamePhase.moveBall;
}

/// Pulsing "BLUE IS THINKING…" strip shown in the side panel during
/// AI turns. Three dots animate in sequence to communicate "wait,
/// the AI is planning its move" without being noisy.
class _AiThinkingIndicator extends StatefulWidget {
  const _AiThinkingIndicator({
    required this.teamColor,
    this.compact = false,
  });

  final Color teamColor;
  final bool compact;

  @override
  State<_AiThinkingIndicator> createState() => _AiThinkingIndicatorState();
}

class _AiThinkingIndicatorState extends State<_AiThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final double labelFont = widget.compact ? 10 : 11.5;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 10 : 12,
        vertical: widget.compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: widget.teamColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.teamColor.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.smart_toy_rounded,
            size: widget.compact ? 14 : 16,
            color: widget.teamColor,
          ),
          SizedBox(width: widget.compact ? 6 : 8),
          Text(
            // Routes through TeamColors.name → displayBlueName, so this
            // reads "AI IS THINKING" in VS AI mode (the default v1
            // wording) regardless of any saved Blue name.
            '${TeamColors.name(Team.blue)} IS THINKING',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w800,
              fontSize: labelFont,
              letterSpacing: 1.2,
            ),
          ),
          AnimatedBuilder(
            animation: _ctrl,
            builder: (final BuildContext context, final Widget? child) {
              // Three dots with phase-shifted opacities — classic
              // "loading" cadence.
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (int i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Opacity(
                        opacity: _dotOpacity(_ctrl.value, i),
                        child: Text(
                          '.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w900,
                            fontSize: labelFont + 4,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Each dot peaks at a phase-shifted offset so the row reads as a
  /// left-to-right wave. Returns a value in [0.25, 1.0] so dots are
  /// always somewhat visible (otherwise the whole row appears to
  /// vanish at every cycle's start).
  static double _dotOpacity(final double t, final int index) {
    final double phase = (t - index * 0.25) % 1.0;
    if (phase < 0) return 0.25;
    final double wave = (phase < 0.5) ? phase * 2 : (1 - phase) * 2;
    return 0.25 + wave * 0.75;
  }
}
