// Phase 16.4 — see ROADMAP.md (레버 2 — 커스텀탭 Activity 생성 계수 · D-19)
//
// 킷 최초의 MethodChannel. Android 호스트(`MainActivity`)가 센
// `NidOAuthCustomTabActivity` 생성 횟수를 정수 하나로만 읽어 온다.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 커스텀탭 생성 계수를 0 으로 되돌리는 함수 시그니처 typedef.
///
/// [NaverCustomTabProbe.resetCount] 의 tear-off 가 기본값이며, 테스트는
/// `NaverSdkClient.forTest` 로 fake 함수를 주입한다.
typedef NaverCustomTabResetFn = Future<void> Function();

/// 커스텀탭 생성 계수를 읽는 함수 시그니처 typedef.
///
/// [NaverCustomTabProbe.readCount] 의 tear-off 가 기본값이다.
typedef NaverCustomTabCountFn = Future<int> Function();

/// Android 호스트가 센 커스텀탭 Activity 생성 횟수를 읽는 probe (D-19).
///
/// 한 번의 Naver 로그인 시도 안에서 `NidOAuthCustomTabActivity` 가 2회 이상
/// 생성되면 재개방이 일어난 것이며, 그때의 `loggedOut` 은 사용자 취소가
/// 아니라 실패다 (Phase 16.4 RESEARCH §1 · §2 레버 2).
///
/// **채널을 건너는 것은 정수 하나뿐이다 (T-16.4-11).** 호스트는 콜백 intent 의
/// extras · `code` · `state` · URI 를 읽지도 넘기지도 않는다 — OAuth 완결은
/// 전적으로 SDK 에 둔다.
///
/// **절대 로그인 흐름을 깨지 않는다 (T-16.4-13).** 채널이 미등록이거나
/// (`MissingPluginException`) 호스트가 예외로 응답해도
/// (`PlatformException`) [readCount] 는 0, [resetCount] 는 no-op 으로 접는다.
/// iOS 는 웹 경로가 `ASWebAuthenticationSession` 으로 완료가 보장돼 대상이
/// 아니므로 채널을 **호출조차 하지 않는다** (D-06).
@immutable
class NaverCustomTabProbe {
  /// 상태 없는 probe 를 만든다 — 채널 이름이 유일한 상태다.
  const NaverCustomTabProbe();

  /// 호스트 `MainActivity.kt` 의 `CHANNEL` 상수와 **같은 문자열**이어야 한다.
  static const MethodChannel _channel = MethodChannel(
    'com.slimpumpkin.flutter_starter_kit/naver_custom_tab',
  );

  /// 구분 로직 발동 대상 플랫폼인지 — Android 한정 (D-06).
  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// 계수를 0 으로 되돌린다 (로그인 시도 시작 시점).
  ///
  /// 되돌리지 않으면 직전 시도가 남긴 값이 누적돼 정상 취소를 재개방으로
  /// 오판한다. 실패는 graceful — 예외를 밖으로 내보내지 않는다.
  Future<void> resetCount() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('resetCount');
    } on MissingPluginException catch (e) {
      _logUnavailable(e);
    } on PlatformException catch (e) {
      _logUnavailable(e);
    }
  }

  /// 계수를 읽는다 — Android 가 아니거나 채널이 없으면 0.
  ///
  /// 0 은 「재개방 없음」 과 같은 값이므로, 채널이 죽어도 동작은 이 plan 이전과
  /// 동일한 silent 취소로 되돌아갈 뿐 로그인이 깨지지 않는다.
  Future<int> readCount() async {
    if (!_isAndroid) return 0;
    try {
      return await _channel.invokeMethod<int>('getCount') ?? 0;
    } on MissingPluginException catch (e) {
      _logUnavailable(e);
      return 0;
    } on PlatformException catch (e) {
      _logUnavailable(e);
      return 0;
    }
  }

  /// 채널 부재 · 호스트 오류를 진단 로그로만 남긴다 (`kDebugMode` · 타입만).
  void _logUnavailable(Object error) {
    if (kDebugMode) {
      debugPrint('Naver customTab probe 미등록: ${error.runtimeType}');
    }
  }
}
