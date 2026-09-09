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

  // WR-03 (2차 리뷰) — ProviderAlreadyLinkedToThisAccount 는
  // `provider-already-linked` (이미 *현재* 계정에 연결) 다. 이전에는
  // AccountAlreadyLinked 와 동일한 errorAccountExistsWithUnknownProvider
  // ("다른 방식으로 가입되어 있습니다 — 처음 가입한 방식으로 다시 로그인") 를
  // 공유해 reactive 표면에 사실과 정반대 안내가 나갔다.
  group('resolveExceptionMessage WR-03 — provider-already-linked 전용 문구', () {
    testWidgets('ProviderAlreadyLinkedToThisAccount → 전용 문구', (tester) async {
      final result = await _resolve(
        tester,
        const ProviderAlreadyLinkedToThisAccount(),
      );
      expect(result, 'This account is already linked to that sign-in method.');
    });

    testWidgets('의미 정반대 collapse 문구로 되돌아가지 않는다', (tester) async {
      final result = await _resolve(
        tester,
        const ProviderAlreadyLinkedToThisAccount(),
      );
      // AccountAlreadyLinked 계열 문구 / 이메일 collapse 문구 미노출.
      expect(result, isNot(contains('another account')));
      expect(result, isNot(contains('different')));
      // ARB 키 문자열이 그대로 새어 나오지 않는다 (매핑 누락 회귀 가드).
      expect(result, isNot(contains('settingsLinkFailed')));
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

      // WR-04: instance type-check early return (line 22-24) 이 switch arm
      // (line 45-46, 'errorAccountExistsWithDifferentCredential') 보다 우선
      // 한다는 dead-code anchor invariant. early return 이 삭제되거나
      // 위치가 바뀌면 dead arm 의 'Please sign in with your password.' 가
      // 노출되어 Phase 9.2 R2 Path A-narrow 의도 (unknown fallback) 가 RED
      // 으로 깨진다. switch arm 의 ARB key + getter 자체는 Phase 17 Account
      // Linking 부활 anchor 로 의도 보존.
      testWidgets(
        'INVARIANT: instance type-check early return 우선 (Phase 17 anchor '
        '보존 + dead-arm 메시지 비노출)',
        (tester) async {
          const ex = AccountExistsWithDifferentCredential();
          // 1. ARB key 가 dead-arm key 와 일치 — Phase 17 부활 anchor 유지.
          expect(ex.userMessage, 'errorAccountExistsWithDifferentCredential');
          // 2. 실제 해석된 메시지는 unknown fallback (early return 경로) 이며
          //    dead arm 의 password-prompt 카피가 절대 노출되지 않는다.
          final resolved = await _resolve(tester, ex);
          expect(resolved, contains('originally used'));
          expect(
            resolved,
            isNot(contains('Please sign in with your password')),
          );
        },
      );
    },
  );
}
