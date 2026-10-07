// Phase 16.3 — SPM 정책 · 손패치 회귀 가드 (코드 리뷰 WR-02 · WR-05 · IN-03).
//
// **목적:** CocoaPods → SPM 전환이 남긴 **불변식 3건**을 자동으로 잠근다. 셋 다
// 「깨져도 빌드는 성공할 수 있다」 는 조용한 실패이므로, 사람이 절차를 기억하는
// 것에만 맡기지 않는다.
//
// 1. **Crashlytics 업로드 단계의 SPM 경로 probe(WR-02)** — 이 build phase 는
//    upstream `flutterfire_cli` 가 생성하는 모양이 **아니다**(손패치). 수동
//    `fff configure` 는 이 단계를 upstream 템플릿으로 재생성하므로 패치가 조용히
//    사라진다. `scripts/firebase-configure.sh` 경로는 스냅샷·복원하므로 안전하다.
// 2. **두 `Package.resolved` 의 바이트 동일(WR-05)** — Xcode 는 어느 컨테이너로
//    해석했느냐에 따라 **둘 중 한쪽만** 갱신한다(`.xcodeproj` 직접 열기 vs
//    `Runner.xcworkspace` 열기). 즉 한쪽만 바뀌는 것이 정상 동작이며, 갈라지면
//    「빌드가 존중하는 쪽」 과 「Flutter prefetch 가 쓰는 쪽」 의 핀이 달라져
//    LINE 5.17.0 고정이 조용히 풀린다.
// 3. **`enable-swift-package-manager` 키 부재(D-01 · IN-03)** — Phase 16.2 의
//    Naver 시크릿 계약 test 에 얹혀 있던 단언을 SPM 가드 쪽으로 옮겨 왔다.
//    SPM 회귀로 red 가 났을 때 Naver 파일을 뒤지게 되는 오도를 없앤다.
//
// **tracked 파일만 읽는다** — gitignored 실 키 파일은 열지 않으므로 fresh clone ·
// CI 에서도 결과가 같다. 각 단언 앞에 양성 대조(파일 비어 있지 않음 · 대상 문자열
// 실재)를 세우는 이유는, 경로가 깨지면 「위반 0건」 이 공허하게 참이 되기 때문이다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';
import '../helpers/source_text.dart';

const String _pbxprojPath = 'ios/Runner.xcodeproj/project.pbxproj';
const String _workspaceResolvedPath =
    'ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved';
const String _projectResolvedPath =
    'ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved';
const String _podfileLockPath = 'ios/Podfile.lock';
const String _workspaceDataPath =
    'ios/Runner.xcworkspace/contents.xcworkspacedata';

/// LINE 핀 결정 기록(비공개 작업 일지) — T-16.3-SPM-11 이 읽는다.
/// 작업 일지 문서를 읽는 검사는 그 문서가 없는 트리(공개 mirror)에서
/// 건너뛴다 — Phase 17.4 D-08 — see ROADMAP.md
const String _linePinDecisionPath =
    '.planning/phases/16.3-ios-cocoapods-to-spm-migration/'
    'artifacts/LINE-PIN-DECISION.md';

