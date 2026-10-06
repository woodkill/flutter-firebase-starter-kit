// 배포 함수 목록(scripts/functions_manifest.json)의 provider 키는 앱의 provider
// 등록 목록과 같아야 한다 (Phase 17.3 D-08 — see ROADMAP.md). functions 쪽 export
// 대조는 functions/test/deploy_manifest.test.ts.
//
// `scripts/deploy_functions.sh` 는 config 의 `enabledAuthProviders` CSV 토큰을
// manifest 의 provider 키로만 받는다. 앱이 provider 를 더하거나 빼고 manifest 를
// 그대로 두면, 켠 provider 가 배포 스크립트에서 「알 수 없는 provider」 로 거부되거나
// 끈 provider 의 함수 묶음이 manifest 에 남는다. 그래서 키 목록(순서 포함)을
// [kAllProviderIds] 에 고정한다.
//
// **tracked 파일만 읽는다** — manifest 는 키 · secret 값이 없는 tracked 파일이다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';

import '../../helpers/source_text.dart';

void main() {
  group('배포 함수 manifest 계약 (Phase 17.3 D-08)', () {
    test(
      'T-173-DEPLOY-04: manifest provider 키 == kAllProviderIds (순서) · 함수 이름 중복 0',
      () {
        final Object? decoded = jsonDecode(
          readTrackedFile('scripts/functions_manifest.json'),
        );
        expect(decoded, isA<Map<String, Object?>>());
        final Map<String, Object?> manifest = decoded! as Map<String, Object?>;

        final Object? providersRaw = manifest['providers'];
        expect(providersRaw, isA<Map<String, Object?>>());
        final Map<String, Object?> providers =
            providersRaw! as Map<String, Object?>;

        expect(
          providers.keys.toList(),
          kAllProviderIds,
          reason:
              'scripts/functions_manifest.json 의 providers 키(순서 포함)가 '
              'kAllProviderIds 와 다르다 — provider 를 더하거나 뺐다면 manifest 도 '
              '같이 고친다',
        );

        final List<String> names = <String>[
          ..._readNames(manifest['common'], 'common'),
          for (final MapEntry<String, Object?> entry in providers.entries)
            ..._readNames(entry.value, 'providers.${entry.key}'),
        ];
        // 공통 함수는 항상 배포되므로 비어 있으면 manifest 가 깨진 것이다(양성 대조).
        expect(names, isNotEmpty);
        expect(
          names.toSet().length,
          names.length,
          reason: '같은 함수 이름이 manifest 에 두 번 이상 나온다: $names',
        );
      },
    );
  });
}

/// manifest 의 함수 이름 배열 [raw] 를 문자열 목록으로 돌려준다.
///
/// 배열이 아니거나 문자열이 아닌 원소가 있으면 [label] 을 알리며 테스트를
/// 실패시킨다.
List<String> _readNames(Object? raw, String label) {
  if (raw is! List<Object?>) {
    fail('manifest 의 $label 이 배열이 아니다');
  }
  return <String>[
    for (final Object? name in raw)
      if (name is String)
        name
      else
        fail('manifest 의 $label 에 문자열이 아닌 값: $name'),
  ];
}
