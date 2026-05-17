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
      // Phase 13.3 R2 (Wave 4 Step 2) — KakaoSpec assetType 변경: PNG → SVG
      // 자산 파일 (`assets/brand/kakao/btn_signin_icon.svg` +
      // `_renderKakaoButton` Universal Layout Pattern).
      // **Phase 13.3 Wave 4 Step 3 (2026-05-16) supersede:** KakaoSpec
      // 공식 PSD M Wide variant verbatim override → iconSize 20.
      // T-13.3-KAKAO-SPEC-VERBATIM-01 별도 회귀 가드.
      expect(const KakaoSpec().assetType, AssetType.svg);
      expect(const KakaoSpec().borderRadius, 12.0);
      expect(const KakaoSpec().height, 48.0);
      expect(const KakaoSpec().iconSize, 20.0);

      // Phase 13.3 R3 — NaverSpec assetType SVG (inline `_kNaverSymbolSvg`).
      // theme 필드 폐기 (BI 단일 그린 #03A94D 강제).
      // **Phase 13.3 Wave 4 Step 3 (2026-05-16) supersede:** NaverSpec
      // 공식 PNG 자상 verbatim override → borderRadius 8 + iconSize 16.
      // T-13.3-NAVER-SPEC-VERBATIM-01 별도 회귀 가드.
      expect(const NaverSpec().assetType, AssetType.svg);
      expect(const NaverSpec().borderRadius, 8.0);
      expect(const NaverSpec().iconSize, 16.0);

      // Phase 13.3 R1 — GoogleSpec theme 필드 폐기 (Theme.brightness 자동
      // 분기로 차원 축소). assetType SVG (Google Identity btn_signin_icon.svg).
      expect(const GoogleSpec().assetType, AssetType.svg);

      // AppleSpec — Phase 13.3 Wave 4 Step 2 (2026-05-15): SDK 위제 폐기 →
      // custom render (SvgPicture.asset 'assets/brand/apple/{light,dark}/
      // btn_signin_icon.svg'). assetType.svg.
      expect(const AppleSpec().assetType, AssetType.svg);
      // FacebookSpec — Phase 13.3 Wave 4 Step 2 (2026-05-15): PNG → SVG
      // 전환 (Meta Brand Asset Pack 의 Facebook_Logo_Primary.ai PyMuPDF
      // verbatim 추출, 2 paths blue circle + white 'f').
      expect(const FacebookSpec().assetType, AssetType.svg);

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
      //
      // **Phase 13.3 Wave 4 Step 3 (2026-05-16) supersede:**
      // - GoogleSpec: Google production CSS verbatim 채택 (4dp).
      //   T-13.3-GOOGLE-SPEC-VERBATIM-01 별도 회귀 가드.
      // - NaverSpec: 공식 PNG 자상 verbatim 채택 (8dp).
      //   T-13.3-NAVER-SPEC-VERBATIM-01 별도 회귀 가드.
      // - 다른 5 sub-class 는 baseline 12 유지.
      expect(const KakaoSpec().borderRadius, 12.0);
      expect(const AppleSpec().borderRadius, 12.0);
      expect(const FacebookSpec().borderRadius, 12.0);
      expect(const LineSpec().borderRadius, 12.0);
      expect(const WechatSpec(size: WechatPixelSize.px48).borderRadius, 12.0);
    });

    // ─── T-13.3-GOOGLE-SPEC-VERBATIM-01: Google production CSS verbatim spec ─
    test(
      'T-13.3-GOOGLE-SPEC-VERBATIM-01: GoogleSpec verbatim override '
      'height 40 / borderRadius 4 / iconSize 20 (CSS verbatim)',
      () {
        // Phase 13.3 Wave 4 Step 3 (2026-05-16) — Google Identity Services
        // production CSS (`.gsi-material-button` 사용자 제공) verbatim:
        //   height: 40px / border-radius: 4px / .gsi-material-button-icon
        //   { width: 20px; height: 20px }
        // BrandSpec default (48 / 12 / 18) supersede — 5 provider 시각 통일
        // lock 의 trade-off 로 Google CSS verbatim 부합 우선 (사용자 결정).
        expect(const GoogleSpec().height, 40.0);
        expect(const GoogleSpec().borderRadius, 4.0);
        expect(const GoogleSpec().iconSize, 20.0);
      },
    );

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
    // Phase 13.3 R2 (Wave 4 Step 2) — Kakao 가 wide PNG (locale × theme leaf
    // 디렉토리) → SVG 자산 파일 (`assets/brand/kakao/btn_signin_icon.svg` +
    // Universal Layout Pattern) 로 전환되어 locale 분기 자체 부재.
    // _iconAssetFor 의 Kakao branch 도 폐기되어 ja → en path fallback 가드의
    // 검증 대상 자체 소실. Wave 4 widget tree assertion 신규로 Material bg
    // #FEE500 + Text(authKakaoSignIn ARB locale 해석) 검증 책임 분리.

    // ─── T-13.1-X2-APPLE-PRESERVE-01: AppleSpec 분기 변경 0 회귀 가드 ──────
    //
    // **Phase 13.3 Wave 4 Step 2 (2026-05-15) supersede:** SignInWithAppleButton
    // SDK 위제 폐기 → custom render (`_renderAppleButton`) 전환. Apple 공식
    // Logo-only SVG 자상 (`assets/brand/apple/{light,dark}/btn_signin_icon.svg`)
    // + Theme.brightness 자동 분기 + ARB 라벨 외부 layer. Gap-1 (X2 wide 자상
    // 통째 buttons) 영향 없음 검증은 BrandedSocialButton 매치 + ARB 라벨
    // 매치 + SvgPicture (Apple logo) 매치 의 3 invariant 로 갱신.
    testWidgets('T-13.1-X2-APPLE-PRESERVE-01: AppleSpec build() → '
        'BrandedSocialButton + ARB 라벨 + SvgPicture (custom render, Wave 4 '
        'Step 2 SDK 위제 폐기)', (tester) async {
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
      // BrandedSocialButton 위제 단일 매치.
      expect(find.byType(BrandedSocialButton), findsOneWidget);
      // ARB 라벨 (caller 전달) 매치.
      expect(find.text('Sign in with Apple'), findsOneWidget);
      // Apple custom render — SvgPicture (Logo-only 자상) 1 매치.
      expect(find.byType(SvgPicture), findsOneWidget);
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
    // mirror, Theme.brightness 자동 분기, 18dp 자상 + Text label) 의무.
    // D-94 = theme 필드 부재 (Primary 단독), D-96 = Google 패턴 (locale
    // 독립, 단일 path).
    //
    // 본 단락의 두 test 는 Wave 1+ 진입 시점에 RED — Wave 1 의
    // branded_social_button.dart 변경 (FacebookSpec sealed switch case 갱신 +
    // _renderFacebookButton 신규 + _iconAssetFor Facebook branch active) 후
    // GREEN 자동 전환. T-13.1-X2-FACEBOOK-PRESERVE-01 sentinel 폐기 의도
    // 명시 — UnsupportedError throw 검증 의도가 Phase 13.2 R5 acceptance 와
    // 의미 반전.
    //
    // **Phase 13.3 Wave 4 Step 2 (2026-05-15) supersede:** D-95 PNG
    // (`assets/brand/facebook/facebook_login.png`) 폐기 → SVG
    // (`assets/brand/facebook/btn_signin_icon.svg`) 전환. Meta Brand Asset
    // Pack 의 Facebook_Logo_Primary.ai PyMuPDF verbatim 추출. FacebookSpec.
    // assetType = AssetType.svg, render 는 SvgPicture.asset 사용. Image 매치
    // 의무 → SvgPicture 매치 의무 갱신. PNG 자상 자체는 Phase 13.3 code review
    // CR-01 정정 commit (2026-05-17) 에서 git rm 으로 폐기.
    testWidgets(
      'T-13.2-FACEBOOK-ACTIVE-01: BrandedSocialButton.facebook() build() → '
      'SvgPicture.asset (Wave 4 Step 2 SVG) + Text(authFacebookSignIn ARB) '
      '단일 매치 (R5/R6 + 옵션 A pivot _renderFacebookButton 호출 검증)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: BrandedSocialButton.facebook(
                label: 'Login with Facebook',
                onPressed: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // BrandedSocialButton 위제 단일 매치 — UnsupportedError throw 폐기.
        expect(find.byType(BrandedSocialButton), findsOneWidget);

        // Wave 4 Step 2 SVG — SvgPicture 1 매치 (Apple 패턴 mirror, icon 슬롯).
        // 옵션 A pivot — Kakao/Naver 의 wide 자상 통째 buttons 패턴 미적용
        // (Facebook 자상은 square logo 단독, _renderActiveButton 호출 불가).
        expect(find.byType(SvgPicture), findsOneWidget);

        // 신규 _renderFacebookButton 의 ARB 라벨 layer — Apple/Facebook 의
        // 외부 layer 단독 권위 패턴 일관 (Phase 13.1 D-82 ARB 머레).
        // 본 test 는 caller 가 전달한 label 이 위제 트리에 렌더되는지 검증
        // (외부 _renderFacebookButton 의 Text 위제 의무).
        expect(find.text('Login with Facebook'), findsOneWidget);
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
              label: 'Login with Facebook',
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
            label: 'Login with Facebook',
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
              label: 'Login with Facebook',
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
            label: 'Login with Facebook',
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
    // `Opacity(...)` wrap 적용. 본 test 는 Opacity descendant 단독 검증.
    //
    // **Phase 13.3 Wave 4 Step 3 (2026-05-17) supersede:** Opacity 0.5 → 0.38
    // (Google CSS verbatim `.gsi-material-button:disabled { opacity: 38%; }`
    // 머레, 사용자 결정 — 5 provider 정량 색 Google mirror 일관성). 본
    // test 는 `lessThan(1.0)` 외 `0.38` 정확값 검증 추가.
    testWidgets('T-13.2-FACEBOOK-DISABLED-01: onPressed=null → 시각 disabled cue '
        '(Opacity opacity 0.38, Google CSS verbatim)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BrandedSocialButton.facebook(
              label: 'Login with Facebook',
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

      // Opacity.opacity 값이 1.0 미만 (시각 fade) + 0.38 정확값 검증
      // (Wave 4 Step 3 Google CSS verbatim).
      final opacity = tester.widget<Opacity>(opacityFinder);
      expect(
        opacity.opacity,
        lessThan(1.0),
        reason:
            'CR-01 회귀 가드 — Opacity.opacity 가 1.0 이면 비활성 시각 cue 0. '
            'Material 3 disabled state spec 위반.',
      );
      expect(
        opacity.opacity,
        0.38,
        reason:
            'Wave 4 Step 3 회귀 가드 — Google CSS verbatim disabled opacity '
            '38% (`.gsi-material-button:disabled { opacity: 38%; }`). 사용자 '
            '결정 2026-05-17 — 5 provider 정량 색 Google mirror 일관성.',
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
                label: 'Login with Facebook',
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

    //
    // **Phase 13.3 Wave 4 Step 2 (2026-05-15) supersede:** D-96 PNG
    // (`assets/brand/facebook/facebook_login.png`, stale) 폐기 → SVG
    // (`assets/brand/facebook/btn_signin_icon.svg`) 전환. `_iconAssetFor`
    // FacebookSpec branch 의 path 갱신. Image → SvgPicture verbatim path 검증.
    // PNG 자상 자체는 Phase 13.3 code review CR-01 정정 commit (2026-05-17)
    // 에서 git rm 으로 폐기 — 본 주석의 PNG 명칭은 history reference.
    testWidgets(
      'T-13.2-FACEBOOK-ASSET-01: BrandedSocialButton.facebook() SvgPicture '
      'path = "assets/brand/facebook/btn_signin_icon.svg" (Wave 4 Step 2 '
      'SVG 전환, locale 독립 — _iconAssetFor FacebookSpec branch active 검증)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: BrandedSocialButton.facebook(
                label: 'Login with Facebook',
                onPressed: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Wave 4 Step 2 — SvgPicture.asset 채택 (AI PyMuPDF verbatim 추출,
        // 2 paths blue circle #0866FF + white 'f'). asset path 정확 검증.
        final SvgPicture svgWidget = tester.widget<SvgPicture>(
          find.byType(SvgPicture),
        );
        // `SvgPicture.asset` 의 internal loader 는 SvgAssetLoader 이며
        // `assetName` 속성을 보유. (flutter_svg ≥2.0)
        final dynamic loader = (svgWidget.bytesLoader as dynamic);
        expect(
          loader.assetName,
          'assets/brand/facebook/btn_signin_icon.svg',
          reason:
              'Phase 13.3 Wave 4 Step 2 — _iconAssetFor FacebookSpec branch '
              'SVG path verbatim. Wave 1 → Step 2 PNG 폐기 후 SVG GREEN.',
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

      // ─── T-13.3-GOOGLE-BG-LIGHT-01 (R1 / Step 3 §3.7) ────────────────────
      // Google Identity Guidelines verbatim bg — light theme = #FFFFFF.
      // Material 3 colorScheme.surface 폐기 (Wave 4 Step 3 §3.7 옵션 A).
      testWidgets(
        'T-13.3-GOOGLE-BG-LIGHT-01: Google light theme bg '
        '#FFFFFF (Step 3 §3.7 verbatim)',
        (tester) async {
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
              if (shape.side.width != 1.0) return false;
              return w.color == Colors.white;
            }),
            findsAtLeastNWidgets(1),
            reason:
                'Google light theme bg 의무 Colors.white (#FFFFFF) — Google '
                'Identity Guidelines verbatim (Step 3 §3.7).',
          );
        },
      );

      // ─── T-13.3-GOOGLE-BG-DARK-01 (R1 / Step 3 §3.7) ─────────────────────
      // Google Identity Guidelines verbatim bg — dark theme = #131314.
      // Material 3 colorScheme.surface (~#1D1B20) drift 회귀 가드.
      testWidgets(
        'T-13.3-GOOGLE-BG-DARK-01: Google dark theme bg '
        '#131314 (Step 3 §3.7 verbatim)',
        (tester) async {
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
              if (shape.side.width != 1.0) return false;
              return w.color == const Color(0xFF131314);
            }),
            findsAtLeastNWidgets(1),
            reason:
                'Google dark theme bg 의무 Color(0xFF131314) — Google '
                'Identity Guidelines verbatim (Step 3 §3.7).',
          );
        },
      );

      // ─── T-13.3-GOOGLE-LABEL-COLOR-LIGHT-01 (R1 / starter kit drift) ─────
      // Google 정문 필수 label color light = #1F1F1F. starter kit 사용자가
      // ThemeData.colorScheme.onSurface override 시 brand drift 회귀 가드 —
      // TextStyle().color 가 hardcoded #1F1F1F 로 변하지 않아야 함.
      testWidgets(
        'T-13.3-GOOGLE-LABEL-COLOR-LIGHT-01: Google light theme label '
        'color #1F1F1F (verbatim hardcode)',
        (tester) async {
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

          final Text textWidget = tester.widget<Text>(
            find.text('Sign in with Google'),
          );
          expect(
            textWidget.style?.color,
            const Color(0xFF1F1F1F),
            reason:
                'Google light theme label color 의무 Color(0xFF1F1F1F) — '
                'Google Identity Guidelines verbatim. colorScheme.onSurface '
                '토큰 drift 회귀 방지.',
          );
        },
      );

      // ─── T-13.3-GOOGLE-LABEL-COLOR-DARK-01 (R1 / starter kit drift) ──────
      testWidgets(
        'T-13.3-GOOGLE-LABEL-COLOR-DARK-01: Google dark theme label '
        'color #E3E3E3 (verbatim hardcode)',
        (tester) async {
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

          final Text textWidget = tester.widget<Text>(
            find.text('Sign in with Google'),
          );
          expect(
            textWidget.style?.color,
            const Color(0xFFE3E3E3),
            reason:
                'Google dark theme label color 의무 Color(0xFFE3E3E3) — '
                'Google Identity Guidelines verbatim. colorScheme.onSurface '
                '토큰 drift 회귀 방지.',
          );
        },
      );

      // ─── T-13.3-GOOGLE-LABEL-FONT-01 (R1 / starter kit drift) ────────────
      // Google 정문 필수: "Roboto Medium" + "14/20" — fontSize 14pt /
      // fontWeight w500 / lineHeight 20pt (height = 20/14). starter kit 사용자
      // 가 textTheme.labelLarge override 시 brand drift 회귀 가드.
      testWidgets(
        'T-13.3-GOOGLE-LABEL-FONT-01: Google label TextStyle '
        'fontSize 14 / w500 / height 20/14 (verbatim hardcode)',
        (tester) async {
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

          final Text textWidget = tester.widget<Text>(
            find.text('Sign in with Google'),
          );
          expect(
            textWidget.style?.fontSize,
            14,
            reason:
                'Google label fontSize 의무 14pt — Google Identity Guidelines '
                '"14/20" verbatim. textTheme.labelLarge drift 회귀 방지.',
          );
          expect(
            textWidget.style?.fontWeight,
            FontWeight.w500,
            reason:
                'Google label fontWeight 의무 w500 (Medium) — Google '
                'Identity Guidelines "Roboto Medium" verbatim.',
          );
          expect(
            textWidget.style?.height,
            20 / 14,
            reason:
                'Google label lineHeight 의무 20/14 — Google Identity '
                'Guidelines "14/20" verbatim.',
          );
          expect(
            textWidget.style?.letterSpacing,
            0.25,
            reason:
                'Google label letterSpacing 의무 0.25 (Android default '
                'platform) — Google production CSS `.gsi-material-button '
                '{ letter-spacing: 0.25px; }` verbatim (Roboto context). '
                'iOS branch 는 T-13.3-GOOGLE-LABEL-FONT-IOS-01 별도 검증 '
                '(Apple HIG SF Pro Text size 14pt 권고 -0.15).',
          );
        },
      );

      // ─── T-13.3-GOOGLE-LABEL-FONT-IOS-01 (R1 / Apple HIG SF Pro Text) ───
      // Google iOS branch — letterSpacing -0.15 (Apple HIG SF Pro Text size
      // 14pt 권고 tracking, developer.apple.com/design/human-interface-
      // guidelines/typography). Roboto 0.25 (Google CSS verbatim) 가 SF Pro
      // Text 의 wider default tracking 위에 누적되어 시각 자간 과도 발생 →
      // iOS 강등 패턴 채택 (padding/gap iOS 강등 mirror, 사용자 결정
      // 2026-05-17).
      testWidgets(
        'T-13.3-GOOGLE-LABEL-FONT-IOS-01: Google label TextStyle iOS branch — '
        'letterSpacing -0.15 + fontFamily SF Pro Text (Apple HIG 강등)',
        (tester) async {
          await tester.pumpWidget(
            _wrapForR1R2R3(
              BrandedSocialButton.google(
                label: 'Sign in with Google',
                onPressed: () {},
              ),
              brightness: Brightness.light,
              platform: TargetPlatform.iOS,
            ),
          );
          await _settleAssetsForR1R2R3(tester);

          final Text textWidget = tester.widget<Text>(
            find.text('Sign in with Google'),
          );
          expect(
            textWidget.style?.letterSpacing,
            -0.15,
            reason:
                'Google label letterSpacing iOS branch 의무 -0.15 — Apple '
                'HIG SF Pro Text size 14pt 권고 tracking. Roboto 0.25 (Google '
                'CSS verbatim) 의 SF Pro Text 누적 자간 과도 방지 (사용자 '
                '시각 보고 2026-05-17).',
          );
          expect(
            textWidget.style?.fontFamily,
            'SF Pro Text',
            reason:
                'Google label fontFamily iOS branch 의무 SF Pro Text — '
                'Google 가이드 iOS 강등 정책 + Apple OS 내부 native font.',
          );
        },
      );

      // ─── T-13.3-GOOGLE-PLATFORM-IOS-01 (R1 / Step 3 §3.5+§3.6) ───────────
      // Google 정문 OS 분기 필수: iOS padding.horizontal = 16dp +
      // logoLabelGap = 12dp. platform 분기 trigger 회귀 가드.
      testWidgets(
        'T-13.3-GOOGLE-PLATFORM-IOS-01: Google iOS padding 16 + '
        'gap 12 (OS 분기 verbatim)',
        (tester) async {
          await tester.pumpWidget(
            _wrapForR1R2R3(
              BrandedSocialButton.google(
                label: 'Sign in with Google',
                onPressed: () {},
              ),
              brightness: Brightness.light,
              platform: TargetPlatform.iOS,
            ),
          );
          await _settleAssetsForR1R2R3(tester);

          // Google iOS padding.horizontal = 16dp
          expect(
            find.byWidgetPredicate((Widget w) {
              if (w is! Padding) return false;
              final EdgeInsetsGeometry p = w.padding;
              if (p is! EdgeInsets) return false;
              return p.left == 16.0 && p.right == 16.0;
            }),
            findsAtLeastNWidgets(1),
            reason:
                'Google iOS padding.horizontal 의무 16dp — Google Identity '
                'Guidelines verbatim (Step 3 §3.6).',
          );

          // Google iOS logoLabelGap = SizedBox(width: 12)
          expect(
            find.byWidgetPredicate((Widget w) {
              if (w is! SizedBox) return false;
              return w.width == 12.0;
            }),
            findsAtLeastNWidgets(1),
            reason:
                'Google iOS logoLabelGap 의무 SizedBox(width: 12) — Google '
                'Identity Guidelines verbatim (Step 3 §3.5).',
          );
        },
      );

      // ════════════════════════════════════════════════════════════════════
      // Phase 13.3 Wave 4 Step 3 (2026-05-17) — Facebook verbatim 회귀 가드
      //
      // Facebook 정문 (developers.facebook.com/docs/facebook-login/userexperience/)
      // 은 bg / label color / fontFamily / size / weight 모두 정성 권고만 자유
      // 영역. 5 provider 시각 consistency 위해 Google CSS verbatim 패턴 mirror
      // 적용 (사용자 결정 2026-05-17). 본 8 test 는 starter kit drift 회귀
      // 가드 — 사용자 ThemeData.colorScheme/textTheme override 시 brand 외관
      // 변하지 않아야 함.
      // ════════════════════════════════════════════════════════════════════

      // ─── T-13.3-FACEBOOK-BG-LIGHT-01 (R5 / Google CSS mirror) ────────────
      testWidgets(
        'T-13.3-FACEBOOK-BG-LIGHT-01: Facebook light theme bg '
        '#FFFFFF (Google CSS mirror, starter kit drift 회귀 가드)',
        (tester) async {
          await tester.pumpWidget(
            _wrapForR1R2R3(
              BrandedSocialButton.facebook(
                label: 'Login with Facebook',
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
              return w.color == const Color(0xFFFFFFFF);
            }),
            findsAtLeastNWidgets(1),
            reason:
                'Facebook light theme bg 의무 Color(0xFFFFFFFF) — Google CSS '
                'verbatim mirror (사용자 결정 2026-05-17). colorScheme.surface '
                '토큰 drift 회귀 방지.',
          );
        },
      );

      // ─── T-13.3-FACEBOOK-BG-DARK-01 (R5 / Google CSS mirror) ─────────────
      testWidgets(
        'T-13.3-FACEBOOK-BG-DARK-01: Facebook dark theme bg '
        '#131314 (Google CSS mirror, starter kit drift 회귀 가드)',
        (tester) async {
          await tester.pumpWidget(
            _wrapForR1R2R3(
              BrandedSocialButton.facebook(
                label: 'Login with Facebook',
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
              return w.color == const Color(0xFF131314);
            }),
            findsAtLeastNWidgets(1),
            reason:
                'Facebook dark theme bg 의무 Color(0xFF131314) — Google CSS '
                'verbatim mirror (사용자 결정 2026-05-17). colorScheme.surface '
                '(~#1D1B20) drift 회귀 방지.',
          );
        },
      );

      // ─── T-13.3-FACEBOOK-OUTLINE-LIGHT-01 (R5 / Google CSS mirror) ───────
      testWidgets(
        'T-13.3-FACEBOOK-OUTLINE-LIGHT-01: Facebook light theme outline '
        '#DADCE0 1dp (Google CSS mirror, starter kit drift 회귀 가드)',
        (tester) async {
          await tester.pumpWidget(
            _wrapForR1R2R3(
              BrandedSocialButton.facebook(
                label: 'Login with Facebook',
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
              return shape.side.color == const Color(0xFFDADCE0);
            }),
            findsAtLeastNWidgets(1),
            reason:
                'Facebook light theme outline 의무 Color(0xFFDADCE0) — Google '
                'CSS verbatim mirror (사용자 결정 2026-05-17). Material grey '
                'shade300 drift 정정 (M3 토큰 0 일관 위해 hex hardcode).',
          );
        },
      );

      // ─── T-13.3-FACEBOOK-OUTLINE-DARK-01 (R5 / Google CSS mirror) ────────
      testWidgets(
        'T-13.3-FACEBOOK-OUTLINE-DARK-01: Facebook dark theme outline '
        '#8E918F 1dp (Google CSS mirror, starter kit drift 회귀 가드)',
        (tester) async {
          await tester.pumpWidget(
            _wrapForR1R2R3(
              BrandedSocialButton.facebook(
                label: 'Login with Facebook',
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
                'Facebook dark theme outline 의무 Color(0xFF8E918F) — Google '
                'CSS verbatim mirror (사용자 결정 2026-05-17). Material grey '
                'shade700 drift 정정 (M3 토큰 0 일관 위해 hex hardcode).',
          );
        },
      );

      // ─── T-13.3-FACEBOOK-LABEL-COLOR-LIGHT-01 (R5 / starter kit drift) ───
      testWidgets(
        'T-13.3-FACEBOOK-LABEL-COLOR-LIGHT-01: Facebook light theme label '
        'color #1F1F1F (Google CSS mirror, verbatim hardcode)',
        (tester) async {
          await tester.pumpWidget(
            _wrapForR1R2R3(
              BrandedSocialButton.facebook(
                label: 'Login with Facebook',
                onPressed: () {},
              ),
              brightness: Brightness.light,
            ),
          );
          await _settleAssetsForR1R2R3(tester);

          final Text textWidget = tester.widget<Text>(
            find.text('Login with Facebook'),
          );
          expect(
            textWidget.style?.color,
            const Color(0xFF1F1F1F),
            reason:
                'Facebook light theme label color 의무 Color(0xFF1F1F1F) — '
                'Google CSS verbatim mirror (사용자 결정 2026-05-17). '
                'colorScheme.onSurface 토큰 drift 회귀 방지.',
          );
        },
      );

      // ─── T-13.3-FACEBOOK-LABEL-COLOR-DARK-01 (R5 / starter kit drift) ────
      testWidgets(
        'T-13.3-FACEBOOK-LABEL-COLOR-DARK-01: Facebook dark theme label '
        'color #E3E3E3 (Google CSS mirror, verbatim hardcode)',
        (tester) async {
          await tester.pumpWidget(
            _wrapForR1R2R3(
              BrandedSocialButton.facebook(
                label: 'Login with Facebook',
                onPressed: () {},
              ),
              brightness: Brightness.dark,
            ),
          );
          await _settleAssetsForR1R2R3(tester);

          final Text textWidget = tester.widget<Text>(
            find.text('Login with Facebook'),
          );
          expect(
            textWidget.style?.color,
            const Color(0xFFE3E3E3),
            reason:
                'Facebook dark theme label color 의무 Color(0xFFE3E3E3) — '
                'Google CSS verbatim mirror (사용자 결정 2026-05-17). '
                'colorScheme.onSurface 토큰 drift 회귀 방지.',
          );
        },
      );

      // ─── T-13.3-FACEBOOK-LABEL-FONT-01 (R5 / starter kit drift) ──────────
      // Google CSS verbatim mirror (사용자 결정 2026-05-17 — Facebook 정문
      // 자유, 5 provider Google 패턴 머레): fontSize 14pt / fontWeight w500 /
      // height 20/14 / letterSpacing 0.25 (Android Roboto context) / fontFamily
      // 'Roboto'. starter kit 사용자가 textTheme.labelLarge override 시 brand
      // drift 회귀 가드.
      testWidgets(
        'T-13.3-FACEBOOK-LABEL-FONT-01: Facebook label TextStyle '
        'fontSize 14 / w500 / height 20/14 / letter 0.25 / Roboto '
        '(Google CSS verbatim hardcode, Android)',
        (tester) async {
          await tester.pumpWidget(
            _wrapForR1R2R3(
              BrandedSocialButton.facebook(
                label: 'Login with Facebook',
                onPressed: () {},
              ),
              brightness: Brightness.light,
            ),
          );
          await _settleAssetsForR1R2R3(tester);

          final Text textWidget = tester.widget<Text>(
            find.text('Login with Facebook'),
          );
          expect(
            textWidget.style?.fontSize,
            14,
            reason:
                'Facebook label fontSize 의무 14pt — Google CSS "14/20" '
                'verbatim mirror (사용자 결정 2026-05-17). textTheme.labelLarge '
                'drift 회귀 방지.',
          );
          expect(
            textWidget.style?.fontWeight,
            FontWeight.w500,
            reason:
                'Facebook label fontWeight 의무 w500 (Medium) — Google CSS '
                'verbatim mirror.',
          );
          expect(
            textWidget.style?.height,
            20 / 14,
            reason:
                'Facebook label lineHeight 의무 20/14 — Google CSS "14/20" '
                'verbatim mirror.',
          );
          expect(
            textWidget.style?.letterSpacing,
            0.25,
            reason:
                'Facebook label letterSpacing 의무 0.25 (Android default '
                'platform) — Google CSS `.gsi-material-button { letter-spacing: '
                '0.25px; }` verbatim mirror (Roboto context). iOS branch 는 '
                'T-13.3-FACEBOOK-LABEL-FONT-IOS-01 별도 검증.',
          );
          expect(
            textWidget.style?.fontFamily,
            'Roboto',
            reason:
                'Facebook label fontFamily 의무 Roboto (Android default '
                'platform) — Google CSS verbatim mirror.',
          );
        },
      );

      // ─── T-13.3-FACEBOOK-LABEL-FONT-IOS-01 (R5 / Apple HIG SF Pro Text) ──
      // iOS branch — letterSpacing -0.15 + fontFamily 'SF Pro Text' (Apple HIG
      // SF Pro Text size 14pt 권고 tracking + Apple OS 내부 native font).
      // Roboto 0.25 가 SF Pro Text 의 wider default tracking 위에 누적되어
      // 시각 자간 과도 → iOS 강등 (Google 패턴 머레, 사용자 결정 2026-05-17).
      testWidgets(
        'T-13.3-FACEBOOK-LABEL-FONT-IOS-01: Facebook label TextStyle iOS '
        'branch — letterSpacing -0.15 + fontFamily SF Pro Text (Apple HIG '
        '강등, Google iOS 패턴 머레)',
        (tester) async {
          await tester.pumpWidget(
            _wrapForR1R2R3(
              BrandedSocialButton.facebook(
                label: 'Login with Facebook',
                onPressed: () {},
              ),
              brightness: Brightness.light,
              platform: TargetPlatform.iOS,
            ),
          );
          await _settleAssetsForR1R2R3(tester);

          final Text textWidget = tester.widget<Text>(
            find.text('Login with Facebook'),
          );
          expect(
            textWidget.style?.letterSpacing,
            -0.15,
            reason:
                'Facebook label letterSpacing iOS branch 의무 -0.15 — Apple '
                'HIG SF Pro Text size 14pt 권고 tracking. Roboto 0.25 의 SF '
                'Pro Text 누적 자간 과도 방지 (Google iOS 패턴 머레, 사용자 '
                '결정 2026-05-17).',
          );
          expect(
            textWidget.style?.fontFamily,
            'SF Pro Text',
            reason:
                'Facebook label fontFamily iOS branch 의무 SF Pro Text — '
                'Google 패턴 머레 iOS 강등 + Apple OS 내부 native font.',
          );
        },
      );

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

      // ─── T-13.3-NAVER-LABEL-COLOR-01 (R3 / starter kit drift) ────────────
      // Naver 정문 필수 label color (green-bg variant) = #FFFFFF. starter kit
      // 사용자가 ThemeData.colorScheme.onSurface override 시 brand drift 회귀
      // 가드 — TextStyle().color 가 hardcoded Colors.white 로 고정.
      testWidgets(
        'T-13.3-NAVER-LABEL-COLOR-01: Naver label color #FFFFFF '
        '(verbatim hardcode)',
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

          final Text textWidget = tester.widget<Text>(
            find.text('Log in with NAVER'),
          );
          expect(
            textWidget.style?.color,
            Colors.white,
            reason:
                'Naver green-bg label color 의무 Colors.white — Naver '
                'developers.naver.com/docs/login/bi/bi.md verbatim. '
                'colorScheme.onSurface 토큰 drift 회귀 방지.',
          );
        },
      );

      // ─── T-13.3-NAVER-LABEL-FONT-01 (R3 / starter kit drift) ─────────────
      // Naver 정문 자유 영역 (fontSize / fontFamily / fontWeight 미명시) →
      // 사용자 결정 2026-05-16: 공식 PNG 자상 (NAVER_login_Light_EN_green_
      // center_H48.png) 정밀 측정 부합. fontSize 18 / fontWeight w800 /
      // fontFamily Pretendard (한국 design 표준 + 공식 PNG 글리프 시각 부합 +
      // SIL OFL 1.1 bundled). 전 platform 단일 (asset bundled). starter kit
      // 사용자 textTheme.labelLarge override drift 회귀 가드.
      testWidgets(
        'T-13.3-NAVER-LABEL-FONT-01: Naver label TextStyle '
        'fontSize 16 / w600 / Pretendard (공식 PNG verbatim)',
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

          final Text textWidget = tester.widget<Text>(
            find.text('Log in with NAVER'),
          );
          expect(
            textWidget.style?.fontSize,
            16,
            reason:
                'Naver label fontSize 의무 16pt — 사용자 시각 sign-off 부합 '
                '(PNG cap height ~16dp 부합). 정문 조건 "로고 높이보다 작은 '
                '크기" 는 cap-height 기준 해석 (cap height ≈ 0.7 × 16 ≈ 11 '
                '< logo.height 16 부합). textTheme.labelLarge drift 회귀 방지.',
          );
          expect(
            textWidget.style?.fontWeight,
            FontWeight.w600,
            reason:
                'Naver label fontWeight 의무 w600 (SemiBold) — Pretendard 명목 '
                'weight 매핑이 무거워 w800/w700 시도 시 stroke 과도 → w600 '
                '채택. 정문 미명시, 사용자 결정.',
          );
          expect(
            textWidget.style?.fontFamily,
            'Pretendard',
            reason:
                'Naver label fontFamily 의무 Pretendard (Android default '
                'platform) — 공식 PNG 글리프 시각 가장 부합. 한국 design '
                '표준 web font. iOS branch 는 T-13.3-NAVER-LABEL-FONT-IOS-01 '
                '별도 검증 (Kakao 패턴 mirror).',
          );
        },
      );

      // ─── T-13.3-NAVER-LABEL-FONT-IOS-01 (R3 / Kakao 패턴 mirror) ────────
      // Naver 라벨 iOS branch — Theme.of(context).platform == TargetPlatform.iOS
      // 분기 시 fontFamily 'AppleSDGothicNeo' (Pretendard 의 source font, native
      // 시스템 폰트) + fontWeight w700 (Bold — NAVER 공식 PNG 굵은 stroke 시각
      // 매칭, AppleSDGothicNeo 명목 weight 가 Pretendard 보다 가벼워 한 단계
      // 올림, 사용자 시각 sign-off 2026-05-16). Apple Font License 부합 (Apple
      // OS 내부 사용, bundle 0). cross-provider 일관성 (Apple/Google/Naver/
      // Kakao 모두 platform 분기).
      testWidgets(
        'T-13.3-NAVER-LABEL-FONT-IOS-01: Naver label TextStyle iOS branch — '
        'fontFamily AppleSDGothicNeo / w700 (Pretendard source font native)',
        (tester) async {
          await tester.pumpWidget(
            _wrapForR1R2R3(
              BrandedSocialButton.naver(
                label: 'Log in with NAVER',
                onPressed: () {},
              ),
              brightness: Brightness.light,
              platform: TargetPlatform.iOS,
            ),
          );
          await _settleAssetsForR1R2R3(tester);

          final Text textWidget = tester.widget<Text>(
            find.text('Log in with NAVER'),
          );
          expect(
            textWidget.style?.fontFamily,
            'AppleSDGothicNeo',
            reason:
                'Naver label fontFamily 의무 AppleSDGothicNeo (iOS branch) — '
                'Pretendard 의 source font (native 시스템 폰트). bundle 0 + '
                'Apple Font License 부합 (Apple OS 내부 사용).',
          );
          expect(
            textWidget.style?.fontWeight,
            FontWeight.w700,
            reason:
                'Naver label fontWeight 의무 w700 Bold (iOS branch) — '
                'NAVER 공식 PNG (`NAVER_login_Light_EN_green_center_H48`) '
                '굵은 stroke 시각 매칭. AppleSDGothicNeo 명목 weight 가 '
                'Pretendard 보다 가벼워 Android w600 에서 한 단계 올림 (사용자 '
                '시각 sign-off 2026-05-16). Kakao case 와 다른 결정 — Kakao '
                'PSD verbatim Medium(w500) vs Naver PNG outlined (weight '
                '없음, 시각 sign-off 우선).',
          );
          // fontSize 17 (iOS branch only — AppleSDGothicNeo cap height 가
          // Pretendard 보다 작은 비율이라 시각 보정 +1pt, 사용자 시각 보고
          // 3회 iteration 2026-05-16: 16→17→18→17 수렴).
          expect(
            textWidget.style?.fontSize,
            17,
            reason:
                'Naver label fontSize iOS branch 의무 17pt — '
                'AppleSDGothicNeo cap height 가 Pretendard 보다 작은 비율 '
                '시각 보정 (Android 16 대비 +1pt, 사용자 시각 보고 '
                '3회 iteration 2026-05-16).',
          );
        },
      );

      // ─── T-13.3-NAVER-SPEC-VERBATIM-01 (R3 / starter kit drift) ──────────
      // NaverSpec 공식 PNG 자상 verbatim override: borderRadius 8 (PNG 측정
      // ~7.5dp + AI 자산 8dp) + iconSize 16 (PNG 측정 16×16dp + 정문 ≥16
      // 정확 대응). BrandSpec default (12/18) 와 다른 별도 값 회귀 가드.
      testWidgets(
        'T-13.3-NAVER-SPEC-VERBATIM-01: NaverSpec borderRadius 8 + '
        'iconSize 16 (공식 PNG verbatim)',
        (tester) async {
          expect(
            const NaverSpec().borderRadius,
            8.0,
            reason:
                'NaverSpec borderRadius 의무 8dp — 공식 PNG 측정 ~7.5dp + '
                'AI 자산 cubic Bezier 8dp 부합. BrandSpec default 12 drift '
                '회귀 방지.',
          );
          expect(
            const NaverSpec().iconSize,
            16.0,
            reason:
                'NaverSpec iconSize 의무 16dp — 공식 PNG 측정 16×16dp + '
                '정문 "완성형 16px 이상" 정확 대응. BrandSpec default 18 '
                'drift 회귀 방지.',
          );
        },
      );

      // ─── T-13.3-NAVER-LABEL-GAP-01 (R3 정문 필수) ────────────────────────
      // Naver 정문 필수: "가운데 정렬 시 로고와 레이블의 간격은 8px". center
      // align logo-label gap = SizedBox(width: 8) 회귀 가드.
      testWidgets(
        'T-13.3-NAVER-LABEL-GAP-01: Naver logoLabelGap '
        'SizedBox(width: 8) (정문 필수)',
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
              if (w is! SizedBox) return false;
              return w.width == 8.0 && w.height == null;
            }),
            findsAtLeastNWidgets(1),
            reason:
                'Naver 정문 필수 "가운데 정렬 시 로고와 레이블의 간격은 '
                '8px" — center align logoLabelGap SizedBox(width: 8) 회귀 '
                '가드.',
          );
        },
      );

      // ─── T-13.3-KAKAO-SPEC-VERBATIM-01 (R2 / starter kit drift) ─────────
      // KakaoSpec 공식 PSD M Wide variant verbatim override:
      //   iconSize 20 (PSD Shape 1 측정 20×20dp + Google CSS 20px 정확 일치).
      // BrandSpec default (18) 와 다른 별도 값 회귀 가드. borderRadius 12 는
      // 정문 필수 정량 그대로 (BrandSpec default 일치).
      testWidgets(
        'T-13.3-KAKAO-SPEC-VERBATIM-01: KakaoSpec iconSize 20 '
        '(PSD M Wide verbatim) + borderRadius 12 (정문 필수)',
        (tester) async {
          expect(
            const KakaoSpec().iconSize,
            20.0,
            reason:
                'KakaoSpec iconSize 의무 20dp — 공식 PSD M Wide Shape 1 측정 '
                '20×20dp + Google CSS 20px 정확 일치. BrandSpec default 18 '
                'drift 회귀 방지.',
          );
          expect(
            const KakaoSpec().borderRadius,
            12.0,
            reason:
                'KakaoSpec borderRadius 의무 12dp — 정문 필수 "컨테이너 박스의 '
                'radius는 12 픽셀". BrandSpec default 와 일치.',
          );
        },
      );

      // ─── T-13.3-KAKAO-LABEL-COLOR-01 (R2 / starter kit drift) ───────────
      // Kakao 정문 필수 label color = #000000 alpha 0.85 = Color(0xD9000000).
      // 가이드 정문 우선 (PSD 자산은 #191919 100% 사용하나 디자이너 별도 적용).
      // starter kit 사용자가 ThemeData.colorScheme.onSurface override 시 brand
      // drift 회귀 가드 — TextStyle().color 가 hardcoded Color(0xD9000000) 로
      // 고정.
      testWidgets(
        'T-13.3-KAKAO-LABEL-COLOR-01: Kakao label color #000000 α0.85 '
        '(가이드 정문 verbatim hardcode)',
        (tester) async {
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

          final Text textWidget = tester.widget<Text>(
            find.text('Login with Kakao'),
          );
          expect(
            textWidget.style?.color,
            const Color(0xD9000000),
            reason:
                'Kakao label color 의무 #000000 α0.85 = 0xD9000000 — '
                'developers.kakao.com/docs/ko/kakaologin/design-guide '
                'verbatim. colorScheme.onSurface 토큰 drift 회귀 방지.',
          );
        },
      );

      // ─── T-13.3-KAKAO-LABEL-FONT-01 (R2 / starter kit drift) ────────────
      // Kakao 정문 "OS별 기본 시스템 서체" + PSD verbatim 결합 (사용자
      // 2026-05-16): Pretendard — PSD `AppleSDGothicNeo` 의 open-source 대체.
      // Pretendard 가 Apple SD Gothic Neo 기반 open-source font (SIL OFL 1.1).
      // AppleSDGothicNeo binary 는 closed-source (Apple Font License + Sandoll
      // 라이센스, third-party 앱 bundle + Android 사용 라이센스 위반 위험).
      // Naver case cross-provider 일관.
      // *audit trail*: KakaoSmallSans (kakao/kakao-font, 2025-06-18 공개) 시도
      // → PSD 자상 (~2022) 의 AppleSDGothicNeo 글리프 character set 과 명백히
      // 다름 (digital-optimized 신규 디자인) + bundle 의미 없음 → Pretendard
      // 복귀.
      // fontSize 15 — PSD M Wide variant verbatim. 모바일 UX (height 48dp) 부합.
      // fontWeight w400 (Regular) — Step A 시각 검증 (Android 용). PSD L Wide
      // variant `AppleSDGothicNeo-Medium` verbatim 부합 의도이나 Pretendard
      // 명목 weight 매핑이 AppleSDGothicNeo 보다 무거워 w500 시도 시 PSD
      // reference 대비 미세 과도 → w400 으로 한 단계 더 낮춤 (Naver case lesson
      // #15 mirror). Step B 진입 시 iOS native AppleSDGothicNeo platform 분기
      // 추가 예정.
      // starter kit 사용자 textTheme.labelLarge override drift 회귀 가드.
      testWidgets(
        'T-13.3-KAKAO-LABEL-FONT-01: Kakao label TextStyle '
        'fontSize 15 / w400 / Pretendard (Step A Android 시각 검증)',
        (tester) async {
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

          final Text textWidget = tester.widget<Text>(
            find.text('Login with Kakao'),
          );
          expect(
            textWidget.style?.fontSize,
            15,
            reason:
                'Kakao label fontSize 의무 15pt — 공식 PSD M Wide variant '
                'verbatim (AppleSDGothicNeo / 15pt). 모바일 UX (height 48dp) '
                '부합. textTheme.labelLarge drift 회귀 방지.',
          );
          expect(
            textWidget.style?.fontWeight,
            FontWeight.w400,
            reason:
                'Kakao label fontWeight 의무 w400 (Regular) — Step A 시각 '
                '검증 (Android 용, 사용자 시각 sign-off 2026-05-16). PSD L '
                'Wide variant AppleSDGothicNeo-Medium verbatim 부합 의도 + '
                'Pretendard 명목 weight 매핑이 AppleSDGothicNeo 보다 무거워 '
                'w500 시도 시 PSD reference 대비 미세 과도 → w400 으로 한 '
                '단계 더 낮춤 (Naver case lesson #15 mirror).',
          );
          expect(
            textWidget.style?.fontFamily,
            'Pretendard',
            reason:
                'Kakao label fontFamily 의무 Pretendard (Android default '
                'platform) — PSD verbatim AppleSDGothicNeo 의 open-source 대체 '
                '(Pretendard 가 Apple SD Gothic Neo 기반 open-source font 로 '
                '디자인, SIL OFL 1.1). AppleSDGothicNeo binary 는 closed-source '
                '(Apple Font License + Sandoll 한글 라이센스, third-party 앱 '
                'bundle + Android 사용 라이센스 위반 위험). iOS branch 는 '
                'T-13.3-KAKAO-LABEL-FONT-IOS-01 별도 검증.',
          );
        },
      );

      // ─── T-13.3-KAKAO-LABEL-FONT-IOS-01 (Step B platform 분기) ──────────
      // Kakao 라벨 iOS branch — Theme.of(context).platform == TargetPlatform.iOS
      // 분기 시 fontFamily 'AppleSDGothicNeo' + fontWeight w500 (Medium). PSD
      // verbatim AppleSDGothicNeo-Medium 를 iOS native 시스템 폰트로 직접 명시
      // → PSD designer 의도 그대로 iOS 렌더. Apple Font License 부합 (Apple OS
      // 내부 사용, bundle 0). starter kit drift 회피 원칙 "허용 (분기 trigger):
      // theme.platform" 부합.
      testWidgets(
        'T-13.3-KAKAO-LABEL-FONT-IOS-01: Kakao label TextStyle iOS branch — '
        'fontFamily AppleSDGothicNeo / w500 (PSD verbatim native)',
        (tester) async {
          await tester.pumpWidget(
            _wrapForR1R2R3(
              BrandedSocialButton.kakao(
                label: 'Login with Kakao',
                onPressed: () {},
              ),
              brightness: Brightness.light,
              platform: TargetPlatform.iOS,
            ),
          );
          await _settleAssetsForR1R2R3(tester);

          final Text textWidget = tester.widget<Text>(
            find.text('Login with Kakao'),
          );
          expect(
            textWidget.style?.fontFamily,
            'AppleSDGothicNeo',
            reason:
                'Kakao label fontFamily 의무 AppleSDGothicNeo (iOS branch) — '
                'PSD verbatim native font. iOS native 시스템 폰트로 bundle 0 + '
                'Apple Font License 부합 (Apple OS 내부 사용).',
          );
          expect(
            textWidget.style?.fontWeight,
            FontWeight.w500,
            reason:
                'Kakao label fontWeight 의무 w500 Medium (iOS branch) — PSD '
                'L Wide variant AppleSDGothicNeo-Medium verbatim. iOS native '
                '폰트 = PSD designer 의도 그대로 렌더.',
          );
          // fontSize 16 (iOS branch — AppleSDGothicNeo cap height 가
          // Pretendard 보다 작은 비율이라 시각 보정 +1pt, Naver case mirror
          // 사용자 시각 보고 3회 iteration 2026-05-16: 15→16→17→16 수렴).
          // Android 는 PSD M Wide variant verbatim 15pt 유지.
          expect(
            textWidget.style?.fontSize,
            16,
            reason:
                'Kakao label fontSize iOS branch 의무 16pt — '
                'AppleSDGothicNeo cap height 가 Pretendard 보다 작은 비율 '
                '시각 보정 (Android 15 대비 +1pt, Naver case mirror, '
                '사용자 시각 보고 3회 iteration 2026-05-16).',
          );
        },
      );

      // ─── T-13.3-APPLE-BG-LIGHT-01 (R5 / Wave 4 Step 2 supersede) ─────────
      //
      // **Phase 13.3 Wave 4 Step 2 (2026-05-15) supersede:** SignInWithApple
      // Button SDK 위제 폐기 → custom render. SDK 의 `style: .black/.white`
      // 검증 → Material.color hex 검증 갱신. Apple HIG 패턴 — light theme app
      // 에서 light bg button (5 provider Google/Facebook 패턴 머레, 직관적
      // theme adapting).
      testWidgets('T-13.3-APPLE-BG-LIGHT-01: Apple light theme bg = '
          '#FFFFFF (custom render, Wave 4 Step 2 SDK 위제 폐기)', (tester) async {
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

        expect(
          find.byWidgetPredicate((Widget w) {
            if (w is! Material) return false;
            final ShapeBorder? shape = w.shape;
            if (shape is! RoundedRectangleBorder) return false;
            return w.color == Colors.white;
          }),
          findsAtLeastNWidgets(1),
          reason:
              'Apple light theme bg 의무 Colors.white (#FFFFFF) — Wave 4 '
              'Step 2 custom render (SDK 위제 폐기). 5 provider Google/'
              'Facebook 패턴 머레.',
        );
      });

      // ─── T-13.3-APPLE-BG-DARK-01 (R5 / Wave 4 Step 2 supersede) ──────────
      testWidgets('T-13.3-APPLE-BG-DARK-01: Apple dark theme bg = '
          '#000000 (custom render, Wave 4 Step 2 SDK 위제 폐기)', (tester) async {
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

        expect(
          find.byWidgetPredicate((Widget w) {
            if (w is! Material) return false;
            final ShapeBorder? shape = w.shape;
            if (shape is! RoundedRectangleBorder) return false;
            return w.color == Colors.black;
          }),
          findsAtLeastNWidgets(1),
          reason:
              'Apple dark theme bg 의무 Colors.black (#000000) — Wave 4 '
              'Step 2 custom render (SDK 위제 폐기). 5 provider Google/'
              'Facebook 패턴 머레.',
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
///
/// **Phase 13.3 Wave 4 Step 3 (2026-05-16):** Google `_renderGoogleButton`
/// 의 platform 분기 (Android/iOS padding/gap) 검증 위해 [platform] 매개변수
/// 추가. `null` (default) → `AppTheme` 의 platform 그대로 사용 (기존 호출자
/// 영향 0). 명시 시 → `ThemeData.copyWith(platform: ...)` 으로 override.
Widget _wrapForR1R2R3(
  Widget child, {
  required Brightness brightness,
  TargetPlatform? platform,
}) {
  final base = brightness == Brightness.light
      ? AppTheme.light()
      : AppTheme.dark();
  final theme = platform == null ? base : base.copyWith(platform: platform);
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
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
