// quick 260911-spw / 260911-twn — Android `google-services.json` 2종 +
// iOS `GoogleService-Info.plist` 3종 = 양 플랫폼 커밋 placeholder 가드.
//
// **목적:** `android/app/src/{stg,prod}/google-services.json` 2종은
// `.gitignore` 예외(negation)로, `ios/config/{dev,stg,prod}/`
// `GoogleService-Info.plist` 3종은 애초에 무시 대상이 아니라서 tracked 되는
// placeholder 다. 이 파일들이 없으면 fresh clone 직후 빌드가 깨진다.
//
//   - Android: Gradle `:app:process<Flavor>DebugGoogleServices` 가
//     "No matching client found for package name" 으로 실패한다.
//   - iOS: `ios/Runner.xcodeproj` 의 `Copy GoogleService-Info.plist` 빌드
//     단계가 `error: GoogleService-Info.plist not found for flavor` 로
//     exit 1 한다.
//
// 반대로 실제 Firebase 키가 든 재생성본이 커밋되면 시크릿이 repo 에 유출된다.
//
// 따라서 본 가드는 두 방향을 동시에 단언한다.
//   (1) placeholder 가 존재하고 값이 gradle `applicationId` + productFlavors
//       접미사 · pbxproj 번들 ID + flavor 접미사와 정확히 맞는가
//       → 빌드 게이트 회귀 차단. 기대 앱 ID 는 상수가 아니라 커밋된 빌드
//         파일에서 읽는다 — `bin/rename.dart` 가 빌드 파일과 placeholder 를
//         같이 바꾼 저장소에서도 이 가드가 참이어야 한다.
//   (2) placeholder 어휘가 유지되고 실 키 접두사가 없는가
//       → 시크릿 유출 회귀 차단 (skip-worktree + pre-commit hook 의 3중 방어
//         중 상시 실행되는 마지막 층)
//
// **왜 워킹트리가 아니라 커밋된 내용을 읽는가 (quick 260911-twn):**
// 개발자가 `./scripts/firebase-configure.sh <flavor>` 를 실행하면 워킹트리
// 파일이 실제 키로 바뀌지만, 같은 스크립트가 `git update-index
// --skip-worktree` 를 걸기 때문에 `git status` 에도 뜨지 않는다. 그 상태에서
// 워킹트리를 읽으면 **개발자 머신에서만** 가드가 RED 가 되고(오탐), 정작
// 물어야 할 질문("실 키가 커밋되었는가")에는 답하지 못한다. 시크릿 유출
// 가드의 진실원은 index/HEAD 다. 따라서 **값 단언은 `git show HEAD:<path>`**,
// **파일 존재 단언만 워킹트리**를 본다(빌드 게이트는 워킹트리가 진실원).
//
// **시크릿 마스킹:** 시크릿을 담을 수 있는 필드의 비교는
// `expect(actual, expected)` 대신 `expect(actual == expected, isTrue,
// reason: ...)` 형태로 쓴다. 전자는 실패 메시지에 **실제 값을 그대로 출력**
// 하므로, 가드가 RED 가 되는 순간(= 실 키가 커밋된 순간) test 로그에 키가
// 찍힌다.
//
// **검증 패턴:** 외부 의존 0 — `dart:io` 의 `File` / `Process.runSync('git',
// ...)` 와 `dart:convert` 의 `jsonDecode` 만 쓴다.
//
// **T-QUICK-260911-SPW-ANDROID-PLACEHOLDER-LINT-01**
// **T-QUICK-260911-TWN-IOS-PLIST-PLACEHOLDER-LINT-01**

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _stgJsonPath = 'android/app/src/stg/google-services.json';
const String _prodJsonPath = 'android/app/src/prod/google-services.json';
const String _gitignorePath = '.gitignore';

const String _devPlistPath = 'ios/config/dev/GoogleService-Info.plist';
const String _stgPlistPath = 'ios/config/stg/GoogleService-Info.plist';
const String _prodPlistPath = 'ios/config/prod/GoogleService-Info.plist';

/// placeholder 어휘 (tracked iOS plist · Dart options 와 동일 규칙).
const String _placeholderProjectNumber = '000000000000';
const String _placeholderApiKey = 'PLACEHOLDER';
const String _placeholderAppIdPrefix = '1:000000000000:android:';

/// iOS placeholder 어휘 — GOOGLE_APP_ID 는 platform 토큰만 다르다.
const String _placeholderIosAppIdPrefix = '1:000000000000:ios:';

