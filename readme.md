# Mini Kickers

A 2-player Flutter board game (digital version of the physical Mini Kickers
football game). Landscape-only, anonymous (no auth), kid-friendly, with
Firestore-backed remote config and AdMob monetization.

---

## Local development

```bash
# Install dependencies
flutter pub get

# Generate freezed / build_runner code
dart run build_runner build --delete-conflicting-outputs

# Clean dart caches if anything goes weird
flutter pub cache clean
```

### Run a flavor

```bash
# Staging (default if --flavor omitted, but always pass --dart-define)
flutter run --flavor staging --dart-define=FLAVOR=staging

# Production
flutter run --flavor prod --dart-define=FLAVOR=prod
```

`FLAVOR` is read by `String.fromEnvironment` in `lib/main.dart` and influences
runtime behavior (analytics tagging, ad cadence, etc). Always pass it.

### Re-sync Xcode debug config to a flavor (after a Flutter or Xcode change)

```bash
flutter build ios --config-only --release --flavor staging --dart-define=FLAVOR=staging
flutter build ios --config-only --release --flavor prod --dart-define=FLAVOR=prod
```

### Regenerate launcher icons (when assets/icon/* changes)

```bash
dart run flutter_launcher_icons
```

### Regenerate native splash (when assets/png/img_splash_*.png changes)

`flutter_native_splash` is normally **commented out** in `pubspec.yaml` because
its plugin registration breaks the Android build. To regenerate splash assets:

```bash
# 1. Uncomment `flutter_native_splash: ^2.4.6` in pubspec.yaml dev_dependencies
# 2. Run the generator
dart run flutter_native_splash:create
# 3. Re-comment the line in pubspec.yaml
# 4. Clean rebuild
flutter clean && flutter pub get
```

---

## Production release

### Prerequisites

1. **Keystore in place.** `android/keystore/mini_kickers.jks` and
   `android/keystore/keystore.properties` must both exist on the build
   machine. They are gitignored — see `keystore.properties.example` for the
   expected shape. Get them from the secure team vault, **never** check
   them in.

2. **Firebase project configured.** Both staging and prod currently share
   the same applicationId (`com.masterly.minikickers`) and therefore share
   one Firebase project. The `google-services.json` files under
   `android/app/src/prod/` and `android/app/src/staging/` are identical
   and reference that single package. Trade-offs of this setup:
    - Staging and prod **cannot** be installed side-by-side on a device.
    - Staging Analytics events land in the same Firebase project as prod.
      When you outgrow this, suffix the staging applicationId in
      `android/app/flavorizr.gradle.kts`, register the new id in Firebase,
      and drop the new `google-services.json` under `android/app/src/staging/`.

3. **App Check** is wired in `lib/main.dart` and uses Play Integrity on
   Android / DeviceCheck on iOS in release builds. Enable both providers
   in the Firebase Console → App Check tab before flipping to release.
   Failures are logged to Crashlytics but **do not** crash the app.

4. **Ad cadence** is remote-driven via the `app_settings` Firestore doc.
   Ads ship with `USE_TEST_ADS=true` (the default) so even if the master
   ad flag is enabled in Firestore, only Google's test ads will load.
   Before promoting to real ads:
    - Replace placeholder unit IDs in `lib/utils/ad_manager.dart` with real
      AdMob IDs.
    - Build with `--dart-define=USE_TEST_ADS=false`.
    - Flip the master ad flag in Firestore.

### Build commands

```bash
# Production APK (sideload / direct install)
flutter build apk --release --flavor prod --dart-define=FLAVOR=prod

# Production App Bundle (Play Store upload)
flutter build appbundle --release --flavor prod --dart-define=FLAVOR=prod

# iOS production (then archive in Xcode)
flutter build ios --release --flavor prod --dart-define=FLAVOR=prod
```

Outputs:

- `build/app/outputs/flutter-apk/app-prod-release.apk`
- `build/app/outputs/bundle/prodRelease/app-prod-release.aab`

### Verify the AAB before upload

```bash
# Find apksigner inside Android SDK build-tools
APKSIGNER=$(find $ANDROID_HOME/build-tools -name apksigner | sort -V | tail -1)

# Confirm the prod keystore signed it (look for CN=Masterly Solutions)
"$APKSIGNER" verify --print-certs build/app/outputs/flutter-apk/app-prod-release.apk
```

If the cert shows `CN=Android Debug`, the build picked up the debug fallback
— `keystore.properties` is missing or unreadable.

### Staging APK

```bash
flutter build apk --release --flavor staging --dart-define=FLAVOR=staging
```

Staging uses the same release keystore **and** the same applicationId as
prod (`com.masterly.minikickers`), so installing the staging build over
a prod build (or vice-versa) overwrites it. The only differences today
are the display name ("Mini Kickers Staging") and the runtime `FLAVOR`
dart-define, which the app uses to tag analytics + tweak ad cadence.

### Change Android package name (rare — full rebrand)

```bash
flutter pub run change_app_package_name:main com.new.package.name
```

---

## Pre-launch checklist (Play Store + App Store)

- [ ] Keystore + `keystore.properties` on build machine, **not** in git
- [ ] App Check enabled in Firebase Console (Play Integrity + DeviceCheck)
- [ ] Privacy Policy URL hosted (required for kids/families category)
- [ ] Play Console Data Safety form completed (Firestore reads, Crashlytics
  crash data, Analytics, AdMob SDK presence)
- [ ] App Store encryption questionnaire answered
  (`ITSAppUsesNonExemptEncryption` in `Info.plist`)
- [ ] Crashlytics tested — force a crash in a release build, confirm it
  lands in the console
- [ ] Real device QA: smallest landscape phone (iPhone SE), large tablet
  (iPad Pro), one Android with a notch
- [ ] Bumped `version:` in `pubspec.yaml` (current is `1.0.0+1`)
