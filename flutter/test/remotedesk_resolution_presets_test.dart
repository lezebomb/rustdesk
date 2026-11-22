import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/remotedesk/resolution_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kRdResolutionPresets', () {
    test('has at least four presets with unique ids and labels', () {
      expect(kRdResolutionPresets.length, greaterThanOrEqualTo(4));
      final ids = kRdResolutionPresets.map((p) => p.id).toSet();
      expect(ids.length, kRdResolutionPresets.length);
      final labels = kRdResolutionPresets.map((p) => p.shortLabel).toSet();
      expect(labels.length, kRdResolutionPresets.length);
    });

    test('every preset uses an option value upstream really accepts', () {
      // flutter/lib/consts.dart:415-425 and src/client.rs:3456-3470 only know
      // these three for image_quality; anything else sends nothing.
      const allowedQuality = {
        kRemoteImageQualityBest,
        kRemoteImageQualityBalanced,
        kRemoteImageQualityLow,
      };
      for (final p in kRdResolutionPresets) {
        expect(allowedQuality, contains(p.imageQuality),
            reason: 'preset ${p.id} has an unknown image quality');
        // view_style must be one of the two styles this feature writes.
        expect(
            p.viewStyle,
            anyOf(equals(kRemoteViewStyleOriginal),
                equals(kRemoteViewStyleCustom)),
            reason: 'preset ${p.id} writes an unknown view style');
      }
    });

    test('scale percent is an integer inside the upstream slider range', () {
      for (final p in kRdResolutionPresets) {
        // custom_scale_percent is parsed with int.tryParse
        // (flutter/lib/utils/scale.dart:10-34), so it has to survive
        // int.tryParse round-tripping unchanged.
        expect(int.tryParse('${p.scalePercent}'), p.scalePercent);
        expect(p.hasValidScalePercent, isTrue,
            reason: 'preset ${p.id} is outside ${kScaleCustomMinPercent}..'
                '${kScaleCustomMaxPercent}');
      }
    });

    test('computes the effective pixels from the 2560-wide base frame', () {
      final byId = {
        for (final p in kRdResolutionPresets) p.id: p,
      };
      // 2560×1600 为基准：1920 → 75%，1600 → 62.5%（取整 63），1280 → 50%。
      expect(byId['original']!.scalePercent, 100);
      expect(byId['original']!.effectiveWidth, 2560);
      expect(byId['original']!.effectiveHeight, 1600);
      expect(byId['original']!.appliesLocalScale, isFalse);

      expect(byId['hd']!.scalePercent, 75);
      expect(byId['hd']!.effectiveWidth, 1920);
      expect(byId['hd']!.effectiveHeight, 1200);

      expect(byId['standard']!.scalePercent, 63);
      expect(byId['standard']!.effectiveWidth, 1613);
      expect(byId['standard']!.effectiveHeight, 1008);

      expect(byId['saver']!.scalePercent, 50);
      expect(byId['saver']!.effectiveWidth, 1280);
      expect(byId['saver']!.effectiveHeight, 800);
    });
  });

  group('rdResolutionPresetById', () {
    test('falls back to the first preset for unknown and null ids', () {
      expect(rdResolutionPresetById('hd').id, 'hd');
      expect(rdResolutionPresetById(null).id, kRdResolutionPresets.first.id);
      // Devices saved before this feature have no such key at all.
      expect(rdResolutionPresetById('').id, kRdResolutionPresets.first.id);
      expect(rdResolutionPresetById('nope').id, kRdResolutionPresets.first.id);
    });

    test('label shown on the device card matches the preset', () {
      expect(rdResolutionPresetLabel('hd'), '高清 1920×1200');
      expect(rdResolutionPresetLabel('saver'), '省流 1280×800');
    });
  });

  group('RdPendingResolutionPreset', () {
    tearDown(RdPendingResolutionPreset.clear);

    test('only hands the preset to the peer it was queued for', () {
      RdPendingResolutionPreset.set('peer-a', rdResolutionPresetById('hd'));
      expect(RdPendingResolutionPreset.forPeer('peer-a')?.id, 'hd');
      // An incoming session from another peer must not pick the preset up.
      expect(RdPendingResolutionPreset.forPeer('peer-b'), isNull);
    });

    test('keeps answering for the same peer so a reconnect re-applies it', () {
      RdPendingResolutionPreset.set('peer-a', rdResolutionPresetById('saver'));
      expect(RdPendingResolutionPreset.forPeer('peer-a')?.id, 'saver');
      expect(RdPendingResolutionPreset.forPeer('peer-a')?.id, 'saver');
    });

    test('clear drops the queued preset', () {
      RdPendingResolutionPreset.set('peer-a', rdResolutionPresetById('hd'));
      RdPendingResolutionPreset.clear();
      expect(RdPendingResolutionPreset.forPeer('peer-a'), isNull);
    });
  });
}
