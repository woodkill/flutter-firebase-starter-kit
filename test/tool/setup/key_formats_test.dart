import 'package:test/test.dart';

import '../../../tool/setup/providers/key_formats.dart';

// 키 모양 문자열은 tracked 소스에 완형으로 두지 않는다 — 맞는 예 · 틀린 예는
// 모두 실행 시점에 조각을 이어 만든다.

/// [format] 이 [valid] 를 모두 받고 [invalid] 를 모두 거르는지 단언한다.
///
/// 틀린 예는 길이 ± 1 · 허용 밖 문자처럼 두 가지 이상을 요구한다.
void expectFormat(
  KeyFormat format, {
  required List<String> valid,
  required List<String> invalid,
}) {
  expect(format.label, isNotEmpty);
  expect(format.description, isNotEmpty);
  expect(valid, isNotEmpty);
  expect(invalid.length, greaterThanOrEqualTo(2));
  for (final value in valid) {
    expect(format.matches(value), isTrue, reason: '맞는 예: $value');
  }
  for (final value in invalid) {
    expect(format.matches(value), isFalse, reason: '틀린 예: $value');
  }
}

/// 소문자 16진수 [length] 자를 만든다.
String buildLowerHex(int length) =>
    ('0a1b2c3d4e5f6789' * 8).substring(0, length);

/// 대소문자가 섞인 16진수 [length] 자를 만든다.
String buildMixedHex(int length) => ('0aB1cD2eF3' * 8).substring(0, length);

/// 대소문자 영문 · 숫자가 섞인 [length] 자를 만든다.
String buildAlnum(int length) => ('aZ09bY18cX27' * 8).substring(0, length);

/// 대문자 영문 · 숫자가 섞인 [length] 자를 만든다.
String buildUpperAlnum(int length) => ('A1B2C3D4E5' * 4).substring(0, length);

/// Google client ID 의 앞 숫자 [digits] 자와 뒤 영숫자 [suffix] 자를 이은 몸통.
String buildClientIdBody({int digits = 12, int suffix = 32}) =>
    '${'1' * digits}-${('a1b2c3' * 8).substring(0, suffix)}';

/// base64 문자 [length] 자를 만든다.
String buildBase64(int length) => ('aB3+/zY9' * 6).substring(0, length);

