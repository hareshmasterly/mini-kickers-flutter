import 'package:mini_kickers/main.dart';

class FlavorConfig {
  FlavorConfig._();

  static bool get isStaging => currentFlavor == 'staging';

  static bool get isProd => currentFlavor == 'prod';

  static String get title {
    if (isStaging) {
      return 'Mini Kickers Staging';
    }
    return 'Mini Kickers';
  }
}
