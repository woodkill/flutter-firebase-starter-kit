// Phase 13.1 — see ROADMAP.md (D-66 sealed sub-class const + R1/R2/R8 회귀 가드)
//
// Phase 13.1 Gap-1 X2 (2026-05-09 자상화) — 본 file 카운트 8 → 14:
// 기존 8 (sealed hierarchy 회귀 가드) + 신규 6 (wide 자상 통째 buttons
// 패턴 검증). 사용자 보고 4 issue 해소 acceptance.
//
// Phase 13.1 Gap-1 X2 BLOCKER 2 fix — sentinel stub-context class 폐기 →
// tester.pumpWidget + tester.takeException 패턴 (Flutter 권장).
//
// Phase 13.3 — see ROADMAP.md (R6 caller-side compile-fail 흡수, Wave 3
//             D-117). 4 enum 폐기 (NaverTheme/GoogleTheme/KakaoLabelVariant/
//             NaverLabelVariant) + factory theme/style parameter 폐기에 따른
//             caller-side 정리. theme 필드 검증 test 폐기 — widget tree
//             assertion 신규는 Wave 4 책임.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

// ─── 회귀 가드 expected 색상 (BI 단일 진실원 mirror) ──────────────────────────
//
// **Phase 13.2 REVIEW WR-05 정정 (2026-05-13):** 본 주석은 이전에 production
// const (`_kKakao*` / `_kNaver*`) 가 비교 대상인 것처럼 시사했으나, Phase
// 13.1 REVIEW iter2 WR-04 fix 로 source const 가 모두 폐기되어 misleading
// 상태. BI 단일 진실원은 (1) `assets/brand/{kakao,naver}/` PNG 자상
// (baked-in 색), (2) 본 test 의 expected literal, (3) `docs/manual.md` D-Note
// (R1 컨텍스트 분리) 3 layer. production lib/ 트리에는 BI 색 const 미존재
// (자상 baked-in 후 dead retention 패턴 제거). 본 test 가 RED 면 expected
// literal 또는 docs/manual.md D-Note 가 drift 한 의미 — production const
// drift 가 아님.
//
// **R1 정정 (Phase 13.1):** `_kNaverGreenExpected = 0xFF03A94D` (NAVER ID
// 로그인 BI verbatim) — 회사 브랜드 0xFF03C75A 와 컨텍스트 분리.
const _kKakaoYellowExpected = Color(0xFFFEE500);
const _kNaverGreenExpected = Color(0xFF03A94D);
const _kNaverLabelExpected = Color(0xFFFFFFFF);

