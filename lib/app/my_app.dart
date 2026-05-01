import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/routes/app_routes.dart';
import 'package:mini_kickers/routes/routes_name.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/utils/ad_manager.dart';
import 'package:mini_kickers/utils/flavors.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(final BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: FlavorConfig.title,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryColor,
          brightness: Brightness.dark,
        ),
        textTheme: AppFonts.dmSansTextTheme(ThemeData.dark().textTheme),
      ),
      initialRoute: RouteName.splashScreen,
      routes: AppRoutes.getRoutes(),
      // Counts every screen push for the "every-5-navigations" interstitial.
      // See [AdManager.recordNavigation] and [_AdNavigatorObserver].
      navigatorObservers: <NavigatorObserver>[
        _AdNavigatorObserver(),
      ],
    );
  }
}

/// Forwards each `didPush` to [AdManager], which fires an interstitial
/// every Nth navigation. Skips anonymous routes (modal dialogs, etc.)
/// so opening the Quit dialog doesn't count as a navigation.
class _AdNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(final Route<dynamic> route, final Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PageRoute<dynamic>) {
      AdManager.instance.recordNavigation();
    }
  }
}
