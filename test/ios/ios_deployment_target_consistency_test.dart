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
// **설계 메모:** 현재 트리 단언에는 배포 타겟의 **현재 값 리터럴을 적지 않는다**
// (진실원 이중화 방지 — D-06). 대신 값 목록이 비어 있지 않음과 개수 12 를 먼저
// 단언한 뒤 「전부 같은 값」 을 본다. 빈 목록에서는 「불일치 0」 이 공허하게
// 참이므로 순서가 중요하다. 부재 단언(D-15)은 `readTrackedFile` 을 쓰지 않는다 —
// 그 헬퍼는 파일이 없을 때 `fail()` 하므로 부재를 검사할 수 없다.
//
// **하한 단언을 더한 이유(코드 리뷰 WR-01 — 16.3-REVIEW.md WR-03):** 「전부 같은
// 값」 은 기대값을 피검사 데이터(`targets.first`)에서 끌어오므로 **12개가 모두
// 13.0 이어도 green 이다** — 위 「결함 사례」 가 바로 그 모양이다. 그래서 현재 값을
// 고정하는 대신 [_minSupportedIosTarget] **하한만** 단언한다. 하한은 진실원의
// 복제가 아니라 외부 의존(Flutter · LineSDK)이 부과하는 **독립 제약**이므로
// D-06 을 깨지 않는다. 15.6 → 15.7 같은 정상 상향은 그대로 통과한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

const String _podfilePathForAbsence = 'ios/Podfile';
const String _pbxprojPath = 'ios/Runner.xcodeproj/project.pbxproj';

/// iOS 최소 배포 타겟이 내려갈 수 없는 하한.
///
/// Flutter 3.47 이 지원하는 iOS 최소 버전(15.0)이자, 킷이 고정한 LineSDK 5.17.0 의
/// `platforms` 하한과 같은 값이다. 이보다 낮추면 SPM 이 타깃 그래프 구성 단계에서
/// 빌드를 막는다 (`docs/manual.md` 「iOS 의존성 관리 (SPM)」 ③ (나) · ⑤).
const String _minSupportedIosTarget = '15.0';

/// 점 구분 버전 [version] 을 정수 성분 목록으로 바꾼다.
///
/// `15.6` → `[15, 6]`, `15.6.1` → `[15, 6, 1]`.
/// 정수가 아닌 성분은 `FormatException` 으로 드러낸다 — 조용히 통과시키지 않는다.
List<int> parseVersionComponents(String version) {
  return version.split('.').map((String part) {
    final int? value = int.tryParse(part);
    if (value == null) {
      throw FormatException(
        'IPHONEOS_DEPLOYMENT_TARGET 을 점 구분 정수 버전으로 읽을 수 없다',
        version,
      );
    }
    return value;
  }).toList();
}

/// 버전 [a] 와 [b] 를 **성분 단위로** 비교한다 (`a < b` 면 음수, 같으면 0).
///
/// 성분 수가 다르면 짧은 쪽을 0 으로 채운다 — `15` 와 `15.0` 은 같다.
int compareVersions(String a, String b) {
  final List<int> left = parseVersionComponents(a);
  final List<int> right = parseVersionComponents(b);
  final int length = left.length > right.length ? left.length : right.length;
  for (int i = 0; i < length; i++) {
    final int l = i < left.length ? left[i] : 0;
    final int r = i < right.length ? right[i] : 0;
    if (l != r) {
      return l < r ? -1 : 1;
    }
  }
  return 0;
}

