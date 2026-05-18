import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:mini_kickers/data/services/settings_service.dart';

/// Distinct ad slot. Each value maps to its own AdMob unit id so
/// per-placement revenue, fill rate and mediation rules can be tuned
/// independently in the AdMob console.
///
/// Test mode (`USE_TEST_ADS=true`) collapses all banner placements to
/// Google's single test banner id and all interstitial placements to
/// the single test interstitial id — Google's test infrastructure is
/// not per-placement.
enum AdPlacement {
  // Banners
  settingsBanner,
  guideBanner,
  // Interstitials
  navigationInterstitial,
  goalInterstitial,
  playAgainInterstitial,
  restartInterstitial,
}

/// Centralised AdMob orchestration.
///
/// Responsibilities:
///   • Owns the **test vs production** ad-unit ID switch (single point
///     to flip when the AdMob account is ready — see [_useTestIds]).
///   • Initialises the MobileAds SDK with **kids-audience** flags
///     (TFCD + max content rating G + non-personalised ads). Required
///     for App Store Kids and Play Family Policy compliance.
///   • Pre-loads exactly one interstitial **per [AdPlacement] slot** so
///     every slot's first show is near-instant when the user reaches a
///     break point.
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
///   2. Replace every `_prod*` placeholder constant below with the real
///      AdMob unit id from the AdMob console — one per placement per
///      platform (12 total).
///   3. Replace `GADApplicationIdentifier` in `ios/Runner/Info.plist`.
///   4. Replace `com.google.android.gms.ads.APPLICATION_ID` meta-data
///      in `android/app/src/main/AndroidManifest.xml`.
class AdManager {
  AdManager._();

  static final AdManager instance = AdManager._();

  // ── ID configuration ──────────────────────────────────────────────────

  /// Master switch — auto-derived from build mode.
  ///
  /// • **Debug builds** (`flutter run`, `flutter build apk --debug`,
  ///   `flutter build appbundle --debug`) → `true` → uses Google's
  ///   public test unit ids. Safe for development; AdMob never flags
  ///   test ids as fraud and they always fill.
  /// • **Profile / Release builds** (`flutter build apk --release`,
  ///   `flutter build appbundle --release`) → `false` → uses the real
  ///   `_prod*` ids defined below.
  ///
  /// `kDebugMode` is a Flutter compile-time constant — the unused
  /// branch is tree-shaken out of release builds, so the test ids
  /// don't even ship in production binaries.
  ///
  /// **Even in release**, no ad request actually leaves the device
  /// unless `SettingsService.instance.showAds` (the Firestore
  /// `show_ads` flag) is also true — see [_preloadInterstitial] and
  /// [BannerAdWidget._loadAd].
  static const bool _useTestIds = kDebugMode;

  // ── Test ids (Google public, never flagged) ───────────────────────────
  // https://developers.google.com/admob/flutter/test-ads
  // Test infrastructure is not per-placement — every banner uses the
  // banner test id, every interstitial uses the interstitial test id.
  static const String _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testInterstitialIOS =
      'ca-app-pub-3940256099942544/4411468910';
  static const String _testBannerAndroid =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testBannerIOS = 'ca-app-pub-3940256099942544/2934735716';

  // ── Prod ids (placeholders — replace before going live) ───────────────
  // One unit id per [AdPlacement] per platform. Format must remain
  // `ca-app-pub-XXXXXXXXXXXXXXXX/SLOT_NAME` so the SDK accepts the
  // string at request time (it'll just no-fill).

  // Banners
  static const String _prodSettingsBannerAndroid =
      'ca-app-pub-8449105731318025/5116433211';
  static const String _prodSettingsBannerIOS =
      'ca-app-pub-8449105731318025/6671408640';
  static const String _prodGuideBannerAndroid =
      'ca-app-pub-8449105731318025/9916274269';
  static const String _prodGuideBannerIOS =
      'ca-app-pub-8449105731318025/2732163637';

