import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/mobile/pages/home_page.dart';
import 'package:flutter_hbb/remotedesk/device_store.dart';
import 'package:flutter_hbb/remotedesk/secure_store.dart';

/// Password storage key for one device. The value itself never leaves the
/// Keystore-backed store.
String _pwKey(String id) => 'rd_pw_$id';

/// "My devices" home page: one card per paired computer, tap to connect.
class RdDevicesPage extends StatefulWidget implements PageShape {
  @override
  final String title = translate('My devices');
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
        title: Text(translate('Remove device')),
        content: Text('${device.name} (${formatID(device.id)})'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(translate('Cancel'))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(translate('OK'))),
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
                    child: Text(translate('No devices yet'),
                        style: TextStyle(color: MyTheme.darkGray)),
                  ),
                  SizedBox(height: 16),
                  Center(
                    child: FilledButton.icon(
                      onPressed: () => _edit(null),
                      icon: Icon(Icons.add),
                      label: Text(translate('Add device')),
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
              tooltip: translate('Add device'),
            ),
    );
  }

  Widget _deviceCard(RdDevice d) {
    final last = d.lastConnected == 0
        ? translate('Never connected')
        : DateTime.fromMillisecondsSinceEpoch(d.lastConnected)
            .toString()
            .substring(0, 16);
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: () => _connect(d),
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                d.platform == 'windows' ? Icons.desktop_windows : Icons.computer,
                size: 36,
                color: MyTheme.accent,
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text('ID: ${formatID(d.id)}',
                        style:
                            TextStyle(fontSize: 12, color: MyTheme.darkGray)),
                    SizedBox(height: 2),
                    Text('${translate('Last connected')}: $last',
                        style:
                            TextStyle(fontSize: 12, color: MyTheme.darkGray)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') _edit(d);
                  if (v == 'delete') _confirmDelete(d);
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(value: 'edit', child: Text(translate('Edit'))),
                  PopupMenuItem(
                      value: 'delete', child: Text(translate('Remove device'))),
                ],
              ),
              FilledButton(
                onPressed: () => _connect(d),
                child: Text(translate('Connect')),
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
      title: Text(widget.existing == null
          ? translate('Add device')
          : translate('Edit')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: translate('Device name')),
            ),
            TextField(
              controller: _id,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: translate('Remote ID')),
            ),
            TextField(
              controller: _server,
              decoration:
                  InputDecoration(labelText: translate('ID server')),
            ),
            TextField(
              controller: _relay,
              decoration: InputDecoration(labelText: 'Relay server'),
            ),
            TextField(
              controller: _key,
              decoration: InputDecoration(labelText: 'Server public key'),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                  labelText: translate('Password'),
                  helperText: translate('Leave empty to be asked on connect')),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _savePassword,
              onChanged: (v) => setState(() => _savePassword = v ?? false),
              title: Text(translate('Save password on this device'),
                  style: TextStyle(fontSize: 13)),
              subtitle: Text(
                  translate('Stored encrypted with the Android Keystore'),
                  style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(translate('Cancel'))),
        TextButton(onPressed: _submit, child: Text(translate('OK'))),
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
