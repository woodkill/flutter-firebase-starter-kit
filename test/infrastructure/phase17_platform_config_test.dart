// Phase 17 — see ROADMAP.md (D-01 · D-07 · Pitfall 9).
//
// FCM · 사진 선택이 요구하는 Android · iOS 플랫폼 설정을 소스 계약으로 잠근다.
// 백그라운드 · 종료 상태 FCM 알림은 Flutter 가 아니라 OS 가 그리므로 manifest
// meta-data 값이 곧 알림 외관이다(UI-SPEC §(O)). 그 알림 색 리소스는
// build.gradle.kts 가 config `brandColor` 로 빌드 때 만든다. iOS 설정은 실기기 검증이
// Phase 18 iOS batch 로 이월되므로(D-07) 코드에 반영됐는지만 여기서 확인한다.
//
// 주석을 걷어낸 뒤 센다 — 설명 주석이 값 문자열을 언급하면 단언이 공허하게
// 참이 되기 때문이다(`test/helpers/source_text.dart` 머리 주석).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

const String _manifestPath = 'android/app/src/main/AndroidManifest.xml';
const String _iconPath =
    'android/app/src/main/res/drawable/ic_notification.xml';
const String _infoPlistPath = 'ios/Runner/Info.plist';
const String _entitlementsPath = 'ios/Runner/Runner.entitlements';
const String _gradlePath = 'android/app/build.gradle.kts';

/// manifest 에서 [name] meta-data 의 [attribute] 값이 [value] 인지 확인하는
/// 공백 무관 패턴을 만든다.
RegExp metaDataPattern(String name, String attribute, String value) => RegExp(
  '<meta-data\\s+android:name="${RegExp.escape(name)}"\\s+'
  'android:$attribute="${RegExp.escape(value)}"\\s*/>',
);

