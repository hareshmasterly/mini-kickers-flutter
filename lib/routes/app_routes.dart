import 'package:flutter/material.dart';
import 'package:mini_kickers/routes/routes_name.dart';
import 'package:mini_kickers/views/game/game_screen.dart';
import 'package:mini_kickers/views/guide/guide_screen.dart';
import 'package:mini_kickers/views/home/home_screen.dart';
import 'package:mini_kickers/views/settings/settings_screen.dart';
import 'package:mini_kickers/views/splash/splash_screen.dart';

class AppRoutes {
  AppRoutes._();

  static Map<String, WidgetBuilder> getRoutes() => <String, WidgetBuilder>{
        RouteName.splashScreen: (final BuildContext _) => const SplashScreen(),
        RouteName.homeScreen: (final BuildContext _) => const HomeScreen(),
        RouteName.gameScreen: (final BuildContext _) => const GameScreen(),
        RouteName.settingsScreen: (final BuildContext _) =>
            const SettingsScreen(),
        RouteName.guideScreen: (final BuildContext _) => const GuideScreen(),
      };
}
