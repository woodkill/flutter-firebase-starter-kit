import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/session_ending.dart';

/// 감싼 화면의 route 진입 전환이 끝나면 세션 종료 관리자에게 도착을 알리는 표식
/// (quick 261011-e6c).
///
/// 로그아웃 · 회원탈퇴 뒤의 목적지 route(킷 기본값은 온보딩)의 `builder` 를 이
/// 위젯으로 감싼다. 관리자는 이 보고와 저장소 로그아웃 종료가 모두 닿았을 때
/// 진행 오버레이를 걷는다.
///
/// **도착 판정:** route 가 offstage 가 아니고 **그리고** 진입 애니메이션이
/// `completed` 인 프레임이 끝난 뒤다. route 가 push 되는 첫 프레임에는 Hero
/// 측정을 위해 route 가 offstage 로 그려지고, 그동안 `ModalRoute.animation` 은
/// 항상 `completed` 를 보고한다 — 애니메이션 상태만 보면 전환이 시작되자마자
/// 오버레이가 걷혀 옛 화면이 드러난다. 그래서 offstage 를 함께 보고, 프레임 뒤
/// 콜백 안에서 같은 조건을 다시 확인한다.
class SessionEndingArrival extends ConsumerStatefulWidget {
  /// [child] 화면의 도착을 알리는 표식을 생성한다.
  const SessionEndingArrival({super.key, required this.child});

  /// 그대로 그릴 목적지 화면.
  final Widget child;

  @override
  ConsumerState<SessionEndingArrival> createState() =>
      _SessionEndingArrivalState();
}

class _SessionEndingArrivalState extends ConsumerState<SessionEndingArrival> {
  /// 이 위젯을 담은 route — route 없이 그린 경우(위젯 테스트)는 `null`.
  ModalRoute<Object?>? _route;

  /// 상태 리스너를 걸어 둔 진입 애니메이션.
  Animation<double>? _animation;

  /// 프레임 뒤 보고 콜백이 이미 예약돼 있는지 — 한 프레임에 1개만 예약한다.
  bool _isReportScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final animation = route?.animation;
    if (!identical(animation, _animation)) {
      _animation?.removeStatusListener(_handleAnimationStatus);
      animation?.addStatusListener(_handleAnimationStatus);
      _animation = animation;
    }
    _route = route;
    _scheduleReportIfShown();
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_handleAnimationStatus);
    super.dispose();
  }

  /// 진입 애니메이션 상태가 바뀔 때마다 도착 여부를 다시 본다.
  void _handleAnimationStatus(AnimationStatus status) =>
      _scheduleReportIfShown();

  /// 화면이 실제로 보이는 상태인지 — offstage 가 아니고 진입 전환이 끝났다.
  bool _checkShown() {
    final route = _route;
    if (route == null) {
      // route 없이 그린 경우에는 전환이 없다.
      return true;
    }
    if (route.offstage) {
      return false;
    }
    final animation = _animation;
    return animation == null || animation.status == AnimationStatus.completed;
  }

  /// 보이는 상태면 프레임 뒤에 관리자에게 알릴 콜백을 1개 예약한다.
  void _scheduleReportIfShown() {
    if (_isReportScheduled || !_checkShown()) {
      return;
    }
    _isReportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isReportScheduled = false;
      // 프레임이 끝나는 사이 offstage 가 풀려 애니메이션이 `forward` 로 바뀌었을
      // 수 있다 — 같은 조건을 다시 확인한다.
      if (!mounted || !_checkShown()) {
        return;
      }
      ref.read(sessionEndingProvider.notifier).handleOnboardingShown();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
