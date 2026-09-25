import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/account_linking_sheet.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// Phase 16 Plan 16-04 Task 4.2 — AccountLinkingSheet widget test (W1~W7).
///
/// **viewport 정책:** test/widgetTester default (800x600) 는 sheet
/// 75% 제약 (maxHeight) 하에서 본 sheet 의 모든 inline 컴포넌트가 한
/// frame 에 표시될 수 있어 ensureVisible 불필요. W6 만 좁은 viewport
/// (320x480) 에서 ensureVisible 패턴 mirror (memory
/// `feedback_test_viewport_ensure_visible`).
///
/// **timer/animation 회피:** `pumpAndSettle` 무한 루프 회피를 위해 명시적
/// `pump(Duration(milliseconds: 500))` 으로 sheet entrance animation 종료
/// 후 한 frame 만 더 그린다 — `BrandedSocialButton` 의 비동기 자산
/// 디코딩 도중 settle 안 되는 경우 방어.

const Duration _kSheetEntranceDuration = Duration(milliseconds: 500);

/// sheet 결과 Future 를 캡슐화한 wrapper — `await _pumpAndShowSheet` 이
/// 내부 sheet Future 까지 자동 await 하여 hang 되는 함정 (Dart async
/// auto-unwrapping) 회피.
class _SheetHandle {
  _SheetHandle(this.result);
  final Future<bool?>? result;
}

/// [AccountLinkingSheet] 를 단독 띄워 테스트하는 harness.
///
/// sheet 의 Future 는 `_SheetHandle` 로 감싸서 반환 — async 함수의 자동
/// Future unwrap 이 sheet pop 까지 await 하지 않도록 한다.
Future<_SheetHandle> _pumpAndShowSheet(
  WidgetTester tester, {
  required AccountProvider provider,
  Locale locale = const Locale('en'),
}) async {
  Future<bool?>? sheetResult;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                sheetResult = AccountLinkingSheet.show(
                  context,
                  existingProvider: provider,
                );
              },
              child: const Text('open-sheet'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open-sheet'));
  // sheet entrance animation 종료 대기 (pumpAndSettle 무한 루프 회피)
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(_kSheetEntranceDuration);
  return _SheetHandle(sheetResult);
}