void main() {
  group('BrandedSocialButton — Phase 13.1 sealed hierarchy', () {
    // ─── T-13.1-SPEC-01: 7 sub-class const + assetType 매핑 ──────────────
    test('T-13.1-SPEC-01: 7 sub-class const constructor + assetType 매핑', () {
      // Phase 13.3 R2 — KakaoSpec assetType 변경: PNG → SVG (inline
      // `_kKakaoSymbolSvg` + `_renderKakaoButton` Universal Layout Pattern).
      expect(const KakaoSpec().assetType, AssetType.svg);
      expect(const KakaoSpec().borderRadius, 12.0);
      expect(const KakaoSpec().height, 48.0);
      expect(const KakaoSpec().iconSize, 18.0);

      // Phase 13.3 R3 — NaverSpec assetType SVG (inline `_kNaverSymbolSvg`).
      // theme 필드 폐기 (BI 단일 그린 #03A94D 강제).
      expect(const NaverSpec().assetType, AssetType.svg);
      expect(const NaverSpec().borderRadius, 12.0);

      // Phase 13.3 R1 — GoogleSpec theme 필드 폐기 (Theme.brightness 자동
      // 분기로 차원 축소). assetType SVG (Google Identity btn_signin_icon.svg).
      expect(const GoogleSpec().assetType, AssetType.svg);

      // AppleSpec — assetType.none (SDK 위제 위임).
      expect(const AppleSpec().assetType, AssetType.none);
      // FacebookSpec — Phase 13.2 D-95 lock: AssetType.png (Meta Primary
      // Logo PNG, Wave 1 sealed switch active 전환 후 GREEN).
      expect(const FacebookSpec().assetType, AssetType.png);

      // LineSpec / WechatSpec — assetType.png (Phase 14/16 자상 commit 후 활성).
      expect(const LineSpec().assetType, AssetType.png);
      expect(
        const WechatSpec(size: WechatPixelSize.px48).size,
        WechatPixelSize.px48,
      );
      expect(
        const WechatSpec(size: WechatPixelSize.px48).assetType,
        AssetType.png,
      );
    });

    // ─── T-13.1-SWITCH-01: sealed switch exhaustive 컴파일 시점 가드 ────
    test('T-13.1-SWITCH-01: sealed switch exhaustive — 7 sub-class 인스턴스화', () {
      // 본 test 는 dart analyze 가 검증 — sealed 7 sub-class 누락 시 컴파일
      // fail. 본 file 컴파일 통과 자체가 BrandedSocialButton.build() 내
      // sealed switch 의 exhaustiveness 보장 (Dart 3 closed hierarchy).
      const specs = <BrandSpec>[
        KakaoSpec(),
        NaverSpec(),
        GoogleSpec(),
        AppleSpec(),
        FacebookSpec(),
        LineSpec(),
        WechatSpec(size: WechatPixelSize.px48),
      ];
      expect(specs.length, 7);
    });

    // ─── T-13.1-FACTORY-01: 7 named factory smoke ────────────────────────
    test('T-13.1-FACTORY-01: 7 named factory 가 BrandedSocialButton 반환', () {
      final kakao = BrandedSocialButton.kakao(label: 'Kakao', onPressed: () {});
      final naver = BrandedSocialButton.naver(label: 'Naver', onPressed: () {});
      final google = BrandedSocialButton.google(
        label: 'Google',
        onPressed: () {},
      );
      final apple = BrandedSocialButton.apple(label: 'Apple', onPressed: () {});
      final facebook = BrandedSocialButton.facebook(
        label: 'Facebook',
        onPressed: () {},
      );
      final line = BrandedSocialButton.line(label: 'LINE', onPressed: () {});
      final wechat = BrandedSocialButton.wechat(
        label: 'WeChat',
        onPressed: () {},
      );

      expect(kakao.spec, isA<KakaoSpec>());
      expect(naver.spec, isA<NaverSpec>());
      expect(google.spec, isA<GoogleSpec>());
      expect(apple.spec, isA<AppleSpec>());
      expect(facebook.spec, isA<FacebookSpec>());
      expect(line.spec, isA<LineSpec>());
      expect(wechat.spec, isA<WechatSpec>());
    });

    // ─── T-13.1-NAVER-THEME-01 폐기 (Phase 13.3 R3) ──────────────────────
    //
    // Phase 13.3 R3 — NaverSpec.theme 필드 폐기 (BI 단일 그린 #03A94D 강제).
    // 본 test 는 theme 필드 존재 자체를 검증하던 회귀 가드 — 필드 폐기로
    // 의미 소실. NaverSpec const identity 검증은 동일 const 인스턴스 1개
    // (theme 분기 없음) 이므로 무의미. Wave 4 widget tree assertion 신규로
    // green-bg + N glyph 색 매핑 검증 책임 분리.

    // ─── T-13.1-R1-01: Naver 색 R1 정정 회귀 가드 ────────────────────────
    test('T-13.1-R1-01: 회귀 가드 — Naver 색 0xFF03A94D (R1 정정)', () {
      // Phase 13.1 R1 — `0xFF03C75A` (NAVER Corp + NCloud SSO) → `0xFF03A94D`
      // (NAVER ID 로그인 BI). 본 test 가 mirror const drift 를 RED 로
      // surface — production 색이 0xFF03C75A 로 회귀하면 즉시 fail.
      expect(_kNaverGreenExpected.toARGB32(), 0xFF03A94D);
      expect(
        _kNaverGreenExpected.toARGB32(),
        isNot(0xFF03C75A),
        reason: 'R1 정정 — 회사 브랜드 0xFF03C75A 회귀 차단',
      );
    });

    // ─── T-13.1-R2-01: borderRadius R2 정정 회귀 가드 ─────────────────────
    test('T-13.1-R2-01: 회귀 가드 — borderRadius default 12 (R2 정정)', () {
      // Phase 13.1 R2 — `borderRadius default 6 → 12` (Kakao BI 명시 12,
      // Naver 일관). BrandSpec base default 가 12 — 모든 sub-class 상속.
      expect(const KakaoSpec().borderRadius, 12.0);
      expect(const NaverSpec().borderRadius, 12.0);
      expect(const GoogleSpec().borderRadius, 12.0);
      expect(const AppleSpec().borderRadius, 12.0);
      expect(const FacebookSpec().borderRadius, 12.0);
      expect(const LineSpec().borderRadius, 12.0);
      expect(const WechatSpec(size: WechatPixelSize.px48).borderRadius, 12.0);
    });

    // ─── T-13.1-COLOR-MIRROR-01: Kakao 노란색 mirror 보존 ────────────────
    test('T-13.1-COLOR-MIRROR-01: Kakao 노란색 mirror 0xFFFEE500 보존 (회귀 0)', () {
      // Phase 12 D-29 / Phase 13.1 mirror — Kakao Brand Guideline 강제
      // (#FEE500). Phase 13.1 sealed 재작성 후에도 색 보존 확인.
      expect(_kKakaoYellowExpected.toARGB32(), 0xFFFEE500);
    });

    // ─── T-13.1-NAVER-LABEL-01: Naver 라벨 색 mirror 보존 ─────────────────
    test('T-13.1-NAVER-LABEL-01: Naver 라벨 색 0xFFFFFFFF 보존', () {
      expect(_kNaverLabelExpected.toARGB32(), 0xFFFFFFFF);
    });
  });

  group('BrandedSocialButton — Phase 13.1 Gap-1 X2 wide 자상 통째 buttons', () {
    // ─── T-13.1-X2-CLIPRRECT-01: Material+borderRadius + Image (Kakao)
    //
    // **Plan 14 deviation 정정 (2026-05-09 사용자 시각 검증 후):** 1차
    // 디자인의 ClipRRect 폐기 — 자상의 baked-in 모서리 (Naver 사각 / Kakao
    // 7.2px scaled / Google rx=19.5 pill) 가 시각 권위, ClipRRect 12dp 강제
    // 가 더블 클리핑 결함. test ID 는 traceability 보존, assertion 만 갱신.
    //
    // **Phase 13.3 R2 caller-fix (Wave 3 D-117):** Kakao 가 wide PNG →
    // Universal Layout Pattern (Material + Row + SvgPicture.string +
    // Text) 로 재설계되어 Image 위제 부재. Image 검증 폐기, ClipRRect
    // 폐기 가드만 보존 (현재 가능한 최소 회귀 가드). Wave 4 widget tree
    // assertion 신규 (Material bg #FEE500 + SvgPicture.string +
    // Text(authKakaoSignIn ARB)) 가 본 test 의 의미 대체 책임.
    testWidgets('T-13.1-X2-CLIPRRECT-01: KakaoSpec build() ClipRRect 폐기 가드 '
        '(Phase 13.3 R2 — Universal Layout Pattern 후 Image 검증 폐기)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BrandedSocialButton.kakao(label: '카카오 로그인', onPressed: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // ClipRRect 폐기 검증 — 본 widget 트리에 ClipRRect 없음 (Plan 14
      // deviation 회귀 가드, 더블 클리핑 차단).
      expect(find.byType(ClipRRect), findsNothing);
    });

    // ─── T-13.1-X2-CLIPRRECT-02: Material+borderRadius + SvgPicture (Google)
    testWidgets(
      'T-13.1-X2-CLIPRRECT-02: GoogleSpec build() Material+borderRadius + '
      'SvgPicture (Plan 14 deviation: BoxFit.contain + no ClipRRect)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: BrandedSocialButton.google(
                label: 'Sign in with Google',
                onPressed: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Google SVG 의 baked-in pill (rx=19.5) 모양 보존 — ClipRRect 폐기
        // 회귀 가드.
        expect(find.byType(ClipRRect), findsNothing);
        // 자상 형식 dispatch 자체는 sealed switch 검증 (T-13.1-SPEC-01 의
        // GoogleSpec.assetType == AssetType.svg) 가 보장. 본 test 는 Image
        // 부재 검증 (Google 은 SVG 이므로 Image.asset 위제는 트리에 없어야 함).
        expect(find.byType(Image), findsNothing);
      },
    );

    // ─── T-13.1-X2-FULLWIDTH-01: SizedBox(width: double.infinity) 검증 ────
    testWidgets('T-13.1-X2-FULLWIDTH-01: NaverSpec build() SizedBox '
        'width: double.infinity 강제 sizing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: BrandedSocialButton.naver(
                label: '네이버로 시작하기',
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // BrandedSocialButton 내부 SizedBox 가 부모 width (300dp) 까지 확장.
      // RenderBox layout 후 width = 300 이어야 (full-width 패턴).
      final renderBox = tester.renderObject<RenderBox>(
        find.byType(BrandedSocialButton),
      );
      expect(renderBox.size.width, 300.0);
      // 높이는 BrandSpec.height (48dp) 와 일치 — Naver/Kakao 자상 통째 buttons.
      expect(renderBox.size.height, 48.0);
    });

    // ─── T-13.1-X2-LOCALE-FALLBACK-01 폐기 (Phase 13.3 R2) ────────────────
    //
    // Phase 13.3 R2 — Kakao 가 wide PNG (locale × theme leaf 디렉토리) →
    // inline SVG (`_kKakaoSymbolSvg` + Universal Layout Pattern) 로 전환되어
    // locale 분기 자체 부재. _iconAssetFor 의 Kakao branch 도 폐기되어
    // ja → en path fallback 가드의 검증 대상 자체 소실. Wave 4 widget tree
    // assertion 신규로 Material bg #FEE500 + Text(authKakaoSignIn ARB locale
    // 해석) 검증 책임 분리.

    // ─── T-13.1-X2-APPLE-PRESERVE-01: AppleSpec 분기 변경 0 회귀 가드 ──────
    testWidgets('T-13.1-X2-APPLE-PRESERVE-01: AppleSpec build() '
        'SignInWithAppleButton 위임 보존 (Gap-1 영향 없음)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrandedSocialButton.apple(
              label: 'Sign in with Apple',
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Apple 분기는 SDK 위제 위임 — ClipRRect + Image 패턴 미적용 정상.
      // SignInWithAppleButton 위제가 트리에 존재해야 함.
      expect(find.byType(SignInWithAppleButton), findsOneWidget);
    });

    // ─── T-13.1-A11Y-SEMANTICS-01: Semantics 액션 핸들러 + label 회귀 가드 ─
    //
    // **Phase 13.1 REVIEW iter2 CR-01 정정 (2026-05-10):** iter1 fix 가
    // `Semantics(button: true, excludeSemantics: true)` 만 추가하고 `onTap`
    // 매개변수 미전달 → 자식 InkWell 의 GestureSemantics 가 트리에서 drop
    // 되어 TalkBack/VoiceOver 사용자가 라벨은 듣지만 활성화 불가 회귀.
    // 본 test 는 (1) button + label + enabled 3 노출 + (2) hasTapAction
    // (시멘틱 액션 핸들러 명시) 둘 다 검증 — `tester.tap` (포인터) 만으로는
    // 검출 불가능한 a11y silent 회귀 차단.
    testWidgets(
      'T-13.1-A11Y-SEMANTICS-01: KakaoSpec _renderActiveButton — button + '
      'label + onTap action 시멘틱 노드 노출 (iter2 CR-01 회귀 가드)',
      (tester) async {
        final SemanticsHandle semHandle = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: BrandedSocialButton.kakao(
                label: '카카오 로그인',
                onPressed: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        try {
          // BrandedSocialButton 의 외부 Semantics 노드 검증.
          // matchesSemantics(hasTapAction: true) 가 시멘틱 트리에 onTap
          // 액션 핸들러가 정상 등록되었는지 단독 검증 — iter1 의
          // `Semantics(button: true, excludeSemantics: true)` + onTap 미전달
          // 패턴이 회귀하면 hasTapAction=false 로 RED.
          expect(
            tester.getSemantics(find.byType(BrandedSocialButton)),
            matchesSemantics(
              isButton: true,
              hasTapAction: true,
              hasEnabledState: true,
              isEnabled: true,
              label: '카카오 로그인',
            ),
            reason:
                'iter2 CR-01 회귀 가드 — Semantics(onTap: onPressed) 미전달 시 '
                'TalkBack/VoiceOver 사용자가 활성화 불가. '
                'button/label/onTap 셋 모두 시멘틱 트리에 노출 의무. '
                'hasTapAction=false RED 시 iter1 회귀 패턴 재발.',
          );
        } finally {
          semHandle.dispose();
        }
      },
    );

    // ─── T-13.1-A11Y-SEMANTICS-02: 비활성 상태 hasTapAction 부재 ─────────
    testWidgets('T-13.1-A11Y-SEMANTICS-02: NaverSpec onPressed=null → '
        'hasTapAction false + isEnabled false (a11y 비활성 표현)', (tester) async {
      final SemanticsHandle semHandle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BrandedSocialButton.naver(
              label: '네이버로 시작하기',
              onPressed: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      try {
        expect(
          tester.getSemantics(find.byType(BrandedSocialButton)),
          matchesSemantics(
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            label: '네이버로 시작하기',
            // onPressed=null 이면 Semantics.onTap 도 null → hasTapAction
            // false.
          ),
          reason:
              'onPressed=null → enabled=false + onTap 핸들러 미등록. '
              '비활성 상태도 button/label 은 노출 (TalkBack 가 "비활성 버튼" 안내).',
        );
      } finally {
        semHandle.dispose();
      }
    });

    // ─── Phase 13.2 — FacebookSpec active 전환 RED gate ───────────────────
    //
    // **Phase 13.2 R5/R6 acceptance + Wave 0 옵션 A pivot (13.2-WAVE0-LOCK.md):**
    // FacebookSpec sealed switch active 전환 (UnsupportedError throw 폐기) +
    // 신규 `_renderFacebookButton` 함수 (Apple SignInWithAppleButton 패턴
    // mirror, Theme.brightness 자동 분기, 18dp Image.asset + Text label)
    // 의무. D-95 = AssetType.png, D-94 = theme 필드 부재 (Primary 단독),
    // D-96 = Google 패턴 (locale 독립, 단일 path
    // 'assets/brand/facebook/facebook_login.png').
    //
    // 본 단락의 두 test 는 Wave 1+ 진입 시점에 RED — Wave 1 의
    // branded_social_button.dart 변경 (FacebookSpec sealed switch case 갱신 +
    // _renderFacebookButton 신규 + _iconAssetFor Facebook branch active) 후
    // GREEN 자동 전환. T-13.1-X2-FACEBOOK-PRESERVE-01 sentinel 폐기 의도
    // 명시 — UnsupportedError throw 검증 의도가 Phase 13.2 R5 acceptance 와
    // 의미 반전.
    testWidgets(
      'T-13.2-FACEBOOK-ACTIVE-01: BrandedSocialButton.facebook() build() → '
      'Image.asset (D-95 PNG) + Text(authFacebookSignIn ARB) 단일 매치 '
      '(R5/R6 + 옵션 A pivot _renderFacebookButton 호출 검증)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: BrandedSocialButton.facebook(
                label: 'Continue with Facebook',
                onPressed: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // BrandedSocialButton 위제 단일 매치 — UnsupportedError throw 폐기.
        expect(find.byType(BrandedSocialButton), findsOneWidget);

        // D-95 PNG — Image.asset 1 매치 (Apple 패턴 mirror, 18dp icon 슬롯).
        // 옵션 A pivot — Kakao/Naver 의 wide 자상 통째 buttons 패턴 미적용
        // (Facebook 자상은 square logo 단독, _renderActiveButton 호출 불가).
        expect(find.byType(Image), findsOneWidget);

        // 신규 _renderFacebookButton 의 ARB 라벨 layer — Apple/Facebook 의
        // 외부 layer 단독 권위 패턴 일관 (Phase 13.1 D-82 ARB 머레).
        // 본 test 는 caller 가 전달한 label 이 위제 트리에 렌더되는지 검증
        // (외부 _renderFacebookButton 의 Text 위제 의무).
        expect(find.text('Continue with Facebook'), findsOneWidget);
      },
    );

    // ─── T-13.2-FACEBOOK-A11Y-01/02: Facebook a11y semantics 회귀 가드 ─────
    //
    // **Phase 13.2 REVIEW WR-02 정정 (2026-05-13):** Phase 13.1 의 Kakao/
    // Naver `T-13.1-A11Y-SEMANTICS-01/02` 와 동일 패턴으로 Facebook
    // `_renderFacebookButton` Semantics 5 invariant (button + hasTapAction +
    // hasEnabledState + isEnabled + label) 회귀 가드. iter2 CR-01 silent
    // drift 패턴 (Semantics(onTap: onPressed) 누락 → InkWell GestureSemantics
    // drop) 을 Facebook 분기에서도 surface 의무.
    testWidgets('T-13.2-FACEBOOK-A11Y-01: Facebook 활성 → '
        'matchesSemantics(button, hasTapAction, isEnabled, label)', (
      tester,
    ) async {
      final SemanticsHandle semHandle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BrandedSocialButton.facebook(
              label: 'Continue with Facebook',
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      try {
        expect(
          tester.getSemantics(find.byType(BrandedSocialButton)),
          matchesSemantics(
            isButton: true,
            hasTapAction: true,
            hasEnabledState: true,
            isEnabled: true,
            label: 'Continue with Facebook',
          ),
          reason:
              'WR-02 회귀 가드 — Facebook 활성 시 button + label + onTap '
              '시멘틱 트리 노출 의무. hasTapAction=false RED 시 iter1 패턴 '
              '(Semantics.onTap 미전달 → GestureSemantics drop) 재발.',
        );
      } finally {
        semHandle.dispose();
      }
    });

    testWidgets('T-13.2-FACEBOOK-A11Y-02: Facebook 비활성 → '
        'isEnabled: false + hasTapAction false', (tester) async {
      final SemanticsHandle semHandle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BrandedSocialButton.facebook(
              label: 'Continue with Facebook',
              onPressed: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      try {
        expect(
          tester.getSemantics(find.byType(BrandedSocialButton)),
          matchesSemantics(
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            label: 'Continue with Facebook',
          ),
          reason:
              'WR-02 회귀 가드 — onPressed=null → enabled=false + onTap '
              '핸들러 미등록. 비활성 상태도 button/label 은 노출 (TalkBack 가 '
              '"비활성 버튼" 안내).',
        );
      } finally {
        semHandle.dispose();
      }
    });

    // ─── T-13.2-FACEBOOK-DISABLED-01: 비활성 상태 시각 cue 회귀 가드 ───────
    //
    // **Phase 13.2 REVIEW CR-01 정정 (2026-05-13):** 비활성 시 시각 disabled
    // cue 부재 회귀 가드. `social_button.dart` 의 docstring 약속 ("Material
    // default disabled 외관") 과 일치하도록 `_renderFacebookButton` 이
    // `Opacity(0.5)` wrap + fg/outline faded 분기를 적용. 본 test 는 Opacity
    // descendant 단독 검증 — 색 변화는 별 layer (fgColor copyWith) 가 책임.
    testWidgets('T-13.2-FACEBOOK-DISABLED-01: onPressed=null → 시각 disabled cue '
        '(Opacity opacity < 1.0)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BrandedSocialButton.facebook(
              label: 'Continue with Facebook',
              onPressed: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // BrandedSocialButton 하위 Opacity 위제 단독 매칭 — descendant 검색.
      final opacityFinder = find.descendant(
        of: find.byType(BrandedSocialButton),
        matching: find.byType(Opacity),
      );
      expect(
        opacityFinder,
        findsOneWidget,
        reason:
            'CR-01 회귀 가드 — onPressed=null 시 Opacity wrap 부재. '
            '_renderFacebookButton 의 Material 3 disabled state cue 누락 회귀.',
      );

      // Opacity.opacity 값이 1.0 미만 (시각 fade) 검증.
      final opacity = tester.widget<Opacity>(opacityFinder);
      expect(
        opacity.opacity,
        lessThan(1.0),
        reason:
            'CR-01 회귀 가드 — Opacity.opacity 가 1.0 이면 비활성 시각 cue 0. '
            'Material 3 disabled state spec 위반.',
      );
    });

    // ─── T-13.2-FACEBOOK-ENABLED-01: 활성 상태 Opacity 1.0 보존 가드 ───────
    testWidgets(
      'T-13.2-FACEBOOK-ENABLED-01: onPressed=() {} → Opacity 1.0 (활성 시각 보존)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: BrandedSocialButton.facebook(
                label: 'Continue with Facebook',
                onPressed: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final opacityFinder = find.descendant(
          of: find.byType(BrandedSocialButton),
          matching: find.byType(Opacity),
        );
        expect(opacityFinder, findsOneWidget);
        final opacity = tester.widget<Opacity>(opacityFinder);
        expect(
          opacity.opacity,
          1.0,
          reason: '활성 상태 시 Opacity 1.0 보존 — Material 3 active state 일관.',
        );
      },
    );

    testWidgets(
      'T-13.2-FACEBOOK-ASSET-01: BrandedSocialButton.facebook() Image.asset '
      'path = "assets/brand/facebook/facebook_login.png" (D-96 Google 패턴, '
      'locale 독립 — _iconAssetFor FacebookSpec branch active 검증)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: BrandedSocialButton.facebook(
                label: 'Continue with Facebook',
                onPressed: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final imageWidget = tester.widget<Image>(find.byType(Image));
        // Phase 13.2 REVIEW IN-03 정정 (2026-05-13): cacheWidth/cacheHeight
        // 추가로 Image.asset 이 ResizeImage(AssetImage) wrapper 로 감싸짐.
        // 본 test 는 underlying AssetImage 의 assetName 검증이 목적이므로
        // ResizeImage.imageProvider 로 unwrap 후 cast.
        final ImageProvider rawProvider = imageWidget.image;
        final AssetImage assetImage = rawProvider is ResizeImage
            ? rawProvider.imageProvider as AssetImage
            : rawProvider as AssetImage;

        // D-96 Google 패턴 — locale 독립 (ko/en/ja 분기 부재), 단일 path.
        // Meta Primary Logo PNG (2084×2084 square, 'f' 마크 + #1877F2 원형).
        // 18dp icon 슬롯 fit — Apple SignInWithAppleButton 패턴 mirror.
        expect(
          assetImage.assetName,
          'assets/brand/facebook/facebook_login.png',
          reason:
              'Phase 13.2 R6 + D-96 — _iconAssetFor FacebookSpec branch '
              'active 검증. Wave 1 코드 마이그 후 GREEN.',
        );
      },
    );

    // ─── T-13.1-PLACEHOLDER-01: LineSpec build() → placeholder 회귀 가드 ────
    //
    // **Phase 13.1 REVIEW iter3 WR-01 정정 (2026-05-10):** iter2 의 WR-02
    // 정정 (`_renderPlaceholder` 시그니처에서 `VoidCallback? onPressed`
    // 제거 + 호출 site 인자 제거) 이 widget pump test 0 인 상태에서 silent
    // 통과했다 — `T-13.1-FACTORY-01` 는 instance 만 생성하고 build() 미도달.
    // 본 test 는 LineSpec build() 분기를 실제 pump 하여 (1) ARB 해석 라벨
    // (`authBrandAssetMissing`) 표시, (2) InkWell/GestureDetector 부재
    // (placeholder 는 탭 처리 미지원 — iter2 docstring 약속), (3) 회색
    // disabled 외관 (R10) 회귀 가드 셋 동시 검증.
    testWidgets(
      'T-13.1-PLACEHOLDER-01: LineSpec build() → 회색 disabled placeholder + '
      'ARB authBrandAssetMissing 라벨 + InkWell/GestureDetector 부재 '
      '(iter2 WR-02 시그니처 변경 회귀 가드)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: BrandedSocialButton.line(
                label: 'Continue with LINE',
                onPressed: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // iter2 WR-02 정정 회귀 가드 — `_renderPlaceholder` 는 탭 처리
        // 책임 0 (InkWell/GestureDetector 미사용). onPressed 가 caller 에서
        // 전달돼도 placeholder 가 무시 — 자상 commit 전 비활성 외관 보장.
        expect(find.byType(InkWell), findsNothing);
        expect(find.byType(GestureDetector), findsNothing);
        // ARB 해석 라벨 검증 — en locale 의 `authBrandAssetMissing` placeholder
        // ('Asset missing: {label}') 가 정상 해석되어 'Continue with LINE'
        // 로 보간된 결과 노출.
        expect(find.text('Asset missing: Continue with LINE'), findsOneWidget);
        // R10 disabled 외관 검증 — Material 의 회색 배경 (Colors.grey.shade200)
        // + iter2 docstring 의 "회색 disabled 외관 (R10)" 약속 회귀 가드.
        // _renderPlaceholder 의 Material 위제만 단독 매칭하기 위해
        // descendantOf 로 BrandedSocialButton 하위 first Material 추출.
        final materialFinder = find.descendant(
          of: find.byType(BrandedSocialButton),
          matching: find.byType(Material),
        );
        final material = tester.widget<Material>(materialFinder.first);
        expect(material.color, Colors.grey.shade200);
      },
    );

    // ─── T-13.1-PLACEHOLDER-02: WechatSpec build() → placeholder 회귀 가드 ──
    testWidgets(
      'T-13.1-PLACEHOLDER-02: WechatSpec build() → 회색 disabled placeholder + '
      'ARB authBrandAssetMissing 라벨 + InkWell/GestureDetector 부재 '
      '(LineSpec 와 동일 분기 회귀 가드)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: BrandedSocialButton.wechat(
                label: 'Continue with WeChat',
                onPressed: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(InkWell), findsNothing);
        expect(find.byType(GestureDetector), findsNothing);
        expect(
          find.text('Asset missing: Continue with WeChat'),
          findsOneWidget,
        );
      },
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // Phase 13.3 Wave 4 — R1/R2/R3/R5 widget tree structural assertion (D-117)
  // ════════════════════════════════════════════════════════════════════════
  //
  // RESEARCH §Wave 4.2 widget tree assertion 매트릭스 + Pattern D
  // (find.byWidgetPredicate). brand verbatim hex literal drift 자동 검출 +
  // wide PNG 자상 미참조 acceptance + Naver carve-out (#03C75A NCloud SSO)
  // 보호. Apple SDK Theme.brightness 자동 매핑 (R5) 검증.
  //
  // Pitfall 3: `_settleAssets(tester)` helper 가 SvgPicture.string 비동기
  // vector_graphics 로드 wait — Kakao/Naver render assertion 전 의무 호출.
  group(
    'BrandedSocialButton — Phase 13.3 widget tree assertion (R1/R2/R3/R5)',
    () {
      // ─── T-13.3-GOOGLE-RENDER-01 (R1) ────────────────────────────────────
      testWidgets('T-13.3-GOOGLE-RENDER-01: Google render — SvgPicture + 1dp '
          'BorderSide + authGoogleSignIn Text (R1)', (tester) async {
        await tester.pumpWidget(
          _wrapForR1R2R3(
            BrandedSocialButton.google(
              label: 'Sign in with Google',
              onPressed: () {},
            ),
            brightness: Brightness.light,
          ),
        );
        await _settleAssetsForR1R2R3(tester);

        // 1. SvgPicture (Google Identity btn_signin_icon.svg) >= 1
        expect(
          find.byType(SvgPicture),
          findsAtLeastNWidgets(1),
          reason:
              'Google render 가 SvgPicture (btn_signin_icon.svg) 보유 의무 (R1).',
        );

        // 2. Material shape = RoundedRectangleBorder + side.width == 1.0
        expect(
          find.byWidgetPredicate((Widget w) {
            if (w is! Material) return false;
            final ShapeBorder? shape = w.shape;
            if (shape is! RoundedRectangleBorder) return false;
            return shape.side.width == 1.0;
          }),
          findsAtLeastNWidgets(1),
          reason: 'Google 1dp BorderSide outline 의무 (R1 Identity Guidelines).',
        );

        // 3. ARB authGoogleSignIn 라벨 Text
        expect(find.text('Sign in with Google'), findsOneWidget);
      });

      // ─── T-13.3-GOOGLE-STROKE-LIGHT-01 (R1) ──────────────────────────────
      testWidgets('T-13.3-GOOGLE-STROKE-LIGHT-01: Google light theme stroke '
          'Color(0xFF747775) (R1 verbatim)', (tester) async {
        await tester.pumpWidget(
          _wrapForR1R2R3(
            BrandedSocialButton.google(
              label: 'Sign in with Google',
              onPressed: () {},
            ),
            brightness: Brightness.light,
          ),
        );
        await _settleAssetsForR1R2R3(tester);

        expect(
          find.byWidgetPredicate((Widget w) {
            if (w is! Material) return false;
            final ShapeBorder? shape = w.shape;
            if (shape is! RoundedRectangleBorder) return false;
            return shape.side.color == const Color(0xFF747775);
          }),
          findsAtLeastNWidgets(1),
          reason:
              'Google light theme stroke 의무 Color(0xFF747775) — Google '
              'Identity Guidelines verbatim (R1).',
        );
      });

      // ─── T-13.3-GOOGLE-STROKE-DARK-01 (R1) ───────────────────────────────
      testWidgets('T-13.3-GOOGLE-STROKE-DARK-01: Google dark theme stroke '
          'Color(0xFF8E918F) (R1 verbatim)', (tester) async {
        await tester.pumpWidget(
          _wrapForR1R2R3(
            BrandedSocialButton.google(
              label: 'Sign in with Google',
              onPressed: () {},
            ),
            brightness: Brightness.dark,
          ),
        );
        await _settleAssetsForR1R2R3(tester);

        expect(
          find.byWidgetPredicate((Widget w) {
            if (w is! Material) return false;
            final ShapeBorder? shape = w.shape;
            if (shape is! RoundedRectangleBorder) return false;
            return shape.side.color == const Color(0xFF8E918F);
          }),
          findsAtLeastNWidgets(1),
          reason:
              'Google dark theme stroke 의무 Color(0xFF8E918F) — Google '
              'Identity Guidelines verbatim (R1).',
        );
      });

      // ─── T-13.3-KAKAO-RENDER-01 (R2) ─────────────────────────────────────
      testWidgets('T-13.3-KAKAO-RENDER-01: Kakao render — Material #FEE500 + '
          'SvgPicture (말풍선 symbol inline) + authKakaoSignIn Text (R2)', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrapForR1R2R3(
            BrandedSocialButton.kakao(
              label: 'Login with Kakao',
              onPressed: () {},
            ),
            brightness: Brightness.light,
          ),
        );
        await _settleAssetsForR1R2R3(tester);

        // 1. Material bg color == #FEE500 (Kakao yellow verbatim)
        expect(
          find.byWidgetPredicate((Widget w) {
            return w is Material && w.color == const Color(0xFFFEE500);
          }),
          findsOneWidget,
          reason: 'Kakao render 가 #FEE500 bg Material 단일 보유 의무 (R2).',
        );

        // 2. SvgPicture (말풍선 symbol SvgPicture.string inline)
        expect(
          find.byType(SvgPicture),
          findsAtLeastNWidgets(1),
          reason: 'Kakao 말풍선 symbol SVG inline render 의무 (R2 + D-105).',
        );

        // 3. ARB authKakaoSignIn 라벨 Text
        expect(find.text('Login with Kakao'), findsOneWidget);
      });

      // ─── T-13.3-KAKAO-WIDE-PNG-MISSING-01 (R2 + R7) ──────────────────────
      testWidgets('T-13.3-KAKAO-WIDE-PNG-MISSING-01: Kakao render 가 '
          'kakao_login_large_wide.png 미참조 (R2 + R7 wide asset 폐기)', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrapForR1R2R3(
            BrandedSocialButton.kakao(
              label: 'Login with Kakao',
              onPressed: () {},
            ),
            brightness: Brightness.light,
          ),
        );
        await _settleAssetsForR1R2R3(tester);

        expect(
          find.byWidgetPredicate((Widget w) {
            if (w is! Image) return false;
            final ImageProvider image = w.image;
            if (image is! AssetImage) return false;
            return image.assetName.contains('kakao_login_large_wide') ||
                image.assetName.contains('kakao_login_medium_wide');
          }),
          findsNothing,
          reason:
              'Phase 13.3 R7 — wide PNG 자상 (kakao_login_*_wide.png) 미참조 '
              '의무. Universal Layout Pattern (SvgPicture.string symbol) '
              '으로 통째 전환.',
        );
      });

      // ─── T-13.3-NAVER-RENDER-01 (R3) ─────────────────────────────────────
      testWidgets('T-13.3-NAVER-RENDER-01: Naver render — Material #03A94D + '
          'SvgPicture (N symbol inline) + authNaverSignIn Text (R3)', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrapForR1R2R3(
            BrandedSocialButton.naver(
              label: 'Log in with NAVER',
              onPressed: () {},
            ),
            brightness: Brightness.light,
          ),
        );
        await _settleAssetsForR1R2R3(tester);

        // 1. Material bg color == #03A94D (NAVER ID 로그인 BI verbatim)
        expect(
          find.byWidgetPredicate((Widget w) {
            return w is Material && w.color == const Color(0xFF03A94D);
          }),
          findsOneWidget,
          reason: 'Naver render 가 #03A94D bg Material 단일 보유 의무 (R3 BI).',
        );

        // 2. SvgPicture (N symbol SvgPicture.string inline)
        expect(
          find.byType(SvgPicture),
          findsAtLeastNWidgets(1),
          reason: 'Naver N symbol SVG inline render 의무 (R3 + D-105).',
        );

        // 3. ARB authNaverSignIn 라벨 Text
        expect(find.text('Log in with NAVER'), findsOneWidget);
      });

      // ─── T-13.3-NAVER-WIDE-PNG-MISSING-01 (R3 + R7) ──────────────────────
      testWidgets('T-13.3-NAVER-WIDE-PNG-MISSING-01: Naver render 가 '
          'naver_login_h48_wide.png 미참조 (R3 + R7 wide asset 폐기)', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrapForR1R2R3(
            BrandedSocialButton.naver(
              label: 'Log in with NAVER',
              onPressed: () {},
            ),
            brightness: Brightness.light,
          ),
        );
        await _settleAssetsForR1R2R3(tester);

        expect(
          find.byWidgetPredicate((Widget w) {
            if (w is! Image) return false;
            final ImageProvider image = w.image;
            if (image is! AssetImage) return false;
            return image.assetName.contains('naver_login_h48_wide') ||
                image.assetName.contains('naver_login_h56_wide');
          }),
          findsNothing,
          reason:
              'Phase 13.3 R7 — wide PNG 자상 (naver_login_h*_wide.png) 미참조 '
              '의무. Universal Layout Pattern (SvgPicture.string symbol) '
              '으로 통째 전환.',
        );
      });

      // ─── T-13.3-NAVER-CARVE-OUT-01 (R3 carve-out) ────────────────────────
      testWidgets(
        'T-13.3-NAVER-CARVE-OUT-01: Naver render 가 #03C75A (NCloud SSO '
        '회사 브랜드) 미사용 (R3 carve-out 보호)',
        (tester) async {
          await tester.pumpWidget(
            _wrapForR1R2R3(
              BrandedSocialButton.naver(
                label: 'Log in with NAVER',
                onPressed: () {},
              ),
              brightness: Brightness.light,
            ),
          );
          await _settleAssetsForR1R2R3(tester);

          expect(
            find.byWidgetPredicate((Widget w) {
              return w is Material && w.color == const Color(0xFF03C75A);
            }),
            findsNothing,
            reason:
                'R3 carve-out — #03C75A 는 NAVER Corp + NCloud SSO 별도 brand. '
                'NAVER ID 로그인 BI 의 #03A94D 단독 강제. drift 시 즉시 RED.',
          );
        },
      );

      // ─── T-13.3-APPLE-LIGHT-BLACK-01 (R5) ────────────────────────────────
      testWidgets('T-13.3-APPLE-LIGHT-BLACK-01: Apple light theme → '
          'SignInWithAppleButtonStyle.black (R5 자동 매핑)', (tester) async {
        await tester.pumpWidget(
          _wrapForR1R2R3(
            BrandedSocialButton.apple(
              label: 'Sign in with Apple',
              onPressed: () {},
            ),
            brightness: Brightness.light,
          ),
        );
        await tester.pumpAndSettle();

        final SignInWithAppleButton appleBtn = tester
            .widget<SignInWithAppleButton>(find.byType(SignInWithAppleButton));
        expect(
          appleBtn.style,
          SignInWithAppleButtonStyle.black,
          reason:
              'R5 Apple light theme → .black 자동 매핑 의무. caller 측 '
              'style: parameter 폐기, Theme.brightness 단독 권위.',
        );
      });

      // ─── T-13.3-APPLE-DARK-WHITE-01 (R5) ─────────────────────────────────
      testWidgets('T-13.3-APPLE-DARK-WHITE-01: Apple dark theme → '
          'SignInWithAppleButtonStyle.white (R5 자동 매핑)', (tester) async {
        await tester.pumpWidget(
          _wrapForR1R2R3(
            BrandedSocialButton.apple(
              label: 'Sign in with Apple',
              onPressed: () {},
            ),
            brightness: Brightness.dark,
          ),
        );
        await tester.pumpAndSettle();

        final SignInWithAppleButton appleBtn = tester
            .widget<SignInWithAppleButton>(find.byType(SignInWithAppleButton));
        expect(
          appleBtn.style,
          SignInWithAppleButtonStyle.white,
          reason:
              'R5 Apple dark theme → .white 자동 매핑 의무. caller 측 '
              'style: parameter 폐기, Theme.brightness 단독 권위.',
        );
      });
    },
  );
}

/// Phase 13.3 Wave 4 — `_wrap` 헬퍼 (위제 트리 assertion 용).
///
/// `branded_social_button_golden_test.dart` 의 `_wrap` helper 와 동일 구조 —
/// AppTheme.light/dark 주입 (`context.appSpacing` ThemeExtension 의무) + en
/// locale lock + ARB delegate 명시. golden 과의 환경 일관성 유지.
Widget _wrapForR1R2R3(Widget child, {required Brightness brightness}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(child: SizedBox(width: 360, child: child)),
    ),
  );
}

/// Phase 13.3 Wave 4 — `_settleAssets` 헬퍼 (SvgPicture.string 비동기 wait).
///
/// `branded_social_button_golden_test.dart` 의 `_settleAssets` 와 동일 패턴 —
/// (1) Image.asset 강제 디코딩 + (2) SvgPicture vector_graphics 비동기 로드
/// 흡수를 위한 200ms delay + (3) 최종 pumpAndSettle. Pitfall 3 가드.
Future<void> _settleAssetsForR1R2R3(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpAndSettle();
    for (final Element element in find.byType(Image).evaluate().toList()) {
      final Image widget = element.widget as Image;
      await precacheImage(widget.image, element);
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  });
  await tester.pumpAndSettle();
}
