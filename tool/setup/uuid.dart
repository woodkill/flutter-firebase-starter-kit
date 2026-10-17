import 'dart:math';

/// UUID 버전 4 모양(대소문자 무관) — 버전 자리 `4` · variant 자리 `8`~`b`.
final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-'
  r'[0-9a-fA-F]{12}$',
);

/// [random] 으로 16바이트를 만들어 UUID 버전 4 문자열(소문자 8-4-4-4-12)을 만든다.
///
/// 비밀 값으로 쓸 때는 `Random.secure()` 를 넘긴다. 외부 프로세스를 부르지 않는다.
String generateUuidV4(Random random) {
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  // 버전 4 와 variant 10 비트를 정해진 자리에 둔다.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final String hex = bytes
      .map((int value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// [value] 가 UUID 버전 4 모양이면 true — 대문자도 받는다.
bool isUuidV4(String value) => _uuidV4Pattern.hasMatch(value);
