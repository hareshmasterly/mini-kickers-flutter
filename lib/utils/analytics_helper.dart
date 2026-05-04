import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Centralised Firebase Analytics event names for the app.
///
/// All custom event firings go through this helper so:
///   • Event names live in one place (consistent naming, easy to audit
///     when configuring Firebase / GA4 conversions and dashboards).
///   • Failures are swallowed — analytics MUST NEVER crash gameplay.
///   • **Debug builds DO NOT register events with Firebase** — dev
///     sessions must never pollute production analytics. Instead we
///     `debugPrint` what WOULD have been sent so you can verify wiring
///     locally without polluting GA4.
///
/// SDK-level collection is also disabled in debug via
/// `FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(...)` in
/// [main.dart] — so even if a future caller bypasses this helper and
/// calls `FirebaseAnalytics.instance.logEvent` directly, the event
/// still won't leave the device in a debug build.
///
/// Naming convention: `<noun>_<verb>` in snake_case (Firebase requires
/// snake_case + 40-char max). Use [Analytics.logXxx] from call sites.
class Analytics {
  Analytics._();

  static FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;

  static Future<void> _log(
    final String name, {
    final Map<String, Object>? params,
  }) async {
    // Hard gate: in debug builds we NEVER actually call Firebase. We
    // still print to console so you can verify the wiring while
    // developing — it just doesn't get registered against the GA4
    // property. This keeps your prod analytics clean.
    if (kDebugMode) {
      debugPrint(
        'Analytics (debug — not sent): $name'
        '${params == null ? '' : ' $params'}',
      );
      return;
    }
    try {
      await _analytics.logEvent(name: name, parameters: params);
    } catch (_) {
      // Never let analytics failures break the app. Crashlytics
      // (release-only) catches any uncaught errors elsewhere; here we
      // intentionally swallow because losing a single event is
      // acceptable, crashing on it is not.
    }
  }

  /// Fires when the home screen first becomes visible after splash.
  /// Useful for measuring DAU and retention vs sessions started.
  static Future<void> logHomeOpened() => _log('home_opened');

  /// Fires when the user taps PLAY on the home screen and the game
  /// route is pushed. Pairs with [logHomeOpened] to compute play-rate.
  static Future<void> logGameStarted() => _log('game_started');

  /// Fires when the user CONFIRMS the in-match Restart prompt
  /// (not when they cancel). Useful for spotting frustration: high
  /// restart rate per match suggests rules confusion or unfair feel.
  static Future<void> logGameRestarted() => _log('game_restarted');

  // ── Online 1v1 ─────────────────────────────────────────────────

  /// Fires when the user opens the online lobby (taps PLAY ONLINE on
  /// the home screen). Useful for measuring funnel into the matchmaking
  /// flow vs how many actually start a match.
  static Future<void> logOnlineLobbyOpened() => _log('online_lobby_opened');

  /// Fires when the user enters the random matchmaking queue. Pairs
  /// with [logOnlineMatchPaired] to compute the match-up rate (queue
  /// joins → actual pair-ups).
  static Future<void> logOnlineQueueJoined() => _log('online_queue_joined');

  /// Fires when the user is paired with an opponent (either via
  /// random matchmaking or a room code). [via] is `'random'` or `'code'`.
  static Future<void> logOnlineMatchPaired({required final String via}) =>
      _log(
        'online_match_paired',
        params: <String, Object>{'via': via},
      );

  /// Fires when the host creates a friend-pair room. Pairs with
  /// [logOnlineRoomJoined] to spot rooms that never get joined
  /// (high abandonment may indicate the share-code UX needs work).
  static Future<void> logOnlineRoomCreated() => _log('online_room_created');

  /// Fires when the joiner submits a room code that resolves to an
  /// open room. [success] is true when the join succeeded; false when
  /// it failed (bad code, taken, expired, self-join, …).
  static Future<void> logOnlineRoomJoined({required final bool success}) =>
      _log(
        'online_room_join_attempt',
        params: <String, Object>{'success': success.toString()},
      );

  /// Fires when an online match is forfeited because the OPPONENT
  /// disconnected past the heartbeat timeout. Tracks network-quality
  /// pain — a high rate suggests we should soften the timeout or add
  /// a "waiting for opponent" grace period.
  static Future<void> logOnlineForfeit() => _log('online_match_forfeit');

  /// Fires when the user taps any Amazon "Buy" link.
  ///
  /// [source] identifies WHERE the tap came from so you can compare
  /// CTR on the home-screen button vs the in-game goal overlay:
  ///   • `'home_button'` — BuyAmazonButton on the home screen
  ///   • `'goal_overlay'` — FirstGoalAdOverlay shown after a goal
  static Future<void> logAmazonTap({required final String source}) => _log(
        'amazon_link_tapped',
        params: <String, Object>{'source': source},
      );
}
