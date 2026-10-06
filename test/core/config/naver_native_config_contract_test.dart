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
//
// **유일한 예외 — `T-16.5-NATIVE-01`:** Phase 16.5 부터 `naverClientId` 가 Dart
// (dart-define) 와 iOS(xcconfig) 두 곳에서 읽히므로 두 gitignored 실 키 파일의
// 값 일치를 비교한다. 두 파일이 모두 있을 때만 비교하고(없으면 skip), 값은 실패
// 메시지에도 싣지 않는다 — bool 비교 결과만 단언한다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/features/auth/data/naver_host_channel.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_web_auth_client.dart';

import '../../helpers/source_text.dart';

void main() {
  group('Naver 시크릿 주입 배선 계약 (Phase 16.2)', () {
    // Phase 16.3 D-01 의 `enable-swift-package-manager` 키 부재 단언은 이 test 에
    // 얹혀 있었다(코드 리뷰 IN-03). SPM 회귀로 red 가 났을 때 Naver 파일을
    // 뒤지게 되는 오도를 없애려고 `test/ios/spm_policy_test.dart` 의
    // `T-16.3-SPM-04` 로 옮겼다 — 단언 자체는 그대로 살아 있다.
    test('T-16.2-NATIVE-01 pubspec pin — naver_login_flutter 정확 고정', () {
      final pubspec = stripHashComments(readTrackedFile('pubspec.yaml'));

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
          readTrackedFile('android/app/build.gradle.kts'),
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
        // Phase 16.5 D-09: 콜백 scheme(`naverWebCallbackScheme`) 은 secret 이
        // 아니고 intent-filter 가 리터럴로 요구하므로 placeholder 가 정답이다.
        // 금지 대상은 client 자격 값(`naverClient*`) 으로 좁힌다.
        expect(
          countOccurrences(gradle, 'manifestPlaceholders["naverClient'),
          0,
          reason:
              'D-01: Naver 키는 resValue + @string 참조로만 주입한다 — '
              'manifestPlaceholders 경로는 금지다 (평문이 manifest 에 박힌다).',
        );
        expect(
          countOccurrences(gradle, 'manifestPlaceholders["naver'),
          1,
          reason:
              'Phase 16.5 D-09: Naver placeholder 는 웹 콜백 scheme 1건뿐이어야 '
              '한다 — 그 밖의 Naver 값을 placeholder 로 옮기지 말 것.',
        );
      },
    );

    test('T-16.2-NATIVE-03 manifest meta-data — @string 참조 + 로그 비활성', () {
      final manifest = stripXmlComments(
        readTrackedFile('android/app/src/main/AndroidManifest.xml'),
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
      final plist = stripXmlComments(readTrackedFile('ios/Runner/Info.plist'));

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
        final source = stripSlashComments(readTrackedFile(path));
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
        final json = jsonDecode(readTrackedFile(path)) as Map<String, dynamic>;
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
      final gitignore = readTrackedFile(
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

  group('Phase 16.5 웹 경로 계약 (T-16.5-NATIVE)', () {
    // 16.5 review IN-05 — 패키지 경로를 리터럴로 두면 `bin/rename.dart` 가
    // Kotlin 디렉터리를 옮긴 뒤 readTrackedFile 이 파일을 못 찾아 깨진다.
    // MainActivity.kt 위치에서 파생한다 (lazy — 실패는 test 안에서 보고).
    // G-16.5-2 — Custom Tab fallback 콜백은 킷 소유 relay(WebAuthCallbackActivity)
    // 가 받아 MainActivity 기존 task 로 복귀시킨다. manifest · Kotlin 두 계약이 잠근다.
    late final String kotlinDir = _findKotlinPackageDir();

    test('T-16.5-NATIVE-01 client_id · scheme — config json ↔ xcconfig 일치', () {
      // tracked example 은 항상 검사한다 — placeholder 가 비어 있지 않은지만.
      final exampleJson =
          jsonDecode(readTrackedFile('config/dev.example.json'))
              as Map<String, dynamic>;
      expect(
        (exampleJson['naverClientId'] as String?) ?? '',
        isNotEmpty,
        reason:
            'G-4: config/dev.example.json 의 naverClientId placeholder 가 '
            '비어 있다 — 채택자가 채울 자리를 지우지 말 것.',
      );
      final exampleXcconfig = stripSlashComments(
        readTrackedFile('ios/Flutter/dev.example.xcconfig'),
      );
      expect(
        _readXcconfigValue(exampleXcconfig, 'NAVER_CLIENT_ID'),
        isNotEmpty,
        reason:
            'G-4: ios/Flutter/dev.example.xcconfig 의 NAVER_CLIENT_ID '
            'placeholder 가 비어 있다.',
      );

      // 실 키 파일(gitignored) 은 둘 다 있을 때만 값을 비교한다.
      final jsonFile = File('config/dev.json');
      final xcconfigFile = File('ios/Flutter/dev.xcconfig');
      if (!jsonFile.existsSync() || !xcconfigFile.existsSync()) {
        markTestSkipped(
          'gitignored 실 키 파일 부재 — config/dev.json · '
          'ios/Flutter/dev.xcconfig 가 모두 있어야 값을 비교한다. '
          'fresh clone / CI 에서는 정상.',
        );
        return;
      }
      final json =
          jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
      final xcconfig = stripSlashComments(xcconfigFile.readAsStringSync());

      // 값은 실패 메시지에 싣지 않는다 — 비교 결과 bool 만 단언한다.
      final jsonClientId = (json['naverClientId'] as String?) ?? '';
      final xcClientId = _readXcconfigValue(xcconfig, 'NAVER_CLIENT_ID');
      expect(
        jsonClientId.isNotEmpty,
        isTrue,
        reason: 'G-4: config/dev.json 의 naverClientId 가 비어 있다.',
      );
      expect(
        jsonClientId == xcClientId,
        isTrue,
        reason:
            'G-4: config/dev.json naverClientId 와 ios/Flutter/dev.xcconfig '
            'NAVER_CLIENT_ID 가 다르다 — Dart 웹 경로(dart-define) 와 iOS SDK '
            '1-tap 경로(xcconfig) 가 서로 다른 앱으로 인증하게 된다.',
      );

      final jsonScheme = (json['naverUrlScheme'] as String?) ?? '';
      final xcScheme = _readXcconfigValue(xcconfig, 'NAVER_URL_SCHEME');
      expect(
        jsonScheme == xcScheme,
        isTrue,
        reason:
            'probe ③: config/dev.json naverUrlScheme 과 ios/Flutter/dev.xcconfig '
            'NAVER_URL_SCHEME 이 다르다 — 웹 콜백 scheme 과 iOS URL Scheme 이 '
            '어긋난다.',
      );
      expect(
        kNaverWebCallbackSchemePattern.hasMatch(jsonScheme),
        isTrue,
        reason:
            'D-09: config/dev.json naverUrlScheme 이 RFC 3986 소문자 scheme '
            '형태가 아니다 — Android intent-filter 가 콜백을 받지 못한다.',
      );
    });

    test('T-16.5-NATIVE-02 호스트 채널 — Kotlin CHANNEL == Dart 상수', () {
      final kotlin = stripBlockComments(
        stripSlashComments(readTrackedFile('$kotlinDir/NaverHostChannel.kt')),
      );

      final match = RegExp(r'const val CHANNEL = "([^"]+)"').firstMatch(kotlin);
      expect(
        match,
        isNotNull,
        reason: 'D-23: NaverHostChannel.kt 에서 CHANNEL 상수를 찾을 수 없다.',
      );
      expect(
        match!.group(1),
        kNaverHostChannelName,
        reason:
            'D-23: Kotlin CHANNEL 과 Dart kNaverHostChannelName 이 다르면 '
            '설치 판정이 MissingPluginException → 항상 false(웹) 로 조용히 접힌다.',
      );
      expect(
        countOccurrences(kotlin, '"$kNaverHostMethodIsInstalled"'),
        1,
        reason:
            'D-23: Kotlin when 분기의 메서드 이름이 Dart '
            'kNaverHostMethodIsInstalled 와 같은 문자열 1건이어야 한다.',
      );
      expect(
        countOccurrences(kotlin, 'NidApplicationUtil.isExistNaverApp('),
        1,
        reason:
            'D-03: 판정은 SDK 자신의 기준(NidApplicationUtil) 에 위임한다 — '
            '킷 자체 패키지 조회로 바꾸지 말 것.',
      );
      expect(
        countOccurrences(kotlin, 'catch (t: Throwable)'),
        1,
        reason:
            'IN-03: compileOnly SDK 의 런타임 버전 불일치(NoClassDefFoundError · '
            'NoSuchMethodError) 는 Error 라 MethodChannel 이 잡지 않는다 — '
            '판정 호출을 Throwable catch 로 감싸 false(웹 경로) 로 접을 것.',
      );

      final dart = stripSlashComments(
        readTrackedFile('lib/features/auth/data/naver_host_channel.dart'),
      );
      expect(
        countOccurrences(dart, "'$kNaverHostChannelName'"),
        1,
        reason: 'D-23: Dart 쪽 채널 이름 리터럴이 정확히 1건이어야 한다.',
      );
      expect(
        countOccurrences(dart, "'$kNaverHostMethodIsInstalled'"),
        1,
        reason: 'D-23: Dart 쪽 메서드 이름 리터럴이 정확히 1건이어야 한다.',
      );
    });

    test('T-16.5-NATIVE-03 MainActivity — 채널 등록 1 · 해제 1', () {
      final kotlin = stripBlockComments(
        stripSlashComments(readTrackedFile('$kotlinDir/MainActivity.kt')),
      );

      expect(
        countOccurrences(
          kotlin,
          'class MainActivity : FlutterFragmentActivity()',
        ),
        1,
        reason:
            'Phase 13 Pitfall 10: MainActivity 는 FlutterFragmentActivity 를 '
            '유지해야 한다 (Naver SDK Fragment BottomSheet).',
      );
      expect(
        countOccurrences(
          kotlin,
          '.attach(flutterEngine.dartExecutor.binaryMessenger)',
        ),
        1,
        reason: 'D-23: configureFlutterEngine 에서 호스트 채널 등록 1건.',
      );
      expect(
        countOccurrences(kotlin, '.detach()'),
        1,
        reason:
            'D-23 · 16.4 IN-04: cleanUpFlutterEngine 에서 호스트 채널 해제 1건 — '
            '엔진 해제 뒤 핸들러가 남지 않게 한다.',
      );
    });

    test('T-16.5-NATIVE-04 manifest — 킷 콜백 relay intent-filter (G-16.5-2)', () {
      final manifest = stripXmlComments(
        readTrackedFile('android/app/src/main/AndroidManifest.xml'),
      );

      // 양성 대조군 — 같은 정규식 방식이 Kakao 블록을 잡는다.
      expect(
        RegExp(
          r'<activity\s+android:name="com\.kakao\.sdk\.flutter\.auth\.'
          r'AuthCodeHandlerActivity"',
        ).hasMatch(manifest),
        isTrue,
        reason: '양성 대조군: Kakao 콜백 Activity 선언을 정규식이 잡지 못한다.',
      );

      final relayBlock = RegExp(
        r'<activity\s+'
        r'android:name="\.WebAuthCallbackActivity"\s+'
        r'android:exported="true"\s+'
        r'android:taskAffinity=""\s*>\s*'
        r'<intent-filter\s*>\s*'
        r'<action\s+android:name="android\.intent\.action\.VIEW"\s*/>\s*'
        r'<category\s+android:name="android\.intent\.category\.DEFAULT"\s*/>\s*'
        r'<category\s+android:name="android\.intent\.category\.BROWSABLE"\s*/>\s*'
        r'<data\s+android:scheme="\$\{naverWebCallbackScheme\}"\s*/>\s*'
        r'</intent-filter>\s*</activity>',
      );
      expect(
        relayBlock.allMatches(manifest).length,
        1,
        reason:
            'G-16.5-2 · D-09: 킷 relay 블록(상대 이름 · exported · 빈 '
            'taskAffinity · placeholder scheme intent-filter)이 정확히 1건이어야 '
            '한다. 상대 이름이어야 bin/rename.dart 의 패키지 이동을 따라간다. '
            'intent-filter 에 label 을 두지 않는다(review 2회차 IN-02) — filter '
            '라벨이 앱 라벨보다 우선해 scheme 충돌 chooser 에 앱 이름 대신 '
            '라이브러리 이름이 보인다.',
      );

      // 부재 단언의 양성 대조 — 같은 문자열 계수 방식이 실제로 매칭한다.
      expect(
        countOccurrences(manifest, 'com.naver.sdk.clientId'),
        1,
        reason: '양성 대조군: countOccurrences 가 Naver meta-data 를 세지 못한다.',
      );
      expect(
        countOccurrences(
          manifest,
          'com.linusu.flutter_web_auth_2.CallbackActivity',
        ),
        0,
        reason:
            'G-16.5-2: 라이브러리 콜백 Activity 를 함께 선언하면 같은 scheme '
            '수신자가 2개가 되어 chooser 가 뜨거나 콜백을 엉뚱한 쪽이 받는다 — '
            '콜백 수신자는 킷 relay 하나뿐이어야 한다.',
      );
      expect(
        countOccurrences(
          manifest,
          'com.linusu.flutter_web_auth_2.AuthenticationManagementActivity',
        ),
        0,
        reason:
            'G-16.5-2 · D-07: 라이브러리 인증 관리 Activity 를 app manifest 에서 '
            '재선언 · launchMode override 하면 Chrome Auth Tab 경로의 task '
            '배치까지 바뀐다.',
      );

      final mainBlock = RegExp(
        r'<activity\s+'
        r'android:name="\.MainActivity"\s+'
        r'android:exported="true"\s+'
        r'android:launchMode="singleTop"\s+'
        r'android:taskAffinity=""',
      );
      expect(
        mainBlock.allMatches(manifest).length,
        1,
        reason:
            'G-16.5-2: MainActivity 는 launchMode singleTop 이어야 한다 — 없으면 '
            'relay 의 (대기 호출 전달 시) CLEAR_TOP 이 MainActivity 를 재생성해 '
            'Flutter 엔진과 대기 '
            '중인 로그인이 사라진다. 빈 taskAffinity 는 StrandHogg(task '
            'hijacking) 방어라 유지한다 (minSdk 24).',
      );
      expect(
        countOccurrences(manifest, 'com.nhn.android.search'),
        0,
        reason:
            'Phase 16.2 D-07: NAVER 앱 패키지 가시성은 SDK AAR 이 병합한다 — '
            'queries 에 중복 선언하지 말 것.',
      );
    });

    test(
      'T-16.5-NATIVE-09 relay Kotlin — success 전달 → MainActivity task 복귀 (G-16.5-2)',
      () {
        final kotlin = stripBlockComments(
          stripSlashComments(
            readTrackedFile('$kotlinDir/WebAuthCallbackActivity.kt'),
          ),
        );

        const Map<String, String> exactlyOnce = <String, String>{
          'class WebAuthCallbackActivity : Activity()':
              'relay 는 플랫폼 Activity 하나로 선언한다.',
          'FlutterWebAuth2Plugin.callbacks.remove(':
              'upstream 콜백 Activity 와 같은 전달 경로 — 대기 호출을 map 에서 꺼낸다.',
          '.success(': '콜백 URL 을 대기 호출에 success 로 1회만 넘긴다.',
          'Intent.FLAG_ACTIVITY_NEW_TASK':
              'NEW_TASK 가 없으면 task 검색이 꺼져 main task 로 돌아가지 못한다.',
          'Intent.FLAG_ACTIVITY_CLEAR_TOP':
              'CLEAR_TOP 이 없으면 대기 호출 전달 뒤 MainActivity 위의 인증 관리 '
              'Activity · 브라우저 tab 이 남는다 (전달 시에만 조건부로 1건).',
          'Intent.FLAG_ACTIVITY_SINGLE_TOP':
              'SINGLE_TOP 이 없으면 MainActivity 가 재생성돼 Flutter 엔진이 사라진다.',
          'MainActivity::class.java': '복귀 대상은 킷 MainActivity 하나다.',
          'startActivity(': 'MainActivity 전면 복귀 기동은 1회다.',
          'finish()': 'relay 자신은 task 에 남지 않는다.',
        };
        exactlyOnce.forEach((String token, String why) {
          expect(
            countOccurrences(kotlin, token),
            1,
            reason: 'G-16.5-2: 주석 제외 relay 소스에 "$token" 이 정확히 1건 — $why',
          );
        });

        expect(
          countOccurrences(kotlin, 'AuthenticationManagementActivity'),
          0,
          reason:
              'G-16.5-2: relay 는 라이브러리 인증 관리 Activity 를 직접 띄우지 '
              '않는다 — 그 같은 task 전용 재기동이 이 gap 의 원인이다.',
        );
        for (final String logCall in <String>['Log.', 'println']) {
          expect(
            countOccurrences(kotlin, logCall),
            0,
            reason:
                'C-01 · WR-05: relay 에 로그 호출("$logCall")을 두지 않는다 — '
                '콜백 URL 에 code · state 가 실린다.',
          );
        }

        // 16.5 review 2회차 IN-01 — CLEAR_TOP 은 대기 호출을 실제로 전달했을 때만.
        // 외부 기동(대기 호출 없음)은 MainActivity 위 Activity 를 걷지 않는다.
        expect(
          RegExp(
            r'val delivered\s*=\s*scheme != null &&\s*'
            r'FlutterWebAuth2Plugin\.callbacks\.remove\(scheme\)\?\.let\s*\{'
            r'[^{}]*\}\s*==\s*true',
          ).allMatches(kotlin).length,
          1,
          reason:
              'IN-01: delivered 는 callbacks.remove 결과(대기 호출 존재)에서 '
              '파생해야 한다 — scheme 존재만으로 참이 되면 외부 intent 가 다시 '
              'CLEAR_TOP 을 건다.',
        );
        expect(
          RegExp(
            r'Intent\.FLAG_ACTIVITY_NEW_TASK\s+or\s+'
            r'Intent\.FLAG_ACTIVITY_SINGLE_TOP\s+or\s+'
            r'\(if \(delivered\) Intent\.FLAG_ACTIVITY_CLEAR_TOP else 0\)',
          ).allMatches(kotlin).length,
          1,
          reason:
              'IN-01: NEW_TASK|SINGLE_TOP(0x30000000)은 항상, CLEAR_TOP 은 '
              'delivered 일 때만(0x34000000) — 무조건 CLEAR_TOP 은 외부 intent '
              '하나로 Kakao · Firebase IdP · NAVER 1-tap bridge 등 MainActivity '
              '위 Activity 를 걷는 표면이다.',
        );

        // 16.5 review 2회차 IN-03 — 실제 불변식: 대기 호출을 map 에서 동기로
        // 꺼내는 것과 success 가 한 식(main thread 같은 구간)에 있다.
        expect(
          RegExp(
            r'FlutterWebAuth2Plugin\.callbacks\.remove\(scheme\)\?\.let\s*'
            r'\{\s*pending\s*->\s*pending\.success\(url\.toString\(\)\)',
          ).allMatches(kotlin).length,
          1,
          reason:
              'G-16.5-2 · IN-03 계약: 대기 호출은 main thread 에서 동기로 map 에서 '
              '꺼낸 뒤(callbacks.remove) 같은 식에서 success 한다 — 이후 '
              'MainActivity resume 이 부르는 cleanUpDanglingCalls(남은 호출을 '
              'CANCELED 로 접음) · 늦은 handleAuthResult 가 빈 map 을 보게 하는 '
              '것이 보호 장치다.',
        );

        final int removeAt = kotlin.indexOf(
          'FlutterWebAuth2Plugin.callbacks.remove(',
        );
        final int startAt = kotlin.indexOf('startActivity(');
        expect(
          removeAt >= 0 && startAt >= 0 && removeAt < startAt,
          isTrue,
          reason:
              'G-16.5-2 가독성 규칙: 전달(remove · success)을 MainActivity 전면 '
              '복귀 기동보다 소스상 먼저 둔다. startActivity 는 비동기 IPC 라 '
              'MainActivity resume 은 relay onCreate 반환 뒤에야 돌므로 보호 '
              '장치는 위 한 식 remove 이고, 이 순서는 읽는 순서를 실행 의미와 '
              '맞추려는 규칙이다 (remove=$removeAt · startActivity=$startAt).',
        );
      },
    );

    test('T-16.5-NATIVE-05 gradle placeholder — Dart 와 같은 config 키', () {
      final gradle = stripSlashComments(
        readTrackedFile('android/app/build.gradle.kts'),
      );
      expect(
        countOccurrences(gradle, 'dartDefines["naverUrlScheme"]'),
        1,
        reason:
            'probe ③ A: gradle 은 config json 의 naverUrlScheme 을 정확히 '
            '1곳에서 읽어야 한다.',
      );
      // gradle 포맷이 줄바꿈 위치를 바꿀 수 있어 공백 무관 정규식으로 센다.
      expect(
        RegExp(
          r'manifestPlaceholders\["naverWebCallbackScheme"\]\s*=\s*'
          r'if\s*\(naverUrlScheme\.isEmpty\(\)\)\s*"unset\.naver\.web"\s*'
          r'else\s+naverUrlScheme\b',
        ).allMatches(gradle).length,
        1,
        reason:
            'probe ③ A: gradle placeholder 는 config json 의 naverUrlScheme 을 '
            '그대로 공급해야 한다. 키가 비면 gradle 만 자리표시 scheme 을 쓴다 — '
            'Naver 를 켜면 둘 다 같은 키 값이다 (Phase 17.3 D-04).',
      );

      final appConfig = stripSlashComments(
        readTrackedFile('lib/core/config/app_config.dart'),
      );
      // dart format 이 인자를 줄바꿈할 수 있어 공백 무관 정규식으로 센다.
      expect(
        RegExp(
          r'naverWebCallbackScheme\s*=\s*String\.fromEnvironment\(\s*'
          r"'naverUrlScheme',?\s*\)",
        ).allMatches(appConfig).length,
        1,
        reason:
            'probe ③ A: Dart AppConfig.naverWebCallbackScheme 도 같은 '
            'naverUrlScheme 키를 읽어야 한다 — 둘이 어긋나면 콜백 map 키가 '
            '달라 세션이 끝나지 않는다.',
      );
    });

    test('T-16.5-NATIVE-07 SDK compileOnly — 플러그인과 같은 좌표 · 버전', () {
      final gradle = stripSlashComments(
        readTrackedFile('android/app/build.gradle.kts'),
      );
      final sdkPattern = RegExp(r'"com\.navercorp\.nid:oauth:([^"]+)"');

      final appMatches = RegExp(
        r'compileOnly\("com\.navercorp\.nid:oauth:([^"]+)"\)',
      ).allMatches(gradle).toList();
      expect(
        appMatches.length,
        1,
        reason:
            'D-23: 앱 gradle 에 NAVER SDK compileOnly 선언이 정확히 1건이어야 '
            '한다 — 없으면 NaverHostChannel.kt 가 컴파일되지 않는다.',
      );
      expect(
        RegExp(r'implementation\("com\.navercorp\.nid:oauth:').hasMatch(gradle),
        isFalse,
        reason:
            'D-23: 앱은 SDK 를 implementation 으로 선언하지 않는다 — 런타임 '
            'AAR 은 플러그인이 공급한다 (버전 이중 관리 금지).',
      );

      // 플러그인이 선언한 SDK 버전 — pub 이 해석한 패키지 루트에서 읽는다.
      final packageConfig =
          jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
              as Map<String, dynamic>;
      final packages = (packageConfig['packages'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final plugin = packages.firstWhere(
        (p) => p['name'] == 'naver_login_flutter',
        orElse: () => <String, dynamic>{},
      );
      expect(
        plugin,
        isNotEmpty,
        reason: 'package_config.json 에서 naver_login_flutter 를 찾을 수 없다.',
      );
      // rootUri 는 끝 `/` 가 없다 — 붙이지 않으면 resolve 가 마지막 segment
      // (패키지 디렉토리)를 대체한다.
      final rawRoot = plugin['rootUri'] as String;
      final rootUri = Uri.parse(rawRoot.endsWith('/') ? rawRoot : '$rawRoot/');
      final root = rootUri.isAbsolute
          ? rootUri
          : Directory('.dart_tool').absolute.uri.resolveUri(rootUri);
      final pluginGradle = File.fromUri(root.resolve('android/build.gradle'));
      expect(
        pluginGradle.existsSync(),
        isTrue,
        reason: '플러그인 android/build.gradle 을 찾을 수 없다: ${root.path}',
      );
      final pluginMatch = sdkPattern.firstMatch(
        pluginGradle.readAsStringSync(),
      );
      expect(
        pluginMatch,
        isNotNull,
        reason: '플러그인 gradle 에서 NAVER SDK 좌표를 찾을 수 없다.',
      );
      expect(
        appMatches.single.group(1),
        pluginMatch!.group(1),
        reason:
            'D-23: 앱의 compileOnly SDK 버전이 naver_login_flutter 가 링크하는 '
            '버전과 다르다 — 앱 gradle 의 compileOnly 줄을 플러그인 버전으로 '
            '갱신할 것.',
      );
    });

    test('T-16.5-NATIVE-08 iOS 호스트 채널 — Swift channelName == Dart 상수', () {
      // plan 05 가 계획한 마커는 `T-16.5-NATIVE-05` 였으나 plan 04 가 05~07 을
      // Android 계약에 이미 썼으므로 08 로 잇는다.
      final swift = stripBlockComments(
        stripSlashComments(
          readTrackedFile('ios/Runner/NaverHostChannel.swift'),
        ),
      );

      final match = RegExp(
        r'static let channelName = "([^"]+)"',
      ).firstMatch(swift);
      expect(
        match,
        isNotNull,
        reason: 'D-22: NaverHostChannel.swift 에서 channelName 상수를 찾을 수 없다.',
      );
      expect(
        match!.group(1),
        kNaverHostChannelName,
        reason:
            'D-01 · D-22: Swift channelName 과 Dart kNaverHostChannelName 이 '
            '다르면 iOS 설치 판정이 MissingPluginException → 항상 false(웹) 로 '
            '조용히 접힌다.',
      );
      expect(
        countOccurrences(swift, '"$kNaverHostMethodIsInstalled"'),
        1,
        reason:
            'D-03: Swift switch 분기의 메서드 이름이 Dart '
            'kNaverHostMethodIsInstalled 와 같은 문자열 1건이어야 한다.',
      );
      expect(
        countOccurrences(swift, 'naversearchthirdlogin://'),
        1,
        reason:
            'D-03: 판정은 NAVER iOS SDK 와 같은 scheme(naversearchthirdlogin) '
            '의 canOpenURL 1건이어야 한다.',
      );
      expect(
        countOccurrences(swift, 'import NidCore'),
        0,
        reason: 'D-22: 호스트 채널은 NAVER SDK 모듈을 import 하지 않는다.',
      );

      final appDelegate = stripSlashComments(
        readTrackedFile('ios/Runner/AppDelegate.swift'),
      );
      // 양성 대조군 — 같은 계수 방식이 기존 registrant 줄을 잡는다.
      expect(
        countOccurrences(
          appDelegate,
          'GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)',
        ),
        1,
        reason: '양성 대조군: AppDelegate 의 GeneratedPluginRegistrant 등록 줄.',
      );
      expect(
        countOccurrences(
          appDelegate,
          'NaverHostChannel.register(with: engineBridge.pluginRegistry)',
        ),
        1,
        reason: 'D-22: AppDelegate 에 iOS 호스트 채널 등록 1줄.',
      );

      // 등장 횟수가 아니라 **줄 수**를 센다 — PBXBuildFile · PBXFileReference
      // 줄은 한 줄에 파일명이 두 번 나온다.
      final pbxprojLines = readTrackedFile(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).split('\n');
      expect(
        pbxprojLines.where((l) => l.contains('AppDelegate.swift')).length,
        4,
        reason: '양성 대조군: AppDelegate.swift 의 pbxproj 등록 4줄.',
      );
      expect(
        pbxprojLines.where((l) => l.contains('NaverHostChannel.swift')).length,
        4,
        reason:
            'P-03: NaverHostChannel.swift 는 pbxproj 에 4항목(PBXBuildFile · '
            'PBXFileReference · Runner group · Sources phase) 으로 등록돼야 '
            '컴파일된다.',
      );
    });

    test('T-16.5-NATIVE-06 scheme 패턴 — RFC 3986 소문자', () {
      // 양성 대조군 먼저.
      for (final valid in const <String>[
        'com.slimpumpkin.flutterstarterkit',
        'probe-scheme',
      ]) {
        expect(
          kNaverWebCallbackSchemePattern.hasMatch(valid),
          isTrue,
          reason: 'D-09: "$valid" 는 유효한 콜백 scheme 이다.',
        );
      }
      for (final invalid in const <String>['Foo_bar', '1abc', '']) {
        expect(
          kNaverWebCallbackSchemePattern.hasMatch(invalid),
          isFalse,
          reason:
              'D-09 · Pitfall 2: "$invalid" 는 RFC 3986 소문자 scheme 이 아니다 '
              '— authenticate 가 ArgumentError 를 던지기 전에 막아야 한다.',
        );
      }
    });
  });
  group('Phase 16.11 관측 계약 (T-16.11-NATIVE)', () {
    /// URL 내용 접근 토큰 — 평시 · UAT 임시 계측 중 모두 항상 0 (C-06).
    const urlContentTokens = <String>[
      'absoluteString',
      '.query',
      '.host',
      '.path',
      '.description',
    ];

    /// 출력 · 보간 토큰 — 평시 0. `\(` 는 Swift 문자열 보간이다.
    const outputTokens = <String>['print(', 'NSLog(', 'os_log', r'\('];

    /// 계수 방식이 두 묶음의 토큰을 실제로 세는지 먼저 확인한다 (공허 단언 방지).
    void expectTokenCounterWorks() {
      expect(
        countOccurrences(r'print("a=\(x)")', r'\('),
        1,
        reason: '양성 대조군: r"\\(" 가 Swift 보간 1건을 세지 못한다.',
      );
      const sample =
          r'NSLog("\(u.path)"); os_log("x"); '
          'print(u.absoluteString, u.query, u.host, u.description)';
      for (final token in <String>[...urlContentTokens, ...outputTokens]) {
        expect(
          countOccurrences(sample, token),
          greaterThanOrEqualTo(1),
          reason: '양성 대조군: 합성 문자열에서 $token 을 세지 못한다.',
        );
      }
      expect(
        countOccurrences(
          stripSlashComments('  // NSLog("\\(url.path)")\nlet a = 1'),
          r'\(',
        ),
        0,
        reason: '주석 줄의 토큰 언급은 stripSlashComments 가 걷어낸다.',
      );
    }

    /// [source]([file]) 의 금지 토큰을 두 묶음으로 단언한다 (C-06 · IN-02).
    void expectNoForbiddenSwiftTokens(String source, String file) {
      for (final token in urlContentTokens) {
        expect(
          countOccurrences(source, token),
          0,
          reason:
              'C-06: $file 은 URL scheme 외의 내용을 읽지 않는다 ($token). '
              'URL 내용 접근 묶음 — UAT 임시 계측 중에도 조정 대상 아님.',
        );
      }
      for (final token in outputTokens) {
        expect(
          countOccurrences(source, token),
          0,
          reason:
              'C-06 · Pitfall 7: $file 에 출력 · 보간을 두지 않는다 ($token). '
              '출력 · 보간 묶음 — plan 16.11-04 UAT 임시 계측이 UAT1611 줄에 '
              '한해 임시 조정하는 대상 (URL 내용 접근 묶음은 조정 대상 아님).',
        );
      }
    }

    test('T-16.11-NATIVE-01 SceneDelegate — 기록 뒤 분배 override 1개', () {
      final scene = stripBlockComments(
        stripSlashComments(readTrackedFile('ios/Runner/SceneDelegate.swift')),
      );

      final overrideMatches = RegExp(
        r'override\s+func\s+scene\(\s*_\s+scene:\s*UIScene,\s*'
        r'openURLContexts\s+URLContexts:\s*Set<UIOpenURLContext>\s*\)',
      ).allMatches(scene);
      expect(
        overrideMatches.length,
        1,
        reason: 'D-04: scene(_:openURLContexts:) override 가 정확히 1개여야 한다.',
      );

      const record = 'NaverHostChannel.recordIfNaverCallback(URLContexts)';
      const dispatch = 'super.scene(scene, openURLContexts: URLContexts)';
      expect(
        countOccurrences(scene, record),
        1,
        reason: 'D-04 · D-05: override 안에서 Naver 콜백 도착 기록 호출 1건.',
      );
      expect(
        countOccurrences(scene, dispatch),
        1,
        reason: 'D-04 · A6: 플러그인 분배(super) 호출 1건 — 분배를 빼면 로그인 불가.',
      );
      expect(
        scene.indexOf(record) < scene.indexOf(dispatch),
        isTrue,
        reason:
            'D-04: 기록이 분배보다 앞이어야 한다 — naver 플러그인이 true 를 '
            '반환하면 분배 뒤에서는 URL 을 볼 수 없다.',
      );
      expect(
        countOccurrences(scene, 'func '),
        1,
        reason: 'D-04: SceneDelegate 에는 관측 override 1개 외의 함수를 두지 않는다.',
      );
      expectTokenCounterWorks();
      expectNoForbiddenSwiftTokens(scene, 'SceneDelegate.swift');
    });

    test('T-16.11-NATIVE-02 NaverHostChannel.swift — 분기 2 · Bool 기록만', () {
      final swift = stripBlockComments(
        stripSlashComments(
          readTrackedFile('ios/Runner/NaverHostChannel.swift'),
        ),
      );

      expect(
        countOccurrences(swift, '"$kNaverHostMethodHasCallbackArrived"'),
        1,
        reason:
            'D-05: Swift switch 분기의 조회 메서드 이름이 Dart '
            'kNaverHostMethodHasCallbackArrived 와 같은 문자열 1건이어야 한다.',
      );
      expect(
        countOccurrences(swift, '"$kNaverHostMethodResetCallbackRecord"'),
        1,
        reason:
            'D-05: Swift switch 분기의 초기화 메서드 이름이 Dart '
            'kNaverHostMethodResetCallbackRecord 와 같은 문자열 1건이어야 한다.',
      );
      expect(
        countOccurrences(swift, 'NidUrlScheme'),
        1,
        reason: 'D-05: Naver 판별은 플러그인과 같은 Info.plist NidUrlScheme 1곳.',
      );
      expect(
        RegExp(
          r'static\s+func\s+recordIfNaverCallback\(',
        ).allMatches(swift).length,
        1,
        reason: 'D-05: 기록 함수 선언 1건.',
      );
      expectTokenCounterWorks();
      expectNoForbiddenSwiftTokens(swift, 'NaverHostChannel.swift');
    });

    test('T-16.11-NATIVE-03 Android 호스트 — 새 메서드 0 (D-03)', () {
      final kotlin = stripBlockComments(
        stripSlashComments(
          readTrackedFile('${_findKotlinPackageDir()}/NaverHostChannel.kt'),
        ),
      );

      // 양성 대조군 — 같은 계수 방식이 기존 설치 판정 분기를 잡는다.
      expect(
        countOccurrences(kotlin, '"$kNaverHostMethodIsInstalled"'),
        1,
        reason: '양성 대조군: Kotlin when 분기의 설치 판정 메서드 이름.',
      );
      for (final method in const <String>[
        kNaverHostMethodHasCallbackArrived,
        kNaverHostMethodResetCallbackRecord,
      ]) {
        expect(
          countOccurrences(kotlin, method),
          0,
          reason:
              'D-03 · D-05: Android 는 콜백 도착 기록 · 판정을 하지 않는다 '
              '($method).',
        );
      }
    });

    test('T-16.11-NATIVE-04 pbxproj — 새 Swift 파일 0', () {
      // 등장 횟수가 아니라 **줄 수**를 센다 (T-16.5-NATIVE-08 과 같은 방식).
      final pbxprojLines = readTrackedFile(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).split('\n');
      expect(
        pbxprojLines.where((l) => l.contains('AppDelegate.swift')).length,
        4,
        reason: '양성 대조군: AppDelegate.swift 의 pbxproj 등록 4줄.',
      );
      expect(
        pbxprojLines.where((l) => l.contains('SceneDelegate.swift')).length,
        4,
        reason: 'D-04: 관측은 기존 SceneDelegate.swift 안에서 한다 (등록 4줄 불변).',
      );
      expect(
        pbxprojLines.where((l) => l.contains('NaverHostChannel.swift')).length,
        4,
        reason: 'D-05: 기록 · 조회는 기존 NaverHostChannel.swift 확장이다 (4줄 불변).',
      );
    });

    test('T-16.11-NATIVE-05 NaverSdkClient — 0.3초 값 · production 판정 배선', () {
      final code = stripSlashComments(
        readTrackedFile('lib/features/auth/data/naver_sdk_client.dart'),
      );

      final contracts = <String, String>{
        r'kNaverResumeSettleDelay\s*=\s*Duration\(\s*milliseconds:\s*300\s*,?\s*\)':
            'D-02: 판정 보류는 LINE SDK verbatim 0.3초 — 상향은 U1 실측 근거로만.',
        r'_subscribeLifecycle\s*=\s*subscribeNaverAppLifecycle':
            'D-03: production ctor 가 실제 lifecycle 구독 함수를 주입한다.',
        r'_hasCallbackArrived\s*=\s*const\s+NaverHostChannel\(\)\.hasNaverCallbackArrived':
            'D-03 · D-05: production ctor 가 네이티브 기록 조회를 주입한다.',
        r'_resetCallbackRecord\s*=\s*const\s+NaverHostChannel\(\)\.resetNaverCallbackRecord':
            'D-03 · D-05: production ctor 가 네이티브 기록 초기화를 주입한다.',
        r'AppLifecycleListener\(':
            'D-03: 구독 수단은 AppLifecycleListener 1곳 (RESEARCH OQ6).',
      };
      for (final entry in contracts.entries) {
        expect(
          RegExp(entry.key).allMatches(code).length,
          1,
          reason: entry.value,
        );
      }
    });
  });
}

/// `android/app/src/main/kotlin` 아래 `MainActivity.kt` 가 있는 패키지
/// 디렉터리를 돌려준다 (16.5 review IN-05).
///
/// `bin/rename.dart` 는 패키지 디렉터리의 모든 `.kt` 를 함께 옮기므로
/// `NaverHostChannel.kt` 도 이 디렉터리에 있다. `MainActivity.kt` 가 0개 또는
/// 2개 이상이면 어느 패키지를 볼지 모호하므로 테스트를 실패시킨다.
String _findKotlinPackageDir() {
  const String kotlinBase = 'android/app/src/main/kotlin';
  final Directory base = Directory(kotlinBase);
  if (!base.existsSync()) {
    fail('Kotlin 소스 루트 부재: $kotlinBase');
  }
  final List<File> mainActivities = base
      .listSync(recursive: true)
      .whereType<File>()
      .where((File file) => file.uri.pathSegments.last == 'MainActivity.kt')
      .toList();
  if (mainActivities.length != 1) {
    fail(
      '$kotlinBase 아래 MainActivity.kt 가 정확히 1개여야 한다 '
      '(발견 ${mainActivities.length}개).',
    );
  }
  return mainActivities.single.parent.path;
}

/// xcconfig 본문에서 `KEY = value` 줄의 값을 돌려준다 (없으면 빈 문자열).
String _readXcconfigValue(String xcconfig, String key) {
  final match = RegExp(
    '^${RegExp.escape(key)}\\s*=\\s*(.*)\$',
    multiLine: true,
  ).firstMatch(xcconfig);
  return match?.group(1)?.trim() ?? '';
}