const String _devProjectId = 'placeholder-dev';
const String _stgProjectId = 'placeholder-stg';
const String _prodProjectId = 'placeholder-prod';

/// Android 앱 ID 진실원 — `applicationId` 를 담은 Gradle 빌드 파일.
const String _gradlePath = 'android/app/build.gradle.kts';

/// iOS 번들 ID 진실원 — `RunnerTests` 번들 ID 를 담은 Xcode 프로젝트 파일.
const String _pbxprojPath = 'ios/Runner.xcodeproj/project.pbxproj';

/// 커밋된 [_gradlePath] 의 base `applicationId` 를 돌려준다.
///
/// 앱 ID 는 `bin/rename.dart` 로 바뀌므로 상수로 박지 않고 빌드 파일에서
/// 읽는다 — rename 이 placeholder 와 빌드 파일을 같이 바꾼 저장소에서도
/// 같은 기준으로 비교한다. placeholder 값과 같은 출처(HEAD)를 읽어 커밋 전
/// 작업 트리 상태에 흔들리지 않는다.
String readBaseApplicationId() {
  final RegExpMatch? match = RegExp(
    r'^\s*applicationId\s*=\s*"([^"]+)"',
    multiLine: true,
  ).firstMatch(readCommittedText(_gradlePath));
  expect(
    match,
    isNotNull,
    reason: '커밋된 $_gradlePath 에서 applicationId 줄을 찾지 못했다.',
  );
  return match!.group(1)!;
}

/// 커밋된 [_pbxprojPath] 의 base iOS 번들 ID 를 돌려준다.
///
/// `RunnerTests` 타깃 번들 ID(`<base>.RunnerTests`)에서 접미사를 뗀 값이다.
/// 킷 추적 `ios/Flutter/*.example.xcconfig` 는 rename 이 바꾸지 않으므로
/// rename 뒤 저장소의 진실원이 될 수 없다.
String readBaseIosBundleId() {
  final RegExpMatch? match = RegExp(
    r'PRODUCT_BUNDLE_IDENTIFIER = ([^;\s]+)\.RunnerTests;',
  ).firstMatch(readCommittedText(_pbxprojPath));
  expect(
    match,
    isNotNull,
    reason: '커밋된 $_pbxprojPath 에서 RunnerTests 번들 ID 를 찾지 못했다.',
  );
  return match!.group(1)!;
}

/// stg 의 applicationId 를 읽어 돌려준다 — base `applicationId` +
/// productFlavors `create("stg") { applicationIdSuffix = ".stg" }`.
String readStgPackageName() => '${readBaseApplicationId()}.stg';

/// prod 의 applicationId 를 읽어 돌려준다 — productFlavors `create("prod")` 에
/// `applicationIdSuffix` 가 없으므로 **접미사가 없다**. 여기에 `.prod` 를
/// 붙이면 Gradle 이 "No matching client found" 로 실패한다.
String readProdPackageName() => readBaseApplicationId();

/// flavor 의 iOS bundle id 를 읽어 돌려준다 — base 번들 ID + flavor
/// 접미사(prod 는 없음). 이 값이 어긋나면 Xcode 가 복사한 plist 와 실제
/// 번들이 불일치해 Firebase 초기화가 런타임에 어긋난다.
String readIosBundleId(String suffix) => '${readBaseIosBundleId()}$suffix';

/// Google API 키 접두사. placeholder 에 이 문자열이 등장하면 실제 키가 든
/// 재생성본이 커밋된 것이다.
const String _googleApiKeyPrefix = 'AIza';

/// iOS 빌드에서 사용되지 않는 Android OAuth client ID key. `flutterfire
/// configure` 가 iOS plist 에 함께 써 넣지만 placeholder 3종은 이 key 를
/// 갖지 않는다 (260411-04e-REVIEW.md WR-02).
const String _androidClientIdKey = 'ANDROID_CLIENT_ID';

const String _stgNegationLine = '!android/app/src/stg/google-services.json';
const String _prodNegationLine = '!android/app/src/prod/google-services.json';

