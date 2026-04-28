import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the Mini Kickers product on Amazon. Tries the Amazon app first
/// via the `com.amazon.mobile.shopping.web` URL scheme on iOS or the
/// `com.amazon.mShop.android.shopping` package intent on Android. Falls back
/// to the standard web URL in the system browser if the app isn't installed.
class AmazonLauncher {
  AmazonLauncher._();

  static const String _productAsin = 'B0F9LD5BB2';
  static const String _webUrl =
      'https://www.amazon.in/Mini-Kickers-Football-Batteries-Travel-Friendly/dp/$_productAsin';

  // iOS Amazon app URL scheme — opens the app and routes to a URL inside it.
  static const String _iosAppUrl =
      'com.amazon.mobile.shopping://www.amazon.in/dp/$_productAsin';

  // Android Amazon app deep link via `amzn://` scheme.
  static const String _androidAppUrl = 'amzn://www.amazon.in/dp/$_productAsin';

  static Future<void> openProductPage() async {
    final List<String> candidates = <String>[
      if (Platform.isIOS) _iosAppUrl,
      if (Platform.isAndroid) _androidAppUrl,
      _webUrl,
    ];

    for (final String urlStr in candidates) {
      final Uri uri = Uri.parse(urlStr);
      try {
        final bool ok = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (ok) return;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('AmazonLauncher: $urlStr failed → $e');
        }
      }
    }

    // Final fallback — try inside an in-app webview.
    try {
      await launchUrl(
        Uri.parse(_webUrl),
        mode: LaunchMode.platformDefault,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('AmazonLauncher: web fallback failed → $e');
    }
  }
}