/// 배포 타겟 [target] 이 [_minSupportedIosTarget] 미만인지 판정한다.
///
/// **`double.parse` 로 비교하지 않는다**(코드 리뷰 IN-07(R2)). 그 방식은
/// 2-component 값에서만 안전했다 — `15.6.1` 같은 3-component 값은 expect 실패가
/// 아니라 `FormatException` 으로 test 를 죽이고, `15.10` 은 `15.1` 로 해석돼
/// `15.6` 보다 **낮다고** 판정된다. 성분 단위 비교는 둘 다 올바르게 다룬다.
bool isDeploymentTargetBelowMinimum(String target) =>
    compareVersions(target, _minSupportedIosTarget) < 0;

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
        readTrackedFile(_pbxprojPath),
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

      // 위 단언은 기대값을 피검사 데이터에서 끌어오므로 「전부 13.0」 을 통과시킨다.
      // 헤더 「결함 사례」 를 되살려 검출하는 것은 아래 하한 단언뿐이다.
      expect(
        isDeploymentTargetBelowMinimum(targets.first),
        isFalse,
        reason:
            '배포 타겟이 $_minSupportedIosTarget 미만(현재 ${targets.first})이면 '
            'Flutter 3.47 의 iOS 최소 지원과 LineSDK 5.17.0 의 platforms 하한에 '
            '어긋나 iOS 빌드가 멈춘다 (헤더 「결함 사례」 재발). '
            '$_pbxprojPath 의 IPHONEOS_DEPLOYMENT_TARGET 12개를 함께 올리세요.',
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

    test('하한 단언이 헤더 「결함 사례」(13.0) 를 검출한다', () {
      // 「전부 같은 값」 단언이 못 잡는 모양 — 12개가 모두 13.0 인 트리.
      final List<String> allLegacy = collectPbxprojDeploymentTargets(
        '$legacyTargetLine\n$legacyTargetLine\n',
      );
      expect(
        findDeploymentTargetMismatches(allLegacy, allLegacy.first),
        isEmpty,
        reason: '일치 단언만으로는 green 이 되는 것이 이 하한 단언의 존재 이유다',
      );
      expect(isDeploymentTargetBelowMinimum(allLegacy.first), isTrue);

      // 하한 경계와 현재 값은 통과한다 — 정상 상향을 막지 않는다.
      expect(isDeploymentTargetBelowMinimum('15.0'), isFalse);
      expect(isDeploymentTargetBelowMinimum('15.6'), isFalse);
      expect(isDeploymentTargetBelowMinimum('16.0'), isFalse);
    });

    test('대입이 0건인 입력은 빈 목록이다', () {
      // 현재 트리 단언이 `isNotEmpty` · 개수 12 를 **먼저** 세우는 이유를 고정한다:
      // 가드가 없으면 매칭 0건에서 「불일치 0」 이 공허하게 참이 된다.
      expect(collectPbxprojDeploymentTargets(''), isEmpty);
      expect(findDeploymentTargetMismatches(<String>[], '0'), isEmpty);
    });
  });

  group('버전 비교 — double.parse 가 틀리던 입력 (코드 리뷰 IN-07(R2))', () {
    test('3-component 값이 예외가 아니라 정상 판정된다', () {
      // double.parse('15.6.1') 은 FormatException 으로 test 를 죽였다.
      expect(parseVersionComponents('15.6.1'), <int>[15, 6, 1]);
      expect(isDeploymentTargetBelowMinimum('15.6.1'), isFalse);
      expect(isDeploymentTargetBelowMinimum('14.9.9'), isTrue);
    });

    test('15.10 을 15.1 로 읽지 않는다', () {
      // double 비교에서는 15.10 → 15.1 이라 15.6 보다 "낮다" 고 판정됐다.
      expect(compareVersions('15.10', '15.6') > 0, isTrue);
      expect(compareVersions('15.6', '15.10') < 0, isTrue);
      expect(isDeploymentTargetBelowMinimum('15.10'), isFalse);
    });

    test('성분 수가 달라도 0 으로 채워 비교한다', () {
      expect(compareVersions('15', '15.0'), 0);
      expect(compareVersions('15.0.0', '15'), 0);
      expect(isDeploymentTargetBelowMinimum('15'), isFalse);
    });

    test('하한 경계와 그 바로 아래를 가른다', () {
      expect(isDeploymentTargetBelowMinimum('15.0'), isFalse);
      expect(isDeploymentTargetBelowMinimum('14.99'), isTrue);
    });

    test('정수가 아닌 성분은 FormatException 으로 드러난다', () {
      // 조용히 통과시키지 않는다는 계약을 고정한다.
      expect(
        () => parseVersionComponents('15.6-beta'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => isDeploymentTargetBelowMinimum(''),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
