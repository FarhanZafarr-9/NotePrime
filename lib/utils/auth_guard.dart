import 'package:flutter/foundation.dart';

/// The three distinct privacy states the app can be in.
///
/// [visible]  – normal UI, nothing hidden.
/// [obscured] – transient privacy blur (e.g. screenshot protection while the
///              app is in the background). No authentication is required and
///              it is automatically removed on resume.
/// [locked]   – a real lockout that requires authentication before the user
///              can continue.
enum ShieldState { visible, obscured, locked }

class AuthGuard {
  /// Global flag to prevent lifecycle loops during biometric prompts
  static bool isAuthenticating = false;
  static DateTime lastActiveAt = DateTime.now();

  /// Single source of truth for the privacy overlay shown on top of the UI.
  static final ValueNotifier<ShieldState> shield =
      ValueNotifier<ShieldState>(ShieldState.visible);

  /// Whether a real authentication is currently required.
  static bool get isLocked => shield.value == ShieldState.locked;

  /// Whether a transient privacy blur is currently shown.
  static bool get isObscured => shield.value == ShieldState.obscured;
}
