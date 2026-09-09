// Phase 16 IN-05 (4차 리뷰) — reauth 안내 ARB 키의 소비처 계약 sentinel.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `authReauthRequired` / `withdrawalReauthRequired` 의 소비처 분리를 소스
/// 수준에서 잠근다.
///
/// **왜 위젯 테스트로는 부족한가:** 두 키의 문구는 3 locale 모두 verbatim
/// 동일하다 ("For security, please sign in again and retry." 등). 따라서
/// `find.text(...)` 단언은 소비처가 `withdrawalReauthRequired` 로 되돌아가도
/// 그대로 GREEN 이다 — 3차 WR-04 / 4차 WR-05 fix 가 실제로는 잠기지 않았다는
/// 것이 IN-05 의 지적이었다. 문구가 아니라 **키 자체**를 단언해야 한다.
///
/// **계약 (en template description 이 진실원):**
/// - `withdrawalReauthRequired` — UI-SPEC Surface C (탈퇴 다이얼로그) 전용.
///   탈퇴 어휘로 특화해도 안전해야 하며, 그것이 키를 분리한 목적이다.
/// - `authReauthRequired` — 도메인 중립 공용 키. 소비처는
///   (1) Surface A 경로 A (AccountLinkingSheet),
///   (2) Surface D (AccountLinkingSection),
///   (3) `resolveExceptionMessage` 의 `errorReauthenticationRequired` arm.
///
/// 소비처가 늘어나면 본 목록과 en description 의 "소비:" 목록을 함께 갱신한다.
void main() {
  const withdrawalOnlyConsumer =
      'lib/features/settings/presentation/_widgets/'
      'withdrawal_confirmation_dialog.dart';
  const neutralKeyConsumers = <String>[
    'lib/features/auth/presentation/_widgets/account_linking_sheet.dart',
    'lib/features/settings/presentation/_widgets/account_linking_section.dart',
    'lib/core/l10n/exception_l10n.dart',
  ];

  /// [path] 의 소스에서 주석 줄을 제거한 실행 코드만 돌려준다.
  ///
  /// 세 파일 모두 "왜 이 키를 쓰는가" 를 주석으로 설명하면서 반대쪽 키 이름을
  /// 언급하므로, 주석을 걷어내지 않으면 미소비 단언이 항상 실패한다.
  String readCode(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path 부재');
    return file
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .where((line) => !line.trimLeft().startsWith('///'))
        .join('\n');
  }

  group('IN-05: reauth ARB 키의 소비처 분리 (문구가 아니라 키를 잠근다)', () {
    for (final path in neutralKeyConsumers) {
      test('${path.split('/').last} 는 authReauthRequired 만 소비한다', () {
        final code = readCode(path);
        expect(
          code,
          contains('authReauthRequired'),
          reason:
              '$path 가 도메인 중립 키 authReauthRequired 를 더 이상 쓰지 '
              '않는다. 3차 WR-04 / 4차 WR-05 회귀.',
        );
        expect(
          code,
          isNot(contains('l10n.withdrawalReauthRequired')),
          reason:
              '$path 가 탈퇴 전용 키 withdrawalReauthRequired 를 소비한다. '
              '그 키의 description 은 소비처를 Surface C 1곳으로 못 박고 '
              '있으므로, Surface C 문구를 탈퇴 어휘로 다듬는 순간 이 화면에 '
              '"탈퇴하려면…" 이 새어 나간다 (WR-04 가 막으려던 사고).',
        );
      });
    }

    test('Surface C (탈퇴 다이얼로그) 는 여전히 전용 키를 소비한다', () {
      // 반대 방향 잠금 — 공용 키로 뭉개면 두 키를 분리한 목적이 사라진다.
      final code = readCode(withdrawalOnlyConsumer);
      expect(code, contains('l10n.withdrawalReauthRequired'));
      expect(code, isNot(contains('l10n.authReauthRequired')));
    });
  });
}