void main() {
  group('AccountLinkingSheet — W1 show happy path (Kakao)', () {
    testWidgets('Kakao label 노출 + Kakao BrandedSocialButton 단일', (
      tester,
    ) async {
      await _pumpAndShowSheet(tester, provider: AccountProvider.kakao);

      // 본문 메시지에 Kakao 라벨 포함 (errorAccountExistsWithProvider 채워짐)
      expect(find.textContaining('Kakao'), findsAtLeast(1));
      // 단일 BrandedSocialButton 노출 (D-02)
      expect(find.byType(BrandedSocialButton), findsOneWidget);
    });
  });

  group('AccountLinkingSheet — W2 provider variant (Google)', () {
    testWidgets('Google label 노출 + 단일 BrandedSocialButton', (tester) async {
      await _pumpAndShowSheet(tester, provider: AccountProvider.google);

      expect(find.textContaining('Google'), findsAtLeast(1));
      expect(find.byType(BrandedSocialButton), findsOneWidget);
    });
  });

  group('AccountLinkingSheet — W3 cancel/dismiss (D-03)', () {
    testWidgets(
      '"Sign in with another method" TextButton 탭 → Navigator.pop(false)',
      (tester) async {
        final handle = await _pumpAndShowSheet(
          tester,
          provider: AccountProvider.kakao,
        );

        // sheet 노출 확인 (sanity)
        expect(find.text('Sign in with another method'), findsOneWidget);

        await tester.tap(find.text('Sign in with another method'));
        await tester.pump();
        await tester.pump(_kSheetEntranceDuration);

        // sheet 가 dismiss 되어 sentinel TextButton 사라짐
        expect(find.text('Sign in with another method'), findsNothing);
        // Navigator.pop(false) 결과 검증 (D-03)
        expect(await handle.result, isFalse);
      },
    );
  });

  group('AccountLinkingSheet — W4 single button assertion (D-02)', () {
    testWidgets('Sheet 안 BrandedSocialButton 정확히 1 개', (tester) async {
      await _pumpAndShowSheet(tester, provider: AccountProvider.naver);

      // D-02 single button — 다른 6 provider 의 BrandedSocialButton 0 노출
      expect(find.byType(BrandedSocialButton), findsOneWidget);
    });
  });

  group('AccountLinkingSheet — W5 a11y tap target ≥48dp', () {
    testWidgets('BrandedSocialButton height ≥ 48dp', (tester) async {
      await _pumpAndShowSheet(tester, provider: AccountProvider.line);

      final size = tester.getSize(find.byType(BrandedSocialButton));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('AccountLinkingSheet — W6 ensureVisible viewport defensive', () {
    testWidgets(
      '좁은 viewport (320x480) 에서 CTA tester.ensureVisible 후 hit-test 성공',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        Future<bool?>? sheetResult;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () {
                      sheetResult = AccountLinkingSheet.show(
                        context,
                        existingProvider: AccountProvider.kakao,
                      );
                    },
                    child: const Text('open-sheet'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open-sheet'));
        await tester.pump();
        await tester.pump(_kSheetEntranceDuration);

        // 좁은 viewport 에서 CTA hit-test 회피
        // (feedback_test_viewport_ensure_visible memory mirror)
        final dismissBtn = find.text('Sign in with another method');
        await tester.ensureVisible(dismissBtn);
        await tester.pump();
        await tester.tap(dismissBtn);
        await tester.pump();
        await tester.pump(_kSheetEntranceDuration);

        expect(await sheetResult, isFalse);
      },
    );
  });

  group('AccountLinkingSheet — W8 헤더 텍스트 렌더 (UI-REVIEW Top 3 #1)', () {
    testWidgets('시트 노출 시 en 헤더 문구가 정확히 1 개 렌더', (tester) async {
      await _pumpAndShowSheet(tester, provider: AccountProvider.kakao);

      // 헤더 ARB 게터의 en 값 (클래스 doc 레이아웃 3번 항목)
      expect(find.text('Email already in use'), findsOneWidget);
    });
  });

  group('AccountLinkingSheet — W9 헤더가 본문 위 배치', () {
    testWidgets('헤더 dy < 본문 dy (레이아웃 3 → 5 순서)', (tester) async {
      await _pumpAndShowSheet(tester, provider: AccountProvider.kakao);

      final header = find.text('Email already in use');
      final body = find.textContaining('This email is registered with');
      expect(header, findsOneWidget);
      expect(body, findsOneWidget);

      // 헤더가 본문보다 위(작은 dy)에 놓여야 한다.
      expect(
        tester.getTopLeft(header).dy,
        lessThan(tester.getTopLeft(body).dy),
      );
    });
  });

  group('AccountLinkingSheet — W7 provider 7 variant smoke', () {
    for (final provider in AccountProvider.values) {
      testWidgets('${provider.name} → sheet 렌더링 성공 (no exception)', (
        tester,
      ) async {
        await _pumpAndShowSheet(tester, provider: provider);
        // email 은 FilledButton fallback, 나머지 6 은 BrandedSocialButton
        if (provider == AccountProvider.email) {
          expect(find.byType(FilledButton), findsAtLeast(1));
        } else {
          expect(find.byType(BrandedSocialButton), findsOneWidget);
        }
      });
    }
  });

  group('AccountLinkingSheet — W10 헤더/본문 색 위계 (UI-REVIEW #8)', () {
    testWidgets('본문 onSurfaceVariant / 헤더 onSurface (Surface A verbatim)', (
      tester,
    ) async {
      await _pumpAndShowSheet(tester, provider: AccountProvider.kakao);

      final theme = Theme.of(tester.element(find.byType(AccountLinkingSheet)));

      // 두 role 이 같은 값이면 아래 두 단언이 서로를 구분하지 못한다
      // (공허한 가드 방지 — 테마 수준 전제).
      expect(
        theme.colorScheme.onSurface,
        isNot(equals(theme.colorScheme.onSurfaceVariant)),
      );

      final header = tester.widget<Text>(find.text('Email already in use'));
      final body = tester.widget<Text>(
        find.textContaining('This email is registered with'),
      );

      // W10-a: 본문은 UI-SPEC Layout Contract Surface A 의 onSurfaceVariant.
      expect(body.style?.color, equals(theme.colorScheme.onSurfaceVariant));

      // W10-b: 헤더는 onSurface 유지 (헤더 회귀 방지).
      expect(header.style?.color, equals(theme.colorScheme.onSurface));
    });
  });
}
