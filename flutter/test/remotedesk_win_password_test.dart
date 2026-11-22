import 'package:flutter_hbb/remotedesk/device_store.dart';
import 'package:flutter_hbb/remotedesk/win_password.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('windows logon password key', () {
    test('lives in its own per-device namespace', () {
      expect(rdWinPasswordKey('123456789'), 'rd_winpw_123456789');
      // Must not collide with the session access password key.
      expect(rdWinPasswordKey('123456789') == 'rd_pw_123456789', isFalse);
    });
  });

  group('password validation', () {
    test('accepts printable ASCII', () {
      expect(rdIsAsciiPassword('Passw0rd!~'), isTrue);
      expect(rdIsAsciiPassword(' '), isTrue);
      expect(rdValidateWinPassword('Passw0rd!~'), isNull);
    });

    test('rejects an empty password', () {
      expect(rdIsAsciiPassword(''), isFalse);
      expect(rdValidateWinPassword(''), '请输入电脑登录密码');
    });

    test('rejects non-ASCII text', () {
      expect(rdIsAsciiPassword('密码'), isFalse);
      expect(rdIsAsciiPassword('pässword'), isFalse);
      expect(rdValidateWinPassword('密码'), isNotNull);
    });

    test('rejects control characters', () {
      expect(rdIsAsciiPassword('a\tb'), isFalse);
      expect(rdIsAsciiPassword('a\nb'), isFalse);
    });
  });

  group('RdDevice JSON', () {
    test('round-trips winPasswordRef', () {
      final device = RdDevice(id: '111222333', name: 'pc', winPasswordRef: true);
      final back = RdDevice.fromJson(device.toJson());
      expect(back.id, '111222333');
      expect(back.winPasswordRef, isTrue);
    });

    test('keeps the old default when the field is absent', () {
      final back = RdDevice.fromJson({'id': '111222333', 'name': 'pc'});
      expect(back.winPasswordRef, isFalse);
    });

    test('never writes a password into the device JSON', () {
      final device = RdDevice(id: '111222333', name: 'pc', winPasswordRef: true);
      final json = device.toJson();
      expect(json.containsKey('winPassword'), isFalse);
      expect(json['winPasswordRef'], isTrue);
    });
  });
}
