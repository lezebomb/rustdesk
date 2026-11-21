import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/mobile/pages/home_page.dart';
import 'package:flutter_hbb/remotedesk/device_store.dart';
import 'package:flutter_hbb/remotedesk/secure_store.dart';

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

  RdDevicesPage({Key? key, this.appBarActions = const []}) : super(key: key);

  @override
  State<RdDevicesPage> createState() => RdDevicesPageState();
}

class RdDevicesPageState extends State<RdDevicesPage> {
  final _store = RdDeviceStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _connect(RdDevice device) async {
    // Apply this device's server settings first so the connection goes through
    // the server it was paired with.
    if (device.server.isNotEmpty) {
      await bind.mainSetLocalOption(
          key: 'custom-rendezvous-server', value: device.server);
    }
    if (device.relayServer.isNotEmpty) {
      await bind.mainSetLocalOption(
          key: 'relay-server', value: device.relayServer);
    }
    if (device.key.isNotEmpty) {
      await bind.mainSetLocalOption(key: 'key', value: device.key);
    }
    final password = await SecureStore.get(_pwKey(device.id));
    if (!mounted) return;
    await _store.touch(device.id);
    if (!mounted) return;
    connect(context, device.id, password: password);
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
    await _store.remove(device.id);
  }

  Future<void> _edit(RdDevice? existing) async {
    final draft = await showDialog<_DeviceDraft>(
      context: context,
      builder: (ctx) => _DeviceDialog(existing: existing),
    );
    if (draft == null) return;
    await _store.addOrUpdate(draft.device);
    await persistDevicePassword(
        draft.device.id, draft.password, draft.savePassword);
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

  Widget _deviceCard(RdDevice d) {
    final last = d.lastConnected == 0
        ? '从未连接'
        : DateTime.fromMillisecondsSinceEpoch(d.lastConnected)
            .toString()
            .substring(0, 16);
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(d.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                        ),
                        SizedBox(width: 6),
                        _statusChip(d),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text('ID: ${formatID(d.id)}',
                        style:
                            TextStyle(fontSize: 12, color: MyTheme.darkGray)),
                    SizedBox(height: 2),
                    Text('最近连接：$last',
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
                  if (v == 'edit') _edit(d);
                  if (v == 'delete') _confirmDelete(d);
                },
                itemBuilder: (ctx) => [
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
  _DeviceDraft(this.device, this.password, this.savePassword);
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
  late final TextEditingController _server;
  late final TextEditingController _relay;
  late final TextEditingController _key;
  late final TextEditingController _password;
  bool _savePassword = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _id = TextEditingController(text: e?.id ?? '');
    _server = TextEditingController(
        text: e?.server ?? bind.mainGetLocalOption(key: 'custom-rendezvous-server'));
    _relay =
        TextEditingController(text: e?.relayServer ?? bind.mainGetLocalOption(key: 'relay-server'));
    _key = TextEditingController(text: e?.key ?? bind.mainGetLocalOption(key: 'key'));
    _password = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    _server.dispose();
    _relay.dispose();
    _key.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final id = _id.text.replaceAll(' ', '').trim();
    if (id.isEmpty) return;
    final device = RdDevice(
      id: id,
      name: _name.text.trim().isEmpty ? id : _name.text.trim(),
      platform: 'windows',
      server: _server.text.trim(),
      relayServer: _relay.text.trim(),
      key: _key.text.trim(),
      lastConnected: widget.existing?.lastConnected ?? 0,
      createdAt: widget.existing?.createdAt ?? 0,
    );
    Navigator.of(context)
        .pop(_DeviceDraft(device, _password.text, _savePassword));
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
