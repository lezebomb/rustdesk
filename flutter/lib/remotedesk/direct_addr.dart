/// Validation and normalisation for the optional "直连地址" field.
///
/// The value is handed to `connect()` instead of the peer id, so it has to look
/// like something the Rust side recognises *before* the rendezvous path:
/// `src/common.rs:3079` `is_direct_ip_access` → `src/client.rs:440-467`
/// `connect_tcp_local(check_port(peer, RELAY_PORT + 1))`.
///
/// Two upstream details shape the rules below:
///
/// * `libs/hbb_common/src/lib.rs:398-406` `is_ipv6_str` accepts a *bare* IPv6
///   address, or a *bracketed* one only when a port is attached. A lone
///   `[2001:db8::1]` matches neither branch, so keeping the brackets would send
///   the connection back through signalling: they are stripped here.
/// * `libs/hbb_common/src/socket_client.rs:16-28` `check_port` appends the
///   default direct access port to a bare IPv6, but leaves alone any value that
///   already contains a colon. A bracket-stripped `[v6]:port` would therefore be
///   read as a 9-group address and never reach the peer, so the port is dropped
///   and the peer's `direct-access-port` (default 21118) is used instead.
class DirectAddrCheck {
  /// Value to persist; empty means "no direct address, connect by ID".
  final String value;

  /// User-facing rejection reason, null when the input was accepted.
  final String? error;

  /// User-facing note describing an automatic correction, null when the input
  /// was stored exactly as typed.
  final String? fixNote;

  const DirectAddrCheck._(this.value, this.error, this.fixNote);

  bool get ok => error == null;
}

const _errEmptyBrackets = '方括号格式不对，应形如 [2001:db8::1] 或 [2001:db8::1]:21118';
const _errPort = '端口需在 1-65535 之间';
const _errFormat = '不是合法的直连地址：支持 IPv4、裸 IPv6、[IPv6]:端口 或 域名:端口';
const _errLocalName = '不带点的主机名（如 localhost:21118）上游不会走直连，请填 IP 或带点的域名';

final _reBracketed = RegExp(r'^\[([0-9A-Fa-f:.]+)\](?::(\d{1,5}))?$');
final _reIpv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?::(\d{1,5}))?$');
// Mirrors `is_domain_port_str` (`libs/hbb_common/src/lib.rs:414-425`): the host
// needs at least one dot and the port is mandatory.
final _reHostPort =
    RegExp(r'^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
        r'(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+:(\d{1,5})$');
final _reLocalNamePort = RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]*:\d{1,5}$');

/// Normalises one raw field value. Never throws: an unusable value comes back
/// as [DirectAddrCheck.error] instead of being silently dropped.
DirectAddrCheck checkDirectAddr(String raw) {
  var s = raw.trim().replaceAll(' ', '');
  if (s.isEmpty) {
    return const DirectAddrCheck._('', null, null);
  }

  String? fixNote;
  if (s.startsWith('[') || s.contains(']')) {
    final m = _reBracketed.firstMatch(s);
    if (m == null) {
      return const DirectAddrCheck._('', _errEmptyBrackets, null);
    }
    s = m.group(1)!;
    final port = m.group(2);
    if (port != null && !_isPort(port)) {
      return const DirectAddrCheck._('', _errPort, null);
    }
    fixNote = '已自动去掉方括号，保存为 $s';
    // A bare "v6:port" is not a valid upstream address, see the class comment.
    if (port != null) {
      fixNote = '$fixNote；端口 $port 不再使用（直连固定走被控端 direct-access-port）';
    }
  }

  if (_isIpv6(s)) {
    return DirectAddrCheck._(s, null, fixNote);
  }
  if (_isIpv4(s)) {
    return DirectAddrCheck._(s, null, fixNote);
  }
  final hostPort = _reHostPort.firstMatch(s);
  if (hostPort != null) {
    final port = hostPort.group(4)!;
    if (!_isPort(port)) {
      return const DirectAddrCheck._('', _errPort, null);
    }
    return DirectAddrCheck._(s, null, fixNote);
  }
  if (_reLocalNamePort.hasMatch(s)) {
    return const DirectAddrCheck._('', _errLocalName, null);
  }
  return const DirectAddrCheck._('', _errFormat, null);
}

bool _isPort(String v) {
  final p = int.tryParse(v);
  return p != null && p >= 1 && p <= 65535;
}

bool _isIpv4(String s) {
  final m = _reIpv4.firstMatch(s);
  if (m == null) return false;
  for (var i = 1; i <= 4; i++) {
    if (int.parse(m.group(i)!) > 255) return false;
  }
  final port = m.group(5);
  return port == null || _isPort(port);
}

/// Bare IPv6 only: `is_ipv6_str` rejects the bracketed form without a port, and
/// `check_port` adds `[ ]` plus the port itself.
bool _isIpv6(String s) {
  if (!s.contains(':')) return false;
  final halves = s.split('::');
  if (halves.length > 2) return false;
  final head = halves.first.isEmpty ? const <String>[] : halves.first.split(':');
  final tail = halves.length == 2
      ? (halves[1].isEmpty ? const <String>[] : halves[1].split(':'))
      : const <String>[];
  final groups = [...head, ...tail];
  if (halves.length == 2) {
    // "::" stands for at least one group.
    if (groups.length >= 8) return false;
  } else if (groups.length != 8) {
    return false;
  }
  return groups.isNotEmpty && groups.every(_isHexGroup);
}

bool _isHexGroup(String g) {
  if (g.isEmpty || g.length > 4) return false;
  for (final c in g.codeUnits) {
    final digit = c >= 0x30 && c <= 0x39;
    final lower = c >= 0x61 && c <= 0x66;
    final upper = c >= 0x41 && c <= 0x46;
    if (!digit && !lower && !upper) return false;
  }
  return true;
}
