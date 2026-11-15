// 홈 화면 앱 아이콘 규격 — 파일 표 · 킷 기본 지문 · Android adaptive 파일 ·
// 승인판에서 고른 여백 · 배경 값 · 표식 · 작업 폴더 이름.
//
// 위저드 「앱 아이콘」 단계가 한 원본에서 iOS 15장 · Android legacy 5장 ·
// adaptive 전경 5장 · adaptive XML · 배경색 파일을 만들 때 이 표만 읽는다.
//
// 규격 출처(공식 문서 원문 · 확인 2026-11):
//  iOS      ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json
//           파일 이름 `Icon-App-<크기>@<배율>x.png` · 한 변 = 크기 × 배율.
//  Android  https://developer.android.com/develop/ui/views/launch/icon_design_adaptive
//           레이어는 108dp · 로고는 48dp 이상 66dp 이하 · `res/mipmap-anydpi-v26/
//           ic_launcher.xml` 의 `<adaptive-icon>` 이 전경 · 배경 레이어를 묶는다.
//           legacy `mipmap-<밀도>/ic_launcher.png` 는 48dp(48 · 72 · 96 · 144 · 192).
import '../providers/icon_specs.dart' show iconsDirectory;
import 'icon_pipeline.dart' show formatHexRgb;

/// iOS 앱 아이콘 폴더 — 저장소 루트 기준.
const String iosAppIconDirectory =
    'ios/Runner/Assets.xcassets/AppIcon.appiconset';

/// Android 리소스 폴더 — 저장소 루트 기준.
const String androidResDirectory = 'android/app/src/main/res';

/// 홈 화면 아이콘 파일 한 행 — 경로 · 한 변 · 킷 기본 지문.
final class HomeIconFile {
  /// 저장소 루트 기준 경로 [relativePath] · 한 변 [side] · 킷 기본 지문
  /// [kitDigest] 로 행을 만든다.
  const HomeIconFile({
    required this.relativePath,
    required this.side,
    required this.kitDigest,
  });

  /// 저장소 루트 기준 경로.
  final String relativePath;

  /// 정사각 PNG 한 변(px).
  final int side;

  /// 킷이 처음 담은 파일 바이트의 sha256(소문자 16진 64자).
  final String kitDigest;
}

