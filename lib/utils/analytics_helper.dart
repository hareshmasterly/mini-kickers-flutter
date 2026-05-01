import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Centralised Firebase Analytics event names for the app.
///
/// All custom event firings go through this helper so:
///   • Event names live in one place (consistent naming, easy to audit
///     when configuring Firebase / GA4 conversions and dashboards).
///   • Failures are swallowed — analytics MUST NEVER crash gameplay.
///   • Debug builds also `debugPrint` what was sent, so you can verify
///     events without opening DebugView.
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
    try {
      await _analytics.logEvent(name: name, parameters: params);
      if (kDebugMode) {
        debugPrint('Analytics: $name${params == null ? '' : ' $params'}');
      }
    } catch (e) {
      // Never let analytics failures break the app — swallow and
      // log only. Common causes: Firebase not initialised yet, no
      // network, App Check failing.
      if (kDebugMode) debugPrint('Analytics failed ($name): $e');
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
