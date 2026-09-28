// Phase 16.10 — see ROADMAP.md
//
// 탈퇴 진행 화면(UI-SPEC §Surface W)의 상태 기계.
//
// - D-05 · D-13: 탈퇴 다이얼로그 확인 뒤 provider 마다 연결을 끊고, 모든 행이
//   끝나면 기존 `SettingsNotifier.requestAccountDeletion` 을 1회 부른다(C-01 —
//   삭제 로직 복제 0).
// - D-06: 행 = `User.providerIds` 중 끊기 step 이 있는 provider 전부(가입 수단
//   포함). 순서 = 서버 행 먼저 → 재로그인 행 · 각 묶음은 `kSocialProviderOrder`.
//   재로그인 행은 한 번에 하나만 현재 행이다.
// - D-07: 재로그인 행의 로그인은 서버 탈퇴의 신선도(C-02)를 겸한다 —
//   `step.run(reloginForFreshness: true)`. 5분 창 초과 거부 뒤의 복구는 화면이
//   notifier 메서드를 명시 호출한다(plan 07 설계 결정).
// - D-12: 모든 행은 건너뛸 수 있다 — 탈퇴는 항상 끝난다.
// - D-14: 진행 상태는 영속화하지 않는다. 화면을 나가면 auto-dispose 되고 다시
//   들어오면 처음부터 한다(끊기는 멱등).
// - RESEARCH Pitfall 4: 재로그인이 user stream 을 재방출해도 행이 초기화되지
//   않도록 `build()` 는 다른 provider 를 읽지 않고, 행은 [WithdrawalDisconnect.start]
//   에서 1회 스냅샷한 뒤 provider 키로 갱신한다.
// - UI-SPEC §행 상태 · §행 순서 · §마지막 「탈퇴」.
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/auth/provider_id.dart';
import '../../../core/auth/provider_order.dart';
import '../../../core/error/app_exception.dart';
import '../../auth/data/auth_repository.dart';
import '../data/disconnect/disconnect_step.dart';
import '../data/disconnect/disconnect_steps.dart';
import 'settings_notifier.dart';

part 'withdrawal_disconnect_notifier.g.dart';

/// 진행 화면 행 상태 (UI-SPEC §행 상태 — 아이콘 · 문구 · 동작).
enum DisconnectRowStatus {
  /// 대기 — `radio_button_unchecked` · 「대기」 · 동작 없음.
  waiting,

  /// 로그인 대기(현재 재로그인 행) — `login` · 「로그인하면 연결을
  /// 해제합니다」 · 브랜드 로그인 버튼 + 건너뛰기.
  needsSignIn,

  /// 해제 중 — 행 아이콘 자리 스피너 · 「해제 중…」 · 동작 없음.
  working,

  /// 해제됨 — `check_circle`(success) · 「해제됨」 · 동작 없음.
  done,

  /// 실패 — `error_outline`(error) · 「해제하지 못했습니다」 · 서버 행은
  /// 건너뛰기 · 재시도, 재로그인 행은 브랜드 로그인 버튼 + 건너뛰기.
  failed,

  /// 신원 불일치(D-08) — `error_outline`(error) · 「연결된 {provider} 계정으로
  /// 로그인하세요」 · 브랜드 로그인 버튼 + 건너뛰기(끊기 호출 0).
  mismatch,

  /// 건너뜀(D-12) — `remove_circle_outline` · 「건너뜀」 + 직접 해제 안내 ·
  /// 되돌리기 없음.
  skipped,
}

/// 진행 화면의 provider 1행 (UI-SPEC §Surface W).
@immutable
class DisconnectRow {
  /// [DisconnectRow] 를 생성한다.
  const DisconnectRow({
    required this.providerId,
    required this.provider,
    required this.kind,
    required this.status,
  });

  /// `User.providerIds` 원소 그대로 (라벨 변환 입력 — `'google.com'` 등).
  final String providerId;

  /// 행 provider — 상태 갱신 키.
  final AccountProvider provider;

  /// 서버 행 · 재로그인 행 구분 (레지스트리 step 의 kind).
  final DisconnectKind kind;

  /// 현재 행 상태.
  final DisconnectRowStatus status;

