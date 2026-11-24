// 직접 하는 일 문서(`docs/guide.md`) 「호출 횟수 제한 기록 정리」 명령 ↔ functions
// 코드 이름 대조.
//
// guide 의 TTL 켜기 · 상태 확인 줄과 일회 삭제 줄을 `functions/src/shared/rate_limit.ts`
// 에서 뽑은 컬렉션 상수 · 만료 필드 이름으로 조립해 guide 에 정확히 한 줄씩 있는지
// 센다. 필드 이름이 어긋나면 TTL 정책은 오류 없이 아무 문서도 지우지 않고, 컬렉션
// 이름이 어긋나면 일회 삭제가 엉뚱한 컬렉션을 겨눈다 — 둘 다 실행해서는 드러나지
// 않으므로 문서와 코드를 시험으로 묶는다.
//
// guide 문장과 functions 소스를 읽으므로 유지보수자 트리에서만 돈다 — 킷 발행 규칙
// 파일이 없는 트리(공개본 · 킷 사용자 저장소)에서는 최상위 group 이 건너뛰어진다.
//
// T-32-DOCS-01: 컬렉션 상수 선언이 1개 · 만료 필드를 쓰는 새 창 자리가 2개 · 필드
//   이름이 1종이고, 그 이름으로 조립한 TTL 켜기 · 상태 확인 줄이 guide 에 1줄씩이다.
// T-32-DOCS-02: 같은 컬렉션 이름으로 조립한 일회 삭제 줄이 guide 에 1줄이다.

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/planning_docs.dart';
import '../../helpers/source_text.dart';

/// 컬렉션 · 만료 필드 이름의 진실원(호출 횟수 제한 공용 모듈).
const String _rateLimitSourcePath = 'functions/src/shared/rate_limit.ts';

/// 직접 하는 일 문서 경로 — 「호출 횟수 제한 기록 정리」 소절이 있다.
const String _guidePath = 'docs/guide.md';

/// 킷 발행 규칙 파일이 있는 트리(유지보수자 트리)에서만 최상위 group 을 돌린다.
const List<String> _maintainerOnlyDocs = <String>[kMaintainerTreeMarker];

/// 컬렉션 상수 선언 — `const RATE_LIMITS_COLLECTION = "rate_limits";`(공백 무관).
final RegExp _collectionDecl = RegExp(
  r'const\s+RATE_LIMITS_COLLECTION\s*=\s*"([A-Za-z_]+)"\s*;',
);

/// 새 창 `set` 의 만료 필드 — `<필드>: computeExpireAt(`(공백 무관).
final RegExp _expireFieldUse = RegExp(r'(\w+)\s*:\s*computeExpireAt\(');

/// [source] 의 컬렉션 상수 선언이 정확히 1개인지 확인하고 그 값을 돌려준다.
String _readCollectionName(String source) {
  final List<RegExpMatch> collections = _collectionDecl
      .allMatches(source)
      .toList();
  expect(collections, hasLength(1), reason: '컬렉션 상수 선언이 1개가 아니다');
  return collections.single.group(1)!;
}

void main() {
  group(
    'rate_limits TTL · 일회 삭제 명령 ↔ 코드',
    skip: skipUnlessPlanningDocsExist(_maintainerOnlyDocs),
    () {
      test(
        'T-32-DOCS-01: guide 의 TTL 켜기 · 상태 확인 줄이 코드의 컬렉션 · 만료 필드 이름과 같다',
        () {
          final String source = readTrackedFile(_rateLimitSourcePath);
          final String collection = _readCollectionName(source);
          final List<RegExpMatch> fieldUses = _expireFieldUse
              .allMatches(source)
              .toList();
          expect(fieldUses, hasLength(2), reason: '새 창 set 두 곳이 만료 필드를 쓰지 않는다');
          final Set<String> fields = fieldUses
              .map((RegExpMatch m) => m.group(1)!)
              .toSet();
          expect(fields, hasLength(1), reason: '만료 필드 이름이 두 곳에서 다르다');
          final String field = fields.single;

          final String guide = readTrackedFile(_guidePath);
          final enableLine =
              'gcloud firestore fields ttls update $field '
              '--collection-group=$collection --enable-ttl '
              '--project <your-project-id>';
          final listLine =
              'gcloud firestore fields ttls list '
              '--collection-group=$collection --project <your-project-id>';
          expect(countExactLines(guide, enableLine), 1, reason: enableLine);
          expect(countExactLines(guide, listLine), 1, reason: listLine);
        },
      );

      test('T-32-DOCS-02: guide 의 일회 삭제 줄이 코드의 컬렉션 이름을 겨눈다', () {
        final String source = readTrackedFile(_rateLimitSourcePath);
        final String collection = _readCollectionName(source);

        final String guide = readTrackedFile(_guidePath);
        final deleteLine =
            'firebase firestore:delete $collection --recursive '
            '--project <your-project-id>';
        expect(countExactLines(guide, deleteLine), 1, reason: deleteLine);
      });
    },
  );
}
