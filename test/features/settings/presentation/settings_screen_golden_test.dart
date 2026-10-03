// Phase 16.7 Plan 12 — 설정 화면 golden (R1) + 줄바꿈 단언 (D-07).
//
// 설정 「내 계정」 3행(이메일 · 가입 수단 · 연결된 계정)은 제목 한 줄 + 값
// 아래 줄로 분리된다 (B2 · D-02 개정 (R1)). 사용자 sign-off 채택안 PNG
// `mockups/adopted_settings_r1_ko_280_worst_{light,dark}.png` 와 production
// `SettingsScreen` golden(`goldens/settings_screen_ko_280_worst_{light,dark}.png`)
// 이 byte 동일해야 sign-off 가 golden 으로 이어진 증거가 된다 (UI-SPEC
// §Golden 캡처 계약 (R1)).
//
// **캡처 계약:** 280×800 logical · DPR 3 · 빈 `Scaffold` 위 `MaterialPageRoute`
// push 진입(AppBar back 화살표 포함) · production 폰트 FontLoader +
// `assets/test_fonts` Noto Sans CJK KR/JP subset · test 전용 ThemeData 에만
// `fontFamilyFallback` · `find.byType(MaterialApp)` 전체 캡처. worst case 는
// 연결 가능 provider 가 없어 「계정 연결」 section 이 숨는다. viewport 는
// `tester.view` 로 주입한다 (MediaQuery 동기화).
//
// **단언:** UI-SPEC 「(R1) 설정 쪽 단언 변경」 2 · 3 — 연결된 계정 값(subtitle
// 문단)의 라벨 내부 줄바꿈 0 · 줄은 쉼표 뒤에서만 바뀜 · 줄 수 = 항목 기준선
// 묶음 수(ko/en/ja × worst · D-11, §Surface S (R1) 실측 표).
//
// **fixture 갱신:** `fvm flutter test --update-goldens <this file>` 후 산출
// PNG 를 `cmp` 로 adopted 와 대조한다. 불일치면 adopted 를 덮어쓰지 말고
// 원인(구현 트리 · harness 조건 차이)을 먼저 찾는다.
//
// **Phase 16.8 (Plan 16.8-01 Task 2):** 설정 golden fixture = W5(가입 naver +
// 보유 6 — 도달 가능 최악)로 바꾸고 채택안 `mockups/adopted_settings_16_8_ko_280_
// worst_{light,dark}.png` 와 대조한다. 해제 확인 다이얼로그 golden 2장(ko 280 ·
// Facebook)은 같은 harness 에서 production 탭 경로(밑줄 이름 → 다이얼로그)로
// 열어 `adopted_unlink_dialog_ko_280_facebook_{light,dark}.png` 와 대조한다.
// D-13 — 해제 버튼 ≥ 24×24 dp · `labeledTapTargetGuideline` ·
// `textContrastGuideline` (Android 48dp guideline 은 inline 예외라 걸지 않는다 ·
// UI-SPEC Q6-A). 16.7 줄바꿈 단언 · 가입 수단 1줄 가드는 보유 7 fixture 그대로.
//
// **Phase 16.10 (Plan 16.10-08 Task 2):** 해제 다이얼로그 content 가 U′(본문 +
// 앱 연결 고지 + 재로그인 provider 로그인 안내)로 바뀌어(Q7-A) Facebook
// 다이얼로그 golden 은 반드시 바뀐다. 대조 채택안은 16.10
// `mockups/adopted_unlink_dialog_16_10_ko_280_{google,facebook}_{light,dark}.png`
// 로 바뀌고 Google 2장이 새로 생긴다 — 16.8 `adopted_unlink_dialog_ko_280_
// facebook_*` 는 이력으로 보존한다(덮어쓰기 0). 설정 화면 golden 은 byte 불변.
// 공용 harness(FontLoader · theme · settle · push 진입)는 같은 디렉터리의
// golden harness 파일로 승격했다(진행 화면 golden 과 공유).
//
// **Phase 17 (Plan 17-15 · 17-17):** 설정 화면에 알림 섹션(Q3-A) · 프로필 사진
// 행(Q2-A)이 들어가 설정 golden 2장이 바뀌고, 채택안
// `mockups/adopted_settings_17_ko_280_worst_{light,dark}.png`(사진 없음 · 알림
// 꺼짐)와 byte 동일해야 한다. 해제 다이얼로그 golden 4장은 barrier 너머 설정
// 배경만 바뀐다(다이얼로그 surface 변경 0 · UI-SPEC 「2026-10-01 정정」).
//
// **Phase 17.1 (Plan 17.1-04 Task 3):** 게스트(익명) 설정 golden 2장
// `goldens/settings_171_guest_ko_280_{light,dark}.png`(테마 시스템 · ko ·
// non-release)이 채택안 `mockups/adopted_settings_guest_ko_280_{light,dark}.png`
// 와 byte 동일해야 한다 (D-23 · UI-SPEC Q9-A). 기존 설정 golden 은 byte 불변.
//
// **Phase 17.1 (Plan 17.1-06 Task 3):** 해제 버튼이 계정 정보 화면으로 옮겨 가
// (D-02) 해제 다이얼로그 golden 4장 · 버튼 크기 · a11y guideline · 연결된 계정
// 줄바꿈 · 가입 수단 값 가드 그룹을 `account_screen_golden_test.dart` 로
// 이전했다. 이 파일에는 설정 worst(T-17-PHOTO-08 — plan 09 가 대체) · 게스트
// golden 만 남는다.
//
// **Phase 17.1 (Plan 17.1-09 Task 1):** 설정 「내 계정」 사본이 지워지고(D-02 ·
// copy → move 완료) 정식 설정이 계정 행 · 일반 · 알림 · 개발자 목록이 되어,
// worst 2장(`settings_screen_ko_280_worst_*`)을 정식 golden
// `goldens/settings_171_member_ko_280_{light,dark}.png`(T-171-SETTINGS-golden-member
// · W5 · 사진 없음 · 알림 꺼짐 · 테마 시스템)로 대체했다. 채택안
// `mockups/adopted_settings_member_ko_280_{light,dark}.png` 와 byte 동일해야
// 한다 (D-23 · UI-SPEC Q9-A). 게스트 golden 은 byte 불변.
//
// **Phase 17.1 (Plan 17.1-09 Task 2):** 테마 · 언어 선택창 golden 4장
// `goldens/settings_171_picker_{theme,language}_ko_280_{light,dark}.png` 은 정식
// 설정 화면에서 행을 탭하는 production 경로로 연다(T-171-SETTINGS-golden-picker).
// 채택안 `mockups/adopted_picker_{theme,language}_ko_280_{light,dark}.png` 와
// byte 동일해야 한다 — `ChoiceSheet` 의 `toggleable: true`(plan 04)가 렌더에
// 영향 0 이라는 증거이고, 언어 선택창은 ko fallback `[KR, JP]` 로 「日本語」 ·
// 「한국어」 를 함께 그린다.

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/providers/locale_provider.dart';
import 'package:flutter_starter_kit/core/providers/theme_provider.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/settings/presentation/settings_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'settings_golden_harness.dart';

