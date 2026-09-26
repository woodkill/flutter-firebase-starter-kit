// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-06 Task 6.2 — SettingsScreen widget test (SS1~SS4).
// Phase 16 Plan 16-11 Task 2 — AccountLinkingSection 삽입 + 회귀 가드 (SS5~SS9).
// Phase 16 Plan 16-16 Task 1 — 3버튼 내비(48dp) inset 회귀 가드 (SS10).
// Phase 16.7 Plan 16.7-05 Task 2 — 내 계정 2행(가입 수단 · 연결된 계정) SS4 재작성
//   + 16.7-S01~S06.
// Phase 16.7 Plan 16.7-11 Task 1 — R1 제목/값 분리(ListTile title/subtitle) 로
//   SS4 · 16.7-S01~S06 재작성.
//
// 검증:
// - SS1 render 정상: AppBar title "Settings" + 계정 section + Danger
//   zone section + 회원탈퇴 ListTile.
// - SS2 Danger zone destructive color: 회원탈퇴 ListTile title color ==
//   Theme.colorScheme.error.
// - SS3 tap → dialog: 회원탈퇴 tap 시 WithdrawalConfirmationDialog 노출.
// - SS4 빈 provider fallback: providerIds==[] · 기록 null 시 가입 수단 행 값 "-" ·
//   연결된 계정 행 값 "None" — 각 행 제목은 따로 한 줄 (Phase 16.7 R1 재작성).
// - SS5 AccountLinkingSection 노출: settingsAccountLinkingSection heading +
//   AccountLinkingSection 위젯 (계정 section 다음, Danger zone 전).
// - SS6 회귀 0: 계정 section (이메일 · 가입 수단 · 연결된 계정 3행) + Danger zone
//   모두 노출.
// - SS7 배치 순서: 계정 section → AccountLinkingSection → DangerZoneSection.
// - SS8 viewport: 360dp ListView scroll — Danger zone (말단) ensureVisible.
// - SS9 모든 소셜 linked: AccountLinkingSection 미노출 + Danger zone 회귀 0.
// - SS10 3버튼 내비(48dp) system inset: ListView 를 끝까지 스크롤해도 회원탈퇴
//   ListTile 이 hit-test 가능하고, 그 bottom 이 `화면 높이 - inset` 이하에
//   머무른다 (G-16-A6-1 회귀 가드 — `3674ec3` 의 SafeArea 를 지킨다).
// - SS11 section heading role·색: "My Account" / "Danger zone" heading 이
//   Theme.textTheme 의 label 계열 role 과 동일 metric 이고 색은 각각
//   onSurfaceVariant / error (UI-REVIEW Top 3 #2·#3).
// - SS12 Danger zone explainer role + chevron 색: explainer 가 body 계열
//   role metric, trailing chevron 이 accent, leading icon·title 은 error 불변.
// - SS13 Danger zone Semantics: 회원탈퇴 ListTile 이 button + 결합 라벨 노출.
// - SS14 계정 연결 heading role·색: "Link an account" heading 이 label 계열
//   role metric + onSurfaceVariant.
// - 16.7-S01 3행 제목/값 semantics — ListTile 병합 label = '제목\n값' (D-02 R1 · D-09).
// - 16.7-S02 연결 0개 — 연결 행 값 「None」 · WidgetSpan 0 (D-03).
// - 16.7-S03 기록 null — 가입 수단 값 「-」 · 연결 = 보유 전부 고정 순서 (D-11 · D-05).
// - 16.7-S04 연결 행 semantics 무오염 — 보이지 않는 문자 6종 0.
// - 16.7-S05 R1 계약 — 제목 bodySmall + onSurfaceVariant · 값 titleMedium ·
//   행별 maxLines/overflow · ListTile SDK 기본(세 줄 · tile 스타일 · dense ·
//   padding 미지정).
// - 16.7-S06 280dp viewport overflow 0.
//
// 동일 패턴 audit (G-16-A6-1 missing 2번째 항목 — 2026-09-07 실행):
//
// 재실행 명령 (Task 1 verify 와 동일):
//   SCREENS=$(git ls-files 'lib/**/*_screen.dart'); for f in $SCREENS; do \
//     if grep -qE 'ListView|SingleChildScrollView|CustomScrollView|GridView' "$f" \
//     && ! grep -q 'SafeArea' "$f" && ! grep -q 'paddingOf(context).bottom' "$f" \
//     && ! grep -q 'AuthScaffold' "$f"; then echo "UNGUARDED: $f"; fi; done; echo AUDIT_DONE
//
// 결과: `UNGUARDED:` 0건 (AUDIT_DONE). 스크롤 말단에 상호작용 요소를 두는 화면
// 중 하단 system inset 미반영 화면은 없다.
//
// | 화면 파일 | 스크롤 보유 | 하단 inset 반영 방식 | 판정 |
// |---|---|---|---|
// | `settings/presentation/settings_screen.dart` | ListView | `SafeArea` 직접 (`3674ec3`) | GUARDED — 본 SS10 이 회귀 잠금 |
// | `terms/presentation/terms_detail_screen.dart` | SingleChildScrollView | `SafeArea` 직접 | GUARDED |
// | `onboarding/presentation/onboarding_screen.dart` | SingleChildScrollView | `SafeArea` 직접 | GUARDED |
// | `home/presentation/environment_info_screen.dart` | ListView | ListView padding 에 `MediaQuery.paddingOf(context).bottom` 가산 | GUARDED — 대체 방식 (동일 결함 없음) |
// | `auth/presentation/login_screen.dart` | 화면 파일에는 없음 | `AuthScaffold` 위임 (`auth_scaffold.dart:36` `body: SafeArea(child: SingleChildScrollView)`) | GUARDED — 위임 (오탐 아님) |
// | `auth/presentation/signup_screen.dart` | 화면 파일에는 없음 | `AuthScaffold` 위임 | GUARDED — 위임 |
// | `auth/presentation/forgot_password_screen.dart` | 화면 파일에는 없음 | `AuthScaffold` 위임 | GUARDED — 위임 |
// | `auth/presentation/verify_email_screen.dart` | 화면 파일에는 없음 | `AuthScaffold` 위임 | GUARDED — 위임 |
// | `splash/presentation/splash_screen.dart` | 없음 (스크롤 없음) | `SafeArea` 직접 | 해당 없음 |
//
// 시트 2종(`account_linking_sheet.dart` / `login_prompt_sheet.dart`) 도 각각
// `SafeArea` 를 직접 적용한다 (audit 명령의 `*_screen.dart` 범위 밖이므로 별도 확인).
// → 신규 누락(UNGUARDED) 0건이므로 본 task 는 `lib/**/*_screen.dart` 를 수정하지 않는다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/kakao_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/line_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/naver_auth_strategy.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/account_linking_section.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/danger_zone_section.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/withdrawal_confirmation_dialog.dart';
import 'package:flutter_starter_kit/features/settings/presentation/settings_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// 활성 소셜 Strategy 6종 전부.
const List<AuthStrategy> _allStrategies = <AuthStrategy>[
  GoogleAuthStrategy(),
  AppleAuthStrategy(),
  FacebookAuthStrategy(),
  KakaoAuthStrategy(),
  NaverAuthStrategy(),
  LineAuthStrategy(),
];

