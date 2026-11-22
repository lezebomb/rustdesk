import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/mobile/pages/home_page.dart';
import 'package:flutter_hbb/remotedesk/device_store.dart';
import 'package:flutter_hbb/remotedesk/direct_addr.dart';
import 'package:flutter_hbb/remotedesk/privacy_shield.dart';
import 'package:flutter_hbb/remotedesk/secure_store.dart';
import 'package:flutter_hbb/remotedesk/win_password.dart';

/// Password storage key for one device. The value itself never leaves the
/// Keystore-backed store.
String _pwKey(String id) => 'rd_pw_$id';

/// "My devices" home page: one card per paired computer, tap to connect.
class RdDevicesPage extends StatefulWidget implements PageShape {
  @override
  final String title = '我的设备';
  @override
  final Widget icon = const Icon(Icons.devices_rounded);
  @override
  final List<Widget> appBarActions;

  RdDevicesPage({
    Key? key,
    // RemoteDesk: 防窥屏开关挂在设备页 AppBar 上；home_page 不传 actions 时
    // 也能拿到入口，不需要改上游的 home_page。
    this.appBarActions = const [RdPrivacyShieldSettingsButton()],
  }) : super(key: key);

  @override
  State<RdDevicesPage> createState() => RdDevicesPageState();
}

class RdDevicesPageState extends State<RdDevicesPage> {
  final _store = RdDeviceStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    _store.load().then((_) => _applyPrimaryServer());
    _ensurePrivacyModeDefault();
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  /// Writes the server settings into the *global* option store. The rendezvous
  /// client reads these keys from the global config (RustDesk2.toml [options]),
  /// so local options would not affect which server the app registers with.
  Future<void> _applyServer(RdDevice device) async {
    if (device.server.isNotEmpty) {
      await bind.mainSetOption(
          key: 'custom-rendezvous-server', value: device.server);
    }
    if (device.relayServer.isNotEmpty) {
      await bind.mainSetOption(
          key: 'relay-server', value: device.relayServer);
    }
    if (device.key.isNotEmpty) {
      await bind.mainSetOption(key: 'key', value: device.key);
    }
  }

  /// Applies the most recently used device's server at startup so the client
  /// registers with the paired server before the user taps anything.
  Future<void> _applyPrimaryServer() async {
    if (_store.devices.isEmpty) return;
    // lastConnected is epoch milliseconds (int), not a DateTime.
    final sorted = [..._store.devices]
      ..sort((a, b) => b.lastConnected.compareTo(a.lastConnected));
    final primary = sorted.first;
    if (primary.server.isEmpty) return;
    final current = bind.mainGetOptionSync(key: 'custom-rendezvous-server');
    if (current != primary.server) {
      await _applyServer(primary);
    }
  }

  /// `privacy_mode` is a display option (`kOptionPrivacyMode` in
  /// `lib/consts.dart`, "Settings -> Display -> Other default options"), so it
  /// lives in `RustDesk_default.toml`: `mainSetLocalOption` would write a key
  /// nothing reads. `mainSetUserDefaultOption` is the API for that file
  /// (`src/ui_interface.rs:1356` -> `UserDefaultConfig::set`). Only the default
  /// is filled in, so a user who turns it off keeps that choice.
  Future<void> _ensurePrivacyModeDefault() async {
    if (bind.mainGetUserDefaultOption(key: kOptionPrivacyMode).isNotEmpty) {
      return;
    }
    await bind.mainSetUserDefaultOption(key: kOptionPrivacyMode, value: 'Y');
  }

