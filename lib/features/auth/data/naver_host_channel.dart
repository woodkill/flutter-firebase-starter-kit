// Phase 16.5 — see ROADMAP.md
//
// NAVER 앱 설치 판정 호스트 채널 (D-03 · D-23). 호스트(Android
// `NaverHostChannel.kt` · iOS `NaverHostChannel.swift`) 가 SDK 와 같은 기준으로
// 판정한 bool 하나만 넘긴다. 실패는 전부 `false`(= 킷 웹 경로) 로 접는다 (D-02).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 호스트 채널 이름 — Kotlin `NaverHostChannel.CHANNEL` 과 같은 문자열이어야
/// 한다 (소스 계약 테스트 `T-16.5-NATIVE` 가 잠근다).
const String kNaverHostChannelName =
    'com.slimpumpkin.flutter_starter_kit/naver_host';

/// 설치 판정 메서드 이름 — 호스트 `when (call.method)` 분기와 같은 문자열.
const String kNaverHostMethodIsInstalled = 'isNaverAppInstalled';

/// 설치 판정 함수 시그니처 — `NaverSdkClient.forTest` 가 fake 를 주입한다.
typedef NaverInstalledFn = Future<bool> Function();

/// NAVER 앱 설치 여부를 호스트에 묻는 채널 (Phase 16.5 D-03 · D-23).
///
/// **플랫폼 가드 없음 (D-01 대칭):** Android · iOS 모두 호스트가 채널을
/// 등록한다. 등록이 없는 환경(테스트 · 미지원 플랫폼)은 `MissingPluginException`
/// 으로 떨어지고 아래 규칙대로 `false` 가 된다.
///
/// **실패는 안전값으로 접는다 (D-02, PC-09 명시 예외):** 호스트 부재 ·
/// `PlatformException` · 반환 타입 불일치(`TypeError`) 전부 `false` — 판정을
/// 못 하면 SDK 커스텀탭이 아니라 킷 웹 경로로 가는 것이 이 phase 의 목적이다.
@immutable
class NaverHostChannel {
  /// 상태 없는 채널 — 채널 이름이 유일한 상태다.
  const NaverHostChannel();

  static const MethodChannel _channel = MethodChannel(kNaverHostChannelName);

  /// NAVER 앱이 설치돼 있으면 `true`, 없거나 판정에 실패하면 `false`.
  ///
  /// 진단 로그는 `kDebugMode` 전용이며 예외 타입 이름만 싣는다 (WR-05).
  Future<bool> isNaverAppInstalled() async {
    try {
      final installed = await _channel.invokeMethod<bool>(
        kNaverHostMethodIsInstalled,
      );
      return installed ?? false;
    } on Object catch (e) {
      // `TypeError`(호스트 반환 타입 불일치) 를 포함해 전부 흡수한다.
      if (kDebugMode) {
        debugPrint('Naver 설치 판정 실패(web 으로 접음): ${e.runtimeType}');
      }
      return false;
    }
  }
}