  // Interstitials
  static const String _prodNavInterstitialAndroid =
      'ca-app-pub-8449105731318025/5970349882';
  static const String _prodNavInterstitialIOS =
      'ca-app-pub-8449105731318025/2658028515';
  static const String _prodGoalInterstitialAndroid =
      'ca-app-pub-8449105731318025/1312919577';
  static const String _prodGoalInterstitialIOS =
      'ca-app-pub-8449105731318025/7792918627';
  static const String _prodPlayAgainInterstitialAndroid =
      'ca-app-pub-8449105731318025/7686756233';
  static const String _prodPlayAgainInterstitialIOS =
      'ca-app-pub-8449105731318025/9780787716';
  static const String _prodRestartInterstitialAndroid =
      'ca-app-pub-8449105731318025/7036019542';
  static const String _prodRestartInterstitialIOS =
      'ca-app-pub-8449105731318025/2306674726';

  /// Returns the AdMob unit id for the given placement. Honors
  /// [_useTestIds] (test mode collapses all banners → one test banner id
  /// and all interstitials → one test interstitial id; Google doesn't
  /// expose per-placement test ids).
  String adUnitIdFor(final AdPlacement placement) {
    final bool isIOS = Platform.isIOS;
    if (_useTestIds) {
      switch (placement) {
        case AdPlacement.settingsBanner:
        case AdPlacement.guideBanner:
          return isIOS ? _testBannerIOS : _testBannerAndroid;
        case AdPlacement.navigationInterstitial:
        case AdPlacement.goalInterstitial:
        case AdPlacement.playAgainInterstitial:
        case AdPlacement.restartInterstitial:
          return isIOS ? _testInterstitialIOS : _testInterstitialAndroid;
      }
    }
    switch (placement) {
      case AdPlacement.settingsBanner:
        return isIOS ? _prodSettingsBannerIOS : _prodSettingsBannerAndroid;
      case AdPlacement.guideBanner:
        return isIOS ? _prodGuideBannerIOS : _prodGuideBannerAndroid;
      case AdPlacement.navigationInterstitial:
        return isIOS ? _prodNavInterstitialIOS : _prodNavInterstitialAndroid;
      case AdPlacement.goalInterstitial:
        return isIOS ? _prodGoalInterstitialIOS : _prodGoalInterstitialAndroid;
      case AdPlacement.playAgainInterstitial:
        return isIOS
            ? _prodPlayAgainInterstitialIOS
            : _prodPlayAgainInterstitialAndroid;
      case AdPlacement.restartInterstitial:
        return isIOS
            ? _prodRestartInterstitialIOS
            : _prodRestartInterstitialAndroid;
    }
  }

  /// All interstitial placements — used for warm pre-loading at init.
  static const List<AdPlacement> _interstitialPlacements = <AdPlacement>[
    AdPlacement.navigationInterstitial,
    AdPlacement.goalInterstitial,
    AdPlacement.playAgainInterstitial,
    AdPlacement.restartInterstitial,
  ];

  // ── Counters ──────────────────────────────────────────────────────────

  int _navigationCount = 0;
  int _goalCount = 0;

  // ── State ─────────────────────────────────────────────────────────────

  bool _initialized = false;
  final Completer<void> _readyCompleter = Completer<void>();

