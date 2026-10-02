// Phase 17 Plan 17-16 — FCM 백그라운드 핸들러 등록 소스 계약 (T-17-PUSH-07).
//
// 백그라운드 핸들러는 별도 isolate 에서 돌고 실 SDK 등록은 Firebase 없이
// 실행할 수 없으므로, `bootstrap_crashlytics_test.dart` 와 같은 소스 문자열
// 계약으로 검증한다(주석 줄 제거 후 매칭 · 공백 무관 RegExp — dart-format 규율 3).
//
// 공식 규칙(firebase.google.com/docs/cloud-messaging/flutter/receive):
// top-level · 익명 함수 아님 · `@pragma('vm:entry-point')` · UI/상태 접근 금지.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [path] 소스에서 `//` 로 시작하는 주석 줄을 뺀 본문.
String _readCode(String path) => File(path)
    .readAsLinesSync()
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// [source] 에서 [pattern] 이 나타나는 횟수.
int _count(String source, Pattern pattern) => pattern.allMatches(source).length;

void main() {
  group('Phase 17 알림 수신 · 탭 (T-17-PUSH)', () {
    late String bootstrap;
    late String handler;

    setUpAll(() {
      bootstrap = _readCode('lib/core/bootstrap.dart');
      handler = _readCode(
        'lib/features/notifications/data/'
        'firebase_messaging_background_handler.dart',
      );
    });

    test('T-17-PUSH-07: bootstrap 이 top-level 핸들러를 onBackgroundMessage 로 '
        '1회 등록한다', () {
      expect(
        _count(
          bootstrap,
          RegExp(
            r'FirebaseMessaging\.onBackgroundMessage\(\s*'
            r'firebaseMessagingBackgroundHandler\s*,?\s*\)',
          ),
        ),
        1,
      );
    });

    test('T-17-PUSH-07: 등록은 isFirebaseInitialized 분기 안 · runApp 앞이다 '
        '(Phase 1 D-13)', () {
      final branchStart = bootstrap.indexOf('if (isFirebaseInitialized) {');
      final registration = bootstrap.indexOf(
        'registerBackgroundMessageHandler();',
      );
      final runApp = bootstrap.indexOf('runApp(');
      expect(branchStart, isNonNegative);
      expect(registration, isNonNegative);
      expect(runApp, isNonNegative);
      expect(registration, greaterThan(branchStart));
      expect(registration, lessThan(runApp));
      // 분기 블록이 등록 호출 전에 닫히지 않는다 — 분기 시작부터 등록 호출까지
      // 여는 · 닫는 중괄호 수 차이가 0 보다 커야 분기 안이다.
      final between = bootstrap.substring(branchStart, registration);
      final depth =
          '{'.allMatches(between).length - '}'.allMatches(between).length;
      expect(depth, greaterThan(0));
      // 등록 호출은 1곳뿐이다.
      expect(_count(bootstrap, 'registerBackgroundMessageHandler();'), 1);
    });

    test('T-17-PUSH-07: 등록은 try/catch 없는 Crashlytics setCustomKey · '
        'Remote Config fetch 앞이다 (리뷰 IN-07)', () {
      final registration = bootstrap.indexOf(
        'registerBackgroundMessageHandler();',
      );
      final flavorKey = bootstrap.indexOf(
        'FirebaseCrashlytics.instance.setCustomKey(',
      );
      final rcFetch = bootstrap.indexOf('fetchAndActivate()');
      expect(registration, isNonNegative);
      expect(flavorKey, isNonNegative);
      expect(rcFetch, isNonNegative);
      expect(registration, lessThan(flavorKey));
      expect(registration, lessThan(rcFetch));
    });

    test("T-17-PUSH-07: 핸들러 = @pragma('vm:entry-point') top-level 함수 · "
        'ref · WidgetsBinding · 로그 0', () {
      expect(_count(handler, "@pragma('vm:entry-point')"), 1);
      expect(
        _count(
          handler,
          RegExp(
            r'^Future<void> firebaseMessagingBackgroundHandler\('
            r'RemoteMessage message\)',
            multiLine: true,
          ),
        ),
        1,
      );
      expect(_count(handler, RegExp(r'ref\.|WidgetsBinding|debugPrint')), 0);
      expect(_count(handler, RegExp(r'\bclass\b')), 0);
    });
  });
}
