import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import 'login_prompt_sheet.dart';

/// 보호된 UI 요소를 감싸서 탭 시점에 isAnonymous 체크를 수행한다 (Phase 10 D-12).
///
/// - 미인증 또는 익명 사용자: [showLoginPromptSheet] 호출하여
///   하단에서 [LoginPromptSheet] 표시 (D-10)
/// - 정식 인증 사용자: [onAuthenticated] 콜백을 실행하여 원래 동작 수행
/// - Firebase 미초기화 (Phase 1 D-13): [onAuthenticated] fallback 실행
///   (Starter Kit 은 Firebase 없이도 앱 정상 실행이 원칙)
///
/// 사용 예:
/// ```dart
/// AuthRequired(
///   onAuthenticated: _runProtectedAction,
///   child: OutlinedButton.icon(
///     onPressed: null, // AuthRequired 가 GestureDetector 로 가로챔
///     icon: const Icon(Icons.lock_outline),
///     label: Text(l10n.homeProtectedExampleCta),
///   ),
/// )
/// ```
///
/// [child] 의 `onPressed` 는 null 로 두는 것이 컨벤션이다. 내부 탭 이벤트는
/// [AbsorbPointer] 가 흡수하고 외부 [GestureDetector] 가 가로챈다.
/// 이는 T-10-15 (AuthRequired 우회 시도) 방어의 1차 방어선이며, 서버 측
/// Firestore Security Rules (Phase 18 — see ROADMAP.md) 이 이중 방어로 보강한다.
class AuthRequired extends ConsumerWidget {
  /// [AuthRequired] 를 생성한다.
  const AuthRequired({
    required this.child,
    required this.onAuthenticated,
    super.key,
  });

  /// 래핑되는 자식 위젯. 일반적으로 버튼/카드 등 탭 가능한 UI 요소.
  final Widget child;

  /// 정식 인증 사용자일 때 실행할 콜백.
  ///
  /// 미인증/익명 사용자의 탭에는 [LoginPromptSheet] 만 노출되며
  /// 본 콜백은 호출되지 않는다.
  final VoidCallback onAuthenticated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleTap(context, ref),
      child: AbsorbPointer(child: child),
    );
  }

  /// 탭 시점에 Firebase 초기화 + 인증 상태를 평가한다.
  ///
  /// - Firebase 미초기화: fallback 으로 [onAuthenticated] 즉시 호출.
  /// - `currentUser == null` 또는 `isAnonymous == true`: Bottom Sheet 노출.
  /// - 정식 인증: [onAuthenticated] 호출.
  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    final isInitialized = ref.read(isFirebaseInitializedProvider);
    if (!isInitialized) {
      // Firebase 미초기화 (D-13): 보호 로직을 우회하여 앱 기본 동작 유지.
      onAuthenticated();
      return;
    }
    final user = ref.read(firebaseAuthProvider).currentUser;
    if (user == null || user.isAnonymous) {
      await showLoginPromptSheet(context);
      return;
    }
    onAuthenticated();
  }
}
