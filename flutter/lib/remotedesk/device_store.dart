import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A computer this device can control.
///
/// Only non-secret fields live here. The access password is stored separately
/// through [SecureStore], backed by the Android Keystore.
class RdDevice {
  String id;
  String name;
  String platform;
  String server;
  String relayServer;
  String key;

  /// Optional direct-IP target ("2001:db8::1", "1.2.3.4", "pc.lan:21118").
  /// Empty means "connect by [id] through the rendezvous server".
  String directAddr;

  /// Whether the Windows logon password of this computer is stored in the
  /// Android Keystore (key `rd_winpw_<id>`, see [RdWinPassword]).
  ///
  /// Only this flag lives in the device list; the password itself never does.
  bool winPasswordRef;

  /// 分辨率预设 id，见 `remotedesk/resolution_presets.dart`。旧设备数据里没有
  /// 这个键，读回时按 `original`（原画）处理。
  String resolutionPreset;

  int lastConnected;
  int createdAt;

  RdDevice({
    required this.id,
    required this.name,
    this.platform = 'windows',
    this.server = '',
    this.relayServer = '',
    this.key = '',
    this.directAddr = '',
    this.resolutionPreset = 'original',
    this.winPasswordRef = false,
    this.lastConnected = 0,
    this.createdAt = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'server': server,
        'relayServer': relayServer,
        'key': key,
        'directAddr': directAddr,
        'resolutionPreset': resolutionPreset,
        'winPasswordRef': winPasswordRef,
        'lastConnected': lastConnected,
        'createdAt': createdAt,
      };

  static RdDevice fromJson(Map<String, dynamic> m) => RdDevice(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        platform: (m['platform'] ?? 'windows').toString(),
        server: (m['server'] ?? '').toString(),
        relayServer: (m['relayServer'] ?? '').toString(),
        key: (m['key'] ?? '').toString(),
        // Devices saved before M2 have no such key; they keep working by ID.
        directAddr: (m['directAddr'] ?? '').toString(),
        // 旧设备文件没有这个键：按原画（不缩放）读回。
        resolutionPreset: (m['resolutionPreset'] ?? 'original').toString(),
        // Older files have no flag at all: no saved logon password then.
        winPasswordRef: m['winPasswordRef'] == true,
        lastConnected: (m['lastConnected'] as num?)?.toInt() ?? 0,
        createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
      );
}

/// Persists the device list in the app support directory.
///
/// Nothing secret is written here: see [SecureStore] for credentials.
class RdDeviceStore extends ChangeNotifier {
  static final RdDeviceStore instance = RdDeviceStore._();
  RdDeviceStore._();

  final List<RdDevice> _devices = [];
  List<RdDevice> get devices => List.unmodifiable(_devices);

  bool _loaded = false;
  bool get loaded => _loaded;

  File? _file;

  Future<File> _resolveFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/remotedesk_devices.json');
    _file = f;
    return f;
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final f = await _resolveFile();
      if (await f.exists()) {
        final raw = await f.readAsString();
        final list = jsonDecode(raw);
        if (list is List) {
          _devices
            ..clear()
            ..addAll(list
                .whereType<Map>()
                .map((e) => RdDevice.fromJson(Map<String, dynamic>.from(e)))
                .where((d) => d.id.isNotEmpty));
        }
      }
    } catch (e) {
      debugPrint('RdDeviceStore.load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final f = await _resolveFile();
      await f.writeAsString(
          jsonEncode(_devices.map((d) => d.toJson()).toList(growable: false)));
    } catch (e) {
      debugPrint('RdDeviceStore.persist failed: $e');
    }
  }

  RdDevice? byId(String id) {
    for (final d in _devices) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> addOrUpdate(RdDevice device) async {
    final idx = _devices.indexWhere((d) => d.id == device.id);
    if (idx >= 0) {
      device.createdAt = _devices[idx].createdAt;
      _devices[idx] = device;
    } else {
      if (device.createdAt == 0) {
        device.createdAt = DateTime.now().millisecondsSinceEpoch;
      }
      _devices.add(device);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String id) async {
    _devices.removeWhere((d) => d.id == id);
    notifyListeners();
    await _persist();
  }

  Future<void> touch(String id) async {
    final d = byId(id);
    if (d == null) return;
    d.lastConnected = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    await _persist();
  }
}
