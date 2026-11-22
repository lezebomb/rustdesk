import 'package:flutter_hbb/common.dart' show SessionID;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';

// RemoteDesk 分辨率预设。
//
// 上游（RustDesk 1.5.3）没有「连接前请求任意像素分辨率」的接口。核实过的杠杆
// 只有三个，本文件只用前两个：
//
// 1. image_quality（flutter/lib/consts.dart:88 kOptionImageQuality）：发给被控端
//    编码器的画质/码率档位（src/server/video_qos.rs:435-447），真正影响带宽。
//    连接前能写进 user default option，成为下一次会话 PeerConfig 的默认值
//    （libs/hbb_common/src/config.rs:2045-2059）；会话内用
//    sessionSetImageQuality 改。
// 2. 本地渲染缩放：custom_scale_percent（整数百分比 5..1000）+ view_style =
//    custom，由 Flutter 画布按百分比绘制对端原始帧
//    （flutter/lib/common/widgets/custom_scale_base.dart:102-126）。它不改变被控端
//    的采集分辨率，也不省带宽，只改变手机这一侧画面大小。
// 3. sessionChangeResolution（flutter/lib/mobile/pages/remote_page.dart:1626-1668）
//    能真切走被控端显示模式，但它会改动被控机器的 Windows 显示设置，且只有对端
//    上报了 pi.resolutions 时才可选。本预设不自动调用它：真正的像素级切换仍由
//    会话内「分辨率」菜单手动完成。
//
// 因此一档 = 一个整数缩放百分比 + 一个画质档位；「目标像素」是原始 2560×1600 帧
// 按该百分比缩放后的等效显示尺寸（effectiveWidth/effectiveHeight）。

/// 预设表的基准：对端 2560×1600 原画。
const int kRdResolutionBaseWidth = 2560;
const int kRdResolutionBaseHeight = 1600;
const int kRdResolutionBasePercent = 100;

/// 一个分辨率档位。
class RdResolutionPreset {
  /// 稳定 id，写进设备 JSON；改名会破坏已保存的设备数据。
  final String id;

  /// 中文档位名，例如 `高清`。
  final String label;

  /// 名义目标像素（列表里展示给人看的那一组数）。
  final int targetWidth;
  final int targetHeight;

  /// 原始帧的渲染百分比。上游用 `int.tryParse` 解析 `custom_scale_percent`
  /// （`flutter/lib/utils/scale.dart:10-34`），小数会被丢掉退回 100，
  /// 所以这里必须是整数。
  final int scalePercent;

  /// 上游真实画质档位：`best` / `balanced` / `low`
  /// （`flutter/lib/consts.dart:415-425`）。
  final String imageQuality;

  /// 表单/文档里的一句话说明（像素目标 + 带宽取向）。
  final String description;

  const RdResolutionPreset({
    required this.id,
    required this.label,
    required this.targetWidth,
    required this.targetHeight,
    required this.scalePercent,
    required this.imageQuality,
    required this.description,
  });

  String get pixelLabel => '$targetWidth×$targetHeight';

  /// 设备卡片/下拉框里的一行，例如 `高清 1920×1200`。
  String get shortLabel => '$label $pixelLabel';

  double get scale => scalePercent / 100.0;

  bool get hasValidScalePercent =>
      scalePercent >= kScaleCustomMinPercent &&
      scalePercent <= kScaleCustomMaxPercent;

  /// 该档位要写的 `view_style`：原画不缩放，其余走自定义缩放。
  String get viewStyle => scalePercent == kRdResolutionBasePercent
      ? kRemoteViewStyleOriginal
      : kRemoteViewStyleCustom;

  /// 是否需要改动本地渲染缩放。
  bool get appliesLocalScale => scalePercent != kRdResolutionBasePercent;

  /// 2560 宽原始帧按 [scalePercent] 缩放后的等效像素宽度。
  int get effectiveWidth =>
      ((kRdResolutionBaseWidth * scalePercent) / 100).round();

  int get effectiveHeight =>
      ((kRdResolutionBaseHeight * scalePercent) / 100).round();
}