/// 모든 활성 소셜 provider 가 이미 linked 인 User (계정 연결 section 미노출
/// 상태) — Danger zone 회귀 검증을 baseline ListView 길이로 유지한다.
List<String> get _allSocialLinked => const <String>[
  'password',
  'google.com',
  'apple.com',
  'facebook.com',
  'kakao',
  'naver',
  'line',
];

/// 테스트용 User factory.
User _testUser({
  List<String> providerIds = const <String>['password'],
  String email = 'me@example.com',
  String? signUpProviderId,
}) {
  return User(
    uid: 'uid-1',
    email: email,
    emailVerified: true,
    createdAt: DateTime.utc(2026, 1, 1),
    providerIds: providerIds,
    signUpProviderId: signUpProviderId,
  );
}

/// 「연결된 계정」 행 `ListTile` finder — leading `Icons.link` 의 조상.
Finder _findLinkedAccountsTile() =>
    find.ancestor(of: find.byIcon(Icons.link), matching: find.byType(ListTile));

/// 「가입 수단」 행 `ListTile` finder — leading `Icons.how_to_reg` 의 조상.
Finder _findSignUpMethodTile() => find.ancestor(
  of: find.byIcon(Icons.how_to_reg),
  matching: find.byType(ListTile),
);

/// 「이메일」 행 `ListTile` finder — leading `Icons.alternate_email` 의 조상.
Finder _findEmailTile() => find.ancestor(
  of: find.byIcon(Icons.alternate_email),
  matching: find.byType(ListTile),
);

