import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/home/presentation/environment_info_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

/// EnvironmentInfoScreen 의 Account 섹션 위젯 테스트.
///
/// Plan 06-07 의 4 시나리오를 검증한다:
///   1. 비인증 시 Account 섹션 미표시 (D-36)
///   2. 인증 시 displayName/email/uid (truncated)/로그아웃 버튼 표시
///   3. 로그아웃 다이얼로그 취소 시 signOut 미호출
///   4. 로그아웃 다이얼로그 확인 시 signOut 호출
Future<void> _pumpScreen(
  WidgetTester tester, {
  required User? user,
  _MockAuthRepository? mockRepo,
}) async {
  final repo = mockRepo ?? _MockAuthRepository();
  // 화면 전체 ListView 컨텐츠가 약 4500dp 이상이므로 viewport 를 충분히
  // 키워 모든 카드/버튼이 한 번에 렌더되도록 한다 (lazy ListView 회피).
  tester.view.physicalSize = const Size(800, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => user),
        authRepositoryProvider.overrideWithValue(repo),
        isFirebaseInitializedProvider.overrideWithValue(false),
        firebaseAuthProvider.overrideWithValue(_MockFirebaseAuth()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const EnvironmentInfoScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('EnvironmentInfoScreen Account 섹션 (Phase 6)', () {
    testWidgets('비인증 시 Account 섹션 미표시 (D-36)', (tester) async {
      await _pumpScreen(tester, user: null);

      // Account 섹션 헤더 텍스트는 'Account' (en) 인데 다른 위치에 동일
      // 텍스트가 없도록 보장. 로그아웃 아이콘과 카드 라벨로 부재 확인.
      expect(
        find.text('Account', skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byIcon(Icons.logout, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byIcon(Icons.fingerprint, skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets(
      '인증 시 Account 섹션이 displayName/email/uid 표시',
      (tester) async {
        final user = User(
          uid: 'abcdefgh-rest-of-uid-12345',
          email: 'user@example.com',
          displayName: 'Test User',
          createdAt: DateTime.utc(2026, 1, 15),
        );

        await _pumpScreen(tester, user: user);

        expect(
          find.text('Account', skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.text('Test User', skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.text('user@example.com', skipOffstage: false),
          findsOneWidget,
        );
        // uid truncated to first 8 chars + '...'
        expect(
          find.text('abcdefgh...', skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byIcon(Icons.logout, skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '로그아웃 버튼 탭 시 AlertDialog 표시, 취소 시 signOut 미호출',
      (tester) async {
        final user = User(
          uid: 'uid-cancel-1',
          email: 'a@b.com',
          displayName: 'A',
          createdAt: DateTime.utc(2026),
        );
        final mockRepo = _MockAuthRepository();
        when(() => mockRepo.signOut()).thenAnswer((_) async {});

        await _pumpScreen(tester, user: user, mockRepo: mockRepo);

        // 로그아웃 OutlinedButton 까지 스크롤
        await tester.scrollUntilVisible(
          find.byIcon(Icons.logout),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byIcon(Icons.logout));
        await tester.pumpAndSettle();

        // 다이얼로그 등장 확인 (en: 'Are you sure you want to sign out?')
        expect(
          find.text('Are you sure you want to sign out?'),
          findsOneWidget,
        );

        // Cancel 버튼은 다이얼로그 actions 안에만 존재
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        verifyNever(() => mockRepo.signOut());
      },
    );

    testWidgets(
      '로그아웃 다이얼로그 확인 시 authRepository.signOut() 호출',
      (tester) async {
        final user = User(
          uid: 'uid-confirm-1',
          email: 'a@b.com',
          displayName: 'A',
          createdAt: DateTime.utc(2026),
        );
        final mockRepo = _MockAuthRepository();
        when(() => mockRepo.signOut()).thenAnswer((_) async {});

        await _pumpScreen(tester, user: user, mockRepo: mockRepo);

        await tester.scrollUntilVisible(
          find.byIcon(Icons.logout),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byIcon(Icons.logout));
        await tester.pumpAndSettle();

        // 'Sign out' 텍스트는 다이얼로그 title + 액션 버튼 양쪽에 존재한다
        // (authLogoutConfirmTitle == authAccountSignOut == "Sign out" en).
        // 액션 버튼만 타겟팅하기 위해 TextButton 자손을 찾는다.
        final dialogSignOutButton = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Sign out'),
        );
        expect(dialogSignOutButton, findsOneWidget);
        await tester.tap(dialogSignOutButton);
        await tester.pumpAndSettle();

        verify(() => mockRepo.signOut()).called(1);
      },
    );
  });
}