/// [path] 의 **커밋된(HEAD) 내용**을 돌려준다.
///
/// 워킹트리를 읽지 않는 이유: 개발자가
/// `scripts/firebase-configure.sh <flavor>` 를 실행하면 워킹트리 파일이
/// 실 키로 바뀌지만 skip-worktree 때문에 `git status` 에 뜨지 않는다.
/// 시크릿 유출 가드의 진실원은 **index/HEAD** 이지 워킹트리가 아니다.
String readCommittedText(String path) {
  final ProcessResult result = Process.runSync(
    'git',
    <String>['show', 'HEAD:$path'],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  expect(
    result.exitCode,
    0,
    reason:
        'git show HEAD:$path 실패 — git 이 PATH 에 없거나 해당 경로가 아직 '
        '커밋되지 않았다. (skip 하지 않고 실패시킨다: 이 가드가 조용히 꺼지면 '
        '실 키 커밋을 아무도 못 막는다.)',
  );
  return result.stdout as String;
}

/// plist XML 에서 [key] 에 대응하는 `<string>` 값을 돌려준다. 없으면 null.
String? readPlistString(String plistText, String key) => RegExp(
  '<key>${RegExp.escape(key)}</key>\\s*<string>([^<]*)</string>',
).firstMatch(plistText)?.group(1);

/// [key] 자체의 존재 여부 (`ANDROID_CLIENT_ID` 부재 단언용).
bool hasPlistKey(String plistText, String key) =>
    plistText.contains('<key>$key</key>');

/// [path] 가 워킹트리에 존재하는지 단언한다 (빌드 게이트 — 진실원은
/// 워킹트리다. 파일이 없으면 값이 무엇이든 빌드가 깨진다).
void expectPlaceholderFileExists(String path, {required String buildFailure}) {
  expect(
    File(path).existsSync(),
    isTrue,
    reason:
        '$path 부재 — fresh clone 직후 해당 flavor 빌드가 $buildFailure 로 '
        '실패한다. quick 260911-spw / 260911-twn 의 바이트 사양대로 '
        'placeholder 를 복구할 것 (iOS plist 는 다른 flavor 파일을 복사한 뒤 '
        'BUNDLE_ID · PROJECT_ID · STORAGE_BUCKET 3 줄만 바꾸면 된다).',
  );
}

/// [path] 의 **커밋된** JSON 을 Map 으로 돌려준다. 워킹트리 파일 존재는
/// 별도로 단언한다 (D-03 — 값은 HEAD, 존재는 워킹트리).
Map<String, dynamic> readPlaceholderJson(String path) {
  expectPlaceholderFileExists(
    path,
    buildFailure:
        'Gradle :app:process<Flavor>DebugGoogleServices 의 "No matching '
        'client found for package name"',
  );
  return jsonDecode(readCommittedText(path)) as Map<String, dynamic>;
}

/// [json] 의 `client[0].client_info.android_client_info.package_name` 을
/// 돌려준다.
String readPackageName(Map<String, dynamic> json) {
  final List<dynamic> clients = json['client'] as List<dynamic>;
  final Map<String, dynamic> clientInfo =
      (clients.first as Map<String, dynamic>)['client_info']
          as Map<String, dynamic>;
  final Map<String, dynamic> androidClientInfo =
      clientInfo['android_client_info'] as Map<String, dynamic>;
  return androidClientInfo['package_name'] as String;
}

/// [json] 의 `client[0].api_key[0].current_key` 를 돌려준다.
String readCurrentKey(Map<String, dynamic> json) {
  final List<dynamic> clients = json['client'] as List<dynamic>;
  final List<dynamic> apiKeys =
      (clients.first as Map<String, dynamic>)['api_key'] as List<dynamic>;
  return (apiKeys.first as Map<String, dynamic>)['current_key'] as String;
}

/// [json] 의 `client[0].client_info.mobilesdk_app_id` 를 돌려준다.
String readMobilesdkAppId(Map<String, dynamic> json) {
  final List<dynamic> clients = json['client'] as List<dynamic>;
  final Map<String, dynamic> clientInfo =
      (clients.first as Map<String, dynamic>)['client_info']
          as Map<String, dynamic>;
  return clientInfo['mobilesdk_app_id'] as String;
}

/// 원복 안내 — 실 키가 커밋됐을 때 개발자가 따라야 할 조치.
String _restoreHint(String path) =>
    'git restore --source=HEAD --staged --worktree $path 로 원복한 뒤 '
    'git update-index --skip-worktree $path 를 적용할 것 '
    '(./scripts/firebase-configure.sh <flavor> 가 자동 적용한다).';

/// 커밋된 iOS plist 1개가 placeholder 사양을 만족하는지 단언한다.
/// 모든 값 비교는 마스킹형(`== ` 불리언)이라 실패 메시지에 실 값이 찍히지
/// 않는다.
void expectCommittedIosPlaceholderPlist({
  required String path,
  required String bundleId,
  required String projectId,
}) {
  final String plist = readCommittedText(path);
  final String hint = _restoreHint(path);

  expect(
    readPlistString(plist, 'BUNDLE_ID') == bundleId,
    isTrue,
    reason:
        '커밋된 $path 의 BUNDLE_ID 가 $bundleId 가 아니다 — '
        'ios/Runner.xcodeproj/project.pbxproj 의 번들 ID + flavor 접미사와 '
        '어긋났거나 실 프로젝트 재생성본이 '
        '커밋됐다. $hint',
  );
  expect(
    readPlistString(plist, 'PROJECT_ID') == projectId,
    isTrue,
    reason:
        '커밋된 $path 의 PROJECT_ID 가 $projectId 가 아니다 — 실제 Firebase '
        '프로젝트 식별자가 커밋되려 한다. $hint',
  );
  expect(
    readPlistString(plist, 'GCM_SENDER_ID') == _placeholderProjectNumber,
    isTrue,
    reason:
        '커밋된 $path 의 GCM_SENDER_ID 가 placeholder 가 아니다 — 실제 '
        'Firebase 프로젝트 번호가 커밋되려 한다. $hint',
  );
  for (final String key in <String>[
    'API_KEY',
    'CLIENT_ID',
    'REVERSED_CLIENT_ID',
  ]) {
    expect(
      readPlistString(plist, key) == _placeholderApiKey,
      isTrue,
      reason:
          '커밋된 $path 의 $key 가 placeholder 어휘($_placeholderApiKey) 가 '
          '아니다 — 실제 키/클라이언트 식별자가 커밋되려 한다. $hint',
    );
  }
  expect(
    (readPlistString(plist, 'GOOGLE_APP_ID') ?? '').startsWith(
      _placeholderIosAppIdPrefix,
    ),
    isTrue,
    reason:
        '커밋된 $path 의 GOOGLE_APP_ID 가 placeholder 접두사로 시작하지 '
        '않는다 — 실제 Firebase 앱 ID 로 보인다. $hint',
  );
}

void main() {
  group(
    'T-QUICK-260911-SPW-ANDROID-PLACEHOLDER-LINT-01: Android google-services '
    'placeholder 가드',
    () {
      test('stg placeholder 의 project_info 가 placeholder 어휘를 유지한다', () {
        final Map<String, dynamic> json = readPlaceholderJson(_stgJsonPath);
        final Map<String, dynamic> projectInfo =
            json['project_info'] as Map<String, dynamic>;

        expect(
          projectInfo['project_number'],
          _placeholderProjectNumber,
          reason:
              '커밋된 $_stgJsonPath 의 project_number 가 placeholder 가 '
              '아니다 — 실제 Firebase 프로젝트 번호가 커밋되려 한다. '
              '${_restoreHint(_stgJsonPath)}',
        );
        expect(
          projectInfo['project_id'],
          _stgProjectId,
          reason:
              '커밋된 $_stgJsonPath 의 project_id 가 placeholder 가 아니다 — '
              '위와 동일한 절차로 원복할 것.',
        );
      });

      test('stg placeholder 의 package_name 이 gradle stg applicationId 와 '
          '일치한다', () {
        final Map<String, dynamic> json = readPlaceholderJson(_stgJsonPath);

        expect(
          readPackageName(json),
          readStgPackageName(),
          reason:
              '커밋된 $_stgJsonPath 의 package_name 이 '
              'android/app/build.gradle.kts 의 stg applicationId(base + '
              '".stg") 와 다르다 — :app:processStgDebugGoogleServices 가 '
              '"No matching client found for package name" 으로 실패한다.',
        );
      });

      test('prod placeholder 의 package_name 이 gradle prod applicationId 와 '
          '일치한다 (접미사 없음)', () {
        final Map<String, dynamic> json = readPlaceholderJson(_prodJsonPath);

        expect(
          readPackageName(json),
          readProdPackageName(),
          reason:
              '커밋된 $_prodJsonPath 의 package_name 이 '
              'android/app/build.gradle.kts 의 prod applicationId 와 다르다. '
              'prod 는 productFlavors 에 applicationIdSuffix 가 없으므로 '
              'flavor 접미사를 붙이면 안 된다 — 붙이는 순간 '
              ':app:processProdDebugGoogleServices 가 실패한다.',
        );
        expect(
          (json['project_info'] as Map<String, dynamic>)['project_id'],
          _prodProjectId,
          reason: '커밋된 $_prodJsonPath 의 project_id 가 placeholder 가 아니다.',
        );
      });

      test('stg/prod placeholder 어느 쪽에도 실제 Google API 키가 없다', () {
        for (final String path in <String>[_stgJsonPath, _prodJsonPath]) {
          final Map<String, dynamic> json = readPlaceholderJson(path);
          final String raw = readCommittedText(path);

          expect(
            raw.contains(_googleApiKeyPrefix),
            isFalse,
            reason:
                '커밋된 $path 에 Google API 키 접두사가 포함되어 있다 — 실제 '
                '키가 든 flutterfire configure 재생성본이다. '
                '${_restoreHint(path)}',
          );
          expect(
            readCurrentKey(json) == _placeholderApiKey,
            isTrue,
            reason:
                '커밋된 $path 의 api_key[0].current_key 가 placeholder 가 '
                '아니다. ${_restoreHint(path)}',
          );
          expect(
            readMobilesdkAppId(json),
            startsWith(_placeholderAppIdPrefix),
            reason:
                '커밋된 $path 의 mobilesdk_app_id 가 placeholder 접두사로 '
                '시작하지 않는다 — 실제 Firebase 앱 ID 로 보인다.',
          );
        }
      });

      test('.gitignore 가 stg/prod placeholder 2종을 negation 으로 되살린다', () {
        final File gitignoreFile = File(_gitignorePath);
        expect(
          gitignoreFile.existsSync(),
          isTrue,
          reason: '.gitignore 부재 — placeholder tracking 예외 검증 불가.',
        );

        final List<String> lines = gitignoreFile
            .readAsLinesSync()
            .map((String line) => line.trim())
            .where((String line) => line.isNotEmpty && !line.startsWith('#'))
            .toList();

        for (final String negation in <String>[
          _stgNegationLine,
          _prodNegationLine,
        ]) {
          expect(
            lines,
            contains(negation),
            reason:
                '.gitignore 에 "$negation" 이 없다 — 해당 placeholder 가 '
                '**/android/app/src/*/google-services.json 무시 패턴에 걸려 '
                '조용히 untracked 로 남는다. 무시 패턴 **뒤** 줄에 negation 을 '
                '복구할 것 (negation 이 앞에 오면 git 이 무시한다).',
          );
        }
      });
    },
  );

  group('T-QUICK-260911-TWN-IOS-PLIST-PLACEHOLDER-LINT-01: iOS '
      'GoogleService-Info.plist placeholder 가드', () {
    test('커밋된 dev plist 가 placeholder 사양을 만족한다', () {
      expectCommittedIosPlaceholderPlist(
        path: _devPlistPath,
        bundleId: readIosBundleId('.dev'),
        projectId: _devProjectId,
      );
    });

    test('커밋된 stg plist 가 placeholder 사양을 만족한다', () {
      expectCommittedIosPlaceholderPlist(
        path: _stgPlistPath,
        bundleId: readIosBundleId('.stg'),
        projectId: _stgProjectId,
      );
    });

    test('커밋된 prod plist 가 placeholder 사양을 만족한다 (접미사 없음)', () {
      expectCommittedIosPlaceholderPlist(
        path: _prodPlistPath,
        bundleId: readIosBundleId(''),
        projectId: _prodProjectId,
      );
    });

    test('커밋된 iOS plist 3종에 실 키도 ANDROID_CLIENT_ID 도 없다', () {
      for (final String path in <String>[
        _devPlistPath,
        _stgPlistPath,
        _prodPlistPath,
      ]) {
        final String plist = readCommittedText(path);

        expect(
          plist.contains(_googleApiKeyPrefix),
          isFalse,
          reason:
              '커밋된 $path 에 Google API 키 접두사가 포함되어 있다 — 실제 '
              '키가 든 flutterfire configure 재생성본이다. '
              '${_restoreHint(path)}',
        );
        expect(
          hasPlistKey(plist, _androidClientIdKey),
          isFalse,
          reason:
              '커밋된 $path 에 $_androidClientIdKey key 가 있다 — iOS '
              '빌드에서 쓰이지 않는 Android OAuth client ID 가 불필요하게 '
              '노출된다 (260411-04e-REVIEW.md WR-02). flutterfire 재생성본을 '
              '커밋하지 말고 ${_restoreHint(path)}',
        );
      }
    });

    test('워킹트리에 iOS plist 3종이 모두 존재한다 (Xcode copy 빌드 단계 게이트)', () {
      for (final String path in <String>[
        _devPlistPath,
        _stgPlistPath,
        _prodPlistPath,
      ]) {
        expectPlaceholderFileExists(
          path,
          buildFailure:
              'Xcode 의 Copy GoogleService-Info.plist 빌드 단계가 '
              '"error: GoogleService-Info.plist not found for flavor"',
        );
      }
    });
  });
}
