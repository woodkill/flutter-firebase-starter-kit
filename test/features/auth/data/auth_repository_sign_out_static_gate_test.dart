// Phase 17.3 — see ROADMAP.md: 로그아웃 SDK fan-out 의 정적 CSV 가드.
//
// 정적 CSV(`enabledAuthProviders`)에 없는 provider 는 bootstrap 이 SDK 를
// 초기화하지 않는다. `AuthRepository.signOut` 이 그 SDK 의 로그아웃을 부르면
// LINE 은 네이티브가 프로세스를 끝낸다(Android `lateinit` 미초기화 예외 ·
// iOS `fatalError`) — Dart `try/catch` 로 막을 수 없으므로 호출 자체가 0 이어야
// 한다. 같은 규칙을 5 SDK 에 둔다.
// - 꺼진 provider → 그 SDK 로그아웃 `verifyNever`.
// - 켜진 provider → 그 SDK 로그아웃 `called(1)`.
// - 어느 경우든 Firebase 로그아웃은 1회.

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/features/auth/application/social_link_in_progress.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/data/kakao_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockFacebookAuth extends Mock implements FacebookAuth {}

class _MockSocialLinkInProgress extends Mock implements SocialLinkInProgress {}

class _MockKakaoSdkClient extends Mock implements KakaoSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

/// 로그아웃 경로 협력 객체 — 모든 SDK 로그아웃을 성공 stub 으로 둔다.
class _Harness {
  _Harness() {
    when(() => auth.signOut()).thenAnswer((_) async {});
    when(() => googleSignIn.signOut()).thenAnswer((_) async {});
    when(() => facebookAuth.logOut()).thenAnswer((_) async {});
    when(() => kakao.logout()).thenAnswer((_) async {});
    when(() => naver.logout()).thenAnswer((_) async {});
    when(() => line.logout()).thenAnswer((_) async {});
  }

  final _MockFirebaseAuth auth = _MockFirebaseAuth();
  final _MockGoogleSignIn googleSignIn = _MockGoogleSignIn();
  final _MockFacebookAuth facebookAuth = _MockFacebookAuth();
  final _MockKakaoSdkClient kakao = _MockKakaoSdkClient();
  final _MockNaverSdkClient naver = _MockNaverSdkClient();
  final _MockLineSdkClient line = _MockLineSdkClient();

  /// [enabledIds] 만 정적 CSV 에 켠 repository 를 만든다.
  AuthRepository buildRepository(Set<String> enabledIds) => AuthRepository(
    auth,
    googleSignIn,
    facebookAuth,
    _MockSocialLinkInProgress(),
    kakao,
    _MockFirebaseFunctions(),
    naver,
    line,
    () async {},
    staticProviders: <String, bool>{
      for (final id in kAllProviderIds) id: enabledIds.contains(id),
    },
  );

  /// provider id → 그 SDK 의 로그아웃 호출 (verify 용 closure).
  Map<String, Future<void> Function()> get logoutCalls =>
      <String, Future<void> Function()>{
        kProviderIdGoogle: googleSignIn.signOut,
        kProviderIdFacebook: facebookAuth.logOut,
        kProviderIdKakao: kakao.logout,
        kProviderIdNaver: naver.logout,
        kProviderIdLine: line.logout,
      };
}

void main() {
  group('signOut — 정적 CSV 가드 (Phase 17.3)', () {
    test('소셜 전부 off(기본 example CSV) → SDK 로그아웃 0 · Firebase '
        '로그아웃 1', () async {
      final h = _Harness();

      await h.buildRepository(const <String>{}).signOut();

      for (final call in h.logoutCalls.values) {
        verifyNever(call);
      }
      verify(() => h.auth.signOut()).called(1);
    });

    test('LINE off · 나머지 on → LINE 로그아웃 0 (네이티브 fatal 회피)', () async {
      final h = _Harness();
      final enabled = <String>{...kAllProviderIds}..remove(kProviderIdLine);

      await h.buildRepository(enabled).signOut();

      verifyNever(() => h.line.logout());
      verify(() => h.googleSignIn.signOut()).called(1);
      verify(() => h.facebookAuth.logOut()).called(1);
      verify(() => h.kakao.logout()).called(1);
      verify(() => h.naver.logout()).called(1);
      verify(() => h.auth.signOut()).called(1);
    });

    for (final providerId in <String>[
      kProviderIdGoogle,
      kProviderIdFacebook,
      kProviderIdKakao,
      kProviderIdNaver,
      kProviderIdLine,
    ]) {
      test('$providerId 만 on → $providerId SDK 로그아웃 1 · 나머지 0', () async {
        final h = _Harness();

        await h.buildRepository(<String>{providerId}).signOut();

        for (final entry in h.logoutCalls.entries) {
          if (entry.key == providerId) {
            verify(entry.value).called(1);
          } else {
            verifyNever(entry.value);
          }
        }
        verify(() => h.auth.signOut()).called(1);
      });
    }

    test('on provider 의 SDK 로그아웃이 throw 해도 Firebase 로그아웃은 '
        '1회', () async {
      final h = _Harness();
      when(() => h.line.logout()).thenThrow(StateError('line logout failed'));

      await h.buildRepository(<String>{kProviderIdLine}).signOut();

      verify(() => h.line.logout()).called(1);
      verify(() => h.auth.signOut()).called(1);
    });
  });
}
