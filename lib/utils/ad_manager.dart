import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:mini_kickers/data/services/settings_service.dart';

/// Centralised AdMob orchestration.
///
/// Responsibilities:
///   • Owns the **test vs production** ad-unit ID switch (single point
///     to flip when the AdMob account is ready — see [_useTestIds]).
///   • Initialises the MobileAds SDK with **kids-audience** flags
///     (TFCD + max content rating G + non-personalised ads). Required
///     for App Store Kids and Play Family Policy compliance.
///   • Pre-loads exactly one interstitial at a time so [showInterstitial]
///     is always near-instant when the user reaches a break point.
///   • Reads frequency thresholds + per-slot toggles from the remote
///     `app_settings` document via [SettingsService] — every gate below
///     is remote-driven, so behaviour can be tuned without an app
///     update.
///
/// **Remote ad config (Firestore `app_settings`):**
///   • `show_ads` (bool)                                — master kill switch
///   • `show_interstitial_every_Nth_nav_push` (int)     — N for nav
///   • `show_interstitial_on_every_Nth_goal` (int)      — N for goals
///   • `show_interstitial_on_screen_naviagtion` (bool)  — nav slot toggle
///   • `show_interstitial_on_goal` (bool)               — goal slot toggle
///   • `show_interstitial_on_play_again` (bool)         — play-again slot
///   • `show_interstitial_on_restart_game` (bool)       — restart slot
///   • `show_guide_banner` / `show_settings_banner`     — banner toggles
///
/// **Switching to production:**
///   1. Set [_useTestIds] = false (or flip via `--dart-define`).
///   2. Replace the four prod constants below with your real AdMob unit
///      ids.
///   3. Replace `GADApplicationIdentifier` in `ios/Runner/Info.plist`.
///   4. Replace `com.google.android.gms.ads.APPLICATION_ID` meta-data
///      in `android/app/src/main/AndroidManifest.xml`.
class AdManager {
  AdManager._();

  static final AdManager instance = AdManager._();

  // ── ID configuration ──────────────────────────────────────────────────

  /// Master switch. When `true`, every ad call uses Google's public test
  /// unit ids — safe to use during development; never flagged as fraud,
  /// always fills. Flip to `false` when going live.
  ///
  /// Can also be overridden at build time:
  /// `flutter run --dart-define=USE_TEST_ADS=false`
  static const bool _useTestIds = bool.fromEnvironment(
    'USE_TEST_ADS',
    defaultValue: true,
  );

  // Google's published test unit ids (https://developers.google.com/admob/flutter/test-ads).
  static const String _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testInterstitialIOS =
      'ca-app-pub-3940256099942544/4411468910';
  static const String _testBannerAndroid =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testBannerIOS =
      'ca-app-pub-3940256099942544/2934735716';

  // Production unit ids — replace these strings when the AdMob account
  // is ready. Until then [_useTestIds] guards them so they're never hit.
  static const String _prodInterstitialAndroid =
      'ca-app-pub-XXXXXXXXXXXXXXXX/INTERSTITIAL_ANDROID';
  static const String _prodInterstitialIOS =
      'ca-app-pub-XXXXXXXXXXXXXXXX/INTERSTITIAL_IOS';
  static const String _prodBannerAndroid =
      'ca-app-pub-XXXXXXXXXXXXXXXX/BANNER_ANDROID';
  static const String _prodBannerIOS =
      'ca-app-pub-XXXXXXXXXXXXXXXX/BANNER_IOS';

  String get interstitialAdUnitId {
    if (_useTestIds) {
      return Platform.isIOS ? _testInterstitialIOS : _testInterstitialAndroid;
    }
    return Platform.isIOS ? _prodInterstitialIOS : _prodInterstitialAndroid;
  }

  String get bannerAdUnitId {
    if (_useTestIds) {
      return Platform.isIOS ? _testBannerIOS : _testBannerAndroid;
    }
    return Platform.isIOS ? _prodBannerIOS : _prodBannerAndroid;
  }

  // ── Counters ──────────────────────────────────────────────────────────

  int _navigationCount = 0;
  int _goalCount = 0;

  // ── State ─────────────────────────────────────────────────────────────

  bool _initialized = false;
  final Completer<void> _readyCompleter = Completer<void>();
  InterstitialAd? _interstitialAd;
  bool _loadingInterstitial = false;