  /// 해제됨 또는 건너뜀 — 「탈퇴」 활성 조건의 행 단위 판정.
  bool get isFinished =>
      status == DisconnectRowStatus.done ||
      status == DisconnectRowStatus.skipped;

  /// [status] 만 바꾼 새 행을 돌려준다.
  DisconnectRow copyWith({DisconnectRowStatus? status}) => DisconnectRow(
    providerId: providerId,
    provider: provider,
    kind: kind,
    status: status ?? this.status,
  );
}

/// 진행 화면 상태 — 행 목록과 사용자 트리거 직렬화 표시.
@immutable
class WithdrawalDisconnectState {
  /// [WithdrawalDisconnectState] 를 생성한다.
  const WithdrawalDisconnectState({
    this.rows = const <DisconnectRow>[],
    this.userTriggered,
  });

  /// 표시 순서의 행 목록.
  final List<DisconnectRow> rows;

  /// 진행 중인 사용자 트리거 행(재로그인 로그인 · 서버 행 재시도) — 없으면
  /// null. 진입 직후 자동 행 실행은 여기에 기록하지 않는다(UI-SPEC — 자동
  /// 행이 도는 동안에도 현재 재로그인 행의 로그인 버튼은 활성).
  final AccountProvider? userTriggered;

  /// 모든 행이 해제됨 또는 건너뜀 — 행이 없으면(스냅샷 전) 거짓.
  bool get allDone => rows.isNotEmpty && rows.every((row) => row.isFinished);

  /// 「해제 중」 행이 하나라도 있는가 — back 차단 · 「탈퇴」 비활성 조건.
  bool get anyWorking =>
      rows.any((row) => row.status == DisconnectRowStatus.working);

  /// 사용자 트리거 행이 진행 중이라 다른 행 동작 · 「탈퇴」 가 잠겼는가.
  bool get actionsLocked => userTriggered != null;

  /// 현재 재로그인 행 — 위에서부터 첫 번째 미완료 재로그인 행 (없으면 null).
  DisconnectRow? get currentReloginRow => rows
      .where((row) => row.kind == DisconnectKind.relogin && !row.isFinished)
      .firstOrNull;
}

/// [providerIds] 에서 진행 화면 행 목록을 만든다 (D-06 · UI-SPEC §행 순서).
///
/// - [AccountProvider.tryParse] 가 식별하지 못한 값 · email · [steps] 에 끊기
///   step 이 없는 provider 는 제외한다(끊을 provider 측 연결이 없다).
/// - 같은 provider 가 두 형식(`'google'` · `'google.com'`)으로 있으면 먼저 온
///   값 하나만 남긴다.
/// - 순서 = 서버 행 먼저 → 재로그인 행, 각 묶음은 [kSocialProviderOrder] 순.
/// - 상태는 모두 대기에서 시작해 [normalizeDisconnectRows] 로 현재 행을 정한다.
///
/// 결과가 비어 있으면 진행 화면을 열지 않는다(UI-SPEC Q6-A).
List<DisconnectRow> buildDisconnectRows(
  List<String> providerIds,
  List<DisconnectStep> steps,
) {
  final seen = <AccountProvider>{};
  final rows = <DisconnectRow>[];
  for (final providerId in providerIds) {
    final provider = AccountProvider.tryParse(providerId);
    if (provider == null || provider == AccountProvider.email) continue;
    if (!seen.add(provider)) continue;
    final step = disconnectStepFor(steps, provider);
    if (step == null) continue;
    rows.add(
      DisconnectRow(
        providerId: providerId,
        provider: provider,
        kind: step.kind,
        status: DisconnectRowStatus.waiting,
      ),
    );
  }
  rows.sort((a, b) {
    final byKind = _kindRank(a.kind).compareTo(_kindRank(b.kind));
    if (byKind != 0) return byKind;
    return _orderRank(a.provider).compareTo(_orderRank(b.provider));
  });
  return normalizeDisconnectRows(rows);
}

/// 서버 행을 재로그인 행보다 앞에 두는 정렬 rank.
int _kindRank(DisconnectKind kind) => kind == DisconnectKind.server ? 0 : 1;

