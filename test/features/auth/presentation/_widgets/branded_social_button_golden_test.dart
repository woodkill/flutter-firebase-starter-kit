// 소셜 버튼 단독 golden — 버튼 6개 × 밝은 · 어두운 테마.
//
// 버튼 한 개를 360 × 480 화면 가운데에 그려 파일 단위로 대조한다(허용 오차 0).
// 문구는 en 고정이다 — 문구 대조는 `brand_label_whitelist_test.dart` 가 맡는다.
//
// iOS 케이스는 macOS 에서만 돈다. 라벨을 macOS 시스템 글꼴로 그리므로 그 PNG
// (`*_ios.png`)는 저장소에 두지 않는다 — `.gitignore` 에 파일마다 한 줄씩 있다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// [child] 를 폭 360 상자에 담아 [brightness] 테마 · en locale 로 감싼다.
///
/// 앱 테마([AppTheme])를 그대로 쓴다. locale 과 delegate 를 명시해 테스트를
/// 돌리는 기기의 언어 설정이 golden 에 섞이지 않게 한다. DEBUG 배너는 끈다.
///
/// [platform] 을 주면 테마의 플랫폼만 바꾼다 — iOS 케이스가 쓴다. 주지 않으면
/// 테스트 기본값(Android)이다.
Widget _wrap(
  Widget child, {
  required Brightness brightness,
  TargetPlatform? platform,
}) {
  final baseTheme = brightness == Brightness.light
      ? AppTheme.light()
      : AppTheme.dark();
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: platform != null
        ? baseTheme.copyWith(platform: platform)
        : baseTheme,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      backgroundColor: brightness == Brightness.light
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF000000),
      body: Center(child: SizedBox(width: 360, child: child)),
    ),
  );
}

/// 로고 자산이 다 그려질 때까지 기다린 뒤 frame 을 안정시킨다.
///
/// 로고(SVG · 비트맵)는 비동기로 올라온다. `pumpAndSettle` 만으로는 로고가
/// 그려지기 전에 golden 이 찍혀 로고 자리가 빈다. `runAsync` 안에서 비트맵을
/// 미리 디코딩하고 SVG 로드를 잠깐 기다린 다음 다시 settle 한다.
Future<void> _settleAssets(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpAndSettle();

    // (1) 비트맵 로고를 미리 디코딩한다.
    for (final element in find.byType(Image).evaluate().toList()) {
      final widget = element.widget as Image;
      await precacheImage(widget.image, element);
    }

    // (2) SVG 로고는 microtask 로 올라온다 — 짧게 기다려 첫 layout 을 맞춘다.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // (3) 마지막으로 frame 을 안정시킨다.
    await tester.pumpAndSettle();
  });
  // runAsync 밖에서 한 번 더 pump 해 안쪽 frame 을 캡처 단계로 넘긴다.
  await tester.pumpAndSettle();
}

