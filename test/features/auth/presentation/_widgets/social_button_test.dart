// Phase 13.1 Plan 13.1-08 — caller refactor 회귀 가드.
// Phase 13.2 Plan 13.2-02 — Facebook 분기 BrandedSocialButton 위임 검증 +
// D-98 findsNothing sentinel 폐기 + sign_in_button 패키지 import 제거.
//
// **갱신 의도 (D-13.1-05-CASCADE acceptance + Phase 13.2 R7/D-98):**
// - Plan 13.1-05 의 sealed BrandSpec 마이그레이션 + Plan 13.1-07 자상 commit +
//   Plan 13.1-08 caller refactor 결과를 종합 검증한다.
// - Apple/Google/Naver 분기는 BrandedSocialButton 의 named factory 위임 검증
//   (Buttons.* enum 검증 폐기 — Buttons.{apple,googleDark,...} 는 Phase 13.1
//   에서 사용하지 않음). Phase 13.2 D-98 — `find.byType(SignInButton),
//   findsNothing` sentinel 도 폐기 (sign_in_button 패키지 자체 폐기 후 타입
//   부재). BrandedSocialButton.google / .apple find sentinel 만 보존.
// - Facebook 분기 — Phase 13.2 R7: SignInButton(Buttons.facebookNew) 직접
//   호출 → BrandedSocialButton.facebook(...) 위임 전환 검증 + Opacity /
//   IgnorePointer 패턴 0 검증.
// - Kakao 6 deferred RED → GREEN 전환 (자상 PNG + BrandedSocialButton 위임).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_button.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// 테스트용 fake [AuthStrategy].
///
/// 생성자가 `const` — 모든 필드가 `final` 이다. 단, `onSignIn` closure 인자를
/// 받는 invocation site 에서는 closure literal 이 const expression 이 아니므로
/// `const _FakeStrategy(...)` 호출은 사용하지 않는다 (Dart 언어 제약).
class _FakeStrategy extends AuthStrategy {
  const _FakeStrategy(
    this._providerId,
    this._labelKey,
    this._iconAsset, {
    this.onSignIn,
  }) : super();

  final String _providerId;
  final String _labelKey;
  final String _iconAsset;
  final Future<void> Function(WidgetRef ref)? onSignIn;

  @override
  String get providerId => _providerId;
  @override
  String get labelKey => _labelKey;
  @override
  String get iconAsset => _iconAsset;

  @override
  Future<void> signIn(WidgetRef ref) async {
    if (onSignIn != null) {
      await onSignIn!(ref);
    }
  }
}