  Future<void> _connect(RdDevice device, {bool forceRelay = false}) async {
    // Apply this device's server settings first so the connection goes through
    // the server it was paired with.
    await _applyServer(device);
    final password = await SecureStore.get(_pwKey(device.id));
    if (!mounted) return;
    await _store.touch(device.id);
    if (!mounted) return;
    final directAddr = device.directAddr;
    if (directAddr.isEmpty) {
      // `connect()` returns before the session is up and upstream reports a
      // rendezvous failure from Rust through a msgbox, so there is no Dart
      // result to test here: warn on the attempt instead of after it.
      showToast('当前网络下信令可能不可用，建议填写直连地址');
    }
    try {
      // A literal IP (or host:port) is routed by `is_direct_ip_access` before
      // the rendezvous client is involved, so it never touches hbbs.
      await connect(context, directAddr.isEmpty ? device.id : directAddr,
          password: password, forceRelay: forceRelay);
    } catch (e) {
      showToast(directAddr.isEmpty
          ? '连接失败：$e\n当前网络下信令可能不可用，建议填写直连地址'
          : '连接失败：$e');
    }
  }

  Future<void> _confirmDelete(RdDevice device) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除设备'),
        content: Text('${device.name} (${formatID(device.id)})'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('取消')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await SecureStore.delete(_pwKey(device.id));
    await RdWinPassword.delete(device.id);
    await _store.remove(device.id);
  }

  Future<void> _edit(RdDevice? existing) async {
    final draft = await showDialog<_DeviceDraft>(
      context: context,
      builder: (ctx) => _DeviceDialog(existing: existing),
    );
    if (draft == null) return;
    // The Keystore entry is written first: the flag on the device has to
    // describe what is really stored, so a failed write cannot claim a
    // password that is not there.
    if (draft.winPassword.isNotEmpty) {
      await RdWinPassword.save(draft.device.id, draft.winPassword);
    } else if (!draft.saveWinPassword) {
      await RdWinPassword.delete(draft.device.id);
    }
    draft.device.winPasswordRef = await RdWinPassword.has(draft.device.id);
    await _store.addOrUpdate(draft.device);
    await persistDevicePassword(
        draft.device.id, draft.password, draft.savePassword);
    final fix = draft.addrFix;
    if (fix != null) showToast(fix);
  }

