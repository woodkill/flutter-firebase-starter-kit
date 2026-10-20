import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/confirm.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/fingerprints.dart';
import '../../../tool/setup/providers/icon_specs.dart';
import '../../../tool/setup/providers/keyed_provider_step.dart';
import '../../../tool/setup/steps/facebook_step.dart';
import '../../../tool/setup/steps/kakao_step.dart';
import '../../../tool/setup/steps/line_step.dart';
import '../../../tool/setup/steps/naver_step.dart';
import '../../../tool/setup/wizard.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'icon-rows-p';

/// fixture Gradle 의 applicationId.
const String applicationId = 'com.example.icon_rows';

/// fixture xcconfig 의 dev 번들 ID.
const String devBundleId = 'com.example.iconRows.dev';

/// 키를 입력받는 네 provider 단계를 새로 만든다.
List<KeyedProviderStep> buildKeyedSteps() => <KeyedProviderStep>[
  NaverStep(),
  KakaoStep(),
  FacebookStep(),
  LineStep(),
];

void main() {
  late Directory tempDir;
  late String root;

  /// 저장소 상대 경로에 내용을 쓴다(부모 디렉터리를 만든다).
  void writeFixture(String relativePath, String content) {
    File('$root/$relativePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// 저장소의 tracked [source] 를 임시 저장소의 [target] 으로 복사한다.
  void copyTracked(String source, String target) =>
      writeFixture(target, File(source).readAsStringSync());

  /// [spec] 아이콘 파일 자리에 가짜 바이트를 둔다(크기 · 형식은 보지 않는다).
  void placeIconFile(IconSpec spec) {
    File('$root/${spec.relativePath}')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(const <int>[1, 2, 3]);
  }

  /// 지문을 계산해 둔 세션으로 dev 문맥을 만든다.
  WizardContext buildContext() {
    final session = WizardSession()
      ..debugFingerprints = const FingerprintsAvailable(
        sha1Hex: 'ab500584b25ed636c9c91b0370546c3831850f16',
        sha256Hex: '',
        keyHash: 'q1AFhLJe1jbJyRsDcFRsODGFDxY=',
      );
    return buildTestContext(projectRoot: root, session: session);
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('provider_icon_rows_test_');
    root = tempDir.path;
    const paths = FlavorPaths(Flavor.dev);
    copyTracked(paths.jsonExample, paths.jsonExample);
    copyTracked(paths.xcconfigExample, paths.xcconfigExample);
    copyTracked(paths.jsonExample, paths.json);
    copyTracked(paths.xcconfigExample, paths.xcconfig);
    replaceJsonString('$root/${paths.json}', 'firebaseProjectId', projectId);
    replaceXcconfigValue(
      '$root/${paths.xcconfig}',
      'PRODUCT_BUNDLE_IDENTIFIER',
      devBundleId,
    );
    writeFixture(
      'android/app/build.gradle.kts',
      'android {\n'
          '    defaultConfig {\n'
          '        applicationId = "$applicationId"\n'
          '    }\n'
          '}\n',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// [step] 의 표 행이 기존 행 그대로 + 아이콘 행 [expectedValue] 하나인지 본다.
  void expectIconRowAppended(
    KeyedProviderStep step,
    WizardContext context,
    String expectedValue,
  ) {
    final String token = step.entry.token;
    final List<SummaryRow> base = step.buildValueRows(context);
    final List<SummaryRow> rows = step.buildDisplayRows(context);
    final IconSpec spec = findIconSpec(token)!;

    expect(rows, hasLength(base.length + 1), reason: token);
    for (var i = 0; i < base.length; i++) {
      expect(rows[i].label, base[i].label, reason: '$token $i');
      expect(rows[i].value, base[i].value, reason: '$token $i');
    }
    expect(rows.last.label, spec.rowLabel, reason: token);
    expect(rows.last.value, expectedValue, reason: token);
  }

  group('T-20.1-ROW-02: 키를 받는 네 provider 값 표는 기존 행 뒤에 그 provider 의 '
      '아이콘 행 하나를 더하고 노트는 Facebook 만 있다', () {
    test('아이콘 파일이 없으면 마지막 행 값이 「아직 없음」 문장이다', () {
      final WizardContext context = buildContext();
      for (final KeyedProviderStep step in buildKeyedSteps()) {
        expectIconRowAppended(step, context, missingIconValue);
      }
    });

    test('아이콘 파일이 있으면 마지막 행 값이 저장소 기준 상대 경로다', () {
      for (final IconSpec spec in iconSpecs) {
        placeIconFile(spec);
      }
      final WizardContext context = buildContext();
      for (final KeyedProviderStep step in buildKeyedSteps()) {
        final IconSpec spec = findIconSpec(step.entry.token)!;
        expectIconRowAppended(step, context, spec.relativePath);

        final String value = step.buildDisplayRows(context).last.value;
        expect(value, startsWith('$iconsDirectory/'), reason: value);
        expect(value, isNot(contains(root)), reason: value);
        expect(value, isNot(startsWith('/')), reason: value);
      }
    });

    test('다른 provider 의 파일만 있으면 그 경로를 보이지 않는다', () {
      placeIconFile(findIconSpec(NaverStep.token)!);
      final WizardContext context = buildContext();
      for (final KeyedProviderStep step in buildKeyedSteps()) {
        final IconSpec spec = findIconSpec(step.entry.token)!;
        expectIconRowAppended(
          step,
          context,
          step.entry.token == NaverStep.token
              ? spec.relativePath
              : missingIconValue,
        );
      }
    });

    test('아이콘 행 라벨은 콘솔 이름 · 요구 정도다', () {
      final WizardContext context = buildContext();
      expect(
        <String, String>{
          for (final KeyedProviderStep step in buildKeyedSteps())
            step.entry.token: step.buildDisplayRows(context).last.label,
        },
        <String, String>{
          NaverStep.token: '로고 이미지 · 필수',
          KakaoStep.token: '앱 아이콘 올리기 · 선택',
          FacebookStep.token: '앱 아이콘(1024 x 1024) · 앱 게시 때 필수',
          LineStep.token: 'Channel icon · 선택',
        },
      );
    });

    test('아이콘 노트는 Facebook 만 있고 나머지 셋은 없다', () {
      expect(
        <String, String?>{
          for (final KeyedProviderStep step in buildKeyedSteps())
            step.entry.token: step.iconNote,
        },
        <String, String?>{
          NaverStep.token: null,
          KakaoStep.token: null,
          FacebookStep.token:
              '앱 아이콘(1024 x 1024): 앱을 게시할 때 필수이고 개발 모드 로그인에는 필요 없습니다',
          LineStep.token: null,
        },
      );
    });

    test('할 일 줄 수는 그대로다', () {
      expect(
        <String, int>{
          for (final KeyedProviderStep step in buildKeyedSteps())
            step.entry.token: step.todoLines.length,
        },
        <String, int>{
          NaverStep.token: 5,
          KakaoStep.token: 4,
          FacebookStep.token: 5,
          LineStep.token: 4,
        },
      );
    });
  });
}
