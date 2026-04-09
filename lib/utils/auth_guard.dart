import 'package:flutter/foundation.dart';

class AuthGuard {
  /// Global flag to prevent lifecycle loops during biometric prompts
  static bool isAuthenticating = false;
  static DateTime lastActiveAt = DateTime.now();
  static final ValueNotifier<bool> isLocked = ValueNotifier<bool>(false);
}
