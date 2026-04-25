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

/// 테스트 harness -- [ProviderScope] + [MaterialApp] + [SocialSignInSection].
///
/// [brightness]로 라이트/다크 테마를 전환하고, [repository]를 주입해
/// `authRepositoryProvider`를 override한다. [isFormLoading]은 이메일 폼
/// 로딩 상태를 시뮬레이션한다. [errorBanner]는 소셜 에러 배너를 주입한다.
Widget buildHarness({
  required Brightness brightness,
  required AuthRepository repository,
  bool isFormLoading = false,
  Widget? errorBanner,
}) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      // AppTheme.light/dark는 AppSpacing/AppTypography/AppColors
      // ThemeExtension을 등록한다. context.appSpacing null 가드 필수.
      theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SocialSignInSection(
          isFormLoading: isFormLoading,
          errorBanner: errorBanner,
        ),
      ),
    ),
  );
}

void main() {
  late _MockAuthRepository mockRepo;

  setUp(() {
    mockRepo = _MockAuthRepository();
    // 기본값: Google/Apple/Facebook 로그인 호출 시 취소(null)로 조용히 무시.
    when(() => mockRepo.signInWithGoogle()).thenAnswer((_) async => null);
    when(() => mockRepo.signInWithApple()).thenAnswer((_) async => null);
    when(() => mockRepo.signInWithFacebook()).thenAnswer((_) async => null);
  });

  group('SocialSignInSection 통일 순서 (D-04)', () {
    testWidgets('3개 버튼이 Google -> Apple -> Facebook 순서로 렌더된다', (tester) async {
      await tester.pumpWidget(
        buildHarness(brightness: Brightness.light, repository: mockRepo),
      );
      await tester.pumpAndSettle();

      final buttons = tester
          .widgetList<SignInButton>(find.byType(SignInButton))
          .toList();
      expect(buttons.length, 3);
      // D-04: 플랫폼 무관 통일 순서 Google -> Apple -> Facebook.
      expect(buttons[0].button, Buttons.google);
      expect(buttons[1].button, Buttons.apple);
      expect(buttons[2].button, Buttons.facebookNew);
    });

    testWidgets('Facebook 버튼 탭 시 signInWithFacebook이 호출된다', (tester) async {
      await tester.pumpWidget(
        buildHarness(brightness: Brightness.light, repository: mockRepo),
      );
      await tester.pumpAndSettle();

      final buttons = tester
          .widgetList<SignInButton>(find.byType(SignInButton))
          .toList();
      expect(buttons[2].button, Buttons.facebookNew);

      final facebookButtonFinder = find.byWidget(buttons[2]);
      await tester.tap(facebookButtonFinder);
      await tester.pumpAndSettle();

      verify(() => mockRepo.signInWithFacebook()).called(1);
    });

    testWidgets('isFormLoading=true일 때 Facebook 버튼 탭해도 '
        'signInWithFacebook이 호출되지 않는다', (tester) async {
      await tester.pumpWidget(
        buildHarness(
          brightness: Brightness.light,
          repository: mockRepo,
          isFormLoading: true,
        ),
      );
      await tester.pumpAndSettle();

      final buttons = tester
          .widgetList<SignInButton>(find.byType(SignInButton))
          .toList();
      expect(buttons.length, 3);
      expect(buttons[2].button, Buttons.facebookNew);

      final facebookButtonFinder = find.byWidget(buttons[2]);
      await tester.tap(facebookButtonFinder);
      await tester.pumpAndSettle();

      // isFormLoading=true이면 onPressed가 빈 콜백으로 교체되어
      // Repository가 호출되지 않아야 한다.
      verifyNever(() => mockRepo.signInWithFacebook());
    });

    testWidgets('errorBanner가 소셜 버튼과 OrDivider 사이에 표시된다', (tester) async {
      await tester.pumpWidget(
        buildHarness(
          brightness: Brightness.light,
          repository: mockRepo,
          errorBanner: const Text('test error'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('test error'), findsOneWidget);
    });
  });

  group('SocialSignInSection 다크모드 버튼 변형', () {
    testWidgets('라이트 모드에서 Google=google, Apple=apple, '
        'Facebook=facebookNew', (tester) async {
      await tester.pumpWidget(
        buildHarness(brightness: Brightness.light, repository: mockRepo),
      );
      await tester.pumpAndSettle();

      final buttons = tester
          .widgetList<SignInButton>(find.byType(SignInButton))
          .toList();
      expect(buttons[0].button, Buttons.google);
      expect(buttons[1].button, Buttons.apple);
      expect(buttons[2].button, Buttons.facebookNew);
    });

    testWidgets('다크 모드에서 Google=googleDark, Apple=appleDark, '
        'Facebook=facebookNew (다크 변형 없음)', (tester) async {
      await tester.pumpWidget(
        buildHarness(brightness: Brightness.dark, repository: mockRepo),
      );
      await tester.pumpAndSettle();

      final buttons = tester
          .widgetList<SignInButton>(find.byType(SignInButton))
          .toList();
      expect(buttons[0].button, Buttons.googleDark);
      expect(buttons[1].button, Buttons.appleDark);
      // Facebook은 라이트/다크 무관 동일 변형 (브랜드 가이드라인).
      expect(buttons[2].button, Buttons.facebookNew);
    });

    testWidgets('isFormLoading=true일 때 Apple 버튼 탭해도 '
        'signInWithApple이 호출되지 않는다', (tester) async {
      await tester.pumpWidget(
        buildHarness(
          brightness: Brightness.light,
          repository: mockRepo,
          isFormLoading: true,
        ),
      );
      await tester.pumpAndSettle();

      final buttons = tester
          .widgetList<SignInButton>(find.byType(SignInButton))
          .toList();
      expect(buttons.length, 3);
      expect(buttons[1].button, Buttons.apple);

      final appleButtonFinder = find.byWidget(buttons[1]);
      await tester.tap(appleButtonFinder);
      await tester.pumpAndSettle();

      // isFormLoading=true이면 onPressed가 빈 콜백으로 교체되어
      // Repository가 호출되지 않아야 한다.
      verifyNever(() => mockRepo.signInWithApple());
    });
  });
}
