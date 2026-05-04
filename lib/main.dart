import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mini_kickers/app/my_app.dart';
import 'package:mini_kickers/data/services/avatar_service.dart';
import 'package:mini_kickers/data/services/faq_service.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/data/services/user_service.dart';
import 'package:mini_kickers/routes/app_providers.dart';
import 'package:mini_kickers/utils/ad_manager.dart';

// Remote defaults + FAQs are warmed on the splash screen so app startup
// stays snappy. See [SplashScreen._warmRemoteData].

const String currentFlavor = String.fromEnvironment(
  'FLAVOR',
  defaultValue: 'staging',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('Current Flavor: $currentFlavor');

  await SettingsService.instance.init();
  await FaqService.instance.init();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }

  // Firebase App Check — attests that requests come from a genuine app
  // instance, blocking abuse of the open Firestore reads (`app_settings` and
  // `faqs`). Wrapped in try/catch + non-blocking unawaited so a Play
  // Integrity / DeviceCheck failure (e.g. emulator without Play Services,
  // or before App Check is enabled in the Firebase Console) NEVER prevents
  // app launch — Firestore will just see un-attested requests, same as
  // today. In debug builds we use the debug provider; in release we use
  // the platform attestation providers.
  unawaited(
    () async {
      try {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: kReleaseMode
              ? const AndroidPlayIntegrityProvider()
              : const AndroidDebugProvider(),
          providerApple: kReleaseMode
              ? const AppleDeviceCheckProvider()
              : const AppleDebugProvider(),
        );
        debugPrint('App Check initialized (release=$kReleaseMode)');
      } catch (e, st) {
        debugPrint('App Check init failed (non-fatal): $e');
        if (kReleaseMode) {
          unawaited(
            FirebaseCrashlytics.instance
                .recordError(e, st, reason: 'AppCheck activate failed'),
          );
        }
      }
    }(),
  );

  // Firebase Analytics — collection is RELEASE ONLY. Debug sessions
  // would otherwise pollute the production GA4 property with dev
  // events. The Analytics helper itself ([Analytics._log]) also
  // short-circuits in debug, but disabling collection at the SDK
  // level is the belt-and-braces guarantee.
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(kReleaseMode);

  // Avatar catalog — must initialise BEFORE UserService because the
  // handle generator (called by UserService.init for new users)
  // consults [AvatarService.defaults] to pick a random avatar. If
  // the fetch fails, the service falls back to a hardcoded 12-animal
  // pool, so the welcome card still has options offline.
  await AvatarService.instance.init();

  // User identity — Firebase Anonymous Auth + load-or-create the
  // matching `users/{uid}` Firestore profile. Best-effort: if the
  // network is down or App Check rejects, [UserService.init] swallows
  // the error and we proceed with no profile (the home screen's
  // welcome card simply won't appear and online play would be
  // unavailable until the next launch).
  await UserService.instance.init();

  if (kReleaseMode) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    PlatformDispatcher.instance.onError =
        (final Object error, final StackTrace stack) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          return true;
        };
  } else {
    // Symmetric explicit-off for Crashlytics in debug. Without this,
    // a debug crash CAN still upload (depending on cached state) —
    // setting it explicitly to false is the clean answer.
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
  }

  // Boot AdMob (test or prod ids depending on the USE_TEST_ADS define).
  // Pre-loads the first interstitial so the post-game-over slot is fast.
  unawaited(AdManager.instance.init());

  runApp(MultiBlocProvider(providers: getAppProviders(), child: const MyApp()));
}
