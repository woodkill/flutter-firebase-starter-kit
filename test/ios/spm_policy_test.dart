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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

const String _pbxprojPath = 'ios/Runner.xcodeproj/project.pbxproj';
const String _workspaceResolvedPath =
    'ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved';
const String _projectResolvedPath =
    'ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved';

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
}
