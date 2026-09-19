import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:mocktail/mocktail.dart';

/// 인증 관련 테스트에서 공유되는 fake 객체 모음.
///
/// `auth_repository_test.dart` 와 `auth_repository_linking_test.dart` 등
/// 여러 테스트 파일에서 동일한 fake 가 반복 정의되는 것을 방지하기 위해
/// 단일 소스로 추출했다. `flutter_facebook_auth` 등 외부 SDK API 가 변경되면
/// 이 파일만 수정하면 된다.

/// 테스트용 [ClassicToken] fake.
///
/// `flutter_facebook_auth` 의 [AccessToken] 은 abstract class 이므로
/// 직접 instance 화할 수 없다. Facebook 로그인 결과의 access token 을
/// 흉내내기 위해 [ClassicToken] 을 implements 한 [Fake] 를 사용한다.
class FakeClassicToken extends Fake implements ClassicToken {
  /// [tokenString] 으로 fake access token 을 생성한다.
  FakeClassicToken({required this.tokenString});

  @override
  final String tokenString;

  @override
  AccessTokenType get type => AccessTokenType.classic;
}

/// iOS Limited Login 이 돌려주는 실 [LimitedToken] 픽스처를 만든다.
///
/// 가짜 타입 (`implements AccessToken` — Classic / Limited 어느 쪽도 아님)
/// 대신 플러그인의 실 타입과 실 `fromJson` 경로를 쓴다. 맵 키는 플러그인
/// 소스와 글자 그대로 같다:
/// - flutter_facebook_auth 7.2.0 (7.1.7+ 에서 iOS 소스가 SPM 배치로 이동)
///   `ios/flutter_facebook_auth/Sources/flutter_facebook_auth/FacebookAuth.swift:212-219` —
///   `isLimitedLogin` 이면 `type: "limited"` · `userId` · `userEmail` ·
///   `userName` · `token` (AuthenticationToken 의 OIDC JWT) · `nonce` 를
///   채운다.
/// - flutter_facebook_auth_platform_interface 6.1.2
///   `lib/src/facebook_auth_implementation.dart:43` — `type == 'limited'`
///   이면 `LimitedToken.fromJson` (`lib/src/access_token.dart:33-41`).
///
/// [tokenString] 은 `token` 키 (OIDC JWT 자리) 에 들어간다. `nonce` 는
/// 플러그인이 되돌려주는 값을 흉내낼 뿐이며, 테스트는 이 값을 단언에 쓰지
/// 않는다 (mock 이 돌려준 값을 다시 검증하는 자기참조 차단).
LimitedToken buildLimitedToken({required String tokenString}) {
  return LimitedToken.fromJson({
    'type': 'limited',
    'userId': 'limited-user-id-fixture',
    'userEmail': 'limited-fixture@example.com',
    'userName': 'Limited Fixture',
    'token': tokenString,
    'nonce': 'plugin-echoed-nonce-fixture',
  });
}
