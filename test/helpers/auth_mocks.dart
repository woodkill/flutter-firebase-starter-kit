// AuthRepository 테스트 공용 mock 과 생성 헬퍼.
//
// AuthRepository 를 만드는 테스트들이 같은 SDK 경계 mock 8개를 파일마다 따로
// 선언하고, 생성자를 저마다 직접 불렀다. 그래서 생성자에 인자가 하나 늘면
// 모든 호출 자리를 고쳐야 했다. mock 선언과 생성자 호출을 이 파일 한 곳에
// 모으고, 테스트는 넘기고 싶은 의존성만 이름 인자로 넘긴다.
//
// 「파일당 public 클래스 1개」 권장의 예외다 — 8개 mock 은 헬퍼가 채우는
// 기본값이자 테스트가 stub 을 거는 대상이라 헬퍼와 한 경계를 이룬다.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_starter_kit/core/config/app_config.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/features/auth/application/social_link_in_progress.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/data/kakao_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

/// [fb.FirebaseAuth] mocktail 대역.
class MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

/// [GoogleSignIn] mocktail 대역.
class MockGoogleSignIn extends Mock implements GoogleSignIn {}

/// [FacebookAuth] mocktail 대역.
class MockFacebookAuth extends Mock implements FacebookAuth {}

/// [SocialLinkInProgress] mocktail 대역.
class MockSocialLinkInProgress extends Mock implements SocialLinkInProgress {}

/// [KakaoSdkClient] mocktail 대역.
class MockKakaoSdkClient extends Mock implements KakaoSdkClient {}

/// [FirebaseFunctions] mocktail 대역.
class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

/// [NaverSdkClient] mocktail 대역.
class MockNaverSdkClient extends Mock implements NaverSdkClient {}

/// [LineSdkClient] mocktail 대역.
class MockLineSdkClient extends Mock implements LineSdkClient {}

/// 의존성을 전부 선택 이름 인자로 받아 [AuthRepository] 를 만든다.
///
/// 넘기지 않은 SDK 경계 8개는 호출마다 새 공용 mock 으로 채우고,
/// [onResetOnboarding] 을 넘기지 않으면 아무것도 하지 않는 콜백을 쓴다.
/// [crashlytics] 기본값은 생성자와 같은 [CrashlyticsService.disabled] 다 —
/// non-nullable 이라 null 로 위임할 수 없어 같은 상수를 가리킨다. 나머지 선택
/// 인자(`now` · `staticProviders` 등)는 같은 이름으로 그대로 전달한다 —
/// 생성자가 null 을 받으면 자기 기본값을 쓰므로 여기서 기본값을 복제하지
/// 않는다.
AuthRepository buildAuthRepository({
  fb.FirebaseAuth? auth,
  GoogleSignIn? googleSignIn,
  FacebookAuth? facebookAuth,
  SocialLinkInProgress? socialLinkInProgress,
  KakaoSdkClient? kakaoSdkClient,
  FirebaseFunctions? functions,
  NaverSdkClient? naverSdkClient,
  LineSdkClient? lineSdkClient,
  Future<void> Function()? onResetOnboarding,
  DateTime Function()? now,
  Map<String, dynamic>? Function()? readTermsAcceptanceSnapshot,
  RecordSignUpMethod? recordSignUpMethod,
  CrashlyticsService crashlytics = CrashlyticsService.disabled,
  Future<void> Function()? onSignOutCleanup,
  Map<String, bool>? staticProviders,
  EmailDeliveryMode? emailDeliveryMode,
  String Function()? readLanguageCode,
}) => AuthRepository(
  auth ?? MockFirebaseAuth(),
  googleSignIn ?? MockGoogleSignIn(),
  facebookAuth ?? MockFacebookAuth(),
  socialLinkInProgress ?? MockSocialLinkInProgress(),
  kakaoSdkClient ?? MockKakaoSdkClient(),
  functions ?? MockFirebaseFunctions(),
  naverSdkClient ?? MockNaverSdkClient(),
  lineSdkClient ?? MockLineSdkClient(),
  onResetOnboarding ?? () async {},
  now: now,
  readTermsAcceptanceSnapshot: readTermsAcceptanceSnapshot,
  recordSignUpMethod: recordSignUpMethod,
  crashlytics: crashlytics,
  onSignOutCleanup: onSignOutCleanup,
  staticProviders: staticProviders,
  emailDeliveryMode: emailDeliveryMode,
  readLanguageCode: readLanguageCode,
);