/// 영문 로케일 + light theme 으로 [SocialButton] 을 pump 하는 helper.
///
/// [locale] 인자로 ko/ja 로케일 회귀도 가능 (Phase 12 — Kakao 라벨 검증).
Widget _wrap(
  Widget child, {
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    child: MaterialApp(
      theme: brightness == Brightness.dark
          ? AppTheme.dark()
          : AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

/// 좁은 시뮬레이터 surface 로 pump — 자상 placeholder 의 native size 가 큰
/// 기본 800x600 viewport 에서 발생하는 Row overflow 회피.
///
/// `tester.view.physicalSize` 는 deprecated 경로라 본 helper 는
/// `binding.setSurfaceSize` 를 사용한다. 모바일 280~674dp 범위 내 360dp 가
/// starter-kit 의 전형적 Pixel 수준 폭이다.
Future<void> _pumpWithMobileViewport(
  WidgetTester tester,
  Widget child,
) async {
  // iPhone 14 Pro 표준 폭 (393dp) + 약간 여유 — Google 자상 + 라벨 Row 가
  // 360dp 에서는 ~25px overflow 발생. 마진 포함 412dp 채택.
  await tester.binding.setSurfaceSize(const Size(412, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(child);
}

void main() {
  group('SocialButton — provider 별 BrandedSocialButton 위임 (Plan 13.1-08)', () {
    testWidgets(
      'Google 분기 (light) → BrandedSocialButton.google + GoogleSpec.theme=light',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdGoogle,
          'authGoogleSignIn',
          'google',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        await tester.pumpAndSettle();

        // Phase 13.2 D-98 — `find.byType(SignInButton), findsNothing`
        // sentinel 폐기 (sign_in_button 패키지 자체 폐기 후 타입 부재).
        // BrandedSocialButton.google find sentinel 단독 보존.
        final btn = tester.widget<BrandedSocialButton>(
          find.byType(BrandedSocialButton),
        );
        expect(btn.spec, isA<GoogleSpec>());
        expect((btn.spec as GoogleSpec).theme, GoogleTheme.light);
      },
    );

    testWidgets(
      'Google 분기 (dark) → GoogleSpec.theme=dark',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdGoogle,
          'authGoogleSignIn',
          'google',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(
            const SocialButton(strategy: strategy, isDisabled: false),
            brightness: Brightness.dark,
          ),
        );
        await tester.pumpAndSettle();

        final btn = tester.widget<BrandedSocialButton>(
          find.byType(BrandedSocialButton),
        );
        expect((btn.spec as GoogleSpec).theme, GoogleTheme.dark);
      },
    );

    testWidgets(
      'Apple 분기 (light) → BrandedSocialButton.apple + AppleSpec '
      '+ SignInWithAppleButtonStyle.black',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdApple,
          'authAppleSignIn',
          'apple',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        await tester.pumpAndSettle();

        // Phase 13.2 D-98 — `find.byType(SignInButton), findsNothing`
        // sentinel 폐기. BrandedSocialButton.apple find + Apple SDK 위제
        // (SignInWithAppleButton) find sentinel 단독 보존.
        final btn = tester.widget<BrandedSocialButton>(
          find.byType(BrandedSocialButton),
        );
        expect(btn.spec, isA<AppleSpec>());
        expect(btn.appleStyle, SignInWithAppleButtonStyle.black);
        // Apple SDK 위제 렌더 검증.
        expect(find.byType(SignInWithAppleButton), findsOneWidget);
      },
    );

    testWidgets(
      'Apple 분기 (dark) → SignInWithAppleButtonStyle.white',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdApple,
          'authAppleSignIn',
          'apple',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(
            const SocialButton(strategy: strategy, isDisabled: false),
            brightness: Brightness.dark,
          ),
        );
        await tester.pumpAndSettle();

        final btn = tester.widget<BrandedSocialButton>(
          find.byType(BrandedSocialButton),
        );
        expect(btn.appleStyle, SignInWithAppleButtonStyle.white);
      },
    );

    // T-13.2-FACEBOOK-DELEGATION-01: Facebook 분기 BrandedSocialButton 위임
    // (Phase 13.2 R7 acceptance) — Wave 2 social_button.dart Facebook 분기
    // 전환 (`SignInButton(Buttons.facebookNew)` → `BrandedSocialButton
    // .facebook(...)`) 완료 후 GREEN 자동 전환.
    //
    // **검증 사양 (Plan 13.2-02 acceptance verbatim):**
    // - SocialButton(strategy: facebookStrategy) pump 후
    //   find.byType(BrandedSocialButton) 매치 (위임 검증)
    // - 활성 상태 (isDisabled: false) 에서 caller-side Opacity 0.5 dim 패턴
    //   부재 검증 — Phase 13.1 WR-05 의 caller-side dim wrapper 폐기.
    // - find.byType(IgnorePointer) 0 매치 — IgnorePointer 패턴 폐기.
    //
    // **Phase 13.2 REVIEW CR-01 정정 (2026-05-13):** 본 test 의 의도는
    // "caller-side Opacity 0.5 dim wrapper 폐기" — `_renderFacebookButton`
    // 위제 내부의 disabled state cue Opacity (CR-01 fix 로 도입) 와 의미
    // 분리. 활성 상태에서는 internal Opacity 가 1.0 이므로 시각 dim 0 —
    // assertion 을 "Opacity.opacity 가 모두 1.0" 으로 정정하여 두 개념을
    // 양립.
    testWidgets(
      'T-13.2-FACEBOOK-DELEGATION-01: Facebook 분기 → BrandedSocialButton'
      '.facebook 위임 + 활성 시 caller-side dim 0 (R7 acceptance)',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdFacebook,
          'authFacebookSignIn',
          'facebook',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        await tester.pumpAndSettle();

        // BrandedSocialButton 위임 검증 — FacebookSpec.
        final btn = tester.widget<BrandedSocialButton>(
          find.byType(BrandedSocialButton),
        );
        expect(btn.spec, isA<FacebookSpec>());

        // 활성 상태 — SocialButton descendant 의 모든 Opacity 위제는
        // opacity == 1.0 (시각 dim 0). caller-side dim wrapper (Phase 13.1
        // WR-05) 가 부활하면 본 검증이 RED 로 회귀 surface.
        final opacityWidgets = tester
            .widgetList<Opacity>(
              find.descendant(
                of: find.byType(SocialButton),
                matching: find.byType(Opacity),
              ),
            )
            .toList();
        for (final op in opacityWidgets) {
          expect(
            op.opacity,
            1.0,
            reason: 'Phase 13.2 R7 — 활성 상태에서 caller-side 또는 widget-'
                'internal dim 0. CR-01 fix 의 disabled cue Opacity 는 '
                'isDisabled=true 시에만 < 1.0.',
          );
        }
        final ignorePointerFinder = find.descendant(
          of: find.byType(SocialButton),
          matching: find.byType(IgnorePointer),
        );
        expect(
          ignorePointerFinder,
          findsNothing,
          reason: 'Phase 13.2 R7 verbatim — IgnorePointer 패턴 폐기.',
        );
      },
    );

    // ─── Phase 13.1 REVIEW iter2 CR-02 정정 (2026-05-10) ──────────────────
    //
    // iter1 의 WR-06 fix (`77d23e0`) 가 `_resolveLabel` default 분기를
    // fail-loud (UnsupportedError throw) 로 전환했으나, `SocialButton.build()`
    // 의 호출 순서상 `_resolveLabel` 가 outer providerId switch BEFORE 호출
    // (line 53). 결과적으로 unknown providerId 단독 테스트 시 동시에
    // unknown labelKey 도 전달하면 inner _resolveLabel throw 가 outer
    // providerId switch default throw 를 mask — 검증 경로 silent drift.
    //
    // **fix:** test 를 두 개로 split — (1) Unknown providerId 분기 가드
    // (known labelKey 사용으로 _resolveLabel 우회), (2) Unknown labelKey
    // fail-loud 가드 (known providerId 사용). 둘 다 throw message 검증으로
    // 미래 회귀 검출 강화.
    testWidgets(
      'Unknown providerId → UnsupportedError (providerId 분기 가드, '
      'iter2 CR-02 split)',
      (tester) async {
        const strategy = _FakeStrategy(
          'unknown.com',
          // known labelKey 명시 — _resolveLabel 우회 의무 (iter1 WR-06 fix
          // 이후 unknown labelKey 시 inner throw 가 outer providerId throw
          // 를 mask 하는 silent drift 차단).
          'authGoogleSignIn',
          'unknown',
        );
        // build 안에서 throw → flutter test framework 의 default error handler
        // 가 capture 후 [tester.takeException] 으로 surface 한다.
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        final ex = tester.takeException();
        expect(ex, isA<UnsupportedError>());
        expect(
          ex.toString(),
          contains('Unknown providerId'),
          reason: 'iter2 CR-02 가드 — 본 test 는 outer providerId switch 의 '
              'default 분기 검증. inner _resolveLabel throw 가 mask 하면 '
              "message 가 'Unknown labelKey' 로 drift — 명시 메시지 매칭으로 "
              '검증 경로 보존.',
        );
      },
    );

    testWidgets(
      'Unknown labelKey → UnsupportedError (WR-06 fail-loud 가드, '
      'iter2 CR-02 split)',
      (tester) async {
        const strategy = _FakeStrategy(
          // known providerId — outer switch 의 case 가 정상 매칭되어 inner
          // _resolveLabel 가 호출되도록 유도. 이 경로에서 unknown labelKey
          // 를 전달해 fail-loud 분기 (iter1 WR-06 fix) 가 trigger 됨.
          kProviderIdGoogle,
          'authUnknown',
          'unknown',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        final ex = tester.takeException();
        expect(ex, isA<UnsupportedError>());
        expect(
          ex.toString(),
          contains('Unknown labelKey'),
          reason: 'iter1 WR-06 fail-loud 회귀 가드 — Phase 14+ provider 추가 시 '
              '_resolveLabel switch 갱신 누락 회귀 검출.',
        );
      },
    );
  });

  group('SocialButton 위임 invariant (D-11/D-12)', () {
    testWidgets('isDisabled=false + tap → strategy.signIn 호출', (tester) async {
      var signInCallCount = 0;
      final strategy = _FakeStrategy(
        kProviderIdGoogle,
        'authGoogleSignIn',
        'google',
        onSignIn: (ref) async {
          signInCallCount += 1;
        },
      );
      await _pumpWithMobileViewport(
        tester,
        _wrap(SocialButton(strategy: strategy, isDisabled: false)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SocialButton));
      await tester.pump();
      expect(
        signInCallCount,
        1,
        reason: 'tap 시 strategy.signIn(ref) 가 1회 호출되어야 한다',
      );
    });

    testWidgets('isDisabled=true + tap → strategy.signIn 호출 안 됨', (tester) async {
      var signInCallCount = 0;
      final strategy = _FakeStrategy(
        kProviderIdGoogle,
        'authGoogleSignIn',
        'google',
        onSignIn: (ref) async {
          signInCallCount += 1;
        },
      );
      await _pumpWithMobileViewport(
        tester,
        _wrap(SocialButton(strategy: strategy, isDisabled: true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SocialButton));
      await tester.pump();
      expect(signInCallCount, 0, reason: 'isDisabled=true 면 위임 호출 안 됨');
    });
  });

  // Phase 12 D-25 옵션 A → Phase 13.1 sealed BrandSpec.
  // Kakao 분기는 sign_in_button 미지원으로 BrandedSocialButton.kakao 위임.
  // Plan 13.1-07 commit 후 자상 = `kakao_login_large_wide.png` (PNG).
  //
  // **Phase 13.1 Gap-1 X2 (2026-05-09 자상화):** Plan 14 wide 자상 통째 buttons
  // 패턴 도입 후 Material color 는 Colors.transparent (자상에 노란 배경 baked-in),
  // ARB 라벨 "Continue with Kakao" / "카카오 로그인" 도 widget tree 에 렌더되지 않음
  // (자상 baked-in). 따라서 Material 노란 배경 검증 + 라벨 텍스트 검증은 자상화로
  // 자연 무효화 — 본 group 의 의도 (위임 invariant + 자상 형식 dispatch + 탭 동작)
  // 만 보존하고 자상 layer 검증 3 test 는 skip 처리.
  group('SocialButton Kakao 분기 (Plan 13.1-08 cascade GREEN)', () {
    testWidgets(
      'Kakao providerId → SignInButton 미사용 + KakaoSpec 위임 + InkWell 자식 '
      '[Phase 13.1 Gap-1 X2: Material 노란 배경 검증 폐기 — 자상 baked-in]',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdKakao,
          'authKakaoSignIn',
          'kakao',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        await tester.pumpAndSettle();

        // Phase 13.2 D-98 — sign_in_button 패키지 폐기 후 SignInButton 타입
        // 부재. findsNothing sentinel 폐기, BrandedSocialButton.kakao 위임
        // 검증 단독.
        // BrandedSocialButton 위임 + KakaoSpec.
        final btn = tester.widget<BrandedSocialButton>(
          find.byType(BrandedSocialButton),
        );
        expect(btn.spec, isA<KakaoSpec>());

        // InkWell 자식 — Material + InkWell 조합으로 button semantics 확보.
        expect(find.byType(InkWell), findsAtLeastNWidgets(1));

        // **Phase 13.1 Gap-1 X2:** Material color 는 Colors.transparent (자상
        // baked-in 노란 배경) — 별도 노란 Material 검증 폐기. 자상 자체가
        // buttons 외관 형성을 검증하는 회귀 가드는 Plan 13.1-09 golden test
        // (kakao_light.png) 가 담당.
      },
    );

    testWidgets(
      'Kakao 라벨 — en 로케일에서 "Continue with Kakao" 표시 (D-29 ARB) '
      '[SKIPPED: Phase 13.1 Gap-1 X2 자상화로 라벨 layer 부재]',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdKakao,
          'authKakaoSignIn',
          'kakao',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Continue with Kakao'), findsOneWidget);
      },
      // 자상화로 라벨 layer 부재 — Phase 18 Brand Center 권한 확보 후 재검토.
      skip: true,
    );

    testWidgets(
      'Kakao 라벨 — ko 로케일에서 "카카오 로그인" 표시 (D-29 ARB) '
      '[SKIPPED: Phase 13.1 Gap-1 X2 자상화로 라벨 layer 부재]',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdKakao,
          'authKakaoSignIn',
          'kakao',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(
            const SocialButton(strategy: strategy, isDisabled: false),
            locale: const Locale('ko'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('카카오 로그인'), findsOneWidget);
      },
      // 자상화로 라벨 layer 부재 — Phase 18 Brand Center 권한 확보 후 재검토.
      skip: true,
    );

    testWidgets(
      'Kakao 분기 — Image.asset 으로 PNG 자상 로드 (Plan 13.1-07 자상 commit 결과)',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdKakao,
          'authKakaoSignIn',
          'kakao',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        await tester.pumpAndSettle();

        // SVG 미사용 (Plan 13.1-05 sealed refactor — Kakao 자상 PNG 마이그레이션).
        expect(find.byType(SvgPicture), findsNothing);
        // PNG 자상 1개 (KakaoSpec.assetType == AssetType.png).
        expect(find.byType(Image), findsOneWidget);
      },
    );

    testWidgets(
      'Kakao 분기 + isDisabled=true → InkWell.onTap == null (탭 무효)',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdKakao,
          'authKakaoSignIn',
          'kakao',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: true)),
        );
        await tester.pumpAndSettle();

        // SocialButton 내부의 첫 InkWell — onTap 이 null 이어야 함.
        final inkWells = tester
            .widgetList<InkWell>(find.byType(InkWell))
            .toList();
        expect(inkWells, isNotEmpty);
        // 첫 번째 InkWell (Kakao 버튼 본체) 의 onTap 검증.
        expect(
          inkWells.first.onTap,
          isNull,
          reason: 'isDisabled=true 면 InkWell.onTap == null 로 탭 무효화',
        );
      },
    );

    testWidgets(
      'Kakao 분기 + isDisabled=false + tap → strategy.signIn 위임 1회',
      (tester) async {
        var signInCallCount = 0;
        final strategy = _FakeStrategy(
          kProviderIdKakao,
          'authKakaoSignIn',
          'kakao',
          onSignIn: (ref) async {
            signInCallCount += 1;
          },
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(SocialButton(strategy: strategy, isDisabled: false)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(SocialButton));
        await tester.pump();
        expect(
          signInCallCount,
          1,
          reason: 'Kakao 분기 tap 시 strategy.signIn(ref) 가 1회 호출되어야 한다',
        );
      },
    );
  });

  // Phase 13.1 신규 — Naver 분기 회귀 가드 (Plan 13.1-05 NaverTheme 매개변수
  // 추가 + Plan 13.1-07 자상 commit 결과 검증).
  //
  // **Phase 13.1 Gap-1 X2 (2026-05-09 자상화):** Plan 14 wide 자상 통째 buttons
  // 패턴 도입 후 Material color 는 Colors.transparent (자상에 그린 배경 baked-in).
  // 그린 Material 검증은 자상화로 자연 무효화 — 본 group 의 의도 (위임 invariant +
  // NaverTheme 분기 dispatch) 만 보존, 그린 배경 layer 검증 폐기.
  group('SocialButton Naver 분기 (Plan 13.1-08)', () {
    testWidgets(
      'Naver 분기 (light) → NaverSpec.theme=light '
      '[Phase 13.1 Gap-1 X2: Material 그린 배경 검증 폐기 — 자상 baked-in]',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdNaver,
          'authNaverSignIn',
          'naver',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        await tester.pumpAndSettle();

        // Phase 13.2 D-98 — sign_in_button 패키지 폐기 후 SignInButton 타입
        // 부재. findsNothing sentinel 폐기, BrandedSocialButton.naver 위임
        // 검증 단독.
        final btn = tester.widget<BrandedSocialButton>(
          find.byType(BrandedSocialButton),
        );
        expect(btn.spec, isA<NaverSpec>());
        expect((btn.spec as NaverSpec).theme, NaverTheme.light);

        // **Phase 13.1 Gap-1 X2:** Material color 는 Colors.transparent (자상
        // baked-in 그린 배경) — 별도 그린 Material 검증 폐기. 그린 배경의
        // 회귀 가드는 Plan 13.1-09 golden test (naver_light.png) 가 담당.
      },
    );

    testWidgets(
      'Naver 분기 (dark) → NaverSpec.theme=dark',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdNaver,
          'authNaverSignIn',
          'naver',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(
            const SocialButton(strategy: strategy, isDisabled: false),
            brightness: Brightness.dark,
          ),
        );
        await tester.pumpAndSettle();

        final btn = tester.widget<BrandedSocialButton>(
          find.byType(BrandedSocialButton),
        );
        expect((btn.spec as NaverSpec).theme, NaverTheme.dark);
      },
    );
  });
}
