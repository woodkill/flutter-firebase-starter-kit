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
Future<void> _pumpVerifyEmail(
  WidgetTester tester, {
  VerifyEmailState initialState = const VerifyEmailState(),
  User? currentUser,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // build() 대체: Timer 부작용 없이 초기 상태만 반환.
        verifyEmailProvider.overrideWithBuild(
          (ref, notifier) => initialState,
        ),
        currentUserProvider.overrideWithValue(
          currentUser ?? _testUser,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
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
    testWidgets(
      '1. 초기 렌더 시 메일 아이콘 + 설명문 + 스팸 안내가 표시된다',
      (tester) async {
        await _pumpVerifyEmail(tester);

        // 메일 아이콘
        expect(
          find.byIcon(Icons.mark_email_unread_outlined),
          findsOneWidget,
        );

        // 사용자 이메일이 포함된 설명문
        expect(
          find.textContaining('test@example.com'),
          findsOneWidget,
        );

        // 스팸함 안내
        expect(
          find.textContaining('spam'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '2. 폴링 활성 시 LinearProgressIndicator가 표시된다',
      (tester) async {
        await _pumpVerifyEmail(
          tester,
          initialState: const VerifyEmailState(isPolling: true),
        );

        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      },
    );

    testWidgets(
      '3. 폴링 비활성 시 LinearProgressIndicator가 미표시된다',
      (tester) async {
        await _pumpVerifyEmail(
          tester,
          initialState: const VerifyEmailState(isPolling: false),
        );

        expect(find.byType(LinearProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      '4. 쿨다운 중 재전송 버튼이 disabled되고 카운트다운이 표시된다',
      (tester) async {
        await _pumpVerifyEmail(
          tester,
          initialState: const VerifyEmailState(cooldownRemaining: 45),
        );

        // 카운트다운 텍스트 표시
        expect(find.textContaining('45'), findsOneWidget);

        // OutlinedButton disabled 상태 확인
        final button = tester.widget<OutlinedButton>(
          find.byType(OutlinedButton),
        );
        expect(button.onPressed, isNull);
      },
    );

    testWidgets(
      '5. 에러 발생 시 FormErrorBanner에 에러 메시지가 표시된다',
      (tester) async {
        await _pumpVerifyEmail(
          tester,
          initialState:
              const VerifyEmailState(error: TooManyRequests()),
        );

        // FormErrorBanner가 에러 아이콘과 함께 표시된다
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
      },
    );

    testWidgets(
      '5b. ServiceUnavailable 에러 시 사용자 친화적 메시지가 '
      'FormErrorBanner에 표시된다 (Firebase 이메일 인증 미설정)',
      (tester) async {
        await _pumpVerifyEmail(
          tester,
          initialState:
              const VerifyEmailState(error: ServiceUnavailable()),
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
        expect(
          find.textContaining('operation-not-allowed'),
          findsNothing,
        );
      },
    );

    testWidgets(
      '5c. ServiceUnavailable 에러 상태에서도 재전송 버튼이 '
      '활성 상태이다 (에러 복구 가능)',
      (tester) async {
        await _pumpVerifyEmail(
          tester,
          initialState: const VerifyEmailState(
            error: ServiceUnavailable(),
            // cooldownRemaining이 0이므로 재전송 가능
          ),
        );

        // OutlinedButton (재전송 버튼)이 enabled 상태
        final button = tester.widget<OutlinedButton>(
          find.byType(OutlinedButton),
        );
        expect(button.onPressed, isNotNull);
      },
    );

    testWidgets(
      '6. 초기 렌더 시 navigation 미호출 보장 (D-05)',
      (tester) async {
        // VerifyEmailScreen 자체 렌더에서 navigation 콜이 발생하면
        // unhandled exception이 발생한다. 본 testWidgets가 통과하면
        // D-05(navigation은 redirect 가드가 처리)가 화면 빌드
        // 단계에서 위반되지 않음을 보장한다.
        await _pumpVerifyEmail(tester);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