/// 「연결된 계정」 행 값(subtitle) `Text.rich` 위젯.
Text _readLinkedAccountsValue(WidgetTester tester) =>
    tester.widget<ListTile>(_findLinkedAccountsTile()).subtitle! as Text;

/// 「연결된 계정」 행 값의 [WidgetSpan] 수 (provider 라벨 1개 = 1개).
int _countLinkedWidgetSpans(WidgetTester tester) {
  var count = 0;
  _readLinkedAccountsValue(tester).textSpan!.visitChildren((span) {
    if (span is WidgetSpan) count++;
    return true;
  });
  return count;
}

/// 표시 span 이 낭독 문자열에 새면 나타나는 문자 — 자리표시(U+FFFC) ·
/// WORD JOINER(U+2060) · NBSP(U+00A0) · ZWSP(U+200B) · BOM(U+FEFF) ·
/// 사용자 영역 첫 문자(U+E000). 소스에 보이지 않는 문자가 저장되지 않도록
/// code point 로 만든다.
final List<String> _kInvisibleChars = <String>[
  String.fromCharCode(0xFFFC),
  String.fromCharCode(0x2060),
  String.fromCharCode(0x00A0),
  String.fromCharCode(0x200B),
  String.fromCharCode(0xFEFF),
  String.fromCharCode(0xE000),
];

/// 7종 provider 전부 보유 (Phase 16.7 D-11 fallback · 280dp 최악 케이스).
const List<String> _kAllProviderIdsHeld = <String>[
  'password',
  'line',
  'naver',
  'kakao',
  'facebook.com',
  'apple.com',
  'google.com',
];

