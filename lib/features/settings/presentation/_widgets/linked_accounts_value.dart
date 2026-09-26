// Phase 16.8 D-10 · D-11 · D-12 — 설정 「연결된 계정」 값 (해제 가능 변형).
//
// UI-SPEC §Surface S (16.8) 트리 verbatim. 홈 계정정보 카드의 보기 전용
// `buildLinkedAccountsValue`(lib/shared/auth/)는 손대지 않는다 — 홈은 보기
// 전용이고(D-10) 홈 golden byte 동일이 가드다. `InkWell` · `Semantics` 는
// material 위젯이라 widgets 만 쓰는 `shared/` 대신 설정 feature 에 둔다.
//
// 16.7 (c) 메커니즘 그대로 provider 1개 = baseline `WidgetSpan` 1개이고 사이는
// 공백 `TextSpan` 이다 — 줄은 쉼표 뒤에서만 바뀌고 라벨 내부에서는 끊기지
// 않는다. 밑줄은 기존 값 스타일에 decoration 만 더해 행 높이 · 줄바꿈 위치를
// 바꾸지 않는다 (새 색 · 새 크기 0).
import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';

/// 설정 「연결된 계정」 값 span 을 만든다 — 해제 가능 이름은 밑줄 텍스트
/// 버튼, 해제 불가 이름은 일반 텍스트 (Phase 16.8 D-10 · D-11 · D-12 ·
/// UI-SPEC §Surface S (16.8)).
///
/// - [entries] — 표시 순서의 연결된 계정 `(id, label)` 쌍. 라벨은
///   `formatProviderLabels` 결과를 그대로 받는다 (provider 별 switch 신설 0 —
///   D-19).
/// - [none] — 0개일 때 값 (`authAccountLinkedAccountsNone`) — 일반
///   `TextSpan` 이라 ListTile 이 제목 · 값을 한 label 로 병합한다.
/// - [valueStyle] — 값 스타일 (`titleMedium`). 해제 가능 이름은 이 스타일에
///   `TextDecoration.underline` 만 더하고, 뒤따르는 쉼표는 밑줄이 없다.
/// - [canUnlink] — id 별 버튼 여부 (`canUnlinkProvider` 위임).
/// - [onUnlinkTap] — 버튼 탭 시 `(id, label)` 로 호출된다 (확인 다이얼로그 진입).
/// - [l10n] — 버튼 semantics label `settingsUnlinkProviderSemantic`.
///
/// **Semantics (UI-SPEC §Semantics):** 버튼마다 `Semantics(container, button,
/// label: 「{provider} 연결 해제」, onTap)` 노드가 생기고, 해제 불가 이름은 쉼표
/// 없는 이름만 가진 label 노드가 된다. 사이 공백은 `semanticsLabel: ''` 로
/// 비워야 공백이 부모 label 에 섞이지 않는다. 바깥 `Text.rich` 에
/// `semanticsLabel` 을 주면 안쪽 버튼 노드가 지워지므로 호출자는 주지 않는다.
InlineSpan buildUnlinkableLinkedAccountsValue({
  required List<({String id, String label})> entries,
  required String none,
  required TextStyle valueStyle,
  required bool Function(String id) canUnlink,
  required void Function(String id, String label) onUnlinkTap,
  required AppLocalizations l10n,
}) {
  if (entries.isEmpty) {
    return TextSpan(text: none);
  }
  final lastIndex = entries.length - 1;
  return TextSpan(
    children: [
      for (var i = 0; i < entries.length; i++) ...[
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: canUnlink(entries[i].id)
              ? _UnlinkableName(
                  label: entries[i].label,
                  comma: i < lastIndex,
                  valueStyle: valueStyle,
                  semanticsLabel: l10n.settingsUnlinkProviderSemantic(
                    entries[i].label,
                  ),
                  onTap: () => onUnlinkTap(entries[i].id, entries[i].label),
                )
              : _PlainName(
                  label: entries[i].label,
                  comma: i < lastIndex,
                  valueStyle: valueStyle,
                ),
        ),
        // 빈 semantics — 빼면 공백이 ListTile label 에 섞인다 (§Semantics 실측).
        if (i < lastIndex) const TextSpan(text: ' ', semanticsLabel: ''),
      ],
    ],
  );
}

/// 해제 가능 이름 — 이름만 밑줄 · 쉼표는 밑줄 없음. 탭 영역 = WidgetSpan
/// 상자 전체 (padding 0 — D-13 · UI-SPEC Q6-A).
class _UnlinkableName extends StatelessWidget {
  const _UnlinkableName({
    required this.label,
    required this.comma,
    required this.valueStyle,
    required this.semanticsLabel,
    required this.onTap,
  });

  final String label;
  final bool comma;
  final TextStyle valueStyle;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // semantics 는 바깥 Semantics 가 소유한다 — InkWell 자체 노드는 뺀다.
    return Semantics(
      container: true,
      button: true,
      label: semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        excludeFromSemantics: true,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: label,
                style: valueStyle.copyWith(
                  decoration: TextDecoration.underline,
                ),
              ),
              if (comma) const TextSpan(text: ','),
            ],
          ),
          style: valueStyle,
        ),
      ),
    );
  }
}

/// 해제 불가 이름 — 16.7 과 같은 `Text('라벨,')` · semantics 는 쉼표 없는
/// 이름만 (D-11).
class _PlainName extends StatelessWidget {
  const _PlainName({
    required this.label,
    required this.comma,
    required this.valueStyle,
  });

  final String label;
  final bool comma;
  final TextStyle valueStyle;

  @override
  Widget build(BuildContext context) {
    // container 로 묶어야 이름이 부모 label 끝으로 몰려 순서가 뒤바뀌지 않는다.
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Text(comma ? '$label,' : label, style: valueStyle),
    );
  }
}