/// 预置档位。`id` 一旦发布就不要再改，`devices.json` 里存的是它。
const List<RdResolutionPreset> kRdResolutionPresets = <RdResolutionPreset>[
  RdResolutionPreset(
    id: 'original',
    label: '原画',
    targetWidth: 2560,
    targetHeight: 1600,
    scalePercent: 100,
    imageQuality: kRemoteImageQualityBest,
    description: '不缩放，1:1 显示对端原始画面；画质最好、流量最高，适合局域网',
  ),
  RdResolutionPreset(
    id: 'hd',
    label: '高清',
    targetWidth: 1920,
    targetHeight: 1200,
    scalePercent: 75,
    imageQuality: kRemoteImageQualityBest,
    description: '渲染 75%（2560×1600 → 1920×1200），文字仍锐利；带宽偏高，适合 5G/Wi-Fi',
  ),
  RdResolutionPreset(
    id: 'standard',
    label: '标准',
    targetWidth: 1600,
    targetHeight: 1000,
    // 精确值 62.5%，但上游只收整数百分比，按四舍五入取 63（≈1613×1008）。
    scalePercent: 63,
    imageQuality: kRemoteImageQualityBalanced,
    description: '渲染 63%（≈1613×1008），画质与流量平衡，日常远程操作用',
  ),
  RdResolutionPreset(
    id: 'saver',
    label: '省流',
    targetWidth: 1280,
    targetHeight: 800,
    scalePercent: 50,
    imageQuality: kRemoteImageQualityLow,
    description: '渲染 50%（2560×1600 → 1280×800）+ 低画质，最省流量，适合手机网络',
  ),
];

/// id 不认识（旧数据/手改 JSON）时退回原画，不抛异常。
RdResolutionPreset rdResolutionPresetById(String? id) {
  for (final p in kRdResolutionPresets) {
    if (p.id == id) return p;
  }
  return kRdResolutionPresets.first;
}

/// 卡片上显示的档位文字，例如 `高清 1920×1200`。
String rdResolutionPresetLabel(String? id) => rdResolutionPresetById(id).shortLabel;

/// 设备页「连接」与 RemotePage 之间传递档位。
///
/// 必须带上 peer id：RemotePage 也用于**被控**会话（别人连进来），只按时间取
/// 用会把档位误用到陌生会话上。
class RdPendingResolutionPreset {
  static String? _peerId;
  static RdResolutionPreset? _preset;

  static void set(String peerId, RdResolutionPreset preset) {
    _peerId = peerId;
    _preset = preset;
  }

  /// 只有 [peerId] 匹配才返回；不消费，同一连接重连时会再应用一次（幂等）。
  static RdResolutionPreset? forPeer(String peerId) {
    final preset = _preset;
    if (preset == null) return null;
    return _peerId == peerId ? preset : null;
  }

  static void clear() {
    _peerId = null;
    _preset = null;
  }
}

/// 连接前唯一能落地的部分：把画质写进 user default option，让下一次会话的
/// `PeerConfig` 默认值就是它（`libs/hbb_common/src/config.rs:2045-2059`）。
///
/// 这里**不**写 `view_style`：Android 上 `UserDefaultConfig::get` 对
/// `view_style` 只接受 `original`/`adaptive`（`libs/hbb_common/src/config.rs:2474-2498`），
/// 存进去的 `custom` 会被读回成 `adaptive`，写了也不生效。
Future<void> applyRdResolutionPresetDefaults(RdResolutionPreset preset) async {
  await bind.mainSetUserDefaultOption(
      key: kOptionImageQuality, value: preset.imageQuality);
}

/// 会话内落地：画质发给被控端编码器，缩放写进本地画布 option。
///
/// 调用方负责在之后刷新画布（`ffi.canvasModel.updateViewStyle()`），与上游
/// `custom_scale_base.dart` 的 `_applyScale` 一致。
Future<void> applyRdResolutionPreset({
  required SessionID sessionId,
  required RdResolutionPreset preset,
}) async {
  await bind.sessionSetImageQuality(
      sessionId: sessionId, value: preset.imageQuality);
  await bind.sessionSetFlutterOption(
      sessionId: sessionId,
      k: kCustomScalePercentKey,
      v: '${preset.scalePercent}');
  final target = preset.viewStyle;
  final current = await bind.sessionGetViewStyle(sessionId: sessionId);
  if (current != target) {
    await bind.sessionSetViewStyle(sessionId: sessionId, value: target);
  }
}
