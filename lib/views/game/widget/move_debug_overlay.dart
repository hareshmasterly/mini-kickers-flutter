import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mini_kickers/bloc/game/game_bloc.dart';
import 'package:mini_kickers/data/models/game_models.dart';

/// **Toggle to show/hide the on-screen debug readout.**
///
/// Off by default. Flip to `true` when investigating a "wrong highlight"
/// or dice-display complaint, then re-build. Even when on, the overlay
/// still only renders in debug builds (`kDebugMode`), never in release.
const bool _kEnabled = false;

/// Debug readout pinned to the bottom-left of the game screen, gated by
/// the `_kEnabled` switch above. Renders **nothing** when disabled or in
/// release builds.
///
/// When active, shows the live ground truth from the bloc:
///   • Selected token id + position
///   • Current dice value
///   • Phase
///   • Number and list of highlighted cells
///
/// Use this to confirm whether a "wrong highlight" complaint is:
///   1. Algorithm bug (the listed cells are wrong for that dice value), or
///   2. Render leak (the on-screen highlights don't match this list).
class MoveDebugOverlay extends StatelessWidget {
  const MoveDebugOverlay({super.key});

  @override
  Widget build(final BuildContext context) {
    if (!_kEnabled || !kDebugMode) return const SizedBox.shrink();
    return Positioned(
      left: 8,
      bottom: 8,
      child: IgnorePointer(
        child: BlocBuilder<GameBloc, GameState>(
          builder: (final BuildContext context, final GameState state) {
            final Token? sel = state.selectedTokenId == null
                ? null
                : state.tokens
                    .where((final Token t) => t.id == state.selectedTokenId)
                    .firstOrNull;
            final List<String> cells = state.highlights
                .map((final Pos p) => '(${p.c},${p.r})')
                .toList();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.6),
                ),
              ),
              constraints: const BoxConstraints(maxWidth: 320),
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'DEBUG • move highlights',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text('phase   : ${state.phase.name}'),
                    Text('turn    : ${state.turn.name}'),
                    Text('dice    : ${state.dice ?? "—"}'),
                    Text(
                      'selected: ${sel == null ? "—" : "${sel.id} (${sel.c},${sel.r})"}',
                    ),
                    Text('count   : ${state.highlights.length}'),
                    if (cells.isNotEmpty)
                      Text(
                        'cells   : ${cells.join(", ")}',
                        softWrap: true,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
