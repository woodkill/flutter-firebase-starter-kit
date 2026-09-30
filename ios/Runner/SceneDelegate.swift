// Phase 16.11 — see ROADMAP.md (D-04 · D-05 — Naver 콜백 URL 도착 관측)
import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  /// 앱 실행 중 들어온 URL 을 플러그인에 분배하기 **전에** Naver 콜백 도착만 기록한다 (16.11 D-04).
  ///
  /// 엔진은 등록 순서대로 플러그인에 URL 을 넘기다가 첫 `true` 에서 멈춘다
  /// (엔진 `FlutterSceneLifeCycle.mm:289-298`). naver 플러그인이 `true` 를 반환하면
  /// `addSceneDelegate` 로 붙인 뒤쪽 관측기는 URL 을 못 보므로, 분배(super) 앞인
  /// 이 override 가 유일하게 안전한 관측 지점이다.
  ///
  /// - 기록은 scheme 비교 결과 `Bool` 뿐이다 — URL 내용은 어디에도 넘기지 않는다 (C-06).
  /// - 분배 동작은 그대로다 — 기록 뒤 `super` 가 플러그인 분배를 이어 간다.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    // UAT 임시 — plan 07 이 제거
    let isNaverCallback = NaverHostChannel.recordIfNaverCallback(URLContexts)
    // UAT 임시 — plan 07 이 제거
    print("UAT1611 openURL naver=\(isNaverCallback ? 1 : 0) t=\(Int(Date().timeIntervalSince1970 * 1000))"); fflush(stdout)
    super.scene(scene, openURLContexts: URLContexts)
  }
}
