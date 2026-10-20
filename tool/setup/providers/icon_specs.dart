import 'dart:io';

import '../confirm.dart';
import '../wizard.dart';

/// 앱 아이콘 단계가 만든 파일을 두는 폴더 — 저장소 루트 기준 · flavor 무관.
///
/// `.setup/` 은 gitignored 이고 `flutter clean` 에도 지워지지 않는다.
const String iconsDirectory = '.setup/icons';

/// 원본 사본의 이름 앞부분 — 사본 이름은 `source.<sips 형식>` 이다.
const String sourceCopyBaseName = 'source';

/// 원본 이미지 한 변의 하한(px) — 가장 큰 대상 규격에 맞춘다.
const int minSourceSide = 1024;

/// 원본 이미지 한 변의 상한(px) — 변환 전에 헤더 값으로 막는다.
const int maxSourceSide = 16384;

/// 아이콘 파일이 아직 없을 때 값 표에 보일 문장.
const String missingIconValue = '(아직 없음 — 다시 실행하면 앱 아이콘 단계가 원본 이미지를 묻습니다)';

/// provider 콘솔이 아이콘을 요구하는 정도.
enum IconRequirement {
  /// 아이콘이 없으면 콘솔이 앱을 저장하지 않는다.
  required('필수', null),

  /// 올리지 않아도 된다.
  optional('선택', null),

  /// 앱을 게시할 때만 필요하다.
  requiredToPublish('앱 게시 때 필수', '앱을 게시할 때 필수이고 개발 모드 로그인에는 필요 없습니다'),

  /// 출시 전에 올려도 되지만 올리면 브랜드 인증을 거쳐야 보인다.
  optionalBeforeRelease(
    '출시 전 선택',
    '출시 전 선택입니다 — 올리면 Google 의 브랜드 인증을 거쳐야 동의 화면에 보입니다',
  );

  /// 짧은 라벨 [shortLabel] 과 덧붙일 설명 [explanation] 으로 값을 만든다.
  const IconRequirement(this.shortLabel, this.explanation);

  /// 값 표 행 라벨에 붙는 짧은 라벨.
  final String shortLabel;

  /// 값 표 아래 노트로 보일 설명 — 없으면 null.
  final String? explanation;
}

/// provider 콘솔 아이콘 규격 한 행.
final class IconSpec {
  /// 토큰 · 한 변 · 용량 상한 · 콘솔 라벨 · 요구 정도로 행을 만든다.
  const IconSpec({
    required this.token,
    required this.side,
    required this.maxBytes,
    required this.consoleLabel,
    required this.requirement,
  });

  /// 로그인 수단 토큰(`enabledAuthProviders` 와 같은 값).
  final String token;

  /// 정사각 PNG 한 변(px).
  final int side;

  /// 파일 용량 상한(10진 바이트 · 이하).
  final int maxBytes;

  /// 콘솔의 칸 이름 또는 기능 이름.
  final String consoleLabel;

  /// 콘솔이 아이콘을 요구하는 정도.
  final IconRequirement requirement;

  /// 파일 이름 — `<token>-<side>x<side>.png`.
  String get fileName => '$token-${side}x$side.png';

  /// 저장소 루트 기준 경로.
  String get relativePath => '$iconsDirectory/$fileName';

  /// 값 표 행 라벨 — `<콘솔 라벨> · <요구 정도>`.
  String get rowLabel => '$consoleLabel · ${requirement.shortLabel}';
}

// 규격 출처(공식 문서 원문 · 콘솔 화면 · 확인 2026-10):
//  Google   https://support.google.com/cloud/answer/15549049
//           1MB 이하 · JPG/PNG/BMP · 120x120 권장 · 선택. 올리면 브랜드 인증 뒤에
//           동의 화면에 보인다 — https://developers.google.com/identity/protocols/oauth2/production-readiness/brand-verification
//  Facebook https://developers.facebook.com/docs/pages-api/create-an-app
//           5 MB 미만 · 512x512 ~ 1024x1024 · JPEG/GIF/PNG. Live 전환 때 필수 —
//           https://developers.facebook.com/docs/development/create-an-app/app-dashboard/basic-settings
//  Kakao    https://developers.kakao.com/docs/latest/ko/app-setting/app
//           250KB 미만 · 128x128 이하 권장 · 선택
//  Naver    공식 문서에 숫자가 없다 — 콘솔 화면 확인(2026-10): 애플리케이션 등록의
//           로고 이미지 · 권장 140x140 · 500KB 이하 · 필수(없으면 저장되지 않는다)
//  LINE     https://developers.line.biz/en/docs/line-login/getting-started/
//           Channel icon 은 선택. 용량은 콘솔 화면 확인(2026-10): 3MB 이하 · 크기
//           규정 없음. 512x512 를 고른 까닭 — 비압축 RGBA PNG 도 약 1.05MB 라
//           어떤 원본이어도 3MB 를 넘지 않는다.

/// provider 콘솔 아이콘 규격 표 — 순서는 로그인 수단 표 순서다.
///
/// 규격 숫자가 바뀌면 이 표의 한 줄만 고친다. Apple 은 콘솔에 아이콘 칸이 없어
/// 표에 없다.
const List<IconSpec> iconSpecs = <IconSpec>[
  IconSpec(
    token: 'google',
    side: 120,
    maxBytes: 1000000,
    consoleLabel: '동의 화면 로고',
    requirement: IconRequirement.optionalBeforeRelease,
  ),
  IconSpec(
    token: 'facebook',
    side: 1024,
    maxBytes: 5000000,
    consoleLabel: '앱 아이콘(1024 x 1024)',
    requirement: IconRequirement.requiredToPublish,
  ),
  IconSpec(
    token: 'kakao',
    side: 128,
    maxBytes: 250000,
    consoleLabel: '앱 아이콘 올리기',
    requirement: IconRequirement.optional,
  ),
  IconSpec(
    token: 'naver',
    side: 140,
    maxBytes: 500000,
    consoleLabel: '로고 이미지',
    requirement: IconRequirement.required,
  ),
  IconSpec(
    token: 'line',
    side: 512,
    maxBytes: 3000000,
    consoleLabel: 'Channel icon',
    requirement: IconRequirement.optional,
  ),
];

/// [token] 의 아이콘 규격을 찾는다 — 없으면 null.
IconSpec? findIconSpec(String token) {
  for (final IconSpec spec in iconSpecs) {
    if (spec.token == token) return spec;
  }
  return null;
}

/// 켠 로그인 수단 [enabledProviders] 가운데 아이콘 대상의 규격을 표 순서로 고른다.
List<IconSpec> selectIconTargets(Set<String> enabledProviders) => iconSpecs
    .where((IconSpec spec) => enabledProviders.contains(spec.token))
    .toList();

/// 값 표에 보일 [spec] 아이콘 경로 — 파일이 없으면 [missingIconValue].
String describeIconPath(WizardContext context, IconSpec spec) =>
    File(context.resolve(spec.relativePath)).existsSync()
    ? spec.relativePath
    : missingIconValue;

/// [spec] 아이콘의 값 표 행을 만든다.
SummaryRow buildIconRow(WizardContext context, IconSpec spec) =>
    SummaryRow(spec.rowLabel, describeIconPath(context, spec));

/// [spec] 의 요구 정도 설명 노트를 만든다 — 설명이 없으면 null.
String? buildIconNote(IconSpec spec) {
  final String? explanation = spec.requirement.explanation;
  if (explanation == null) return null;
  return '${spec.consoleLabel}: $explanation';
}
