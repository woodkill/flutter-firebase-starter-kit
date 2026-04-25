import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_router.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

/// 404 [buildNotFoundScreen] 본문을 지정한 [locale] 로 pump 한다.
///
/// GoRouter 전체 스택 없이 errorBuilder 의 본문 위젯만 직접 검증한다.
Future<void> _pumpNotFound(
  WidgetTester tester, {
  required Locale locale,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Builder(builder: buildNotFoundScreen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('appRouterProvider', () {
    late ProviderContainer container;

    setUp(() {
      final mockAuth = _MockFirebaseAuth();
      when(
        () => mockAuth.authStateChanges(),
      ).thenAnswer((_) => const Stream<User?>.empty());

      container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(false),
          firebaseAuthProvider.overrideWithValue(mockAuth),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('GoRouter 인스턴스를 반환한다', () {
      final router = container.read(appRouterProvider);
      expect(router, isA<GoRouter>());
    });

    test('keepAlive Provider이다', () {
      final sub = container.listen(appRouterProvider, (_, _) {});
      sub.close();

      // keepAlive이므로 subscription 해제 후에도 읽을 수 있다
      final router = container.read(appRouterProvider);
      expect(router, isA<GoRouter>());
    });
  });

  group('errorBuilder (buildNotFoundScreen)', () {
    testWidgets('1. en 로케일에서 l10n 제목/본문/CTA + error_outline 렌더', (
      tester,
    ) async {
      await _pumpNotFound(tester, locale: const Locale('en'));

      // AppBar title 과 body title 두 곳에 동일 텍스트가 노출될 수 있다.
      expect(find.text('Page not found'), findsAtLeastNWidgets(1));
      expect(
        find.text('The page you requested does not exist.'),
        findsOneWidget,
      );
      expect(find.text('Go home'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.widgetWithIcon(FilledButton, Icons.home), findsOneWidget);
    });

    testWidgets('2. ko 로케일에서 한글 l10n 제목/본문/CTA 렌더', (tester) async {
      await _pumpNotFound(tester, locale: const Locale('ko'));

      expect(find.text('페이지를 찾을 수 없습니다'), findsAtLeastNWidgets(1));
      expect(find.text('요청하신 페이지가 존재하지 않습니다.'), findsOneWidget);
      expect(find.text('홈으로'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });
}
