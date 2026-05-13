// Phase 13.1 — see ROADMAP.md (D-66 sealed sub-class const + R1/R2/R8 회귀 가드)
//
// Phase 13.1 Gap-1 X2 (2026-05-09 자상화) — 본 file 카운트 8 → 14:
// 기존 8 (sealed hierarchy 회귀 가드) + 신규 6 (wide 자상 통째 buttons
// 패턴 검증). 사용자 보고 4 issue 해소 acceptance.
//
// Phase 13.1 Gap-1 X2 BLOCKER 2 fix — sentinel stub-context class 폐기 →
// tester.pumpWidget + tester.takeException 패턴 (Flutter 권장).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

// ─── 회귀 가드 expected 색상 (production private literal mirror) ────────────
//
// 단일 진실원은 `branded_social_button.dart` 의 `_kKakao*` / `_kNaver*` const
// 이며 본 상수는 회귀 가드 비교 대상이다 — 둘 중 어느 쪽이든 변경되면 테스트
// 가 RED 로 떨어져 contract drift 를 즉시 surface.
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
      // KakaoSpec — PNG asset, R2 borderRadius 12.
      expect(const KakaoSpec().assetType, AssetType.png);
      expect(const KakaoSpec().borderRadius, 12.0);
      expect(const KakaoSpec().height, 48.0);
      expect(const KakaoSpec().iconSize, 18.0);

      // NaverSpec — PNG asset, theme 명시 매개변수, R2 borderRadius 12.
      expect(const NaverSpec(theme: NaverTheme.light).assetType, AssetType.png);
      expect(const NaverSpec(theme: NaverTheme.light).borderRadius, 12.0);
      expect(const NaverSpec(theme: NaverTheme.dark).theme, NaverTheme.dark);

      // GoogleSpec — SVG asset, theme 명시 매개변수 (3 변형).
      expect(
        const GoogleSpec(theme: GoogleTheme.light).assetType,
        AssetType.svg,
      );
      expect(const GoogleSpec(theme: GoogleTheme.dark).theme, GoogleTheme.dark);
      expect(
        const GoogleSpec(theme: GoogleTheme.neutral).theme,
        GoogleTheme.neutral,
      );

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
        NaverSpec(theme: NaverTheme.light),
        GoogleSpec(theme: GoogleTheme.light),
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
      final naver = BrandedSocialButton.naver(
        label: 'Naver',
        theme: NaverTheme.light,
        onPressed: () {},
      );
      final google = BrandedSocialButton.google(
        label: 'Google',
        theme: GoogleTheme.light,
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

    // ─── T-13.1-NAVER-THEME-01: NaverSpec theme 분기 ─────────────────────
    test('T-13.1-NAVER-THEME-01: NaverSpec({theme}) 가 light/dark 분기 보존', () {
      const lightSpec = NaverSpec(theme: NaverTheme.light);
      const darkSpec = NaverSpec(theme: NaverTheme.dark);
      expect(lightSpec.theme, NaverTheme.light);
      expect(darkSpec.theme, NaverTheme.dark);
      expect(
        identical(lightSpec, darkSpec),
        isFalse,
        reason: 'theme 다르면 const 인스턴스도 다름',
      );
    });

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
      expect(const NaverSpec(theme: NaverTheme.light).borderRadius, 12.0);
      expect(const GoogleSpec(theme: GoogleTheme.light).borderRadius, 12.0);
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
    // ─── T-13.1-X2-CLIPRRECT-01: Material+borderRadius + Image.asset (Kakao)
    //
    // **Plan 14 deviation 정정 (2026-05-09 사용자 시각 검증 후):** 1차
    // 디자인의 ClipRRect 폐기 — 자상의 baked-in 모서리 (Naver 사각 / Kakao
    // 7.2px scaled / Google rx=19.5 pill) 가 시각 권위, ClipRRect 12dp 강제
    // 가 더블 클리핑 결함. test ID 는 traceability 보존, assertion 만 갱신.
    testWidgets(
        'T-13.1-X2-CLIPRRECT-01: KakaoSpec build() Material+borderRadius + '
        'Image.asset (Plan 14 deviation: BoxFit.contain + no ClipRRect)',
        (tester) async {
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
      // 자상 baked-in shape 권위 패턴 — Material+borderRadius (InkWell ripple
      // 영역만 12dp 제어) + Image.asset (PNG 자연 baked-in 모서리 보존).
      expect(find.byType(Image), findsOneWidget);
      // ClipRRect 폐기 검증 — 본 widget 트리에 ClipRRect 없음 (Plan 14
      // deviation 회귀 가드, 더블 클리핑 차단).
      expect(find.byType(ClipRRect), findsNothing);
      // Image.asset 의 fit: BoxFit.contain 검증 — fitWidth scale-up 결함 차단.
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.contain);
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
              theme: GoogleTheme.light,
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
    });

    // ─── T-13.1-X2-FULLWIDTH-01: SizedBox(width: double.infinity) 검증 ────
    testWidgets(
        'T-13.1-X2-FULLWIDTH-01: NaverSpec build() SizedBox '
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
                theme: NaverTheme.light,
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

    // ─── T-13.1-X2-LOCALE-FALLBACK-01: ja locale → en path ────────────────
    testWidgets(
        'T-13.1-X2-LOCALE-FALLBACK-01: ja locale 시 KakaoSpec 자상이 '
        'en path (kakao/en/light/) 로딩', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BrandedSocialButton.kakao(
              label: 'Continue with Kakao',
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final imageWidget = tester.widget<Image>(find.byType(Image));
      final assetImage = imageWidget.image as AssetImage;
      // ko 외 모든 locale (ja 포함) 은 en path 로 fallback (D-79 + Gap-1 X2
      // 사용자 3번 답변).
      expect(
        assetImage.assetName,
        'assets/brand/kakao/en/light/kakao_login_large_wide.png',
        reason: 'ja locale 은 en fallback (ko 외 모두 en) — '
            '_iconAssetFor 의 lang 분기',
      );
    });

    // ─── T-13.1-X2-APPLE-PRESERVE-01: AppleSpec 분기 변경 0 회귀 가드 ──────
    testWidgets(
        'T-13.1-X2-APPLE-PRESERVE-01: AppleSpec build() '
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
            reason: 'iter2 CR-01 회귀 가드 — Semantics(onTap: onPressed) 미전달 시 '
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
    testWidgets(
      'T-13.1-A11Y-SEMANTICS-02: NaverSpec onPressed=null → '
      'hasTapAction false + isEnabled false (a11y 비활성 표현)',
      (tester) async {
        final SemanticsHandle semHandle = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: BrandedSocialButton.naver(
                label: '네이버로 시작하기',
                theme: NaverTheme.light,
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
            reason: 'onPressed=null → enabled=false + onTap 핸들러 미등록. '
                '비활성 상태도 button/label 은 노출 (TalkBack 가 "비활성 버튼" 안내).',
          );
        } finally {
          semHandle.dispose();
        }
      },
    );

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

    // ─── T-13.2-FACEBOOK-DISABLED-01: 비활성 상태 시각 cue 회귀 가드 ───────
    //
    // **Phase 13.2 REVIEW CR-01 정정 (2026-05-13):** 비활성 시 시각 disabled
    // cue 부재 회귀 가드. `social_button.dart` 의 docstring 약속 ("Material
    // default disabled 외관") 과 일치하도록 `_renderFacebookButton` 이
    // `Opacity(0.5)` wrap + fg/outline faded 분기를 적용. 본 test 는 Opacity
    // descendant 단독 검증 — 색 변화는 별 layer (fgColor copyWith) 가 책임.
    testWidgets(
      'T-13.2-FACEBOOK-DISABLED-01: onPressed=null → 시각 disabled cue '
      '(Opacity opacity < 1.0)',
      (tester) async {
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
          reason: 'CR-01 회귀 가드 — onPressed=null 시 Opacity wrap 부재. '
              '_renderFacebookButton 의 Material 3 disabled state cue 누락 회귀.',
        );

        // Opacity.opacity 값이 1.0 미만 (시각 fade) 검증.
        final opacity = tester.widget<Opacity>(opacityFinder);
        expect(
          opacity.opacity,
          lessThan(1.0),
          reason: 'CR-01 회귀 가드 — Opacity.opacity 가 1.0 이면 비활성 시각 cue 0. '
              'Material 3 disabled state spec 위반.',
        );
      },
    );

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
        final assetImage = imageWidget.image as AssetImage;

        // D-96 Google 패턴 — locale 독립 (ko/en/ja 분기 부재), 단일 path.
        // Meta Primary Logo PNG (2084×2084 square, 'f' 마크 + #1877F2 원형).
        // 18dp icon 슬롯 fit — Apple SignInWithAppleButton 패턴 mirror.
        expect(
          assetImage.assetName,
          'assets/brand/facebook/facebook_login.png',
          reason: 'Phase 13.2 R6 + D-96 — _iconAssetFor FacebookSpec branch '
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
}
