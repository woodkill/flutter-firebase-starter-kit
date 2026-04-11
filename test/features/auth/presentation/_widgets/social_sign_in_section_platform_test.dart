import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_button/sign_in_button.dart';

import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_sign_in_section.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// [AuthRepository]를 mocktail로 대체하기 위한 Mock.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// 테스트 harness — [ProviderScope] + [MaterialApp] + [SocialSignInSection].
///
/// [brightness]로 라이트/다크 테마를 전환하고, [repository]를 주입해
/// `authRepositoryProvider`를 override한다. [isFormLoading]은 이메일 폼
/// 로딩 상태를 시뮬레이션한다.
Widget buildHarness({
  required Brightness brightness,
  required AuthRepository repository,
  bool isFormLoading = false,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      // AppTheme.light/dark는 AppSpacing/AppTypography/AppColors
      // ThemeExtension을 등록한다. context.appSpacing null 가드 필수.
      theme: brightness == Brightness.dark
          ? AppTheme.dark()
          : AppTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SocialSignInSection(isFormLoading: isFormLoading),
      ),
    ),
  );
}

void main() {
  late _MockAuthRepository mockRepo;

  setUp(() {
    mockRepo = _MockAuthRepository();
    // 기본값: Google/Apple 로그인 호출 시 취소(null)로 조용히 무시.
    when(() => mockRepo.signInWithGoogle()).thenAnswer((_) async => null);
    when(() => mockRepo.signInWithApple()).thenAnswer((_) async => null);
  });

  /// 플랫폼 override 해제 보장 wrapper.
  ///
  /// `AutomatedTestWidgetsFlutterBinding._runTestBody`는 testBody가
  /// 끝난 직후 동기적으로 `_verifyInvariants`를 호출해 foundation debug
  /// 변수가 unset 상태인지 검사한다. `tearDown` 이나 `addTearDown`은
  /// 이 검증보다 **나중에** 실행되므로 try/finally로 복원해야 한다.
  Future<void> withPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  group('SocialSignInSection platform branching', () {
    testWidgets(
      'AUTH-03-11: iOS에서 Apple 버튼이 Google 버튼보다 먼저 렌더된다',
      (tester) async {
        await withPlatform(TargetPlatform.iOS, () async {
          await tester.pumpWidget(
            buildHarness(
              brightness: Brightness.light,
              repository: mockRepo,
            ),
          );
          await tester.pumpAndSettle();

          final buttons = tester
              .widgetList<SignInButton>(find.byType(SignInButton))
              .toList();
          expect(buttons.length, 2);
          // iOS: Apple 먼저(라이트 기준 Buttons.apple = 검정 배경).
          expect(buttons[0].button, Buttons.apple);
          expect(buttons[1].button, Buttons.google);
        });
      },
    );

    testWidgets(
      'AUTH-03-12: Android에서 Google 버튼이 Apple 버튼보다 먼저 렌더된다',
      (tester) async {
        await withPlatform(TargetPlatform.android, () async {
          await tester.pumpWidget(
            buildHarness(
              brightness: Brightness.light,
              repository: mockRepo,
            ),
          );
          await tester.pumpAndSettle();

          final buttons = tester
              .widgetList<SignInButton>(find.byType(SignInButton))
              .toList();
          expect(buttons.length, 2);
          // Android: Google 먼저.
          expect(buttons[0].button, Buttons.google);
          expect(buttons[1].button, Buttons.apple);
        });
      },
    );

    testWidgets(
      'AUTH-03-13: 라이트 모드에서 Buttons.apple (검정 배경) 렌더',
      (tester) async {
        await withPlatform(TargetPlatform.iOS, () async {
          await tester.pumpWidget(
            buildHarness(
              brightness: Brightness.light,
              repository: mockRepo,
            ),
          );
          await tester.pumpAndSettle();

          final buttons = tester
              .widgetList<SignInButton>(find.byType(SignInButton))
              .toList();
          final appleButton = buttons.firstWhere(
            (b) =>
                b.button == Buttons.apple || b.button == Buttons.appleDark,
          );
          expect(appleButton.button, Buttons.apple);
        });
      },
    );

    testWidgets(
      'AUTH-03-14: 다크 모드에서 Buttons.appleDark (흰색 배경) 렌더',
      (tester) async {
        await withPlatform(TargetPlatform.iOS, () async {
          await tester.pumpWidget(
            buildHarness(
              brightness: Brightness.dark,
              repository: mockRepo,
            ),
          );
          await tester.pumpAndSettle();

          final buttons = tester
              .widgetList<SignInButton>(find.byType(SignInButton))
              .toList();
          final appleButton = buttons.firstWhere(
            (b) =>
                b.button == Buttons.apple || b.button == Buttons.appleDark,
          );
          expect(appleButton.button, Buttons.appleDark);
        });
      },
    );

    testWidgets(
      'isFormLoading=true일 때 Apple 버튼 탭해도 '
      'signInWithApple이 호출되지 않는다',
      (tester) async {
        await withPlatform(TargetPlatform.iOS, () async {
          await tester.pumpWidget(
            buildHarness(
              brightness: Brightness.light,
              repository: mockRepo,
              isFormLoading: true,
            ),
          );
          await tester.pumpAndSettle();

          // iOS 순서: 첫 번째 SignInButton이 Apple.
          final buttons = tester
              .widgetList<SignInButton>(find.byType(SignInButton))
              .toList();
          expect(buttons.length, 2);
          expect(buttons[0].button, Buttons.apple);

          final appleButtonFinder = find.byWidget(buttons[0]);
          await tester.tap(appleButtonFinder);
          await tester.pumpAndSettle();

          // isFormLoading=true이면 onPressed가 빈 콜백으로 교체되어
          // Repository가 호출되지 않아야 한다.
          verifyNever(() => mockRepo.signInWithApple());
        });
      },
    );
  });
}
