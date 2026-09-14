// quick 260915-0z4 — iOS 최소 배포 타겟 단일 출처 일관성 가드.
//
// **목적:** 최소 iOS 버전은 `ios/Podfile` 의 지역 변수 `ios_deployment_target`
// 한 곳에서만 선언한다. `ios/Runner.xcodeproj/project.pbxproj` 의
// IPHONEOS_DEPLOYMENT_TARGET 12개 값은 이 변수와 같아야 한다. 본 가드는 두 파일이
// 어긋나면 `flutter test` 를 실패시켜 함께 바꿀 위치를 알려 준다.
//
// **결함 사례:** Podfile 은 15.6 을 선언했지만 post_install 이 pod target 을
// 끌어올리지 않아, podspec 하한이 13.0 인 flutter_line_sdk 가 LineSDKSwift 5.17.0
// (iOS 15.0) 모듈을 import 하면서 "Compiling for iOS 13.0, but module 'LineSDK' has
// a minimum deployment target of iOS 15.0" Swift 컴파일 에러로 빌드가 멈췄다.
// Runner pbxproj 도 13.0 으로 남아 실제 지원 하한을 과소 표기하고 있었다.
//
// **왜 주석을 제외하는가:** Podfile 의 설명 주석이 `ios_deployment_target` 과
// `Gem::Version` 식별자를 인용한다. 주석까지 세면 실행 라인이 사라진 회귀를
// 주석이 가려 버린다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _podfilePath = 'ios/Podfile';
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

/// [content] 에서 빈 줄과 [commentPrefix] 로 시작하는 주석 줄을 뺀 실행 라인을 돌려준다.
///
/// 각 줄은 앞뒤 공백을 제거한 형태로 반환한다.
List<String> extractExecutableLines(String content, String commentPrefix) {
  return content
      .split('\n')
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty)
      .where((String line) => !line.startsWith(commentPrefix))
      .toList();
}

/// Podfile 실행 라인 [executableLines] 에서 단일 출처 버전을 추출한다.
///
/// `ios_deployment_target = '<숫자 버전>'` 대입이 정확히 1개일 때만 그 버전을
/// 돌려준다. 0개(단일 출처 변수 없음)이거나 2개 이상(단일 출처 위반)이면 null 이다.
String? parsePodfileDeploymentTarget(List<String> executableLines) {
  final RegExp assignment = RegExp(
    r'''^ios_deployment_target\s*=\s*['"](\d+(?:\.\d+)*)['"]$''',
  );
  final List<String> versions = <String>[
    for (final String line in executableLines)
      if (assignment.firstMatch(line) case final RegExpMatch match)
        match.group(1)!,
  ];
  return versions.length == 1 ? versions.single : null;
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
  group('현재 트리 — Podfile 단일 출처 ↔ Runner pbxproj', () {
    late List<String> podfileLines;
    late String pbxprojContent;

    setUp(() {
      podfileLines = extractExecutableLines(readProjectFile(_podfilePath), '#');
      pbxprojContent = readProjectFile(_pbxprojPath);
    });

    test('Podfile 이 ios_deployment_target 변수 하나로 platform 을 선언한다', () {
      final String? version = parsePodfileDeploymentTarget(podfileLines);
      expect(
        version,
        isNotNull,
        reason: "ios_deployment_target = '<버전>' 대입이 정확히 1회 있어야 한다",
      );
      expect(RegExp(r'^\d+(\.\d+)*$').hasMatch(version!), isTrue);

      expect(
        podfileLines
            .where(
              (String line) => line == 'platform :ios, ios_deployment_target',
            )
            .length,
        1,
        reason: 'platform 선언은 단일 출처 변수를 참조해야 한다',
      );
      expect(
        podfileLines
            .where(
              (String line) =>
                  line.startsWith('platform :ios') &&
                  RegExp('[\'"]').hasMatch(line),
            )
            .toList(),
        isEmpty,
        reason: 'platform 선언 줄에 따옴표 버전 리터럴이 남으면 안 된다',
      );
    });

    test('post_install 이 flutter helper 호출 뒤 하한 상향 규칙을 적용한다', () {
      final List<int> helperIndexes = <int>[
        for (int i = 0; i < podfileLines.length; i++)
          if (podfileLines[i] ==
              'flutter_additional_ios_build_settings(target)')
            i,
      ];
      final List<int> raiseIndexes = <int>[
        for (int i = 0; i < podfileLines.length; i++)
          if (podfileLines[i].contains(
            'Gem::Version.new(ios_deployment_target)',
          ))
            i,
      ];

      expect(helperIndexes.length, 1);
      expect(
        raiseIndexes,
        isNotEmpty,
        reason: '하한 미만 pod target 상향 규칙이 사라지면 LINE SDK 빌드 실패가 재발한다',
      );
      expect(
        helperIndexes.single < raiseIndexes.first,
        isTrue,
        reason: 'helper 가 키를 지운 뒤에 상향해야 한다',
      );
    });

    test('Runner pbxproj 의 모든 deployment target 이 Podfile 버전과 같다', () {
      final String? version = parsePodfileDeploymentTarget(podfileLines);
      expect(version, isNotNull);

      final List<String> targets = collectPbxprojDeploymentTargets(
        pbxprojContent,
      );
      expect(targets, isNotEmpty);

      final List<String> mismatches = findDeploymentTargetMismatches(
        targets,
        version!,
      );
      expect(
        mismatches,
        isEmpty,
        reason:
            'Podfile 의 ios_deployment_target($version) 과 Runner pbxproj 의 '
            'IPHONEOS_DEPLOYMENT_TARGET 을 함께 바꾸세요. '
            '불일치 값: $mismatches',
      );
    });
  });

  group('검출 로직 — 수정 전 커밋(7866f8cd) fixture', () {
    // 7866f8cd 의 ios/Podfile 1–2행 그대로.
    const String legacyPodfile =
        '# iOS 최소 배포 타겟 (Firebase SDK 요구사항)\n'
        "platform :ios, '15.6'\n";
    // 7866f8cd 의 Runner pbxproj 대입 줄(탭 4개 들여쓰기) 과 값만 15.6 으로 바꾼 줄.
    const String legacyTargetLine =
        '\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 13.0;';
    const String alignedTargetLine =
        '\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 15.6;';

    test('문자열 리터럴 platform 선언은 단일 출처 변수 없음으로 판정한다', () {
      expect(
        parsePodfileDeploymentTarget(
          extractExecutableLines(legacyPodfile, '#'),
        ),
        isNull,
      );
    });

    test('주석 속 대입은 단일 출처로 인정하지 않는다', () {
      const String commentedPodfile =
          "# ios_deployment_target = '15.6'\n"
          "platform :ios, '15.6'\n";
      expect(
        parsePodfileDeploymentTarget(
          extractExecutableLines(commentedPodfile, '#'),
        ),
        isNull,
      );
    });

    test('대입이 2회 이상이면 단일 출처 위반으로 판정한다', () {
      const String duplicatedPodfile =
          "ios_deployment_target = '15.6'\n"
          "ios_deployment_target = '16.0'\n";
      expect(
        parsePodfileDeploymentTarget(
          extractExecutableLines(duplicatedPodfile, '#'),
        ),
        isNull,
      );
    });

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
  });
}
