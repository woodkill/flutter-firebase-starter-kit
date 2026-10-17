import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/firebase_app_files.dart';
import '../../../tool/setup/flavor.dart';
import 'firebase_options_fixture.dart';

/// 저장소에 tracked 된 dev Dart 설정 자리표시 본문의 바이트 사본(저장소 상대 경로).
const String placeholderFixturePath =
    'test/tool/setup/fixtures/firebase_options_dev_placeholder.txt';

/// 생성본 커밋을 막는 커밋 훅(저장소 상대 경로).
const String preCommitHookPath = 'scripts/git-hooks/pre-commit';

/// 테스트 프로젝트 ID.
const String projectId = 'p';

/// 실행 시점에 조립한 가짜 API 키 — 소스에 완형을 두지 않는다.
final String fakeApiKey = 'AIza${'x' * 35}';

void main() {
  late Directory tempDir;
  late String root;

  /// 임시 저장소의 Dart 설정 파일 자리에 [content] 를 쓴다.
  void writeOptions(String content) {
    File('$root/${FirebaseAppFiles.optionsPath}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// 공용 빌더로 생성본 모양 본문을 만든다.
  String buildGenerated() => buildGeneratedOptionsSource(
    projectId: projectId,
    apiKey: fakeApiKey,
    androidAppId: '1:000:android:fake',
    iosAppId: '1:000:ios:fake',
  );

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('firebase_app_files_test_');
    root = tempDir.path;
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('T-19-OPTS-01 저장소 자리표시 본문 사본은 자리표시로 본다 · 프로젝트 ID 없음', () {
    final String placeholder = File(placeholderFixturePath).readAsStringSync();
    // 빈 파일 · 엉뚱한 파일이 아님을 먼저 확인한다.
    expect(placeholder, contains('DefaultFirebaseOptions'));
    expect(placeholder, contains('UnsupportedError'));
    writeOptions(placeholder);

    final files = FirebaseAppFiles.read(root);

    expect(files.isOptionsPlaceholder, isTrue);
    expect(files.optionsProjectId, isNull);
  });

  test(
    'T-19-OPTS-02 생성본 모양(예외 throw 5곳)은 끝난 파일로 보고 프로젝트 ID 를 읽는다 · 파일 없음은 자리표시',
    () {
      expect(FirebaseAppFiles.read(root).isOptionsPlaceholder, isTrue);
      final String generated = buildGenerated();
      expect('throw UnsupportedError('.allMatches(generated), hasLength(5));
      writeOptions(generated);

      final files = FirebaseAppFiles.read(root);

      expect(files.isOptionsPlaceholder, isFalse);
      expect(files.optionsProjectId, projectId);
    },
  );

  test('T-19-OPTS-03 생성 마커 상수 = 커밋 훅의 MARKER 값 · 생성본 첫 줄이 그 값을 담는다', () {
    final List<String> markerLines = File(preCommitHookPath)
        .readAsLinesSync()
        .where((String line) => line.startsWith('MARKER='))
        .toList();
    expect(markerLines, hasLength(1));
    final RegExpMatch? match = RegExp(
      r"^MARKER='([^']+)'$",
    ).firstMatch(markerLines.single);
    expect(match, isNotNull);

    expect(match?.group(1), FirebaseAppFiles.optionsGeneratedMarker);
    expect(
      buildGenerated().split('\n').first,
      contains(FirebaseAppFiles.optionsGeneratedMarker),
    );
  });

  test(
    'T-20-STG-01: 저장소의 stg · prod 자리표시 설정 파일은 그 flavor 경로에서 읽혀 미등록(옵션 자리표시 · 프로젝트 불일치)으로 본다',
    () {
      for (final flavor in <Flavor>[Flavor.stg, Flavor.prod]) {
        final paths = FlavorPaths(flavor);
        // 저장소에 tracked 된 자리표시 파일을 그대로 복사한다 — 값을 소스에 박지 않는다.
        for (final path in <String>[
          paths.dartOptions,
          paths.iosPlist,
          paths.androidJson,
        ]) {
          final copy = File('$root/$path')..parent.createSync(recursive: true);
          File(path).copySync(copy.path);
        }

        final files = FirebaseAppFiles.read(root, flavor: flavor);

        expect(files.isOptionsPlaceholder, isTrue, reason: flavor.name);
        expect(files.optionsProjectId, isNull, reason: flavor.name);
        // 자리표시 파일이 그 flavor 경로에서 읽혔다 — 비어 있지 않고 설정 프로젝트와 다르다.
        expect(files.iosProjectId, isNotNull, reason: flavor.name);
        expect(files.iosProjectId, isNot(projectId), reason: flavor.name);
        expect(files.androidProjectId, isNotNull, reason: flavor.name);
        expect(files.androidProjectId, isNot(projectId), reason: flavor.name);
        // stg 는 `.stg` 접미사 · prod 는 접미사 없음.
        expect(
          files.iosBundleId,
          flavor == Flavor.prod
              ? allOf(
                  isNot(endsWith(Flavor.dev.suffix)),
                  isNot(endsWith(Flavor.stg.suffix)),
                )
              : endsWith(flavor.suffix),
          reason: flavor.name,
        );
      }

      // dev 경로에는 아무 파일도 없다 — stg · prod 파일을 dev 로 읽지 않는다.
      final devFiles = FirebaseAppFiles.read(root);
      expect(devFiles.iosProjectId, isNull);
      expect(devFiles.androidProjectId, isNull);
    },
  );
}
