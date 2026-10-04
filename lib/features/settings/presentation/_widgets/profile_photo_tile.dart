// Phase 17 D-15 · D-17 · D-18 · D-23 · D-41 · UI-SPEC (P) Q2-A — 계정 정보
// 화면(`AccountScreen`) 「프로필」 첫 행 프로필 사진.
//
// 참조 구현 = mockups/p17_widgets.dart.txt `ProfilePhotoTile` (같은 트리 · 토큰,
// 문구만 ARB). 행 탭 → 사진 메뉴 → 업로드 · 삭제 → 결과 SnackBar.
// Phase 17.1 UI-SPEC §(S) DRY — 아바타는 공용 [ProfileAvatar](profile_avatar.dart)
// 로 추출했다(설정 계정 · 게스트 행과 공유 · 렌더 동일).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/error_snack_bar.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/domain/user.dart';
import '../../application/profile_photo_notifier.dart';
import 'profile_avatar.dart';
import 'profile_photo_sheet.dart';

/// 사진 행 아바타 지름 — [CircleAvatar] 기본 반지름 20 의 2배 (UI-SPEC (P)).
const double _kAvatarDiameter = 40;

/// 계정 정보 화면 첫 행 — 프로필 사진 (Phase 17 D-18 · UI-SPEC (P) Q2-A).
///
/// - 아바타: 기본 반지름 [CircleAvatar](40 dp) · 사진은 `BoxFit.cover` 가운데
///   맞춤(D-41 — 자르기 화면 없음) · 없으면 `Icons.person` · 장식이라
///   [ExcludeSemantics].
/// - 값: 직접 올린 사진 > 소셜 사진 > 없음 (D-17 표시 우선순위).
/// - 탭: 사진 메뉴 → 업로드 · 삭제 → 성공 · 실패 SnackBar (실패 시 행은 이전
///   상태).
///
/// 행 상태 (D-23 · UI-SPEC E2 — 배너 없음 · non-blocking): 사진 출처
/// (`users/{uid}` stream) 첫 값 전 = 현재 사진 + 「불러오는 중」 · 탭 비활성,
/// 읽기 실패 = 업로드 사진 없음 취급(소셜 · 없음) · 탭 가능, 업로드 · 삭제
/// 중 = 사진 위 진행 링 + 「사진을 올리는 중…」 · 탭 비활성.
///
/// 계정 정보 화면(`AccountScreen`)은 guard 가 정식 사용자만 들여보낸다
/// (17.1 D-07) — 사용자가 없으면 행을 그리지 않는다.
class ProfilePhotoTile extends ConsumerWidget {
  /// [ProfilePhotoTile] 을 생성한다.
  const ProfilePhotoTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final isBusy = ref.watch(profilePhotoProvider);
    return AsyncValueView<UserProviderRecord>(
      value: ref.watch(linkedProvidersStreamProvider(user.uid)),
      loading: () => _PhotoRow(
        photoUrl: user.photoUrl,
        value: context.l10n.commonLoading,
        isBusy: false,
        onTap: null,
      ),
      // 읽기 실패 — 업로드 사진 없음 취급 · 배너 없음 (non-blocking).
      error: (_, _) => _buildRow(
        context,
        ref,
        photoUrl: _socialPhotoUrlOf(user),
        hasCustomPhoto: false,
        isBusy: isBusy,
      ),
      data: (_) => _buildRow(
        context,
        ref,
        photoUrl: user.photoUrl,
        hasCustomPhoto: user.customPhotoUrl != null,
        isBusy: isBusy,
      ),
    );
  }

  /// 사진 출처를 읽은 뒤의 행 — 값 · 탭은 업로드 사진 유무와 busy 로 정한다.
  Widget _buildRow(
    BuildContext context,
    WidgetRef ref, {
    required String? photoUrl,
    required bool hasCustomPhoto,
    required bool isBusy,
  }) {
    final l10n = context.l10n;
    final String value;
    if (isBusy) {
      value = l10n.settingsProfilePhotoUploading;
    } else if (hasCustomPhoto) {
      value = l10n.settingsProfilePhotoSourceCustom;
    } else if (photoUrl != null) {
      value = l10n.settingsProfilePhotoSourceSocial;
    } else {
      value = l10n.settingsProfilePhotoSourceNone;
    }
    return _PhotoRow(
      photoUrl: photoUrl,
      value: value,
      isBusy: isBusy,
      onTap: isBusy
          ? null
          : () => _onTap(context, ref, hasCustomPhoto: hasCustomPhoto),
    );
  }

  /// 행 탭 — 사진 메뉴를 열고 고른 동작을 실행한 뒤 결과 SnackBar 를 띄운다.
  Future<void> _onTap(
    BuildContext context,
    WidgetRef ref, {
    required bool hasCustomPhoto,
  }) async {
    final notifier = ref.read(profilePhotoProvider.notifier);
    final action = await showProfilePhotoSheet(
      context,
      hasCustomPhoto: hasCustomPhoto,
    );
    if (action == null) return;
    final result = switch (action) {
      ProfilePhotoSheetAction.pick => await notifier.pickAndUpload(),
      ProfilePhotoSheetAction.remove => await notifier.remove(),
    };
    if (!context.mounted) return;
    switch (result) {
      case ProfilePhotoActionResult.success:
        _showSuccessSnackBar(context, action);
      case ProfilePhotoActionResult.cancelled:
        break;
      case ProfilePhotoActionResult.failed:
        showErrorSnackBar(context, switch (action) {
          ProfilePhotoSheetAction.pick => const ProfilePhotoUploadException(),
          ProfilePhotoSheetAction.remove => const ProfilePhotoRemoveException(),
        });
    }
  }
}

