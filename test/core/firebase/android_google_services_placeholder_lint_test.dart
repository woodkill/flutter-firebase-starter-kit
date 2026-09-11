// quick 260911-spw — Android stg/prod `google-services.json` placeholder
// 회귀 가드 lint test.
//
// **목적:** `android/app/src/{stg,prod}/google-services.json` 2종은
// `.gitignore` 예외(negation)로 tracked 되는 placeholder 다. 이 파일들이
// 없으면 fresh clone 직후 `--flavor stg` / `--flavor prod` Android 빌드가
// Gradle `:app:process<Flavor>DebugGoogleServices` 에서 "No matching client
// found for package name" 으로 실패한다. 반대로 실제 Firebase 키가 든
// 재생성본이 커밋되면 시크릿이 repo 에 유출된다.
//
// 따라서 본 가드는 두 방향을 동시에 단언한다.
//   (1) placeholder 가 존재하고 값이 gradle productFlavors 와 정확히 맞는가
//       → 빌드 게이트 회귀 차단
//   (2) placeholder 어휘가 유지되고 실 키 접두사가 없는가
//       → 시크릿 유출 회귀 차단 (skip-worktree + pre-commit hook 의 3중 방어 중
//         상시 실행되는 마지막 층)
//
// **검증 패턴:** 외부 의존 0 — `dart:io` 로 repo 파일을 직접 읽고
// `dart:convert` 의 `jsonDecode` 로만 파싱한다.
//
// **T-QUICK-260911-SPW-ANDROID-PLACEHOLDER-LINT-01**

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _stgJsonPath = 'android/app/src/stg/google-services.json';
const String _prodJsonPath = 'android/app/src/prod/google-services.json';
const String _gitignorePath = '.gitignore';

/// placeholder 어휘 (tracked iOS plist · Dart options 와 동일 규칙).
const String _placeholderProjectNumber = '000000000000';
const String _placeholderApiKey = 'PLACEHOLDER';
const String _placeholderAppIdPrefix = '1:000000000000:android:';

const String _stgProjectId = 'placeholder-stg';
const String _prodProjectId = 'placeholder-prod';

/// stg 의 applicationId — `android/app/build.gradle.kts:44` 의 base
/// `applicationId` + 같은 파일 77행 `create("stg") { applicationIdSuffix =
/// ".stg" }`.
const String _stgPackageName = 'com.slimpumpkin.flutter_starter_kit.stg';

/// prod 의 applicationId — `android/app/build.gradle.kts:78` 의
/// `create("prod") { /* prod는 suffix 없음 */ }` 이므로 **접미사가 없다**.
/// 같은 규칙이 `ios/Flutter/prod.example.xcconfig` 의
/// `PRODUCT_BUNDLE_IDENTIFIER` 에도 이미 적용되어 있다
/// (`com.slimpumpkin.flutterStarterKit` — 접미사 없음).
/// 여기에 `.prod` 를 붙이면 Gradle 이 "No matching client found" 로 실패한다.
const String _prodPackageName = 'com.slimpumpkin.flutter_starter_kit';

/// Google API 키 접두사. placeholder 에 이 문자열이 등장하면 실제 키가 든
/// 재생성본이 커밋된 것이다.
const String _googleApiKeyPrefix = 'AIza';

const String _stgNegationLine = '!android/app/src/stg/google-services.json';
const String _prodNegationLine = '!android/app/src/prod/google-services.json';

/// [path] 의 JSON 을 읽어 Map 으로 돌려준다. 파일이 없으면 조치 방법을 담아
/// 즉시 실패한다.
Map<String, dynamic> readPlaceholderJson(String path) {
  final File file = File(path);
  expect(
    file.existsSync(),
    isTrue,
    reason:
        '$path 부재 — fresh clone 직후 해당 flavor 의 Android 빌드가 Gradle '
        ':app:process<Flavor>DebugGoogleServices 에서 "No matching client '
        'found for package name" 으로 실패한다. quick 260911-spw 의 바이트 '
        '사양대로 placeholder 를 복구하고, .gitignore 의 negation 2줄이 '
        '유지되는지 확인할 것.',
  );
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
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
              '$_stgJsonPath 의 project_number 가 placeholder 가 아니다 — 실제 '
              'Firebase 프로젝트 번호가 커밋되려 한다. '
              'git restore --source=HEAD --staged --worktree $_stgJsonPath '
              '로 원복한 뒤 git update-index --skip-worktree $_stgJsonPath '
              '를 적용할 것.',
        );
        expect(
          projectInfo['project_id'],
          _stgProjectId,
          reason:
              '$_stgJsonPath 의 project_id 가 placeholder 가 아니다 — 위와 '
              '동일한 절차로 원복할 것.',
        );
      });

      test('stg placeholder 의 package_name 이 gradle stg applicationId 와 '
          '일치한다', () {
        final Map<String, dynamic> json = readPlaceholderJson(_stgJsonPath);

        expect(
          readPackageName(json),
          _stgPackageName,
          reason:
              '$_stgJsonPath 의 package_name 이 android/app/build.gradle.kts '
              '의 stg applicationId(base + ".stg") 와 다르다 — '
              ':app:processStgDebugGoogleServices 가 "No matching client '
              'found for package name" 으로 실패한다.',
        );
      });

      test('prod placeholder 의 package_name 이 gradle prod applicationId 와 '
          '일치한다 (접미사 없음)', () {
        final Map<String, dynamic> json = readPlaceholderJson(_prodJsonPath);

        expect(
          readPackageName(json),
          _prodPackageName,
          reason:
              '$_prodJsonPath 의 package_name 이 '
              'android/app/build.gradle.kts 의 prod applicationId 와 다르다. '
              'prod 는 productFlavors 에 applicationIdSuffix 가 없으므로 '
              'flavor 접미사를 붙이면 안 된다 — 붙이는 순간 '
              ':app:processProdDebugGoogleServices 가 실패한다.',
        );
        expect(
          (json['project_info'] as Map<String, dynamic>)['project_id'],
          _prodProjectId,
          reason: '$_prodJsonPath 의 project_id 가 placeholder 가 아니다.',
        );
      });

      test('stg/prod placeholder 어느 쪽에도 실제 Google API 키가 없다', () {
        for (final String path in <String>[_stgJsonPath, _prodJsonPath]) {
          final Map<String, dynamic> json = readPlaceholderJson(path);
          final String raw = File(path).readAsStringSync();

          expect(
            raw.contains(_googleApiKeyPrefix),
            isFalse,
            reason:
                '$path 에 Google API 키 접두사가 포함되어 있다 — 실제 키가 든 '
                'flutterfire configure 재생성본이다. '
                'git restore --source=HEAD --staged --worktree $path 로 '
                '원복한 뒤 git update-index --skip-worktree $path 를 적용할 것 '
                '(scripts/firebase-configure.sh 가 자동 적용한다).',
          );
          expect(
            readCurrentKey(json),
            _placeholderApiKey,
            reason: '$path 의 api_key[0].current_key 가 placeholder 가 아니다.',
          );
          expect(
            readMobilesdkAppId(json),
            startsWith(_placeholderAppIdPrefix),
            reason:
                '$path 의 mobilesdk_app_id 가 placeholder 접두사로 시작하지 '
                '않는다 — 실제 Firebase 앱 ID 로 보인다.',
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
}
