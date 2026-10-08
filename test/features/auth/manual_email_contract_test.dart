// 매뉴얼 이메일 절 계약 (Phase 17.5 — see ROADMAP.md).
// 「인증 결과 페이지 바꾸기」 · 「인증 메일 발송 모드 켜고 끄기」 두 절의 위치 ·
// 사용자 문서 금지 패턴 · 명령 · 예시 일치 · 링크 계약.
//
// T-175-DOCS-01: 「인증 결과 페이지 바꾸기」 헤딩 1개 · 목차 항목 1개 · 목차에서
//   「로그인 수단 켜고 끄기」 바로 다음이다.
// T-175-DOCS-02: 절에 금지 패턴 · 문의 채널 단어가 0 건이고, hosting 배포 명령
//   (dry-run · `--apply`) · 작업 URL · 커스텀 도메인 공식 링크 · 로고 형식 ·
//   example 파일과 같은 `appName` · `brandColor` 줄 · 인자 없는 deploy 금지 문장이
//   있으며 `###` 소절이 템플릿 순서 그대로다.
// T-175-DOCS-03: 「인증 메일 발송 모드 켜고 끄기」 헤딩 1개 · 목차 항목 1개 · 목차와
//   본문 순서가 로그인 수단 → 결과 페이지 → 발송 모드 → 킷 업데이트 반영이다.
// T-175-DOCS-04: 「로그인 수단 켜고 끄기」 「켜기」 ⑤ 가 kit 모드 메일 함수를 말하고,
//   발송 모드 절에 금지 패턴 · 문의 채널 단어 · 강제 옵션 · secret 반복문이 0 건이며,
//   서비스 중립 문장이 Resend 예시보다 앞이고, 명령(확장 값 복사 · kit 배포 · TTL ·
//   함수 배포 · 확장 삭제) · DMARC 최소 레코드 · Gmail · Yahoo 공식 링크 · example
//   파일과 같은 확장 값 줄 · 금지 문장이 있다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/source_text.dart';

/// 매뉴얼 경로.
const String _manualPath = 'docs/manual.md';

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

/// 「인증 결과 페이지 바꾸기」 바로 앞에 있어야 하는 목차 항목.
final RegExp _providerTocPattern = RegExp(
  r'^\d+\. \[로그인 수단 켜고 끄기\]\(#로그인-수단-켜고-끄기\)$',
);

/// 「인증 메일 발송 모드 켜고 끄기」 목차 항목 줄.
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
  'bash scripts/deploy_functions.sh dev --apply',
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
        _resultPageTocPattern,
        _deliveryTocPattern,
        _kitUpdateTocPattern,
      ].map((RegExp entry) => tocLines.indexWhere(entry.hasMatch)).toList();
      expect(tocOrder.first, greaterThanOrEqualTo(0), reason: '목차 항목을 찾지 못했다');
      expect(
        tocOrder,
        List<int>.generate(4, (int i) => tocOrder.first + i),
        reason: '목차가 로그인 수단 → 결과 페이지 → 발송 모드 → 킷 업데이트 반영으로 이어지지 않는다',
      );

      final List<int> bodyOrder = <String>[
        _providerHeading,
        _resultPageHeading,
        _deliveryHeading,
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
        _resultPageHeading,
        _deliveryHeading,
        _kitUpdateHeading,
      ]);
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
}
