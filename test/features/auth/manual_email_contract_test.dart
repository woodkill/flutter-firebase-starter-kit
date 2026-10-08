// 매뉴얼 이메일 절 계약 (Phase 17.5 — see ROADMAP.md).
// 「인증 결과 페이지 바꾸기」 절의 위치 · 사용자 문서 금지 패턴 · 명령 · 예시 일치 ·
// 링크 계약.
//
// T-175-DOCS-01: 「인증 결과 페이지 바꾸기」 헤딩 1개 · 목차 항목 1개 · 목차에서
//   「로그인 수단 켜고 끄기」 바로 다음이다.
// T-175-DOCS-02: 절에 금지 패턴 · 문의 채널 단어가 0 건이고, hosting 배포 명령
//   (dry-run · `--apply`) · 작업 URL · 커스텀 도메인 공식 링크 · 로고 형식 ·
//   example 파일과 같은 `appName` · `brandColor` 줄 · 인자 없는 deploy 금지 문장이
//   있으며 `###` 소절이 템플릿 순서 그대로다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/source_text.dart';

/// 매뉴얼 경로.
const String _manualPath = 'docs/manual.md';

/// config 예시 파일(예시 값의 진실원).
const String _exampleConfigPath = 'config/dev.example.json';

/// 메일 표면 배포 스크립트(명령의 진실원).
const String _deployEmailScriptPath = 'scripts/deploy_email.sh';

/// 「인증 결과 페이지 바꾸기」 절 헤딩 (정확히 한 줄).
const String _resultPageHeading = '## 인증 결과 페이지 바꾸기';

/// 「인증 결과 페이지 바꾸기」 목차 항목 줄.
final RegExp _resultPageTocPattern = RegExp(
  r'^\d+\. \[인증 결과 페이지 바꾸기\]\(#인증-결과-페이지-바꾸기\)$',
);

/// 「인증 결과 페이지 바꾸기」 바로 앞에 있어야 하는 목차 항목.
final RegExp _providerTocPattern = RegExp(
  r'^\d+\. \[로그인 수단 켜고 끄기\]\(#로그인-수단-켜고-끄기\)$',
);

/// 인자 없는 deploy 금지 문장 — 새 이메일 절마다 정확한 문자열로 있다.
const String _bareDeployWarning =
    '배포는 배포 스크립트로만 한다 — 인자 없는 `firebase deploy` 는 '
    '`firebase.json` 의 모든 대상(확장 포함)을 배포하므로 쓰지 않는다.';

/// 「인증 결과 페이지 바꾸기」 절의 `###` 소절 (순서 그대로).
const List<String> _resultPageSubsections = <String>[
  '### 바꾸고 배포하기',
  '### 문구 · 모양 바꾸기',
  '### 커스텀 도메인',
  '### 확인 방법',
  '### 문제 해결',
  '### 되돌리기',
];

/// 「인증 결과 페이지 바꾸기」 절에 정확한 줄로 있어야 하는 명령.
const List<String> _resultPageCommandLines = <String>[
  'bash scripts/deploy_email.sh dev hosting',
  'bash scripts/deploy_email.sh dev hosting --apply',
];

/// 「인증 결과 페이지 바꾸기」 절에 있어야 하는 토큰.
const List<String> _resultPageTokens = <String>[
  'https://<your-project-id>.web.app/',
  '작업 URL 맞춤설정',
  'https://firebase.google.com/docs/hosting/custom-domain',
  'https://firebase.google.com/docs/hosting/default-site',
  '승인된 도메인',
  'App Check',
  '`hosting/public/logo.png`',
  'PNG',
  'SVG',
  '`functions/src/email/copy.json`',
  '`hosting/public/`',
  '「인증 확인」',
  '「인증 메일 재전송」',
  '「비밀번호를 잊으셨나요?」',
];

/// 문의 채널 단어 — 리터럴 대신 조각을 이어 만든다.
final List<String> _contactChannelWords = <String>[
  <String>['고객', '센터'].join(),
  <String>['문', '의'].join(),
];

/// [text] 에서 사용자 문서 금지 패턴에 걸린 문자열을 모은다.
List<String> _collectForbiddenHits(String text) => RegExp(
  kUserDocForbiddenPatternSource,
).allMatches(text).map((RegExpMatch m) => m.group(0)!).toList();

