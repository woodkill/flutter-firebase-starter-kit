import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

part 'apple_sign_in_client.g.dart';

/// [SignInWithApple.getAppleIDCredential]의 얇은 wrapper.
///
/// sign_in_with_apple 패키지의 static 메서드를 인스턴스 메서드로 감싸
/// DI 가능하게 만들고, 테스트에서 mocktail로 override할 수 있게 한다.
/// Android Web OAuth에 필요한 [WebAuthenticationOptions]도 내부에서
/// 주입하며, iOS에서는 webAuthenticationOptions 파라미터가 무시된다.
class AppleSignInClient {
  /// [AppleSignInClient]를 생성한다.
  const AppleSignInClient({
    required this.webServiceId,
    required this.webRedirectUri,
  });

  /// Firebase Console Apple Provider에 등록된 Service ID (Android 전용).
  ///
  /// dart-define-from-file을 통해 `APPLE_SERVICE_ID` 값이 주입된다.
  final String webServiceId;

  /// Firebase Auth handler redirect URI (Android 전용).
  ///
  /// 형식: `https://<PROJECT>.firebaseapp.com/__/auth/handler`.
  /// dart-define-from-file을 통해 `APPLE_REDIRECT_URI` 값이 주입된다.
  final Uri webRedirectUri;

  /// Apple ID credential을 획득한다.
  ///
  /// [nonce]는 SHA256 해싱된 값을 전달해야 한다. Firebase는 Apple
  /// identityToken에 박힌 해시와 rawNonce를 대조하므로, 해시 전달은
  /// Apple에만 하고 rawNonce는 호출부에서 별도 보관한다
  /// ([AuthRepository.signInWithApple]에서 처리).
  Future<AuthorizationCredentialAppleID> getCredential({
    required String nonce,
  }) async {
    return SignInWithApple.getAppleIDCredential(
      scopes: const <AppleIDAuthorizationScopes>[
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
      // iOS/macOS에서는 webAuthenticationOptions가 무시된다.
      // Android에서만 Chrome Custom Tab 기반 웹 OAuth 플로우에 사용된다.
      webAuthenticationOptions: Platform.isAndroid
          ? WebAuthenticationOptions(
              clientId: webServiceId,
              redirectUri: webRedirectUri,
            )
          : null,
    );
  }
}

/// [AppleSignInClient] 인스턴스 Provider (keepAlive).
///
/// `--dart-define-from-file`에서 주입된 `APPLE_SERVICE_ID`와
/// `APPLE_REDIRECT_URI`를 읽어 wrapper를 구성한다. 키가 주입되지
/// 않은 경우에는 스타터킷 placeholder 값으로 fallback하여 iOS 빌드가
/// 여전히 동작한다 (stg/prod Firebase dev only 원칙).
@Riverpod(keepAlive: true)
AppleSignInClient appleSignInClient(Ref ref) {
  return AppleSignInClient(
    webServiceId: const String.fromEnvironment(
      'APPLE_SERVICE_ID',
      defaultValue: 'com.example.flutter_starter_kit.service',
    ),
    webRedirectUri: Uri.parse(
      const String.fromEnvironment(
        'APPLE_REDIRECT_URI',
        defaultValue:
            'https://flutter-starter-kit-dev.firebaseapp.com/__/auth/handler',
      ),
    ),
  );
}
