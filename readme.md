# mini_kickers

A new Flutter project.

### To Generate Assets and freezed class

- flutter pub run build_runner build --delete-conflicting-outputs
- dart run build_runner build --delete-conflicting-outputs

#remove cache file

- flutter pub cache clean

**Add this in flavor configuration**
Flavor staging -> --flavor staging --dart-define=FLAVOR=staging
Flavor prod -> --flavor prod --dart-define=FLAVOR=prod

**To update debug config to prod (iOS)**
flutter build ios --config-only --release --flavor staging --dart-define=FLAVOR=staging
flutter build ios --config-only --release --flavor prod --dart-define=FLAVOR=prod

**To update debug config to prod (Android)**
flutter build apk --release --flavor staging --dart-define=FLAVOR=staging

**Change Package name**
flutter pub run change_app_package_name:main com.new.package.name
