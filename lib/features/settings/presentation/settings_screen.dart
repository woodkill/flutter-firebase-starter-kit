// Phase 16 Plan 16-06 본체 채움 — Wave 0 sentinel placeholder.
//
// `SettingsScreen` 은 Material 3 ListTile + Danger zone (탈퇴) 구성의
// 설정 화면. Plan 16-06 이 본체 (사용자 정보 표시 + 탈퇴 진입점) 를
// add-only 로 확장한다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 설정 화면 (Phase 16 D-06).
///
/// **Wave 0 sentinel placeholder** — Plan 16-06 이 본체 채움.
///
/// 본체 구현 시 mirror source: UI-SPEC Surface B (line 248~275) — Material 3
/// ListTile + Danger zone 격리 section.
class SettingsScreen extends ConsumerWidget {
  /// [SettingsScreen] 을 생성한다.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(
      body: Center(
        child: Text('Phase 16 Plan 16-06 implementation pending'),
      ),
    );
  }
}
