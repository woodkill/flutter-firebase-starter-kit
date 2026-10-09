// 매뉴얼 이메일 절 계약 (Phase 17.5 — see ROADMAP.md).
// 「인증 메일 발송 모드 켜고 끄기」 · 「인증 결과 페이지 바꾸기」 두 절의 위치 ·
// 사용자 문서 금지 패턴 · 명령 · 예시 일치 · 링크 계약.
//
// T-175-DOCS-01: 「인증 결과 페이지 바꾸기」 헤딩 1개 · 목차 항목 1개 · 목차에서
//   「인증 메일 발송 모드 켜고 끄기」 바로 다음이다(결과 페이지는 kit 모드 전용).
// T-175-DOCS-02: 절에 금지 패턴 · 문의 채널 단어가 0 건이고, hosting 배포 명령
//   (dry-run · `--apply`) · 발송 모드 절 링크 · 커스텀 도메인 공식 링크 · 로고 형식 ·
//   example 파일과 같은 `appName` · `brandColor` 줄 · 인자 없는 deploy 금지 문장이
//   있으며 `###` 소절이 템플릿 순서 그대로다.
// T-175-DOCS-03: 「인증 메일 발송 모드 켜고 끄기」 헤딩 1개 · 목차 항목 1개 · 목차와
//   본문 순서가 로그인 수단 → 발송 모드 → 결과 페이지 → 킷 업데이트 반영이다.
// T-175-DOCS-04: 「로그인 수단 켜고 끄기」 「켜기」 ⑤ 가 kit 모드 메일 함수를 말하고,
//   발송 모드 절에 금지 패턴 · 문의 채널 단어 · 강제 옵션 · secret 반복문이 0 건이며,
//   서비스 중립 문장이 Resend 예시보다 앞이고, 명령(확장 값 복사 · kit 배포 · TTL ·
//   함수 배포 · 확장 삭제) · DMARC 최소 레코드 · Gmail · Yahoo 공식 링크 · Hosting
//   기본 사이트 안내 · 결과 페이지 env · Firebase 기본 페이지 서술 · example 파일과
//   같은 확장 값 줄 · 금지 문장이 있다.
// T-175-DOCS-05: 옛 전제 문구(Console 메일 링크 주소 · 모드 무관 · 이메일 주소 복원 ·
//   결과 페이지 생략 가능 · callbackUri)가 매뉴얼 전체와 CHANGELOG 에 0 건이다.
// T-175-DOCS-06: 확장 함수 invoker 명령 줄이 매뉴얼 · 발송 모드 절에 정확히 2줄이고
//   배포 스크립트 `next:` echo 와 글자가 대응하며, 「켜기」 ⑤ ~ ⑧ · 명령 순서가
//   스크립트 `next:` 순서와 같고, 반영 토큰 · 로고 바탕 문장 · 무조건 실행 문장이
//   있으며 공개 · 프로젝트 단위 부여 안내가 0 건이다.
// T-175-DOCS-07: 결과 페이지가 Referer 를 보내지 않는다(firebase.json Hosting
//   `Referrer-Policy` = `no-referrer` · index.html meta)는 사실이 그대로이고, 웹 API
//   키 안내 세 곳(매뉴얼 키 표 · 매뉴얼 문제 해결 첫 항목 · config/README 절)이 리퍼러
//   제한 키 거부 사실과 애플리케이션 제한 없는 키 조치를 말하며 옛 허용 목록 안내가
//   0 건이다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/source_text.dart';

/// 매뉴얼 경로.
const String _manualPath = 'docs/manual.md';

/// CHANGELOG 경로(킷 판별 변경 사항 — 옛 전제 문구 0 단언 대상).
const String _changelogPath = 'CHANGELOG.md';

/// config 예시 파일(예시 값의 진실원).
const String _exampleConfigPath = 'config/dev.example.json';

/// 메일 표면 배포 스크립트(명령의 진실원).
const String _deployEmailScriptPath = 'scripts/deploy_email.sh';

/// 배포 함수 목록(kit 메일 함수 이름의 진실원).
const String _functionsManifestPath = 'scripts/functions_manifest.json';

/// 확장 값 예시 파일(확장 값 줄의 진실원).
const String _extensionEnvExamplePath =
    'extensions/firestore-send-email.env.example';

