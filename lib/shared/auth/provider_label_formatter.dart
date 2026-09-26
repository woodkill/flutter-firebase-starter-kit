// Phase 13 — see ROADMAP.md (D-53 5 provider 일반화 + assert + Localizable Unknown)
// Phase 16.7 — 가입 수단 · 연결된 계정 표시 helper (D-04 · D-05 · D-11 · D-12)

import 'package:flutter/widgets.dart';

import '../../core/auth/provider_id.dart';
import '../../features/auth/domain/user.dart';
import '../../l10n/generated/app_localizations.dart';

/// [formatProviderLabels] 가 라벨로 변환하는 매핑 키 set.
///
/// Phase 7~9 의 4개 native URI + Phase 12 `kakao` slug + Phase 13 `naver` slug +
/// Phase 14 등재 (`line`) 까지 모두 컨트랙트로
/// 노출한다. 컨트랙트 테스트가 우선 실패하여 동시 갱신 의무를 강제한다.
///
/// **두 형식이 공존한다 (Phase 12 D-16 / D-17, Phase 13 D-53):**
///
/// - **Native 4 provider** (Email/Google/Apple/Facebook): Firebase Auth 가
///   `User.providerData[i].providerId` 로 자체 반환하는 OAuth URI 형식
///   (`'password'` / `'google.com'` / `'apple.com'` / `'facebook.com'`).
/// - **Custom Token provider** (Kakao/Naver/LINE): Firebase 가
///   URI 를 반환하지 않으므로 Firestore `users/{uid}.linkedProviders[].providerId`
///   의 도메인 slug ([kProviderIdKakao] 등) 를 직접 사용한다.
///
/// `currentUserProvider` 가 양쪽을 합산해 `User.providerIds` 에 채우므로
/// (Phase 12 D-16 합집합 정책) 본 매핑 set 과 switch 는 두 형식을 모두
/// 인식해야 한다 (라벨 매핑 책임은 본 모듈 단일 진실원 — URI → enum 변환은
/// [AccountProvider.tryParse], Phase 16.7).
const Set<String> kSupportedAuthProviderIds = <String>{
  // Native (URI 형식)
  'password',
  'google.com',
  'apple.com',
  'facebook.com',
  // Custom Token slug — Native URI 형식 미존재 (Phase 12 D-17 / Phase 13 D-53).
  kProviderIdKakao,
  kProviderIdNaver,
  kProviderIdLine,
};

/// `User.providerIds` 의 각 원소를 사용자 가독형 라벨로 변환한다
/// (D-11, D-17, D-53 · Phase 16.7 D-04 · D-27).
///
/// 본 함수의 switch 가 provider 라벨 매핑의 유일한 사이트다 — 순서는 입력
/// 그대로 보존하고 결합하지 않는다 (결합 · 줄바꿈 보호는 호출 쪽 책임).
///
/// - `'password'` -> [AppLocalizations.authAccountProviderEmailPassword]
/// - `'google.com'` -> [AppLocalizations.authAccountProviderGoogle]
/// - `'apple.com'` -> [AppLocalizations.authAccountProviderApple] (Phase 8)
/// - `'facebook.com'` -> [AppLocalizations.authAccountProviderFacebook] (Phase 9)
/// - [kProviderIdKakao] -> [AppLocalizations.authAccountProviderKakao] (Phase 12 D-17)
/// - [kProviderIdNaver] -> [AppLocalizations.authAccountProviderNaver] (Phase 13)
/// - [kProviderIdLine] -> [AppLocalizations.authAccountProviderLine] (Phase 14 pre-registered)
/// - 미지원 slug -> [AppLocalizations.errorUnknownProvider] (D-53 Localizable Unknown,
///   raw slug 노출 차단)
///
/// **D-53 contract drift 가드 (kDebugMode assert):** [kAllProviderIds] 의 모든
/// slug 가 본 switch 에 매핑되는지 검증. 신규 slug 가 kAllProviderIds 에
/// 추가되지만 본 switch 갱신을 누락하면 dev 빌드 fail.
List<String> formatProviderLabels(
  List<String> providerIds,
  AppLocalizations l10n,
) {
  // D-53 contract drift 방지 assert (kDebugMode 만).
  // kAllProviderIds 의 모든 slug 가 아래 switch 에 매핑되는지 검증한다.
  // 신규 slug 가 kAllProviderIds 에 추가되면 본 함수 갱신 의무를 강제
  // (dev 빌드 fail).
  assert(() {
    const knownIds = <String>{
      kProviderIdGoogle,
      kProviderIdApple,
      kProviderIdFacebook,
      kProviderIdKakao,
      kProviderIdNaver,
      kProviderIdLine,
    };
    final missing = kAllProviderIds
        .where((id) => !knownIds.contains(id))
        .toList();
    if (missing.isNotEmpty) {
      throw StateError(
        'kAllProviderIds 중 매핑되지 않은 provider: $missing — '
        'provider_label_formatter switch 확장 필요 (D-53).',
      );
    }
    return true;
  }());

  return providerIds
      .map(
        (id) => switch (id) {
          // Native URI 형식
          'password' => l10n.authAccountProviderEmailPassword,
          'google.com' => l10n.authAccountProviderGoogle,
          'apple.com' => l10n.authAccountProviderApple,
          'facebook.com' => l10n.authAccountProviderFacebook,
          // Custom Token slug 형식 (D-17 / D-53)
          kProviderIdKakao => l10n.authAccountProviderKakao,
          kProviderIdNaver => l10n.authAccountProviderNaver,
          kProviderIdLine => l10n.authAccountProviderLine,
          // D-53 release fallback — Localizable Unknown (raw slug 노출 절대 금지).
          _ => l10n.errorUnknownProvider,
        },
      )
      .toList(growable: false);
}

