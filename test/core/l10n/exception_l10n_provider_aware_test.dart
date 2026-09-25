import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/l10n/exception_l10n.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// 영어 로케일 위젯 트리에서 [resolveExceptionMessage]를 호출하여
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
}
