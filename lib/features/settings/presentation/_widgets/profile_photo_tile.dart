// Phase 17 D-15 · D-17 · D-18 · D-41 · UI-SPEC (P) Q2-A — 설정 「내 계정」 첫 행
// 프로필 사진.
//
// 참조 구현 = mockups/p17_widgets.dart.txt `ProfilePhotoTile` (같은 트리 · 토큰,
// 문구만 ARB). 행 탭 → 사진 메뉴 → 동작 → 결과 SnackBar.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../shared/widgets/error_snack_bar.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/domain/user.dart';
import '../../application/profile_photo_notifier.dart';
import 'profile_photo_sheet.dart';

/// 설정 「내 계정」 첫 행 — 프로필 사진 (Phase 17 D-18 · UI-SPEC (P) Q2-A).
///
/// - 아바타: 기본 반지름 [CircleAvatar](40 dp) · 사진은 `BoxFit.cover` 가운데
///   맞춤(D-41 — 자르기 화면 없음) · 없으면 `Icons.person` · 장식이라
///   [ExcludeSemantics].
/// - 값: 직접 올린 사진 > 소셜 사진 > 없음 (D-17 표시 우선순위).
/// - 탭: 사진 메뉴 → 갤러리 선택 → 업로드 → 성공 · 실패 SnackBar. 진행 중에는
///   탭이 비활성이다.
///
/// 정식 사용자만 설정에 들어온다(게스트 진입점 숨김) — 사용자가 없으면 행을
/// 그리지 않는다.
class ProfilePhotoTile extends ConsumerWidget {
  /// [ProfilePhotoTile] 을 생성한다.
  const ProfilePhotoTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final isBusy = ref.watch(profilePhotoProvider);
    return _PhotoRow(
      photoUrl: user.photoUrl,
      value: _sourceLabelOf(context, user),
      onTap: isBusy ? null : () => _onTap(context, ref),
    );
  }

  /// 행 탭 — 사진 메뉴를 열고 고른 동작을 실행한 뒤 결과 SnackBar 를 띄운다.
  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(profilePhotoProvider.notifier);
    final action = await showProfilePhotoSheet(context);
    if (action == null) return;
    final result = switch (action) {
      ProfilePhotoSheetAction.pick => await notifier.pickAndUpload(),
    };
    if (!context.mounted) return;
    switch (result) {
      case ProfilePhotoActionResult.success:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(context.l10n.settingsProfilePhotoUpdated)),
          );
      case ProfilePhotoActionResult.cancelled:
        break;
      case ProfilePhotoActionResult.failed:
        showErrorSnackBar(context, const ProfilePhotoUploadException());
    }
  }
}

/// [user] 의 사진 출처 문구 — 직접 올린 사진 > 소셜 사진 > 없음 (D-17).
String _sourceLabelOf(BuildContext context, User user) {
  final l10n = context.l10n;
  if (user.customPhotoUrl != null) return l10n.settingsProfilePhotoSourceCustom;
  if (user.photoUrl != null) return l10n.settingsProfilePhotoSourceSocial;
  return l10n.settingsProfilePhotoSourceNone;
}

/// 사진 행 외관 — 참조 구현 `ProfilePhotoTile` 트리 그대로.
class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.photoUrl,
    required this.value,
    required this.onTap,
  });

  /// 아바타에 그릴 사진 URL (null = placeholder).
  final String? photoUrl;

  /// subtitle 값 문구.
  final String value;

  /// 행 탭 — null 이면 비활성.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // WR-07: appTypography 가 AppTypography override 를 반영하는 유일한 경로.
    final typography = context.appTypography;
    final scheme = context.colorScheme;
    return ListTile(
      leading: ExcludeSemantics(child: _ProfileAvatar(photoUrl: photoUrl)),
      title: Text(
        l10n.authAccountPhotoUrl,
        style: typography.bodySmall.copyWith(color: scheme.onSurfaceVariant),
      ),
      subtitle: Text(value, softWrap: true, style: typography.titleMedium),
      trailing: Icon(Icons.chevron_right, color: scheme.primary),
      onTap: onTap,
    );
  }
}

/// 기본 반지름 [CircleAvatar] — 사진(cover) 또는 `Icons.person` placeholder.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.photoUrl});

  /// 사진 URL (null = placeholder).
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    // CircleAvatar 는 backgroundImage 를 BoxFit.cover 로 채운다 — 원형 가운데
    // 맞춤(D-41). 이미지 로드 실패는 배경색만 남기고 조용히 넘긴다.
    return CircleAvatar(
      backgroundImage: url != null ? CachedNetworkImageProvider(url) : null,
      onBackgroundImageError: url != null ? (_, _) {} : null,
      child: url == null
          ? Icon(Icons.person, color: context.colorScheme.onSurfaceVariant)
          : null,
    );
  }
}