  @override
  Widget build(BuildContext context) {
    final devices = _store.devices;
    return Scaffold(
      backgroundColor: MyTheme.grayBg,
      body: RefreshIndicator(
        onRefresh: () async {
          // There is no OSS device-status API: refresh only reloads local state
          // and never fabricates an "online" flag.
          await _store.load();
        },
        child: devices.isEmpty
            ? ListView(
                children: [
                  SizedBox(height: 120),
                  Icon(Icons.devices_other, size: 64, color: MyTheme.darkGray),
                  SizedBox(height: 12),
                  Center(
                    child: Text('还没有添加设备',
                        style: TextStyle(color: MyTheme.darkGray)),
                  ),
                  SizedBox(height: 16),
                  Center(
                    child: FilledButton.icon(
                      onPressed: () => _edit(null),
                      icon: Icon(Icons.add),
                      label: Text('添加设备'),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: EdgeInsets.symmetric(vertical: 8),
                itemCount: devices.length,
                itemBuilder: (ctx, i) => _deviceCard(devices[i]),
              ),
      ),
      floatingActionButton: devices.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: () => _edit(null),
              child: Icon(Icons.add),
              tooltip: '添加设备',
            ),
    );
  }

  /// Presence is reported honestly: the self-hosted OSS server exposes no
  /// peer-presence API, so a device is only shown as online while a session to
  /// it is actually live; everything else is "not checked" and tapping connect
  /// is the real test.
  Widget _statusChip(RdDevice d) {
    final connected = gFFI.serverModel.clients.any((e) => e.id == d.id);
    final label = connected ? '在线' : '未检测';
    final color = connected ? const Color(0xFF2E9E5B) : MyTheme.darkGray;
    return Tooltip(
      message: connected
          ? '当前有活动会话'
          : '自建服务器没有在线状态接口，点击连接即验证',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: color)),
      ),
    );
  }

  /// Epoch milliseconds -> local wall clock. `DateTime.toString()` renders UTC
  /// with a "Z" suffix and no offset, which showed 03:26 for an 11:26 attempt.
  static String _fmtLocal(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  Widget _deviceCard(RdDevice d) {
    final last = d.lastConnected == 0 ? '从未尝试' : _fmtLocal(d.lastConnected);
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: () => _connect(d),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Icon(
                d.platform == 'windows' ? Icons.desktop_windows : Icons.computer,
                size: 36,
                color: MyTheme.accent,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The name gets the full row width: putting the status chip
                    // beside it squeezed long Chinese device names into "拯救…".
                    Text(d.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Text('ID: ${formatID(d.id)}',
                            style: TextStyle(
                                fontSize: 12, color: MyTheme.darkGray)),
                        SizedBox(width: 8),
                        _statusChip(d),
                      ],
                    ),
                    if (d.directAddr.isNotEmpty) ...[
                      SizedBox(height: 2),
                      Text('直连：${d.directAddr}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: MyTheme.accent)),
                    ],
                    SizedBox(height: 2),
                    Text('最近尝试：$last',
                        style:
                            TextStyle(fontSize: 12, color: MyTheme.darkGray)),
                  ],
                ),
              ),
              SizedBox(width: 6),
              FilledButton(
                onPressed: () => _connect(d),
                child: Text('连接'),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.more_vert, size: 20),
                onSelected: (v) {
                  if (v == 'relay') _connect(d, forceRelay: true);
                  if (v == 'edit') _edit(d);
                  if (v == 'delete') _confirmDelete(d);
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(value: 'relay', child: Text('强制中继连接')),
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除设备')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceDraft {
  final RdDevice device;
  final String password;
  final bool savePassword;

  /// Windows logon password typed in this dialog; empty when left untouched.
  final String winPassword;

  /// Whether the logon password should exist in the Keystore after this edit.
  final bool saveWinPassword;

  /// Set when the direct address was rewritten before saving, so the page can
  /// tell the user what was stored.
  final String? addrFix;
  _DeviceDraft(this.device, this.password, this.savePassword,
      {this.addrFix, this.winPassword = '', this.saveWinPassword = false});
}

class _DeviceDialog extends StatefulWidget {
  final RdDevice? existing;
  const _DeviceDialog({this.existing});

  @override
  State<_DeviceDialog> createState() => _DeviceDialogState();
}

