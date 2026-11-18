// 계정 화면 「연결된 계정」 값(buildUnlinkableLinkedAccountsValue)의 provider
// 이름이 큰 글자 배율에서 한 번만 커지는지 고정한다.
//
// 해제 가능 이름(밑줄 버튼)과 해제 불가 이름(일반 글자)은 서로 다른 위젯이
// 그린다. fixture 는 두 종류를 섞어 한 값에 같이 그리되, 시험은 종류별로
// 그 종류의 이름만 잰다 — 한 지점만 망가지면 그 종류 시험만 실패한다.

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/linked_accounts_value.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations_ko.dart';
import 'package:flutter_starter_kit/shared/auth/provider_label_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/widget_span_text_scale.dart';

void main() {
  final ko = AppLocalizationsKo();

  // 표시 순서의 연결된 계정 — 해제 가능 3 · 해제 불가 2 를 섞는다.
  const ids = <String>['google.com', 'apple.com', 'kakao', 'naver', 'line'];
  const unlinkableIds = <String>{'google.com', 'kakao', 'line'};
  final labels = formatProviderLabels(ids, ko);
  final entries = <({String id, String label})>[
    for (final (i, id) in ids.indexed) (id: id, label: labels[i]),
  ];

  // 화면에 그려지는 이름 — 마지막 외에는 쉼표가 붙는다.
  String shownName(int i) =>
      i < entries.length - 1 ? '${entries[i].label},' : entries[i].label;

  for (final (kind, isUnlinkable, tag) in <(String, bool, String)>[
    ('해제 가능 이름', true, '[unlinkable]'),
    ('해제 불가 이름', false, '[plain]'),
  ]) {
    for (final c in kWidgetSpanScaleCases) {
      testWidgets('$kind — 배율 ${c.label} 에서 이름 상자 = 같은 배율 일반 Text', (
        tester,
      ) async {
        final violations = await collectWidgetSpanScaleViolations(
          tester,
          buildValue: (style) => buildUnlinkableLinkedAccountsValue(
            entries: entries,
            none: ko.authAccountLinkedAccountsNone,
            valueStyle: style,
            canUnlink: unlinkableIds.contains,
            onUnlinkTap: (_, _) {},
            l10n: ko,
          ),
          tagsByName: <String, String>{
            for (final (i, entry) in entries.indexed)
              if (unlinkableIds.contains(entry.id) == isUnlinkable)
                shownName(i): tag,
          },
          caseLabel: c.label,
          textScaler: c.scaler,
        );
        // fixture 확인 — 마지막으로 그린 값에 해제 버튼이 3개여야 한다.
        final buttons = find
            .descendant(
              of: find.byKey(kWidgetSpanValueKey),
              matching: find.byType(InkWell),
            )
            .evaluate()
            .length;
        if (buttons != unlinkableIds.length) {
          violations.add('[count] case=${c.label} buttons=$buttons');
        }
        expect(violations, isEmpty, reason: violations.join('\n'));
      });
    }
  }
}
