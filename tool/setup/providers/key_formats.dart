/// 로그인 수단 키 하나의 형식 규칙 — 입력 즉시 검사해 틀리면 그 값만 다시 묻는다.
final class KeyFormat {
  /// 화면 이름 [label] · 정규식 [pattern] · 사용자에게 보일 규칙 [description]
  /// 으로 만든다.
  const KeyFormat({
    required this.label,
    required this.pattern,
    required this.description,
  });

  /// 화면에 보일 값 이름.
  final String label;

  /// 값 전체가 맞아야 하는 정규식(`^…$`).
  final String pattern;

  /// 사용자에게 보일 규칙 한 줄(예: `영숫자 32자`).
  final String description;

  /// [value] 가 규칙에 맞으면 true.
  bool matches(String value) => RegExp(pattern).hasMatch(value);
}

/// Kakao 네이티브 앱 키.
const KeyFormat kakaoNativeAppKey = KeyFormat(
  label: 'Kakao 네이티브 앱 키',
  pattern: r'^[0-9a-f]{32}$',
  description: '소문자 16진수 32자',
);

/// Kakao 어드민 키 — 대소문자를 모두 받는다.
const KeyFormat kakaoAdminKey = KeyFormat(
  label: 'Kakao 어드민 키',
  pattern: r'^[0-9a-fA-F]{32}$',
  description: '16진수 32자',
);

/// Facebook App ID.
const KeyFormat facebookAppId = KeyFormat(
  label: 'Facebook App ID',
  pattern: r'^[0-9]{10,20}$',
  description: '숫자 10 ~ 20자',
);

/// Facebook App Secret — 대소문자를 모두 받는다.
const KeyFormat facebookAppSecret = KeyFormat(
  label: 'Facebook App Secret',
  pattern: r'^[0-9a-fA-F]{32}$',
  description: '16진수 32자',
);

/// Facebook Client Token.
const KeyFormat facebookClientToken = KeyFormat(
  label: 'Facebook Client Token',
  pattern: r'^[0-9a-f]{32}$',
  description: '소문자 16진수 32자',
);

/// Naver Client ID.
const KeyFormat naverClientId = KeyFormat(
  label: 'Naver Client ID',
  pattern: r'^[A-Za-z0-9]{1,40}$',
  description: '영숫자 40자 이하',
);

/// Naver Client Secret.
const KeyFormat naverClientSecret = KeyFormat(
  label: 'Naver Client Secret',
  pattern: r'^[A-Za-z0-9]{1,40}$',
  description: '영숫자 40자 이하',
);

/// Naver URL scheme — 킷은 소문자 영문으로 시작하는 소문자 영문 · 숫자만 쓴다.
const KeyFormat naverUrlScheme = KeyFormat(
  label: 'Naver URL scheme',
  pattern: r'^[a-z][a-z0-9]*$',
  description: '소문자 영문으로 시작하는 소문자 영문 · 숫자',
);

/// LINE Channel ID.
const KeyFormat lineChannelId = KeyFormat(
  label: 'LINE Channel ID',
  pattern: r'^[0-9]{10}$',
  description: '숫자 10자',
);

/// LINE Channel Secret — 영숫자 32자로 받는다.
const KeyFormat lineChannelSecret = KeyFormat(
  label: 'LINE Channel Secret',
  pattern: r'^[0-9A-Za-z]{32}$',
  description: '영숫자 32자',
);

/// Google Web client ID.
///
/// 앞쪽 프로젝트 번호는 자릿수를 고정하지 않는다 — Firebase 가 준 값이라 숫자인지만
/// 보고 뒤쪽 모양(`-<32자>.apps.googleusercontent.com`)을 검사한다.
const KeyFormat googleWebClientId = KeyFormat(
  label: 'Google Web client ID',
  pattern: r'^[0-9]+-[a-z0-9]{32}\.apps\.googleusercontent\.com$',
  description: '<프로젝트 번호(숫자)>-<영숫자 32자>.apps.googleusercontent.com',
);

/// iOS `REVERSED_CLIENT_ID` — 프로젝트 번호 자리는 [googleWebClientId] 와 같다.
const KeyFormat reversedClientId = KeyFormat(
  label: 'REVERSED_CLIENT_ID',
  pattern: r'^com\.googleusercontent\.apps\.[0-9]+-[a-z0-9]{32}$',
  description: 'com.googleusercontent.apps.<프로젝트 번호(숫자)>-<영숫자 32자>',
);

/// Apple Key ID.
const KeyFormat appleKeyId = KeyFormat(
  label: 'Apple Key ID',
  pattern: r'^[A-Z0-9]{10}$',
  description: '대문자 영문 · 숫자 10자',
);

/// Apple Team ID.
const KeyFormat appleTeamId = KeyFormat(
  label: 'Apple Team ID',
  pattern: r'^[A-Z0-9]{10}$',
  description: '대문자 영문 · 숫자 10자',
);

/// Apple Services ID — 점이 하나 이상 있는 reverse-domain 꼴.
const KeyFormat appleServicesId = KeyFormat(
  label: 'Apple Services ID',
  pattern: r'^(?=.*\.)[a-z0-9.-]+$',
  description: '점이 들어간 reverse-domain 꼴(소문자 영문 · 숫자 · 점 · 하이픈)',
);

/// 인증서 SHA-1 지문(콜론을 떼고 소문자로 바꾼 뒤).
const KeyFormat sha1Hex = KeyFormat(
  label: 'SHA-1',
  pattern: r'^[0-9a-f]{40}$',
  description: '소문자 16진수 40자',
);

/// 인증서 SHA-256 지문(콜론을 떼고 소문자로 바꾼 뒤).
const KeyFormat sha256Hex = KeyFormat(
  label: 'SHA-256',
  pattern: r'^[0-9a-f]{64}$',
  description: '소문자 16진수 64자',
);

/// Kakao · Facebook 이 받는 Android 키 해시(SHA-1 의 base64).
const KeyFormat keyHash = KeyFormat(
  label: '키 해시',
  pattern: r'^[A-Za-z0-9+/]{27}=$',
  description: 'base64 28자(= 로 끝남)',
);
