// off provider 의 빈 scheme 불변식 (Phase 17.3 D-04 · D-05 — see ROADMAP.md).
//
// 키를 비운 provider 는 일반 scheme(빈 값 · `kakao` · `fb`)을 등록하지 않는다.
// 같은 custom scheme 을 여러 앱이 등록하면 OS 가 어느 앱을 열지 정의되지 않으므로
// (Apple 「If multiple apps register the same scheme, the app the system
// targets is undefined.」), 키가 빈 provider 는 앱이 쓰지 않는 자리표시 scheme 을
// 등록한다.
//
// 고치는 방법은 빌드가 이미 읽는 키 값의 비어 있음만 보고 provider on/off CSV 는
// 읽지 않는다(D-05 — 빌드 설정이 CSV 를 읽는 구조로 커지면 정지 조건). 이 test 는
// tracked 소스만 읽는다. 실 빌드 산출물 검사는
// `scripts/verify_placeholder_builds.sh`.
//
// 범위는 킷이 `AndroidManifest.xml` · `Info.plist` 에 직접 적은 scheme 뿐이다 —
// 플러그인 라이브러리가 병합하는 scheme 은 설치만으로 등록되며 여기서 다루지 않는다.

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/source_text.dart';

/// provider on/off CSV 의 config 키 — 빌드 설정 파일에 등장하면 안 된다(D-05).
const String _csvKey = 'enabledAuthProviders';

void main() {
  group('off provider 빈 scheme 불변식 (T-173-SCHEME)', () {
    test('T-173-SCHEME-01: gradle — Kakao · Naver scheme placeholder 는 키가 비면 '
        'unset.* · CSV 미참조', () {
      final String rawGradle = readTrackedFile('android/app/build.gradle.kts');
      final String gradle = stripSlashComments(rawGradle);

      expect(
        countOccurrences(gradle, 'manifestPlaceholders["kakaoOAuthScheme"]'),
        1,
        reason:
            'D-04: Kakao OAuth redirect scheme 은 전용 placeholder '
            'kakaoOAuthScheme 1곳에서 공급해야 한다.',
      );
      // gradle 포맷이 줄바꿈 위치를 바꿀 수 있어 공백 무관 정규식으로 센다.
      expect(
        RegExp(
          r'if\s*\(kakaoNativeAppKey\.isEmpty\(\)\)\s*"unset\.kakao\.oauth"'
          r'\s*else\s*"kakao\$kakaoNativeAppKey"',
        ).allMatches(gradle).length,
        1,
        reason:
            'D-04: Kakao 키가 비면 일반 scheme(kakao) 대신 자리표시 '
            'unset.kakao.oauth 를, 키가 있으면 kakao + 키를 써야 한다.',
      );
      expect(
        RegExp(
          r'if\s*\(naverUrlScheme\.isEmpty\(\)\)\s*"unset\.naver\.web"'
          r'\s*else\s+naverUrlScheme\b',
        ).allMatches(gradle).length,
        1,
        reason:
            'D-04: Naver 웹 콜백 scheme 은 키가 비면 빈 scheme 대신 자리표시 '
            'unset.naver.web 를, 키가 있으면 그 값을 그대로 써야 한다.',
      );
      // 주석까지 포함한 원문에서 센다 — 설명으로도 CSV 를 끌어오지 않는다.
      expect(
        countOccurrences(rawGradle, _csvKey),
        0,
        reason:
            'D-05: gradle 은 provider on/off CSV 를 읽지 않는다 — 키 값의 '
            '비어 있음만 본다. CSV 를 읽어야 한다면 구조 변경이라 멈추고 '
            '사용자에게 확인한다.',
      );
    });

    test('T-173-SCHEME-02: manifest — Kakao OAuth intent-filter 는 '
        'kakaoOAuthScheme placeholder', () {
      final String rawManifest = readTrackedFile(
        'android/app/src/main/AndroidManifest.xml',
      );
      final String manifest = stripXmlComments(rawManifest);

      // 양성 대조 — 같은 소스에서 Kakao 블록을 읽고 있음을 확인한다.
      expect(
        countOccurrences(manifest, 'com.kakao.sdk.AppKey'),
        1,
        reason: '양성 대조: Kakao meta-data 선언을 찾지 못했다.',
      );
      expect(
        RegExp(
          r'<data\s+android:scheme="\$\{kakaoOAuthScheme\}"\s+'
          r'android:host="oauth"\s*/>',
        ).allMatches(manifest).length,
        1,
        reason:
            'D-04: Kakao OAuth intent-filter scheme 은 gradle placeholder '
            'kakaoOAuthScheme 이어야 한다 — 키가 비면 자리표시가 들어간다.',
      );
      expect(
        countOccurrences(manifest, 'android:scheme="kakao'),
        0,
        reason:
            'D-04: Kakao scheme 을 kakao 접두 리터럴로 쓰면 키가 빌 때 일반 '
            'scheme(kakao) 이 등록된다.',
      );
      expect(
        countOccurrences(rawManifest, _csvKey),
        0,
        reason: 'D-05: manifest 는 provider on/off CSV 를 참조하지 않는다.',
      );
    });
  });
}
