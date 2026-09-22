// Naver 시크릿 주입 배선 계약 테스트 (Phase 16.2 — see ROADMAP.md).
//
// Naver 키가 **빌드 타임 native 설정으로만** 주입된다는 계약
// (D-01 · D-02 · D-03 · D-06 · D-07 · C-02 · C-04)을 소스 수준에서 잠근다.
// Dart 런타임 상수도, 플러그인 configure CLI 가 남기는 평문도 허용하지 않는다.
//
// **tracked 파일만 읽는다** — gitignored 실 키 파일(`config/{flavor}.json` ·
// `ios/Flutter/{flavor}.xcconfig`)은 열지 않으므로 fresh clone · CI 에서도
// 결과가 같다. 주석을 걷어낸 뒤 세는 이유는 설명 주석이 감사용 grep 카운트를
// 오염시키기 때문이다 (AndroidManifest.xml 이 같은 규칙을 명문화하고 있다).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `//` 로 시작하는 행 주석을 제거한다 (Dart · Kotlin · xcconfig 공용).
String stripSlashComments(String raw) => raw
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// `#` 로 시작하는 행 주석을 제거한다 (YAML).
String stripHashComments(String raw) => raw
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('#'))
    .join('\n');

/// `<!-- ... -->` 블록 주석을 제거한다 (XML · plist).
String stripXmlComments(String raw) =>
    raw.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// [needle] 이 [haystack] 에 나타나는 횟수를 센다.
int countOccurrences(String haystack, String needle) {
  if (needle.isEmpty) {
    return 0;
  }
  var count = 0;
  var index = haystack.indexOf(needle);
  while (index != -1) {
    count++;
    index = haystack.indexOf(needle, index + needle.length);
  }
  return count;
}

String readTracked(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: 'tracked 파일 부재: $path');
  return file.readAsStringSync();
}