/// 버튼 라벨이 쓰는 글꼴 family 를 올린다.
///
/// flutter_test 의 기본 글꼴은 모든 글자를 같은 상자로 그린다. 라벨이 쓰는
/// family 를 올려야 golden 에 실제 글자가 찍힌다. 올리는 family 와 순서는 다음과
/// 같다.
///
/// - `Roboto` — Google 을 뺀 5개 버튼의 라벨. 테스트 전용 자산
///   `assets/test_fonts/Roboto-Medium.ttf` 를 올린다.
/// - `GoogleSans` — Google 버튼의 라벨. 번들한 라틴 축소본이다.
/// - `CupertinoSystemText` — iOS 케이스의 라벨. macOS 에서만 시스템 글꼴 파일
///   `SFNS.ttf` 를 이 이름으로 올린다.
///
/// 자산이 없으면 [TestFailure] 로 알린다 — 조용히 넘어가면 golden 이 상자
/// 글자로 다시 만들어진다.
Future<void> _loadGoldenFonts() async {
  final robotoFile = File('assets/test_fonts/Roboto-Medium.ttf');
  if (!robotoFile.existsSync()) {
    throw TestFailure(
      'Roboto-Medium.ttf 부재 (assets/test_fonts/Roboto-Medium.ttf) — '
      'golden test 라벨 글리프 회귀 가드 불가. Phase 13.3 D-119 (golden 라벨 '
      'Ahem ▮▮ 회피) 자산 누락 — `assets/test_fonts/` 디렉토리 / file 갱신 '
      '의무 (IN-06 정정).',
    );
  }
  final robotoLoader = FontLoader('Roboto');
  final robotoBytes = await robotoFile.readAsBytes();
  robotoLoader.addFont(Future.value(ByteData.view(robotoBytes.buffer)));
  await robotoLoader.load();

  final googleSansFile = File(
    'assets/fonts/googlesans/GoogleSans-Latin-wght.ttf',
  );
  if (!googleSansFile.existsSync()) {
    throw TestFailure(
      'GoogleSans 글꼴 자산 부재 '
      '(assets/fonts/googlesans/GoogleSans-Latin-wght.ttf) — Google 버튼 '
      '라벨이 Ahem 상자로 그려진다. `pubspec.yaml` fonts: 항목과 파일을 확인한다.',
    );
  }
  final googleSansLoader = FontLoader('GoogleSans');
  final googleSansBytes = await googleSansFile.readAsBytes();
  googleSansLoader.addFont(Future.value(ByteData.view(googleSansBytes.buffer)));
  await googleSansLoader.load();

  if (Platform.isMacOS) {
    // iOS 케이스의 라벨 글꼴 — macOS 시스템 글꼴 파일을 버튼이 쓰는 이름으로
    // 올린다. 이 파일의 라벨은 영문뿐이라 한글 face 는 필요 없다.
    final systemFontFile = File('/System/Library/Fonts/SFNS.ttf');
    if (!systemFontFile.existsSync()) {
      throw TestFailure(
        'macOS SFNS.ttf 부재 (/System/Library/Fonts/SFNS.ttf) — iOS 케이스의 '
        '라벨을 시스템 글꼴로 그릴 수 없다. 시스템 글꼴 위치를 확인한다.',
      );
    }
    final systemFontLoader = FontLoader('CupertinoSystemText');
    final systemFontBytes = await systemFontFile.readAsBytes();
    systemFontLoader.addFont(
      Future.value(ByteData.view(systemFontBytes.buffer)),
    );
    await systemFontLoader.load();
  }
}