/// [kSocialProviderOrder] 의 자리 — 목록에 없는 provider 는 맨 뒤.
int _orderRank(AccountProvider provider) {
  final index = kSocialProviderOrder.indexOf(provider);
  return index < 0 ? kSocialProviderOrder.length : index;
}

/// 현재 재로그인 행을 하나로 맞춘 새 목록을 돌려준다 (UI-SPEC §현재 행).
///
/// 위에서부터 첫 번째 미완료 재로그인 행이 현재 행이다 — 그 행이 대기면
/// 로그인 대기로 바꾸고, 그 뒤 재로그인 행 중 로그인 대기는 대기로 되돌린다.
/// 실패 · 신원 불일치 · 해제 중 행은 그대로다(현재 행으로 남는다). 서버 행은
/// 바꾸지 않는다.
List<DisconnectRow> normalizeDisconnectRows(List<DisconnectRow> rows) {
  var currentFound = false;
  final result = <DisconnectRow>[];
  for (final row in rows) {
    if (row.kind != DisconnectKind.relogin || row.isFinished) {
      result.add(row);
    } else if (!currentFound) {
      currentFound = true;
      result.add(
        row.status == DisconnectRowStatus.waiting
            ? row.copyWith(status: DisconnectRowStatus.needsSignIn)
            : row,
      );
    } else {
      result.add(
        row.status == DisconnectRowStatus.needsSignIn
            ? row.copyWith(status: DisconnectRowStatus.waiting)
            : row,
      );
    }
  }
  return result;
}

/// 탈퇴 진행 화면 notifier (Phase 16.10 D-05 · D-06 · D-07 · D-12 · D-14).
///
/// auto-dispose — 화면이 살아 있는 동안만 상태를 가진다(D-14 영속화 0).
/// [build] 는 빈 상태만 반환하고 다른 provider 를 읽지 않는다 — 행 스냅샷과
/// 서버 행 시작은 화면이 첫 프레임 뒤 1회 부르는 [start] 가 한다(Pitfall 4).
@riverpod
class WithdrawalDisconnect extends _$WithdrawalDisconnect {
  /// [start] 1회 가드.
  bool _started = false;

  @override
  WithdrawalDisconnectState build() => const WithdrawalDisconnectState();

