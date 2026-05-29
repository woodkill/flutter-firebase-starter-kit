// Phase 16 Plan 16-04 본체 채움 — Wave 0 sentinel placeholder.
//
// `AccountLinkingSheet` 는 이메일 충돌 시 기존 provider 와 추가 provider
// 를 link 하는 bottom sheet. `LoginPromptSheet` (Phase 10) 의 패턴을 mirror.
// Plan 16-04 이 본체 (existingProvider type ProviderId enum 교체 + link
// 진행 + linkCustomTokenProvider Cloud Function 호출) 를 add-only 로 확장.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 계정 연동 Bottom Sheet (Phase 16 D-04 / D-09 / D-10).
///
/// **Wave 0 sentinel placeholder** — Plan 16-04 이 본체 채움.
///
/// 본체 구현 시 mirror source:
///   `lib/features/auth/presentation/_widgets/login_prompt_sheet.dart`
///   (Phase 10 D-10) — showModalBottomSheet + drag handle + Theme
///   surfaceContainerHigh background + 28dp 상단 둥근 모서리.
///
/// **타입 진화 (Plan 16-04 가 변경):** [existingProvider] 는 현재 `String`
/// (placeholder) 이지만 Plan 16-04 가 `ProviderId` enum 으로 교체한다.
class AccountLinkingSheet extends ConsumerStatefulWidget {
  /// [AccountLinkingSheet] 를 생성한다.
  const AccountLinkingSheet({
    required this.existingProvider,
    required this.collisionEmail,
    super.key,
  });

  /// 기존에 가입된 provider ID (Plan 16-04 가 `ProviderId` enum 으로 교체).
  final String existingProvider;

  /// 충돌이 발생한 이메일 주소.
  final String collisionEmail;

  /// [AccountLinkingSheet] 를 modal bottom sheet 로 표시한다.
  static Future<bool?> show(
    BuildContext context, {
    required String existingProvider,
    required String collisionEmail,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isDismissible: true,
      showDragHandle: true,
      builder: (_) => AccountLinkingSheet(
        existingProvider: existingProvider,
        collisionEmail: collisionEmail,
      ),
    );
  }

  @override
  ConsumerState<AccountLinkingSheet> createState() =>
      _AccountLinkingSheetState();
}

class _AccountLinkingSheetState extends ConsumerState<AccountLinkingSheet> {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Text('Phase 16 Plan 16-04 placeholder'),
    );
  }
}