  /// Completes once `MobileAds.initialize()` has finished. Widgets that
  /// load ads (banners) should `await AdManager.instance.ready` before
  /// touching any AdMob API — otherwise their `load()` runs against an
  /// un-booted SDK and fails silently.
  Future<void> get ready => _readyCompleter.future;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  /// Boots the MobileAds SDK with kids-audience flags. Idempotent.
  /// Call once early in [main]; subsequent calls are no-ops.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (kDebugMode) debugPrint('AdManager: initializing MobileAds...');
    final InitializationStatus status =
        await MobileAds.instance.initialize();
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        // COPPA / Family Policy — the app targets kids 5–12.
        tagForChildDirectedTreatment: TagForChildDirectedTreatment.yes,
        maxAdContentRating: MaxAdContentRating.g,
      ),
    );

    if (kDebugMode) {
      debugPrint(
        'AdManager: initialised — '
        'mode=${_useTestIds ? 'TEST' : 'PROD'} '
        'interstitial=$interstitialAdUnitId '
        'banner=$bannerAdUnitId',
      );
      status.adapterStatuses.forEach(
        (final String name, final AdapterStatus s) {
          debugPrint(
            'AdManager: adapter $name → state=${s.state} desc="${s.description}"',
          );
        },
      );
    }

    if (!_readyCompleter.isCompleted) _readyCompleter.complete();

    // Warm up the first interstitial so the post-game-over slot is fast.
    // We preload regardless of remote toggles — if `show_ads` is later
    // flipped on, we want an ad already in the chamber.
    _preloadInterstitial();
  }

  /// Standard ad request used for every load. Non-personalised because
  /// the audience is children — required by Family Policy.
  AdRequest get adRequest => const AdRequest(nonPersonalizedAds: true);

  // ── Interstitial pre-load + show ──────────────────────────────────────

  Future<void> _preloadInterstitial() async {
    if (_loadingInterstitial || _interstitialAd != null) return;
    _loadingInterstitial = true;
    // Defensive: only safe to call after `MobileAds.initialize()`.
    await ready;
    if (kDebugMode) debugPrint('AdManager: requesting interstitial load');
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: adRequest,
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (final InterstitialAd ad) {
          _interstitialAd = ad;
          _loadingInterstitial = false;
          if (kDebugMode) debugPrint('AdManager: interstitial loaded');
        },
        onAdFailedToLoad: (final LoadAdError err) {
          _interstitialAd = null;
          _loadingInterstitial = false;
          if (kDebugMode) {
            debugPrint('AdManager: interstitial load failed — $err');
          }
        },
      ),
    );
  }

  /// Shows the pre-loaded interstitial if one is ready and immediately
  /// kicks off loading the next one. If no ad is ready yet (slow network
  /// / first call), this returns without showing — by design, we never
  /// block the user waiting for an ad.
  ///
  /// **Master gate:** if remote `show_ads` is false, this is a no-op.
  /// Per-slot toggles (e.g. `show_interstitial_on_play_again`) are
  /// enforced by the slot-specific helpers below; calling this method
  /// directly bypasses those.
  Future<void> showInterstitial({final String? reason}) async {
    if (!SettingsService.instance.showAds) {
      if (kDebugMode) {
        debugPrint('AdManager: skipped (show_ads=false, reason=$reason)');
      }
      return;
    }
    final InterstitialAd? ad = _interstitialAd;
    if (ad == null) {
      _preloadInterstitial();
      if (kDebugMode) {
        debugPrint('AdManager: interstitial not ready (reason=$reason)');
      }
      return;
    }
    _interstitialAd = null;

    final Completer<void> dismissed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (final InterstitialAd ad) {
        ad.dispose();
        _preloadInterstitial();
        if (!dismissed.isCompleted) dismissed.complete();
      },
      onAdFailedToShowFullScreenContent: (
        final InterstitialAd ad,
        final AdError err,
      ) {
        ad.dispose();
        _preloadInterstitial();
        if (kDebugMode) debugPrint('AdManager: show failed — $err');
        if (!dismissed.isCompleted) dismissed.complete();
      },
    );
    if (kDebugMode) debugPrint('AdManager: showing interstitial ($reason)');
    await ad.show();
    await dismissed.future;
  }

  // ── Slot-specific gates ───────────────────────────────────────────────
  //
  // Each method below combines the master `show_ads` flag with the
  // per-slot toggle and (where applicable) the frequency threshold from
  // [SettingsService]. Call sites use these helpers rather than
  // [showInterstitial] directly so the gating stays in one place.

  /// Increment navigation counter; if it hits the remote threshold and
  /// the slot is enabled, show an interstitial and reset. Returns
  /// whether an ad fired.
  Future<bool> recordNavigation() async {
    final SettingsService s = SettingsService.instance;
    if (!s.showAds || !s.showInterstitialOnScreenNavigation) return false;

    _navigationCount++;
    final int every = s.interstitialEveryNthNavPush;
    if (_navigationCount >= every) {
      _navigationCount = 0;
      await showInterstitial(reason: 'navigation-${every}x');
      return true;
    }
    return false;
  }

  /// Increment the goal counter and report whether the next goal slot
  /// should fire a paid interstitial. Returns `true` on every Nth goal
  /// when ads are enabled and the goal slot is on; in that case the
  /// caller should **skip** the house Amazon promo and call
  /// [showInterstitial] (or rely on the play-loop's own dispatch).
  ///
  /// We always increment so the cadence stays stable across remote
  /// toggle flips — flipping `show_interstitial_on_goal` off then on
  /// mid-match shouldn't suddenly fire an ad on the very next goal.
  bool shouldShowGoalInterstitial() {
    _goalCount++;
    final SettingsService s = SettingsService.instance;
    if (!s.showAds || !s.showInterstitialOnGoal) return false;
    return _goalCount % s.interstitialOnEveryNthGoal == 0;
  }

  /// Post-match interstitial fired from the "Play Again" button on the
  /// game-over screen. No-op when ads are off or the slot is disabled.
  Future<void> showPlayAgainInterstitial() async {
    final SettingsService s = SettingsService.instance;
    if (!s.showAds || !s.showInterstitialOnPlayAgain) return;
    await showInterstitial(reason: 'play-again');
  }

  /// In-match interstitial fired from the side-panel "Restart" button.
  /// No-op when ads are off or the slot is disabled.
  Future<void> showRestartInterstitial() async {
    final SettingsService s = SettingsService.instance;
    if (!s.showAds || !s.showInterstitialOnRestartGame) return;
    await showInterstitial(reason: 'restart');
  }
}
