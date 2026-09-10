import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/or_divider.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_sign_in_section.dart';
import 'package:flutter_starter_kit/features/auth/presentation/email_signup_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// [AuthRepository] 를 mocktail 로 대체하기 위한 Mock.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// [EmailSignupScreen] 을 영문 로케일 + [AppTheme.light] 주입 상태로 pump 한다.
///
/// harness 는 `signup_screen_test.dart` 의 `_pumpSignup` verbatim 이며
/// (overrides 목록 · MaterialApp 구성 · pump 호출 횟수 동일) 화면 타입만
/// 교체했다 — override 를 "개선" 하면 listener 분기 도달이 달라진다.
Future<void> _pumpEmailSignup(
  WidgetTester tester,
  _MockAuthRepository mockRepo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(mockRepo),
        activeStrategiesProvider(const Locale('en')).overrideWithValue(
          const <AuthStrategy>[
            GoogleAuthStrategy(),
            AppleAuthStrategy(),
            FacebookAuthStrategy(),
          ],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const EmailSignupScreen(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late _MockAuthRepository mockRepo;

  setUp(() {
    mockRepo = _MockAuthRepository();
  });

  group('EmailSignupScreen', () {
    testWidgets('1. 빈 입력 제출 시 3개 validator 에러 inline 표시', (tester) async {
      await _pumpEmailSignup(tester, mockRepo);
      // AuthScaffold(SingleChildScrollView) content 가 default 800x600 viewport
      // 보다 길어 Create account 버튼이 viewport 밖에 위치. Test 2~ 는 enterText
      // → EditableText.ensureVisible 자동 우회. Test 1 만 텍스트 입력 0건이라
      // 명시적 ensureVisible 필요.
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Create account'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();

      expect(find.text('Enter your name.'), findsOneWidget);
      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(
        find.text('Password must be at least 8 characters.'),
        findsOneWidget,
      );
      verifyNever(
        () => mockRepo.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      );
    });

    testWidgets('2. displayName 33자 입력 시 too long 에러 표시', (tester) async {
      await _pumpEmailSignup(tester, mockRepo);
      final longName = 'a' * 33;
      await tester.enterText(find.byType(TextFormField).at(0), longName);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();

      expect(find.text('Name must be 32 characters or fewer.'), findsOneWidget);
    });

    testWidgets('3. 정상 입력 제출 시 Repository 호출 (트림 검증)', (tester) async {
      when(
        () => mockRepo.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer(
        (_) async => Result.success(
          User(
            uid: 'u1',
            email: 'new@example.com',
            emailVerified: true,
            displayName: 'Test User',
            createdAt: DateTime.utc(2026),
          ),
        ),
      );

      await _pumpEmailSignup(tester, mockRepo);
      await tester.enterText(find.byType(TextFormField).at(0), '  Test User  ');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        '  new@example.com  ',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'password123');
      final ctaFinder = find.widgetWithText(FilledButton, 'Create account');
      await tester.ensureVisible(ctaFinder);
      await tester.pumpAndSettle();
      await tester.tap(ctaFinder);
      await tester.pump();
      await tester.pumpAndSettle();

      verify(
        () => mockRepo.signUpWithEmail(
          email: 'new@example.com',
          password: 'password123',
          displayName: 'Test User',
        ),
      ).called(1);
    });

    testWidgets('4. EmailAlreadyInUse 에러 시 폼 상단 배너 표시', (tester) async {
      when(
        () => mockRepo.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) async => const Result.failure(EmailAlreadyInUse()));

      await _pumpEmailSignup(tester, mockRepo);
      await tester.enterText(find.byType(TextFormField).at(0), 'Name');
      await tester.enterText(find.byType(TextFormField).at(1), 'a@b.com');
      await tester.enterText(find.byType(TextFormField).at(2), 'password123');
      final ctaFinder = find.widgetWithText(FilledButton, 'Create account');
      await tester.ensureVisible(ctaFinder);
      await tester.pumpAndSettle();
      await tester.tap(ctaFinder);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Email is already in use.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('5. 로딩 중 spinner + 버튼 disabled', (tester) async {
      final completer = Completer<Result<User>>();
      when(
        () => mockRepo.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) => completer.future);

      await _pumpEmailSignup(tester, mockRepo);
      await tester.enterText(find.byType(TextFormField).at(0), 'Name');
      await tester.enterText(find.byType(TextFormField).at(1), 'a@b.com');
      await tester.enterText(find.byType(TextFormField).at(2), 'password123');
      final ctaFinder = find.widgetWithText(FilledButton, 'Create account');
      await tester.ensureVisible(ctaFinder);
      await tester.pumpAndSettle();
      await tester.tap(ctaFinder);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Create account'), findsNothing);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      completer.complete(
        Result.success(
          User(
            uid: 'u',
            email: 'a@b.com',
            emailVerified: true,
            displayName: 'Name',
            createdAt: DateTime.utc(2026),
          ),
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('6. 화면 렌더 시 navigation 미호출 (예외 없음)', (tester) async {
      await _pumpEmailSignup(tester, mockRepo);
      expect(tester.takeException(), isNull);
    });

    testWidgets('7. (Phase 16.1 SC 3) 소셜 섹션·OrDivider 가 렌더되지 않는다', (
      tester,
    ) async {
      await _pumpEmailSignup(tester, mockRepo);
      // 소셜 진입점은 A(chooser) / D(sheet) 로 단일화됐다 — C 에는 소셜
      // 에러가 도달할 경로 자체가 없다.
      expect(find.byType(SocialSignInSection), findsNothing);
      expect(find.byType(OrDivider), findsNothing);
    });
  });
}
