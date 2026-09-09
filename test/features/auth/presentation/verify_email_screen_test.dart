import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/verify_email_notifier.dart';
import 'package:flutter_starter_kit/features/auth/presentation/verify_email_screen.dart';
import 'package:flutter_starter_kit/features/auth/presentation/verify_email_state.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// 테스트용 기본 사용자.
final _testUser = User(
  uid: 'u1',
  email: 'test@example.com',
  emailVerified: false,
  createdAt: DateTime.utc(2026),
);

/// [VerifyEmailScreen]을 영문 로케일 + [AppTheme.light] 주입 상태로 pump한다.
///
/// [initialState]로 [VerifyEmailNotifier]의 build 결과를 제어하여
/// Timer 부작용 없이 순수 렌더링만 테스트한다.
/// [currentUser]로 사용자 정보를 주입한다.
/// [locale]로 ARB 본문 verbatim 검증 시 로케일을 변경할 수 있다 (기본 en).
Future<void> _pumpVerifyEmail(
  WidgetTester tester, {
  VerifyEmailState initialState = const VerifyEmailState(),
  User? currentUser,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // build() 대체: Timer 부작용 없이 초기 상태만 반환.
        verifyEmailProvider.overrideWithBuild((ref, notifier) => initialState),
        currentUserProvider.overrideWithValue(currentUser ?? _testUser),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const VerifyEmailScreen(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('VerifyEmailScreen', () {
    testWidgets('1. 초기 렌더 시 메일 아이콘 + 설명문 + 스팸 안내가 표시된다', (tester) async {
      await _pumpVerifyEmail(tester);

      // 메일 아이콘
      expect(find.byIcon(Icons.mark_email_unread_outlined), findsOneWidget);

      // 사용자 이메일이 포함된 설명문
      expect(find.textContaining('test@example.com'), findsOneWidget);

      // 스팸함 안내
      expect(find.textContaining('spam'), findsOneWidget);
    });

    testWidgets('2. 폴링 활성 시 LinearProgressIndicator가 표시된다', (tester) async {
      await _pumpVerifyEmail(
        tester,
        initialState: const VerifyEmailState(isPolling: true),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('3. 폴링 비활성 시 LinearProgressIndicator가 미표시된다', (tester) async {
      await _pumpVerifyEmail(
        tester,
        initialState: const VerifyEmailState(isPolling: false),
      );

      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('4. 쿨다운 중 재전송 버튼이 disabled되고 카운트다운이 표시된다', (tester) async {
      await _pumpVerifyEmail(
        tester,
        initialState: const VerifyEmailState(cooldownRemaining: 45),
      );

      // 카운트다운 텍스트 표시
      expect(find.textContaining('45'), findsOneWidget);

      // OutlinedButton disabled 상태 확인
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('5. 에러 발생 시 FormErrorBanner에 에러 메시지가 표시된다', (tester) async {
      await _pumpVerifyEmail(
        tester,
        initialState: const VerifyEmailState(error: TooManyRequests()),
      );

      // FormErrorBanner가 에러 아이콘과 함께 표시된다
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('5b. ServiceUnavailable 에러 시 사용자 친화적 메시지가 '
        'FormErrorBanner에 표시된다 (Firebase 이메일 인증 미설정)', (tester) async {
      await _pumpVerifyEmail(
        tester,
        initialState: const VerifyEmailState(error: ServiceUnavailable()),
      );

      // FormErrorBanner가 에러 아이콘과 함께 표시된다
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      // 번역된 사용자 친화적 메시지 표시 확인
      // (raw Firebase 에러가 아닌 l10n 메시지)
      expect(
        find.textContaining('Service is temporarily unavailable'),
        findsOneWidget,
      );

      // raw 에러 코드가 노출되지 않는다
      expect(find.textContaining('operation-not-allowed'), findsNothing);
    });

    testWidgets('5c. ServiceUnavailable 에러 상태에서도 재전송 버튼이 '
        '활성 상태이다 (에러 복구 가능)', (tester) async {
      await _pumpVerifyEmail(
        tester,
        initialState: const VerifyEmailState(
          error: ServiceUnavailable(),
          // cooldownRemaining이 0이므로 재전송 가능
        ),
      );

      // OutlinedButton (재전송 버튼)이 enabled 상태
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('6. 초기 렌더 시 navigation 미호출 보장 (D-05)', (tester) async {
      // VerifyEmailScreen 자체 렌더에서 navigation 콜이 발생하면
      // unhandled exception이 발생한다. 본 testWidgets가 통과하면
      // D-05(navigation은 redirect 가드가 처리)가 화면 빌드
      // 단계에서 위반되지 않음을 보장한다.
      await _pumpVerifyEmail(tester);
      expect(tester.takeException(), isNull);
    });

    // ========================================================================
    // Phase 9.2 Gap B Dart consumer (HUMAN-UAT 2026-05-11):
    // currentUser.email 가 빈 문자열일 때 graceful fallback 메시지가 표시되는
    // invariant + non-empty 시 기존 메시지가 보존되는 regression sentinel.
    // User.email 은 freezed 모델에서 required non-null String 이므로 'email
    // 미설정' 시나리오는 빈 문자열로 표현된다 (verify_email_screen 의
    // `userEmail.isEmpty` 분기와 정합). 본 테스트는 generated getter 호출
    // 대신 ARB 본문 verbatim 비교로 컴파일 의존성 최소화.
    // ========================================================================
    testWidgets('VE-EMAIL-NULL-01: currentUser.email 빈 문자열 → graceful fallback '
        '메시지 표시 (ko 로케일 verbatim)', (tester) async {
      final emptyEmailUser = User(
        uid: 'test-uid-empty-email',
        email: '',
        emailVerified: false,
        createdAt: DateTime.utc(2026),
      );

      await _pumpVerifyEmail(
        tester,
        currentUser: emptyEmailUser,
        locale: const Locale('ko'),
      );

      // ko ARB verbatim — graceful fallback 메시지.
      expect(
        find.text(
          '가입하신 이메일 주소로 인증 메일을 보냈습니다. '
          '메일의 링크를 클릭하여 인증을 완료해 주세요.',
        ),
        findsOneWidget,
      );
      // 기존 authVerifyEmailDescription 본문 일부 (placeholder 포함) 미발현.
      expect(find.textContaining('(으)로 보냈습니다'), findsNothing);
    });

    testWidgets(
      'VE-EMAIL-PRESENT-01: currentUser.email non-empty → 기존 메시지 표시 + '
      'fallback 미발동 (ko 로케일 regression sentinel)',
      (tester) async {
        final presentEmailUser = User(
          uid: 'test-uid-present-email',
          email: 'user@example.com',
          emailVerified: false,
          createdAt: DateTime.utc(2026),
        );

        await _pumpVerifyEmail(
          tester,
          currentUser: presentEmailUser,
          locale: const Locale('ko'),
        );

        // 기존 authVerifyEmailDescription 본문 — email 포함 표시 sentinel.
        expect(find.textContaining('user@example.com'), findsOneWidget);
        // fallback 메시지 미발현 — Gap B 분기 false-positive 차단.
        expect(
          find.text(
            '가입하신 이메일 주소로 인증 메일을 보냈습니다. '
            '메일의 링크를 클릭하여 인증을 완료해 주세요.',
          ),
          findsNothing,
        );
      },
    );
  });
}
