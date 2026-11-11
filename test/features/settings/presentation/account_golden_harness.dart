// 계정 화면 golden 공용 harness — pump · fixture · 끝까지 스크롤 · 계정 연결
// golden 칸.
//
// `account_screen_golden_test.dart` 의 private 함수를 옮겼다. 본문은 그대로이고
// 이름만 public 으로 바꿨다 — 옮긴 뒤에도 계정 화면 golden 은 byte 불변이어야
// 한다.
//
// **캡처 계약:** `settings_golden_harness.dart` 와 같다 — 280×800 logical ·
// DPR 3 · 빈 `Scaffold` 위 `MaterialPageRoute` push 진입 · production 폰트
// FontLoader + `assets/test_fonts` Noto Sans CJK subset ·
// `find.byType(MaterialApp)` 전체 캡처. 이 파일을 쓰는 시험은 `setUpAll` 에서
// [loadGoldenFonts] 를 부른다.
//
// 파일명이 `_test.dart` 가 아니라 테스트 러너가 단독 실행하지 않는다.

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/providers/locale_provider.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/settings/presentation/account_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'settings_golden_harness.dart';

/// [AuthRepository] 대체 Mock — 계정 화면 렌더 · 다이얼로그 열기는 repository
/// 를 호출하지 않으므로 stub 을 두지 않는다.
class GoldenMockAuthRepository extends Mock implements AuthRepository {}

/// 정식(비익명) Firebase 사용자 — UI-SPEC §Golden 캡처 계약 「정식 =
/// `isAnonymous: false` mock」.
class GoldenMockFbUser extends Mock implements fb.User {}

/// Phase 16.8 W5 — 가입 naver + 연결 5 (도달 가능 최악 · UI-SPEC §Golden
/// 캡처 계약 fixture verbatim 순서).
const List<String> kGoldenW5ProviderIds = <String>[
  'google.com',
  'apple.com',
  'facebook.com',
  'kakao',
  'line',
  'naver',
];

/// 보유 provider 7종 전부 — UI-SPEC fixture 표 verbatim 순서.
const List<String> kGoldenAllProviderIds = <String>[
  'google.com',
  'apple.com',
  'facebook.com',
  'kakao',
  'naver',
  'line',
  'password',
];

/// locale 별 표시 이름 — UI-SPEC fixture 표 (합성 값 · PII 0).
const Map<String, String> kGoldenDisplayNames = <String, String>{
  'ko': '홍길동',
  'en': 'Jane Doe',
  'ja': '山田太郎',
};

/// Phase 17.1 계정 화면 worst fixture 의 긴 이메일 — 합성 값 · PII 0
/// (mockup harness `_longEmail` verbatim · UI-SPEC §Golden 캡처 계약).
const String kGoldenLongEmail = 'gildong.hong.starterkit.test@example-mail.com';

/// 계정 연결 golden 칸 「미연결 6」 의 보유 provider — 이메일로 가입해 소셜
/// 연결이 하나도 없다(가입 수단 `password`).
const List<String> kAccountLinkingUnlinkedSixProviderIds = <String>['password'];

/// 계정 연결 golden 칸 「미연결 3」 의 보유 provider — 가입 kakao + 연결 naver ·
/// line 이라 Google · Apple · Facebook 이 미연결이다(가입 수단 `kakao`).
const List<String> kAccountLinkingUnlinkedThreeProviderIds = <String>[
  'kakao',
  'naver',
  'line',
];

/// UI-SPEC fixture — 가입 수단 [signUpProviderId](null = D-11 기록 없음) ·
/// 보유 provider [providerIds] (기본 7종 · Phase 16.8 golden 은
/// [kGoldenW5ProviderIds]) · 이메일 [email] (기본 `me@example.com` · 17.1
/// worst 는 [kGoldenLongEmail]).
User buildFixtureUser(
  String lang, {
  required String? signUpProviderId,
  List<String> providerIds = kGoldenAllProviderIds,
  String email = 'me@example.com',
}) {
  return User(
    uid: 'Xy7Qa2Lm9Rt4Wz8Kp1Nc5Vb3Hd6',
    email: email,
    emailVerified: true,
    displayName: kGoldenDisplayNames[lang],
    // 가입일은 로컬 DateTime — 계정 화면 formatYMD 가 toLocal() 로 그려 UTC 정오면
    // UTC+12 이상에서 이튿날로 찍힌다(변환은 test/core/l10n/intl_extensions_test.dart 몫).
    createdAt: DateTime(2026, 9, 26, 12),
    providerIds: providerIds,
    signUpProviderId: signUpProviderId,
  );
}

/// 사진 출처 stream fixture — 업로드 사진 없음 (UI-SPEC §Golden 캡처 계약 ·
/// 채택안 조건 「사진 없음」).
const UserProviderRecord kGoldenNoPhotoRecord = (
  linkedProviderIds: <String>[],
  signUpProviderId: null,
  customPhotoUrl: null,
);