/// 홈 화면 아이콘 20장 — iOS 15장 · Android legacy 5장.
///
/// 지문이 모두 이 값과 같으면 킷 기본 아이콘이다. 같은 바이트의 두 쌍
/// (20@2x = 40@1x · 40@3x = 60@2x)은 지문도 같다.
const List<HomeIconFile> homeIconFiles = <HomeIconFile>[
  HomeIconFile(
    relativePath: '$iosAppIconDirectory/Icon-App-1024x1024@1x.png',
    side: 1024,
    kitDigest:
        '7770183009e914112de7d8ef1d235a6a30c5834424858e0d2f8253f6b8d31926',
  ),
  HomeIconFile(
    relativePath: '$iosAppIconDirectory/Icon-App-20x20@1x.png',
    side: 20,
    kitDigest:
        'cab10a0d391ec5bc09ef50ce49e8ad401cee7ef03707ec0923a222c5c2b3d212',
  ),
  HomeIconFile(
    relativePath: '$iosAppIconDirectory/Icon-App-20x20@2x.png',
    side: 40,
    kitDigest:
        'b9ad02cf6576a04d1b6806ac02a2431481b448dd0c2e505ce25842d1f7c4730b',
  ),
  HomeIconFile(
    relativePath: '$iosAppIconDirectory/Icon-App-20x20@3x.png',
    side: 60,
    kitDigest:
        'c6e6d3b215ae744a9c391f4c4d44157eff5e739d6ad6c39f9bfa5df66dddd267',
  ),
  HomeIconFile(
    relativePath: '$iosAppIconDirectory/Icon-App-29x29@1x.png',
    side: 29,
    kitDigest:
        '5dee24dc104ac76dc162e42ae0beb163d426bf365562ee28ba7b3ad368559a60',
  ),
  HomeIconFile(
    relativePath: '$iosAppIconDirectory/Icon-App-29x29@2x.png',
    side: 58,
    kitDigest:
        'a9b21eb6f4271385655a8771f76e29eef8c1107d7879cbcfc567e6619d1f716a',
  ),
  HomeIconFile(
    relativePath: '$iosAppIconDirectory/Icon-App-29x29@3x.png',
    side: 87,
    kitDigest:
        'e677d701ffe4af7bc2935098d6b3984cc9ab7ace573e6900955a5535b12410cf',
  ),
  HomeIconFile(
    relativePath: '$iosAppIconDirectory/Icon-App-40x40@1x.png',
    side: 40,
    kitDigest:
        'b9ad02cf6576a04d1b6806ac02a2431481b448dd0c2e505ce25842d1f7c4730b',
  ),
  HomeIconFile(
    relativePath: '$iosAppIconDirectory/Icon-App-40x40@2x.png',
    side: 80,
    kitDigest:
        '7c61c42fc7b657d9cf314d32a4ec458f0647c3aaf360be1b9377857266ec2499',
  ),
  HomeIconFile(
    relativePath: '$iosAppIconDirectory/Icon-App-40x40@3x.png',
    side: 120,
    kitDigest:
        '19be171481dc71a0b2803ebcd01dd8b0c5fd5778dee34c0a3cabc948c225f24e',
  ),
  HomeIconFile(
    relativePath: '$iosAppIconDirectory/Icon-App-60x60@2x.png',
    side: 120,
    kitDigest:
        '19be171481dc71a0b2803ebcd01dd8b0c5fd5778dee34c0a3cabc948c225f24e',
  ),
  HomeIconFile(
    relativePath: '$iosAppIconDirectory/Icon-App-60x60@3x.png',
    side: 180,
    kitDigest:
        '4209a49e44a92ec40a327d3455eb1b1c153ee83d75de1c2be0a12ab18b2ff9de',
  ),
  HomeIconFile(
    relativePath: '$iosAppIconDirectory/Icon-App-76x76@1x.png',
    side: 76,
    kitDigest:
        '836c918cb613249eba0483a6b02fa3df3c1c0a89a315ee4d3b88509b83c7ab73',
  ),
  HomeIconFile(
    relativePath: '$iosAppIconDirectory/Icon-App-76x76@2x.png',
    side: 152,
    kitDigest:
        '41c7d42f6e61f8fe7f30b1ffa2256aecbc9682be06d18c4a3062043e1a2e547c',
  ),
  HomeIconFile(
    relativePath: '$iosAppIconDirectory/Icon-App-83.5x83.5@2x.png',
    side: 167,
    kitDigest:
        '5d7e5bdf01b93802bc973345b3a78c038907147625035952a08a115a563b7f81',
  ),
  HomeIconFile(
    relativePath: '$androidResDirectory/mipmap-mdpi/ic_launcher.png',
    side: 48,
    kitDigest:
        'c7c0c0189145e4e32a401c61c9bdc615754b0264e7afae24e834bb81049eaf81',
  ),
  HomeIconFile(
    relativePath: '$androidResDirectory/mipmap-hdpi/ic_launcher.png',
    side: 72,
    kitDigest:
        '6a7c8f0d703e3682108f9662f813302236240d3f8f638bb391e32bfb96055fef',
  ),
  HomeIconFile(
    relativePath: '$androidResDirectory/mipmap-xhdpi/ic_launcher.png',
    side: 96,
    kitDigest:
        'e14aa40904929bf313fded22cf7e7ffcbf1d1aac4263b5ef1be8bfce650397aa',
  ),
  HomeIconFile(
    relativePath: '$androidResDirectory/mipmap-xxhdpi/ic_launcher.png',
    side: 144,
    kitDigest:
        '4d470bf22d5c17d84edc5f82516d1ba8a1c09559cd761cefb792f86d9f52b540',
  ),
  HomeIconFile(
    relativePath: '$androidResDirectory/mipmap-xxxhdpi/ic_launcher.png',
    side: 192,
    kitDigest:
        '3c34e1f298d0c9ea3455d46db6b7759c8211a49e9ec6e44b635fc5c87dfb4180',
  ),
];

/// iOS 1024 아이콘 경로 — 채운 그림 크기 그대로이고 표식이 이 파일 바이트를 본다.
const String ios1024Path = '$iosAppIconDirectory/Icon-App-1024x1024@1x.png';

/// [homeIconFiles] 를 경로 → 킷 기본 지문 맵으로 만든다.
Map<String, String> buildKitDefaultDigests() => <String, String>{
  for (final HomeIconFile file in homeIconFiles)
    file.relativePath: file.kitDigest,
};

/// adaptive 전경 PNG 한 밀도 — 밀도 이름과 108dp 캔버스의 한 변(px).
final class AdaptiveDensity {
  /// 밀도 이름 [name](`mdpi` 등)과 캔버스 한 변 [canvasSide] 로 값을 만든다.
  const AdaptiveDensity(this.name, this.canvasSide);

