// Android LINE 로그인 콜백 뒤 앱 task 복귀 계약.
//
// LINE 앱의 「허용」 뒤 SDK 콜백 Activity 는 LINE task 에 열리고, 인증 Activity 를
// 새 task 에 다시 띄운 뒤 끝난다. 앱 task 를 앞으로 가져오는 주체가 없어 LINE 메인
// 화면이 남던 문제를 `MainActivity.kt` 안의 private 수명주기 콜백이 고친다. 이 시험은
// 그 콜백의 등록 · 해제, 앞세우는 조건 · 방법, 하지 않는 것(대기 인증 Activity 를 지우는
// 플래그 · MainActivity 재기동 · 로그), gradle compileOnly 버전, manifest 불변을 소스
// 텍스트로 잠근다.
//
// tracked 파일만 읽고, 주석을 걷은 뒤 센다 — 설명 주석이 토큰을 언급하면 「있어야
// 한다」 단언이 공허하게 참이 되고 「0 건」 단언이 거짓 RED 가 된다.
// Kotlin 디렉터리는 `MainActivity.kt` 위치에서 파생하므로 앱 패키지 경로를 바꾼
// 저장소에서도 돈다.
//
// UBZ-LINE-04(패키지 디렉터리 Kotlin 파일 집합 고정)는 킷 유지보수 규칙이라 유지보수자
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
  group('Android LINE 콜백 뒤 앱 task 복귀 계약 (UBZ-LINE)', () {
    late final String kotlinDir = _findKotlinPackageDir();

    /// 주석을 걷은 `MainActivity.kt` 본문을 돌려준다.
    String readMainActivity() => stripBlockComments(
      stripSlashComments(readTrackedFile('$kotlinDir/MainActivity.kt')),
    );

    test('UBZ-LINE-01 MainActivity 가 onCreate 에서 등록하고 onDestroy 에서 해제한다', () {
      final String source = readMainActivity();

      expect(
        RegExp(r'\bregisterActivityLifecycleCallbacks\(').allMatches(source),
        hasLength(1),
        reason: '콜백 등록은 정확히 1곳이어야 한다',
      );
      expect(
        RegExp(r'\bunregisterActivityLifecycleCallbacks\(').allMatches(source),
        hasLength(1),
        reason: '등록한 콜백은 해제해야 한다 — 없으면 MainActivity 인스턴스가 새어 나간다',
      );
      expect(
        countOccurrences(source, 'LineAuthTaskReturnCallbacks(this)'),
        1,
        reason: '콜백 인스턴스는 MainActivity 필드 하나로 만든다',
      );
      expect(
        RegExp(
          r'super\.onCreate\(savedInstanceState\)\s*'
          r'application\.registerActivityLifecycleCallbacks\('
          r'lineAuthTaskReturnCallbacks\)',
        ).allMatches(source),
        hasLength(1),
        reason: '등록은 onCreate 의 super.onCreate 바로 뒤에 둔다',
      );
      expect(
        RegExp(
          r'application\.unregisterActivityLifecycleCallbacks\('
          r'lineAuthTaskReturnCallbacks\)\s*super\.onDestroy\(\)',
        ).allMatches(source),
        hasLength(1),
        reason: '해제는 onDestroy 의 super.onDestroy 바로 앞에 둔다',
      );
    });

    test(
      'UBZ-LINE-02 콜백은 LINE 콜백 뒤 재기동된 인증 Activity 가 다른 task 에 생긴 다음 앱 task 를 앞세운다',
      () {
        final String source = readMainActivity();

        expect(
          RegExp(
            r'private class LineAuthTaskReturnCallbacks\(private val host: '
            r'Activity\)\s*:\s*Application\.ActivityLifecycleCallbacks',
          ).allMatches(source),
          hasLength(1),
          reason:
              '콜백은 MainActivity.kt 안의 top-level private class 로 둔다 — '
              '새 Kotlin 파일은 rename 저장소 merge 에서 위치 충돌이 난다',
        );
        for (final token in <String>[
          'Application.ActivityLifecycleCallbacks',
          'is LineAuthenticationCallbackActivity',
          'Looper.getMainLooper()',
          '.moveToFront()',
          '.appTasks',
          'Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q',
          '@Suppress("DEPRECATION")',
          'host.isDestroyed',
        ]) {
          expect(
            countOccurrences(source, token),
            1,
            reason: '`$token` 이 코드에 정확히 1번 있어야 한다',
          );
        }
        final patterns = <String, String>{
          r'^import com\.linecorp\.linesdk\.auth\.internal\.LineAuthenticationCallbackActivity$':
              'SDK 콜백 Activity 를 컴파일 타임에 참조한다 — 이름이 바뀌면 빌드가 깨진다',
          r'^import com\.linecorp\.linesdk\.auth\.internal\.LineAuthenticationActivity$':
              'SDK 인증 Activity 를 컴파일 타임에 참조한다 — 이름이 바뀌면 빌드가 깨진다',
          r'hasPendingCallback\s*&&\s*activity is LineAuthenticationActivity\s*&&\s*activity\.taskId\s*!=\s*host\.taskId':
              '콜백 표시가 있고 인증 Activity 가 앱과 다른 task 에 생긴 경우에만 앞세운다',
          r'^\s*hasPendingCallback = true\s*$': '콜백 Activity 생성 때 표시만 한다',
          r'^\s*hasPendingCallback = false\s*$': '앞세우기를 예약할 때 표시를 지워 한 번만 돈다',
          r'\.post\s*\{':
              '인증 Activity 의 onCreate(결과 저장) 뒤에 돌도록 main looper 에 post 한다',
        };
        patterns.forEach((String pattern, String reason) {
          expect(
            RegExp(pattern, multiLine: true).allMatches(source),
            hasLength(1),
            reason: reason,
          );
        });
      },
    );

    test(
      'UBZ-LINE-03 대기 인증 Activity 를 지우거나 MainActivity 를 새로 띄우거나 로그를 남기지 않는다',
      () {
        final String source = readMainActivity();

        for (final token in <String>[
          'FLAG_ACTIVITY_CLEAR_TOP',
          'startActivity(',
          'moveTaskToFront',
          'Log.',
          'println',
          'runCatching',
        ]) {
          expect(
            countOccurrences(source, token),
            0,
            reason:
                '`$token` 금지 — CLEAR_TOP 은 대기 인증 Activity 를 지워 결과를 잃고, '
                'startActivity 는 Flutter 엔진을 하나 더 만들고, 로그는 콜백 code · '
                'state 를 남길 수 있고, 예외 삼킴은 실패를 숨긴다',
          );
        }
        expect(
          RegExp(r'\btry\s*\{').hasMatch(source),
          isFalse,
          reason: 'try/catch 를 두지 않는다 — 앞세우기 실패는 시스템 쪽 무음이다',
        );
      },
    );

    test(
      'UBZ-LINE-04 패키지 디렉터리에 Kotlin 파일을 더하지 않는다 — rename 저장소 merge 가 깨끗하도록',
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

    test('UBZ-LINE-05 LINE SDK compileOnly — 플러그인과 같은 좌표 · 버전', () {
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

    test(
      'UBZ-LINE-06 manifest 는 그대로다 — MainActivity 빈 taskAffinity 유지 · SDK Activity 선언을 덮지 않는다',
      () {
        final String manifest = stripXmlComments(
          readTrackedFile(_manifestPath),
        );
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
        expect(
          countOccurrences(manifest, 'LineAuthentication'),
          0,
          reason: 'SDK Activity 선언을 manifest 에서 tools:replace 로 덮지 않는다',
        );
      },
    );
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
