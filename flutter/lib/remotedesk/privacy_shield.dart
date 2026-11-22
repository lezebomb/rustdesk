// RemoteDesk 本地防窥屏（privacy shield）。
//
// 只作用于手机这一侧（控制端）：把手机上的远程画面挡住，避免旁人偷看。
// 与被控端的 privacy_mode 是两回事，这里完全不碰对端。
//
// 三个开关存在 RustDesk 的 local option（RustDesk2.toml 的 [local-options]）里，
// 不新增 SharedPreferences 依赖；FLAG_SECURE 通过 `remotedesk/privacy` 通道
// 交给 MainActivity.kt 设置。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';

/// 应用切到后台 / 任务列表时盖住远程画面。默认开。
const String kPrivacyShieldOnBackground = 'privacy-shield-on-background';

/// 会话期间设置 FLAG_SECURE：禁止截屏与录屏，最近任务缩略图为黑。默认开。
const String kPrivacyShieldBlockScreenshot = 'privacy-shield-block-screenshot';

/// 进入会话就默认遮挡。默认关。
const String kPrivacyShieldDefaultBlur = 'privacy-shield-default-blur';

/// 与 MainActivity.kt 里的 `remotedesk/privacy` 通道对应，只负责 FLAG_SECURE。
final MethodChannel _privacyChannel = MethodChannel('remotedesk/privacy');

/// 三个开关的内存镜像，外加 FLAG_SECURE 的平台调用。
///
/// 用单例而不是 Provider，是因为会话页（remote_page.dart）和设置入口
/// （设备页 AppBar）之间没有共同的祖先，而开关本身没有按会话区分的状态。
class RdPrivacyShieldSettings extends ChangeNotifier {
  RdPrivacyShieldSettings._();

  static final RdPrivacyShieldSettings instance = RdPrivacyShieldSettings._();

  bool _onBackground = true;
  bool _blockScreenshot = true;
  bool _defaultBlur = false;

  /// 切后台时遮挡。
  bool get onBackground => _onBackground;

  /// 会话期间禁止截屏 / 录屏。
  bool get blockScreenshot => _blockScreenshot;

  /// 进入会话就默认遮挡。
  bool get defaultBlur => _defaultBlur;

  /// 读本地选项。
  ///
  /// 不能直接用 common.dart 的 `mainGetLocalBoolOptionSync()`：RustDesk 的
  /// `option2bool()` 把空串当成 true，而这三个 key 是从未写过的新 key，
  /// 空串必须落到这里的 [fallback]（否则 `privacy-shield-default-blur`
  /// 会默认变成开）。
  static bool _readBool(String key, bool fallback) {
    try {
      final v = bind.mainGetLocalOption(key: key);
      if (v.isEmpty) return fallback;
      return v != 'N';
    } catch (e) {
      debugPrint('privacy shield: read $key failed: $e');
      return fallback;
    }
  }

  static Future<void> _writeBool(String key, bool value) async {
    try {
      await bind.mainSetLocalOption(key: key, value: value ? 'Y' : 'N');
    } catch (e) {
      debugPrint('privacy shield: write $key failed: $e');
    }
  }

  /// 从 local option 载入三个开关。会话开始时调用一次即可。
  void load() {
    _onBackground = _readBool(kPrivacyShieldOnBackground, true);
    _blockScreenshot = _readBool(kPrivacyShieldBlockScreenshot, true);
    _defaultBlur = _readBool(kPrivacyShieldDefaultBlur, false);
  }

  Future<void> setOnBackground(bool value) async {
    if (_onBackground == value) return;
    _onBackground = value;
    notifyListeners();
    await _writeBool(kPrivacyShieldOnBackground, value);
  }

  Future<void> setBlockScreenshot(bool value) async {
    if (_blockScreenshot == value) return;
    _blockScreenshot = value;
    notifyListeners();
    await _writeBool(kPrivacyShieldBlockScreenshot, value);
    // 会话中途改这个开关要立刻生效，不能等到下一次进会话。
    await applyScreenshotBlock();
  }

  Future<void> setDefaultBlur(bool value) async {
    if (_defaultBlur == value) return;
    _defaultBlur = value;
    notifyListeners();
    await _writeBool(kPrivacyShieldDefaultBlur, value);
  }

  /// 打开或关闭 FLAG_SECURE。只有 Android 实现了这条通道，
  /// 其他平台拿到异常就当没这个能力（FLAG_SECURE 本来就是 Android 概念）。
  Future<void> applyScreenshotBlock({bool? enable}) async {
    final on = enable ?? _blockScreenshot;
    try {
      await _privacyChannel.invokeMethod('setSecure', {'enable': on});
    } catch (e) {
      debugPrint('privacy shield: setSecure($on) failed: $e');
    }
  }

  /// 退出会话时一定要撤掉，否则回到主页后用户也截不了图。
  Future<void> releaseScreenshotBlock() => applyScreenshotBlock(enable: false);
}

