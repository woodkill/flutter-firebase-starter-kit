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
    });
  });
}
