import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/confirm.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/icon_specs.dart';
import '../../../tool/setup/providers/provider_catalog.dart';
import 'fakes.dart';

/// 규격 표 한 행의 기대값.
typedef ExpectedSpec = ({
  String token,
  int side,
  int maxBytes,
  String fileName,
  String consoleLabel,
  IconRequirement requirement,
  String rowLabel,
});

/// 규격 표 다섯 행의 기대값(로그인 수단 표 순서).
const List<ExpectedSpec> expectedSpecs = <ExpectedSpec>[
  (
    token: 'google',
    side: 120,
    maxBytes: 1000000,
    fileName: 'google-120x120.png',
    consoleLabel: '동의 화면 로고',
    requirement: IconRequirement.optionalBeforeRelease,
    rowLabel: '동의 화면 로고 · 출시 전 선택',
  ),
  (
    token: 'facebook',
    side: 1024,
    maxBytes: 5000000,
    fileName: 'facebook-1024x1024.png',
    consoleLabel: '앱 아이콘(1024 x 1024)',
    requirement: IconRequirement.requiredToPublish,
    rowLabel: '앱 아이콘(1024 x 1024) · 앱 게시 때 필수',
  ),
  (
    token: 'kakao',
    side: 128,
    maxBytes: 250000,
    fileName: 'kakao-128x128.png',
    consoleLabel: '앱 아이콘 올리기',
    requirement: IconRequirement.optional,
    rowLabel: '앱 아이콘 올리기 · 선택',
  ),
  (
    token: 'naver',
    side: 140,
    maxBytes: 500000,
    fileName: 'naver-140x140.png',
    consoleLabel: '로고 이미지',
    requirement: IconRequirement.required,
    rowLabel: '로고 이미지 · 필수',
  ),
  (
    token: 'line',
    side: 512,
    maxBytes: 3000000,
    fileName: 'line-512x512.png',
    consoleLabel: 'Channel icon',
    requirement: IconRequirement.optional,
    rowLabel: 'Channel icon · 선택',
  ),
];

/// 한 변 [side] 정사각 RGBA PNG 의 최악(비압축) 크기 상한을 계산한다.
///
/// 줄마다 필터 바이트 1 · zlib stored 블록 머리 5바이트/65,535바이트 · 청크와
/// 색 프로파일 등 덧붙는 청크 여유 8,192바이트.
double computeWorstPngBytes(int side) =>
    (side * side * 4 + side) * (1 + 5 / 65535) + 8192;

void main() {
  test('T-20.1-SPEC-01: 규격 표 다섯 행이 토큰 · 크기 · 상한 · 파일 이름 · '
      '콘솔 라벨 · 요구 정도 그대로다', () {
    expect(iconSpecs, hasLength(expectedSpecs.length));
    for (var i = 0; i < expectedSpecs.length; i++) {
      final ExpectedSpec expected = expectedSpecs[i];
      final IconSpec spec = iconSpecs[i];
      expect(spec.token, expected.token, reason: '$i');
      expect(spec.side, expected.side, reason: expected.token);
      expect(spec.maxBytes, expected.maxBytes, reason: expected.token);
      expect(spec.fileName, expected.fileName, reason: expected.token);
      expect(spec.consoleLabel, expected.consoleLabel, reason: expected.token);
      expect(spec.requirement, expected.requirement, reason: expected.token);
      expect(spec.rowLabel, expected.rowLabel, reason: expected.token);
      expect(
        spec.relativePath,
        '.setup/icons/${expected.fileName}',
        reason: expected.token,
      );
    }
  });

  test('T-20.1-SPEC-02: 토큰은 로그인 수단 표에 있고 순서가 같으며 '
      'Apple 은 대상이 아니다', () {
    final List<String> tokens = iconSpecs
        .map((IconSpec spec) => spec.token)
        .toList();
    for (final token in tokens) {
      expect(findProvider(token), isNotNull, reason: token);
    }
    expect(
      providerCatalog
          .map((ProviderEntry entry) => entry.token)
          .where(tokens.contains)
          .toList(),
      tokens,
    );
    expect(tokens, isNot(contains('apple')));
    expect(findIconSpec('apple'), isNull);
    final Set<String> allTokens = providerCatalog
        .map((ProviderEntry entry) => entry.token)
        .toSet();
    expect(
      selectIconTargets(allTokens).map((IconSpec spec) => spec.token).toList(),
      tokens,
    );
    expect(selectIconTargets(const <String>{'apple'}), isEmpty);
  });

  test('T-20.1-SPEC-03: 행마다 최악(비압축 RGBA) PNG 크기가 용량 상한보다 '
      '작다', () {
    for (final IconSpec spec in iconSpecs) {
      expect(
        computeWorstPngBytes(spec.side),
        lessThan(spec.maxBytes),
        reason: spec.token,
      );
    }
  });

  test('T-20.1-SPEC-04: 출력 폴더는 .setup/ 아래 · flavor 무관이고 '
      '.gitignore 가 /.setup/ 을 무시한다', () {
    expect(iconsDirectory, startsWith('.setup/'));
    for (final Flavor flavor in Flavor.values) {
      expect(iconsDirectory, isNot(contains(flavor.name)), reason: flavor.name);
    }
    for (final IconSpec spec in iconSpecs) {
      expect(
        spec.relativePath,
        startsWith('$iconsDirectory/'),
        reason: spec.token,
      );
    }
    expect(File('.gitignore').readAsLinesSync(), contains('/.setup/'));
  });

  group('T-20.1-SPEC-05: 값 표 행 · 노트 · 원본 크기 범위', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('icon_specs_'));
    tearDown(() => root.deleteSync(recursive: true));

    test('파일이 없으면 안내 문장, 있으면 저장소 상대 경로를 보인다', () {
      final context = buildTestContext(projectRoot: root.path);
      final IconSpec spec = findIconSpec('naver')!;

      expect(describeIconPath(context, spec), missingIconValue);
      final SummaryRow missingRow = buildIconRow(context, spec);
      expect(missingRow.label, spec.rowLabel);
      expect(missingRow.value, missingIconValue);

      File('${root.path}/${spec.relativePath}')
        ..createSync(recursive: true)
        ..writeAsBytesSync(const <int>[1, 2, 3]);

      expect(describeIconPath(context, spec), spec.relativePath);
      final SummaryRow presentRow = buildIconRow(context, spec);
      expect(presentRow.label, spec.rowLabel);
      expect(presentRow.value, spec.relativePath);
    });

    test('Facebook · Google 만 노트가 있다', () {
      expect(
        buildIconNote(findIconSpec('facebook')!),
        contains('개발 모드 로그인에는 필요 없습니다'),
      );
      expect(buildIconNote(findIconSpec('google')!), contains('브랜드 인증'));
      for (final token in const <String>['kakao', 'naver', 'line']) {
        expect(buildIconNote(findIconSpec(token)!), isNull, reason: token);
      }
    });

    test('원본 한 변 하한 1024 · 상한 16384', () {
      expect(minSourceSide, 1024);
      expect(maxSourceSide, 16384);
    });
  });
}
