import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:mini_kickers/data/models/remote_app_update_settings.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Result of an update check.
///
/// • [shouldShow] — true if the popup should be shown to the user.
/// • [settings]   — the remote doc that drove the decision (so the UI
///                   can read title/message/buttons/store link).
/// • [storeUrl]   — the platform-specific store URL pre-resolved from
///                   [settings] (so the UI doesn't have to do platform
///                   branching).
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.shouldShow,
    required this.settings,
    required this.storeUrl,
  });

  final bool shouldShow;
  final RemoteAppUpdateSettings? settings;
  final String storeUrl;

  /// Convenience: when no popup is needed.
  static const UpdateCheckResult none = UpdateCheckResult(
    shouldShow: false,
    settings: null,
    storeUrl: '',
  );
}

/// Fetches the `app_update_settings` doc from Firestore on demand and
/// decides whether the in-app update prompt should be shown.
///
/// Decision matrix:
///   1. Platform master switch must be ON for current platform
///      (`is_display_popup_in_android` on Android,
///       `is_display_popup_in_iOS` on iOS).
///   2. The platform's reference version (`play_store_version` /
///      `app_store_latest_version`) must be GREATER than the running
///      app version (`PackageInfo.version`).
///   3. Once the user dismisses an OPTIONAL update, we don't bother
///      them again until app restart (one-prompt-per-session). Force
///      updates IGNORE this rule — they're shown every check.
///
/// The check is best-effort: any error (network down, doc missing,
/// malformed data) silently returns [UpdateCheckResult.none]. App
/// must NEVER fail to launch because of an update check.
class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  static const String _collection = 'app_update_settings';

  /// True after a non-force prompt has been dismissed in this session.
  /// Reset on app restart (since the field lives on the singleton, not
  /// in SharedPreferences). Force updates ignore this.
  bool _dismissedThisSession = false;

  /// Mark the optional update as dismissed for this session. Call this
  /// from the dialog's "Maybe later" path.
  void markDismissed() => _dismissedThisSession = true;

  /// Performs the fetch + version comparison. Returns the decision.
  ///
  /// Wrapped in a top-level try/catch so a Firestore failure or App
  /// Check rejection silently no-ops; the user just doesn't see the
  /// prompt.
  Future<UpdateCheckResult> check() async {
    try {
      // 1. Read app version from native package metadata (pubspec
      //    `version: 1.0.0+N` exposes "1.0.0" here).
      final PackageInfo info = await PackageInfo.fromPlatform();
      final String currentVersion = info.version;
      debugPrint('currentVersion--> $currentVersion');

      // 2. Fetch the (single) update-settings doc. We use limit(1)
      //    rather than a fixed doc id so the editor can keep using
      //    Firestore's auto-id without us hardcoding it.
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection(_collection)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return UpdateCheckResult.none;

      final RemoteAppUpdateSettings settings = RemoteAppUpdateSettings.fromMap(
        snap.docs.first.data(),
      );

      // 3. Platform master switch.
      final bool platformEnabled = Platform.isIOS
          ? settings.isDisplayPopupInIOS
          : settings.isDisplayPopupInAndroid;
      if (!platformEnabled) return UpdateCheckResult.none;

      // 4. Compare versions.
      final String latestVersion = Platform.isIOS
          ? settings.appStoreLatestVersion
          : settings.playStoreVersion;
      if (latestVersion.isEmpty) return UpdateCheckResult.none;
      if (_compareVersions(currentVersion, latestVersion) >= 0) {
        // Already on latest (or newer — devs running unreleased
        // builds). No prompt.
        return UpdateCheckResult.none;
      }

      // 5. Once-per-session dismissal (only for OPTIONAL updates).
      if (_dismissedThisSession && !settings.isForceUpdateEnable) {
        return UpdateCheckResult.none;
      }

      // 6. Resolve the store URL we want the "Update" button to launch.
      final String storeUrl = Platform.isIOS
          ? settings.appStoreLink
          : settings.playStoreLink;
      if (storeUrl.isEmpty) {
        // Editor enabled the popup but didn't fill in a store link —
        // pointless to show a popup with a broken button.
        if (kDebugMode) {
          debugPrint(
            'AppUpdateService: skipped — popup enabled but no store URL',
          );
        }
        return UpdateCheckResult.none;
      }

      if (kDebugMode) {
        debugPrint(
          'AppUpdateService: showing popup '
          '(current=$currentVersion latest=$latestVersion '
          'force=${settings.isForceUpdateEnable})',
        );
      }
      return UpdateCheckResult(
        shouldShow: true,
        settings: settings,
        storeUrl: storeUrl,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('AppUpdateService: check failed (non-fatal) → $e\n$st');
      }
      return UpdateCheckResult.none;
    }
  }

  /// Semver-ish comparison: splits on '.', pads the shorter side with
  /// zeros, compares numeric parts left-to-right. Non-numeric parts
  /// are treated as 0 so weird inputs ("1.0-beta") don't crash.
  ///
  /// Returns -1 if [a] < [b], 0 if equal, 1 if [a] > [b].
  int _compareVersions(final String a, final String b) {
    final List<int> aParts = a
        .split('.')
        .map((final String p) => int.tryParse(p) ?? 0)
        .toList();
    final List<int> bParts = b
        .split('.')
        .map((final String p) => int.tryParse(p) ?? 0)
        .toList();
    final int len = max(aParts.length, bParts.length);
    for (int i = 0; i < len; i++) {
      final int av = i < aParts.length ? aParts[i] : 0;
      final int bv = i < bParts.length ? bParts[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }
}
