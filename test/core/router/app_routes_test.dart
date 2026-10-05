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

    // Phase 17.2 todo 결정 5 사전 잠금 — 전체 경로를 조각 상수로 조합해도
    // guard · 알림 허용 목록 · GA4 screen name 키가 되는 값은 그대로여야 한다.
    group('Phase 17.2 경로 · name 값 고정 (todo 결정 5 — 조각 조합 전후 불변)', () {
      test('T-172-ROUTES-01: 전체 경로 상수 14개 값이 그대로다', () {
        const List<(String, String)> paths = <(String, String)>[
          (AppRoutes.home, '/'),
          (AppRoutes.login, '/login'),
          (AppRoutes.splash, '/splash'),
          (AppRoutes.signup, '/signup'),
          (AppRoutes.emailLogin, '/login/email'),
          (AppRoutes.forgotPassword, '/forgot-password'),
          (AppRoutes.verifyEmail, '/verify-email'),
          (AppRoutes.onboarding, '/onboarding'),
          (AppRoutes.termsService, '/terms/service'),
          (AppRoutes.termsPrivacy, '/terms/privacy'),
          (AppRoutes.settings, '/settings'),
          (AppRoutes.withdrawalDisconnect, '/settings/withdraw'),
          (AppRoutes.account, '/settings/account'),
          (AppRoutes.developerDemo, '/settings/developer'),
        ];
        expect(paths, hasLength(14), reason: '전체 경로 상수 14개를 모두 고정한다');
        for (final (String actual, String expected) in paths) {
          expect(actual, expected, reason: '전체 경로 값이 바뀌었다 (기대 $expected)');
        }
      });

      test('T-172-ROUTES-02: GoRoute name 상수 14개 값이 그대로다', () {
        const List<(String, String)> names = <(String, String)>[
          (AppRoutes.homeName, 'home'),
          (AppRoutes.loginName, 'login'),
          (AppRoutes.splashName, 'splash'),
          (AppRoutes.signupName, 'signup'),
          (AppRoutes.emailLoginName, 'emailLogin'),
          (AppRoutes.forgotPasswordName, 'forgotPassword'),
          (AppRoutes.verifyEmailName, 'verifyEmail'),
          (AppRoutes.onboardingName, 'onboarding'),
          (AppRoutes.termsServiceName, 'termsService'),
          (AppRoutes.termsPrivacyName, 'termsPrivacy'),
          (AppRoutes.settingsName, 'settings'),
          (AppRoutes.withdrawalDisconnectName, 'withdrawalDisconnect'),
          (AppRoutes.accountName, 'account'),
          (AppRoutes.developerDemoName, 'developerDemo'),
        ];
        expect(names, hasLength(14), reason: 'GoRoute name 상수 14개를 모두 고정한다');
        for (final (String actual, String expected) in names) {
          expect(
            actual,
            expected,
            reason: 'GoRoute name 값이 바뀌었다 (기대 $expected)',
          );
        }
      });

      test('T-172-ROUTES-03: 조각 상수 6개 값 · 전체 경로 = 조각 조합', () {
        const List<(String, String)> segments = <(String, String)>[
          (AppRoutes.settingsSegment, 'settings'),
          (AppRoutes.accountSegment, 'account'),
          (AppRoutes.withdrawalDisconnectSegment, 'withdraw'),
          (AppRoutes.developerDemoSegment, 'developer'),
          (AppRoutes.termsServiceSegment, 'terms/service'),
          (AppRoutes.termsPrivacySegment, 'terms/privacy'),
        ];
        expect(segments, hasLength(6), reason: '홈 하위 조각 상수 6개를 모두 고정한다');
        for (final (String actual, String expected) in segments) {
          expect(actual, expected, reason: '조각 상수 값이 바뀌었다 (기대 $expected)');
        }

        // 전체 경로 = 조각 조합 — GoRoute.path(조각)와 guard · 허용 목록 ·
        // push(전체 경로)가 같은 경로를 가리킨다.
        const List<(String, String)> joined = <(String, String)>[
          (AppRoutes.settings, '/${AppRoutes.settingsSegment}'),
          (
            AppRoutes.account,
            '${AppRoutes.settings}/${AppRoutes.accountSegment}',
          ),
          (
            AppRoutes.withdrawalDisconnect,
            '${AppRoutes.settings}/${AppRoutes.withdrawalDisconnectSegment}',
          ),
          (
            AppRoutes.developerDemo,
            '${AppRoutes.settings}/${AppRoutes.developerDemoSegment}',
          ),
          (AppRoutes.termsService, '/${AppRoutes.termsServiceSegment}'),
          (AppRoutes.termsPrivacy, '/${AppRoutes.termsPrivacySegment}'),
        ];
        expect(joined, hasLength(6), reason: '조각으로 조합한 전체 경로 6개');
        for (final (String actual, String expected) in joined) {
          expect(actual, expected, reason: '전체 경로가 조각 조합과 다르다 (기대 $expected)');
        }
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

      test(
        'removeReauthMarker 는 로그인 흐름 4개 경로의 표시를 지워 path 만 남긴다 (260924-phz)',
        () {
          for (final path in loginFlowPaths) {
            expect(
              AppRoutes.removeReauthMarker(
                Uri.parse(AppRoutes.buildReauthLocation(path)),
              ),
              path,
              reason: '남는 query 가 없으면 물음표 꼬리 없는 $path 여야 한다',
            );
          }
        },
      );

      test('removeReauthMarker 는 다른 query 를 보존한다 (260924-phz)', () {
        expect(
          AppRoutes.removeReauthMarker(Uri.parse('/login?reauth=1&from=x')),
          '/login?from=x',
          reason: '정규화는 재인증 표시만 빼고 템플릿 사용자의 query 를 지우지 않는다',
        );
      });

      test('removeReauthMarker 는 중복 key 를 값 개수와 무관하게 모두 지운다 (260924-phz)', () {
        final removed = AppRoutes.removeReauthMarker(
          Uri.parse('/login?reauth=0&reauth=1'),
        );
        expect(removed, AppRoutes.login, reason: '중복 key 를 일부만 지우면 표시가 남는다');
        expect(
          AppRoutes.hasReauthMarker(Uri.parse(removed)),
          isFalse,
          reason: '표시가 남으면 guard 분기 (2.5) 재평가가 redirect loop 가 된다',
        );
      });

      test('removeReauthMarker 는 표시 없는 location 을 그대로 돌려준다 (260924-phz)', () {
        expect(
          AppRoutes.removeReauthMarker(Uri(path: AppRoutes.login)),
          AppRoutes.login,
          reason: '표시가 없으면 경로를 바꾸지 않는다',
        );
      });
    });
  });
}
