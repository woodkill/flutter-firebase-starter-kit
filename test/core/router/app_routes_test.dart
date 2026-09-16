import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/router/app_routes.dart';

void main() {
  group('AppRoutes', () {
    group('path 상수', () {
      test('home path는 /이다', () {
        expect(AppRoutes.home, '/');
      });

      test('login path는 /login이다', () {
        expect(AppRoutes.login, '/login');
      });

      test('splash path는 /splash이다', () {
        expect(AppRoutes.splash, '/splash');
      });

      test('signup path는 /signup이다', () {
        expect(AppRoutes.signup, '/signup');
      });

      test('forgotPassword path는 /forgot-password이다', () {
        expect(AppRoutes.forgotPassword, '/forgot-password');
      });

      test('emailLogin path는 /login/email이다 (Phase 16.1 D-01)', () {
        expect(AppRoutes.emailLogin, '/login/email');
      });
    });

    group('name 상수', () {
      test('homeName은 home이다', () {
        expect(AppRoutes.homeName, 'home');
      });

      test('loginName은 login이다', () {
        expect(AppRoutes.loginName, 'login');
      });

      test('splashName은 splash이다', () {
        expect(AppRoutes.splashName, 'splash');
      });

      test('signupName은 signup이다', () {
        expect(AppRoutes.signupName, 'signup');
      });

      test('forgotPasswordName은 forgotPassword이다', () {
        expect(AppRoutes.forgotPasswordName, 'forgotPassword');
      });

      test('emailLoginName은 emailLogin이다 (Phase 16.1 D-01)', () {
        expect(AppRoutes.emailLoginName, 'emailLogin');
      });
    });

    group('재인증 표시 API — R_EXTRA_G3_REAUTH_LOGIN_BOUNCE (260916-p8d)', () {
      const loginFlowPaths = <String>[
        AppRoutes.login,
        AppRoutes.emailLogin,
        AppRoutes.signup,
        AppRoutes.forgotPassword,
      ];

      test('buildReauthLocation 은 기준 형태 /login?reauth=1 을 만든다', () {
        expect(
          AppRoutes.buildReauthLocation(AppRoutes.login),
          '/login?reauth=1',
          reason: 'CONTEXT 가 고정한 재인증 표시 기준 형태',
        );
      });

      test('hasReauthMarker 는 로그인 흐름 4개 경로의 표시 location 에서 true', () {
        for (final path in loginFlowPaths) {
          expect(
            AppRoutes.hasReauthMarker(
              Uri.parse(AppRoutes.buildReauthLocation(path)),
            ),
            isTrue,
            reason: '$path 에 붙인 표시는 판정 함수가 인식해야 한다',
          );
        }
      });

      test('hasReauthMarker 는 표시가 없거나 값이 다르면 false', () {
        expect(
          AppRoutes.hasReauthMarker(Uri(path: AppRoutes.login)),
          isFalse,
          reason: '표시 없는 진입은 재인증이 아니다',
        );
        expect(
          AppRoutes.hasReauthMarker(
            Uri(
              path: AppRoutes.login,
              queryParameters: <String, String>{AppRoutes.reauthQueryKey: '0'},
            ),
          ),
          isFalse,
          reason: 'key 가 같아도 값이 다르면 표시로 인정하지 않는다 (strict equality)',
        );
      });

      test('forwardReauthMarker 는 표시가 있을 때만 다음 경로에 표시를 붙인다', () {
        final marked = Uri.parse(
          AppRoutes.buildReauthLocation(AppRoutes.login),
        );
        expect(
          AppRoutes.forwardReauthMarker(AppRoutes.emailLogin, from: marked),
          AppRoutes.buildReauthLocation(AppRoutes.emailLogin),
          reason: '재인증 흐름은 다음 push 에도 표시를 이어 붙여야 한다',
        );
        expect(
          AppRoutes.forwardReauthMarker(
            AppRoutes.emailLogin,
            from: Uri(path: AppRoutes.login),
          ),
          AppRoutes.emailLogin,
          reason: '표시 없는 진입은 경로를 바꾸지 않는다',
        );
      });
    });
  });
}