void main() {
  setUpAll(_loadGoldenFonts);

  group('BrandedSocialButton golden — 버튼 6개 × 밝은 · 어두운', () {
    testWidgets('Naver light', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.naver(
            label: 'Log in with NAVER',
            onPressed: () {},
          ),
          brightness: Brightness.light,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/naver_light.png'),
      );
    });

    testWidgets('Naver light (iOS)', skip: !Platform.isMacOS, (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.naver(
            label: 'Log in with NAVER',
            onPressed: () {},
          ),
          brightness: Brightness.light,
          platform: TargetPlatform.iOS,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/naver_light_ios.png'),
      );
    });

    testWidgets('Naver dark', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.naver(
            label: 'Log in with NAVER',
            onPressed: () {},
          ),
          brightness: Brightness.dark,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/naver_dark.png'),
      );
    });

    testWidgets('Naver dark (iOS)', skip: !Platform.isMacOS, (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.naver(
            label: 'Log in with NAVER',
            onPressed: () {},
          ),
          brightness: Brightness.dark,
          platform: TargetPlatform.iOS,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/naver_dark_ios.png'),
      );
    });

    testWidgets('Kakao light', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.kakao(
            label: 'Login with Kakao',
            onPressed: () {},
          ),
          brightness: Brightness.light,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/kakao_light.png'),
      );
    });

    testWidgets('Kakao light (iOS)', skip: !Platform.isMacOS, (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.kakao(
            label: 'Login with Kakao',
            onPressed: () {},
          ),
          brightness: Brightness.light,
          platform: TargetPlatform.iOS,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/kakao_light_ios.png'),
      );
    });

    testWidgets('Kakao dark', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.kakao(
            label: 'Login with Kakao',
            onPressed: () {},
          ),
          brightness: Brightness.dark,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/kakao_dark.png'),
      );
    });

    testWidgets('Kakao dark (iOS)', skip: !Platform.isMacOS, (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.kakao(
            label: 'Login with Kakao',
            onPressed: () {},
          ),
          brightness: Brightness.dark,
          platform: TargetPlatform.iOS,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/kakao_dark_ios.png'),
      );
    });

    testWidgets('Google light', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.google(
            label: 'Sign in with Google',
            onPressed: () {},
          ),
          brightness: Brightness.light,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/google_light.png'),
      );
    });

    testWidgets('Google dark', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.google(
            label: 'Sign in with Google',
            onPressed: () {},
          ),
          brightness: Brightness.dark,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/google_dark.png'),
      );
    });

    testWidgets('Google light (iOS)', skip: !Platform.isMacOS, (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.google(
            label: 'Sign in with Google',
            onPressed: () {},
          ),
          brightness: Brightness.light,
          platform: TargetPlatform.iOS,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/google_light_ios.png'),
      );
    });

    testWidgets('Google dark (iOS)', skip: !Platform.isMacOS, (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.google(
            label: 'Sign in with Google',
            onPressed: () {},
          ),
          brightness: Brightness.dark,
          platform: TargetPlatform.iOS,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/google_dark_ios.png'),
      );
    });

    testWidgets('Facebook light', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.facebook(
            label: 'Login with Facebook',
            onPressed: () {},
          ),
          brightness: Brightness.light,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/facebook_light.png'),
      );
    });

    testWidgets('Facebook dark', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.facebook(
            label: 'Login with Facebook',
            onPressed: () {},
          ),
          brightness: Brightness.dark,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/facebook_dark.png'),
      );
    });

    testWidgets('Facebook light (iOS)', skip: !Platform.isMacOS, (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.facebook(
            label: 'Login with Facebook',
            onPressed: () {},
          ),
          brightness: Brightness.light,
          platform: TargetPlatform.iOS,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/facebook_light_ios.png'),
      );
    });

    testWidgets('Facebook dark (iOS)', skip: !Platform.isMacOS, (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.facebook(
            label: 'Login with Facebook',
            onPressed: () {},
          ),
          brightness: Brightness.dark,
          platform: TargetPlatform.iOS,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/facebook_dark_ios.png'),
      );
    });

    testWidgets('Apple light', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.apple(
            label: 'Sign in with Apple',
            onPressed: () {},
          ),
          brightness: Brightness.light,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/apple_light.png'),
      );
    });

    testWidgets('Apple dark', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.apple(
            label: 'Sign in with Apple',
            onPressed: () {},
          ),
          brightness: Brightness.dark,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/apple_dark.png'),
      );
    });

    testWidgets('Apple light (iOS)', skip: !Platform.isMacOS, (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.apple(
            label: 'Sign in with Apple',
            onPressed: () {},
          ),
          brightness: Brightness.light,
          platform: TargetPlatform.iOS,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/apple_light_ios.png'),
      );
    });

    testWidgets('Apple dark (iOS)', skip: !Platform.isMacOS, (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.apple(
            label: 'Sign in with Apple',
            onPressed: () {},
          ),
          brightness: Brightness.dark,
          platform: TargetPlatform.iOS,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/apple_dark_ios.png'),
      );
    });

    testWidgets('LINE light', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.line(label: 'Log in with LINE', onPressed: () {}),
          brightness: Brightness.light,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/line_light.png'),
      );
    });

    testWidgets('LINE dark', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.line(label: 'Log in with LINE', onPressed: () {}),
          brightness: Brightness.dark,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/line_dark.png'),
      );
    });

    testWidgets('LINE light (iOS)', skip: !Platform.isMacOS, (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.line(label: 'Log in with LINE', onPressed: () {}),
          brightness: Brightness.light,
          platform: TargetPlatform.iOS,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/line_light_ios.png'),
      );
    });

    testWidgets('LINE dark (iOS)', skip: !Platform.isMacOS, (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.line(label: 'Log in with LINE', onPressed: () {}),
          brightness: Brightness.dark,
          platform: TargetPlatform.iOS,
        ),
      );
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/line_dark_ios.png'),
      );
    });
  });
}
