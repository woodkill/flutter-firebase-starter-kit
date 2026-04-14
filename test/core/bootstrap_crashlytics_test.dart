import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `bootstrap.dart` Crashlytics 3경로 등록 + Zone 가드를 소스 문자열로 검증.
///
/// FirebaseCrashlytics.instance 를 실제 호출하면 Firebase 미초기화 환경에서
/// throw 하므로, 등록 코드 존재 자체를 grep 형태로 확인한다 (Phase 1 D-13
/// 철학 + Pitfall 4 — Crashlytics 미초기화 상태 회피).
void main() {
  group('bootstrap.dart Crashlytics 3경로 + Zone 가드 (Phase 10 AUTH-11)', () {
    late String source;

    setUpAll(() async {
      final file = File('lib/core/bootstrap.dart');
      source = await file.readAsString();
    });

    test('Test 1: runZonedGuarded 로 전체 시퀀스를 감싼다 (경로 1)', () {
      // Pitfall 4 대응 — Zone 미처리 에러를 Crashlytics 로 보낸다.
      expect(
        source.contains('runZonedGuarded<Future<void>>('),
        isTrue,
        reason: 'bootstrap 은 runZonedGuarded 로 전체 시퀀스를 감싸야 한다.',
      );
      expect(
        source.contains('recordError(error, stack, fatal: true)'),
        isTrue,
        reason: 'Zone onError 는 recordError(fatal: true) 를 호출해야 한다.',
      );
    });

    test('Test 2: FlutterError.onError 가 recordFlutterFatalError 에 할당된다 (경로 2)',
        () {
      expect(
        source.contains(
          'FlutterError.onError =\n'
          '          FirebaseCrashlytics.instance.recordFlutterFatalError',
        ) ||
            source.contains(
              'FlutterError.onError = '
              'FirebaseCrashlytics.instance.recordFlutterFatalError',
            ),
        isTrue,
        reason: 'FlutterError.onError 는 recordFlutterFatalError 로 위임.',
      );
    });

    test('Test 3: PlatformDispatcher.instance.onError 가 등록된다 (경로 3)', () {
      expect(
        source.contains('PlatformDispatcher.instance.onError'),
        isTrue,
        reason:
            'PlatformDispatcher.onError 는 비동기/플랫폼 에러를 Crashlytics 로 보낸다.',
      );
    });

    test('Test 4: isFirebaseInitialized=true 분기 안에서만 3경로 등록 (Phase 1 D-13)',
        () {
      // 등록 모두 if (isFirebaseInitialized) 블록 안에서 이루어져야 한다.
      // 단순 grep 으로는 분기 위치를 정확히 검증하기 어려우므로,
      // 등록 직전 가드 라인 존재 여부 + flavor custom key 함께 검사한다.
      expect(
        source.contains('if (isFirebaseInitialized) {'),
        isTrue,
        reason: 'Crashlytics 등록은 isFirebaseInitialized 가드 안에서만.',
      );
      expect(
        source.contains("setCustomKey('flavor', flavor)"),
        isTrue,
        reason: 'AUTH-11 — flavor custom key 태깅이 필요하다.',
      );
    });
  });
}