Future<void> _pumpSettingsScreen(
  WidgetTester tester, {
  required User? user,
  Locale locale = const Locale('en'),
  List<AuthStrategy> strategies = _allStrategies,
}) async {
  // 280dp 이상 (PROJECT.md mobile 반응형) — default 800x600 사용.
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => user),
        // 활성 Strategy 직접 주입 — AccountLinkingSection available 계산 결정성.
        activeStrategiesProvider.overrideWith((ref) => strategies),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Phase 16 D-05~D-08 — SettingsScreen', () {
    testWidgets(
      'SS1 render — AppBar title + 계정 section + Danger zone section 노출',
      (tester) async {
        // 소셜 전부 linked → 계정 연결 section 미노출 → baseline ListView 길이.
        await _pumpSettingsScreen(
          tester,
          user: _testUser(providerIds: _allSocialLinked),
        );

        // AppBar title (en locale).
        expect(find.text('Settings'), findsOneWidget);
        // 계정 section heading.
        expect(find.text('My Account'), findsOneWidget);
        // 이메일 ListTile (placeholder 채워진 형태).
        expect(find.textContaining('me@example.com'), findsOneWidget);
        // Danger zone section heading.
        expect(find.text('Danger zone'), findsOneWidget);
        // Danger zone explainer.
        expect(find.text('These actions cannot be undone.'), findsOneWidget);
        // 회원탈퇴 ListTile.
        expect(find.text('Delete account'), findsAtLeast(1));
      },
    );

    testWidgets(
      'SS2 Danger zone destructive color — 회원탈퇴 title color == error',
      (tester) async {
        await _pumpSettingsScreen(
          tester,
          user: _testUser(providerIds: _allSocialLinked),
        );

        final dangerTile = tester.widget<ListTile>(
          find.ancestor(
            of: find.text('Delete account').last,
            matching: find.byType(ListTile),
          ),
        );
        final titleText = dangerTile.title! as Text;
        final theme = Theme.of(tester.element(find.byType(SettingsScreen)));
        expect(titleText.style?.color, equals(theme.colorScheme.error));
      },
    );

    testWidgets(
      'SS3 tap → dialog — 회원탈퇴 ListTile tap 시 WithdrawalConfirmationDialog 노출',
      (tester) async {
        await _pumpSettingsScreen(
          tester,
          user: _testUser(providerIds: _allSocialLinked),
        );

        expect(find.byType(WithdrawalConfirmationDialog), findsNothing);

        await tester.ensureVisible(find.text('Delete account').last);
        await tester.tap(find.text('Delete account').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(WithdrawalConfirmationDialog), findsOneWidget);
      },
    );

    testWidgets(
      'SS4 빈 provider fallback — 가입 수단 값 "-" · 연결된 계정 값 "None" (16.7 R1 재작성)',
      (tester) async {
        await _pumpSettingsScreen(
          tester,
          user: _testUser(providerIds: const <String>[]),
        );

        // 기록 null → formatProviderIds([]) '-' (D-11). 연결 0개는 「None」
        // 일반 TextSpan (D-03). 짧은 값은 다른 위젯과 겹칠 수 있어 tile 로 좁힌다.
        expect(
          find.descendant(
            of: _findSignUpMethodTile(),
            matching: find.text('-'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _findLinkedAccountsTile(),
            matching: find.text('None'),
          ),
          findsOneWidget,
        );
        // 제목은 값과 다른 줄 — 홈 카드 라벨 키 재사용 (D-09).
        expect(find.text('Email'), findsOneWidget);
        expect(find.text('Sign-up method'), findsOneWidget);
        expect(find.text('Linked accounts'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('SS5 AccountLinkingSection 노출 — heading + 위젯 (계정 section 다음)', (
      tester,
    ) async {
      // linked=[password] (email native) → 소셜 0 linked → 활성 소셜 6 노출.
      await _pumpSettingsScreen(tester, user: _testUser());

      // 계정 연결 section heading (en) + 위젯.
      expect(find.text('Link an account'), findsOneWidget);
      expect(find.byType(AccountLinkingSection), findsOneWidget);
      // 소셜 연결 버튼 (예: Apple) 노출.
      expect(find.text('Link Apple'), findsOneWidget);
    });

    testWidgets(
      'SS6 회귀 0 — 계정 section + Danger zone 모두 노출 (AccountLinkingSection 공존)',
      (tester) async {
        // 단일 활성 Strategy (apple) → section 1 버튼 → ListView baseline 길이
        // 내 Danger zone 공존.
        await _pumpSettingsScreen(
          tester,
          user: _testUser(),
          strategies: const <AuthStrategy>[AppleAuthStrategy()],
        );

        // 계정 section (회귀 0).
        expect(find.text('My Account'), findsOneWidget);
        expect(find.textContaining('me@example.com'), findsOneWidget);
        // 계정 연결 section 공존.
        expect(find.byType(AccountLinkingSection), findsOneWidget);
        expect(find.text('Link Apple'), findsOneWidget);
        // Danger zone (회귀 0).
        expect(find.byType(DangerZoneSection), findsOneWidget);
        expect(find.text('Danger zone'), findsOneWidget);
      },
    );

    testWidgets(
      'SS7 배치 순서 — 계정 section → AccountLinkingSection → DangerZoneSection',
      (tester) async {
        // 단일 활성 Strategy → 3 section 모두 viewport 내 동시 측정 가능.
        await _pumpSettingsScreen(
          tester,
          user: _testUser(),
          strategies: const <AuthStrategy>[AppleAuthStrategy()],
        );

        final accountY = tester.getTopLeft(find.text('My Account')).dy;
        final linkingY = tester.getTopLeft(find.text('Link an account')).dy;
        final dangerY = tester.getTopLeft(find.byType(DangerZoneSection)).dy;

        // 계정 section < 계정 연결 < Danger zone (mockup 배치 verbatim).
        expect(accountY, lessThan(linkingY));
        expect(linkingY, lessThan(dangerY));
      },
    );

    testWidgets(
      'SS8 viewport — 360dp ListView scroll, Danger zone (말단) 접근 가능',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // 단일 활성 Strategy → Danger zone 이 below-fold 여도 scroll 접근 가능.
        await _pumpSettingsScreen(
          tester,
          user: _testUser(),
          strategies: const <AuthStrategy>[AppleAuthStrategy()],
        );

        // Danger zone 회원탈퇴 ListTile 이 below-fold 여도 scroll 후 접근 가능.
        await tester.ensureVisible(find.text('Delete account').last);
        expect(find.byType(DangerZoneSection), findsOneWidget);
      },
    );

    testWidgets('SS10 3버튼 내비 48dp viewPadding — 회원탈퇴 ListTile hit-test 가능 + '
        'SafeArea geometry 회귀 가드 (G-16-A6-1)', (tester) async {
      // 위젯 테스트 세계에는 시스템 내비게이션 바라는 실제 occluder 가 없다.
      // 따라서 `tester.tap` 만으로는 SafeArea 유무를 구분하지 못한다 —
      // SafeArea 를 제거해도 tap 은 그대로 통과한다. 구분 가능한 관측량은
      // geometry 다: SafeArea 가 있으면 끝까지 스크롤해도 마지막 항목의 bottom
      // 이 `화면 높이 − inset` 이하에 머무르고, 없으면 그 아래(= 실 단말에서
      // 3버튼 내비게이션 바에 가려지는 영역)로 내려간다. 아래 (b) 단언이 본
      // 테스트의 신호이며, (a)/(c) 는 진입 path 가 살아있음을 함께 잠근다.
      const double screenHeight = 640;
      const double bottomInset = 48; // 3버튼 내비게이션 상당.
      const double safeBottom = screenHeight - bottomInset; // 592.0

      tester.view.physicalSize = const Size(360, screenHeight);
      // 물리 픽셀 == dp — FakeViewPadding 값 단위가 물리 픽셀이므로 48 = 48dp.
      tester.view.devicePixelRatio = 1.0;
      // SafeArea 가 읽는 것은 MediaQuery.paddingOf 이므로 viewPadding 과
      // padding 을 **둘 다** 설정해야 inset 이 실제로 반영된다.
      tester.view.viewPadding = const FakeViewPadding(bottom: bottomInset);
      tester.view.padding = const FakeViewPadding(bottom: bottomInset);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);

      // 활성 소셜 6종 전부 미연결 → ListView 가 viewport 를 확실히 초과하여
      // "끝까지 스크롤한 상태" 가 성립한다 (geometry 단언의 전제).
      await _pumpSettingsScreen(tester, user: _testUser());

      // ensureVisible 은 "겨우 보이는" 위치에서 멈출 수 있어 geometry 단언이
      // 무의미해진다 — 충분히 큰 음수 offset 으로 끝까지 내린다.
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();

      final withdrawalTile = find
          .ancestor(
            of: find.text('Delete account').last,
            matching: find.byType(ListTile),
          )
          .hitTestable();

      // (a) hit-test 가능 — inset 아래에서도 실제로 탭 대상이 된다.
      expect(withdrawalTile, findsOneWidget);

      // (b) geometry — SafeArea 제거 시 실패하는 유일한 관측량.
      expect(
        tester.getRect(withdrawalTile).bottom,
        lessThanOrEqualTo(safeBottom),
        reason:
            '회원탈퇴 ListTile 의 bottom 이 $safeBottom (= 화면 높이 $screenHeight '
            '− 하단 system inset $bottomInset) 을 넘으면 실 단말의 3버튼 '
            '내비게이션 바에 가려져 탭 불가가 된다. 이 단언은 '
            'settings_screen.dart 의 `body: SafeArea(...)` (`3674ec3`, '
            'G-16-A6-1) 가 제거되면 실패하는 유일한 관측량이다.',
      );

      // (c) 진입 path — 탭이 실제로 탈퇴 확인 다이얼로그를 띄운다.
      expect(find.byType(WithdrawalConfirmationDialog), findsNothing);
      await tester.tap(withdrawalTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(WithdrawalConfirmationDialog), findsOneWidget);
    });

    testWidgets(
      'SS9 모든 소셜 linked — AccountLinkingSection 미노출 (Danger zone 회귀 0)',
      (tester) async {
        await _pumpSettingsScreen(
          tester,
          user: _testUser(
            providerIds: const <String>[
              'password',
              'google.com',
              'apple.com',
              'facebook.com',
              'kakao',
              'naver',
              'line',
            ],
          ),
        );

        // available 빈 set → 계정 연결 heading 미노출.
        expect(find.text('Link an account'), findsNothing);
        // 단, Danger zone 은 계속 노출 (회귀 0).
        expect(find.byType(DangerZoneSection), findsOneWidget);
      },
    );

    testWidgets(
      'SS11 section heading role·색 — heading 2곳 label 계열 role + 지정 색',
      (tester) async {
        await _pumpSettingsScreen(
          tester,
          user: _testUser(providerIds: _allSocialLinked),
        );

        final theme = Theme.of(tester.element(find.byType(SettingsScreen)));
        final headingRole = theme.textTheme.labelMedium;

        final accountHeading = tester.widget<Text>(find.text('My Account'));
        expect(accountHeading.style?.fontSize, equals(headingRole?.fontSize));
        expect(
          accountHeading.style?.fontWeight,
          equals(headingRole?.fontWeight),
        );
        expect(
          accountHeading.style?.color,
          equals(theme.colorScheme.onSurfaceVariant),
        );

        final dangerHeading = tester.widget<Text>(find.text('Danger zone'));
        expect(dangerHeading.style?.fontSize, equals(headingRole?.fontSize));
        expect(
          dangerHeading.style?.fontWeight,
          equals(headingRole?.fontWeight),
        );
        expect(dangerHeading.style?.color, equals(theme.colorScheme.error));
      },
    );

    testWidgets(
      'SS12 Danger zone explainer role + chevron accent (icon·title 은 error 불변)',
      (tester) async {
        await _pumpSettingsScreen(
          tester,
          user: _testUser(providerIds: _allSocialLinked),
        );

        final theme = Theme.of(tester.element(find.byType(SettingsScreen)));

        // explainer 는 본문 보조 role 과 동일 metric.
        final explainer = tester.widget<Text>(
          find.text('These actions cannot be undone.'),
        );
        expect(
          explainer.style?.fontSize,
          equals(theme.textTheme.bodyMedium?.fontSize),
        );

        // trailing chevron 은 accent 화이트리스트 대상.
        final chevron = tester.widget<Icon>(find.byIcon(Icons.chevron_right));
        expect(chevron.color, equals(theme.colorScheme.primary));

        // destructive intent 2요소(leading icon + title)는 그대로 유지.
        final leadingIcon = tester.widget<Icon>(
          find.byIcon(Icons.delete_forever),
        );
        expect(leadingIcon.color, equals(theme.colorScheme.error));
        final dangerTile = tester.widget<ListTile>(
          find.ancestor(
            of: find.text('Delete account').last,
            matching: find.byType(ListTile),
          ),
        );
        expect(
          (dangerTile.title! as Text).style?.color,
          equals(theme.colorScheme.error),
        );
      },
    );

    testWidgets('SS13 Danger zone Semantics — 회원탈퇴 ListTile 결합 라벨 노출', (
      tester,
    ) async {
      // 시맨틱 트리를 명시적으로 켠다 (environment_info_screen_test 패턴).
      final handle = tester.ensureSemantics();
      await _pumpSettingsScreen(
        tester,
        user: _testUser(providerIds: _allSocialLinked),
      );

      // en verbatim — 기존 ARB 2 key 조합 (신규 key 0).
      expect(
        find.bySemanticsLabel('Delete account | Danger zone'),
        findsAtLeast(1),
      );
      handle.dispose();
    });

    testWidgets(
      'SS14 계정 연결 heading role·색 — label 계열 role + onSurfaceVariant',
      (tester) async {
        // password-only → 계정 연결 section 노출.
        await _pumpSettingsScreen(tester, user: _testUser());

        final linkingHeading = find.text('Link an account');
        expect(linkingHeading, findsOneWidget);
        // 기본 800x600 viewport 밖일 수 있으므로 먼저 노출시킨다.
        await tester.ensureVisible(linkingHeading);
        await tester.pump();

        final theme = Theme.of(tester.element(find.byType(SettingsScreen)));
        final headingRole = theme.textTheme.labelMedium;
        final heading = tester.widget<Text>(linkingHeading);
        expect(heading.style?.fontSize, equals(headingRole?.fontSize));
        expect(heading.style?.fontWeight, equals(headingRole?.fontWeight));
        expect(
          heading.style?.color,
          equals(theme.colorScheme.onSurfaceVariant),
        );
      },
    );
  });

  group('Phase 16.7 내 계정 3행 제목/값 (D-02 R1 · D-03 · D-09 · D-11)', () {
    testWidgets(
      '16.7-S01 3행 제목/값 semantics — 병합 label = 제목 줄바꿈 값 (D-02 R1 · D-09)',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pumpSettingsScreen(
          tester,
          user: _testUser(
            providerIds: const <String>['password', 'kakao'],
            signUpProviderId: 'kakao',
          ),
        );

        // ListTile 은 title · subtitle 을 한 노드로 병합하고 줄바꿈으로 잇는다.
        expect(
          tester.getSemantics(_findEmailTile()).label,
          'Email\nme@example.com',
        );
        expect(
          tester.getSemantics(_findSignUpMethodTile()).label,
          'Sign-up method\nKakao',
        );
        expect(
          tester.getSemantics(_findLinkedAccountsTile()).label,
          'Linked accounts\nEmail / Password',
        );
        expect(find.byIcon(Icons.alternate_email), findsOneWidget);
        expect(find.byIcon(Icons.how_to_reg), findsOneWidget);
        expect(find.byIcon(Icons.link), findsOneWidget);
        // S06 — overflow 0.
        expect(tester.takeException(), isNull);
        handle.dispose();
      },
    );

    testWidgets('16.7-S02 연결 0개 — 연결 행 값 "None" · WidgetSpan 0 (D-03)', (
      tester,
    ) async {
      await _pumpSettingsScreen(
        tester,
        user: _testUser(
          providerIds: const <String>['naver'],
          signUpProviderId: 'naver',
        ),
      );

      expect(
        find.descendant(
          of: _findSignUpMethodTile(),
          matching: find.text('Naver'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _findLinkedAccountsTile(),
          matching: find.text('None'),
        ),
        findsOneWidget,
      );
      expect(_countLinkedWidgetSpans(tester), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('16.7-S03 기록 null — 가입 수단 값 "-" · 연결 = 보유 전부 (D-11 · D-05)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpSettingsScreen(
        tester,
        user: _testUser(providerIds: _kAllProviderIdsHeld),
      );

      expect(
        tester.getSemantics(_findSignUpMethodTile()).label,
        'Sign-up method\n-',
      );
      expect(
        tester.getSemantics(_findLinkedAccountsTile()).label,
        'Linked accounts\nGoogle, Apple, Facebook, Kakao, Naver, LINE, '
        'Email / Password',
      );
      expect(_countLinkedWidgetSpans(tester), 7);
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('16.7-S04 연결 행 semantics 무오염 — 보이지 않는 문자 6종 0', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpSettingsScreen(
        tester,
        user: _testUser(
          providerIds: const <String>['google.com', 'line', 'password'],
          signUpProviderId: 'line',
        ),
      );

      final label = tester.getSemantics(_findLinkedAccountsTile()).label;
      expect(label, 'Linked accounts\nGoogle, Email / Password');
      for (final char in _kInvisibleChars) {
        expect(label.contains(char), isFalse);
        // 화면 어느 semantics 노드에도 자리표시 · 결합 문자가 새지 않는다.
        expect(find.bySemanticsLabel(RegExp(char)), findsNothing);
      }
      // 대조군 — 표시 span 의 plain text 에는 WidgetSpan 자리표시가 있다
      // (flutter_test 의 text finder 가 textSpan.toPlainText() 로 매칭).
      // 그래서 semanticsLabel 없이는 낭독 문자열이 오염된다.
      expect(find.textContaining(_kInvisibleChars.first), findsOneWidget);
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('16.7-S05 R1 계약 — 제목/값 style · 행별 maxLines · ListTile SDK 기본', (
      tester,
    ) async {
      await _pumpSettingsScreen(
        tester,
        user: _testUser(
          providerIds: const <String>['password', 'kakao'],
          signUpProviderId: 'kakao',
        ),
      );

      final theme = Theme.of(tester.element(find.byType(SettingsScreen)));
      final titleRole = theme.textTheme.bodySmall;
      final valueRole = theme.textTheme.titleMedium;

      final tiles = <String, ListTile>{
        'Email': tester.widget<ListTile>(_findEmailTile()),
        'Sign-up method': tester.widget<ListTile>(_findSignUpMethodTile()),
        'Linked accounts': tester.widget<ListTile>(_findLinkedAccountsTile()),
      };
      for (final entry in tiles.entries) {
        final tile = entry.value;
        expect(tile.title, isNotNull);
        expect(tile.subtitle, isNotNull);

        // 제목 = 홈 카드 라벨 키 · bodySmall + onSurfaceVariant.
        final title = tile.title! as Text;
        expect(title.data, entry.key);
        expect(title.style?.fontSize, equals(titleRole?.fontSize));
        expect(title.style?.fontWeight, equals(titleRole?.fontWeight));
        expect(title.style?.color, equals(theme.colorScheme.onSurfaceVariant));

        // 값 = titleMedium (색 미지정 — theme 기본 onSurface).
        final value = tile.subtitle! as Text;
        expect(value.style?.fontSize, equals(valueRole?.fontSize));
        expect(value.style?.fontWeight, equals(valueRole?.fontWeight));

        // ListTile 은 SDK 기본 — mockup 과 byte 동일 전제. 세 줄 플래그는
        // SDK 에서 nullable 이라 미지정 = null (theme · false 로 해석은 SDK 내부).
        expect(tile.isThreeLine, isNull);
        expect(tile.titleTextStyle, isNull);
        expect(tile.subtitleTextStyle, isNull);
        expect(tile.dense, isNull);
        expect(tile.contentPadding, isNull);
      }

      // 이메일 주소만 2줄 + 말줄임 (WR-14).
      final emailValue = tiles['Email']!.subtitle! as Text;
      expect(emailValue.maxLines, 2);
      expect(emailValue.overflow, TextOverflow.ellipsis);
      // 가입 수단 값 — 줄 수 제한 없음 (D-04 개정 (R1)).
      final signUpValue = tiles['Sign-up method']!.subtitle! as Text;
      expect(signUpValue.maxLines, isNull);
      expect(signUpValue.overflow, isNull);
      expect(signUpValue.softWrap, isTrue);
      // 연결된 계정 값 — Text.rich · 줄 수 제한 없음 (D-02 개정 (R1)).
      expect(_readLinkedAccountsValue(tester).textSpan, isNotNull);
      expect(_readLinkedAccountsValue(tester).maxLines, isNull);
      expect(_readLinkedAccountsValue(tester).overflow, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('16.7-S06 280dp viewport · 보유 전부 — overflow 0 (D-02 개정)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpSettingsScreen(
        tester,
        user: _testUser(providerIds: _kAllProviderIdsHeld),
      );

      // maxLines 없이 전부 표시 — 7개 라벨이 모두 WidgetSpan 으로 존재한다.
      expect(_countLinkedWidgetSpans(tester), 7);
      expect(tester.takeException(), isNull);
    });
  });
}
