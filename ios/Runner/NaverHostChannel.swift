// Phase 16.5 — see ROADMAP.md (D-01 · D-03 · D-22 — NAVER 앱 설치 판정 호스트 채널, iOS 절반)
// Phase 16.11 — see ROADMAP.md (D-04 · D-05 — Naver 콜백 URL 도착 기록 · 조회 · 초기화)
import Flutter
import UIKit

/// NAVER 앱 설치 여부 · 콜백 도착 기록을 Dart 로 넘기는 호스트 채널
/// (Phase 16.5 D-03 iOS · D-22 · Phase 16.11 D-05).
///
/// Android `NaverHostChannel.kt` 의 iOS 대칭이다. 판정 기준은 NAVER iOS SDK 가
/// 1-tap(app-to-app) 을 시도할 때 쓰는 기준과 같다 — naveridlogin-sdk-ios-swift
/// 5.2.1 `Constant.swift:12` 의 `naversearchthirdlogin` scheme 을 SDK
/// `private isNaverAppInstalled()` 와 같은 문자열로 `canOpenURL` 한다.
/// SDK 판정과 킷 라우팅 기준이 어긋나면 「설치됐다고 판정했는데 SDK 는 웹으로
/// 간다」 는 불일치가 생기므로 문자열을 바꾸지 말 것.
///
/// - `NidCore` 를 import 하지 않는다 (D-22: Naver 제거 = 이 파일 + `AppDelegate`
///   등록 1줄 + pbxproj 4항목 + `SceneDelegate` 의 `scene(_:openURLContexts:)`
///   override 삭제로 끝난다).
/// - `LSApplicationQueriesSchemes` 에 `naversearchthirdlogin` 이 이미 선언돼 있다
///   (`Info.plist` — Phase 13). 선언이 없으면 `canOpenURL` 은 항상 `false` 다.
/// - 채널을 건너는 것은 `Bool` 2개(설치 판정 · 콜백 도착)와 제어 호출 1개(초기화)뿐
///   이다 — URL · code · state · authCode 는 다루지 않는다 (16.11 C-06).
///   설치 판정 실패(채널 부재 · 예외)는 Dart 쪽이 `false`(= 킷 웹 경로) 로,
///   콜백 도착 조회 실패는 `true`(= 계속 대기) 로 접는다.
final class NaverHostChannel {
  /// Dart `kNaverHostChannelName` 과 **같은 문자열**이어야 한다 (소스 계약 테스트가 잠근다).
  static let channelName = "com.slimpumpkin.flutter_starter_kit/naver_host"

  /// 등록된 채널 참조 — 엔진 수명 동안 핸들러를 붙들어 둔다.
  private static var channel: FlutterMethodChannel?

  /// 현재 1-tap 요청 동안 Naver 콜백 URL 이 도착했는가 — main 스레드에서만 읽고 쓴다 (16.11 D-05).
  ///
  /// `SceneDelegate` 가 `recordIfNaverCallback(_:)` 로 세우고, Dart 가 채널로 조회 ·
  /// 초기화한다. 판정(포기 여부)은 Dart 가 한다 — 여기는 기록만 한다 (D-03).
  private static var hasCallbackArrived = false

  /// `registry` 에서 전용 registrar 를 받아 채널을 만들고 설치 판정 · 콜백 기록 핸들러를 등록한다.
  ///
  /// `AppDelegate.didInitializeImplicitFlutterEngine` 이
  /// `GeneratedPluginRegistrant` 다음 줄에서 한 번 부른다.
  /// registrar 를 얻지 못하면(엔진 부재) 아무것도 등록하지 않는다 —
  /// Dart 는 `MissingPluginException` 을 `false` 로 접는다.
  static func register(with registry: FlutterPluginRegistry) {
    guard let messenger = registry.registrar(forPlugin: "NaverHostChannel")?.messenger() else {
      return
    }
    let methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "isNaverAppInstalled":
        // 리터럴 상수라 URL 생성은 실패하지 않는다.
        result(UIApplication.shared.canOpenURL(URL(string: "naversearchthirdlogin://")!))
      case "hasNaverCallbackArrived":
        result(NaverHostChannel.hasCallbackArrived)
      case "resetNaverCallbackRecord":
        NaverHostChannel.hasCallbackArrived = false
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = methodChannel

    // UAT 임시 — plan 07 이 제거 (U1 · U2 — 엔진이 lifecycle 로 매핑하는 scene 알림 4종 시각)
    let center = NotificationCenter.default
    // UAT 임시 — plan 07 이 제거
    _ = center.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) { _ in
      // UAT 임시 — plan 07 이 제거
      print("UAT1611 willDeactivate t=\(Int(Date().timeIntervalSince1970 * 1000))"); fflush(stdout)
    }
    // UAT 임시 — plan 07 이 제거
    _ = center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
      // UAT 임시 — plan 07 이 제거
      print("UAT1611 didEnterBackground t=\(Int(Date().timeIntervalSince1970 * 1000))"); fflush(stdout)
    }
    // UAT 임시 — plan 07 이 제거
    _ = center.addObserver(forName: UIScene.willEnterForegroundNotification, object: nil, queue: .main) { _ in
      // UAT 임시 — plan 07 이 제거
      print("UAT1611 willEnterForeground t=\(Int(Date().timeIntervalSince1970 * 1000))"); fflush(stdout)
    }
    // UAT 임시 — plan 07 이 제거
    _ = center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { _ in
      // UAT 임시 — plan 07 이 제거
      print("UAT1611 didActivate t=\(Int(Date().timeIntervalSince1970 * 1000))"); fflush(stdout)
    }
  }

  /// [contexts] 중 Naver 콜백 URL 이 있으면 도착 기록을 세우고 `true` 를 돌려준다 (16.11 D-04 · D-05).
  ///
  /// 판별 규칙은 naver 플러그인과 같다 — `Info.plist` 의 Naver 콜백 scheme 값과
  /// URL scheme 을 소문자로 바꿔 완전 일치 비교한다
  /// (`FlutterNaverLoginPlugin.swift:171-172`). 그 값을 못 읽거나 일치하는 URL 이
  /// 없으면 기록을 건드리지 않고 `false` 를 돌려준다.
  ///
  /// URL 의 host · query · 전체 문자열은 읽지 않는다 — scheme 비교 결과만 남긴다 (C-06).
  @discardableResult
  static func recordIfNaverCallback(_ contexts: Set<UIOpenURLContext>) -> Bool {
    guard let naverScheme = Bundle.main.infoDictionary?["NidUrlScheme"] as? String else {
      return false
    }
    let expected = naverScheme.lowercased()
    guard contexts.contains(where: { $0.url.scheme?.lowercased() == expected }) else {
      return false
    }
    hasCallbackArrived = true
    return true
  }
}
