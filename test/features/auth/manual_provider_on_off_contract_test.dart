// 설정 문서(`docs/setup.md`) 「로그인 수단 켜기」 · 「로그인 수단 끄기」 계약.
// 헤딩 · 목차 · 사용자 문서 금지 패턴 · 예시 일치 · 배포 함수 목록 대조.
//
// setup.md 의 절 순서 · 문장을 읽으므로 유지보수자 트리에서만 돈다 — 비공개 작업
// 일지가 없는 트리(공개본 · 킷 사용자 저장소)에서는 최상위 group 이 건너뛰어진다.
//
// T-173-DOCS-01: 「로그인 수단 켜기」 절 헤딩 1개 · 목차 블록 안 항목 1개 · 목차 번호
//   1부터 연속.
// T-173-DOCS-02: 「켜기」 절에 사용자 문서 금지 패턴(`.claude/rules/docs-user-manual.md`
//   §4 표 전체)이 0 건이다.
// T-173-DOCS-03: provider config 키 8개 · xcconfig 변수 8개가 「켜기」 절과 example
//   파일 양쪽에 있다.
// T-173-DOCS-04: manifest 의 함수 이름 · provider secret · provider 토큰 6개가
//   「켜기」 절에 있다.
// T-173-DOCS-05: 「켜기」 절과 「끄기」 절의 `###` 소절이 정한 순서 그대로이고, 끄기 ·
//   iOS 서명 · 심사 4.8 문구와 키를 비운 빌드 확인 명령이 있다.
// T-173-DOCS-06: 「위저드가 채우는 설정 키」 표가 「off 면 비워도 됨」 열과 example 키
//   18개를 한 줄씩 갖고, 표에 금지 패턴이 0 건이며 표 바로 뒤에 「켜기」 절 링크 줄이
//   있다.
// T-173-DOCS-07: provider 추가 · 제거 가이드는 두 가이드에 없고 유지보수자 문서에
//   있으며(현재 구조 토큰 · 플러그인 scheme 기록), 「켜기」 절에 그 문서 링크가 1줄 있다.
// T-173-DOCS-08: 두 가이드 전체에 옛 공유 연결 callable 이름 · 옮긴 절 제목 참조가
//   0 건이고, 새 Kakao 연결 callable 이름이 있다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/planning_docs.dart';
import '../../helpers/source_text.dart';

/// 설정 문서 경로 — 「켜기」 · 「끄기」 절과 설정 키 표가 있다.
const String _setupPath = 'docs/setup.md';

/// 직접 하는 일 문서 경로 — 부재 단언(옛 이름 · 옮긴 절)의 대상에 함께 든다.
const String _guidePath = 'docs/guide.md';

/// 배포 함수 목록(진실원).
const String _manifestPath = 'scripts/functions_manifest.json';

/// config 예시 파일(진실원).
const String _exampleConfigPath = 'config/dev.example.json';

/// xcconfig 예시 파일(진실원).
const String _exampleXcconfigPath = 'ios/Flutter/dev.example.xcconfig';

/// 「켜기」 절 헤딩 (정확히 한 줄).
const String _sectionHeading = '## 로그인 수단 켜기';

/// 「끄기」 절 헤딩.
const String _offSectionHeading = '## 로그인 수단 끄기';

/// 목차 항목 줄 (번호는 목차 위치에 따라 바뀌므로 정규식으로 본다).
final RegExp _tocEntryPattern = RegExp(
  r'^\d+\. \[로그인 수단 켜기\]\(#로그인-수단-켜기\)$',
  multiLine: true,
);

/// 켤 때 값을 넣는 provider config 키 8개.
const List<String> _providerConfigKeys = <String>[
  'googleServerClientId',
  'facebookAppId',
  'facebookClientToken',
  'kakaoNativeAppKey',
  'naverClientId',
  'naverClientSecret',
  'naverUrlScheme',
  'lineChannelId',
];

/// 켤 때 값을 넣는 provider xcconfig 변수 8개.
const List<String> _providerXcconfigVars = <String>[
  'REVERSED_CLIENT_ID',
  'FACEBOOK_APP_ID',
  'FACEBOOK_CLIENT_TOKEN',
  'KAKAO_NATIVE_APP_KEY',
  'NAVER_CLIENT_ID',
  'NAVER_CLIENT_SECRET',
  'NAVER_URL_SCHEME',
  'LINE_CHANNEL_ID',
];

