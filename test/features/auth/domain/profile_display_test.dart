import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/features/auth/domain/profile_display.dart';

/// Phase 17 D-27 — [resolveProfileValue] 표시 규칙 단위 테스트.
///
/// 순서 = top-level → 가입 수단 항목 → 첫 비어 있지 않은 값 → null.
/// 빈 문자열은 값이 없는 것으로 본다.
void main() {
  const providerValues = <(String, String?)>[
    ('facebook.com', 'F'),
    ('google.com', 'G'),
  ];

  group('T-17-PROFILE-03 resolveProfileValue (D-27)', () {
    test('T-17-PROFILE-03 top-level 이 비면 가입 수단 항목 값', () {
      expect(
        resolveProfileValue(
          topLevel: '',
          providerValues: providerValues,
          signUpProviderId: 'google.com',
        ),
        'G',
      );
    });

    test('T-17-PROFILE-03 top-level 값이 있으면 top-level', () {
      expect(
        resolveProfileValue(
          topLevel: 'T',
          providerValues: providerValues,
          signUpProviderId: 'google.com',
        ),
        'T',
      );
    });

    test('T-17-PROFILE-03 가입 수단 항목이 빈 문자열이면 첫 비어 있지 않은 값', () {
      expect(
        resolveProfileValue(
          topLevel: null,
          providerValues: const <(String, String?)>[
            ('google.com', ''),
            ('facebook.com', 'F'),
          ],
          signUpProviderId: 'google.com',
        ),
        'F',
      );
    });

    test('T-17-PROFILE-03 모든 값이 비면 null', () {
      expect(
        resolveProfileValue(
          topLevel: '',
          providerValues: const <(String, String?)>[
            ('google.com', ''),
            ('facebook.com', null),
          ],
          signUpProviderId: 'google.com',
        ),
        isNull,
      );
      expect(
        resolveProfileValue(
          topLevel: null,
          providerValues: const <(String, String?)>[],
          signUpProviderId: null,
        ),
        isNull,
      );
    });

    test('T-17-PROFILE-03 signUpProviderId 가 null 이면 첫 값', () {
      expect(
        resolveProfileValue(
          topLevel: null,
          providerValues: providerValues,
          signUpProviderId: null,
        ),
        'F',
      );
    });

    test('T-17-PROFILE-03 가입 수단 항목이 providerData 에 없으면 첫 값', () {
      // Custom Token 가입(kakao 등)은 providerData 에 항목이 없다.
      expect(
        resolveProfileValue(
          topLevel: null,
          providerValues: providerValues,
          signUpProviderId: 'kakao',
        ),
        'F',
      );
    });
  });
}
