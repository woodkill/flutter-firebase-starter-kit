// Phase 17 Plan 17-13 — Remote Config typed Feature Flag · 공지 표시 문구 결정.
//
// T-17-RC-01 · 02 (Task 1): enum 키 · 기본값 · 미초기화 기본값 · 언어 → en →
// 없음 규칙(D-36).
// T-17-RC-04 · 05 (Task 2): onConfigUpdated → activate → state 갱신 · kill
// switch 재평가 · 오류 non-fatal 1회 · dispose 시 구독 해제(D-10 · Pitfall 14).

import 'dart:async';
import 'dart:ui' show Locale;

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/config/app_config.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/remote_config/feature_flag.dart';
import 'package:flutter_starter_kit/core/remote_config/feature_flags_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRemoteConfig extends Mock implements FirebaseRemoteConfig {}

class _MockCrashlytics extends Mock implements CrashlyticsService {}

/// 실시간 구독 오류 기록 reason (D-10 · T-17-45).
const String _updateReason = 'feature_flags_on_config_updated';

/// mock Remote Config 의 활성 값 — 키 → bool | String.
///
/// [_stubRemoteConfig] 가 `getBool` · `getString` 을 이 맵에서 읽게 한다.
final Map<String, Object> _active = <String, Object>{};

/// [rc] 의 읽기 API 를 [_active] 로 stub 한다 — 키 없음은 SDK 정적 기본값.
void _stubRemoteConfig(_MockRemoteConfig rc) {
  when(() => rc.getBool(any())).thenAnswer((invocation) {
    final value = _active[invocation.positionalArguments.first];
    return value is bool && value;
  });
  when(() => rc.getString(any())).thenAnswer((invocation) {
    final value = _active[invocation.positionalArguments.first];
    return value is String ? value : '';
  });
  // kill switch 키 없음 → 정적 enabled 그대로(activeStrategies D-25).
  when(rc.getAll).thenReturn(<String, RemoteConfigValue>{});
}

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
      // 공백만 있는 칸은 빈 칸 — 다음 칸으로 넘어가고, 둘 다면 배너 없음
      // (리뷰 IN-12). 표시 문구는 원문 그대로다.
      expect(
        resolveAnnouncementText(_values(ko: '  ', en: ' Notice'), ko),
        ' Notice',
      );
      expect(resolveAnnouncementText(_values(ko: ' ', en: '\n\t'), ko), isNull);
    });

    group('실시간 반영 (D-10)', () {
      late _MockRemoteConfig rc;
      late _MockCrashlytics crashlytics;
      late StreamController<RemoteConfigUpdate> updates;
      late int cancelCount;

      setUpAll(() {
        registerFallbackValue(StackTrace.empty);
      });

      setUp(() {
        _active.clear();
        rc = _MockRemoteConfig();
        crashlytics = _MockCrashlytics();
        cancelCount = 0;
        updates = StreamController<RemoteConfigUpdate>(
          onCancel: () => cancelCount++,
        );
        // 리스너가 없으면 close() Future 가 끝나지 않는다 — 기다리지 않는다.
        addTearDown(() => unawaited(updates.close()));
        _stubRemoteConfig(rc);
        when(() => rc.onConfigUpdated).thenAnswer((_) => updates.stream);
        when(
          () => crashlytics.recordError(
            any<Object>(),
            any(),
            reason: any(named: 'reason'),
          ),
        ).thenAnswer((_) async {});
      });

      ProviderContainer makeContainer() {
        return ProviderContainer(
          overrides: [
            isFirebaseInitializedProvider.overrideWithValue(true),
            firebaseRemoteConfigProvider.overrideWithValue(rc),
            crashlyticsServiceProvider.overrideWithValue(crashlytics),
            staticAuthProvidersProvider.overrideWithValue(<String, bool>{
              for (final id in kAllProviderIds) id: id == kProviderIdGoogle,
            }),
          ],
        );
      }

      test(
        'T-17-RC-04 변경 이벤트 → activate 1회 · 새 값 · kill switch 재평가 1회',
        () async {
          when(rc.activate).thenAnswer((_) async {
            _active
              ..['announcement_banner_enabled'] = true
              ..['announcement_message_ko'] = '공지 A';
            return true;
          });
          final container = makeContainer();
          addTearDown(container.dispose);

          expect(
            container.read(featureFlagsProvider),
            FeatureFlagValues.defaults,
          );
          var strategyUpdates = 0;
          container.listen(
            activeStrategiesProvider,
            (_, _) => strategyUpdates++,
          );

          updates.add(
            RemoteConfigUpdate(<String>{
              'announcement_banner_enabled',
              'announcement_message_ko',
            }),
          );
          await pumpEventQueue();
          await container.pump();

          verify(rc.activate).called(1);
          expect(
            resolveAnnouncementText(
              container.read(featureFlagsProvider),
              const Locale('ko'),
            ),
            '공지 A',
          );
          expect(strategyUpdates, 1);
          verifyNever(
            () => crashlytics.recordError(
              any<Object>(),
              any(),
              reason: any(named: 'reason'),
            ),
          );
        },
      );

      test(
        'T-17-RC-05 스트림 오류 · activate 실패 → state 불변 · 기록 1회씩 · dispose → cancel 1회',
        () async {
          _active['announcement_banner_enabled'] = true;
          _active['announcement_message_en'] = 'Notice';
          final container = makeContainer();
          final before = container.read(featureFlagsProvider);
          expect(resolveAnnouncementText(before, const Locale('en')), 'Notice');

          // 스트림 onError — throw 0 · state 그대로 · non-fatal 1회.
          updates.addError(StateError('realtime'), StackTrace.current);
          await pumpEventQueue();
          expect(container.read(featureFlagsProvider), before);
          verify(
            () => crashlytics.recordError(
              any<Object>(),
              any(),
              reason: _updateReason,
            ),
          ).called(1);

          // 콜백 안 activate 실패 — 같은 reason 으로 1회.
          when(rc.activate).thenThrow(StateError('activate'));
          updates.add(RemoteConfigUpdate(<String>{'announcement_message_en'}));
          await pumpEventQueue();
          expect(container.read(featureFlagsProvider), before);
          verify(
            () => crashlytics.recordError(
              any<Object>(),
              any(),
              reason: _updateReason,
            ),
          ).called(1);

          expect(cancelCount, 0);
          container.dispose();
          expect(cancelCount, 1);
        },
      );

      test('T-17-RC-05 구독 자체가 throw 하면 읽은 값 유지 · throw 0 (Pitfall 14)', () {
        _active['announcement_banner_enabled'] = true;
        _active['announcement_message_ko'] = '공지 A';
        when(() => rc.onConfigUpdated).thenThrow(UnsupportedError('platform'));
        final container = makeContainer();
        addTearDown(container.dispose);

        expect(
          resolveAnnouncementText(
            container.read(featureFlagsProvider),
            const Locale('ko'),
          ),
          '공지 A',
        );
      });
    });
  });
}
