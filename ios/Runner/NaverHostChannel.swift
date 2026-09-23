// Phase 16.5 — see ROADMAP.md (D-01 · D-03 · D-22 — NAVER 앱 설치 판정 호스트 채널, iOS 절반)
import Flutter
import UIKit

/// NAVER 앱 설치 여부만 Dart 로 넘기는 호스트 채널 (Phase 16.5 D-03 iOS · D-22).
///
/// Android `NaverHostChannel.kt` 의 iOS 대칭이다. 판정 기준은 NAVER iOS SDK 가
/// 1-tap(app-to-app) 을 시도할 때 쓰는 기준과 같다 — naveridlogin-sdk-ios-swift
/// 5.2.1 `Constant.swift:12` 의 `naversearchthirdlogin` scheme 을 SDK
/// `private isNaverAppInstalled()` 와 같은 문자열로 `canOpenURL` 한다.
/// SDK 판정과 킷 라우팅 기준이 어긋나면 「설치됐다고 판정했는데 SDK 는 웹으로
/// 간다」 는 불일치가 생기므로 문자열을 바꾸지 말 것.
///
/// - `NidCore` 를 import 하지 않는다 (D-22: Naver 제거 = 이 파일 + `AppDelegate`
///   등록 1줄 + pbxproj 4항목 삭제로 끝난다).
/// - `LSApplicationQueriesSchemes` 에 `naversearchthirdlogin` 이 이미 선언돼 있다
///   (`Info.plist` — Phase 13). 선언이 없으면 `canOpenURL` 은 항상 `false` 다.
/// - 채널을 건너는 것은 `Bool` 하나뿐이다 — URL · code · state 는 다루지 않는다.
///   실패(채널 부재 · 예외)는 Dart 쪽이 `false`(= 킷 웹 경로) 로 접는다.
final class NaverHostChannel {
  /// Dart `kNaverHostChannelName` 과 **같은 문자열**이어야 한다 (소스 계약 테스트가 잠근다).
  static let channelName = "com.slimpumpkin.flutter_starter_kit/naver_host"

  /// 등록된 채널 참조 — 엔진 수명 동안 핸들러를 붙들어 둔다.
  private static var channel: FlutterMethodChannel?

  /// `registry` 에서 전용 registrar 를 받아 채널을 만들고 설치 판정 핸들러를 등록한다.
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
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = methodChannel
  }
}
