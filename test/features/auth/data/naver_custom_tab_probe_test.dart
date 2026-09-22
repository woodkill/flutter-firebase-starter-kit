// Phase 16.4 — see ROADMAP.md (레버 2 — 커스텀탭 계수 MethodChannel probe)
//
// P-03 「조용한 실패만 테스트」: Kotlin 컴파일 실패 · 채널 미등록은 빌드와
// `MissingPluginException` 이 시끄럽게 알린다. 여기서 잠그는 것은 Dart 측
// graceful 흡수(채널 없음 → 0 · throw 0)와 플랫폼 가드뿐이다.
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, PlatformException;
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/features/auth/data/naver_custom_tab_probe.dart';

/// 호스트 채널 — `MainActivity.kt` 의 `CHANNEL` 상수와 같은 문자열이어야 한다.
const MethodChannel kProbeChannel = MethodChannel(
  'com.slimpumpkin.flutter_starter_kit/naver_custom_tab',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> calls;

  setUp(() {
    calls = <String>[];
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kProbeChannel, null);
  });

  /// 채널에 fake handler 를 건다 — [getCount] 가 `getCount` 응답값이다.
  void mockHost({int getCount = 0, bool throwPlatformException = false}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kProbeChannel, (MethodCall call) async {
          calls.add(call.method);
          if (throwPlatformException) {
            throw PlatformException(code: 'boom');
          }
          return switch (call.method) {
            'getCount' => getCount,
            'resetCount' => null,
            _ => null,
          };
        });
  }

  group('NaverCustomTabProbe (T-16.4-NAVER-PROBE)', () {
    test('T-16.4-NAVER-PROBE-01: 호스트가 2 를 돌려주면 readCount() == 2 이고 '
        'resetCount() 는 resetCount 메서드를 1회 호출한다', () async {
      mockHost(getCount: 2);
      const probe = NaverCustomTabProbe();

      await probe.resetCount();
      expect(
        calls,
        equals(<String>['resetCount']),
        reason: '시도 시작 시 계수를 되돌리지 않으면 직전 시도의 값이 누적된다',
      );

      expect(await probe.readCount(), equals(2));
      expect(calls, equals(<String>['resetCount', 'getCount']));
    });

    test('T-16.4-NAVER-PROBE-02: handler 가 없으면 '
        '(MissingPluginException) readCount() == 0 이고 throw 하지 않는다', () async {
      // 양성 대조군 — handler 를 걸면 실제로 채널이 응답한다. 아래 0 단언이
      // 「채널이 애초에 안 불렸다」 로 공허하게 참이 되는 것을 막는다.
      mockHost(getCount: 7);
      const probe = NaverCustomTabProbe();
      expect(await probe.readCount(), equals(7), reason: '대조군 — 채널은 살아 있다');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kProbeChannel, null);

      expect(await probe.readCount(), equals(0));
      await probe.resetCount(); // throw 하지 않는다 (T-16.4-13 DoS 완화)
    });

    test('T-16.4-NAVER-PROBE-03: PlatformException 도 삼켜 0 / no-op 으로 '
        '흡수한다', () async {
      mockHost(throwPlatformException: true);
      const probe = NaverCustomTabProbe();

      expect(await probe.readCount(), equals(0));
      await probe.resetCount();
      expect(
        calls.length,
        greaterThanOrEqualTo(2),
        reason: '대조군 — 두 호출 모두 채널에 실제로 도달했다',
      );
    });

    test('T-16.4-NAVER-PROBE-04: iOS 에서는 채널을 호출조차 하지 않고 0 이다 '
        '(D-06 — 결함은 Android 한정)', () async {
      mockHost(getCount: 5);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const probe = NaverCustomTabProbe();

      expect(await probe.readCount(), equals(0));
      await probe.resetCount();
      expect(
        calls,
        isEmpty,
        reason: 'iOS 는 ASWebAuthenticationSession 경로라 대상이 아니다',
      );
    });
  });
}
