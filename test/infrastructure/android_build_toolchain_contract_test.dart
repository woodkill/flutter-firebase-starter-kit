// Phase 17.6 — see ROADMAP.md.
//
// Android 빌드 설비(AGP 9 단계 B)의 소스 계약을 잠근다. AGP 9 는 resValue 기능을
// 기본으로 끄고, KGP 2.3 이상은 android 블록 안의 옛 Kotlin 옵션 DSL 을 스크립트
// 컴파일 오류로 만든다 — 두 줄이 빠지면 빌드가 설정 단계에서 멈추므로 앱 gradle 의
// 해당 줄을 고정한다. 앱 모듈은 AGP 내장 Kotlin 을 쓰므로 내장 Kotlin 을 켠 플래그와
// 앱 gradle 에 KGP 적용 줄이 없음을 잠그고, 새 DSL 을 끄는 플래그와 settings 의 KGP
// 선언은 다음 단계(C)까지 남아 있어야 하므로 함께 잠근다. 도구(Gradle · AGP · KGP ·
// 플러그인) 버전 숫자는 단언하지 않는다 — 다음 상향마다 이 테스트를 고치게 만들지
// 않기 위해서다. Kotlin jvmTarget 줄만은 Flutter 템플릿 원문 그대로(`JVM_17`)
// 고정한다 — Java 타깃을 바꾸면 T-176-ANDROID-02 의 그 단언도 함께 고친다.
//
// 주석을 걷어낸 뒤 센다 — 설명 주석이 값 문자열을 언급하면 단언이 공허하게
// 참이 되기 때문이다(`test/helpers/source_text.dart` 머리 주석).

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

const String _appGradlePath = 'android/app/build.gradle.kts';
const String _settingsPath = 'android/settings.gradle.kts';
const String _gradlePropertiesPath = 'android/gradle.properties';

void main() {
  group('Android 빌드 설비 계약 (AGP 9 단계 B)', () {
    test('T-176-ANDROID-01 buildFeatures.resValues — AGP 9 기본값(꺼짐) 덮어쓰기', () {
      final String gradle = stripBlockComments(
        stripSlashComments(readTrackedFile(_appGradlePath)),
      );

      expect(
        countOccurrences(gradle, 'resValues = true'),
        1,
        reason:
            '빠지면 설정 단계에서 「defaultConfig contains custom resource '
            'values, but the feature is disabled.」 로 멈춘다 — docs/guide.md '
            '「Flutter SDK 상향 (FVM)」 ⑤',
      );
      expect(
        countOccurrences(gradle, 'buildFeatures {'),
        1,
        reason: 'resValues 는 앱 모듈 android { buildFeatures { } } 에서 켠다',
      );
    });

    test('T-176-ANDROID-02 Kotlin jvmTarget — compilerOptions DSL', () {
      final String gradle = stripBlockComments(
        stripSlashComments(readTrackedFile(_appGradlePath)),
      );
      // 옛 DSL 이름이 이 소스에 통째로 남지 않게 조각을 이어 만든다.
      const legacyKotlinBlock =
          'kotlin'
          'Options {';

      expect(
        countOccurrences(
          gradle,
          'jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17',
        ),
        1,
        reason: 'top-level kotlin { compilerOptions { } } 의 jvmTarget 은 JVM_17',
      );
      expect(
        countOccurrences(gradle, 'compilerOptions {'),
        1,
        reason: 'Flutter 3.47.5 템플릿과 같은 compilerOptions DSL',
      );
      expect(
        countOccurrences(gradle, legacyKotlinBlock),
        0,
        reason: 'KGP 2.3 이상은 옛 Kotlin 옵션 DSL 을 스크립트 컴파일 오류로 만든다',
      );
      expect(
        countOccurrences(gradle, 'id("kotlin-android")'),
        0,
        reason: '앱 모듈은 AGP 내장 Kotlin 을 쓴다 — KGP 를 직접 적용하지 않는다',
      );
      // 같은 플러그인의 정식 id · Kotlin DSL 접근자로도 적용하지 않는다.
      // settings 의 `apply false` 선언은 T-176-ANDROID-03 이 다른 파일에서 센다.
      for (final alias in <String>[
        'id("org.jetbrains.kotlin.android")',
        'kotlin("android")',
      ]) {
        expect(
          countOccurrences(gradle, alias),
          0,
          reason: '앱 모듈은 AGP 내장 Kotlin 을 쓴다 — `$alias` 로도 KGP 를 적용하지 않는다',
        );
      }
    });

    test(
      'T-176-ANDROID-03 단계 B 불변식 — 내장 Kotlin 켬 · 새 DSL 끔 · settings KGP 선언',
      () {
        final String properties = readTrackedFile(_gradlePropertiesPath);
        final String settings = stripBlockComments(
          stripSlashComments(readTrackedFile(_settingsPath)),
        );

        expect(
          countExactLines(properties, 'android.builtInKotlin=true'),
          1,
          reason: '앱 모듈은 AGP 내장 Kotlin 을 쓴다',
        );
        expect(
          countExactLines(properties, 'android.builtInKotlin=false'),
          0,
          reason: '끄는 옵션은 AGP 10.0 에서 사라진다 — false 로 되돌리지 않는다',
        );
        expect(
          countExactLines(properties, 'android.newDsl=false'),
          1,
          reason: '새 DSL 전환은 단계 C 범위다',
        );
        expect(
          countOccurrences(
            settings,
            'id("org.jetbrains.kotlin.android") version "',
          ),
          1,
          reason:
              '지우면 AGP 번들 KGP 가 Flutter 오류 하한 미만이 된다 '
              '(flutter/flutter#192167)',
        );
      },
    );
  });
}