/// [action] 성공 SnackBar — 업로드 = 「변경했습니다」 · 삭제 = 「삭제했습니다」.
void _showSuccessSnackBar(
  BuildContext context,
  ProfilePhotoSheetAction action,
) {
  final l10n = context.l10n;
  final message = switch (action) {
    ProfilePhotoSheetAction.pick => l10n.settingsProfilePhotoUpdated,
    ProfilePhotoSheetAction.remove => l10n.settingsProfilePhotoRemoved,
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// 업로드 사진을 뺀 소셜 사진 URL — 사진 출처 읽기 실패 때 쓴다.
///
/// [User.photoUrl] 은 업로드 사진 > 소셜 사진 합성값이라, 업로드 사진이 있으면
/// 소셜 사진을 따로 알 수 없어 placeholder(null)로 둔다. production 의
/// `currentUserProvider` 는 읽기 실패 때 이미 업로드 사진을 비운다.
String? _socialPhotoUrlOf(User user) =>
    user.customPhotoUrl == null ? user.photoUrl : null;

/// 사진 행 외관 — 참조 구현 `ProfilePhotoTile` 트리 그대로.
class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.photoUrl,
    required this.value,
    required this.isBusy,
    required this.onTap,
  });

  /// 아바타에 그릴 사진 URL (null = placeholder).
  final String? photoUrl;

  /// subtitle 값 문구.
  final String value;

  /// 업로드 · 삭제 중이면 true — 아바타 위에 진행 링을 겹친다.
  final bool isBusy;

  /// 행 탭 — null 이면 비활성.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // WR-07: appTypography 가 AppTypography override 를 반영하는 유일한 경로.
    final typography = context.appTypography;
    final scheme = context.colorScheme;
    final avatar = ProfileAvatar(photoUrl: photoUrl);
    return ListTile(
      leading: ExcludeSemantics(
        child: isBusy
            // 업로드 · 삭제 중 — 아바타 위 40 dp 진행 링 (SDK 기본 크기 아님).
            ? SizedBox.square(
                dimension: _kAvatarDiameter,
                child: Stack(
                  fit: StackFit.expand,
                  children: [avatar, const CircularProgressIndicator()],
                ),
              )
            : avatar,
      ),
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
