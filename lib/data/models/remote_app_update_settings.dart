/// Mirrors a single document in the Firestore `app_update_settings`
/// collection. Editor-curated config that drives the in-app update
/// prompt — same structure as our other `app_settings` / `faqs`
/// remote-config docs.
///
/// Schema (all fields nullable in transit; defaults applied here):
///   • app_store_latest_version    (String) — iOS reference version
///   • app_store_link              (String) — iTunes / App Store URL
///   • play_store_version          (String) — Android reference version
///   • play_store_link             (String) — Play Store URL
///   • title                       (String) — popup headline
///   • message                     (String) — popup body
///   • ok_btn_text                 (String) — primary CTA label
///   • cancel_btn_text             (String) — dismiss label (hidden when forced)
///   • is_display_popup_in_android (bool)   — Android master switch
///   • is_display_popup_in_iOS     (bool)   — iOS master switch
///   • is_force_update_enable      (bool)   — when true, hide cancel and
///                                            keep popup up after dismiss
class RemoteAppUpdateSettings {
  const RemoteAppUpdateSettings({
    required this.appStoreLatestVersion,
    required this.appStoreLink,
    required this.playStoreVersion,
    required this.playStoreLink,
    required this.title,
    required this.message,
    required this.okBtnText,
    required this.cancelBtnText,
    required this.isDisplayPopupInAndroid,
    required this.isDisplayPopupInIOS,
    required this.isForceUpdateEnable,
  });

  final String appStoreLatestVersion;
  final String appStoreLink;
  final String playStoreVersion;
  final String playStoreLink;
  final String title;
  final String message;
  final String okBtnText;
  final String cancelBtnText;
  final bool isDisplayPopupInAndroid;
  final bool isDisplayPopupInIOS;
  final bool isForceUpdateEnable;

  // ── Hardcoded fallback copy ─────────────────────────────────────────
  // Used when the doc is missing a field or the fetch fails entirely.
  static const String _defaultTitle = 'Update Available';
  static const String _defaultMessage =
      'A newer version of the app is available. Please update to access '
      'the latest features and ensure a smooth and improved experience.';
  static const String _defaultOk = 'Update';
  static const String _defaultCancel = 'Maybe later';

  /// Bulletproof factory — every field has a fallback so a malformed
  /// remote doc can never crash the app at parse time.
  factory RemoteAppUpdateSettings.fromMap(
      final Map<String, dynamic> data) {
    return RemoteAppUpdateSettings(
      appStoreLatestVersion:
          (data['app_store_latest_version'] as String?) ?? '',
      appStoreLink: (data['app_store_link'] as String?) ?? '',
      playStoreVersion: (data['play_store_version'] as String?) ?? '',
      playStoreLink: (data['play_store_link'] as String?) ?? '',
      title: (data['title'] as String?) ?? _defaultTitle,
      message: (data['message'] as String?) ?? _defaultMessage,
      okBtnText: (data['ok_btn_text'] as String?) ?? _defaultOk,
      cancelBtnText: (data['cancel_btn_text'] as String?) ?? _defaultCancel,
      isDisplayPopupInAndroid:
          (data['is_display_popup_in_android'] as bool?) ?? false,
      isDisplayPopupInIOS:
          (data['is_display_popup_in_iOS'] as bool?) ?? false,
      isForceUpdateEnable:
          (data['is_force_update_enable'] as bool?) ?? false,
    );
  }
}
