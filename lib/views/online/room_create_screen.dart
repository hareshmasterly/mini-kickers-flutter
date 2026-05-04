import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mini_kickers/data/models/room_code.dart';
import 'package:mini_kickers/data/services/match_service.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/utils/analytics_helper.dart';
import 'package:mini_kickers/views/home/widget/stadium_background.dart';
import 'package:mini_kickers/views/online/widget/online_action_button.dart';

/// Host-side room screen.
///
/// Lifecycle:
///   1. [initState] calls [MatchService.createRoom] → gets a 4-letter
///      code, displays it big and shareable.
///   2. We listen on the room doc via [MatchService.watchRoom]. When
///      the joiner stamps it with `match_id` + flips `status` to
///      `matched`, we pop with that match id.
///   3. On cancel / back, we DON'T delete the room doc — Firestore's
///      24-hour TTL takes care of stale rooms. (We could delete it,
///      but that races with a joiner who's already on their way.)
///
/// The code's narrow alphabet (no 0/O, 1/I/L, B/8 — see
/// [MatchService] alphabet constant) means it can be shared verbally
/// or over chat without confusion.
class RoomCreateScreen extends StatefulWidget {
  const RoomCreateScreen({super.key});

  @override
  State<RoomCreateScreen> createState() => _RoomCreateScreenState();
}

class _RoomCreateScreenState extends State<RoomCreateScreen> {
  String? _code;
  String? _errorMessage;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roomSub;
  bool _disposed = false;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _disposed = true;
    _roomSub?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    try {
      final String code = await MatchService.instance.createRoom();
      if (_disposed) return;
      Analytics.logOnlineRoomCreated();
      setState(() => _code = code);
      _roomSub = MatchService.instance.watchRoom(code).listen(_onRoomUpdate);
    } catch (e) {
      if (kDebugMode) debugPrint('Room create failed → $e');
      if (!mounted) return;
      setState(() {
        _errorMessage =
            "We couldn't create a room right now. Please try again.";
      });
    }
  }

  void _onRoomUpdate(
    final DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    if (_disposed || _resolved) return;
    if (!snap.exists) return;
    final RoomCode room = RoomCode.fromMap(snap.id, snap.data()!);
    if (room.status == RoomStatus.matched && room.matchId != null) {
      _resolved = true;
      Analytics.logOnlineMatchPaired(via: 'code');
      Navigator.of(context).pop(room.matchId);
    }
  }

  Future<void> _onCopy() async {
    final String? code = _code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Code $code copied — paste it to your friend!'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onCancel() {
    if (_disposed) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.stadiumDeep,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const StadiumBackground(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        'YOUR ROOM CODE',
                        textAlign: TextAlign.center,
                        style: AppFonts.bebasNeue(
                          fontSize: 28,
                          letterSpacing: 5,
                          color: Colors.white,
                          shadows: <Shadow>[
                            Shadow(
                              color:
                                  AppColors.brandGreen.withValues(alpha: 0.6),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _errorMessage ??
                            "Share this code with a friend.\n"
                                "We'll start the match the moment they join.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _CodeCard(code: _code, error: _errorMessage != null),
                      const SizedBox(height: 18),
                      if (_code != null) ...<Widget>[
                        OnlineActionButton(
                          label: 'COPY CODE',
                          icon: Icons.copy_rounded,
                          primary: false,
                          compact: true,
                          onTap: _onCopy,
                        ),
                        const SizedBox(height: 22),
                        const _WaitingDots(),
                        const SizedBox(height: 8),
                        Text(
                          'Waiting for your friend…',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      OnlineActionButton(
                        label: 'CANCEL',
                        icon: Icons.close_rounded,
                        primary: false,
                        onTap: _onCancel,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Big, kid-friendly display of the 4-letter code. Falls back to a
/// dotted skeleton while the code is being generated, or an error
/// state if creation failed.
class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, required this.error});
  final String? code;
  final bool error;

  @override
  Widget build(final BuildContext context) {
    final String shown = code ?? '— — — —';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF101F10),
            Color(0xFF0A150A),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: error
              ? AppColors.brandRed.withValues(alpha: 0.5)
              : AppColors.brandGreen.withValues(alpha: 0.55),
          width: 2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: (error ? AppColors.brandRed : AppColors.brandGreen)
                .withValues(alpha: 0.32),
            blurRadius: 32,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Text(
          shown,
          textAlign: TextAlign.center,
          style: AppFonts.bebasNeue(
            // Wide letter-spacing makes each char read individually —
            // important for verbal sharing ("K seven M three").
            fontSize: 56,
            letterSpacing: 14,
            color: Colors.white,
            shadows: <Shadow>[
              Shadow(
                color: AppColors.goldShine.withValues(alpha: 0.55),
                blurRadius: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three pulsing dots — visual feedback that we're still waiting.
/// Pure custom animation, no asset dependency.
class _WaitingDots extends StatefulWidget {
  const _WaitingDots();

  @override
  State<_WaitingDots> createState() => _WaitingDotsState();
}

class _WaitingDotsState extends State<_WaitingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return SizedBox(
      height: 16,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (final BuildContext context, final Widget? _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(3, (final int i) {
              final double phase = (_ctrl.value - i * 0.15) % 1.0;
              final double scale = 0.6 + 0.4 * (1 - (phase - 0.3).abs() * 2)
                  .clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.goldBright.withValues(alpha: 0.85),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color:
                              AppColors.goldBright.withValues(alpha: 0.45),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
