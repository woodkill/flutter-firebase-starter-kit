// ignore_for_file: lines_longer_than_80_chars
//
// Phase 17.1 Plan 17.1-06 Task 2 — 계정 기능이 계정 정보 화면으로 옮겨 가
//   (D-02 · D-22) 아래 이력의 SS1~SS14 · 16.7 · 16.8 · fp6 · T-17-PHOTO-09
//   그룹은 account_screen_test.dart 로 이전했다. 이 파일에는 T-17-NOTIF-12 와
//   게스트 그룹(T-171-SETTINGS)만 남는다 — 설정 고유 단언(AppBar 제목 · 말단
//   스크롤 · 3버튼 내비 hit-test · heading)은 plan 09 T-171-SETTINGS-17 이 최종
//   설정 화면에서 다시 잠근다.
//
// Phase 16 Plan 16-06 Task 6.2 — SettingsScreen widget test (SS1~SS4).
// Phase 16 Plan 16-11 Task 2 — AccountLinkingSection 삽입 + 회귀 가드 (SS5~SS9).
// Phase 16 Plan 16-16 Task 1 — 3버튼 내비(48dp) inset 회귀 가드 (SS10).
// Phase 16.7 Plan 16.7-05 Task 2 — 내 계정 2행(가입 수단 · 연결된 계정) SS4 재작성
//   + 16.7-S01~S06.
// Phase 16.7 Plan 16.7-11 Task 1 — R1 제목/값 분리(ListTile title/subtitle) 로
//   SS4 · 16.7-S01~S06 재작성.
// Phase 16.8 Plan 16.8-01 Task 1 — 연결된 계정 semantics 가 provider 별 노드
//   (UI-SPEC §Semantics (16.8))로 바뀌어 16.7-S01 · S03 · S04 재작성 + S02 보강.
// Phase 16.8 Plan 16.8-04 Task 1 — 연결된 계정 해제 16.8-S01~S11 (semantics
//   구조 · 3조건 fixture · 탭 → 다이얼로그 → outcome SnackBar · reauth 라우팅 ·
//   CT 분기 · ja 280 SnackBar). 탭 → outcome 케이스는 GoRouter harness
//   (`_pumpSettingsScreenWithRouter`)로 pump 한다 — reauthRequired arm 이
//   `GoRouter.of(context)` 를 그 arm 안에서 해석하기 때문이다.
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
// - 16.7-S01 3행 제목/값 semantics — 이메일 · 가입 수단 ListTile 병합 label =
//   '제목\n값' (D-02 R1 · D-09) · 연결된 계정은 제목만 + 해제 버튼 노드
//   (16.8 D-12).
// - 16.7-S02 연결 0개 — 연결 행 값 「None」 · WidgetSpan 0 · 병합 label
//   '제목\n없음' (D-03 · 16.8 UI-SPEC E1 empty).
// - 16.7-S03 기록 null — 가입 수단 값 「-」 · 연결 = 보유 전부 고정 순서 ·
//   전부 일반 텍스트 노드(버튼 0) (D-11 · D-05 · 16.8 D-05).
// - 16.7-S04 연결 행 semantics 무오염 — 보이지 않는 문자 6종 0 (제목 label +
//   해제 버튼 노드 label).
// - 16.7-S05 R1 계약 — 제목 bodySmall + onSurfaceVariant · 값 titleMedium ·
//   행별 maxLines/overflow · ListTile SDK 기본(세 줄 · tile 스타일 · dense ·
//   padding 미지정).
// - 16.7-S06 280dp viewport overflow 0.
// - 16.8-S01 semantics 구조 — ListTile label = 제목만 · 해제 버튼마다 button +
//   tap 노드 · 보이지 않는 문자 · 공백 전용 label 노드 0 (D-12).
// - 16.8-S02 덮어쓰기(D-03 · D-22) — 자격증명 1개면 일반 텍스트 · 탭 no-op.
// - 16.8-S03 가입 수단 기록 null(D-05 로딩 · 읽기 실패 fallback) — 버튼 0 ·
//   같은 보유에 기록이 오면 버튼 6.
// - 16.8-S04 미지 provider 혼재(D-11) · 16.8-S05 1개 · 자격증명 2 — 쉼표 없음.
// - 16.8-S06 취소 no-op · 16.8-S07 success SnackBar · 16.8-S08 실패 outcome 4
//   문구 · 16.8-S09 reauthRequired → /login + 재인증 표시 · 16.8-S10 CT 분기 ·
//   16.8-S11 ja 280 SnackBar overflow 0 (E3).
// Phase 16.10 Plan 16.10-08 Task 1 — 해제 「해제」 가 provider 측 끊기 → 킷
//   해제로 바뀌어(D-09 · D-11) 확인을 누르는 16.8-S07~S11 은
//   `_pumpSettingsScreenWithRouter` 의 끊기 step(기본 = google.com · kakao
//   Done fake) · dummy 실행 의존 override 로 픽스처만 갱신(기대값 불변).
// - SU1 신원 불일치 → settingsUnlinkFailedIdentityMismatch SnackBar · 연결 유지.
// - SU2 끊기 실패(ServiceUnavailable) → settingsUnlinkFailedDisconnect SnackBar.
// 16.10 review IN-03 (iteration 3) — 끊기 Done 뒤 킷 해제 일시 · 미분류 실패는
//   부분 상태 문구. 16.8-S08(NoInternet · Unknown) · 16.8-S11 기대 문구를
//   settingsUnlinkFailedAfterDisconnect 로 갱신 · 16.8-S08b 이메일/비밀번호는
//   16.8 §N 문구 그대로 · SU3 Kakao 서버 행 Done 뒤 일시 오류.
// 16.10 review IN-04 (iteration 3) — SU4 끊기 provider_config
//   (ProviderMisconfigured) → settingsUnlinkFailedProviderConfig SnackBar · 연결 유지.
//
// Phase 17 Plan 17-15 Task 1 — 알림 섹션(Q3-A)이 계정 연결 아래 · Danger zone
//   위에 들어가 두 pump harness 가 `notificationSettingsProvider` 를 꺼짐
//   (AsyncData(false))으로 고정한다. T-17-NOTIF-12 — 고정 override 로 섹션이
//   꺼짐 렌더 · 배치 순서 · Danger zone 탭 경로(ensureVisible 뒤) 회귀 0.
// Phase 17 Plan 17-17 Task 1 — 프로필 사진 행(Q2-A)이 「내 계정」 첫 행으로
//   들어가 두 pump harness 가 `linkedProvidersStreamProvider(uid)` 를 data(업로드
//   사진 없음)로 고정한다. T-17-PHOTO-09 — 사진 행 위치 · 값 · 밀린 Danger zone
//   탭 경로(scrollUntilVisible 뒤) 회귀 0.
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

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/kakao_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/line_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/naver_auth_strategy.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/providers/locale_provider.dart';
import 'package:flutter_starter_kit/core/providers/theme_provider.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/notifications/application/notification_settings_notifier.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/account_linking_section.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/danger_zone_section.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/notifications_section.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/profile_photo_tile.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/withdrawal_confirmation_dialog.dart';
import 'package:flutter_starter_kit/features/settings/presentation/settings_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