  /// 행 목록을 1회 스냅샷하고 서버 행을 모두 자동 시작한다 (Q2-A).
  ///
  /// 두 번째 호출은 무시한다. 행 대상은 이 시점의 `currentUserProvider`
  /// providerIds 이며, 이후 user stream 재방출은 행에 반영하지 않는다.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final providerIds =
        ref.read(currentUserProvider)?.providerIds ?? const <String>[];
    final steps = ref.read(disconnectStepsProvider);
    state = WithdrawalDisconnectState(
      rows: buildDisconnectRows(providerIds, steps),
    );
    await Future.wait(<Future<void>>[
      for (final row in state.rows)
        if (row.kind == DisconnectKind.server)
          _runRow(row.provider, userTriggered: false),
    ]);
  }

  /// 현재 재로그인 행 [provider] 의 로그인 → 끊기를 실행한다.
  ///
  /// 잠금이 없고, [provider] 가 현재 재로그인 행이며, 그 행이 로그인 대기 ·
  /// 실패 · 신원 불일치일 때만 실행한다. 로그인은 서버 탈퇴 신선도를
  /// 겸한다(D-07).
  Future<void> signInAndDisconnect(AccountProvider provider) async {
    if (state.actionsLocked) return;
    final current = state.currentReloginRow;
    if (current == null || current.provider != provider) return;
    if (!_actionableStatuses.contains(current.status)) return;
    await _runRow(provider, userTriggered: true);
  }

  /// 실패한 서버 행 [provider] 를 다시 끊는다 (D-12 재시도).
  Future<void> retry(AccountProvider provider) async {
    if (state.actionsLocked) return;
    final row = _rowOf(provider);
    if (row == null ||
        row.kind != DisconnectKind.server ||
        row.status != DisconnectRowStatus.failed) {
      return;
    }
    await _runRow(provider, userTriggered: true);
  }

  /// [provider] 행을 건너뛴다 (D-12 — 되돌리기 없음).
  ///
  /// 잠금이 없고 그 행이 끝나지 않았으며 해제 중이 아닐 때만 건너뛴다.
  void skip(AccountProvider provider) {
    if (state.actionsLocked) return;
    final row = _rowOf(provider);
    if (row == null ||
        row.isFinished ||
        row.status == DisconnectRowStatus.working) {
      return;
    }
    state = WithdrawalDisconnectState(
      rows: _replaceRow(provider, DisconnectRowStatus.skipped),
      userTriggered: state.userTriggered,
    );
  }

  /// 모든 행이 끝났을 때 계정 삭제를 1회 요청한다 (D-05 · C-01).
  ///
  /// 삭제는 기존 `SettingsNotifier.requestAccountDeletion` 을 그대로 부른다 —
  /// 성공 · 실패 분기는 화면이 settings provider 를 listen 해 처리한다. 실패해도
  /// 행 상태를 스스로 바꾸지 않는다(5분 창 복구는 화면이 명시 호출한다).
  Future<void> requestDeletion() async {
    final current = state;
    if (!current.allDone || current.anyWorking || current.actionsLocked) {
      return;
    }
    final settings = ref.read(settingsProvider.notifier);
    // 이중 탭 방지 — 삭제가 이미 진행 중이면 다시 부르지 않는다.
    if (ref.read(settingsProvider).isLoading) return;
    await settings.requestAccountDeletion();
  }

  /// 로그인 버튼이 동작하는 현재 행 상태.
  static const Set<DisconnectRowStatus> _actionableStatuses =
      <DisconnectRowStatus>{
        DisconnectRowStatus.needsSignIn,
        DisconnectRowStatus.failed,
        DisconnectRowStatus.mismatch,
      };

  /// [provider] 행을 찾는다 — 없으면 null.
  DisconnectRow? _rowOf(AccountProvider provider) =>
      state.rows.where((row) => row.provider == provider).firstOrNull;

  /// [provider] 행의 상태를 [status] 로 바꾸고 현재 행을 다시 맞춘 목록.
  List<DisconnectRow> _replaceRow(
    AccountProvider provider,
    DisconnectRowStatus status,
  ) {
    return normalizeDisconnectRows(<DisconnectRow>[
      for (final row in state.rows)
        row.provider == provider ? row.copyWith(status: status) : row,
    ]);
  }

  /// [provider] 행의 끊기 step 을 실행하고 결과를 행 상태로 반영한다.
  ///
  /// [userTriggered] 면 실행 동안 다른 사용자 동작을 잠근다(T-16.10-32).
  /// step · 의존은 await 전에 캡처한다. step 은 예외를 던지지 않는 계약이지만
  /// 예상 밖 throw 는 실패로 흡수한다.
  Future<void> _runRow(
    AccountProvider provider, {
    required bool userTriggered,
  }) async {
    final step = disconnectStepFor(ref.read(disconnectStepsProvider), provider);
    final row = _rowOf(provider);
    if (step == null || row == null) return;
    final deps = ref.read(disconnectDepsProvider);
    state = WithdrawalDisconnectState(
      rows: _replaceRow(provider, DisconnectRowStatus.working),
      userTriggered: userTriggered ? provider : state.userTriggered,
    );
    DisconnectOutcome outcome;
    try {
      outcome = await step.run(deps, reloginForFreshness: true);
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint(
          'WithdrawalDisconnect(${provider.slug}): run threw '
          'runtimeType=${e.runtimeType}',
        );
      }
      outcome = DisconnectFailed(ServiceUnavailable(cause: e));
    }
    if (!ref.mounted) return;
    final next = switch (outcome) {
      DisconnectDone() => DisconnectRowStatus.done,
      // 로그인 취소는 실패가 아니다 — 재로그인 행은 로그인 대기로 돌아간다.
      DisconnectCancelled() =>
        row.kind == DisconnectKind.relogin
            ? DisconnectRowStatus.needsSignIn
            : DisconnectRowStatus.failed,
      DisconnectIdentityMismatch() => DisconnectRowStatus.mismatch,
      DisconnectFailed() => DisconnectRowStatus.failed,
    };
    state = WithdrawalDisconnectState(
      rows: _replaceRow(provider, next),
      userTriggered: userTriggered ? null : state.userTriggered,
    );
  }
}
