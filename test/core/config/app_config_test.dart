import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig.authProviders 단일 CSV 진실 (Pitfall 2, T-11-CONST-01)', () {
    test('미주입 키는 false 안전 default 를 반환한다 (D-21)', () {
      // dart-define-from-file 미적용 상태 (test 환경) → CSV 빈 문자열 →
      // 모든 6 슬러그 disabled.
      final map = AppConfig.authProviders;
      expect(map.length, kAllProviderIds.length);
      for (final id in kAllProviderIds) {
        expect(map.containsKey(id), isTrue, reason: 'missing $id');
        expect(map[id], isFalse, reason: '$id should default to false');
      }
    });

    test('staticAuthProvidersProvider 가 동일 맵을 반환한다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final mapFromProvider = container.read(staticAuthProvidersProvider);
      expect(mapFromProvider, AppConfig.authProviders);
    });

    test('AppConfig.authProviders 키 셋이 kAllProviderIds 와 정합한다', () {
      // CSV 토큰이 어떤 값이든 키 셋은 항상 kAllProviderIds 와 동일해야 한다 —
      // 미등록 슬러그는 false 로, 미주입 슬러그도 false 로 노출 (D-21).
      expect(AppConfig.authProviders.keys.toSet(), kAllProviderIds.toSet());
      expect(AppConfig.authProviders.length, kAllProviderIds.length);
    });

    test('isEnabledStatically 가 authProviders[id] 와 동등하다', () {
      for (final id in kAllProviderIds) {
        expect(
          AppConfig.isEnabledStatically(id),
          AppConfig.authProviders[id],
          reason: '$id helper 와 map 결과 불일치',
        );
      }
      // 미등록 슬러그는 false (D-21).
      expect(AppConfig.isEnabledStatically('nonexistent'), isFalse);
    });
  });

  group('config JSON 무결성 (D-19, T-11-CONST-01)', () {
    for (final flavor in const <String>['dev', 'stg', 'prod']) {
      test('$flavor.json 의 enabledAuthProviders CSV 가 형식 정합한다', () {
        // CR-02 (Phase 13 review): config/{flavor}.json 은 .gitignore 대상.
        // fresh clone / CI 에서 `cp *.example.json *.json` 미실행 시
        // FileSystemException 으로 entire suite 가 fail 되는 것을 방지하기
        // 위해 missing 시 graceful skip. 본 contract 는 사용자가 실제 키를
        // 주입한 dev 환경에서만 검증되어야 하므로 skip 가 안전.
        final file = File('config/$flavor.json');
        if (!file.existsSync()) {
          markTestSkipped(
            'config/$flavor.json missing — `cp config/$flavor.example.json '
            'config/$flavor.json` 실행 후 재시도. fresh clone / CI 에서는 정상.',
          );
          return;
        }
        final raw = file.readAsStringSync();
        final json = jsonDecode(raw) as Map<String, dynamic>;

        // 단일 키 존재.
        expect(
          json.containsKey('enabledAuthProviders'),
          isTrue,
          reason: '$flavor.json missing enabledAuthProviders',
        );
        expect(
          json['enabledAuthProviders'],
          isA<String>(),
          reason: '$flavor.json: enabledAuthProviders must be String',
        );

        // CSV 토큰 모두 kAllProviderIds 멤버여야 한다 (오타 방지).
        final csv = json['enabledAuthProviders'] as String;
        final tokens = csv
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        for (final token in tokens) {
          expect(
            kAllProviderIds.contains(token),
            isTrue,
            reason:
                '$flavor.json: enabledAuthProviders 의 "$token" 이 kAllProviderIds 에 없음',
          );
        }

        // dart-define 키 자체도 식별자 정책 (`[A-Za-z_][A-Za-z0-9_]*`) 정합.
        const flatKey = 'enabledAuthProviders';
        final dartDefinePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
        expect(
          dartDefinePattern.hasMatch(flatKey),
          isTrue,
          reason: 'dart-define 키 정책 위반',
        );
      });

      test('$flavor.json 의 기본값 (google/apple/facebook/kakao 활성, '
          'flavor 별 Phase 13~16 Custom Token 정책)', () {
        // CR-02 (Phase 13 review): missing 시 graceful skip — 위 contract
        // test 와 동일 정책.
        final file = File('config/$flavor.json');
        if (!file.existsSync()) {
          markTestSkipped(
            'config/$flavor.json missing — `cp config/$flavor.example.json '
            'config/$flavor.json` 실행 후 재시도.',
          );
          return;
        }
        final raw = file.readAsStringSync();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final csv = (json['enabledAuthProviders'] as String? ?? '');
        final enabled = csv
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet();

        // 활성: Google / Apple / Facebook (Phase 7~9) + Kakao (Phase 12 D-19).
        expect(enabled.contains(kProviderIdGoogle), isTrue);
        expect(enabled.contains(kProviderIdApple), isTrue);
        expect(enabled.contains(kProviderIdFacebook), isTrue);
        expect(enabled.contains(kProviderIdKakao), isTrue);

        // dev 는 Phase 진행에 따라 Custom Token 점진 활성화 (Phase 13:
        // naver, Phase 14: line).
        // stg/prod 는 Starter Kit 정책상 placeholder — Phase 13~16 모두 비활성.
        if (flavor == 'dev') {
          expect(
            enabled.contains(kProviderIdNaver),
            isTrue,
            reason: 'dev.json: naver should be enabled (Phase 13)',
          );
          expect(
            enabled.contains(kProviderIdLine),
            isTrue,
            reason: 'dev.json: line should be enabled (Phase 14)',
          );
        } else {
          for (final id in const <String>[kProviderIdNaver, kProviderIdLine]) {
            expect(
              enabled.contains(id),
              isFalse,
              reason:
                  '$flavor.json: $id should be disabled (placeholder policy)',
            );
          }
        }
      });
    }
  });

  group('Phase 12 — kakaoNativeAppKey (D-20)', () {
    test('AppConfig.kakaoNativeAppKey 는 dart-define 미주입 시 빈 문자열', () {
      // 테스트 환경에서는 --dart-define-from-file 미적용 → 빈 문자열 default.
      expect(AppConfig.kakaoNativeAppKey, isA<String>());
      expect(AppConfig.kakaoNativeAppKey, isEmpty);
    });

    for (final flavor in const <String>['dev', 'stg', 'prod']) {
      test('$flavor.json 에 kakaoNativeAppKey 키가 존재한다', () {
        // CR-02 (Phase 13 review): missing 시 graceful skip — fresh clone / CI
        // 에서는 정상.
        final file = File('config/$flavor.json');
        if (!file.existsSync()) {
          markTestSkipped(
            'config/$flavor.json missing — `cp config/$flavor.example.json '
            'config/$flavor.json` 실행 후 재시도.',
          );
          return;
        }
        final raw = file.readAsStringSync();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        expect(
          json.containsKey('kakaoNativeAppKey'),
          isTrue,
          reason: '$flavor.json missing kakaoNativeAppKey',
        );
        expect(
          json['kakaoNativeAppKey'],
          isA<String>(),
          reason: '$flavor.json: kakaoNativeAppKey must be String',
        );
        // placeholder 또는 실 키 — 빈 문자열은 D-20 에서 silent fallback 회피.
        expect(
          (json['kakaoNativeAppKey'] as String).isNotEmpty,
          isTrue,
          reason: '$flavor.json: kakaoNativeAppKey 가 빈 문자열이면 silent failure',
        );
      });
    }
  });

  // IN-03 테스트 2건(Naver 3종 평탄화 · client secret doc)은 Phase 16.2 D-04 로
  // 단언 대상인 AppConfig 의 Naver 상수 3종 자체가 삭제되어 함께 제거됐다.
  // Naver 키는 이제 빌드 타임 native 설정으로만 주입되며, 그 배선은
  // naver_native_config_contract_test.dart 가 잠근다.
  group('IN-02 / IN-04 — app_config.dart 표기 일관성 (소스 계약)', () {
    late String source;

    setUpAll(() async {
      source = await File('lib/core/config/app_config.dart').readAsString();
    });

    /// 주석·문서 라인을 제거한 [raw] 를 반환한다.
    String stripComments(String raw) => raw
        .split('\n')
        .where((line) {
          final trimmed = line.trimLeft();
          return !trimmed.startsWith('//') && !trimmed.startsWith('///');
        })
        .join('\n');

    test("IN-02: defaultValue: '' 표기가 파일 전체에서 제거되어 있다", () {
      // flavor / appName 은 "defaultValue 없음 = silent fallback 회피" 를
      // 근거로 인자를 의도적으로 생략했는데, 나머지는 defaultValue: '' 를
      // 명시하면서 doc 에는 똑같은 근거를 적었다. 한 파일 안에 두 규칙이
      // 공존하지 않게 한다.
      expect(
        stripComments(source),
        isNot(contains("defaultValue: ''")),
        reason: "IN-02: String.fromEnvironment 의 기본 defaultValue 가 이미 '' 다",
      );
    });

    test('IN-04: doc 이 kAllProviderIds 개수를 하드코딩하지 않는다', () {
      // (IN-04 수정 당시) 실제 kAllProviderIds 는 7개였는데 doc 은 "8 슬러그" 라고
      // 적고 있었다 (당시 exception_l10n 의 "8 provider (… + email)" 와 혼동된 숫자).
      // 개수는 provider 추가/폐기마다 바뀌므로 doc 에서 숫자를 제거한다.
      expect(source, isNot(contains('8 슬러그')));
      expect(source, isNot(contains('8개 평탄 키')));
      expect(source, isNot(contains('8 entry')));
      // 근거: email 은 kAllProviderIds 에 없다.
      expect(kAllProviderIds.contains('email'), isFalse);
    });
  });

  group('WR-09: enabledAuthProviders CSV 의 미지 슬러그 검출', () {
    // 수정 전에는 결과 맵이 kAllProviderIds 로만 구성되어, CSV 에 들어 있지만
    // 알려진 슬러그가 아닌 토큰이 아무 흔적 없이 버려졌다. 증상은 "로그인
    // 화면에 Google 버튼이 없다" 로만 나타났고 analyze 도 런타임도 조용했다.
    test('정상 CSV 는 해당 슬러그만 true 로 노출한다', () {
      final map = AppConfig.parseEnabledProviders('google,apple');
      expect(map[kProviderIdGoogle], isTrue);
      expect(map[kProviderIdApple], isTrue);
      expect(map[kProviderIdFacebook], isFalse);
      expect(map.keys.toSet(), kAllProviderIds.toSet());
    });

    test('빈 CSV 는 모두 false (D-21 안전 default 유지)', () {
      final map = AppConfig.parseEnabledProviders('');
      for (final id in kAllProviderIds) {
        expect(map[id], isFalse, reason: id);
      }
    });

    test('공백/빈 토큰은 무시된다 (기존 동작 회귀 가드)', () {
      final map = AppConfig.parseEnabledProviders(' google , , apple ,');
      expect(map[kProviderIdGoogle], isTrue);
      expect(map[kProviderIdApple], isTrue);
    });

    test('오타 슬러그는 debug 에서 StateError 로 즉시 드러난다', () {
      expect(
        () => AppConfig.parseEnabledProviders('gogle,apple'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('gogle'), contains('enabledAuthProviders')),
          ),
        ),
      );
    });

    test('대소문자가 다른 슬러그도 미지 슬러그로 검출된다', () {
      expect(
        () => AppConfig.parseEnabledProviders('Google,apple'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Google'),
          ),
        ),
      );
    });

    test('구분자 오타(세미콜론)도 미지 슬러그로 검출된다', () {
      expect(
        () => AppConfig.parseEnabledProviders('google;apple'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('google;apple'),
          ),
        ),
      );
    });

    test('실패 메시지는 알려진 슬러그 목록을 함께 제시한다 (조치 가능성)', () {
      try {
        AppConfig.parseEnabledProviders('gogle');
        fail('미지 슬러그인데 통과했다');
      } on StateError catch (e) {
        for (final id in kAllProviderIds) {
          expect(e.message, contains(id), reason: '알려진 슬러그 $id 가 안내에 없다');
        }
      }
    });

    test('authProviders 는 parseEnabledProviders 와 동일한 결과를 반환한다', () {
      // 테스트 환경은 dart-define 미주입이므로 CSV 가 빈 문자열이다.
      expect(AppConfig.authProviders, AppConfig.parseEnabledProviders(''));
    });
  });

  group('IN-06: functionsRegion — Dart / TS 단일 진실원 정합', () {
    test('dart-define 미주입 시 defaultFunctionsRegion 을 쓴다', () {
      expect(AppConfig.functionsRegion, AppConfig.defaultFunctionsRegion);
      expect(AppConfig.functionsRegion, isNotEmpty);
    });

    test('Dart 기본값이 functions/src/shared/region.ts 의 REGION 과 일치한다', () {
      // 수정 전에는 같은 값이 두 언어에 각각 박혀 있어 한쪽만 바뀌면 런타임
      // callable `not-found` 로만 드러났다. 그 드리프트를 테스트로 잠근다.
      final ts = File('functions/src/shared/region.ts').readAsStringSync();
      final match = RegExp(r'''REGION\s*=\s*["']([^"']+)["']''').firstMatch(ts);
      expect(match, isNotNull, reason: 'region.ts 의 REGION 상수를 찾지 못했다');
      expect(
        AppConfig.defaultFunctionsRegion,
        match!.group(1),
        reason:
            'IN-06: Dart 의 defaultFunctionsRegion 과 TS 의 REGION 이 어긋나면 '
            'Cloud Functions 호출이 not-found 로 실패한다 — 함께 바꿀 것.',
      );
    });

    test('config/*.example.json 이 functionsRegion 키를 노출한다', () {
      for (final flavor in const <String>['dev', 'stg', 'prod']) {
        final file = File('config/$flavor.example.json');
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(
          json.containsKey('functionsRegion'),
          isTrue,
          reason: '$flavor.example.json 에 functionsRegion 키 누락',
        );
        expect(
          json['functionsRegion'],
          AppConfig.defaultFunctionsRegion,
          reason: 'example 은 프로젝트 표준 region 을 그대로 보여야 한다',
        );
      }
    });

    test('firebase_providers.dart 가 region 을 하드코딩하지 않는다 (소스 계약)', () {
      final source = File(
        'lib/core/providers/firebase_providers.dart',
      ).readAsStringSync();
      final codeOnly = source
          .split('\n')
          .where((line) {
            final trimmed = line.trimLeft();
            return !trimmed.startsWith('//') && !trimmed.startsWith('///');
          })
          .join('\n');
      expect(
        codeOnly.contains("region: 'asia-northeast3'"),
        isFalse,
        reason: 'IN-06: region 리터럴이 되살아났다',
      );
      expect(
        codeOnly.contains('region: AppConfig.functionsRegion'),
        isTrue,
        reason: 'IN-06: region 은 AppConfig 를 경유해야 한다',
      );
    });
  });
}
