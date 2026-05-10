import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/l10n/exception_l10n.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// 영어 로케일 위젯 트리에서 [resolveExceptionMessage]를 호출하여
/// 번역된 문자열을 반환한다.
Future<String> _resolve(WidgetTester tester, AppException ex) async {
  late String resolved;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          resolved = resolveExceptionMessage(context, ex);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return resolved;
}

void main() {
  group('resolveExceptionMessage 신규 AuthException 매핑', () {
    testWidgets('InvalidEmail → 영어 메시지', (tester) async {
      final result = await _resolve(tester, const InvalidEmail());
      expect(result, 'This email address is not valid.');
    });

    testWidgets('UserDisabled → 영어 메시지', (tester) async {
      final result = await _resolve(tester, const UserDisabled());
      expect(result, 'This account has been disabled. Contact support.');
    });

    testWidgets('TooManyRequests → 영어 메시지', (tester) async {
      final result = await _resolve(tester, const TooManyRequests());
      expect(result, 'Too many attempts. Please try again later.');
    });
  });

  group('resolveExceptionMessage 기존 매핑 회귀 검증', () {
    testWidgets('InvalidCredentials → 영어 메시지', (tester) async {
      final result = await _resolve(tester, const InvalidCredentials());
      expect(result, 'Invalid email or password.');
    });

    testWidgets('NoInternetConnection → 영어 메시지', (tester) async {
      final result = await _resolve(tester, const NoInternetConnection());
      expect(result, 'No internet connection.');
    });

    testWidgets('ServiceUnavailable → 영어 메시지', (tester) async {
      final result = await _resolve(tester, const ServiceUnavailable());
      expect(result, 'Service is temporarily unavailable.');
    });
  });

  // (Phase 9.2 R2 — Path A-narrow) AccountExistsWithDifferentCredential 인스
  // 턴스는 email 유무와 무관하게 단일 unknown fallback 메시지로 매핑된다.
  // exception_l10n.dart 의 special-case branch (instance type-check + 조기
  // return) 가 _mapAuthException 의 'account-exists-with-different-credential'
  // 분기 + _mapFunctionsException 의 'already-exists' 분기 모두 동일 경로로
  // 흡수한다. Phase 17 (Account Linking) — see ROADMAP.md 부활 시 본 분기
  // 안에서 server-side provider 매핑 input 으로 활용.
  group(
    'Phase 9.2 R2 — AccountExistsWithDifferentCredential → unknown fallback',
    () {
      testWidgets(
        'email != null → errorAccountExistsWithUnknownProvider',
        (tester) async {
          final result = await _resolve(
            tester,
            const AccountExistsWithDifferentCredential(
              email: 'old@example.com',
            ),
          );
          expect(
            result,
            'This email is already registered with another sign-in method. '
            'Please sign in with the method you originally used.',
          );
        },
      );

      testWidgets(
        "email == null (Cloud Function 'already-exists' 경로) → 동일 unknown "
        '메시지',
        (tester) async {
          final result = await _resolve(
            tester,
            const AccountExistsWithDifferentCredential(),
          );
          expect(result, contains('originally used'));
        },
      );
    },
  );
}
