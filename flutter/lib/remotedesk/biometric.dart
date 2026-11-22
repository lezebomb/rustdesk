import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Local user verification in front of the saved Windows logon password.
///
/// Backed by the platform channel `remotedesk/biometric`. The Android side uses
/// the framework `android.hardware.biometrics.BiometricPrompt` when the device
/// has an enrolled biometric, and falls back to
/// `KeyguardManager.createConfirmDeviceCredentialIntent` (device PIN / pattern /
/// password) when it does not. `androidx.biometric` is not a dependency of this
/// project and is not added for this feature.
class RdBiometric {
  static const MethodChannel _channel = MethodChannel('remotedesk/biometric');

  /// Fingerprint or face is enrolled and usable.
  static const String kindBiometric = 'biometric';

  /// No usable biometric, but the device is secured, so PIN/pattern/password
  /// can still verify the user.
  static const String kindCredential = 'credential';

  /// Nothing can gate the password on this device.
  static const String kindNone = 'none';

  /// Which verification the platform would offer right now.
  static Future<String> canAuthenticate() async {
    try {
      final kind = await _channel.invokeMethod<String>('canAuthenticate');
      if (kind == kindBiometric || kind == kindCredential) return kind;
      return kindNone;
    } on PlatformException catch (e) {
      debugPrintBiometric('canAuthenticate failed: ${e.code}');
      return kindNone;
    } on MissingPluginException {
      return kindNone;
    }
  }

  /// Runs the verification once. Returns false when it was cancelled, failed,
  /// or is not available; callers must not retry on their own.
  static Future<bool> authenticate({String reason = '验证指纹以解锁远程电脑'}) async {
    try {
      final ok = await _channel
          .invokeMethod<bool>('authenticate', {'reason': reason});
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrintBiometric('authenticate failed: ${e.code}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Never log secrets or prompts, only failure codes.
  static void debugPrintBiometric(String message) {
    // ignore: avoid_print
    assert(() {
      // ignore: avoid_print
      print('[RdBiometric] $message');
      return true;
    }());
  }
}
