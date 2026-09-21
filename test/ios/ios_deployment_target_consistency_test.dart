// quick 260915-0z4 · Phase 16.3 D-06 · D-15 — iOS 최소 배포 타겟 단일 출처
// 일관성 가드 + CocoaPods fallback 감지.
//
// **목적:** iOS 최소 배포 타겟의 진실원은 `ios/Runner.xcodeproj/project.pbxproj` 의
// IPHONEOS_DEPLOYMENT_TARGET 12개 값 하나다. SPM 에서는 Flutter 가 빌드 때마다 이
// 값을 읽어 생성 패키지(`FlutterGeneratedPluginSwiftPackage`)의 platforms 를 올린다.
// 12개가 서로 어긋나면 구성마다 다른 하한이 적용되므로 `flutter test` 를 실패시킨다.
// 그리고 `ios/Podfile` 이 되살아나면 SPM 을 지원하지 않는 iOS 플러그인이 들어와
// Flutter 가 CocoaPods 로 fallback 한 것이다 — 경고만 내고 빌드는 성공하는 조용한
// 실패이므로 여기서 잡는다.
//
// **결함 사례:** pod target 하한이 끌어올려지지 않아, podspec 하한이 13.0 인
// flutter_line_sdk 가 LineSDKSwift 5.17.0(iOS 15.0) 모듈을 import 하면서
// "Compiling for iOS 13.0, but module 'LineSDK' has a minimum deployment target of
// iOS 15.0" Swift 컴파일 에러로 빌드가 멈췄다. Runner pbxproj 도 13.0 으로 남아
// 실제 지원 하한을 과소 표기하고 있었다.
//
// **설계 메모:** 현재 트리 단언에는 배포 타겟 **값 리터럴을 적지 않는다**(진실원
// 이중화 방지 — D-06). 대신 값 목록이 비어 있지 않음과 개수 12 를 먼저 단언한 뒤
// 「전부 같은 값」 만 본다. 빈 목록에서는 「불일치 0」 이 공허하게 참이므로 순서가
// 중요하다. 부재 단언(D-15)은 `readProjectFile` 을 쓰지 않는다 — 그 헬퍼는 파일이
// 없을 때 `fail()` 하므로 부재를 검사할 수 없다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _podfilePathForAbsence = 'ios/Podfile';
const String _pbxprojPath = 'ios/Runner.xcodeproj/project.pbxproj';

/// 저장소 루트 기준 상대 경로 [path] 의 파일 내용을 돌려준다.
///
/// 파일이 없으면 경로를 알리며 테스트를 실패시킨다
/// (`flutter test` 의 CWD = 프로젝트 루트).
String readProjectFile(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    fail('$path 가 존재하지 않는다');
  }
  return file.readAsStringSync();
}

/// pbxproj [content] 의 `IPHONEOS_DEPLOYMENT_TARGET = <v>;` 값 목록을 등장 순서대로 돌려준다.
List<String> collectPbxprojDeploymentTargets(String content) {
  return RegExp(
    r'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);',
  ).allMatches(content).map((RegExpMatch match) => match.group(1)!).toList();
}

/// [targets] 중 [expected] 와 다른 값만 등장 순서대로 돌려준다.
List<String> findDeploymentTargetMismatches(
  List<String> targets,
  String expected,
) {
  return targets.where((String target) => target != expected).toList();
}

void main() {
  group('현재 트리 — Runner pbxproj 단일 진실원', () {
    test('Runner pbxproj 의 IPHONEOS_DEPLOYMENT_TARGET 이 전부 같은 값이다', () {
      final List<String> targets = collectPbxprojDeploymentTargets(
        readProjectFile(_pbxprojPath),
      );
      expect(targets, isNotEmpty, reason: '대입이 0건이면 정규식이 깨진 것이다');
      expect(targets.length, 12, reason: 'build configuration 12개 = 진실원의 개수');

      final List<String> mismatches = findDeploymentTargetMismatches(
        targets,
        targets.first,
      );
      expect(
        mismatches,
        isEmpty,
        reason:
            'iOS 최소 배포 타겟의 진실원은 $_pbxprojPath 하나다 '
            '(Phase 16.3 D-06). 12개 값을 함께 바꾸세요. '
            '불일치 값: $mismatches',
      );
    });

    test('ios/Podfile 이 존재하지 않는다 (SPM 전용)', () {
      expect(
        File(_podfilePathForAbsence).existsSync(),
        isFalse,
        reason:
            'Phase 16.3 D-15: $_podfilePathForAbsence 이 되살아났다면 SPM 을 '
            '지원하지 않는 iOS 플러그인이 들어와 Flutter 가 CocoaPods 로 '
            'fallback 한 것이다(경고만 내고 빌드는 성공한다). '
            'docs/manual.md "## iOS 의존성 관리 (SPM)" 의 ③ 사전 확인 절차와 '
            '④ 증상을 보라.',
      );
      // 양성 대조 — 같은 파일시스템 API 가 실제로 매칭한다는 사실을 고정한다.
      // 이것이 없으면 ios/ 디렉터리째 사라져도 위 단언이 공허하게 통과한다.
      expect(
        File(_pbxprojPath).existsSync(),
        isTrue,
        reason: 'tracked 파일 부재: $_pbxprojPath',
      );
    });
  });

  group('검출 로직 — 수정 전 커밋(7866f8cd) fixture', () {
    // 7866f8cd 의 Runner pbxproj 대입 줄(탭 4개 들여쓰기) 과 값만 15.6 으로 바꾼 줄.
    const String legacyTargetLine =
        '\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 13.0;';
    const String alignedTargetLine =
        '\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 15.6;';

    test('수정 전 13.0 값을 불일치로 검출한다', () {
      final List<String> targets = collectPbxprojDeploymentTargets(
        '$legacyTargetLine\n$alignedTargetLine\n',
      );
      expect(targets, <String>['13.0', '15.6']);
      expect(findDeploymentTargetMismatches(targets, '15.6'), <String>['13.0']);
    });

    test('모든 값이 같으면 빈 목록을 돌려준다', () {
      final List<String> targets = collectPbxprojDeploymentTargets(
        '$alignedTargetLine\n$alignedTargetLine\n',
      );
      expect(findDeploymentTargetMismatches(targets, '15.6'), isEmpty);
    });

    test('대입이 0건인 입력은 빈 목록이다', () {
      // 현재 트리 단언이 `isNotEmpty` · 개수 12 를 **먼저** 세우는 이유를 고정한다:
      // 가드가 없으면 매칭 0건에서 「불일치 0」 이 공허하게 참이 된다.
      expect(collectPbxprojDeploymentTargets(''), isEmpty);
      expect(findDeploymentTargetMismatches(<String>[], '0'), isEmpty);
    });
  });
}
