// Phase 17 Plan 17-13 — Remote Config typed Feature Flag · 공지 표시 문구 결정.
//
// T-17-RC-01 · 02 (Task 1): enum 키 · 기본값 · 미초기화 기본값 · 언어 → en →
// 없음 규칙(D-36).

import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/remote_config/feature_flag.dart';
import 'package:flutter_starter_kit/core/remote_config/feature_flags_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// 공지 스위치 · 문구를 지정한 [FeatureFlagValues] (지정 안 한 칸 = 기본값).
FeatureFlagValues _values({
  bool enabled = true,
  String ko = '',
  String en = '',
  String ja = '',
}) {
  return FeatureFlagValues(<FeatureFlag, Object>{
    FeatureFlag.announcementBannerEnabled: enabled,
    FeatureFlag.announcementMessageKo: ko,
    FeatureFlag.announcementMessageEn: en,
    FeatureFlag.announcementMessageJa: ja,
  });
}

void main() {
  group('Phase 17 Remote Config 공지 (T-17-RC)', () {
    test('T-17-RC-01 FeatureFlag 4키 · 기본값 · 미초기화 컨테이너는 기본값', () {
      expect(
        <String, Object>{
          for (final flag in FeatureFlag.values) flag.key: flag.defaultValue,
        },
        <String, Object>{
          'announcement_banner_enabled': false,
          'announcement_message_ko': '',
          'announcement_message_en': '',
          'announcement_message_ja': '',
        },
      );

      final container = ProviderContainer(
        overrides: [isFirebaseInitializedProvider.overrideWithValue(false)],
      );
      addTearDown(container.dispose);

      final values = container.read(featureFlagsProvider);
      expect(values, FeatureFlagValues.defaults);
      expect(values.boolValue(FeatureFlag.announcementBannerEnabled), isFalse);
      for (final flag in <FeatureFlag>[
        FeatureFlag.announcementMessageKo,
        FeatureFlag.announcementMessageEn,
        FeatureFlag.announcementMessageJa,
      ]) {
        expect(values.stringValue(flag), isEmpty);
      }
    });

    test('T-17-RC-02 표시 문구 = 앱 언어 → en → 없음 (D-36 · edge empty/partial)', () {
      const ko = Locale('ko');
      expect(
        resolveAnnouncementText(_values(enabled: false, ko: '공지 A'), ko),
        isNull,
      );
      expect(resolveAnnouncementText(_values(ko: '공지 A'), ko), '공지 A');
      expect(resolveAnnouncementText(_values(en: 'Notice'), ko), 'Notice');
      expect(resolveAnnouncementText(_values(), ko), isNull);
      expect(
        resolveAnnouncementText(_values(en: 'Notice'), const Locale('ja')),
        'Notice',
      );
      expect(
        resolveAnnouncementText(_values(ja: 'お知らせ'), const Locale('ja')),
        'お知らせ',
      );
      // 지원 밖 언어는 en 칸을 읽는다.
      expect(
        resolveAnnouncementText(
          _values(ko: '공지 A', en: 'Notice'),
          const Locale('fr'),
        ),
        'Notice',
      );
      // 앱은 문구를 가공하지 않는다 — 공백도 그대로다.
      expect(resolveAnnouncementText(_values(ko: ' 공지 A '), ko), ' 공지 A ');
    });
  });
}