  /// One pre-loaded interstitial cached per slot. After a slot fires, the
  /// callback re-loads that slot so the next firing is also instant.
  final Map<AdPlacement, InterstitialAd?> _interstitials =
      <AdPlacement, InterstitialAd?>{};
  final Map<AdPlacement, bool> _loadingInterstitials = <AdPlacement, bool>{};

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
    final InitializationStatus status = await MobileAds.instance.initialize();
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        // COPPA / Family Policy — the app targets kids 5–12.
        tagForChildDirectedTreatment: TagForChildDirectedTreatment.yes,
        maxAdContentRating: MaxAdContentRating.g,
      ),
    );

    if (kDebugMode) {
      debugPrint(
        'AdManager: initialised — mode=${_useTestIds ? 'TEST' : 'PROD'}',
      );
      for (final AdPlacement p in AdPlacement.values) {
        debugPrint('AdManager: ${p.name} → ${adUnitIdFor(p)}');
      }
      status.adapterStatuses.forEach((
        final String name,
        final AdapterStatus s,
      ) {
        debugPrint(
          'AdManager: adapter $name → state=${s.state} desc="${s.description}"',
        );
      });
    }

    if (!_readyCompleter.isCompleted) _readyCompleter.complete();

    // React to remote `show_ads` flips during the session. The hard
    // rule is: NO ad activity (load OR show) when show_ads is false.
    //   • toggled ON  → preload every slot so the first firing is fast
    //   • toggled OFF → dispose any cached/in-flight interstitials so
    //                   nothing sits in memory or hits AdMob
    SettingsService.instance.addListener(_onSettingsChanged);

    // Initial preload — only if show_ads is currently true. If it's
    // false (or false in cached remote config), we DON'T touch AdMob
    // until/unless it flips on later.
    _maybePreloadAllSlots();
  }

  void _onSettingsChanged() {
    if (SettingsService.instance.showAds) {
      _maybePreloadAllSlots();
    } else {
      _disposeAllCachedInterstitials();
    }
  }

  /// Preloads every interstitial slot — but only when the master
  /// `show_ads` flag is on. Idempotent: slots that are already loaded
  /// or in-flight are skipped by [_preloadInterstitial].
  void _maybePreloadAllSlots() {
    if (!SettingsService.instance.showAds) return;
    for (final AdPlacement p in _interstitialPlacements) {
      _preloadInterstitial(p);
    }
  }

  /// Releases the native AAB/IronSource ad object for every cached
  /// interstitial. Called when `show_ads` flips OFF mid-session so we
  /// don't keep ad inventory in memory we'll never display.
  void _disposeAllCachedInterstitials() {
    for (final AdPlacement p in _interstitials.keys.toList()) {
      _interstitials[p]?.dispose();
      _interstitials[p] = null;
    }
    if (kDebugMode) {
      debugPrint(
        'AdManager: disposed all cached interstitials (show_ads=false)',
      );
    }
  }

  /// Standard ad request used for every load. Non-personalised because
  /// the audience is children — required by Family Policy.
  AdRequest get adRequest => const AdRequest(nonPersonalizedAds: true);

  // ── Interstitial pre-load + show ──────────────────────────────────────

  Future<void> _preloadInterstitial(final AdPlacement placement) async {
    // Hard gate: NEVER hit AdMob when the master switch is off, even
    // if a slot helper accidentally calls in here. This is the single
    // point where every interstitial network request originates.
    if (!SettingsService.instance.showAds) {
      if (kDebugMode) {
        debugPrint(
          'AdManager: skipped preload of ${placement.name} — show_ads=false',
        );
      }
      return;
    }
    if (_loadingInterstitials[placement] == true) return;
    if (_interstitials[placement] != null) return;
    _loadingInterstitials[placement] = true;
    // Defensive: only safe to call after `MobileAds.initialize()`.
    await ready;
    final String unitId = adUnitIdFor(placement);
    if (kDebugMode) {
      debugPrint('AdManager: requesting load — ${placement.name} ($unitId)');
    }
    InterstitialAd.load(
      adUnitId: unitId,
      request: adRequest,
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (final InterstitialAd ad) {
          _interstitials[placement] = ad;
          _loadingInterstitials[placement] = false;
          if (kDebugMode) {
            debugPrint('AdManager: ${placement.name} loaded');
          }
        },
        onAdFailedToLoad: (final LoadAdError err) {
          _interstitials[placement] = null;
          _loadingInterstitials[placement] = false;
          if (kDebugMode) {
            debugPrint('AdManager: ${placement.name} load failed — $err');
          }
        },
      ),
    );
  }

  /// Internal: shows the cached interstitial for [placement] if one is
  /// ready, otherwise schedules a pre-load and returns silently. Honors
  /// the master `show_ads` flag; per-slot toggles are enforced by the
  /// public slot helpers.
  Future<void> _showInterstitialFor(
    final AdPlacement placement, {
    final String? reason,
  }) async {
    if (!SettingsService.instance.showAds) {
      if (kDebugMode) {
        debugPrint(
          'AdManager: skipped (show_ads=false, slot=${placement.name}, '
          'reason=$reason)',
        );
      }
      return;
    }
    final InterstitialAd? ad = _interstitials[placement];
    if (ad == null) {
      _preloadInterstitial(placement);
      if (kDebugMode) {
        debugPrint(
          'AdManager: ${placement.name} not ready (reason=$reason) — '
          'scheduled preload',
        );
      }
      return;
    }
    _interstitials[placement] = null;

    final Completer<void> dismissed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (final InterstitialAd ad) {
        ad.dispose();
        _preloadInterstitial(placement);
        if (!dismissed.isCompleted) dismissed.complete();
      },
      onAdFailedToShowFullScreenContent:
          (final InterstitialAd ad, final AdError err) {
            ad.dispose();
            _preloadInterstitial(placement);
            if (kDebugMode) {
              debugPrint('AdManager: ${placement.name} show failed — $err');
            }
            if (!dismissed.isCompleted) dismissed.complete();
          },
    );
    if (kDebugMode) {
      debugPrint('AdManager: showing ${placement.name} (reason=$reason)');
    }
    await ad.show();
    await dismissed.future;
  }

  // ── Slot-specific gates ───────────────────────────────────────────────
  //
  // Each method below combines the master `show_ads` flag with the
  // per-slot toggle and (where applicable) the frequency threshold from
  // [SettingsService]. Call sites use these helpers rather than
  // [_showInterstitialFor] directly so the gating stays in one place.

  /// Increment navigation counter; if it hits the remote threshold and
  /// the slot is enabled, show the navigation interstitial and reset.
  /// Returns whether an ad fired.
  Future<bool> recordNavigation() async {
    final SettingsService s = SettingsService.instance;
    if (!s.showAds || !s.showInterstitialOnScreenNavigation) return false;

    _navigationCount++;
    final int every = s.interstitialEveryNthNavPush;
    if (_navigationCount >= every) {
      _navigationCount = 0;
      await _showInterstitialFor(
        AdPlacement.navigationInterstitial,
        reason: 'navigation-${every}x',
      );
      return true;
    }
    return false;
  }

  /// Synchronous check: should the next goal slot fire a paid
  /// interstitial? Always increments so the cadence stays stable across
  /// remote toggle flips. Caller uses the return value to decide whether
  /// to show the house Amazon promo instead — if `true`, call
  /// [showGoalInterstitial] and skip the promo.
  bool shouldShowGoalInterstitial() {
    _goalCount++;
    final SettingsService s = SettingsService.instance;
    if (!s.showAds || !s.showInterstitialOnGoal) return false;
    return _goalCount % s.interstitialOnEveryNthGoal == 0;
  }

  /// Fires the goal-slot interstitial. Pair with
  /// [shouldShowGoalInterstitial] (the bool gate stays synchronous so
  /// the caller can decide between paid ad and house promo without
  /// awaiting).
  Future<void> showGoalInterstitial() =>
      _showInterstitialFor(AdPlacement.goalInterstitial, reason: 'goal-nth');

  /// Post-match interstitial fired from the "Play Again" button on the
  /// game-over screen. No-op when ads are off or the slot is disabled.
  Future<void> showPlayAgainInterstitial() async {
    final SettingsService s = SettingsService.instance;
    if (!s.showAds || !s.showInterstitialOnPlayAgain) return;
    await _showInterstitialFor(
      AdPlacement.playAgainInterstitial,
      reason: 'play-again',
    );
  }

  /// In-match interstitial fired from the side-panel "Restart" button.
  /// No-op when ads are off or the slot is disabled.
  Future<void> showRestartInterstitial() async {
    final SettingsService s = SettingsService.instance;
    if (!s.showAds || !s.showInterstitialOnRestartGame) return;
    await _showInterstitialFor(
      AdPlacement.restartInterstitial,
      reason: 'restart',
    );
  }
}