/// 확장 manifest 가 있는 파일(확장 인스턴스 ID 의 진실원).
const String _firebaseJsonPath = 'firebase.json';

/// 「로그인 수단 켜고 끄기」 절 헤딩.
const String _providerHeading = '## 로그인 수단 켜고 끄기';

/// 「인증 메일 발송 모드 켜고 끄기」 절 헤딩 (정확히 한 줄).
const String _deliveryHeading = '## 인증 메일 발송 모드 켜고 끄기';

/// 「킷 업데이트 반영」 절 헤딩.
const String _kitUpdateHeading = '## 킷 업데이트 반영';

/// 「인증 결과 페이지 바꾸기」 절 헤딩 (정확히 한 줄).
const String _resultPageHeading = '## 인증 결과 페이지 바꾸기';

/// 「인증 결과 페이지 바꾸기」 목차 항목 줄.
final RegExp _resultPageTocPattern = RegExp(
  r'^\d+\. \[인증 결과 페이지 바꾸기\]\(#인증-결과-페이지-바꾸기\)$',
);

/// 「로그인 수단 켜고 끄기」 목차 항목 줄.
final RegExp _providerTocPattern = RegExp(
  r'^\d+\. \[로그인 수단 켜고 끄기\]\(#로그인-수단-켜고-끄기\)$',
);

/// 「인증 메일 발송 모드 켜고 끄기」 목차 항목 줄 — 「인증 결과 페이지 바꾸기」
/// 바로 앞에 있어야 한다.
final RegExp _deliveryTocPattern = RegExp(
  r'^\d+\. \[인증 메일 발송 모드 켜고 끄기\]\(#인증-메일-발송-모드-켜고-끄기\)$',
);

