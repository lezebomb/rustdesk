import 'package:flutter_hbb/remotedesk/direct_addr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('checkDirectAddr', () {
    test('accepts the bare IPv6 form verified on a real device', () {
      const addr = '2001:da8:8002:6bd1:a84a:df91:f9ff:2dbd';
      final r = checkDirectAddr(addr);
      expect(r.ok, isTrue);
      expect(r.value, addr);
      expect(r.fixNote, isNull);
    });

    test('strips brackets so the value can take the direct path', () {
      final r = checkDirectAddr('[2001:db8::1]:21118');
      expect(r.ok, isTrue);
      // A bare "v6:port" is not a valid upstream address, so the port goes away
      // with the brackets and the peer's direct-access-port is used.
      expect(r.value, '2001:db8::1');
      expect(r.fixNote, contains('去掉方括号'));
      expect(r.fixNote, contains('21118'));
    });

    test('accepts IPv4, host:port and empty, rejects everything else', () {
      expect(checkDirectAddr('192.168.1.20').value, '192.168.1.20');
      expect(checkDirectAddr('192.168.1.20:21118').value, '192.168.1.20:21118');
      expect(checkDirectAddr('pc.lan:21118').value, 'pc.lan:21118');
      expect(checkDirectAddr('  ').value, '');
      expect(checkDirectAddr('localhost:21118').ok, isFalse);
      expect(checkDirectAddr('999.1.1.1').ok, isFalse);
      expect(checkDirectAddr('2001:db8::1:21118:7').ok, isFalse);
    });
  });
}
