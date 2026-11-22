import 'package:flutter_hbb/remotedesk/secure_store.dart';

/// Keystore key for the Windows logon password of [deviceId].
///
/// A separate namespace from the session access password (`rd_pw_<id>`): this
/// value is the OS account password of the controlled PC and is only ever
/// handed to the input channel after a local user verification.
String rdWinPasswordKey(String deviceId) => 'rd_winpw_$deviceId';

/// Whether [password] can be typed by the remote keyboard as plain text.
///
/// RustDesk sends the logon password as a Legacy keyboard "seq"
/// (`input_os_password` in `src/client.rs`), which maps every character onto a
/// virtual key. Only printable ASCII has a stable mapping there, so anything
/// else is refused up front instead of being typed as a wrong password.
bool rdIsAsciiPassword(String password) {
  if (password.isEmpty) return false;
  for (final rune in password.runes) {
    if (rune < 0x20 || rune > 0x7e) return false;
  }
  return true;
}

/// Validation message for [password], or null when it can be used.
String? rdValidateWinPassword(String password) {
  if (password.isEmpty) return '请输入电脑登录密码';
  if (!rdIsAsciiPassword(password)) {
    return '当前只支持 ASCII 密码（字母、数字、英文符号）；含中文或其它字符时请手动在画面上输入';
  }
  return null;
}

/// The Windows logon password, encrypted by the Android Keystore.
///
/// Nothing here writes the password anywhere else: [SecureStore] keeps the
/// AES-GCM key in `AndroidKeyStore` and only ciphertext in shared preferences.
/// No method logs the value, not even in debug builds.
class RdWinPassword {
  static Future<void> save(String deviceId, String password) async {
    if (deviceId.isEmpty || password.isEmpty) return;
    await SecureStore.put(rdWinPasswordKey(deviceId), password);
  }

  static Future<String?> load(String deviceId) async {
    if (deviceId.isEmpty) return null;
    final value = await SecureStore.get(rdWinPasswordKey(deviceId));
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static Future<bool> has(String deviceId) async =>
      (await load(deviceId)) != null;

  static Future<void> delete(String deviceId) async {
    if (deviceId.isEmpty) return;
    await SecureStore.delete(rdWinPasswordKey(deviceId));
  }
}
