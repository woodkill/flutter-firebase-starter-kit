// Phase 17 — see ROADMAP.md (D-01 · D-07 · Pitfall 9).
//
// FCM · 사진 선택이 요구하는 Android · iOS 플랫폼 설정을 소스 계약으로 잠근다.
// 백그라운드 · 종료 상태 FCM 알림은 Flutter 가 아니라 OS 가 그리므로 manifest
// meta-data 값이 곧 알림 외관이다(UI-SPEC §(O)). iOS 설정은 실기기 검증이
// Phase 18 iOS batch 로 이월되므로(D-07) 코드에 반영됐는지만 여기서 확인한다.
//
// 주석을 걷어낸 뒤 센다 — 설명 주석이 값 문자열을 언급하면 단언이 공허하게
// 참이 되기 때문이다(`test/helpers/source_text.dart` 머리 주석).

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

const String _manifestPath = 'android/app/src/main/AndroidManifest.xml';
const String _colorsPath = 'android/app/src/main/res/values/colors.xml';
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
      const String prefix = 'com.google.firebase.messaging.';

      for (final String key in <String>[
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
        reason: '백그라운드 알림 색 = colors.xml 상수',
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

    test('T-17-PLATFORM-02 알림 색은 #673AB7 상수이고 아이콘은 흰색 단색 vector 다', () {
      final String colors = stripXmlComments(readTrackedFile(_colorsPath));
      expect(countOccurrences(colors, 'name="notification_color"'), 1);
      expect(
        RegExp(
          r'<color\s+name="notification_color">#673AB7</color>',
        ).hasMatch(colors),
        isTrue,
        reason: '= AppTheme.seedColor (Colors.deepPurple 500) 표기 그대로',
      );

      final String icon = stripXmlComments(readTrackedFile(_iconPath));
      expect(icon, contains('<vector'));
      final List<String> fills = RegExp(
        r'android:fillColor="([^"]+)"',
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
  });
}
