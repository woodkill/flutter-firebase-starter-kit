import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/uuid.dart';

/// UUID4 소문자 모양(버전 4 · variant 10).
final RegExp uuidV4Shape = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  test(
    'T-19-UUID-01 generateUuidV4 는 버전 4 · variant 10 소문자 8-4-4-4-12 를 만든다',
    () {
      final String value = generateUuidV4(Random(1));

      expect(uuidV4Shape.hasMatch(value), isTrue, reason: value);
      expect(generateUuidV4(Random(1)), value);
    },
  );

  test('T-19-UUID-02 Random.secure() 로 1000번 만들면 중복이 없다', () {
    final random = Random.secure();
    final values = <String>{
      for (int i = 0; i < 1000; i++) generateUuidV4(random),
    };

    expect(values, hasLength(1000));
    expect(values.every(uuidV4Shape.hasMatch), isTrue);
  });

  test('T-19-UUID-03 isUuidV4 는 대문자도 받고 버전 1 · 빈 값 · 자리표시는 거부한다', () {
    final String value = generateUuidV4(Random(2));

    expect(isUuidV4(value), isTrue);
    expect(isUuidV4(value.toUpperCase()), isTrue);
    expect(isUuidV4('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), isFalse);
    expect(isUuidV4(''), isFalse);
    expect(isUuidV4('YOUR_APP_CHECK_DEBUG_TOKEN'), isFalse);
    expect(isUuidV4(' $value'), isFalse);
    expect(isUuidV4('${value}0'), isFalse);
  });
}
