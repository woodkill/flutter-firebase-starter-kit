import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../application/session_ending.dart';
import 'auth_in_progress_overlay.dart';

/// 로그아웃 · 회원탈퇴 마무리 동안 앱 전체를 덮는 최상위 오버레이
/// (quick 261011-e6c).
///
/// `MaterialApp.router` 의 `builder` 에 한 번만 둔다 — Navigator 위라서
/// 다이얼로그까지 덮고, route 가 바뀌어도 그대로 남는다. 모양은
/// [AuthInProgressOverlay] 그대로이고 문구만 [SessionEndingKind] 에 따라
/// 바뀐다.
///
/// **항상 같은 [Stack] 을 돌려준다.** [child](Navigator) 는 늘 첫 자리에 있어
/// 오버레이가 켜지고 꺼져도 State 가 유지된다. 진행 중일 때만 child 를 Stack
/// 으로 감싸면 켜지는 순간 Navigator 가 통째로 다시 만들어진다.
///
/// **[Material] 로 감싸는 이유:** `builder` 자리에는 Material 조상이 없다.
/// 감싸지 않으면 라벨이 Scaffold 안에서 쓰는 `DefaultTextStyle` 을 물려받지
/// 못해, 조상 스타일을 상속하는 타이포그래피 테마에서 글자 모양이 달라진다.
class SessionEndingOverlay extends ConsumerWidget {
  /// [child](Navigator) 위에 얹을 오버레이를 생성한다.
  const SessionEndingOverlay({super.key, required this.child});

  /// 오버레이 아래에 그대로 둘 앱 본체 — `MaterialApp.router` 의 Navigator.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(
      sessionEndingProvider.select((SessionEndingState state) => state.kind),
    );
    final label = switch (kind) {
      SessionEndingKind.none => null,
      SessionEndingKind.signOut => context.l10n.authSigningOut,
      SessionEndingKind.withdrawal => context.l10n.withdrawalFinalizing,
    };

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        child,
        if (label != null)
          Material(
            type: MaterialType.transparency,
            // AuthInProgressOverlay 는 Positioned.fill 을 돌려주므로 바로 위
            // 부모가 Stack 이어야 한다.
            child: Stack(
              children: <Widget>[AuthInProgressOverlay(label: label)],
            ),
          ),
      ],
    );
  }
}