/// `User.providerIds` 를 사용자 가독형 라벨 문자열로 변환한다 (D-11, D-17, D-53).
///
/// 각 원소의 라벨은 [formatProviderLabels] 가 만든다. 빈 리스트이면 `'-'`.
/// 다중 provider 는 `, ` 로 결합한다.
String formatProviderIds(List<String> providerIds, AppLocalizations l10n) {
  final labels = formatProviderLabels(providerIds, l10n);
  return labels.isEmpty ? '-' : labels.join(', ');
}

/// [user] 의 provider 를 「가입 수단」 과 「연결된 계정」 으로 나눈다
/// (Phase 16.7 D-05 · D-06 · D-11 · D-12 — 두 표면 공통 규칙).
///
/// - 가입 수단 = `user.signUpProviderId` 그대로. null(기록 없음 · 게스트 ·
///   읽기 실패 · 첫 emit 전)이어도 `providerIds` 에서 추론하지 않는다 (D-11).
/// - 연결된 계정 = `providerIds` 에서 가입 수단과 같은 값만 뺀 나머지를
///   [orderForDisplay] 순서로. 가입 수단이 보유 목록에 없으면 보유 전부다
///   (D-12 — 가입 수단 값은 그대로 돌려준다).
/// - [user] 가 null 이면 `(null, [])`. 0개 표시(「없음」)는 호출 쪽이
///   `authAccountLinkedAccountsNone` 으로 만든다 (D-03).
({String? signUpProviderId, List<String> linkedProviderIds})
splitAccountProviders(User? user) {
  final signUp = user?.signUpProviderId;
  final ids = user?.providerIds ?? const <String>[];
  return (
    signUpProviderId: signUp,
    linkedProviderIds: orderForDisplay(ids.where((id) => id != signUp)),
  );
}

/// [providerIds] 를 표시 순서로 정렬한 새 리스트를 돌려준다 (Phase 16.7 D-05).
///
/// 순서 = [kAllProviderIds] 순 소셜 → 미지 값 → 이메일(`'password'`) 맨 끝.
/// native URI 와 Custom Token slug 가 섞여 있어도 [AccountProvider.tryParse]
/// 로 같은 rank 를 매긴다. rank 가 같은 원소(미지 값 여러 개)는 입력 순서를
/// 유지하는 안정 정렬이다 (RESEARCH A2).
List<String> orderForDisplay(Iterable<String> providerIds) {
  // List.sort 는 안정 정렬을 보장하지 않으므로 원래 index 로 tie-break 한다.
  final indexed = providerIds.toList().indexed.toList()
    ..sort((a, b) {
      final byRank = _rankForDisplay(a.$2).compareTo(_rankForDisplay(b.$2));
      return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
    });
  return indexed.map((entry) => entry.$2).toList(growable: false);
}

/// [orderForDisplay] 의 정렬 rank — 소셜은 [kAllProviderIds] 의 index,
/// 미지 값은 그 뒤, 이메일은 맨 끝.
int _rankForDisplay(String providerId) {
  final unknownRank = kAllProviderIds.length;
  final provider = AccountProvider.tryParse(providerId);
  if (provider == null) return unknownRank;
  if (provider == AccountProvider.email) return unknownRank + 1;
  final index = kAllProviderIds.indexOf(provider.slug);
  // enum 에는 있으나 등록 목록에 없는 값은 미지 값과 같은 자리로 둔다.
  return index < 0 ? unknownRank : index;
}

/// 「연결된 계정」 값의 표시 span 과 스크린 리더 문자열을 만든다
/// (Phase 16.7 D-04 보강 · UI-SPEC §Line-break Mechanism (c)).
///
/// - [labels] 가 비어 있으면 `TextSpan(text: none)` + semantics [none] —
///   호출 쪽이 `authAccountLinkedAccountsNone` 을 [none] 으로 넘긴다 (D-03).
/// - 아니면 라벨마다 기준선 정렬 `WidgetSpan` 하나(마지막 외에는 `'라벨,'`)와
///   그 사이 `TextSpan(text: ' ')` — 줄바꿈은 라벨 사이 공백에서만 일어나고
///   provider 이름 내부에서는 끊기지 않는다.
/// - semantics 는 `labels.join(', ')` 로 따로 만든다 — 표시 span 의
///   자리표시 문자가 낭독 문자열에 섞이지 않는다.
///
/// `Text.rich` 생성과 `semanticsLabel` 지정은 호출 쪽(홈 카드 · 설정 행)
/// 책임이다. [style] 은 바깥 `Text.rich` 와 같은 style 을 넘긴다.
({InlineSpan display, String semantics}) buildLinkedAccountsValue(
  List<String> labels, {
  required String none,
  TextStyle? style,
}) {
  if (labels.isEmpty) {
    return (display: TextSpan(text: none), semantics: none);
  }
  final lastIndex = labels.length - 1;
  return (
    display: TextSpan(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Text(
              i < lastIndex ? '${labels[i]},' : labels[i],
              style: style,
            ),
          ),
          if (i < lastIndex) const TextSpan(text: ' '),
        ],
      ],
    ),
    semantics: labels.join(', '),
  );
}