void main() {
  group('Naver 시크릿 주입 배선 계약 (Phase 16.2)', () {
    // Phase 16.3 D-01 의 `enable-swift-package-manager` 키 부재 단언은 이 test 에
    // 얹혀 있었다(코드 리뷰 IN-03). SPM 회귀로 red 가 났을 때 Naver 파일을
    // 뒤지게 되는 오도를 없애려고 `test/ios/spm_policy_test.dart` 의
    // `T-16.3-SPM-04` 로 옮겼다 — 단언 자체는 그대로 살아 있다.
    test('T-16.2-NATIVE-01 pubspec pin — naver_login_flutter 정확 고정', () {
      final pubspec = stripHashComments(readTracked('pubspec.yaml'));

      expect(
        countOccurrences(pubspec, 'naver_login_flutter: 4.0.0'),
        1,
        reason:
            'C-02: naver_login_flutter 는 caret 없는 정확 고정 1줄이어야 한다. '
            'pubspec.yaml 의 의존성 줄을 확인할 것 (Wave 1 공급망 감사 기준선 대상).',
      );
      expect(
        countOccurrences(pubspec, 'naver_login_flutter: ^'),
        0,
        reason:
            'C-02: caret 범위 지정은 감사한 sha256 이외의 버전을 끌어올 수 있다. '
            'pubspec.yaml 에서 ^ 를 제거할 것.',
      );
      expect(
        countOccurrences(pubspec, 'naver_login_sdk'),
        0,
        reason:
            'Phase 16.2: 구 플러그인 naver_login_sdk 는 완전히 제거됐다. '
            'pubspec.yaml 에 잔존하면 두 SDK 가 동시에 링크된다.',
      );
    });

    test(
      'T-16.2-NATIVE-02 gradle resValue — dart-define → string resource',
      () {
        final gradle = stripSlashComments(
          readTracked('android/app/build.gradle.kts'),
        );
        final lines = gradle.split('\n');

        bool hasPairOnSameLine(String resourceName, String dartDefineKey) =>
            lines.any(
              (line) =>
                  line.contains(resourceName) && line.contains(dartDefineKey),
            );

        expect(
          hasPairOnSameLine('naver_client_id', 'dartDefines["naverClientId"]'),
          isTrue,
          reason:
              'D-01: naver_client_id resValue 는 config json 의 naverClientId '
              'dart-define 에서 와야 한다. android/app/build.gradle.kts 확인.',
        );
        expect(
          hasPairOnSameLine(
            'naver_client_secret',
            'dartDefines["naverClientSecret"]',
          ),
          isTrue,
          reason:
              'D-01: naver_client_secret resValue 는 config json 의 '
              'naverClientSecret dart-define 에서 와야 한다.',
        );
        expect(
          hasPairOnSameLine('naver_client_name', 'dartDefines["appName"]'),
          isTrue,
          reason:
              'D-06: Android 동의 화면 앱 이름은 기존 appName 키를 재사용한다 — '
              '전용 키를 새로 만들지 말 것.',
        );
        expect(
          countOccurrences(gradle, 'manifestPlaceholders["naver'),
          0,
          reason:
              'D-01: Naver 키는 resValue + @string 참조로만 주입한다 — '
              'manifestPlaceholders 경로는 금지다 (평문이 manifest 에 박힌다).',
        );
      },
    );

    test('T-16.2-NATIVE-03 manifest meta-data — @string 참조 + 로그 비활성', () {
      final manifest = stripXmlComments(
        readTracked('android/app/src/main/AndroidManifest.xml'),
      );

      for (final name in const <String>[
        'com.naver.sdk.clientId',
        'com.naver.sdk.clientSecret',
        'com.naver.sdk.clientName',
        'com.naver.sdk.logEnabled',
      ]) {
        expect(
          countOccurrences(manifest, name),
          1,
          reason:
              'D-01: meta-data $name 이 정확히 1건이어야 한다. '
              'AndroidManifest.xml 의 <application> 직하를 확인할 것.',
        );
      }

      for (final ref in const <String>[
        '@string/naver_client_id',
        '@string/naver_client_secret',
        '@string/naver_client_name',
      ]) {
        expect(
          countOccurrences(manifest, ref),
          1,
          reason:
              'D-01: meta-data 값은 $ref 형태의 string resource 참조여야 한다 — '
              '리터럴 키를 manifest 에 쓰지 말 것.',
        );
      }

      // clientSecret 값이 @string/ 로 시작하는지 (리터럴 secret 금지).
      final secretMatch = RegExp(
        r'android:name="com\.naver\.sdk\.clientSecret"\s*'
        r'android:value="([^"]*)"',
      ).firstMatch(manifest);
      expect(
        secretMatch,
        isNotNull,
        reason:
            'D-01: com.naver.sdk.clientSecret meta-data 의 android:value 를 '
            '찾을 수 없다 — 속성 순서가 name → value 여야 한다.',
      );
      expect(
        secretMatch!.group(1),
        startsWith('@string/'),
        reason:
            'C-04: client secret 을 manifest 에 평문으로 쓰지 않는다 — '
            'resValue 가 만든 @string/ 참조만 허용된다.',
      );

      final logMatch = RegExp(
        r'android:name="com\.naver\.sdk\.logEnabled"\s*'
        r'android:value="([^"]*)"',
      ).firstMatch(manifest);
      expect(
        logMatch,
        isNotNull,
        reason: 'D-07: com.naver.sdk.logEnabled meta-data 를 찾을 수 없다.',
      );
      expect(
        logMatch!.group(1),
        'false',
        reason:
            'D-07: SDK 로그는 비활성이어야 한다 — true 면 토큰·프로필이 '
            'logcat 으로 샌다. AndroidManifest.xml 의 logEnabled 값을 false 로.',
      );
    });

    test('T-16.2-NATIVE-04 Info.plist substitution — 변수 치환만, 평문 금지', () {
      final plist = stripXmlComments(readTracked('ios/Runner/Info.plist'));

      const expected = <String, String>{
        'NidClientID': r'$(NAVER_CLIENT_ID)',
        'NidClientSecret': r'$(NAVER_CLIENT_SECRET)',
        'NidAppName': r'$(DISPLAY_NAME)',
        'NidUrlScheme': r'$(NAVER_URL_SCHEME)',
      };

      for (final entry in expected.entries) {
        final key = entry.key;
        expect(
          countOccurrences(plist, '<key>$key</key>'),
          1,
          reason:
              'D-02: Info.plist 의 $key 키가 정확히 1건이어야 한다 — '
              '플러그인이 register(with:) 시점에 이 4키를 읽는다.',
        );
        final match = RegExp(
          '<key>$key</key>\\s*<string>([^<]*)</string>',
        ).firstMatch(plist);
        expect(
          match,
          isNotNull,
          reason: 'D-02: $key 바로 다음 <string> 값을 찾을 수 없다.',
        );
        expect(
          match!.group(1),
          entry.value,
          reason:
              'D-03: $key 값은 xcconfig 변수 치환 ${entry.value} 여야 한다. '
              '평문이 들어 있다면 플러그인 configure CLI 를 돌린 것이다 — '
              '되돌리고 변수 참조로 복원할 것 (C-04).',
        );
      }

      expect(
        countOccurrences(plist, r'$(NAVER_URL_SCHEME)'),
        2,
        reason:
            'D-02: CFBundleURLSchemes 1건 + NidUrlScheme 1건 = 2건이어야 한다. '
            '두 값이 어긋나면 플러그인의 복귀 URL 필터가 콜백을 버린다.',
      );
    });

    test('T-16.2-NATIVE-05 example xcconfig placeholder — 실 키 0', () {
      const placeholders = <String>[
        'NAVER_CLIENT_ID = your-naver-client-id-here',
        'NAVER_CLIENT_SECRET = your-naver-client-secret-here',
        'NAVER_URL_SCHEME = your-naver-url-scheme-here',
      ];

      for (final flavor in const <String>['dev', 'stg', 'prod']) {
        final path = 'ios/Flutter/$flavor.example.xcconfig';
        final source = stripSlashComments(readTracked(path));
        for (final placeholder in placeholders) {
          expect(
            countOccurrences(source, placeholder),
            1,
            reason:
                'C-04: $path 에 placeholder "$placeholder" 가 정확히 1줄 '
                '있어야 한다. tracked example 에는 실 키를 넣지 않는다 — '
                '실 키는 gitignored $flavor.xcconfig 에만 둔다.',
          );
        }
      }
    });

    test('T-16.2-NATIVE-06 example json placeholder — 콘솔 발급 3키의 기록처', () {
      const expected = <String, String>{
        'naverClientId': 'YOUR_NAVER_CLIENT_ID',
        'naverClientSecret': 'YOUR_NAVER_CLIENT_SECRET',
        'naverUrlScheme': 'your-naver-url-scheme-here',
      };

      for (final flavor in const <String>['dev', 'stg', 'prod']) {
        final path = 'config/$flavor.example.json';
        final json = jsonDecode(readTracked(path)) as Map<String, dynamic>;
        for (final entry in expected.entries) {
          expect(
            json[entry.key],
            entry.value,
            reason:
                'D-01: $path 의 ${entry.key} 는 placeholder "${entry.value}" '
                '여야 한다. 이 3키는 Android gradle 입력이자 콘솔 발급 값의 '
                '기록처이므로 제거하지 않는다 (iOS 실제 출처는 xcconfig).',
          );
        }
        expect(
          (json['appName'] as String?) ?? '',
          isNotEmpty,
          reason:
              'D-06: $path 의 appName 이 Android 동의 화면 앱 이름의 원천이다 — '
              '비어 있으면 naver_client_name resValue 가 빈 문자열이 된다.',
        );
      }
    });

    test('T-16.2-NATIVE-07 gitignore — 실 키 파일은 추적되지 않는다', () {
      final gitignore = readTracked(
        '.gitignore',
      ).split('\n').map((line) => line.trim()).toSet();

      for (final entry in const <String>[
        'ios/Flutter/dev.xcconfig',
        'ios/Flutter/stg.xcconfig',
        'ios/Flutter/prod.xcconfig',
        'config/*.json',
        '!config/*.example.json',
      ]) {
        expect(
          gitignore.contains(entry),
          isTrue,
          reason:
              'C-04: .gitignore 에 "$entry" 줄이 있어야 한다 — 이 줄이 사라지면 '
              '실 client secret 이 커밋될 수 있다.',
        );
      }
    });

    test('T-16.2-NATIVE-08 no runtime config API — 금지 호출 0건', () {
      const forbidden = <String>[
        'setLogEnabled(',
        'logOutAndDeleteToken(',
        'FlutterNaverLogin.initSdk',
      ];

      var inspected = 0;
      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File) {
          continue;
        }
        final path = entity.path;
        if (!path.endsWith('.dart') ||
            path.endsWith('.g.dart') ||
            path.endsWith('.freezed.dart')) {
          continue;
        }
        inspected++;
        final code = stripSlashComments(entity.readAsStringSync());
        for (final needle in forbidden) {
          if (code.contains(needle)) {
            offenders.add('$path → $needle');
          }
        }
      }

      expect(
        inspected,
        greaterThan(0),
        reason: 'lib/ 아래 dart 파일을 하나도 읽지 못했다 — 순회가 깨졌다.',
      );
      expect(
        offenders,
        isEmpty,
        reason:
            'D-07 · D-15: 런타임 설정 API 는 호출하지 않는다. setLogEnabled 는 '
            'manifest logEnabled(D-07)를 무력화하고, logOutAndDeleteToken 은 '
            'D-57 의 기기 내 토큰 제거 범위를 넘어 연동 자체를 해제한다. '
            'FlutterNaverLogin.initSdk 는 native 설정 주입(D-02)과 중복된다. '
            '위반: ${offenders.join(", ")}',
      );
    });
  });
}