/// 목차 블록에서 [entry] 에 맞는 줄의 바로 앞 줄을 돌려준다(없으면 빈 문자열).
String _readPreviousTocLine(String toc, RegExp entry) {
  final List<String> lines = toc.split('\n');
  final int index = lines.indexWhere(entry.hasMatch);
  return index > 0 ? lines[index - 1] : '';
}

/// [example] JSON 의 [key] 값을 매뉴얼 JSON 예시 줄 꼴(`"key": "value"`)로 만든다.
String _buildExampleLine(Map<String, Object?> example, String key) =>
    '"$key": "${example[key]}"';

void main() {
  final String manual = readTrackedFile(_manualPath);
  final String toc = sliceTocBlock(manual);
  final String resultPage = sliceMarkdownSection(
    manual,
    _resultPageHeading,
    maxLevel: 2,
  );

  group('매뉴얼 「인증 결과 페이지 바꾸기」 계약 (T-175-DOCS)', () {
    test('T-175-DOCS-01: 헤딩 1개 · 목차 항목 1개 · 로그인 수단 항목 다음이다', () {
      expect(
        countExactLines(manual, _resultPageHeading),
        1,
        reason: '절 헤딩이 없거나 중복이다',
      );
      expect(toc.trim(), isNotEmpty, reason: '목차 블록을 찾지 못했다');
      expect(
        toc.split('\n').where(_resultPageTocPattern.hasMatch).length,
        1,
        reason: '목차 블록 안 「인증 결과 페이지 바꾸기」 항목이 없거나 중복이다',
      );
      expect(
        _providerTocPattern.hasMatch(
          _readPreviousTocLine(toc, _resultPageTocPattern),
        ),
        isTrue,
        reason: '「인증 결과 페이지 바꾸기」 항목이 「로그인 수단 켜고 끄기」 바로 다음이 아니다',
      );
    });

    test('T-175-DOCS-02: 금지 패턴 0 · 명령 · 링크 · 예시 일치 · 금지 문장이 있다', () {
      expect(resultPage.trim(), isNotEmpty, reason: '절 슬라이스가 비었다');
      // 양성 대조: 금지 패턴 정규식이 실제로 phase 번호를 잡는다.
      expect(_collectForbiddenHits('Phase 9'), isNotEmpty);
      final List<String> hits = _collectForbiddenHits(resultPage);
      expect(hits, isEmpty, reason: '금지 패턴이 절에 있다: $hits');
      for (final String word in _contactChannelWords) {
        expect(
          countOccurrences(resultPage, word),
          0,
          reason: '절이 문의 채널을 가정한다: $word',
        );
      }

      expect(
        linesStartingWith(resultPage, '### '),
        _resultPageSubsections,
        reason: '절의 ### 소절이 템플릿 순서와 다르다',
      );

      // 명령은 스크립트가 실제로 받는 대상 이름이다(양성 대조).
      expect(
        countOccurrences(
          readTrackedFile(_deployEmailScriptPath),
          '<hosting|kit>',
        ),
        greaterThanOrEqualTo(1),
        reason: '$_deployEmailScriptPath 사용법에 hosting 대상이 없다',
      );
      for (final String line in _resultPageCommandLines) {
        expect(
          countExactLines(resultPage, line),
          greaterThanOrEqualTo(1),
          reason: '명령 줄이 정확한 줄로 없다: $line',
        );
      }
      for (final String token in _resultPageTokens) {
        expect(
          countOccurrences(resultPage, token),
          greaterThanOrEqualTo(1),
          reason: '절에 토큰이 없다: $token',
        );
      }

      final Map<String, Object?> example =
          jsonDecode(readTrackedFile(_exampleConfigPath))
              as Map<String, Object?>;
      expect(
        countExactLines(
          resultPage,
          '${_buildExampleLine(example, 'appName')},',
        ),
        1,
        reason: '절의 appName 예시 줄이 example 파일 값과 다르다',
      );
      expect(
        countExactLines(resultPage, _buildExampleLine(example, 'brandColor')),
        1,
        reason: '절의 brandColor 예시 줄이 example 파일 값과 다르다',
      );

      expect(
        countOccurrences(resultPage, _bareDeployWarning),
        greaterThanOrEqualTo(1),
        reason: '절에 인자 없는 deploy 금지 문장이 없다',
      );
      expect(
        countOccurrences(resultPage, '--force'),
        0,
        reason: '절이 강제 옵션을 안내한다',
      );
    });
  });
}
