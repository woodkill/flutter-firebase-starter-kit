import 'package:flutter/material.dart';

/// "이메일로 계속" 공유 CTA (Phase 16.1 Surface S) — RED 단계 placeholder.
///
/// 본 구현은 TDD RED 단계에서 컴파일만 성립시키기 위한 빈 골격이며,
/// 라벨·렌더는 GREEN 커밋에서 구현한다.
class EmailAuthCta extends StatelessWidget {
  /// [EmailAuthCta] 를 생성한다.
  const EmailAuthCta({required this.onPressed, super.key});

  /// 탭 콜백. 라우팅은 호출자 책임이다.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
