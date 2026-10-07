// 매뉴얼 「로그인 수단 켜고 끄기」 계약 (Phase 17.3 D-11 — see ROADMAP.md).
// 헤딩 · 목차 · 사용자 문서 금지 패턴 · 예시 일치 · 배포 함수 목록 대조.
//
// T-173-DOCS-01: 절 헤딩 1개 · 목차 블록 안 항목 1개 · 목차 번호 0부터 연속.
// T-173-DOCS-02: 절에 사용자 문서 금지 패턴(`.claude/rules/docs-user-manual.md`
//   §4 표 전체)이 0 건이다.
// T-173-DOCS-03: 절의 JSON 예시 값 == example 파일 값(enabledAuthProviders 제외) ·
//   provider config 키 8개 · xcconfig 변수 8개가 절과 example 파일 양쪽에 있다.
// T-173-DOCS-04: manifest 의 함수 이름 · provider secret · 배포 명령 2줄 ·
//   provider 토큰 6개가 절에 있고, 「켜기」 ④ 반복문의 secret 이름 집합이 provider
//   secret 목록과 같다.
// T-173-DOCS-05: 절의 `###` 소절 8개가 절 템플릿 순서 그대로이고, 확인 방법 ·
//   끄기 · iOS 서명 · 심사 4.8 문구가 있다.
// T-173-DOCS-06: Initial Setup 키 표가 「off 면 비워도 됨」 열과 example 키 14개를
//   한 줄씩 갖고, 표에 금지 패턴이 0 건이며 표 바로 뒤에 새 절 링크 줄이 있다.
// T-173-DOCS-07: provider 추가 · 제거 가이드가 매뉴얼에서 빠져 유지보수자 문서로
//   옮겨졌고(현재 구조 토큰 · 플러그인 scheme 기록), 새 절에 그 문서 링크가 1줄 있다.
// T-173-DOCS-08: 변경 이력 앞 본문에 옛 공유 연결 callable 이름 · 옮긴 절 제목 참조가
//   0 건이고, 계정 연결 · 해제 절의 고친 단위 머리 줄 5개가 각각 1줄이며 금지 패턴 0 건이다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/source_text.dart';

/// 매뉴얼 경로.
const String _manualPath = 'docs/manual.md';

/// 배포 함수 목록(진실원).
const String _manifestPath = 'scripts/functions_manifest.json';

/// config 예시 파일(진실원).
const String _exampleConfigPath = 'config/dev.example.json';

/// xcconfig 예시 파일(진실원).
const String _exampleXcconfigPath = 'ios/Flutter/dev.example.xcconfig';

/// 절 헤딩 (정확히 한 줄).
const String _sectionHeading = '## 로그인 수단 켜고 끄기';

