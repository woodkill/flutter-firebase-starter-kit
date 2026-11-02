// Android LINE 로그인 콜백 relay 계약.
//
// SDK 콜백 Activity 의 재기동은 빈 taskAffinity 때문에 앱 task 를 찾지 못한다 — LINE
// 앱 경로에서는 LINE 메인 화면이, 웹 경로에서는 브라우저 탭이 앱 위에 남는다. 그래서
// manifest 에서 SDK 콜백 Activity 를 빼고, `MainActivity.kt` 안의 공개 relay
// `LineAuthCallbackActivity` 가 `lineauth` 콜백을 받아 앱 task 의 대기 인증 Activity 로
// data 만 넘긴다. 이 시험은 relay 의 동작 · 하지 않는 것(앞세우기 · 수명주기 콜백 · data
// 외 전달 · 로그), gradle compileOnly 버전, manifest 두 선언을 소스 텍스트로 잠근다.
//
// tracked 파일만 읽고, 주석을 걷은 뒤 센다 — 설명 주석이 토큰을 언급하면 「있어야
// 한다」 단언이 공허하게 참이 되고 「0 건」 단언이 거짓 RED 가 된다.
// Kotlin 디렉터리는 `MainActivity.kt` 위치에서 파생하므로 앱 패키지 경로를 바꾼
// 저장소에서도 돈다.
//
// WQ0-LINE-04(패키지 디렉터리 Kotlin 파일 집합 고정)는 킷 유지보수 규칙이라 유지보수자
// 트리에서만 돈다 — 킷을 받은 저장소는 자기 Kotlin 파일을 더할 수 있고, 거기서 이
// 시험이 실패하면 안 된다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';
import '../helpers/source_text.dart';

const String _gradlePath = 'android/app/build.gradle.kts';
const String _manifestPath = 'android/app/src/main/AndroidManifest.xml';