class _DeviceDialogState extends State<_DeviceDialog> {
  late final TextEditingController _name;
  late final TextEditingController _id;
  late final TextEditingController _directAddr;
  late final TextEditingController _server;
  late final TextEditingController _relay;
  late final TextEditingController _key;
  late final TextEditingController _password;
  late final TextEditingController _winPassword;
  bool _savePassword = true;
  bool _saveWinPassword = false;
  String? _directErr;
  String? _winErr;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _id = TextEditingController(text: e?.id ?? '');
    _directAddr = TextEditingController(text: e?.directAddr ?? '');
    _server = TextEditingController(
        text: e?.server ?? bind.mainGetOptionSync(key: 'custom-rendezvous-server'));
    _relay =
        TextEditingController(text: e?.relayServer ?? bind.mainGetOptionSync(key: 'relay-server'));
    _key = TextEditingController(text: e?.key ?? bind.mainGetOptionSync(key: 'key'));
    _password = TextEditingController();
    // The stored logon password itself is never read back into the UI, only
    // the fact that one exists.
    _winPassword = TextEditingController();
    _saveWinPassword = e?.winPasswordRef ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    _directAddr.dispose();
    _server.dispose();
    _relay.dispose();
    _key.dispose();
    _password.dispose();
    _winPassword.dispose();
    super.dispose();
  }

  void _submit() {
    final id = _id.text.replaceAll(' ', '').trim();
    if (id.isEmpty) return;
    final direct = checkDirectAddr(_directAddr.text);
    if (!direct.ok) {
      setState(() => _directErr = direct.error);
      return;
    }
    if (_directErr != null) setState(() => _directErr = null);
    final winText = _winPassword.text;
    if (winText.isEmpty) {
      // Keeping an already saved password is fine; turning the option on
      // without a password would silently store nothing.
      if (_saveWinPassword && widget.existing?.winPasswordRef != true) {
        setState(() => _winErr = '开启后需要填写电脑登录密码');
        return;
      }
    } else {
      final winErr = rdValidateWinPassword(winText);
      if (winErr != null) {
        setState(() => _winErr = winErr);
        return;
      }
    }
    if (_winErr != null) setState(() => _winErr = null);
    final device = RdDevice(
      id: id,
      name: _name.text.trim().isEmpty ? id : _name.text.trim(),
      platform: 'windows',
      server: _server.text.trim(),
      relayServer: _relay.text.trim(),
      key: _key.text.trim(),
      directAddr: direct.value,
      winPasswordRef: _saveWinPassword,
      lastConnected: widget.existing?.lastConnected ?? 0,
      createdAt: widget.existing?.createdAt ?? 0,
    );
    Navigator.of(context).pop(_DeviceDraft(device, _password.text, _savePassword,
        addrFix: direct.fixNote,
        winPassword: _winPassword.text,
        saveWinPassword: _saveWinPassword));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? '添加设备' : '编辑设备'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: '设备名称'),
            ),
            TextField(
              controller: _id,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: '远程 ID'),
            ),
            TextField(
              controller: _directAddr,
              decoration: InputDecoration(
                labelText: '直连地址（可选）',
                helperText: '裸 IPv6 或 IPv4，例如 2001:da8:...:2dbd，留空则用 ID 连接',
                helperMaxLines: 2,
                errorText: _directErr,
                errorMaxLines: 2,
              ),
            ),
            TextField(
              controller: _server,
              decoration: InputDecoration(labelText: 'ID 服务器'),
            ),
            TextField(
              controller: _relay,
              decoration: InputDecoration(labelText: '中继服务器'),
            ),
            TextField(
              controller: _key,
              decoration: InputDecoration(labelText: '服务器公钥'),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                  labelText: '访问密码',
                  helperText: '留空则连接时询问'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _savePassword,
              onChanged: (v) => setState(() => _savePassword = v ?? false),
              title: Text('在本机保存密码', style: TextStyle(fontSize: 13)),
              subtitle: Text('使用 Android Keystore 加密存储',
                  style: TextStyle(fontSize: 11)),
            ),
            // RemoteDesk 指纹解锁：Windows 账户密码单独存一份，只在指纹
            // 验证通过后解密，并交给上游的输入通道"打字"到锁屏界面。
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _saveWinPassword,
              onChanged: (v) => setState(() {
                _saveWinPassword = v ?? false;
                if (!_saveWinPassword) {
                  _winPassword.clear();
                  _winErr = null;
                }
              }),
              title: Text('保存电脑登录密码（用于指纹解锁）',
                  style: TextStyle(fontSize: 13)),
              subtitle: Text(
                  '密码将用 Android Keystore 加密保存在本机，仅用于远控时自动输入；指纹验证通过后才解密',
                  style: TextStyle(fontSize: 11)),
            ),
            if (_saveWinPassword)
              TextField(
                controller: _winPassword,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: '电脑登录密码（Windows 账户密码）',
                  helperText: widget.existing?.winPasswordRef == true
                      ? '已保存一份；留空表示不修改'
                      : '仅支持 ASCII 密码：字母、数字、英文符号',
                  helperMaxLines: 2,
                  errorText: _winErr,
                  errorMaxLines: 3,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(), child: Text('取消')),
        TextButton(onPressed: _submit, child: Text('保存')),
      ],
    );
  }
}

/// Persists the optional password for [device] after the dialog is accepted.
Future<void> persistDevicePassword(String id, String password, bool save) async {
  if (password.isEmpty) return;
  if (save) {
    await SecureStore.put(_pwKey(id), password);
  } else {
    await SecureStore.delete(_pwKey(id));
  }
}
