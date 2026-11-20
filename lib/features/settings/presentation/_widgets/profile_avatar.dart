// 사진 행 · 설정 계정/게스트 행 공용 아바타.
//
// 사진이 없으면 사람 아이콘을 원 바탕(primaryContainer)과 짝인 역할
// (onPrimaryContainer)로 그린다 — 두 색을 CircleAvatar 한 곳에서 정한다.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/theme_extensions.dart';

/// 기본 반지름 [CircleAvatar] — 사진(cover) 또는 `Icons.person` placeholder.
///
/// 지름 40 dp(기본 반지름 20). 장식이라 호출부가 [ExcludeSemantics] 로 감싼다.
/// 사진 행([photoUrl] = 표시 사진)과 설정 계정 · 게스트 행(게스트 = null)이 같이
/// 쓴다 (Phase 17.1 UI-SPEC §(S)).
class ProfileAvatar extends StatelessWidget {
  /// [ProfileAvatar] 를 생성한다.
  const ProfileAvatar({super.key, required this.photoUrl});

  /// 사진 URL (null = placeholder).
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    // CircleAvatar 는 backgroundImage 를 BoxFit.cover 로 채운다 — 원형 가운데
    // 맞춤(D-41). 이미지 로드 실패는 배경색만 남기고 조용히 넘긴다.
    return CircleAvatar(
      // 바탕과 아이콘은 짝 역할이다 — 아이콘에는 색을 주지 않아 전경색을
      // 받는다. 색 역할 자리에서 두 역할을 함께 정하면 아바타도 그 짝을 쓴다.
      backgroundColor: context.colorScheme.primaryContainer,
      foregroundColor: context.colorScheme.onPrimaryContainer,
      backgroundImage: url != null ? CachedNetworkImageProvider(url) : null,
      onBackgroundImageError: url != null ? (_, _) {} : null,
      child: url == null ? const Icon(Icons.person) : null,
    );
  }
}
