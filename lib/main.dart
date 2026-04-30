import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mini_kickers/app/my_app.dart';
import 'package:mini_kickers/data/services/faq_service.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
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

  if (kReleaseMode) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    PlatformDispatcher.instance.onError =
        (final Object error, final StackTrace stack) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          return true;
        };
  }

  // Boot AdMob (test or prod ids depending on the USE_TEST_ADS define).
  // Pre-loads the first interstitial so the post-game-over slot is fast.
  unawaited(AdManager.instance.init());

  runApp(MultiBlocProvider(providers: getAppProviders(), child: const MyApp()));
}