/// 「킷 업데이트 반영」 목차 항목 줄.
final RegExp _kitUpdateTocPattern = RegExp(
  r'^\d+\. \[킷 업데이트 반영\]\(#킷-업데이트-반영\)$',
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
  '](#인증-메일-발송-모드-켜고-끄기)',
  'https://firebase.google.com/docs/hosting/custom-domain',
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

/// 「인증 메일 발송 모드 켜고 끄기」 절의 `###` 소절 (순서 그대로).
const List<String> _deliverySubsections = <String>[
  '### 켜기',
  '### 확인 방법',
  '### 문제 해결',
  '### 끄기',
];

/// 「인증 메일 발송 모드 켜고 끄기」 절에 정확한 줄로 있어야 하는 명령.
const List<String> _deliveryCommandLines = <String>[
  'cp extensions/firestore-send-email.env.example '
      'extensions/firestore-send-email.env.<your-project-id>',
  'bash scripts/deploy_email.sh dev kit',
  'bash scripts/deploy_email.sh dev kit --apply',
  'bash scripts/deploy_functions.sh dev',
  _functionsApplyCommandLine,
  'fvm flutter run --flavor dev --dart-define-from-file=config/dev.json',
  'firebase functions:delete sendVerificationMail sendPasswordResetMail '
      '--region asia-northeast3 --project <your-project-id>',
];

/// mail 컬렉션 TTL 정책 명령 — 매뉴얼 전체에 정확히 한 줄이다.
const String _ttlCommandLine =
    'gcloud firestore fields ttls update delivery.expireAt '
    '--collection-group=mail --enable-ttl --project <your-project-id>';

/// 확장 삭제 명령 — 저장소 밖 임시 디렉터리에서 실행한다(정확한 줄).
const String _extensionUninstallLine =
    '( cd "\$(mktemp -d)" && firebase ext:uninstall firestore-send-email '
    '--immediate --project <your-project-id> )';

/// 메일 함수 배포 명령(`--apply`) — 발송 모드 절 「켜기」 ⑥ 의 정확한 줄.
const String _functionsApplyCommandLine =
    'bash scripts/deploy_functions.sh dev --apply';

/// 확장 함수 invoker 부여 명령 — 발송 모드 절 「켜기」 ⑦ · 「문제 해결」 에
/// 정확한 줄로 있고, 매뉴얼 전체에 정확히 2줄이다.
const String _invokerCommandLine =
    'gcloud run services add-iam-policy-binding '
    'ext-firestore-send-email-processqueue --region=us-central1 '
    '--member=serviceAccount:\$(gcloud projects describe <your-project-id> '
    "--format='value(projectNumber)')-compute@developer.gserviceaccount.com "
    '--role=roles/run.invoker --project <your-project-id>';

/// 매뉴얼 명령의 프로젝트 ID 자리표시.
const String _projectIdPlaceholder = '<your-project-id>';

/// 배포 스크립트 소스에서 프로젝트 ID 를 담는 변수 꼴.
const String _scriptProjectVariable = r'${PROJECT}';

/// 배포 스크립트 `next:` 첫째 줄(TTL) echo 의 앞부분.
const String _scriptTtlEchoPrefix =
    'echo "next: gcloud firestore fields ttls update';

/// 배포 스크립트 `next:` 둘째 줄(메일 함수 배포) echo 의 앞부분.
const String _scriptFunctionsEchoPrefix =
    'echo "next: bash scripts/deploy_functions.sh';

/// 발송 모드 절 「켜기」 ⑦ 단계 머리 줄.
const String _invokerStepHeading = '**⑦ 확장 함수에 호출 권한을 준다.**';

/// 발송 모드 절 「켜기」 ⑧ 단계 머리 줄.
const String _appRebuildStepHeading = '**⑧ 앱을 다시 빌드해 실행한다.**';

/// 발송 모드 절 「켜기」 ⑤ ~ ⑧ 단계 머리 (순서 그대로 · 각 1개).
const List<String> _deliveryLateStepHeads = <String>[
  '**⑤ ',
  '**⑥ ',
  _invokerStepHeading,
  _appRebuildStepHeading,
];

/// 발송 모드 절에 있어야 하는 반영 토큰(도메인 인증 상태 · 미인증 거부 문구 ·
/// 확장 첫 설치 실패 문구 · 확장 함수 403).
const List<String> _deliveryReflectionTokens = <String>[
  'Not Started',
  'Verified',
  'domain is not verified',
  'Eventarc Service Agent',
  '403',
];

/// 결과 페이지 절 ② 의 로고 바탕 권장 문구.
const String _logoBackgroundPhrase = '바탕을 채운 PNG';

/// 「켜기」 ⑦ 단락의 무조건 실행 문장.
const String _invokerAllProjectsPhrase = '모든 프로젝트에서 실행한다';

/// 발송 모드 절에 없어야 하는 공개 · 프로젝트 단위 invoker 부여 토큰.
const List<String> _forbiddenInvokerGrantTokens = <String>[
  'allUsers',
  'allAuthenticatedUsers',
  'gcloud projects add-iam-policy-binding',
];

/// config README 경로(`firebaseWebApiKey` 안내 절의 위치).
const String _configReadmePath = 'config/README.md';

/// 결과 페이지 HTML 경로(referrer meta 의 진실원).
const String _resultPageHtmlPath = 'hosting/public/index.html';

/// config README 의 `firebaseWebApiKey` 절 헤딩.
const String _webApiKeyReadmeHeading =
    '## `firebaseWebApiKey` — 결과 페이지의 Firebase 웹 API 키';

/// 매뉴얼 키 표에서 `firebaseWebApiKey` 행의 머리.
const String _webApiKeyRowPrefix = '| `firebaseWebApiKey` |';

/// 매뉴얼 「문제 해결」 의 「문제가 발생했습니다」 항목 머리.
const String _webApiKeyTroubleBulletPrefix = '- **링크를 열면 「문제가 발생했습니다」 가 뜬다.**';

/// 웹 API 키 안내 세 곳이 모두 말해야 하는 토큰(공백 정규화 후 비교).
const List<String> _webApiKeyRefererTokens = <String>[
  '웹사이트(HTTP 리퍼러) 제한',
  'Referer',
  '애플리케이션 제한이 없는 키',
];

/// 웹 API 키 안내 세 곳에 없어야 하는 옛 조치 문구.
const List<String> _staleRefererAdvice = <String>[
  'web.app/*',
  '허용 목록에 더한다',
  '허용 목록에 `https',
];

/// 연속 공백 · 줄바꿈을 한 칸으로 줄인다(hard-wrap 된 문서 매칭용).
String _normalizeWhitespace(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// [text] 에서 [prefix] 로 시작하는 줄 하나를 돌려준다(없으면 빈 문자열).
String _readLineStartingWith(String text, String prefix) => text
    .split('\n')
    .firstWhere((String l) => l.startsWith(prefix), orElse: () => '');

/// `firebase.json` Hosting 헤더에서 [key] 의 값들을 모은다.
List<String> _collectHostingHeaderValues(String key) {
  final Map<String, Object?> root =
      jsonDecode(readTrackedFile(_firebaseJsonPath)) as Map<String, Object?>;
  final Map<String, Object?> hosting = root['hosting']! as Map<String, Object?>;
  final List<String> values = <String>[];
  for (final Object? rule in hosting['headers']! as List<Object?>) {
    if (rule case {'headers': final List<Object?> headers}) {
      for (final Object? header in headers) {
        if (header case {
          'key': final String k,
          'value': final String v,
        } when k == key) {
          values.add(v);
        }
      }
    }
  }
  return values;
}

/// [_invokerCommandLine] 을 배포 스크립트 소스의 echo 꼴로 바꾼다.
///
/// 자리표시 → `${PROJECT}` · `$(` → `\$(` 로 바꾸고 `echo "next: …"` 로 감싼다.
String _buildInvokerScriptEcho() {
  final String body = _invokerCommandLine
      .replaceAll(_projectIdPlaceholder, _scriptProjectVariable)
      .replaceAll(r'$(', r'\$(');
  return 'echo "next: $body"';
}

/// [text] 에서 [startPrefix] 로 시작하는 줄부터 [endPrefix] 로 시작하는 다음 줄
/// 앞까지를 돌려준다(시작 줄이 없으면 빈 문자열).
String _sliceLinesBetween(String text, String startPrefix, String endPrefix) {
  final List<String> lines = text.split('\n');
  final int start = lines.indexWhere((String l) => l.startsWith(startPrefix));
  if (start < 0) {
    return '';
  }
  final int end = lines.indexWhere(
    (String l) => l.startsWith(endPrefix),
    start + 1,
  );
  return lines.sublist(start, end < 0 ? lines.length : end).join('\n');
}

/// 「인증 메일 발송 모드 켜고 끄기」 절에 있어야 하는 토큰.
const List<String> _deliveryTokens = <String>[
  'v=DMARC1; p=none; rua=mailto:',
  '_dmarc.',
  'SPF',
  'DKIM',
  'https://support.google.com/a/answer/81126',
  'https://senders.yahooinc.com/best-practices/',
  'smtps://resend@smtp.resend.com:465',
  'Blaze',
  '`delivery.state`',
  '`delivery.error`',
  '`functions/src/email/copy.json`',
  '](#인증-결과-페이지-바꾸기)',
  'https://firebase.google.com/docs/hosting/default-site',
  '`EMAIL_RESULT_PAGE_URL`',
  'Firebase 기본 페이지',
  'https://<your-project-id>.web.app/',
];

/// 결과 페이지의 옛 전제 문구 — 매뉴얼 전체 · CHANGELOG 에 0 건이어야 한다.
///
/// Console 의 메일 링크 주소 변경 단계 · 결과 페이지가 발송 모드와 무관하다는
/// 서술 · 이메일 주소 복원 화면 · 결과 페이지 없이도 된다는 서술 · Console 설정
/// 이름이 다시 들어오는 것을 막는다.
const List<String> _staleResultPagePhrases = <String>[
  '작업 URL',
  '발송 모드와 상관없이',
  '이메일 주소 복원',
  '결과 페이지를 바꾸지 않아도',
  'callbackUri',
];

/// 서비스 중립 문장 — Resend 예시보다 먼저 나온다.
const String _serviceNeutralPhrase = 'SMTP URI 를 주는 발송 서비스면 무엇이든';

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

/// 매뉴얼 [manual] 에서 [heading] 줄의 위치(줄 번호)를 돌려준다(없으면 -1).
int _indexOfHeading(String manual, String heading) =>
    manual.split('\n').indexOf(heading);

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
  final String delivery = sliceMarkdownSection(
    manual,
    _deliveryHeading,
    maxLevel: 2,
  );
  final String providerSection = sliceMarkdownSection(
    manual,
    _providerHeading,
    maxLevel: 2,
  );

  group('매뉴얼 「인증 결과 페이지 바꾸기」 계약 (T-175-DOCS)', () {
    test('T-175-DOCS-01: 헤딩 1개 · 목차 항목 1개 · 발송 모드 항목 다음이다', () {
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
        _deliveryTocPattern.hasMatch(
          _readPreviousTocLine(toc, _resultPageTocPattern),
        ),
        isTrue,
        reason: '「인증 결과 페이지 바꾸기」 항목이 「인증 메일 발송 모드 켜고 끄기」 바로 다음이 아니다',
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

  group('매뉴얼 「인증 메일 발송 모드 켜고 끄기」 계약 (T-175-DOCS)', () {
    test('T-175-DOCS-03: 헤딩 1개 · 목차 항목 1개 · 목차와 본문이 작업 순서다', () {
      expect(
        countExactLines(manual, _deliveryHeading),
        1,
        reason: '절 헤딩이 없거나 중복이다',
      );
      final List<String> tocLines = toc.split('\n');
      expect(
        tocLines.where(_deliveryTocPattern.hasMatch).length,
        1,
        reason: '목차 블록 안 「인증 메일 발송 모드 켜고 끄기」 항목이 없거나 중복이다',
      );

      final List<int> tocOrder = <RegExp>[
        _providerTocPattern,
        _deliveryTocPattern,
        _resultPageTocPattern,
        _kitUpdateTocPattern,
      ].map((RegExp entry) => tocLines.indexWhere(entry.hasMatch)).toList();
      expect(tocOrder.first, greaterThanOrEqualTo(0), reason: '목차 항목을 찾지 못했다');
      expect(
        tocOrder,
        List<int>.generate(4, (int i) => tocOrder.first + i),
        reason: '목차가 로그인 수단 → 발송 모드 → 결과 페이지 → 킷 업데이트 반영으로 이어지지 않는다',
      );

      final List<int> bodyOrder = <String>[
        _providerHeading,
        _deliveryHeading,
        _resultPageHeading,
        _kitUpdateHeading,
      ].map((String heading) => _indexOfHeading(manual, heading)).toList();
      expect(bodyOrder.first, greaterThanOrEqualTo(0), reason: '본문 헤딩을 찾지 못했다');
      for (int i = 1; i < bodyOrder.length; i++) {
        expect(
          bodyOrder[i],
          greaterThan(bodyOrder[i - 1]),
          reason: '본문 ## 순서가 목차와 다르다: $bodyOrder',
        );
      }
      // 본문에서도 네 절 사이에 다른 ## 절이 끼지 않는다.
      final List<String> between = manual
          .split('\n')
          .sublist(bodyOrder.first, bodyOrder.last + 1)
          .where((String line) => line.startsWith('## '))
          .toList();
      expect(between, <String>[
        _providerHeading,
        _deliveryHeading,
        _resultPageHeading,
        _kitUpdateHeading,
      ], reason: '네 절 사이에 다른 ## 절이 있거나 순서가 다르다');
    });

    test('T-175-DOCS-04: kit 함수 문장 · 금지 0 · 명령 · 링크 · 예시 일치가 있다', () {
      // 「로그인 수단 켜고 끄기」 「켜기」 ⑤ — kit 모드 메일 함수 목록 문장.
      expect(providerSection.trim(), isNotEmpty, reason: '로그인 수단 절을 찾지 못했다');
      final Map<String, Object?> manifest =
          jsonDecode(readTrackedFile(_functionsManifestPath))
              as Map<String, Object?>;
      final List<String> kitFunctions =
          ((manifest['email']! as Map<String, Object?>)['kit']!
                  as List<Object?>)
              .cast<String>();
      expect(kitFunctions, isNotEmpty, reason: 'manifest 의 kit 함수를 읽지 못했다');
      for (final String name in kitFunctions) {
        expect(
          countOccurrences(providerSection, '`$name`'),
          greaterThanOrEqualTo(1),
          reason: '로그인 수단 절 「켜기」 ⑤ 에 kit 메일 함수 $name 이 없다',
        );
        expect(
          countOccurrences(delivery, '`$name`'),
          greaterThanOrEqualTo(1),
          reason: '발송 모드 절에 kit 메일 함수 $name 이 없다',
        );
      }
      expect(
        countOccurrences(providerSection, '`pnpm run deploy`'),
        greaterThanOrEqualTo(1),
        reason: '로그인 수단 절이 functions/ 의 deploy 스크립트를 쓰지 않는다고 말하지 않는다',
      );

      // 발송 모드 절 — 금지 패턴 · 문의 채널 · 강제 옵션 · secret 반복문 0.
      expect(delivery.trim(), isNotEmpty, reason: '절 슬라이스가 비었다');
      final List<String> hits = _collectForbiddenHits(delivery);
      expect(hits, isEmpty, reason: '금지 패턴이 절에 있다: $hits');
      for (final String word in _contactChannelWords) {
        expect(
          countOccurrences(delivery, word),
          0,
          reason: '절이 문의 채널을 가정한다: $word',
        );
      }
      expect(
        countOccurrences(delivery, '--force'),
        0,
        reason: '절이 강제 옵션을 안내한다',
      );
      expect(
        RegExp(r'^for s in ', multiLine: true).hasMatch(delivery),
        isFalse,
        reason: '절에 secret 반복문이 있다(반복문은 로그인 수단 절 한 곳)',
      );

      expect(
        linesStartingWith(delivery, '### '),
        _deliverySubsections,
        reason: '절의 ### 소절이 템플릿 순서와 다르다',
      );

      // 서비스 중립 문장이 Resend 예시보다 먼저다.
      final int neutralIndex = delivery.indexOf(_serviceNeutralPhrase);
      final int resendIndex = delivery.indexOf('Resend');
      expect(neutralIndex, greaterThanOrEqualTo(0), reason: '서비스 중립 문장이 없다');
      expect(resendIndex, greaterThanOrEqualTo(0), reason: 'Resend 예시가 없다');
      expect(
        neutralIndex,
        lessThan(resendIndex),
        reason: '서비스 중립 문장이 Resend 첫 등장보다 뒤에 있다',
      );

      for (final String line in _deliveryCommandLines) {
        expect(
          countExactLines(delivery, line),
          greaterThanOrEqualTo(1),
          reason: '명령 줄이 정확한 줄로 없다: $line',
        );
      }
      expect(countExactLines(delivery, _ttlCommandLine), 1);
      expect(
        countExactLines(manual, _ttlCommandLine),
        1,
        reason: 'TTL 명령은 매뉴얼 전체에 정확히 한 줄이다',
      );
      expect(countExactLines(delivery, _extensionUninstallLine), 1);
      expect(
        countOccurrences(
          readTrackedFile(_firebaseJsonPath),
          '"firestore-send-email":',
        ),
        1,
        reason: '확장 삭제 명령의 인스턴스 ID 가 firebase.json 과 다르다',
      );
      for (final String token in _deliveryTokens) {
        expect(
          countOccurrences(delivery, token),
          greaterThanOrEqualTo(1),
          reason: '절에 토큰이 없다: $token',
        );
      }
      expect(
        countOccurrences(delivery, _bareDeployWarning),
        greaterThanOrEqualTo(1),
        reason: '절에 인자 없는 deploy 금지 문장이 없다',
      );

      // 예시 값 — config example 과 확장 값 example 파일의 줄 그대로.
      expect(countExactLines(delivery, '"emailDelivery": "kit"'), 1);
      final List<String> envLines = readTrackedFile(_extensionEnvExamplePath)
          .split('\n')
          .where((String line) => RegExp(r'^[A-Z_]+=').hasMatch(line))
          .toList();
      expect(envLines, hasLength(4), reason: '확장 값 example 의 키 줄이 4개가 아니다');
      for (final String line in envLines) {
        expect(
          countExactLines(delivery, line),
          1,
          reason: '절의 확장 값 예시 줄이 example 파일과 다르다: $line',
        );
      }
    });
  });

  group('매뉴얼 · CHANGELOG 결과 페이지 옛 전제 문구 (T-175-DOCS)', () {
    test('T-175-DOCS-05: 옛 전제 문구가 매뉴얼 · CHANGELOG 에 0 건이다', () {
      // 양성 대조: 목록을 이은 문자열에서 첫 문구가 세어진다.
      expect(
        countOccurrences(
          _staleResultPagePhrases.join(' '),
          _staleResultPagePhrases.first,
        ),
        1,
      );
      final Map<String, String> sources = <String, String>{
        _manualPath: manual,
        _changelogPath: readTrackedFile(_changelogPath),
      };
      for (final MapEntry<String, String> source in sources.entries) {
        expect(source.value.trim(), isNotEmpty, reason: '${source.key} 가 비었다');
        for (final String phrase in _staleResultPagePhrases) {
          expect(
            countOccurrences(source.value, phrase),
            0,
            reason: '${source.key} 에 옛 전제 문구가 있다: $phrase',
          );
        }
      }
    });
  });

  group('매뉴얼 발송 모드 invoker 단계 · UAT 반영 문장 (T-175-DOCS)', () {
    test('T-175-DOCS-06: invoker 명령 줄 · 스크립트 대조 · 순서 · 반영 문장이 있다', () {
      expect(delivery.trim(), isNotEmpty, reason: '발송 모드 절 슬라이스가 비었다');
      expect(resultPage.trim(), isNotEmpty, reason: '결과 페이지 절 슬라이스가 비었다');

      // 양성 대조: 명령 줄을 두 번 이은 문자열에서 정확한 줄이 2개로 세어진다.
      expect(
        countExactLines(
          '$_invokerCommandLine\n$_invokerCommandLine',
          _invokerCommandLine,
        ),
        2,
      );

      // ① invoker 명령 줄 — 「켜기」 ⑦ · 「문제 해결」 두 곳(매뉴얼 전체도 2줄).
      expect(
        countExactLines(delivery, _invokerCommandLine),
        2,
        reason: '발송 모드 절의 invoker 명령 줄이 정확히 2줄이 아니다',
      );
      expect(
        countExactLines(manual, _invokerCommandLine),
        2,
        reason: '매뉴얼 전체의 invoker 명령 줄이 정확히 2줄이 아니다',
      );

      // ② 배포 스크립트 `next:` 셋째 echo 와 글자가 대응한다.
      final String script = readTrackedFile(_deployEmailScriptPath);
      final String invokerEcho = _buildInvokerScriptEcho();
      expect(
        countOccurrences(script, invokerEcho),
        1,
        reason: '$_deployEmailScriptPath 에 매뉴얼 invoker 명령의 echo 꼴이 1개가 아니다',
      );

      // ③ 스크립트 `next:` 순서 — TTL < 메일 함수 배포 < invoker.
      final int scriptTtl = script.indexOf(_scriptTtlEchoPrefix);
      final int scriptFunctions = script.indexOf(_scriptFunctionsEchoPrefix);
      final int scriptInvoker = script.indexOf(invokerEcho);
      expect(scriptTtl, greaterThanOrEqualTo(0), reason: '스크립트에 TTL next 가 없다');
      expect(
        scriptTtl,
        lessThan(scriptFunctions),
        reason: '스크립트 next 순서가 TTL → 함수 배포가 아니다',
      );
      expect(
        scriptFunctions,
        lessThan(scriptInvoker),
        reason: '스크립트 next 순서가 함수 배포 → invoker 가 아니다',
      );

      // ④ 매뉴얼 「켜기」 ⑤ ~ ⑧ 단계 머리 — 각 1개 · 순서 그대로.
      int previousHead = -1;
      for (final String head in _deliveryLateStepHeads) {
        expect(
          countOccurrences(delivery, head),
          1,
          reason: '발송 모드 절의 단계 머리가 1개가 아니다: $head',
        );
        final int index = delivery.indexOf(head);
        expect(
          index,
          greaterThan(previousHead),
          reason: '발송 모드 절의 단계 머리 순서가 다르다: $head',
        );
        previousHead = index;
      }

      // ⑤ 매뉴얼 명령 순서 — TTL < 메일 함수 배포 < invoker(스크립트 next 순서와 같다).
      final int manualTtl = delivery.indexOf(_ttlCommandLine);
      final int manualFunctions = delivery.indexOf(_functionsApplyCommandLine);
      final int manualInvoker = delivery.indexOf(_invokerCommandLine);
      expect(manualTtl, greaterThanOrEqualTo(0), reason: '절에 TTL 명령이 없다');
      expect(
        manualTtl,
        lessThan(manualFunctions),
        reason: '매뉴얼 명령 순서가 TTL → 함수 배포가 아니다',
      );
      expect(
        manualFunctions,
        lessThan(manualInvoker),
        reason: '매뉴얼 명령 순서가 함수 배포 → invoker 가 아니다',
      );

      // ⑥ 발송 모드 절 반영 토큰.
      for (final String token in _deliveryReflectionTokens) {
        expect(
          countOccurrences(delivery, token),
          greaterThanOrEqualTo(1),
          reason: '발송 모드 절에 반영 토큰이 없다: $token',
        );
      }

      // ⑦ 결과 페이지 절 ② 로고 바탕 권장 문장.
      expect(
        countOccurrences(resultPage, _logoBackgroundPhrase),
        greaterThanOrEqualTo(1),
        reason: '결과 페이지 절에 로고 바탕 권장 문장이 없다',
      );

      // ⑨ 「켜기」 ⑦ 단락은 모든 프로젝트가 실행하는 단계이고, 공개 · 프로젝트
      // 단위 부여 안내는 없다.
      final String invokerStep = _sliceLinesBetween(
        delivery,
        _invokerStepHeading,
        '**⑧ ',
      );
      expect(invokerStep.trim(), isNotEmpty, reason: '「켜기」 ⑦ 단락을 찾지 못했다');
      expect(
        countOccurrences(invokerStep, _invokerAllProjectsPhrase),
        greaterThanOrEqualTo(1),
        reason: '「켜기」 ⑦ 단락이 모든 프로젝트의 단계로 쓰여 있지 않다',
      );
      for (final String token in _forbiddenInvokerGrantTokens) {
        expect(
          countOccurrences(delivery, token),
          0,
          reason: '발송 모드 절이 공개 · 프로젝트 단위 부여를 안내한다: $token',
        );
      }
    });
  });

  group('웹 API 키 안내와 no-referrer 정책 일관성 (T-175-DOCS)', () {
    test('T-175-DOCS-07: 리퍼러 제한 키 거부 사실과 조치가 세 곳에 있고 옛 안내가 없다', () {
      // (a) 진실원 — 결과 페이지는 Referer 를 보내지 않는다.
      expect(_collectHostingHeaderValues('Referrer-Policy'), <String>[
        'no-referrer',
      ], reason: 'Hosting Referrer-Policy 가 no-referrer 가 아니다 — 키 안내를 다시 검토한다');
      expect(
        RegExp(
          r'<meta\s+name="referrer"\s+content="no-referrer"\s*>',
        ).hasMatch(readTrackedFile(_resultPageHtmlPath)),
        isTrue,
        reason: '$_resultPageHtmlPath 의 referrer meta 가 no-referrer 가 아니다',
      );

      final String readme = readTrackedFile(_configReadmePath);
      final Map<String, String> regions = <String, String>{
        '매뉴얼 키 표 행': _readLineStartingWith(manual, _webApiKeyRowPrefix),
        '매뉴얼 문제 해결 항목': _readLineStartingWith(
          _sliceLinesBetween(resultPage, '### 문제 해결', '### 되돌리기'),
          _webApiKeyTroubleBulletPrefix,
        ),
        'config/README 절': sliceMarkdownSection(
          readme,
          _webApiKeyReadmeHeading,
          maxLevel: 2,
        ),
      };

      // 양성 대조: 정규화가 hard-wrap 을 이어 주고 세기 API 가 실제로 맞는다.
      expect(
        countOccurrences(_normalizeWhitespace('Referer\n  를'), 'Referer 를'),
        1,
      );

      for (final MapEntry<String, String> region in regions.entries) {
        expect(
          region.value.trim(),
          isNotEmpty,
          reason: '${region.key} 를 찾지 못했다',
        );
        final String flat = _normalizeWhitespace(region.value);
        // (c) 사실과 조치 토큰.
        for (final String token in _webApiKeyRefererTokens) {
          expect(
            countOccurrences(flat, token),
            greaterThanOrEqualTo(1),
            reason: '${region.key} 에 토큰이 없다: $token',
          );
        }
        // (b) 옛 허용 목록 안내.
        for (final String stale in _staleRefererAdvice) {
          expect(
            countOccurrences(flat, stale),
            0,
            reason: '${region.key} 에 옛 리퍼러 허용 목록 안내가 있다: $stale',
          );
        }
      }

      // (b) 파일 전체에서도 결과 페이지 주소 허용 목록 안내는 없다.
      expect(countOccurrences(manual, 'web.app/*'), 0);
      expect(countOccurrences(readme, 'web.app/*'), 0);
    });
  });
}
