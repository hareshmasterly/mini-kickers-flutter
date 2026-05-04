import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mini_kickers/data/models/match_player.dart';
import 'package:mini_kickers/data/models/online_match.dart';
import 'package:mini_kickers/data/models/user_profile.dart';
import 'package:mini_kickers/data/services/match_service.dart';
import 'package:mini_kickers/data/services/user_service.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/utils/analytics_helper.dart';
import 'package:mini_kickers/views/home/widget/stadium_background.dart';
import 'package:mini_kickers/views/online/widget/avatar_chip.dart';
import 'package:mini_kickers/views/online/widget/online_action_button.dart';

/// Random matchmaking — "looking for opponent" screen.
///
/// Lifecycle:
///   1. [initState] enters the queue via [MatchService.enterMatchmakingQueue]
///      and starts listening on our queue doc.
///   2. Every [_pairUpInterval] we attempt a client-side pair-up via
///      [MatchService.tryClientSidePairUp]. Whichever side wins the
///      transaction creates the `matches/{id}` doc.
///   3. We watch our queue doc — when it disappears (deleted by the
///      pair-up transaction, server function, or the cancel button)
///      we stop polling. If a match was created with us in it, the
///      pair-up call's return value gives us the match id directly;
///      if the OTHER side paired us up, we look ourselves up in the
///      matches collection.
///   4. On match found we [Navigator.pop(matchId)]. On cancel /
///      back button we [leaveMatchmakingQueue] and pop with `null`.
///
/// Failure modes:
///   • Queue write fails → show "couldn't join queue, try again" +
///     dismiss. Doesn't crash.
///   • Stuck in queue past [_searchTimeout] → show "no players online,
///     try again later" copy with retry button. Still keeps the doc
///     so the next person to queue can pair with us.
class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({super.key});

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen>
    with SingleTickerProviderStateMixin {
  /// How often we attempt a client-side pair-up while waiting. Three
  /// seconds is the sweet spot: fast enough that two players queueing
  /// at the same moment match within ~3s, slow enough that we don't
  /// hammer Firestore with reads.
  static const Duration _pairUpInterval = Duration(seconds: 3);

  /// After this long without a match we soften the UI to "no players
  /// online" without leaving the queue (so a late arriver can still
  /// pair with us).
  static const Duration _searchTimeout = Duration(seconds: 45);

  late final AnimationController _spinner;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _queueSub;
  Timer? _pairUpTimer;
  Timer? _timeoutTimer;
  bool _entering = true;
  bool _stale = false;
  String? _errorMessage;
  String? _resultMatchId;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _spinner = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    Analytics.logOnlineQueueJoined();
    _enterQueue();
  }

  @override
  void dispose() {
    _disposed = true;
    _spinner.dispose();
    _queueSub?.cancel();
    _pairUpTimer?.cancel();
    _timeoutTimer?.cancel();
    // Best-effort queue cleanup. Fire-and-forget — if the user is
    // already in a match (we paired up successfully) the doc won't
    // exist and the delete is a no-op.
    MatchService.instance.leaveMatchmakingQueue();
    super.dispose();
  }

  Future<void> _enterQueue() async {
    try {
      final Stream<DocumentSnapshot<Map<String, dynamic>>> stream =
          await MatchService.instance.enterMatchmakingQueue();
      if (_disposed) return;
      _queueSub = stream.listen(_onQueueUpdate);
      _pairUpTimer = Timer.periodic(
        _pairUpInterval,
        (final _) => _attemptPairUp(),
      );
      _timeoutTimer = Timer(_searchTimeout, () {
        if (_disposed || _resultMatchId != null) return;
        setState(() => _stale = true);
      });
      // Fire one immediate attempt so we don't wait the full interval
      // when there's already someone queued.
      unawaited(_attemptPairUp());
      if (mounted) setState(() => _entering = false);
    } catch (e) {
      if (kDebugMode) debugPrint('Matchmaking: enter failed → $e');
      if (!mounted) return;
      setState(() {
        _entering = false;
        _errorMessage = "We couldn't join the queue. Please try again.";
      });
    }
  }

  Future<void> _attemptPairUp() async {
    if (_disposed || _resultMatchId != null) return;
    final String? matchId =
        await MatchService.instance.tryClientSidePairUp();
    if (matchId != null) {
      _onMatchFound(matchId);
    }
  }

  void _onQueueUpdate(
    final DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    // If our queue doc was deleted while we still don't know about a
    // match, the OTHER side paired us up. Look ourselves up in the
    // matches collection.
    if (snap.exists || _resultMatchId != null) return;
    _findOurMatch();
  }

  Future<void> _findOurMatch() async {
    final String? uid = UserService.instance.uid;
    if (uid == null) return;
    try {
      // Look up matches where we appear on either side. Limit to the
      // newest doc — if multiple match us we want the freshest one.
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection('matches')
          .where('status', isEqualTo: MatchStatus.inProgress.wireValue)
          .orderBy('created_at', descending: true)
          .limit(10)
          .get();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snap.docs) {
        final Map<String, dynamic> data = doc.data();
        final String? redUid =
            ((data['red'] as Map<dynamic, dynamic>?)?['uid']) as String?;
        final String? blueUid =
            ((data['blue'] as Map<dynamic, dynamic>?)?['uid']) as String?;
        if (redUid == uid || blueUid == uid) {
          _onMatchFound(doc.id);
          return;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Matchmaking: opponent-paired lookup failed → $e');
      }
    }
  }

  void _onMatchFound(final String matchId) {
    if (_disposed || _resultMatchId != null) return;
    _resultMatchId = matchId;
    Analytics.logOnlineMatchPaired(via: 'random');
    // Cancel the polling immediately so we don't kick off another
    // pair-up while we're navigating.
    _pairUpTimer?.cancel();
    _timeoutTimer?.cancel();
    _queueSub?.cancel();
    if (mounted) Navigator.of(context).pop(matchId);
  }

  void _onCancel() {
    if (_disposed) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(final BuildContext context) {
    final UserProfile? profile = UserService.instance.profile;
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
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _SpinnerCrest(animation: _spinner),
                      const SizedBox(height: 24),
                      Text(
                        _stale
                            ? 'STILL LOOKING…'
                            : (_errorMessage != null
                                ? 'OOPS!'
                                : 'LOOKING FOR\nOPPONENT'),
                        textAlign: TextAlign.center,
                        style: AppFonts.bebasNeue(
                          fontSize: 32,
                          letterSpacing: 4,
                          color: Colors.white,
                          shadows: <Shadow>[
                            Shadow(
                              color:
                                  AppColors.brandYellow.withValues(alpha: 0.5),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _errorMessage ??
                            (_stale
                                ? 'Not many players online right now —'
                                    " we'll keep trying."
                                : "Hang tight! We'll match you with"
                                    ' someone in a sec.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (profile != null)
                        AvatarChip(
                          player: MatchPlayer(
                            uid: profile.uid,
                            handle: profile.handle,
                            displayName: profile.displayName,
                            avatarId: profile.avatarId,
                          ),
                          size: 64,
                        ),
                      const SizedBox(height: 32),
                      OnlineActionButton(
                        label: _entering ? 'JOINING…' : 'CANCEL',
                        icon: Icons.close_rounded,
                        primary: false,
                        busy: _entering,
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

/// Pulsing crest behind the "looking for opponent" copy. Two layered
/// rotating arcs give a subtle stadium-spotlight feel without a heavy
/// asset. Pure custom-paint, no images.
class _SpinnerCrest extends StatelessWidget {
  const _SpinnerCrest({required this.animation});
  final AnimationController animation;

  @override
  Widget build(final BuildContext context) {
    return SizedBox(
      width: 140,
      height: 140,
      child: AnimatedBuilder(
        animation: animation,
        builder: (final BuildContext context, final Widget? _) {
          return CustomPaint(
            painter: _CrestPainter(t: animation.value),
            child: Center(
              child: Text(
                '⚽',
                style: TextStyle(
                  fontSize: 48,
                  shadows: <Shadow>[
                    Shadow(
                      color: AppColors.brandYellow.withValues(alpha: 0.6),
                      blurRadius: 18,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CrestPainter extends CustomPainter {
  _CrestPainter({required this.t});
  final double t;

  @override
  void paint(final Canvas canvas, final Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double radius = min(size.width, size.height) / 2;

    // Outer arc — slow rotation, gold accent.
    final Paint arc1 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: pi * 2,
        colors: <Color>[
          Colors.transparent,
          AppColors.goldShine.withValues(alpha: 0.85),
          Colors.transparent,
        ],
        transform: GradientRotation(t * pi * 2),
      ).createShader(Rect.fromCircle(center: c, radius: radius));
    canvas.drawCircle(c, radius - 6, arc1);

    // Inner arc — opposite direction, lime accent.
    final Paint arc2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: pi * 2,
        colors: <Color>[
          Colors.transparent,
          AppColors.limeBright.withValues(alpha: 0.55),
          Colors.transparent,
        ],
        transform: GradientRotation(-t * pi * 2),
      ).createShader(Rect.fromCircle(center: c, radius: radius - 18));
    canvas.drawCircle(c, radius - 22, arc2);
  }

  @override
  bool shouldRepaint(covariant final _CrestPainter old) => old.t != t;
}