/// [directory] 아래 **tracked** `.xcconfig` 파일 경로 목록을 등장 순서대로
/// 돌려준다.
///
/// `Directory.listSync()` 대신 `git ls-files` 로 거른다 — 워킹트리에는
/// `ios/Flutter/Generated.xcconfig` · `dev.xcconfig` 등 gitignored 실 값
/// 파일도 함께 있어(로컬 secrets), 디스크 나열만 하면 fresh clone·CI 에는
/// 없는 파일까지 대상에 넣게 된다. 이 test 는 tracked 파일만 본다는
/// 프로젝트 규칙(`readTrackedFile` 주석)을 xcconfig 목록에도 그대로 적용한다.
List<String> listTrackedXcconfigFiles(String directory) {
  final ProcessResult result = Process.runSync(
    'git',
    <String>['ls-files', '$directory/*.xcconfig'],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  expect(
    result.exitCode,
    0,
    reason:
        'git ls-files $directory/*.xcconfig 실패 — git 이 PATH 에 없거나 '
        '저장소 밖에서 실행됐다.',
  );
  return (result.stdout as String)
      .split('\n')
      .where((String line) => line.isNotEmpty)
      .toList();
}

/// [path] 의 `LINE_PIN_VERSION:` / `LINE_PIN_REVISION:` 값을 읽는다.
///
/// **하드코딩하지 않는 이유:** LINE 핀의 진실원은 이 결정 파일이다
/// (`.planning/.../LINE-PIN-DECISION.md`). 값을 테스트에 다시 적으면
/// 진실원이 둘로 갈라진다.
({String version, String revision}) readLinePinDecision(String path) {
  final String text = readTrackedFile(path);
  final String? version = RegExp(
    r'LINE_PIN_VERSION:\s*(\S+)',
  ).firstMatch(text)?.group(1);
  final String? revision = RegExp(
    r'LINE_PIN_REVISION:\s*(\S+)',
  ).firstMatch(text)?.group(1);

  // 빈 값을 그대로 흘려보내지 않는다 — 두 빈 문자열을 비교하면 아래 핀
  // 검사가 공허하게 통과한다 (plan 02 의 "빈 값 가드" 를 그대로 재현).
  expect(
    version,
    isNotNull,
    reason: '$path 에서 LINE_PIN_VERSION 을 읽지 못했다 — 키 형식이 바뀌었다',
  );
  expect(
    revision,
    isNotNull,
    reason: '$path 에서 LINE_PIN_REVISION 을 읽지 못했다 — 키 형식이 바뀌었다',
  );
  expect(version, isNotEmpty, reason: '$path 의 LINE_PIN_VERSION 값이 비었다');
  expect(revision, isNotEmpty, reason: '$path 의 LINE_PIN_REVISION 값이 비었다');
  return (version: version!, revision: revision!);
}

/// [resolvedJson] 의 `pins` 목록에서 identity [identity] 의 핀을 돌려준다.
///
/// 못 찾으면 `fail()` 한다 — 오타 난 identity 가 조용히 skip 되지 않고
/// 시끄럽게 죽어야 한다.
Map<String, Object?> findPin(List<Object?> pins, String identity) {
  for (final Object? pin in pins) {
    final Map<String, Object?> map = pin! as Map<String, Object?>;
    if (map['identity'] == identity) {
      return map;
    }
  }
  fail(
    'identity "$identity" 를 Package.resolved 의 pins 에서 찾지 못했다 — '
    '핀이 삭제됐거나 identity 문자열이 바뀌었다.',
  );
}

/// probe 루프의 1순위 후보 — Flutter 가 `-clonedSourcePackagesDirPath` 로 지정하는 곳.
const String _flutterCheckoutRun =
    r'"${SRCROOT}/../build/ios/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"';

/// pbxproj 의 `shellScript = "…";` 값 하나를 통째로 집는다.
///
/// **`"(.*?)";` 같은 non-greedy 패턴을 쓰면 안 된다**(코드 리뷰 IN-04(R2) 수정 중
/// 실측) — 스크립트 본문에 `…/Crashlytics/run\"; do` 가 들어 있어 probe 루프 도중에
/// 끊긴다. 역슬래시 이스케이프를 인식하는 이 패턴만 값 전체를 집는다.
final RegExp _shellScriptValue = RegExp(r'shellScript = "((?:\\.|[^"\\])*)";');

/// pbxproj 문자열 리터럴 [raw] 의 이스케이프를 풀어 실제 셸 스크립트로 되돌린다.
String _decodePbxprojString(String raw) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < raw.length; i++) {
    final String ch = raw[i];
    if (ch != r'\' || i + 1 >= raw.length) {
      out.write(ch);
      continue;
    }
    final String next = raw[i + 1];
    i++;
    switch (next) {
      case 'n':
        out.write('\n');
      case 't':
        out.write('\t');
      default:
        // `\"` → `"`, `\\` → `\` 등 나머지는 다음 문자를 그대로 쓴다.
        out.write(next);
    }
  }
  return out.toString();
}