class _MockFbUser extends Mock implements fb.User {}

/// 활성 소셜 Strategy 6종 전부.
const List<AuthStrategy> _allStrategies = <AuthStrategy>[
  GoogleAuthStrategy(),
  AppleAuthStrategy(),
  FacebookAuthStrategy(),
  KakaoAuthStrategy(),
  NaverAuthStrategy(),
  LineAuthStrategy(),
];

/// 테스트용 User factory.
User _testUser({
  List<String> providerIds = const <String>['password'],
  String? email = 'me@example.com',
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

/// 사진 출처 stream fixture — 업로드 사진 없음 (Phase 17 T-17-PHOTO-09).
///
/// 화면은 `currentUserProvider` override 로 사용자를 고정하므로 이 record 는
/// 사진 행의 출처 읽기 상태(data)만 결정한다.
const UserProviderRecord _kNoPhotoRecord = (
  linkedProviderIds: <String>[],
  signUpProviderId: null,
  customPhotoUrl: null,
);

Future<void> _pumpSettingsScreen(
  WidgetTester tester, {
  required User? user,
  Locale locale = const Locale('en'),
  List<AuthStrategy> strategies = _allStrategies,
  AuthRepository? authRepo,
}) async {
  // 280dp 이상 (PROJECT.md mobile 반응형) — default 800x600 사용.
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => user),
        // 활성 Strategy 직접 주입 — AccountLinkingSection available 계산 결정성.
        activeStrategiesProvider.overrideWith((ref) => strategies),
        // Phase 16.8 — 해제 경로가 실 Firebase 에 닿지 않도록 mock 주입(선택).
        if (authRepo != null)
          authRepositoryProvider.overrideWithValue(authRepo),
        // Phase 17 T-17-NOTIF-12 — 알림 섹션 꺼짐 고정(AsyncData(false)).
        notificationSettingsProvider.overrideWithBuild(
          (ref, notifier) => false,
        ),
        // Phase 17 T-17-PHOTO-09 — 사진 행의 사진 출처 stream 을 data 로 고정
        // (미초기화 Firestore 에 닿지 않게 · 업로드 사진 없음).
        if (user != null)
          linkedProvidersStreamProvider(
            user.uid,
          ).overrideWith((ref) => Stream.value(_kNoPhotoRecord)),
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

/// 설정 ListView 를 [finder] 가 보일 때까지 스크롤한다 (Phase 17 Plan 17-15).
///
/// 알림 섹션(Q3-A)이 들어가 Danger zone 이 800×600 의 lazy build 범위 밖으로
/// 밀렸다 — build 되지 않은 위젯은 `ensureVisible` 로 찾을 수 없다.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

/// 게스트(익명) 설정 화면을 GoRouter 안에서 pump 하고 provider container 를
/// 돌려준다 (Phase 17.1 T-171-SETTINGS).
///
/// - `authStateProvider` = 익명 mock(`isAnonymous` true) data — 설정 화면의
///   게스트 판정 입력 (RESEARCH Pitfall 6).
/// - 테마 = 실 notifier + 빈 SharedPreferences(→ 시스템) · 언어 = 실 notifier
///   (초기값만 [locale] 로 고정) — 시트 저장이 실제 저장 경로를 탄다.
/// - `MaterialApp.locale` 을 `localeProvider` 에 묶는다(앱 `app.dart` 와 같게).
/// - `/login` · 데모 경로는 stub 화면.
///
/// [screen] 으로 설정 화면 생성 방식을, [extraOverrides] 로 상태 override 를
/// 바꾼다.
Future<ProviderContainer> _pumpGuestSettings(
  WidgetTester tester, {
  Locale locale = const Locale('ko'),
  Widget screen = const SettingsScreen(),
  List<Override> extraOverrides = const <Override>[],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final anon = _MockFbUser();
  when(() => anon.isAnonymous).thenReturn(true);
  when(() => anon.uid).thenReturn('anon-uid');

  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(path: AppRoutes.home, builder: (context, state) => screen),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const Scaffold(body: Text('LOGIN ROUTE')),
      ),
      GoRoute(
        path: AppRoutes.developerDemo,
        builder: (context, state) => const Scaffold(body: Text('DEMO ROUTE')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      // 테마 build 실패 케이스(T-171-SETTINGS-08)가 재시도 타이머를 남기지 않게.
      retry: (retryCount, error) => null,
      overrides: [
        // 첫 프레임부터 익명 data — 실 앱은 authState(keepAlive)가 설정 진입 전에
        // 이미 값을 가진다.
        authStateProvider.overrideWithValue(AsyncData(anon)),
        currentUserProvider.overrideWith((ref) => null),
        localeProvider.overrideWithBuild((ref, notifier) => locale),
        ...extraOverrides,
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          theme: AppTheme.light(),
          locale: ref.watch(localeProvider),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
}

/// 열린 선택창의 [RadioListTile] 라벨을 화면 위 → 아래 순서로 돌려준다.
List<String> _sheetLabels<T>(WidgetTester tester) {
  final tiles = find.byType(RadioListTile<T>);
  final entries = [
    for (final element in tiles.evaluate())
      (
        y: tester.getTopLeft(find.byWidget(element.widget)).dy,
        label: ((element.widget as RadioListTile<T>).title! as Text).data ?? '',
      ),
  ]..sort((a, b) => a.y.compareTo(b.y));
  return [for (final entry in entries) entry.label];
}

/// [finder] 문단의 렌더 줄 수 — 같은 폭으로 재배치해 센다.
int _countLines(WidgetTester tester, Finder finder) {
  final rp = tester.renderObject<RenderParagraph>(finder);
  final painter = TextPainter(
    text: rp.text,
    textDirection: rp.textDirection,
    textScaler: rp.textScaler,
    locale: rp.locale,
    strutStyle: rp.strutStyle,
    textWidthBasis: rp.textWidthBasis,
    textHeightBehavior: rp.textHeightBehavior,
  )..layout(maxWidth: rp.constraints.maxWidth);
  final count = painter.computeLineMetrics().length;
  painter.dispose();
  return count;
}

/// 테스트 viewport 를 [size](DPR 1)로 바꾼다 — 테스트 끝에 되돌린다.
void _useViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

/// 열린 선택창 [RadioGroup] 의 현재 선택값.
T? _sheetGroupValue<T>(WidgetTester tester) =>
    tester.widget<RadioGroup<T>>(find.byType(RadioGroup<T>)).groupValue;

void main() {
  group('Phase 17 알림 섹션 회귀 (T-17-NOTIF-12)', () {
    testWidgets('T-17-NOTIF-12: 꺼짐 고정 override — 알림 섹션(꺼짐)이 계정 연결 '
        '아래 · Danger zone 위 · 회원탈퇴 탭 경로 회귀 0', (tester) async {
      await _pumpSettingsScreen(
        tester,
        user: _testUser(
          providerIds: const <String>['google.com'],
          signUpProviderId: 'google.com',
        ),
      );

      final section = find.byType(NotificationsSection);
      await _scrollTo(tester, find.byType(DangerZoneSection));
      final toggle = tester.widget<SwitchListTile>(
        find.descendant(of: section, matching: find.byType(SwitchListTile)),
      );
      expect(toggle.value, isFalse);
      expect(toggle.onChanged, isNotNull);

      final linkingY = tester.getTopLeft(find.byType(AccountLinkingSection)).dy;
      final sectionY = tester.getTopLeft(section).dy;
      final dangerY = tester.getTopLeft(find.byType(DangerZoneSection)).dy;
      expect(linkingY, lessThan(sectionY));
      expect(sectionY, lessThan(dangerY));

      await _scrollTo(tester, find.byType(DangerZoneSection));
      await tester.tap(find.text('Delete account').last);
      await tester.pumpAndSettle();
      expect(find.byType(WithdrawalConfirmationDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 17.1 설정 게스트 (T-171-SETTINGS)', () {
    final ko = lookupAppLocalizations(const Locale('ko'));

    testWidgets('T-171-SETTINGS-01: 게스트 — 로그인 · 가입 행 · 일반(테마 · 언어) · '
        '개발자 데모 행 · 알림 · 계정 블록 0 (D-07)', (tester) async {
      await _pumpGuestSettings(tester);

      expect(find.text(ko.settingsGuestLabel), findsOneWidget);
      expect(find.text(ko.settingsSignInOrSignUp), findsOneWidget);
      expect(find.text(ko.settingsGeneralSection), findsOneWidget);
      expect(find.text(ko.settingsTheme), findsOneWidget);
      expect(find.text(ko.settingsThemeSystem), findsOneWidget);
      expect(find.text(ko.settingsLanguage), findsOneWidget);
      expect(find.text('한국어'), findsOneWidget);
      expect(find.text(ko.settingsDeveloperSection), findsOneWidget);
      expect(find.text(ko.demoScreenTitle), findsOneWidget);
      expect(find.text(ko.settingsDemoScreenSubtitle), findsOneWidget);
      // 17 D-02 정정 — 게스트에게 알림 · 정식 전용 블록 0 (T-17.1-07).
      expect(find.byType(NotificationsSection), findsNothing);
      expect(find.byType(DangerZoneSection), findsNothing);
      expect(find.byType(ProfilePhotoTile), findsNothing);
      expect(find.byType(AccountLinkingSection), findsNothing);
      expect(find.text(ko.settingsAccountSection), findsNothing);

      // 배치 순서 — 게스트 행 → 일반 → 테마 → 언어 → 개발자 → 데모 행.
      final ys = [
        for (final text in [
          ko.settingsGuestLabel,
          ko.settingsGeneralSection,
          ko.settingsTheme,
          ko.settingsLanguage,
          ko.settingsDeveloperSection,
          ko.demoScreenTitle,
        ])
          tester.getTopLeft(find.text(text)).dy,
      ];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i - 1], lessThan(ys[i]));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('T-171-SETTINGS-02: 게스트 행 탭 → 로그인 화면 push', (tester) async {
      await _pumpGuestSettings(tester);

      await tester.tap(find.text(ko.settingsSignInOrSignUp));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN ROUTE'), findsOneWidget);
    });

    testWidgets('T-171-SETTINGS-03: 테마 행 → 시트(시스템 · 라이트 · 다크 · 시스템 '
        '선택) → 다크 = 저장 + 닫힘 · SnackBar 0 (D-04 · Q2-A)', (tester) async {
      final container = await _pumpGuestSettings(tester);

      await tester.tap(find.text(ko.settingsTheme));
      await tester.pumpAndSettle();

      expect(find.byType(RadioListTile<ThemeMode>), findsNWidgets(3));
      expect(_sheetLabels<ThemeMode>(tester), [
        ko.settingsThemeSystem,
        ko.settingsThemeLight,
        ko.settingsThemeDark,
      ]);
      expect(_sheetGroupValue<ThemeMode>(tester), ThemeMode.system);

      await tester.tap(find.text(ko.settingsThemeDark));
      await tester.pumpAndSettle();

      expect(find.byType(RadioListTile<ThemeMode>), findsNothing);
      expect(container.read(themeProvider).value, ThemeMode.dark);
      expect(find.text(ko.settingsThemeDark), findsOneWidget);
      expect(find.text(ko.settingsThemeSystem), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('T-171-SETTINGS-04: 언어 행 → 시트(English · 日本語 · 한국어 · '
        '한국어 선택) → English = 저장 + 닫힘 · SnackBar 0 (D-04)', (tester) async {
      final container = await _pumpGuestSettings(tester);

      await tester.tap(find.text(ko.settingsLanguage));
      await tester.pumpAndSettle();

      expect(find.byType(RadioListTile<Locale>), findsNWidgets(3));
      expect(_sheetLabels<Locale>(tester), ['English', '日本語', '한국어']);
      expect(_sheetGroupValue<Locale>(tester), const Locale('ko'));

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      expect(find.byType(RadioListTile<Locale>), findsNothing);
      expect(container.read(localeProvider), const Locale('en'));
      // 앱 언어가 바로 바뀐다 — 행 라벨도 영어, 값 = English.
      final en = lookupAppLocalizations(const Locale('en'));
      expect(find.text(en.settingsLanguage), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('T-171-SETTINGS-05: 바깥 탭 · back · 현재값 다시 탭 → 시트 닫힘 · '
        '값 불변 · 저장 0 (E4 populated)', (tester) async {
      final container = await _pumpGuestSettings(tester);
      final prefs = await SharedPreferences.getInstance();

      Future<void> openThemeSheet() async {
        await tester.tap(find.text(ko.settingsTheme));
        await tester.pumpAndSettle();
        expect(find.byType(RadioListTile<ThemeMode>), findsNWidgets(3));
      }

      void expectThemeUnchanged() {
        expect(find.byType(RadioListTile<ThemeMode>), findsNothing);
        expect(container.read(themeProvider).value, ThemeMode.system);
        expect(find.text(ko.settingsThemeSystem), findsOneWidget);
      }

      // 1) 바깥(barrier) 탭 — 시트 위 화면 좌상단.
      await openThemeSheet();
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expectThemeUnchanged();

      // 2) back.
      await openThemeSheet();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expectThemeUnchanged();

      // 3) 현재값(시스템) 다시 탭 — toggleable → null → 닫힘.
      await openThemeSheet();
      await tester.tap(
        find.descendant(
          of: find.byType(RadioListTile<ThemeMode>),
          matching: find.text(ko.settingsThemeSystem),
        ),
      );
      await tester.pumpAndSettle();
      expectThemeUnchanged();

      // 언어도 현재값(한국어) 다시 탭 = 닫힘 · 값 불변.
      await tester.tap(find.text(ko.settingsLanguage));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(RadioListTile<Locale>),
          matching: find.text('한국어'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RadioListTile<Locale>), findsNothing);
      expect(container.read(localeProvider), const Locale('ko'));

      // 저장 호출 0 — 두 provider 의 저장 키가 비어 있다.
      expect(prefs.getInt('theme_mode'), isNull);
      expect(prefs.getString('locale_language_code'), isNull);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('T-171-SETTINGS-06: showsDemoRow false(release) — 「개발자」 '
        'heading · 데모 행 0 · 언어 행이 마지막 (D-14)', (tester) async {
      await _pumpGuestSettings(
        tester,
        screen: const SettingsScreen(showsDemoRow: false),
      );

      expect(find.text(ko.settingsDeveloperSection), findsNothing);
      expect(find.text(ko.demoScreenTitle), findsNothing);
      expect(find.byIcon(Icons.developer_mode), findsNothing);
      expect(find.text(ko.settingsLanguage), findsOneWidget);
      expect(find.text(ko.settingsSignInOrSignUp), findsOneWidget);
    });

    testWidgets('T-171-SETTINGS-07: 데모 행 탭 → 데모 경로 push (D-15)', (
      tester,
    ) async {
      await _pumpGuestSettings(tester);

      await _scrollTo(tester, find.text(ko.demoScreenTitle));
      await tester.tap(find.text(ko.demoScreenTitle));
      await tester.pumpAndSettle();

      expect(find.text('DEMO ROUTE'), findsOneWidget);
    });

    for (final (name, build) in <(String, FutureOr<ThemeMode> Function())>[
      ('loading(끝나지 않는 build)', () => Completer<ThemeMode>().future),
      ('error(throw 하는 build)', () => throw StateError('theme_load')),
    ]) {
      testWidgets('T-171-SETTINGS-08: 테마 $name → 행 값 「시스템」 · 시트도 시스템 '
          '선택 (E3 · E4 loading)', (tester) async {
        await _pumpGuestSettings(
          tester,
          extraOverrides: [
            themeProvider.overrideWithBuild((ref, notifier) => build()),
          ],
        );

        expect(find.text(ko.settingsThemeSystem), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing,
        );

        await tester.tap(find.text(ko.settingsTheme));
        await tester.pumpAndSettle();
        expect(_sheetGroupValue<ThemeMode>(tester), ThemeMode.system);
        expect(tester.takeException(), isNull);
      });
    }

    for (final code in const ['ko', 'en', 'ja']) {
      testWidgets('T-171-SETTINGS-10: 게스트 280×800 $code — overflow 0 · '
          '선택창 제목 maxLines 없음 (E3 · E4 long-text)', (tester) async {
        _useViewport(tester, const Size(280, 800));
        final l10n = lookupAppLocalizations(Locale(code));
        await _pumpGuestSettings(tester, locale: Locale(code));

        expect(find.text(l10n.settingsSignInOrSignUp), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (code == 'ja') {
          // UI-SPEC (S) — ja 게스트 값 「ログイン・登録」 1줄.
          expect(
            _countLines(tester, find.text(l10n.settingsSignInOrSignUp)),
            1,
          );
        }

        await tester.tap(find.text(l10n.settingsTheme));
        await tester.pumpAndSettle();
        final tiles = tester.widgetList<RadioListTile<ThemeMode>>(
          find.byType(RadioListTile<ThemeMode>),
        );
        expect(tiles, hasLength(3));
        for (final tile in tiles) {
          expect((tile.title! as Text).maxLines, isNull);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('T-171-SETTINGS-10: 가로 780×360 — 테마 · 언어 시트 넘침 0 '
        '(E4 overflow)', (tester) async {
      _useViewport(tester, const Size(780, 360));
      await _pumpGuestSettings(tester);

      await tester.tap(find.text(ko.settingsTheme));
      await tester.pumpAndSettle();
      expect(find.byType(RadioListTile<ThemeMode>), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      await tester.tap(find.text(ko.settingsLanguage));
      await tester.pumpAndSettle();
      expect(find.byType(RadioListTile<Locale>), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('T-171-SETTINGS-10: ko 280 light — 설정 · 선택창 터치 영역 · '
        '라벨 · 대비 guideline', (tester) async {
      final handle = tester.ensureSemantics();
      _useViewport(tester, const Size(280, 800));
      await _pumpGuestSettings(tester);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      await tester.tap(find.text(ko.settingsTheme));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });
}