  /// 밀도 이름 — `mipmap-<name>` 폴더 이름의 뒷부분.
  final String name;

  /// 108dp 캔버스의 한 변(px).
  final int canvasSide;

  /// 전경 PNG 경로 — 저장소 루트 기준.
  String get foregroundPath =>
      '$androidResDirectory/mipmap-$name/ic_launcher_foreground.png';
}

/// adaptive 전경 다섯 밀도 — 108dp × 1 · 1.5 · 2 · 3 · 4.
const List<AdaptiveDensity> adaptiveDensities = <AdaptiveDensity>[
  AdaptiveDensity('mdpi', 108),
  AdaptiveDensity('hdpi', 162),
  AdaptiveDensity('xhdpi', 216),
  AdaptiveDensity('xxhdpi', 324),
  AdaptiveDensity('xxxhdpi', 432),
];

/// adaptive 아이콘 XML 경로 — API 26 이상에서 legacy PNG 대신 쓰인다.
const String adaptiveIconXmlPath =
    '$androidResDirectory/mipmap-anydpi-v26/ic_launcher.xml';

/// adaptive 배경색 리소스 경로.
const String adaptiveBackgroundPath =
    '$androidResDirectory/values/ic_launcher_background.xml';

/// 위저드가 만드는 adaptive 파일 7개 — 전경 5 · XML · 배경색 순서.
List<String> listAdaptiveFilePaths() => <String>[
  for (final AdaptiveDensity density in adaptiveDensities)
    density.foregroundPath,
  adaptiveIconXmlPath,
  adaptiveBackgroundPath,
];

/// adaptive 아이콘 XML 원문 — 배경은 색 리소스 · 전경은 밀도별 PNG 다.
///
/// `roundIcon` · monochrome 레이어는 두지 않는다.
String buildAdaptiveIconXml() =>
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon '
    'xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@color/ic_launcher_background" />\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
    '</adaptive-icon>\n';

/// adaptive 배경색 리소스 원문 — 색은 [rgb](`0xRRGGBB`)의 `#RRGGBB` 다.
String buildAdaptiveBackgroundXml(int rgb) =>
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<resources>\n'
    '    <color name="ic_launcher_background">${formatHexRgb(rgb)}</color>\n'
    '</resources>\n';

/// 투명 로고 원본의 adaptive 전경 로고 한 변(dp · 108dp 캔버스 안).
///
/// 승인판에서 고른 값이다 — 바꾸면 비교판으로 다시 고른다.
const double logoForegroundDp = 66;

/// 칠한 그림(투명 픽셀 없는 원본)의 adaptive 전경 그림 한 변(dp · 108dp 캔버스 안).
///
/// 승인판에서 고른 값이다 — 바꾸면 비교판으로 다시 고른다.
const double paintedForegroundDp = 72;

/// 칠한 그림 원본의 adaptive 배경 레이어 색을 정하는 방법.
enum PaintedBackground {
  /// 늘 흰색.
  white,

  /// 채운 그림 가장자리 1px 고리의 평균색.
  edge,
}

/// 칠한 그림 원본의 adaptive 배경 레이어 색.
///
/// 승인판에서 고른 값이다 — 바꾸면 비교판으로 다시 고른다.
const PaintedBackground paintedBackground = PaintedBackground.edge;

/// 투명한 원본을 채울 배경색 질문의 기본값(`0xRRGGBB` · Enter 값) — 흰색.
const int defaultBackgroundRgb = 0xFFFFFF;

/// 콘솔 아이콘을 어느 iOS 1024 에서 만들었는지 적는 표식 파일 이름 — 줄마다
/// `<그때 iOS 1024 바이트의 sha256> <수단 token>` 을 담는다.
///
/// 원본 사본 이름(`source.<형식>`)과 겹치지 않게 `source.` 로 시작하지 않는다.
const String homeIconMarkerName = 'home-icon.sha256';

/// 표식 파일 경로 — 저장소 루트 기준.
const String homeIconMarkerPath = '$iconsDirectory/$homeIconMarkerName';

/// 아이콘을 만들 때 쓰는 작업 폴더 — 실행마다 만들고 지운다(gitignored).
const String iconWorkDirectory = '.setup/app-icon-work';

/// 원본을 맞출 sRGB 색 프로파일 경로(macOS 기본 프로파일).
const String srgbProfilePath =
    '/System/Library/ColorSync/Profiles/sRGB Profile.icc';