/// [AuthRepository] 대체 Mock — 설정 화면 렌더는 repository 를 호출하지
/// 않으므로 stub 을 두지 않는다.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// 게스트(익명) Firebase 사용자 — 설정 화면 게스트 판정 입력 (Phase 17.1).
class _MockFbUser extends Mock implements fb.User {}

/// Phase 16.8 W5 — 가입 naver + 연결 5 (도달 가능 최악 · UI-SPEC §Golden
/// 캡처 계약 fixture verbatim 순서).
const List<String> _w5ProviderIds = <String>[
  'google.com',
  'apple.com',
  'facebook.com',
  'kakao',
  'line',
  'naver',
];

/// 보유 provider 7종 전부 — UI-SPEC fixture 표 verbatim 순서.
const List<String> _allProviderIds = <String>[
  'google.com',
  'apple.com',
  'facebook.com',
  'kakao',
  'naver',
  'line',
  'password',
];

/// locale 별 표시 이름 — UI-SPEC fixture 표 (합성 값 · PII 0).
const Map<String, String> _displayNames = <String, String>{
  'ko': '홍길동',
  'en': 'Jane Doe',
  'ja': '山田太郎',
};

/// UI-SPEC fixture — 가입 수단 [signUpProviderId](null = D-11 기록 없음) ·
/// 보유 provider [providerIds] (기본 7종 · Phase 16.8 golden 은 [_w5ProviderIds]).
User _fixtureUser(
  String lang, {
  required String? signUpProviderId,
  List<String> providerIds = _allProviderIds,
}) {
  return User(
    uid: 'Xy7Qa2Lm9Rt4Wz8Kp1Nc5Vb3Hd6',
    email: 'me@example.com',
    emailVerified: true,
    displayName: _displayNames[lang],
    createdAt: DateTime.utc(2026, 9, 26, 12),
    providerIds: providerIds,
    signUpProviderId: signUpProviderId,
  );
}