/// Crashlytics 업로드 build phase 의 `shellScript` 본문만 잘라 돌려준다.
///
/// 이 test 들이 pbxproj **전체 텍스트**가 아니라 이 반환값만 보는 이유
/// (코드 리뷰 IN-04(R2)): 문자열 `flutterfire upload-crashlytics-symbols` 는
/// buildPhases 참조 · 객체 주석 · `name =` 에도 있어서 **`shellScript` 가 통째로
/// 비어도** 전체 텍스트 검사는 통과한다. 여기서 실패시키면 그 구멍이 닫힌다.
String _readCrashlyticsShellScript(String pbx) {
  return _shellScriptValue
      .allMatches(pbx)
      .map((RegExpMatch match) => _decodePbxprojString(match.group(1)!))
      .firstWhere(
        (String script) =>
            script.contains('flutterfire upload-crashlytics-symbols'),
        orElse: () => fail(
          'Crashlytics 업로드 build phase 의 shellScript 본문을 찾지 못했다 '
          '($_pbxprojPath). build phase 가 사라졌거나 shellScript 가 비었다 — '
          '의도한 제거라면 이 가드도 함께 지우세요.',
        ),
      );
}

void main() {
  group('Crashlytics 업로드 단계의 SPM 손패치 (16.3 R-05 · 리뷰 WR-02)', () {
    test('T-16.3-SPM-01 build phase 가 SPM checkout 경로를 probe 한다', () {
      // 양성 대조 겸 범위 한정 — shellScript 가 비어 있으면 여기서 fail 한다.
      final String script = _readCrashlyticsShellScript(
        readTrackedFile(_pbxprojPath),
      );

      // 「파일 어딘가의 문자열」 이 아니라 **실제로 동작하는 probe 루프**를 본다.
      // 경로 문자열만 세면 루프를 지우고 진단 메시지만 남겨도 green 이 된다.
      expect(
        countOccurrences(script, 'for CANDIDATE in $_flutterCheckoutRun'),
        1,
        reason:
            'Phase 16.3 R-05 패치가 사라졌다. upstream flutterfire_cli 템플릿은 '
            'DerivedData 경로 한 줄만 대입하지만, Flutter 는 모든 iOS xcodebuild '
            '호출에 -clonedSourcePackagesDirPath <project>/build/ios/SourcePackages '
            '를 붙이므로 SPM checkout 은 DerivedData 밑에 없다. 수동 '
            'fff configure 가 이 build phase 를 재생성했다면 diff 를 읽고 '
            '복원하세요 — docs/manual.md 「iOS 의존성 관리 (SPM)」 ⑥ 참고.',
      );

      // 루프가 그 후보를 실제로 소비하는지 — 선언만 남고 본문이 비면 무의미하다.
      expect(
        countOccurrences(script, r'if [ -f "$CANDIDATE" ]; then'),
        1,
        reason:
            'probe 루프의 본문(후보 존재 검사)이 사라졌다. 후보 목록만 남으면 '
            'PATH_TO_CRASHLYTICS_UPLOAD_SCRIPT 가 영영 대입되지 않는다.',
      );
    });

    test('T-16.3-SPM-02 probe 실패 시 빈 경로를 흘려보내지 않는다', () {
      final String script = _readCrashlyticsShellScript(
        readTrackedFile(_pbxprojPath),
      );

      expect(
        countOccurrences(
          script,
          r'if [ -z "$PATH_TO_CRASHLYTICS_UPLOAD_SCRIPT" ]',
        ),
        1,
        reason:
            '코드 리뷰 WR-01 패치가 사라졌다. 두 후보 경로가 모두 없으면 '
            'PATH_TO_CRASHLYTICS_UPLOAD_SCRIPT 가 미설정인 채 '
            '--upload-symbols-script-path="" 로 전달되고, flutterfire_cli 1.3.2 는 '
            '그 값을 그대로 Process.run 에 넘겨 원인을 알 수 없는 '
            'ProcessException 으로 빌드가 멈춘다. probe 한 경로를 찍으며 '
            'exit 1 하는 분기를 복원하세요.',
      );

      // 분기가 실제로 빌드를 멈추는지 — echo 만 남기면 빈 경로가 그대로 흘러간다.
      expect(
        countOccurrences(script, 'exit 1'),
        greaterThan(0),
        reason:
            '빈 경로 분기가 exit 1 하지 않으면 경고만 남기고 빌드가 계속된다 — '
            '이 가드가 막으려던 ProcessException 이 그대로 발생한다.',
      );
    });
  });

  group('두 Package.resolved 의 바이트 동일 (16.3 ② · 리뷰 WR-05)', () {
    test('T-16.3-SPM-03 workspace 와 xcodeproj 의 핀이 바이트 동일하다', () {
      final File workspace = File(_workspaceResolvedPath);
      final File project = File(_projectResolvedPath);

      expect(
        workspace.existsSync(),
        isTrue,
        reason: 'tracked 파일 부재: $_workspaceResolvedPath',
      );
      expect(
        project.existsSync(),
        isTrue,
        reason:
            'tracked 파일 부재: $_projectResolvedPath — 이 파일을 지우면 Flutter 의 '
            '사전 해석(prefetch)이 핀을 무시한 최신값으로 자동 재생성한다.',
      );

      final List<int> workspaceBytes = workspace.readAsBytesSync();
      final List<int> projectBytes = project.readAsBytesSync();

      // 양성 대조 — 두 파일이 모두 비어 있으면 아래 비교가 공허하게 참이 된다.
      expect(
        workspaceBytes,
        isNotEmpty,
        reason: '$_workspaceResolvedPath 가 비었다 — 경로 또는 파일이 깨졌다',
      );
      expect(
        projectBytes,
        isNotEmpty,
        reason: '$_projectResolvedPath 가 비었다 — 경로 또는 파일이 깨졌다',
      );

      expect(
        projectBytes,
        orderedEquals(workspaceBytes),
        reason:
            'Phase 16.3 ②: 두 Package.resolved 가 갈라졌다. Xcode 가 한쪽 '
            '컨테이너로만 해석하면 이렇게 된다(.xcodeproj 를 직접 열면 project 쪽, '
            'Runner.xcworkspace 를 열면 workspace 쪽). 갈라진 채 두면 「빌드가 '
            '존중하는 쪽」 과 「Flutter prefetch 가 쓰는 쪽」 의 핀이 달라져 LINE '
            '5.17.0 고정이 조용히 풀린다. 의도한 쪽을 다른 쪽으로 복사해 같은 '
            '커밋에 담으세요 — docs/manual.md 「iOS 의존성 관리 (SPM)」 ② 참고.',
      );
    });
  });

  group('SPM 스위치 키 부재 (16.3 D-01 · 리뷰 IN-03)', () {
    test('T-16.3-SPM-04 pubspec 에 enable-swift-package-manager 가 없다', () {
      final String pubspec = stripHashComments(readTrackedFile('pubspec.yaml'));

      // 양성 대조 — 주석 제거가 파일을 통째로 날려도 눈치채도록 한다.
      expect(
        countOccurrences(pubspec, 'flutter:'),
        greaterThan(0),
        reason: 'pubspec.yaml 본문을 읽지 못했다 — 주석 제거가 깨졌다',
      );

      expect(
        countOccurrences(pubspec, 'enable-swift-package-manager'),
        0,
        reason:
            'Phase 16.3 D-01: SPM 은 Flutter 3.44+ 의 기본값(on)에 맡긴다. '
            'pubspec.yaml 에 이 키가 있으면(true 든 false 든) flutter create 표준 '
            '모양과 어긋나고, false 면 CocoaPods fallback 으로 되돌아가 '
            'ios/Podfile 이 재생성된다.',
      );
    });
  });

  group('CocoaPods 흔적 부재 (16.3 D-02)', () {
    test('T-16.3-SPM-05 ios/Podfile.lock 이 존재하지 않는다', () {
      expect(
        File(_podfileLockPath).existsSync(),
        isFalse,
        reason:
            'Phase 16.3 D-02: $_podfileLockPath 이 되살아났다면 CocoaPods 가 '
            '다시 실행된 것이다 — docs/manual.md 「iOS 의존성 관리 (SPM)」 ③ 을 '
            '보라.',
      );
      // 양성 대조 — 같은 File API 가 실제로 매칭한다는 사실을 고정한다.
      // 이것이 없으면 ios/ 디렉터리째 사라져도 위 단언이 공허하게 통과한다.
      expect(
        File(_pbxprojPath).existsSync(),
        isTrue,
        reason: 'tracked 파일 부재: $_pbxprojPath',
      );
    });

    test('T-16.3-SPM-06 pbxproj 에 CocoaPods 통합 흔적([CP] · Pods)이 없다', () {
      final String pbx = readTrackedFile(_pbxprojPath);

      // 양성 대조 — 파일이 비어 있거나 SPM 통합 자체가 사라지면
      // 아래 0건 단언들이 공허하게 참이 된다.
      expect(pbx, isNotEmpty, reason: '$_pbxprojPath 를 읽지 못했다');
      expect(
        countOccurrences(pbx, 'FlutterGeneratedPluginSwiftPackage'),
        greaterThan(0),
        reason:
            'SPM 생성 패키지 참조가 pbxproj 에서 사라졌다 — G3 SPM 실사용 '
            '증거가 깨졌다.',
      );

      expect(
        countOccurrences(pbx, '[CP]'),
        0,
        reason:
            'Phase 16.3 D-02: pbxproj 에 CocoaPods build phase 접두 '
            '"[CP]" 가 남아 있다 — CocoaPods 가 다시 통합됐다. '
            'docs/manual.md 「iOS 의존성 관리 (SPM)」 ③ 을 보라.',
      );
      expect(
        countOccurrences(pbx, 'Pods'),
        0,
        reason:
            'Phase 16.3 D-02: pbxproj 에 "Pods" 문자열이 남아 있다 — '
            'CocoaPods target/참조가 재유입됐다. '
            'docs/manual.md 「iOS 의존성 관리 (SPM)」 ③ 을 보라.',
      );
    });

    test(
      'T-16.3-SPM-07 xcworkspace 의 contents.xcworkspacedata 에 Pods 참조가 없다',
      () {
        final String workspaceData = readTrackedFile(_workspaceDataPath);

        // 양성 대조 — 파일이 텅 비면 아래 0건 단언이 공허하게 참이 된다.
        expect(
          countOccurrences(
            workspaceData,
            'location = "group:Runner.xcodeproj"',
          ),
          1,
          reason:
              '$_workspaceDataPath 의 FileRef 가 사라졌다 — 파일이 깨졌거나 '
              'workspace 구조가 바뀌었다 (읽어서 실제 리터럴을 먼저 확인할 것).',
        );

        expect(
          countOccurrences(workspaceData, 'Pods'),
          0,
          reason:
              'Phase 16.3 D-02: $_workspaceDataPath 에 "Pods" 참조가 '
              '남아 있다 — CocoaPods 프로젝트 참조가 재유입됐다.',
        );
      },
    );

    test(
      'T-16.3-SPM-08 tracked ios/Flutter/*.xcconfig 에 CocoaPods 링크 흔적이 없다',
      () {
        final List<String> xcconfigFiles = listTrackedXcconfigFiles(
          'ios/Flutter',
        );

        // 빈 목록 가드 — 0개에서는 아래 "0건" 이 공허하게 참이 된다
        // (ios_deployment_target_consistency_test.dart 와 같은 패턴).
        expect(
          xcconfigFiles,
          isNotEmpty,
          reason: 'tracked ios/Flutter/*.xcconfig 목록이 비었다 — git ls-files 실패',
        );

        // 양성 대조 — 열거된 파일 중 적어도 하나는 Generated.xcconfig 를
        // #include 한다는 사실을 고정한다. 이것이 없으면 목록이 전부
        // 엉뚱한 파일이어도 아래 0건이 공허하게 참이 된다.
        final bool anyIncludesGenerated = xcconfigFiles.any(
          (String path) =>
              countOccurrences(readTrackedFile(path), 'Generated.xcconfig') > 0,
        );
        expect(
          anyIncludesGenerated,
          isTrue,
          reason:
              'tracked xcconfig 중 어느 것도 Generated.xcconfig 를 #include '
              '하지 않는다 — 목록 또는 파일 내용이 깨졌다.',
        );

        for (final String path in xcconfigFiles) {
          expect(
            countOccurrences(readTrackedFile(path), 'Target Support Files'),
            0,
            reason:
                'Phase 16.3 D-02: $path 에 CocoaPods 가 심는 '
                '"Target Support Files" #include 가 남아 있다 — '
                'CocoaPods 가 다시 통합됐다. '
                'docs/manual.md 「iOS 의존성 관리 (SPM)」 ③ 을 보라.',
          );
        }
      },
    );
  });

  group('SPM 실사용 증거 (16.3 D-03 discretion)', () {
    test(
      'T-16.3-SPM-09 pbxproj 가 FlutterGeneratedPluginSwiftPackage 를 최소 1회 참조한다',
      () {
        final String pbx = readTrackedFile(_pbxprojPath);

        // 양성 대조 — 파일이 비면 아래 ≥1 단언이 무의미해진다.
        expect(pbx, isNotEmpty, reason: '$_pbxprojPath 를 읽지 못했다');

        // ios/Flutter/ephemeral/Packages 는 gitignored 생성물이라 test
        // 대상으로 삼지 않는다 — fresh clone·CI 에는 존재하지 않는다.
        expect(
          countOccurrences(pbx, 'FlutterGeneratedPluginSwiftPackage'),
          greaterThan(0),
          reason:
              'Phase 16.3: pbxproj 에 SPM 생성 패키지 참조가 없다 — SPM 이 '
              '더 이상 실제로 쓰이지 않는 것일 수 있다 (CocoaPods 로 '
              '회귀했는지 확인하세요).',
        );
      },
    );
  });

  group('Package.resolved 핀 값 (16.3 D-05 · D-07)', () {
    /// 손으로 값을 바꾸거나 명시 고정한 5개 identity — 16.3-02-SUMMARY.md
    /// 「② 고정한 identity」 표가 진실원이다. LINE 은 하드코딩하지 않고
    /// 결정 파일에서 읽으므로 이 표에 없다.
    const Map<String, ({String version, String revision})> expectedPins =
        <String, ({String version, String revision})>{
          'facebook-ios-sdk': (
            version: '18.0.2',
            revision: '32da5bdef917ccd845fcf319c5fb67c654459d27',
          ),
          'googlesignin-ios': (
            version: '9.1.0',
            revision: '913b4005ea26aebe1c97d54e35ad82a515924c71',
          ),
          'firebase-ios-sdk': (
            version: '12.19.0',
            revision: '27eaab3918e0bf78711cf1abf240577176326432',
          ),
          'appauth-ios': (
            version: '2.0.0',
            revision: '145104f5ea9d58ae21b60add007c33c1cc0c948e',
          ),
          'naveridlogin-sdk-ios-swift': (
            version: '5.2.1',
            revision: '70f0cecb996768b3f6df88ec72567e3c5dee1035',
          ),
        };

    test('T-16.3-SPM-10 6개 SDK 의 identity 별 핀이 기준선 값을 유지한다', () {
      final Map<String, Object?> resolved =
          jsonDecode(readTrackedFile(_workspaceResolvedPath))
              as Map<String, Object?>;
      final List<Object?> pins = resolved['pins']! as List<Object?>;

      // 양성 대조 — pins 목록이 비면 아래 5개 identity 검사 전부가
      // findPin() 의 fail() 로 죽지만, threat T-16.3-13(Package.resolved
      // 삭제)을 「pins 자체가 없다」 로도 명시적으로 잡아 둔다.
      expect(
        pins,
        isNotEmpty,
        reason:
            '$_workspaceResolvedPath 의 pins 가 비었다 — Xcode "Update to '
            'Latest Package Versions" 또는 파일 재생성으로 고정이 통째로 '
            '풀렸을 수 있다. docs/manual.md 「iOS 의존성 관리 (SPM)」 ② 를 보라.',
      );

      for (final MapEntry<String, ({String version, String revision})> entry
          in expectedPins.entries) {
        final Map<String, Object?> pin = findPin(pins, entry.key);
        final Map<String, Object?> state =
            pin['state']! as Map<String, Object?>;

        expect(
          state['version'],
          entry.value.version,
          reason:
              'Phase 16.3 D-05: identity "${entry.key}" 의 version 핀이 '
              '기준선(${entry.value.version})에서 벗어났다 — Xcode '
              '"Update to Latest Package Versions" 를 실행했거나 누군가 '
              '수동으로 값을 바꿨다. docs/manual.md 「iOS 의존성 관리 '
              '(SPM)」 ② 를 보라.',
        );
        expect(
          state['revision'],
          entry.value.revision,
          reason:
              'Phase 16.3 D-05: identity "${entry.key}" 의 revision 핀이 '
              '기준선(${entry.value.revision})에서 벗어났다 — version '
              '문자열은 같아도 실제로 받아오는 코드가 달라졌을 수 있다. '
              'docs/manual.md 「iOS 의존성 관리 (SPM)」 ② 를 보라.',
        );
      }
    });

    test('T-16.3-SPM-11 line-sdk-ios-swift 핀이 LINE-PIN-DECISION.md 값과 일치한다', () {
      final ({String version, String revision}) decision = readLinePinDecision(
        _linePinDecisionPath,
      );

      final Map<String, Object?> resolved =
          jsonDecode(readTrackedFile(_workspaceResolvedPath))
              as Map<String, Object?>;
      final List<Object?> pins = resolved['pins']! as List<Object?>;
      final Map<String, Object?> pin = findPin(pins, 'line-sdk-ios-swift');
      final Map<String, Object?> state = pin['state']! as Map<String, Object?>;

      expect(
        state['version'],
        decision.version,
        reason:
            'Phase 16.3 D-07: line-sdk-ios-swift 의 version 핀이 '
            '$_linePinDecisionPath 의 LINE_PIN_VERSION(${decision.version})과 '
            '어긋났다. docs/manual.md 「iOS 의존성 관리 (SPM)」 ② 를 보라.',
      );
      expect(
        state['revision'],
        decision.revision,
        reason:
            'Phase 16.3 D-07: line-sdk-ios-swift 의 revision 핀이 '
            '$_linePinDecisionPath 의 LINE_PIN_REVISION(${decision.revision})과 '
            '어긋났다 — version 문자열은 같아도 실제 checkout 이 달라졌을 '
            '수 있다. docs/manual.md 「iOS 의존성 관리 (SPM)」 ② 를 보라.',
      );
    }, skip: skipUnlessPlanningDocsExist(const <String>[_linePinDecisionPath]));
  });
}
