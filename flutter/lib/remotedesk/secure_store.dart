import 'package:flutter/services.dart';

/// Access to credential storage backed by the Android Keystore.
///
/// The platform side keeps an AES-256-GCM key in `AndroidKeyStore` and only the
/// ciphertext is written to shared preferences, so passwords never touch disk in
/// plaintext and never end up in logs.
class SecureStore {
  static const MethodChannel _channel = MethodChannel('remotedesk/secure');

  static Future<bool> put(String key, String value) async {
    try {
      final ok = await _channel.invokeMethod<bool>('put', {
        'key': key,
        'value': value,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrintSecure('put failed: ${e.code}');
      return false;
    }
  }

  static Future<String?> get(String key) async {
    try {
      return await _channel.invokeMethod<String>('get', {'key': key});
    } on PlatformException catch (e) {
      debugPrintSecure('get failed: ${e.code}');
      return null;
    }
  }

  static Future<bool> delete(String key) async {
    try {
      final ok = await _channel.invokeMethod<bool>('delete', {'key': key});
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrintSecure('delete failed: ${e.code}');
      return false;
    }
  }

  /// Never log secret material itself, only failure codes.
  static void debugPrintSecure(String message) {
    // ignore: avoid_print
    assert(() {
      // ignore: avoid_print
      print('[SecureStore] $message');
      return true;
    }());
  }
}