void main() {
  group('Phase 17 플랫폼 설정 계약 (T-17-PLATFORM)', () {
    test('T-17-PLATFORM-01 manifest 에 FCM 기본 알림 meta-data 3개가 킷 값으로 있다', () {
      final String manifest = stripXmlComments(readTrackedFile(_manifestPath));
      const prefix = 'com.google.firebase.messaging.';

      for (final key in <String>[
        'default_notification_icon',
        'default_notification_color',
        'default_notification_channel_id',
      ]) {
        expect(
          countOccurrences(manifest, '"$prefix$key"'),
          1,
          reason: '$prefix$key meta-data 는 정확히 1개여야 한다',
        );
      }

      expect(
        metaDataPattern(
          '${prefix}default_notification_icon',
          'resource',
          '@drawable/ic_notification',
        ).hasMatch(manifest),
        isTrue,
        reason: '백그라운드 알림 작은 아이콘 = 킷 흰색 vector',
      );
      expect(
        metaDataPattern(
          '${prefix}default_notification_color',
          'resource',
          '@color/notification_color',
        ).hasMatch(manifest),
        isTrue,
        reason: '백그라운드 알림 색 = build.gradle.kts 가 brandColor 로 만든 리소스',
      );
      expect(
        metaDataPattern(
          '${prefix}default_notification_channel_id',
          'value',
          'general',
        ).hasMatch(manifest),
        isTrue,
        reason: '백그라운드 알림 채널 = 로컬 알림과 같은 general',
      );
    });

    test('T-17-PLATFORM-02 알림 색 리소스는 build.gradle.kts 가 brandColor 로 만들고 '
        '아이콘은 흰색 단색 vector 다', () {
      final String gradle = stripSlashComments(readTrackedFile(_gradlePath));
      expect(
        RegExp(
          r'resValue\(\s*"color",\s*"notification_color",',
        ).allMatches(gradle),
        hasLength(1),
        reason: 'notification_color 리소스는 gradle 의 resValue 하나가 만든다',
      );
      expect(
        countOccurrences(gradle, 'dartDefines["brandColor"]'),
        greaterThanOrEqualTo(1),
        reason: '알림 색의 원천은 config brandColor 다',
      );

      // 기본값 = Dart 의 킷 기본 시드 색.
      final RegExpMatch? fallback = RegExp(
        r'else\s+"(#[0-9A-Fa-f]{6})"',
      ).firstMatch(gradle);
      expect(fallback, isNotNull, reason: 'gradle 에 기본 색 리터럴이 있어야 한다');
      expect(
        0xFF000000 | int.parse(fallback!.group(1)!.substring(1), radix: 16),
        AppTheme.seedColor.toARGB32(),
        reason: 'gradle 기본 색 = AppTheme.seedColor',
      );

      // 판정 꼴 = 공유 표(Dart · 메일 · 결과 페이지와 같은 판정).
      final RegExpMatch? rule = RegExp(
        r'Regex\("([^"]+)"\)\.matches\(brandColor\)',
      ).firstMatch(gradle);
      expect(rule, isNotNull, reason: 'gradle 에 brandColor 판정 꼴이 있어야 한다');
      // Kotlin `Regex.matches` 는 입력 전체 일치다.
      final gradleRule = RegExp('^(?:${rule!.group(1)!})\$');
      final table =
          (jsonDecode(File('hosting/test/shared_rules.json').readAsStringSync())
                  as Map<String, dynamic>)['brandColor']
              as List<dynamic>;
      expect(table, isNotEmpty);
      for (final Map<String, dynamic> row
          in table.cast<Map<String, dynamic>>()) {
        final input = row['input'] as String;
        final expected = row['expected'] as String;
        expect(
          gradleRule.hasMatch(input),
          input == expected,
          reason: 'gradle 판정이 공유 표와 다르다: "$input"',
        );
      }

      // res/values* 의 어느 xml 도 notification_color 를 정의하지 않는다 —
      // 정의가 남으면 생성 리소스와 두 원천이 된다.
      final List<File> valueXmls = Directory('android/app/src/main/res')
          .listSync()
          .whereType<Directory>()
          .where(
            (Directory d) => d.uri.pathSegments.reversed
                .firstWhere((String seg) => seg.isNotEmpty)
                .startsWith('values'),
          )
          .expand((Directory d) => d.listSync().whereType<File>())
          .where((File f) => f.path.endsWith('.xml'))
          .toList();
      final List<String> xmlBodies = valueXmls
          .map((File f) => stripXmlComments(f.readAsStringSync()))
          .toList();
      // 양성 대조 — 실제로 values 디렉터리의 xml 을 읽었다.
      expect(xmlBodies, isNotEmpty);
      expect(xmlBodies.any((String body) => body.contains('<style')), isTrue);
      for (var i = 0; i < valueXmls.length; i++) {
        expect(
          countOccurrences(xmlBodies[i], 'name="notification_color"'),
          0,
          reason: '${valueXmls[i].path} 가 notification_color 를 정의한다',
        );
      }

      final String icon = stripXmlComments(readTrackedFile(_iconPath));
      expect(icon, contains('<vector'));
      final List<String> fills = RegExp(
        'android:fillColor="([^"]+)"',
      ).allMatches(icon).map((RegExpMatch m) => m.group(1)!).toList();
      expect(fills, isNotEmpty, reason: 'path 에 fillColor 가 있어야 한다');
      expect(
        fills.every((String c) => c == '#FFFFFFFF' || c == '#FFFFFF'),
        isTrue,
        reason: 'Android 작은 알림 아이콘은 흰색 단색이어야 한다: $fills',
      );
    });

    test('T-17-PLATFORM-03 Info.plist 에 백그라운드 모드 2개와 사진 권한 문구가 있다', () {
      final String plist = stripXmlComments(readTrackedFile(_infoPlistPath));
      expect(countOccurrences(plist, '<key>UIBackgroundModes</key>'), 1);

      final RegExpMatch? modes = RegExp(
        r'<key>UIBackgroundModes</key>\s*<array>([\s\S]*?)</array>',
      ).firstMatch(plist);
      expect(modes, isNotNull, reason: 'UIBackgroundModes 는 배열이어야 한다');
      final String modeBody = modes!.group(1)!;
      expect(modeBody, contains('<string>fetch</string>'));
      expect(modeBody, contains('<string>remote-notification</string>'));

      expect(
        countOccurrences(plist, '<key>NSPhotoLibraryUsageDescription</key>'),
        1,
      );
      expect(
        RegExp(
          r'<key>NSPhotoLibraryUsageDescription</key>\s*<string>[^<]+</string>',
        ).hasMatch(plist),
        isTrue,
        reason: '사진 권한 문구는 비어 있으면 안 된다(App Store 심사)',
      );
    });

    test(
      'T-17-PLATFORM-04 entitlements 에 aps-environment=development 가 있고 기존 Apple 로그인 키가 유지된다',
      () {
        final String entitlements = stripXmlComments(
          readTrackedFile(_entitlementsPath),
        );
        expect(countOccurrences(entitlements, '<key>aps-environment</key>'), 1);
        expect(
          RegExp(
            r'<key>aps-environment</key>\s*<string>development</string>',
          ).hasMatch(entitlements),
          isTrue,
        );
        // 양성 대조군 — 같은 읽기 · 계수 경로가 기존 키를 실제로 찾는다.
        expect(
          countOccurrences(
            entitlements,
            '<key>com.apple.developer.applesignin</key>',
          ),
          1,
        );
      },
    );

    test('T-17-PLATFORM-05 Gradle 에 core library desugaring 이 켜져 있다', () {
      final String gradle = stripBlockComments(
        stripSlashComments(readTrackedFile(_gradlePath)),
      );
      expect(
        countOccurrences(gradle, 'isCoreLibraryDesugaringEnabled = true'),
        1,
      );
      expect(countOccurrences(gradle, 'desugar_jdk_libs:2.1.4'), 1);
    });

    // debug notification-task-duplication RC2 (2026-10-03) — 알림 PendingIntent
    // 로 만든 task 의 루트는 back 에서 finish 된다(홈 발 실행만 task 를 뒤로
    // 보냄). 빈 taskAffinity 라 런처 실행이 그 빈 task 를 최근 앱에서 지우지
    // 못해 카드 2장 · 옛 알림 intent 재실행 · 엔진 2개(알림 2중)로 번졌다.
    test(
      'T-17-PLATFORM-06 MainActivity 는 마지막 Activity 가 끝나면 최근 앱에서 빠지고 빈 taskAffinity 는 유지한다',
      () {
        final String manifest = stripXmlComments(
          readTrackedFile(_manifestPath),
        );
        final RegExpMatch? mainTag = RegExp(
          r'<activity\s+android:name="\.MainActivity"[^>]*>',
        ).firstMatch(manifest);
        expect(mainTag, isNotNull, reason: 'MainActivity 선언을 찾지 못했다');
        final String tag = mainTag!.group(0)!;

        expect(
          RegExp('android:autoRemoveFromRecents="true"').hasMatch(tag),
          isTrue,
          reason:
              '알림 탭 → 뒤로 로 끝난 task 가 최근 앱에 빈 카드로 남으면 그 카드가 '
              '옛 알림 intent 를 재실행하고, 런처 task 와 함께 엔진 2개가 된다',
        );
        // 양성 대조군 겸 유지 단언 — 같은 태그 범위에서 빈 affinity 를 잡는다.
        expect(
          RegExp('android:taskAffinity=""').hasMatch(tag),
          isTrue,
          reason: '빈 taskAffinity 는 StrandHogg 방어라 유지한다 (minSdk 24)',
        );
        expect(
          countOccurrences(manifest, 'android:autoRemoveFromRecents='),
          1,
          reason: 'MainActivity 1곳에만 둔다 — relay 등 다른 Activity 는 대상 밖',
        );
      },
    );
  });
}