/// provider 함수가 쓰는 secret 이름 목록 — 「켜기」 절 표의 secret 칸에 모두 있다.
const List<String> _providerSecrets = <String>[
  'KAKAO_NATIVE_APP_KEY',
  'KAKAO_ADMIN_KEY',
  'NAVER_CLIENT_ID',
  'NAVER_CLIENT_SECRET',
  'LINE_CHANNEL_ID',
  'LINE_CHANNEL_SECRET',
  'FACEBOOK_APP_ID',
  'FACEBOOK_APP_SECRET',
];

/// `enabledAuthProviders` 에서 쓸 수 있는 토큰 6개.
const List<String> _providerTokens = <String>[
  'google',
  'apple',
  'facebook',
  'kakao',
  'naver',
  'line',
];

/// 「켜기」 절의 `###` 소절 — 공통 소절 · 수단별 소절 · 서명 권한 · 이메일 받기 순서.
const List<String> _subsectionHeadings = <String>[
  '### 켜는 순서와 수단별로 필요한 것',
  '### Google 로그인 켜기',
  '### Apple 로그인 켜기',
  '### Facebook 로그인 켜기',
  '### Kakao 로그인 켜기',
  '### Naver 로그인 켜기',
  '### LINE 로그인 켜기',
  '### Kakao · Naver · LINE 서명 권한(Token Creator)',
  '### 로그인 수단에서 이메일 받기',
];

/// 「끄기」 절의 `###` 소절 — 확인 · 되돌리기 · iOS 서명 · 심사 4.8 순서.
const List<String> _offSubsectionHeadings = <String>[
  '### 확인 방법',
  '### 되돌리기',
  '### iOS 서명 — Apple 을 꺼도 필요한 capability',
  '### App Store 심사 4.8 (Login Services) 주의',
];

/// 키를 비운 빌드 확인 명령 · 성공 줄이 있는 문제 해결 소절 헤딩.
const String _otherProblemsHeading = '### 그 밖의 문제';

/// [_otherProblemsHeading] 소절에 있어야 하는 키를 비운 빌드 확인 명령 · 성공 줄.
const List<String> _placeholderBuildPhrases = <String>[
  'bash scripts/verify_placeholder_builds.sh <android|ios> <dev|stg|prod> [off|google|all]',
  'PLACEHOLDER-BUILD-OK <platform> <flavor> <case>',
];

/// 「끄기」 절에 있어야 하는 끄기 · iOS 서명 · 심사 4.8 · Kill Switch 문구.
const List<String> _requiredSectionPhrases = <String>[
  'Sign in with Apple capability',
  '자동 서명이면 Xcode 가 켠다',
  'com.apple.developer.applesignin',
  '시뮬레이터 빌드에는 영향이 없다',
  'Apps that use a third-party or social login service (such as Facebook Login, Google Sign-In, Log in with X, Sign In with LinkedIn, Login with Amazon, or WeChat Login) to set up or authenticate the user',
  'the login service limits data collection to the user',
  'https://developer.apple.com/app-store/review/guidelines/#login-services',
  '[Kill Switch 로 로그인 수단 막기](guide.md#kill-switch-로-로그인-수단-막기)',
  '로그인 · 재인증 · 회원탈퇴를 할 수 없다',
];

/// 설정 키 표가 있는 소절 헤딩.
const String _keyTableHeading = '### 위저드가 채우는 설정 키';

/// 설정 키 표 헤더 줄.
const String _keyTableHeader = '| 키 | 값 출처 | off 면 비워도 됨 | 비고 |';

/// 설정 키 표 바로 뒤의 「켜기」 절 링크 줄.
const String _keyTableLinkLine =
    '끈 provider 의 키는 비워 둬도 된다 — 무엇을 켤 때 무엇이 필요한지는 '
    '[로그인 수단 켜기](#로그인-수단-켜기).';

/// 유지보수자 문서 경로(provider 추가 · 제거 가이드).
const String _maintainerDocPath =
    'docs/maintainer/custom-token-provider-add-remove.md';

/// 「켜기」 절에서 유지보수자 문서를 가리키는 상대 링크 조각.
const String _maintainerDocLink =
    '](maintainer/custom-token-provider-add-remove.md)';

