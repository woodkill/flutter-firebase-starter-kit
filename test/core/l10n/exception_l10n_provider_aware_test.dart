import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/l10n/exception_l10n.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// 주어진 로케일(기본 `en`) 위젯 트리에서 [resolveExceptionMessage]를 호출하여
/// 번역된 문자열을 반환한다.
Future<String> _resolve(
  WidgetTester tester,
  AppException ex, {
  Locale locale = const Locale('en'),
}) async {
  late String resolved;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
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
  // Phase 16 Task 4.1 — _resolveAccountExists provider-aware variant.
  //
  // L1: exception.existingProvider != null → errorAccountExistsWithProvider
  //     placeholder 가 정확 provider 라벨 (authAccountProvider{X}) 로 채워진다.
  // L2: existingProvider == null → errorAccountExistsWithUnknownProvider (R2
  //     baseline 보존).
  group(
    'resolveExceptionMessage — provider-aware variant (L1) — 7 provider',
    () {
      testWidgets('Google → provider 라벨 포함', (tester) async {
        final result = await _resolve(
          tester,
          const AccountExistsWithDifferentCredential(
            email: 'a@example.com',
            existingProvider: AccountProvider.google,
          ),
        );
        expect(result, contains('Google'));
      });

      testWidgets('Apple → provider 라벨 포함', (tester) async {
        final result = await _resolve(
          tester,
          const AccountExistsWithDifferentCredential(
            existingProvider: AccountProvider.apple,
          ),
        );
        expect(result, contains('Apple'));
      });

      testWidgets('Facebook → provider 라벨 포함', (tester) async {
        final result = await _resolve(
          tester,
          const AccountExistsWithDifferentCredential(
            existingProvider: AccountProvider.facebook,
          ),
        );
        expect(result, contains('Facebook'));
      });

      testWidgets('Email → provider 라벨 포함', (tester) async {
        final result = await _resolve(
          tester,
          const AccountExistsWithDifferentCredential(
            existingProvider: AccountProvider.email,
          ),
        );
        // EN 라벨: "Email / Password"
        expect(result, contains('Email'));
      });

      testWidgets('Kakao → provider 라벨 포함', (tester) async {
        final result = await _resolve(
          tester,
          const AccountExistsWithDifferentCredential(
            existingProvider: AccountProvider.kakao,
          ),
        );
        expect(result, contains('Kakao'));
      });

      testWidgets('Naver → provider 라벨 포함', (tester) async {
        final result = await _resolve(
          tester,
          const AccountExistsWithDifferentCredential(
            existingProvider: AccountProvider.naver,
          ),
        );
        expect(result, contains('Naver'));
      });

      testWidgets('LINE → provider 라벨 포함', (tester) async {
        final result = await _resolve(
          tester,
          const AccountExistsWithDifferentCredential(
            existingProvider: AccountProvider.line,
          ),
        );
        // EN 라벨: "LINE"
        expect(result.toUpperCase(), contains('LINE'));
      });
    },
  );

  group('resolveExceptionMessage — unknown fallback (L2)', () {
    testWidgets('existingProvider == null → R2 unknown fallback 메시지 (회귀 가드)', (
      tester,
    ) async {
      final result = await _resolve(
        tester,
        const AccountExistsWithDifferentCredential(email: 'a@example.com'),
      );
      expect(result, contains('originally used'));
    });
  });

  // quick 260928-bgk — ko 조사 규칙 (16.8 UI-SPEC §Copywriting): `{provider}`
  // 바로 뒤에 받침 의존 조사를 붙이지 않고 고정 명사 「계정」 에 붙인다.
  // Facebook(페이스북 · ㄱ 받침) · 라인(ㄴ 받침)에서 「Facebook로 · 라인로」 가
  // 렌더되던 결함의 회귀 가드. 라벨은 ARB 에서 읽어 리터럴 중복을 피한다.
  group('errorAccountExistsWithProvider — ko 조사 규칙 (quick 260928-bgk)', () {
    test('7 provider 라벨 전부 「{label} 계정으로」 형태이고 「{label}로」 는 없다', () {
      final ko = lookupAppLocalizations(const Locale('ko'));
      final labels = [
        ko.authAccountProviderGoogle,
        ko.authAccountProviderApple,
        ko.authAccountProviderFacebook,
        ko.authAccountProviderEmailPassword,
        ko.authAccountProviderKakao,
        ko.authAccountProviderNaver,
        ko.authAccountProviderLine,
      ];
      for (final label in labels) {
        final message = ko.errorAccountExistsWithProvider(label);
        expect(message, contains('$label 계정으로'), reason: label);
        expect(message, isNot(contains('$label로')), reason: label);
        expect(message, isNot(contains('$label으로')), reason: label);
      }
    });

    test('Facebook · 라인 — 사용자 확정 문구 verbatim (2026-09-28 선택 B)', () {
      final ko = lookupAppLocalizations(const Locale('ko'));
      expect(
        ko.errorAccountExistsWithProvider(ko.authAccountProviderFacebook),
        '이 이메일은 Facebook 계정으로 가입되어 있습니다. Facebook 계정으로 로그인하여 연결하세요.',
      );
      expect(
        ko.errorAccountExistsWithProvider(ko.authAccountProviderLine),
        '이 이메일은 라인 계정으로 가입되어 있습니다. 라인 계정으로 로그인하여 연결하세요.',
      );
    });

    testWidgets('resolveExceptionMessage ko 경로 — Facebook 이 「계정으로」 로 이어진다', (
      tester,
    ) async {
      final result = await _resolve(
        tester,
        const AccountExistsWithDifferentCredential(
          existingProvider: AccountProvider.facebook,
        ),
        locale: const Locale('ko'),
      );
      expect(
        result,
        '이 이메일은 Facebook 계정으로 가입되어 있습니다. Facebook 계정으로 로그인하여 연결하세요.',
      );
    });
  });
}
