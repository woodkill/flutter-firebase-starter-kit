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