/// 유지보수자 문서로 옮긴 두 가이드 절의 제목(헤딩 · 목차 항목에 나오면 안 된다).
const List<String> _movedGuideTitles = <String>[
  'Custom Token Provider 추가 가이드 (stub)',
  'Custom Token Provider 제거 가이드 (Phase 16.6)',
];

/// 유지보수자 문서에 있어야 하는 현재 구조 토큰
/// (연결 팩토리 · 배포 함수 목록 · 초기화 표 · 자리표시 scheme · 플러그인 scheme).
const List<String> _maintainerDocTokens = <String>[
  'buildLinkOidcProviderCallable',
  'scripts/functions_manifest.json',
  'buildProviderSdkInits',
  ':default=unset.',
  'naver3rdpartylogin',
];

/// 두 가이드에서 옮긴 절을 가리키면 안 되는 제목 조각(번호 · 괄호 꼬리 없이).
const List<String> _movedGuideTitleStems = <String>[
  'Custom Token Provider 제거 가이드',
  'Custom Token Provider 추가 가이드',
];

/// 옛 공유 연결 callable 이름 조각 — 이어 붙여야 이름이 된다(리터럴 0).
const List<String> _legacyCallableParts = <String>[
  'linkCustom',
  'Token',
  'Provider',
];

/// 옛 공유 연결 callable 이름을 세는 정규식을 만든다.
///
/// 해제 callable(이름 앞에 `un`)과 클라이언트 arm(이름 뒤에 `Arm`)은 다른
/// 식별자라 세지 않는다.
RegExp _buildLegacyCallablePattern() {
  final String legacyCallable = _legacyCallableParts.join();
  return RegExp('(^|[^n])$legacyCallable([^A]|\$)', multiLine: true);
}

