import 'package:flutter_starter_kit/features/auth/data/apple_sign_in_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// [AppleSignInClient]의 mocktail Mock.
///
/// Plan 02(`auth_repository_test.dart`)에서 `signInWithApple` 그룹을
/// 작성할 때 재사용한다. 단일 책임 원칙에 따라 별도 파일로 분리.
class MockAppleSignInClient extends Mock implements AppleSignInClient {}

/// [AuthorizationCredentialAppleID]의 mocktail Mock.
///
/// `identityToken`, `givenName`, `familyName`, `email` 등 필드별로
/// `when()` stub을 작성할 수 있다.
class MockAuthorizationCredentialAppleID extends Mock
    implements AuthorizationCredentialAppleID {}

/// mocktail `registerFallbackValue`에 쓸 더미 객체.
///
/// `any(named: 'nonce')` 매처 사용 시 String fallback은 자동 등록되지만,
/// `signInWithCredential(any())`에 넘길 OAuthCredential fallback은
/// `test/helpers/firebase_auth_fakes.dart`에서 별도 등록한다.
void registerAppleFallbacks() {
  // String, Uri는 mocktail 기본 제공이므로 추가 등록 불필요.
  // OAuthCredential fallback은 Plan 02에서 확장.
}