/// 목차 항목 줄 (번호는 목차 위치에 따라 바뀌므로 정규식으로 본다).
final RegExp _tocEntryPattern = RegExp(
  r'^\d+\. \[로그인 수단 켜고 끄기\]\(#로그인-수단-켜고-끄기\)$',
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

/// provider 함수가 쓰는 secret 이름 목록 — 「켜기」 ④ 반복문과 집합이 같아야 한다
/// (`functions/test/deploy_manifest.test.ts` T-173-DEPLOY-15 가 소유 맵 ·
/// `functions/src` 의 `defineSecret` 선언 · 같은 반복문을 대조한다).
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

/// 절에 줄 단위로 있어야 하는 배포 명령 2줄.
const List<String> _deployCommandLines = <String>[
  'bash scripts/deploy_functions.sh dev',
  'bash scripts/deploy_functions.sh dev --apply',
];

/// 「켜기」 ④ secret 반복문의 `for s in … ; do` 머리(이름은 줄 이음 `\` 을 넘어
/// 이어진다).
final RegExp _secretLoopPattern = RegExp(
  r'^for s in ([\s\S]*?); do$',
  multiLine: true,
);

/// `enabledAuthProviders` 에서 쓸 수 있는 토큰 6개.
const List<String> _providerTokens = <String>[
  'google',
  'apple',
  'facebook',
  'kakao',
  'naver',
  'line',
];

/// 절의 JSON 예시 `"<key>": "<value>"` 쌍.
final RegExp _jsonPairPattern = RegExp(r'"([A-Za-z]+)":\s*"([^"]*)"');

/// 절의 `###` 소절 — 절 템플릿(언제 · 전제 · 단계 · 확인 · 문제 해결 · 되돌리기) 순서.
const List<String> _subsectionHeadings = <String>[
  '### provider 별로 켤 때 필요한 것',
  '### 켜기',
  '### 끄기',
  '### iOS 서명 — Apple 을 꺼도 필요한 capability',
  '### App Store 심사 4.8 (Login Services) 주의',
  '### 확인 방법',
  '### 문제 해결',
  '### 되돌리기',
];

/// `### 확인 방법` 소절에 있어야 하는 키를 비운 빌드 확인 명령 · 성공 줄.
const List<String> _placeholderBuildPhrases = <String>[
  'bash scripts/verify_placeholder_builds.sh <android|ios> <dev|stg|prod> '
      '[off|google|all]',
  'PLACEHOLDER-BUILD-OK <platform> <flavor> <case>',
];

/// 절에 있어야 하는 끄기 · iOS 서명 · 심사 4.8 문구.
const List<String> _requiredSectionPhrases = <String>[
  'Sign in with Apple capability',
  '자동 서명이면 Xcode 가 켠다',
  'com.apple.developer.applesignin',
  '시뮬레이터 빌드에는 영향이 없다',
  'Apps that use a third-party or social login service (such as Facebook '
      'Login, Google Sign-In, Log in with X, Sign In with LinkedIn, Login '
      'with Amazon, or WeChat Login) to set up or authenticate the user',
  'the login service limits data collection to the user',
  'https://developer.apple.com/app-store/review/guidelines/#login-services',
  'RC Kill Switch 운영 절차',
  '로그인 · 재인증 · 회원탈퇴를 할 수 없다',
];

/// Initial Setup 절 헤딩.
const String _initialSetupHeading =
    '## Initial Setup — Flavor Config 키 주입 (사전 작업, 모든 Phase 공통)';

/// Initial Setup 키 표 헤더 줄.
const String _keyTableHeader = '| 키 | 값 출처 | off 면 비워도 됨 | 비고 |';

/// Initial Setup 키 표 바로 뒤의 새 절 링크 줄.
const String _keyTableLinkLine =
    '끈 provider 의 키는 비워 둬도 된다 — 무엇을 켤 때 무엇이 필요한지는 '
    '[로그인 수단 켜고 끄기](#로그인-수단-켜고-끄기).';

/// 유지보수자 문서 경로(provider 추가 · 제거 가이드).
const String _maintainerDocPath =
    'docs/maintainer/custom-token-provider-add-remove.md';

/// 새 절에서 유지보수자 문서를 가리키는 상대 링크 조각.
const String _maintainerDocLink =
    '](maintainer/custom-token-provider-add-remove.md)';

/// 매뉴얼에서 빠진 두 가이드 절의 제목(헤딩 · 목차 항목에 다시 나오면 안 된다).
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

/// 변경 이력 헤딩 — 이 앞까지가 「본문」 이다(이력 표는 옛 이름을 그대로 둔다).
const String _historyHeading = '## 변경 이력';

/// 본문에서 옮긴 절을 가리키면 안 되는 제목 조각(번호 · 괄호 꼬리 없이).
const List<String> _movedGuideTitleStems = <String>[
  'Custom Token Provider 제거 가이드',
  'Custom Token Provider 추가 가이드',
];

/// 계정 연결 · 해제 절에서 고친 단위의 머리 문자열 — 각각 정확히 한 줄이 이것으로
/// 시작한다(앞 공백은 무시 — 중첩 bullet 이 있다).
const List<String> _correctedUnitHeads = <String>[
  '**배포 (연결 끊기 함수):**',
  '**배포 (Naver 연결 함수):**',
  '- **재인증 창** —',
  '- **provider 제거** —',
  '- **Custom Token provider — Kakao/LINE (OIDC ID token):**',
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
  final String manual = readTrackedFile(_manualPath);
  final String section = sliceMarkdownSection(
    manual,
    _sectionHeading,
    maxLevel: 2,
  );
  final Map<String, Object?> manifest =
      jsonDecode(readTrackedFile(_manifestPath)) as Map<String, Object?>;
  final Map<String, Object?> exampleConfig =
      jsonDecode(readTrackedFile(_exampleConfigPath)) as Map<String, Object?>;
  final String exampleXcconfig = readTrackedFile(_exampleXcconfigPath);

  group('매뉴얼 「로그인 수단 켜고 끄기」 계약 (T-173-DOCS)', () {
    test('T-173-DOCS-01: 절 헤딩 1개 · 목차 항목 1개 · 목차 번호가 0부터 연속이다', () {
      expect(
        countExactLines(manual, _sectionHeading),
        1,
        reason: '절 헤딩이 없거나 중복이다',
      );

      final String toc = sliceTocBlock(manual);
      expect(toc.trim(), isNotEmpty, reason: '목차 블록을 찾지 못했다');
      expect(
        _tocEntryPattern.allMatches(toc).length,
        1,
        reason: '목차 블록 안 「로그인 수단 켜고 끄기」 항목이 없거나 중복이다',
      );

      final List<int> numbers = RegExp(
        r'^(\d+)\. ',
        multiLine: true,
      ).allMatches(toc).map((RegExpMatch m) => int.parse(m.group(1)!)).toList();
      expect(numbers, isNotEmpty, reason: '목차 번호 줄이 없다');
      expect(
        numbers,
        List<int>.generate(numbers.length, (int i) => i),
        reason: '목차 번호가 0부터 빠짐없이 이어지지 않는다',
      );
    });

    test('T-173-DOCS-02: 절에 사용자 문서 금지 패턴이 0 건이다', () {
      expect(section.trim(), isNotEmpty, reason: '절 슬라이스가 비었다');
      final List<String> hits = RegExp(
        kUserDocForbiddenPatternSource,
      ).allMatches(section).map((RegExpMatch m) => m.group(0)!).toList();
      expect(hits, isEmpty, reason: '금지 패턴이 절에 있다: $hits');
    });

    test('T-173-DOCS-03: 예시 값 · 키 · 변수가 example 파일과 일치한다', () {
      final List<RegExpMatch> pairs = _jsonPairPattern
          .allMatches(section)
          .toList();
      expect(pairs, isNotEmpty, reason: '절에 JSON 예시가 없다(양성 대조)');
      for (final RegExpMatch pair in pairs) {
        final String key = pair.group(1)!;
        final String value = pair.group(2)!;
        expect(
          exampleConfig.containsKey(key),
          isTrue,
          reason: '절의 예시 키 $key 가 $_exampleConfigPath 에 없다',
        );
        if (key == 'enabledAuthProviders') {
          continue;
        }
        expect(
          value,
          '${exampleConfig[key]}',
          reason: '절의 예시 값 $key 가 $_exampleConfigPath 값과 다르다',
        );
      }

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

    test('T-173-DOCS-04: 배포 함수 · secret · 배포 명령 · 토큰이 절에 있다', () {
      final Map<String, Object?> providers =
          manifest['providers']! as Map<String, Object?>;
      final List<String> providerFunctions = <String>[
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
      for (final String name in <String>[
        ...providerFunctions,
        ...commonFunctions,
      ]) {
        expect(
          section,
          contains('`$name`'),
          reason: 'manifest 의 함수 $name 이 절에 없다',
        );
      }

      for (final String secret in _providerSecrets) {
        expect(section, contains(secret), reason: '절에 secret $secret 이 없다');
      }

      final List<RegExpMatch> loops = _secretLoopPattern
          .allMatches(section)
          .toList();
      expect(loops, hasLength(1), reason: '절에 「켜기」 ④ secret 반복문이 1개가 아니다');
      final List<String> loopNames = loops.single
          .group(1)!
          .split(RegExp(r'[\s\\]+'))
          .where((String token) => token.isNotEmpty)
          .toList();
      expect(
        loopNames.toSet(),
        hasLength(loopNames.length),
        reason: '④ 반복문에 같은 secret 이름이 두 번 있다',
      );
      expect(
        loopNames.toSet(),
        _providerSecrets.toSet(),
        reason: '④ 반복문의 secret 이름 집합이 provider secret 목록과 다르다',
      );

      for (final String line in _deployCommandLines) {
        expect(
          countExactLines(section, line),
          greaterThanOrEqualTo(1),
          reason: '절에 배포 명령 줄 「$line」 이 없다',
        );
      }

      expect(
        providers.keys.toList(),
        _providerTokens,
        reason: 'manifest providers 키가 토큰 목록과 다르다',
      );
      for (final String token in _providerTokens) {
        expect(section, contains('`$token`'), reason: '절에 토큰 $token 이 없다');
      }
    });

    test('T-173-DOCS-05: 소절 순서 · 확인 방법 · 끄기 · iOS 서명 · 심사 4.8 문구', () {
      expect(
        linesStartingWith(section, '### '),
        _subsectionHeadings,
        reason: '절의 ### 소절이 템플릿 순서 8개와 다르다',
      );

      final String check = sliceMarkdownSection(
        section,
        '### 확인 방법',
        maxLevel: 3,
      );
      expect(check.trim(), isNotEmpty, reason: '확인 방법 소절을 찾지 못했다');
      for (final String phrase in _placeholderBuildPhrases) {
        expect(check, contains(phrase), reason: '확인 방법 소절에 「$phrase」 가 없다');
      }

      for (final String phrase in _requiredSectionPhrases) {
        expect(section, contains(phrase), reason: '절에 「$phrase」 가 없다');
      }
    });

    test('T-173-DOCS-06: Initial Setup 키 표 · off 열 · 금지 패턴 0 · 링크 줄', () {
      final String setup = sliceMarkdownSection(
        manual,
        _initialSetupHeading,
        maxLevel: 2,
      );
      expect(setup.trim(), isNotEmpty, reason: 'Initial Setup 절을 찾지 못했다');
      expect(
        countExactLines(setup, _keyTableHeader),
        1,
        reason: '「off 면 비워도 됨」 열이 있는 키 표 헤더가 없거나 중복이다',
      );

      final List<String> table = collectTableLines(setup, _keyTableHeader);
      final List<String> keys = exampleConfig.keys
          .where((String key) => key != 'flavor')
          .toList();
      expect(keys, hasLength(14), reason: 'example 키 수(flavor 제외)가 14 가 아니다');
      for (final String key in keys) {
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

      final List<String> setupLines = setup.split('\n');
      final int afterTable =
          setupLines.indexOf(_keyTableHeader) + table.length + 1;
      expect(
        afterTable < setupLines.length ? setupLines[afterTable] : '',
        _keyTableLinkLine,
        reason: '키 표 바로 뒤(빈 줄 다음)에 새 절 링크 줄이 없다',
      );
      expect(
        countExactLines(setup, _keyTableLinkLine),
        1,
        reason: '새 절 링크 줄이 없거나 중복이다',
      );
    });

    test('T-173-DOCS-07: 추가 · 제거 가이드가 유지보수자 문서로 옮겨지고 새 절에 링크 1줄', () {
      final RegExp legacyPattern = _buildLegacyCallablePattern();
      // 양성 대조: 정규식이 옛 이름은 잡고 해제 callable · arm 이름은 잡지 않는다.
      final String legacyCallable = _legacyCallableParts.join();
      expect(legacyPattern.hasMatch('`$legacyCallable`'), isTrue);
      expect(legacyPattern.hasMatch('`un$legacyCallable`'), isFalse);
      expect(legacyPattern.hasMatch('`${legacyCallable}Arm`'), isFalse);

      final String toc = sliceTocBlock(manual);
      expect(toc.trim(), isNotEmpty, reason: '목차 블록을 찾지 못했다');
      for (final String title in _movedGuideTitles) {
        expect(
          countExactLines(manual, '## $title'),
          0,
          reason: '매뉴얼에 옮긴 절 헤딩 「$title」 이 남아 있다',
        );
        expect(
          countOccurrences(toc, '[$title]('),
          0,
          reason: '목차에 옮긴 절 항목 「$title」 이 남아 있다',
        );
      }

      expect(
        countOccurrences(section, _maintainerDocLink),
        1,
        reason: '새 절에 유지보수자 문서 링크가 없거나 중복이다',
      );

      final String maintainerDoc = readTrackedFile(_maintainerDocPath);
      for (final String heading in <String>['## 추가 가이드', '## 제거 가이드']) {
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
      'T-173-DOCS-08: 본문에 옛 연결 callable · 옮긴 절 참조 0 · 고친 단위 머리 줄 1개씩 · 금지 패턴 0',
      () {
        final int historyIndex = manual.indexOf('\n$_historyHeading\n');
        expect(historyIndex, greaterThan(0), reason: '변경 이력 헤딩을 찾지 못했다');
        final String body = manual.substring(0, historyIndex);
        // 양성 대조: 본문 슬라이스가 새 절을 포함한다.
        expect(countOccurrences(body, '$_sectionHeading\n'), 1);

        expect(
          _buildLegacyCallablePattern().allMatches(body).length,
          0,
          reason: '본문에 옛 공유 연결 callable 이름이 있다',
        );
        for (final String stem in _movedGuideTitleStems) {
          expect(
            countOccurrences(body, stem),
            0,
            reason: '본문이 옮긴 절 「$stem」 을 가리킨다',
          );
        }
        expect(
          countOccurrences(body, 'linkKakaoProvider'),
          greaterThanOrEqualTo(1),
          reason: '본문에 새 Kakao 연결 callable 이름이 없다',
        );

        final List<String> bodyLines = body.split('\n');
        final List<String> unitLines = <String>[];
        for (final String head in _correctedUnitHeads) {
          final List<String> selected = bodyLines
              .where((String line) => line.trimLeft().startsWith(head))
              .toList();
          expect(selected, hasLength(1), reason: head);
          unitLines.addAll(selected);
        }

        final List<String> hits = RegExp(kUserDocForbiddenPatternSource)
            .allMatches(unitLines.join('\n'))
            .map((RegExpMatch m) => m.group(0)!)
            .toList();
        expect(hits, isEmpty, reason: '고친 단위에 금지 패턴이 있다: $hits');
      },
    );
  });
}