/// 빈 [Scaffold] 위에 production [AccountScreen] 을 push 해 [width]×800 ·
/// DPR 3 viewport 에 올린다 ([pumpGoldenRoute] 위임).
///
/// override = repository mock · 활성 strategy 6 · 정식 authState(비익명) ·
/// 사용자 fixture · 사진 출처 stream(업로드 사진 없음).
///
/// [isLocalePinned] = true 면 `localeProvider` 도 [locale] 로 고정한다 —
/// production 은 `MaterialApp.locale` 과 가입일 형식이 같은 provider 를 보므로
/// Phase 17.1 계정 golden(채택 시안 harness `_overrides` 와 같은 조건)은 이
/// 값을 켠다. 기본 false 는 Phase 16.10 해제 다이얼로그 golden 4장(barrier 뒤
/// 가입일이 기기 기본 locale 형식)의 byte 불변을 지키기 위한 것이다.
Future<void> pumpAccountScreen(
  WidgetTester tester, {
  required User user,
  required Locale locale,
  required Brightness brightness,
  required double width,
  bool isLocalePinned = false,
}) {
  final fbUser = GoldenMockFbUser();
  when(() => fbUser.isAnonymous).thenReturn(false);
  when(() => fbUser.uid).thenReturn(user.uid);
  return pumpGoldenRoute(
    tester,
    route: (_) => const AccountScreen(),
    overrides: [
      authRepositoryProvider.overrideWithValue(GoldenMockAuthRepository()),
      activeStrategiesProvider.overrideWithValue(kGoldenSixStrategies),
      authStateProvider.overrideWithValue(AsyncData(fbUser)),
      currentUserProvider.overrideWith((ref) => user),
      // 사진 행의 사진 출처 stream 을 data(업로드 사진 없음)로 고정한다 —
      // 네트워크 사진 비결정성 회피 · 미초기화 Firestore 무접촉.
      linkedProvidersStreamProvider(
        user.uid,
      ).overrideWith((ref) => Stream.value(kGoldenNoPhotoRecord)),
      if (isLocalePinned)
        localeProvider.overrideWithBuild((ref, notifier) => locale),
    ],
    locale: locale,
    brightness: brightness,
    width: width,
  );
}

/// 계정 화면 목록을 끝까지 내린다 — `ScrollPosition.jumpTo(maxScrollExtent)`.
///
/// 드래그(fling)는 ink · overscroll 흔적을 남겨 golden 이 비결정적이 되므로
/// 쓰지 않는다 (UI-SPEC §Golden 캡처 계약 「드래그 금지 — ink」). 계정 화면의
/// [Scrollable] 은 본문 [ListView] 하나뿐이다.
Future<void> jumpToEnd(WidgetTester tester) async {
  final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
  state.position.jumpTo(state.position.maxScrollExtent);
  await tester.pump();
}

/// 계정 연결 golden 칸 하나를 그린다 — 280 · ko · 끝까지 스크롤.
///
/// [unlinkedCount] 는 계정 연결 절의 미연결 provider 수로 6 또는 3 이다(그 밖은
/// [ArgumentError]). 6 = [kAccountLinkingUnlinkedSixProviderIds](가입
/// `password`), 3 = [kAccountLinkingUnlinkedThreeProviderIds](가입 `kakao`).
/// 사용자는 표시 이름 홍길동 · 이메일 `me@example.com` · 사진 없음이고
/// `localeProvider` 를 ko 로 고정한다. 스크롤 뒤 새로 보이는 로고 이미지까지
/// 디코딩해 프레임을 안정화한다.
Future<void> pumpAccountLinkingGoldenCell(
  WidgetTester tester, {
  required int unlinkedCount,
  required Brightness brightness,
}) async {
  final (signUpProviderId, providerIds) = switch (unlinkedCount) {
    6 => ('password', kAccountLinkingUnlinkedSixProviderIds),
    3 => ('kakao', kAccountLinkingUnlinkedThreeProviderIds),
    _ => throw ArgumentError.value(
      unlinkedCount,
      'unlinkedCount',
      '6 또는 3 이어야 한다',
    ),
  };
  await pumpAccountScreen(
    tester,
    user: buildFixtureUser(
      'ko',
      signUpProviderId: signUpProviderId,
      providerIds: providerIds,
    ),
    locale: const Locale('ko'),
    brightness: brightness,
    width: 280,
    isLocalePinned: true,
  );
  await jumpToEnd(tester);
  await settleGoldenAssets(tester);
}

/// 계정 연결 golden 칸의 golden 파일 경로를 돌려준다.
///
/// [unlinkedCount] 와 [brightness] 가 파일 이름에 들어간다 — golden 파일
/// 이름이 이 함수 하나에서 나온다.
String resolveAccountLinkingGoldenPath({
  required int unlinkedCount,
  required Brightness brightness,
}) {
  final mode = brightness.name;
  return 'goldens/account_linking_ko_280_unlinked${unlinkedCount}_$mode.png';
}

/// 계정 연결 golden 칸 4장(미연결 6 · 3 × 밝은 · 어두운)의 시험을 등록한다.
///
/// 각 시험은 [pumpAccountLinkingGoldenCell] 로 그리고 예외 0 을 확인한 뒤
/// [resolveAccountLinkingGoldenPath] 의 golden 과 견준다. 부르는 시험 파일은
/// `setUpAll` 에서 [loadGoldenFonts] 를 부른다.
void registerAccountLinkingGoldenTests() {
  for (final unlinkedCount in const <int>[6, 3]) {
    for (final brightness in Brightness.values) {
      final mode = brightness.name;
      testWidgets('T-25-GOLDEN: 계정 연결 ko 280 미연결 $unlinkedCount — $mode', (
        tester,
      ) async {
        await pumpAccountLinkingGoldenCell(
          tester,
          unlinkedCount: unlinkedCount,
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            resolveAccountLinkingGoldenPath(
              unlinkedCount: unlinkedCount,
              brightness: brightness,
            ),
          ),
        );
      });
    }
  }
}
