// 10-REVIEW WR-02 — Surface D proactive link 진행 플래그.
//
// 회원탈퇴(Surface C) 와 계정 연결(Surface D) 은 서로 무관한 유스케이스인데
// 하나의 `settingsProvider` AsyncValue 를 공유하고 있었다. 본 provider 는 link
// 진행 상태만 보유해 두 표면의 상태를 분리한다.
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'account_link_in_progress.g.dart';

/// Surface D proactive 계정 연결 진행 여부 (10-REVIEW WR-02).
///
/// `SettingsNotifier._dispatchLink` 가 진입 시 [begin], `finally` 에서 [end]
/// 를 호출하며, `AccountLinkingSection` 이 watch 하여 in-progress 오버레이와
/// 버튼 disable 을 결정한다.
///
/// **분리 이유:** 이전에는 link 진행 상태도 `settingsProvider`
/// (`AsyncValue<void>`) 에 실렸다. 그 결과 (a) 탈퇴 진행 중 배경 Settings 의
/// 모든 연결 버튼이 disabled 되고 `AuthInProgressOverlay` 가 떴으며,
/// (b) 탈퇴 실패로 남은 `error` state 가 `AccountLinkingSection` 의 watch
/// 때문에 auto-dispose 되지 않고 Settings 화면에 살아남았고, (c) 향후
/// `_dispatchLink` 가 error state 를 쓰도록 바뀌면 탈퇴 다이얼로그의
/// `ref.listen` 이 계정 연결 실패를 "탈퇴 실패" SnackBar 로 오표시하게 된다.
///
/// `@Riverpod(keepAlive: true)` 인 이유는 `SettingsNotifier` (auto-dispose)
/// 가 OAuth 왕복 중 dispose 되더라도 `finally` 의 [end] 가 도달할 수 있어야
/// 하기 때문이다 — 플래그가 `true` 로 고착되면 오버레이가 영구 표시된다.
/// `SocialLinkInProgress` (auth feature) 와 같은 패턴이나, 그쪽은 race 보호용
/// 이고 본 provider 는 UI 진행 표시 전용이라 소유자가 다르다.
@Riverpod(keepAlive: true)
class AccountLinkInProgress extends _$AccountLinkInProgress {
  /// 초기 상태는 `false` — 진행 중인 proactive link 가 없는 상태.
  @override
  bool build() => false;

  /// proactive link 시작을 표시한다.
  ///
  /// `SettingsNotifier._dispatchLink` 전용이다 — 외부 모듈에서 호출 금지.
  void begin() => state = true;

  /// proactive link 종료를 표시한다 (성공/실패/취소 공통).
  ///
  /// [begin] 과 짝을 이루는 `finally` 블록에서만 호출한다.
  void end() => state = false;
}