/// 遮挡层：高斯模糊 + 半透明黑底，把远程画面盖成不可读。
///
/// 它是 `HitTestBehavior.opaque` 的 GestureDetector，遮罩下面的输入注入链
/// （RawPointerMouseRegion / RawTouchGestureDetectorRegion）收不到任何指针事件，
/// 所以“遮挡时暂停输入转发”有一半是结构上保证的，见 remote_page.dart
/// `getRawPointerAndKeyBody()`。
class RdPrivacyShieldCover extends StatelessWidget {
  const RdPrivacyShieldCover({Key? key, this.onTap, this.showHint = true})
      : super(key: key);

  /// 为空时不响应点击（后台遮挡用，用户看不到画面）。
  final VoidCallback? onTap;

  /// 是否显示「已遮挡 · 点击恢复」。
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32),
          child: Container(
            color: Colors.black54,
            alignment: Alignment.center,
            child: showHint ? _hint() : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Widget _hint() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.visibility_off_rounded, color: Colors.white70, size: 36),
        SizedBox(height: 10),
        Text('已遮挡 · 点击恢复',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        SizedBox(height: 4),
        Text('此时不会把操作发送给远程设备',
            style: TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}

/// 四指下滑触发遮挡。
///
/// 上游的 `CustomTouchGestureRecognizer` 只处理 1/2/3 指（1 指拖拽、2 指缩放、
/// 3 指上下滚动），4 指是空的，所以这个手势不会和远程滚动/缩放抢；
/// 另外这里是 `Listener`，旁听指针事件、不加入手势竞技场，
/// 因此要转发给被控端的 Tap / 双击 / 长按都不受影响。
class RdPrivacyShieldSwipeDetector extends StatefulWidget {
  const RdPrivacyShieldSwipeDetector(
      {Key? key, required this.onTrigger, required this.child})
      : super(key: key);

  final VoidCallback onTrigger;
  final Widget child;

  @override
  State<RdPrivacyShieldSwipeDetector> createState() =>
      _RdPrivacyShieldSwipeDetectorState();
}

class _RdPrivacyShieldSwipeDetectorState
    extends State<RdPrivacyShieldSwipeDetector> {
  /// 需要同时按下的手指数。
  static const int _fingers = 4;

  /// 每根手指至少下滑多少逻辑像素才算触发。
  static const double _distance = 90;

  final Map<int, Offset> _start = {};
  final Map<int, double> _down = {};

  void _reset() {
    _start.clear();
    _down.clear();
  }

  void _onDown(PointerDownEvent e) {
    if (_start.length >= _fingers) return;
    _start[e.pointer] = e.position;
    _down[e.pointer] = 0;
  }

  void _onMove(PointerMoveEvent e) {
    final start = _start[e.pointer];
    if (start == null) return;
    final dy = e.position.dy - start.dy;
    final maxDown = _down[e.pointer] ?? 0;
    if (dy > maxDown) _down[e.pointer] = dy;
    if (_start.length < _fingers) return;
    if (_down.values.any((d) => d < _distance)) return;
    // 触发后清空，避免同一组手指继续移动时反复触发。
    _reset();
    widget.onTrigger();
  }

  void _onUp(PointerEvent e) {
    _start.remove(e.pointer);
    _down.remove(e.pointer);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: widget.child,
    );
  }
}

/// 设置入口：设备页 AppBar 上的盾牌图标。
class RdPrivacyShieldSettingsButton extends StatelessWidget {
  const RdPrivacyShieldSettingsButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.shield_outlined),
      tooltip: '防窥屏',
      onPressed: () => showRdPrivacyShieldSettings(context),
    );
  }
}

/// 底部弹出的三个开关。改一下立刻写 local option，会话里再读。
Future<void> showRdPrivacyShieldSettings(BuildContext context) {
  final settings = RdPrivacyShieldSettings.instance..load();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => AnimatedBuilder(
      animation: settings,
      builder: (ctx, _) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('防窥屏（仅本机）',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              SwitchListTile(
                value: settings.onBackground,
                title: const Text('切到后台时遮挡画面'),
                subtitle: const Text('进入任务列表或切到其他应用时立刻盖住远程画面'),
                onChanged: (v) => settings.setOnBackground(v),
              ),
              SwitchListTile(
                value: settings.blockScreenshot,
                title: const Text('禁止截屏与录屏'),
                subtitle: const Text('会话期间设置 FLAG_SECURE；副作用是本机无法截图/录屏'),
                onChanged: (v) => settings.setBlockScreenshot(v),
              ),
              SwitchListTile(
                value: settings.defaultBlur,
                title: const Text('进入会话就遮挡'),
                subtitle: const Text('连上远程设备时默认先遮住画面'),
                onChanged: (v) => settings.setDefaultBlur(v),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text(
                  '会话里可用底部「眼睛」按钮或四指下滑切换遮挡；遮挡期间不会把操作发给远程设备。',
                  style: TextStyle(fontSize: 12, color: MyTheme.darkGray),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