void main() {
  group('Android LINE 콜백 relay 계약 (WQ0-LINE)', () {
    late final String kotlinDir = _findKotlinPackageDir();

    /// 주석을 걷은 `MainActivity.kt` 본문을 돌려준다.
    String readMainActivity() => stripBlockComments(
      stripSlashComments(readTrackedFile('$kotlinDir/MainActivity.kt')),
    );

    test('WQ0-LINE-01 수명주기 콜백 · 앞세우기를 쓰지 않는다', () {
      final String source = readMainActivity();

      for (final token in <String>[
        'registerActivityLifecycleCallbacks',
        'Application.ActivityLifecycleCallbacks',
        'LineAuthTaskReturnCallbacks',
        'moveToFront',
        'moveTaskToFront',
        'Looper',
        'Handler',
        'override fun onDestroy',
      ]) {
        expect(
          countOccurrences(source, token),
          0,
          reason: '`$token` 금지 — 앞세우기는 탭을 걷지 못하고, relay 하나가 앱 · 웹 경로를 모두 맡는다',
        );
      }
    });

    test('WQ0-LINE-02 relay 는 앱 task 의 대기 인증 Activity 에 data 를 보내고 끝난다', () {
      final String source = readMainActivity();

      for (final token in <String>[
        'class LineAuthCallbackActivity : Activity()',
        'finish()',
        '.appTasks',
        'intent?.data',
        'MainActivity::class.java',
      ]) {
        expect(
          countOccurrences(source, token),
          1,
          reason: '`$token` 이 코드에 정확히 1번 있어야 한다',
        );
      }
      final patterns = <String, String>{
        r'\.startActivity\(\s*this,':
            'AppTask.startActivity 로 앱 task 안에서 시작해야 탭이 걷힌다',
        r'Intent\(this,\s*LineAuthenticationActivity::class\.java\)\s*'
                r'\.setData\(data\)\s*'
                r'\.addFlags\(\s*Intent\.FLAG_ACTIVITY_CLEAR_TOP\s+or\s+'
                r'Intent\.FLAG_ACTIVITY_SINGLE_TOP\s*,?\s*\)':
            '대기 인증 Activity 를 부르는 새 명시 intent 에 data 와 두 플래그만 싣는다',
        r'baseActivity\?\.className\s*==\s*MainActivity::class\.java\.name':
            '앱 task 는 base 가 MainActivity 인 task 다',
        r'numActivities\s*>=\s*2': 'MainActivity 위에 Activity 가 있어야 대기 중으로 본다',
        r'^import com\.linecorp\.linesdk\.auth\.internal\.LineAuthenticationActivity$':
            'SDK 인증 Activity 를 컴파일 타임에 참조한다 — 이름이 바뀌면 빌드가 깨진다',
        r'\btry\s*\{': 'task 조회와 시작을 try 하나로 함께 감싼다',
        r'catch\s*\(\s*\w+\s*:\s*IllegalArgumentException\s*\)':
            'task 가 사라진 경우의 IllegalArgumentException 만 잡는다',
        r'\bcatch\b': 'catch 는 하나뿐이다 — 다른 예외를 숨기지 않는다',
      };
      patterns.forEach((String pattern, String reason) {
        expect(
          RegExp(pattern, multiLine: true).allMatches(source),
          hasLength(1),
          reason: reason,
        );
      });
    });

    test(
      'WQ0-LINE-03 SDK 콜백 Activity 를 참조하지 않고 data 외에는 넘기지 않으며 로그를 남기지 않는다',
      () {
        final String source = readMainActivity();

        for (final token in <String>[
          'LineAuthenticationCallbackActivity',
          'FLAG_ACTIVITY_NEW_TASK',
          'Log.',
          'println',
          'runCatching',
          'putExtra',
          '.extras',
          'Intent(intent',
        ]) {
          expect(
            countOccurrences(source, token),
            0,
            reason:
                '`$token` 금지 — SDK 콜백 Activity 는 manifest 에서 제거했고, '
                'NEW_TASK 는 앱 task 를 벗어나고, 로그는 콜백 code · state 를 남길 수 '
                '있고, 예외 삼킴은 실패를 숨기고, exported relay 가 들어온 값을 넘기면 '
                'intent redirection 이 된다',
          );
        }
      },
    );

    test(
      'WQ0-LINE-04 패키지 디렉터리에 Kotlin 파일을 더하지 않는다 — rename 저장소 merge 가 깨끗하도록',
      () {
        final Set<String> names = Directory(kotlinDir)
            .listSync()
            .whereType<File>()
            .map((File file) => file.uri.pathSegments.last)
            .where((String name) => name.endsWith('.kt'))
            .toSet();

        expect(
          names,
          <String>{
            'MainActivity.kt',
            'NaverHostChannel.kt',
            'WebAuthCallbackActivity.kt',
          },
          reason:
              '패키지 경로를 바꾼 저장소에서 새 .kt 는 merge 가 CONFLICT (file '
              'location) 으로 멈추고 package 줄이 옛 값으로 남지만, 기존 파일 수정은 '
              '옮겨진 파일로 자동 병합된다(git ort 모의) — 킷 코드는 기존 파일 안에 '
              '둔다. 킷을 받은 저장소는 자기 Kotlin 파일을 더할 수 있어 유지보수자 '
              '트리에서만 돈다',
        );
      },
      skip: skipUnlessMaintainerTree(),
    );

    test('WQ0-LINE-05 LINE SDK compileOnly — 플러그인과 같은 좌표 · 버전', () {
      final String gradle = stripSlashComments(readTrackedFile(_gradlePath));

      final List<RegExpMatch> appMatches = RegExp(
        r'compileOnly\("com\.linecorp\.linesdk:linesdk:([^"]+)"\)',
      ).allMatches(gradle).toList();
      expect(
        appMatches,
        hasLength(1),
        reason:
            '앱 gradle 에 LINE SDK compileOnly 선언이 정확히 1건이어야 한다 — '
            '없으면 MainActivity.kt 의 SDK 클래스 참조가 컴파일되지 않는다',
      );
      expect(
        RegExp(r'implementation\("com\.linecorp\.linesdk').hasMatch(gradle),
        isFalse,
        reason: '앱은 SDK 를 implementation 으로 선언하지 않는다 — 런타임 AAR 은 플러그인이 공급한다',
      );

      // 플러그인이 선언한 SDK 버전 — pub 이 해석한 패키지 루트에서 읽는다.
      final packageConfig =
          jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
              as Map<String, dynamic>;
      final List<Map<String, dynamic>> packages =
          (packageConfig['packages'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      final Map<String, dynamic> plugin = packages.firstWhere(
        (Map<String, dynamic> p) => p['name'] == 'flutter_line_sdk',
        orElse: () => <String, dynamic>{},
      );
      expect(
        plugin,
        isNotEmpty,
        reason: 'package_config.json 에서 flutter_line_sdk 를 찾을 수 없다',
      );
      // rootUri 는 끝 `/` 가 없다 — 붙이지 않으면 resolve 가 마지막 segment
      // (패키지 디렉터리)를 대체한다.
      final rawRoot = plugin['rootUri'] as String;
      final Uri rootUri = Uri.parse(
        rawRoot.endsWith('/') ? rawRoot : '$rawRoot/',
      );
      final Uri root = rootUri.isAbsolute
          ? rootUri
          : Directory('.dart_tool').absolute.uri.resolveUri(rootUri);
      final pluginGradle = File.fromUri(root.resolve('android/build.gradle'));
      expect(
        pluginGradle.existsSync(),
        isTrue,
        reason: '플러그인 android/build.gradle 을 찾을 수 없다: ${root.path}',
      );
      final RegExpMatch? pluginMatch = RegExp(
        r'''['"]com\.linecorp\.linesdk:linesdk:([^'"]+)['"]''',
      ).firstMatch(pluginGradle.readAsStringSync());
      expect(
        pluginMatch,
        isNotNull,
        reason: '플러그인 gradle 에서 LINE SDK 좌표를 찾을 수 없다',
      );
      expect(
        appMatches.single.group(1),
        pluginMatch!.group(1),
        reason:
            '앱의 compileOnly SDK 버전이 flutter_line_sdk 가 링크하는 버전과 같아야 '
            '한다 — 플러그인을 올렸다면 앱 gradle 의 compileOnly 줄도 갱신한다',
      );
    });

    test('WQ0-LINE-06 manifest — SDK 콜백 Activity 제거 · relay 등록 · 빈 taskAffinity', () {
      final String manifest = stripXmlComments(readTrackedFile(_manifestPath));
      final RegExpMatch? mainTag = RegExp(
        r'<activity\s+android:name="\.MainActivity"[^>]*>',
      ).firstMatch(manifest);
      expect(mainTag, isNotNull, reason: 'MainActivity 선언을 찾지 못했다');

      // 양성 대조군 겸 유지 단언 — 같은 태그 범위에서 빈 affinity 를 잡는다.
      expect(
        RegExp('android:taskAffinity=""').hasMatch(mainTag!.group(0)!),
        isTrue,
        reason: '빈 taskAffinity 는 StrandHogg 방어라 유지한다',
      );

      final patterns = <String, String>{
        r'<activity\s+android:name="com\.linecorp\.linesdk\.auth\.internal\.'
                r'LineAuthenticationCallbackActivity"\s+tools:node="remove"\s*/>':
            'SDK 콜백 Activity 를 병합에서 뺀다 — 남으면 수신자가 2개가 되어 chooser 가 뜬다',
        r'<activity\s+android:name="\.LineAuthCallbackActivity"\s+'
                r'android:exported="true"\s+android:taskAffinity=""\s*>\s*'
                r'<intent-filter\s*>\s*'
                r'<action\s+android:name="android\.intent\.action\.VIEW"\s*/>\s*'
                r'<category\s+android:name="android\.intent\.category\.DEFAULT"\s*/>\s*'
                r'<category\s+android:name="android\.intent\.category\.BROWSABLE"\s*/>\s*'
                r'<data\s+android:scheme="lineauth"\s*/>\s*'
                r'</intent-filter>\s*</activity>':
            'relay 는 lineauth 콜백을 받고 빈 taskAffinity 로 StrandHogg 를 막는다',
      };
      patterns.forEach((String pattern, String reason) {
        expect(
          RegExp(pattern).allMatches(manifest),
          hasLength(1),
          reason: reason,
        );
      });
      for (final token in <String>[
        'xmlns:tools="http://schemas.android.com/tools"',
        'android:scheme="lineauth"',
        'LineAuthentication',
        'android:autoRemoveFromRecents=',
      ]) {
        expect(
          countOccurrences(manifest, token),
          1,
          reason:
              '`$token` 이 manifest 에 정확히 1번 있어야 한다 — SDK 선언 중 대기 인증 '
              'Activity 는 덮지 않는다',
        );
      }
    });
  });
}

/// `android/app/src/main/kotlin` 아래 `MainActivity.kt` 가 있는 패키지
/// 디렉터리를 돌려준다.
///
/// `test/core/config/naver_native_config_contract_test.dart` 의
/// `_findKotlinPackageDir` 와 같은 동작의 작은 사본이다 — 그 시험 파일을 고치지
/// 않으려고 여기 둔다. `MainActivity.kt` 가 0개 또는 2개 이상이면 어느 패키지를
/// 볼지 모호하므로 테스트를 실패시킨다.
String _findKotlinPackageDir() {
  const kotlinBase = 'android/app/src/main/kotlin';
  final base = Directory(kotlinBase);
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