/// 정식(비익명) Firebase 사용자 mock — 설정 화면 게스트 판정 입력 (Phase 17.1).
_MockFbUser _memberAuthUser(String uid) {
  final member = _MockFbUser();
  when(() => member.isAnonymous).thenReturn(false);
  when(() => member.uid).thenReturn(uid);
  return member;
}

/// 빈 [Scaffold] 위에 production 정식 [SettingsScreen] 을 push 해 [width]×800 ·
/// DPR 3 viewport 에 올린다 ([pumpGoldenRoute] 위임).
///
/// override 는 UI-SPEC §Golden 캡처 계약 「설정 정식」 — repository mock · 활성
/// strategy 6 · 정식 `authStateProvider`(`isAnonymous` false) · 사용자 fixture ·
/// 테마 시스템 · 언어 [locale] 고정(알림 꺼짐은 harness 고정).
Future<void> _pumpMemberSettingsScreen(
  WidgetTester tester, {
  required User user,
  required Locale locale,
  required Brightness brightness,
  required double width,
}) {
  return pumpGoldenRoute(
    tester,
    route: (_) => const SettingsScreen(),
    overrides: [
      authRepositoryProvider.overrideWithValue(_MockAuthRepository()),
      activeStrategiesProvider.overrideWithValue(kGoldenSixStrategies),
      // 첫 프레임부터 정식 data — 설정 진입 전 authState 가 값을 가진 실 앱과
      // 같다.
      authStateProvider.overrideWithValue(AsyncData(_memberAuthUser(user.uid))),
      currentUserProvider.overrideWith((ref) => user),
      // 결정성 — 테마 값 「시스템」 · 언어 값은 [locale] 의 endonym.
      themeProvider.overrideWithBuild((ref, notifier) => ThemeMode.system),
      localeProvider.overrideWithBuild((ref, notifier) => locale),
    ],
    locale: locale,
    brightness: brightness,
    width: width,
  );
}

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
  });

  // Phase 17.1 D-23 · UI-SPEC Q9-A — 정식 설정 golden 2장이 채택안
  // `mockups/adopted_settings_member_ko_280_{light,dark}.png` 와 byte 동일하다는
  // 계약 이름이다(대조 = plan 17.1-09 Task 1 `cmp` · 채택안 파일은 test 에서
  // 읽지 않는다). 옛 T-17-PHOTO-08 worst 2장(`settings_screen_ko_280_worst_*`)을
  // 대체한다 — 「내 계정」 상세가 계정 화면으로 옮겨 갔다(D-02).
  group('Phase 17.1 설정 정식 golden (T-171-SETTINGS-golden-member) — W5 · '
      '사진 없음 · 알림 꺼짐 · 테마 시스템 · ko 280×800 · non-release', () {
    for (final brightness in Brightness.values) {
      final mode = brightness.name;

      testWidgets('T-171-SETTINGS-golden-member: ko 280 — $mode', (
        tester,
      ) async {
        await _pumpMemberSettingsScreen(
          tester,
          user: _fixtureUser(
            'ko',
            signUpProviderId: 'naver',
            providerIds: _w5ProviderIds,
          ),
          locale: const Locale('ko'),
          brightness: brightness,
          width: 280,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'layout 예외 0 이어야 golden 이 시각 계약을 대표한다',
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/settings_171_member_ko_280_$mode.png'),
        );
      });
    }
  });

  // Phase 17.1 D-23 · UI-SPEC Q9-A — 게스트 설정 golden 2장이 채택안
  // `mockups/adopted_settings_guest_ko_280_{light,dark}.png` 와 byte 동일하다는
  // 계약 이름이다(대조 = plan 17.1-04 Task 3 `cmp` · 채택안 파일은 test 에서
  // 읽지 않는다).
  group('Phase 17.1 설정 게스트 golden (T-171-SETTINGS-golden-guest) — 익명 · '
      '테마 시스템 · ko 280×800 · non-release', () {
    for (final brightness in Brightness.values) {
      final mode = brightness.name;

      testWidgets('T-171-SETTINGS-golden-guest: ko 280 — $mode', (
        tester,
      ) async {
        final anon = _MockFbUser();
        when(() => anon.isAnonymous).thenReturn(true);
        when(() => anon.uid).thenReturn('anon-uid');
        await pumpGoldenRoute(
          tester,
          route: (_) => const SettingsScreen(),
          overrides: [
            authRepositoryProvider.overrideWithValue(_MockAuthRepository()),
            activeStrategiesProvider.overrideWithValue(kGoldenSixStrategies),
            // 첫 프레임부터 익명 data — 설정 진입 전 authState 가 값을 가진
            // 실 앱과 같다.
            authStateProvider.overrideWithValue(AsyncData(anon)),
            currentUserProvider.overrideWith((ref) => null),
            // 결정성 — 테마 값 「시스템」(UI-SPEC §Golden 캡처 계약 허용) ·
            // 언어 값 「한국어」.
            themeProvider.overrideWithBuild(
              (ref, notifier) => ThemeMode.system,
            ),
            localeProvider.overrideWithBuild(
              (ref, notifier) => const Locale('ko'),
            ),
          ],
          locale: const Locale('ko'),
          brightness: brightness,
          width: 280,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'layout 예외 0 이어야 golden 이 시각 계약을 대표한다',
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/settings_171_guest_ko_280_$mode.png'),
        );
      });
    }
  });

  // Phase 17.1 D-23 · UI-SPEC Q9-A — 선택창 golden 4장이 채택안
  // `mockups/adopted_picker_{theme,language}_ko_280_{light,dark}.png` 와 byte
  // 동일하다는 계약 이름이다(대조 = plan 17.1-09 Task 2 `cmp`).
  group('Phase 17.1 선택창 golden (T-171-SETTINGS-golden-picker) — 정식 설정에서 '
      '행 탭 · W5 · 테마 시스템 · ko 280×800', () {
    final ko = lookupAppLocalizations(const Locale('ko'));

    for (final (which, rowLabel) in <(String, String)>[
      ('theme', ko.settingsTheme),
      ('language', ko.settingsLanguage),
    ]) {
      for (final brightness in Brightness.values) {
        final mode = brightness.name;

        testWidgets('T-171-SETTINGS-golden-picker: $which ko 280 — $mode', (
          tester,
        ) async {
          await _pumpMemberSettingsScreen(
            tester,
            user: _fixtureUser(
              'ko',
              signUpProviderId: 'naver',
              providerIds: _w5ProviderIds,
            ),
            locale: const Locale('ko'),
            brightness: brightness,
            width: 280,
          );
          // production 탭 경로 — 설정 행을 눌러 선택창을 연다.
          await tester.tap(find.text(rowLabel));
          await settleGoldenAssets(tester);

          expect(find.byType(BottomSheet), findsOneWidget);
          if (which == 'language') {
            // 日本語 · 한국어 동시 렌더(한국어 = 행 값 + 시트 항목).
            expect(find.text('日本語'), findsOneWidget);
            expect(find.text('한국어'), findsNWidgets(2));
          }
          expect(
            tester.takeException(),
            isNull,
            reason: 'layout 예외 0 이어야 golden 이 시각 계약을 대표한다',
          );
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              'goldens/settings_171_picker_${which}_ko_280_$mode.png',
            ),
          );
        });
      }
    }
  });
}