void main() {
  test('T-20-FMT-01: Kakao 네이티브 앱 키는 소문자 16진수 32자', () {
    expectFormat(
      kakaoNativeAppKey,
      valid: <String>[buildLowerHex(32)],
      invalid: <String>[
        buildLowerHex(31),
        buildLowerHex(33),
        buildMixedHex(32),
        'g' * 32,
      ],
    );
  });

  test('T-20-FMT-02: Kakao 어드민 키는 대소문자 16진수 32자', () {
    expectFormat(
      kakaoAdminKey,
      valid: <String>[buildMixedHex(32), buildLowerHex(32)],
      invalid: <String>[buildMixedHex(31), buildMixedHex(33), 'g' * 32],
    );
  });

  test('T-20-FMT-03: Facebook App ID 는 숫자 10 ~ 20자', () {
    expectFormat(
      facebookAppId,
      valid: <String>['1' * 10, '1' * 16, '1' * 20],
      invalid: <String>['1' * 9, '1' * 21, '${'1' * 15}a'],
    );
  });

  test('T-20-FMT-04: Facebook App Secret 은 대소문자 16진수 32자', () {
    expectFormat(
      facebookAppSecret,
      valid: <String>[buildMixedHex(32)],
      invalid: <String>[buildMixedHex(31), buildMixedHex(33), 'z' * 32],
    );
  });

  test('T-20-FMT-05: Facebook Client Token 은 소문자 16진수 32자', () {
    expectFormat(
      facebookClientToken,
      valid: <String>[buildLowerHex(32)],
      invalid: <String>[buildLowerHex(31), buildLowerHex(33), 'F' * 32],
    );
  });

  test('T-20-FMT-06: Naver Client ID 는 영숫자 1 ~ 40자', () {
    expectFormat(
      naverClientId,
      valid: <String>['a', buildAlnum(20), buildAlnum(40)],
      invalid: <String>['', buildAlnum(41), 'ab_cd', 'ab-cd'],
    );
  });

  test('T-20-FMT-07: Naver Client Secret 은 영숫자 1 ~ 40자', () {
    expectFormat(
      naverClientSecret,
      valid: <String>['Z', buildAlnum(10), buildAlnum(40)],
      invalid: <String>['', buildAlnum(41), 'ab cd'],
    );
  });

  test('T-20-FMT-08: Naver URL scheme 은 소문자로 시작하는 소문자 · 숫자만', () {
    expectFormat(
      naverUrlScheme,
      valid: <String>['a', 'kitlogin', 'kitlogin2'],
      invalid: <String>['', 'Kitlogin', 'kit_login', 'kit-login', '2kit'],
    );
  });

  test('T-20-FMT-09: LINE Channel ID 는 숫자 10자', () {
    expectFormat(
      lineChannelId,
      valid: <String>['1' * 10],
      invalid: <String>['1' * 9, '1' * 11, '${'1' * 9}a'],
    );
  });

  test('T-20-FMT-10: LINE Channel Secret 은 영숫자 32자', () {
    expectFormat(
      lineChannelSecret,
      valid: <String>[buildAlnum(32)],
      invalid: <String>[buildAlnum(31), buildAlnum(33), '${buildAlnum(31)}_'],
    );
  });

  test('T-20-FMT-11: Google Web client ID 는 숫자 12자-영숫자 32자.apps 주소', () {
    const domain = '.apps.googleusercontent.com';
    expectFormat(
      googleWebClientId,
      valid: <String>['${buildClientIdBody()}$domain'],
      invalid: <String>[
        '${buildClientIdBody(digits: 11)}$domain',
        '${buildClientIdBody(digits: 13)}$domain',
        '${buildClientIdBody(suffix: 31)}$domain',
        '${buildClientIdBody(suffix: 33)}$domain',
        '${'1' * 12}-${'A' * 32}$domain',
        '${buildClientIdBody()}.apps.example.com',
      ],
    );
  });

  test('T-20-FMT-12: REVERSED_CLIENT_ID 는 com.googleusercontent.apps 로 시작', () {
    const prefix = 'com.googleusercontent.apps.';
    expectFormat(
      reversedClientId,
      valid: <String>['$prefix${buildClientIdBody()}'],
      invalid: <String>[
        '$prefix${buildClientIdBody(digits: 11)}',
        '$prefix${buildClientIdBody(suffix: 33)}',
        '$prefix${'1' * 12}-${'A' * 32}',
        buildClientIdBody(),
      ],
    );
  });

  test('T-20-FMT-13: Apple Key ID 는 대문자 영문 · 숫자 10자', () {
    expectFormat(
      appleKeyId,
      valid: <String>[buildUpperAlnum(10)],
      invalid: <String>[
        buildUpperAlnum(9),
        buildUpperAlnum(11),
        buildUpperAlnum(10).toLowerCase(),
      ],
    );
  });

  test('T-20-FMT-14: Apple Team ID 는 대문자 영문 · 숫자 10자', () {
    expectFormat(
      appleTeamId,
      valid: <String>[buildUpperAlnum(10), '9' * 10],
      invalid: <String>[
        buildUpperAlnum(9),
        buildUpperAlnum(11),
        '${buildUpperAlnum(9)}-',
      ],
    );
  });

  test('T-20-FMT-15: Apple Services ID 는 점이 든 소문자 reverse-domain 꼴', () {
    expectFormat(
      appleServicesId,
      valid: <String>['com.example.app.signin', 'com.example-app.web'],
      invalid: <String>[
        '',
        'comexampleapp',
        'com.Example.app',
        'com.example_app',
      ],
    );
  });

  test('T-20-FMT-16: SHA-1 은 소문자 16진수 40자', () {
    expectFormat(
      sha1Hex,
      valid: <String>[buildLowerHex(40)],
      invalid: <String>[
        buildLowerHex(39),
        buildLowerHex(41),
        buildLowerHex(40).toUpperCase(),
        '${buildLowerHex(38)}:a',
      ],
    );
  });

  test('T-20-FMT-17: SHA-256 은 소문자 16진수 64자', () {
    expectFormat(
      sha256Hex,
      valid: <String>[buildLowerHex(64)],
      invalid: <String>[
        buildLowerHex(63),
        buildLowerHex(65),
        buildLowerHex(64).toUpperCase(),
      ],
    );
  });

  test('T-20-FMT-18: 키 해시는 = 로 끝나는 base64 28자', () {
    expectFormat(
      keyHash,
      valid: <String>['${buildBase64(27)}='],
      invalid: <String>[
        '${buildBase64(26)}=',
        '${buildBase64(28)}=',
        buildBase64(28),
        '${buildBase64(26)}-=',
      ],
    );
  });
}