void main() {
  final String setup = readTrackedFile(_setupPath);
  final String guide = readTrackedFile(_guidePath);
  final String section = sliceMarkdownSection(
    setup,
    _sectionHeading,
    maxLevel: 2,
  );
  final String offSection = sliceMarkdownSection(
    setup,
    _offSectionHeading,
    maxLevel: 2,
  );
  final manifest =
      jsonDecode(readTrackedFile(_manifestPath)) as Map<String, Object?>;
  final exampleConfig =
      jsonDecode(readTrackedFile(_exampleConfigPath)) as Map<String, Object?>;
  final String exampleXcconfig = readTrackedFile(_exampleXcconfigPath);

  group('설정 문서 「로그인 수단 켜기 · 끄기」 계약 (T-173-DOCS)', () {
    test('T-173-DOCS-01: 절 헤딩 1개 · 목차 항목 1개 · 목차 번호가 1부터 연속이다', () {
      expect(
        countExactLines(setup, _sectionHeading),
        1,
        reason: '절 헤딩이 없거나 중복이다',
      );

      final String toc = sliceTocBlock(setup);
      expect(toc.trim(), isNotEmpty, reason: '목차 블록을 찾지 못했다');
      expect(
        _tocEntryPattern.allMatches(toc).length,
        1,
        reason: '목차 블록 안 「로그인 수단 켜기」 항목이 없거나 중복이다',
      );

      final List<int> numbers = RegExp(
        r'^(\d+)\. ',
        multiLine: true,
      ).allMatches(toc).map((RegExpMatch m) => int.parse(m.group(1)!)).toList();
      expect(numbers, isNotEmpty, reason: '목차 번호 줄이 없다');
      expect(
        numbers,
        List<int>.generate(numbers.length, (int i) => i + 1),
        reason: '목차 번호가 1부터 빠짐없이 이어지지 않는다',
      );
    });

    test('T-173-DOCS-02: 절에 사용자 문서 금지 패턴이 0 건이다', () {
      expect(section.trim(), isNotEmpty, reason: '절 슬라이스가 비었다');
      final List<String> hits = RegExp(
        kUserDocForbiddenPatternSource,
      ).allMatches(section).map((RegExpMatch m) => m.group(0)!).toList();
      expect(hits, isEmpty, reason: '금지 패턴이 절에 있다: $hits');
    });

    test('T-173-DOCS-03: 키 · 변수가 절과 example 파일 양쪽에 있다', () {
      // 키 값은 위저드가 기록한다 — 절에 손으로 붙여 넣는 JSON 예시가 없으므로 예시
      // 값 대조는 하지 않는다.
      for (final String key in _providerConfigKeys) {
        expect(section, contains('`$key`'), reason: '절에 config 키 $key 가 없다');
        expect(
          exampleConfig.containsKey(key),
          isTrue,
          reason: '$_exampleConfigPath 에 $key 가 없다',
        );
      }

      for (final String name in _providerXcconfigVars) {
        expect(
          section,
          contains('`$name`'),
          reason: '절에 xcconfig 변수 $name 이 없다',
        );
        expect(
          RegExp('^$name\\s*=', multiLine: true).hasMatch(exampleXcconfig),
          isTrue,
          reason: '$_exampleXcconfigPath 에 $name 이 없다',
        );
      }
    });

    test('T-173-DOCS-04: 배포 함수 · secret · 토큰이 절에 있다', () {
      final providers = manifest['providers']! as Map<String, Object?>;
      final providerFunctions = <String>[
        for (final Object? list in providers.values)
          ...(list! as List<Object?>).cast<String>(),
      ];
      expect(
        providerFunctions,
        isNotEmpty,
        reason: 'manifest 의 provider 함수를 읽지 못했다(양성 대조)',
      );
      final List<String> commonFunctions =
          (manifest['common']! as List<Object?>).cast<String>();
      for (final name in <String>[...providerFunctions, ...commonFunctions]) {
        expect(
          section,
          contains('`$name`'),
          reason: 'manifest 의 함수 $name 이 절에 없다',
        );
      }

      for (final String secret in _providerSecrets) {
        expect(section, contains(secret), reason: '절에 secret $secret 이 없다');
      }

      // secret 은 위저드가 등록하고 함수는 위저드가 배포한다 — 문서에 secret 을 미리
      // 만드는 셸 명령과 수동 배포 명령이 없으므로 그 줄은 대조하지 않는다.

      expect(
        providers.keys.toList(),
        _providerTokens,
        reason: 'manifest providers 키가 토큰 목록과 다르다',
      );
      for (final String token in _providerTokens) {
        expect(section, contains('`$token`'), reason: '절에 토큰 $token 이 없다');
      }
    });

    test('T-173-DOCS-05: 두 절의 소절 순서 · 끄기 · iOS 서명 · 심사 4.8 · 빌드 확인 문구', () {
      expect(
        linesStartingWith(section, '### '),
        _subsectionHeadings,
        reason: '「켜기」 절의 ### 소절이 정한 순서 9개와 다르다',
      );

      expect(offSection.trim(), isNotEmpty, reason: '「끄기」 절을 찾지 못했다');
      expect(
        linesStartingWith(offSection, '### '),
        _offSubsectionHeadings,
        reason: '「끄기」 절의 ### 소절이 정한 순서 4개와 다르다',
      );

      final String otherProblems = sliceMarkdownSection(
        setup,
        _otherProblemsHeading,
        maxLevel: 3,
      );
      expect(
        otherProblems.trim(),
        isNotEmpty,
        reason: '「$_otherProblemsHeading」 소절을 찾지 못했다',
      );
      for (final String phrase in _placeholderBuildPhrases) {
        expect(
          otherProblems,
          contains(phrase),
          reason: '「$_otherProblemsHeading」 소절에 「$phrase」 가 없다',
        );
      }

      for (final String phrase in _requiredSectionPhrases) {
        expect(offSection, contains(phrase), reason: '「끄기」 절에 「$phrase」 가 없다');
      }
    });

    test('T-173-DOCS-06: 설정 키 표 · off 열 · 금지 패턴 0 · 링크 줄', () {
      final String keySection = sliceMarkdownSection(
        setup,
        _keyTableHeading,
        maxLevel: 3,
      );
      expect(
        keySection.trim(),
        isNotEmpty,
        reason: '「$_keyTableHeading」 소절을 찾지 못했다',
      );
      expect(
        countExactLines(keySection, _keyTableHeader),
        1,
        reason: '「off 면 비워도 됨」 열이 있는 키 표 헤더가 없거나 중복이다',
      );

      final List<String> table = collectTableLines(keySection, _keyTableHeader);
      final List<String> keys = exampleConfig.keys
          .where((String key) => key != 'flavor')
          .toList();
      expect(keys, hasLength(18), reason: 'example 키 수(flavor 제외)가 18 이 아니다');
      for (final key in keys) {
        expect(
          table.where((String line) => line.startsWith('| `$key` |')).length,
          1,
          reason: '키 표에 $key 행이 없거나 중복이다',
        );
      }

      final List<String> hits = RegExp(kUserDocForbiddenPatternSource)
          .allMatches(table.join('\n'))
          .map((RegExpMatch m) => m.group(0)!)
          .toList();
      expect(hits, isEmpty, reason: '키 표에 금지 패턴이 있다: $hits');

      final List<String> keySectionLines = keySection.split('\n');
      final int afterTable =
          keySectionLines.indexOf(_keyTableHeader) + table.length + 1;
      expect(
        afterTable < keySectionLines.length ? keySectionLines[afterTable] : '',
        _keyTableLinkLine,
        reason: '키 표 바로 뒤(빈 줄 다음)에 「켜기」 절 링크 줄이 없다',
      );
      expect(
        countExactLines(keySection, _keyTableLinkLine),
        1,
        reason: '「켜기」 절 링크 줄이 없거나 중복이다',
      );
    });

    test('T-173-DOCS-07: 추가 · 제거 가이드는 유지보수자 문서에만 있고 「켜기」 절에 링크 1줄', () {
      final RegExp legacyPattern = _buildLegacyCallablePattern();
      // 양성 대조: 정규식이 옛 이름은 잡고 해제 callable · arm 이름은 잡지 않는다.
      final String legacyCallable = _legacyCallableParts.join();
      expect(legacyPattern.hasMatch('`$legacyCallable`'), isTrue);
      expect(legacyPattern.hasMatch('`un$legacyCallable`'), isFalse);
      expect(legacyPattern.hasMatch('`${legacyCallable}Arm`'), isFalse);

      final docs = <String, String>{_setupPath: setup, _guidePath: guide};
      for (final MapEntry<String, String> doc in docs.entries) {
        final String toc = sliceTocBlock(doc.value);
        expect(toc.trim(), isNotEmpty, reason: '${doc.key} 목차 블록을 찾지 못했다');
        for (final String title in _movedGuideTitles) {
          expect(
            countExactLines(doc.value, '## $title'),
            0,
            reason: '${doc.key} 에 옮긴 절 헤딩 「$title」 이 있다',
          );
          expect(
            countOccurrences(toc, '[$title]('),
            0,
            reason: '${doc.key} 목차에 옮긴 절 항목 「$title」 이 있다',
          );
        }
      }

      expect(
        countOccurrences(section, _maintainerDocLink),
        1,
        reason: '「켜기」 절에 유지보수자 문서 링크가 없거나 중복이다',
      );

      final String maintainerDoc = readTrackedFile(_maintainerDocPath);
      for (final heading in <String>['## 추가 가이드', '## 제거 가이드']) {
        expect(
          countExactLines(maintainerDoc, heading),
          1,
          reason: '유지보수자 문서에 「$heading」 헤딩이 없거나 중복이다',
        );
      }
      for (final String token in _maintainerDocTokens) {
        expect(
          maintainerDoc,
          contains(token),
          reason: '유지보수자 문서에 현재 구조 토큰 「$token」 이 없다',
        );
      }
      expect(
        legacyPattern.allMatches(maintainerDoc).length,
        0,
        reason: '유지보수자 문서에 옛 공유 연결 callable 이름이 있다',
      );
    });

    test(
      'T-173-DOCS-08: 두 가이드에 옛 연결 callable · 옮긴 절 참조 0 · 새 연결 callable 이름 있음',
      () {
        // 두 가이드에는 이력 절이 없다 — 파일 전체가 본문이다.
        final body = '$setup\n$guide';
        // 양성 대조: 본문이 「켜기」 절을 포함한다.
        expect(countOccurrences(body, '$_sectionHeading\n'), 1);

        expect(
          _buildLegacyCallablePattern().allMatches(body).length,
          0,
          reason: '두 가이드에 옛 공유 연결 callable 이름이 있다',
        );
        for (final String stem in _movedGuideTitleStems) {
          expect(
            countOccurrences(body, stem),
            0,
            reason: '두 가이드가 옮긴 절 「$stem」 을 가리킨다',
          );
        }
        expect(
          countOccurrences(body, 'linkKakaoProvider'),
          greaterThanOrEqualTo(1),
          reason: '두 가이드에 새 Kakao 연결 callable 이름이 없다',
        );

        // 연결 · 해제 함수는 위저드가 배포한다 — 문서에 손 배포 단위 머리 줄이 없으므로
        // 그 줄은 대조하지 않는다.
      },
    );
  }, skip: skipUnlessMaintainerTree());
}
