# Mini Kickers — release ProGuard / R8 keep rules.
#
# These rules are layered on top of `proguard-android-optimize.txt` (default
# Android rules) which is applied first via `proguardFiles(...)` in
# build.gradle.kts. Add app-specific keep rules here.
#
# Test before each release with:
#   flutter build apk --release --flavor prod --dart-define=FLAVOR=prod
#   flutter build appbundle --release --flavor prod --dart-define=FLAVOR=prod
# and verify the app launches + Firestore reads + crash reporting work.

# ----- Flutter -----
# Flutter ships its own consumer rules, but we keep these for safety.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ----- Firebase (analytics, crashlytics, app check, firestore) -----
# Firebase libraries ship with consumer ProGuard rules but reflection on
# generated PII proto classes occasionally still gets stripped. Keep these
# explicitly to be safe.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Crashlytics: keep stack traces readable in the console. Without this, line
# numbers map to obfuscated names instead of source lines.
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# ----- AdMob (google_mobile_ads) -----
# AdMob SDK uses reflection internally for mediation adapters and ad formats.
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# ----- AudioPlayers -----
# Reflection on platform channel handlers.
-keep class xyz.luan.audioplayers.** { *; }

# ----- Vibration plugin -----
-keep class com.benjaminabel.vibration.** { *; }

# ----- Generic: keep annotations and JNI -----
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-keepclasseswithmembernames class * {
    native <methods>;
}
