import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/remotedesk/biometric.dart';
import 'package:flutter_hbb/remotedesk/device_store.dart';
import 'package:flutter_hbb/remotedesk/win_password.dart';

/// Set while one unlock attempt is running, so a double tap cannot start a
/// second biometric prompt.
bool _rdUnlockInFlight = false;

/// Unlocks the controlled PC from this device:
/// confirmation -> local verification -> Keystore decrypt -> type the password.
///
/// The typing is upstream's `input_os_password` path (FFI
/// `sessionInputOsPassword`): it clicks once to bring up the password box, sends
/// the password as a Legacy keyboard sequence and presses Enter. Every key event
/// on the server side first switches its thread onto the current input desktop
/// (`try_change_desktop` in `src/server/input_service.rs`), which is what makes
/// it land on the logon screen instead of the desktop of the logged-on user.
///
/// That local path has no peer-side "am I really at the logon screen" check —
/// the `OSLogin` message does, this one does not — so the user confirms first and
/// a mis-tap cannot type the password into a normal desktop window.
///
/// On any failure (no saved password, no biometrics, cancelled, non-ASCII) the
/// user is told to type it manually and nothing is retried.
Future<void> rdUnlockLockedPeer({
  required BuildContext context,
  required SessionID sessionId,
  required String deviceId,
}) async {
  if (_rdUnlockInFlight) return;
  _rdUnlockInFlight = true;
  try {
    if (!await _confirmOnLogonScreen(context)) return;
    final password = await RdWinPassword.load(deviceId);
    if (password == null) {
      showToast('这台电脑没有保存登录密码，请手动在画面上输入密码');
      return;
    }
    final err = rdValidateWinPassword(password);
    if (err != null) {
      showToast(err);
      return;
    }
    final kind = await RdBiometric.canAuthenticate();
    if (kind == RdBiometric.kindNone) {
      showToast('本机没有可用的指纹或锁屏验证，请手动在画面上输入密码');
      return;
    }
    final verified = await RdBiometric.authenticate();
    if (!verified) {
      showToast('验证未通过，请手动在画面上输入密码');
      return;
    }
    bind.sessionInputOsPassword(sessionId: sessionId, value: password);
    showToast('已发送登录密码');
  } finally {
    _rdUnlockInFlight = false;
  }
}

Future<bool> _confirmOnLogonScreen(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('发送登录密码'),
      content: const Text('只有对端画面停在 Windows 登录/锁屏界面时才继续。'
          '确认后需要指纹验证，通过后把保存的密码逐字符发送到对端。'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消')),
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('继续')),
      ],
    ),
  );
  return ok == true;
}

/// 「指纹解锁」 for the remote session canvas.
///
/// Only shown for a device that has a saved logon password. There is no
/// reliable "the peer is at its lock screen" signal in the Flutter layer, so the
/// button stays available for the whole session and the user presses it when the
/// picture shows the Windows logon screen.
class RdUnlockButton extends StatelessWidget {
  final SessionID sessionId;
  final String deviceId;

  const RdUnlockButton({
    Key? key,
    required this.sessionId,
    required this.deviceId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final device = RdDeviceStore.instance.byId(deviceId);
    if (device == null || !device.winPasswordRef) return const SizedBox.shrink();
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => rdUnlockLockedPeer(
          context: context,
          sessionId: sessionId,
          deviceId: deviceId,
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fingerprint, size: 18, color: Colors.white),
              SizedBox(width: 4),
              Text('指纹解锁',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
