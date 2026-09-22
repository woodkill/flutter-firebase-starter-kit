// Phase 16.4 — see ROADMAP.md (레버 2 — 커스텀탭 Activity 생성 계수 · D-19)
//
// 킷 최초의 MethodChannel. Android 호스트(`MainActivity`)가 센
// `NidOAuthCustomTabActivity` 생성 횟수를 정수 하나로만 읽어 온다.
import 'package:flutter/foundation.dart';

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
@immutable
class NaverCustomTabProbe {
  /// 상태 없는 probe 를 만든다 — 채널 이름이 유일한 상태다.
  const NaverCustomTabProbe();

  /// 계수를 0 으로 되돌린다 (로그인 시도 시작 시점).
  Future<void> resetCount() async {
    // GREEN 에서 MethodChannel 로 배선한다.
  }

  /// 계수를 읽는다 — Android 가 아니거나 채널이 없으면 0.
  Future<int> readCount() async => 0;
}
