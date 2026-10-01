// Phase 17 — see ROADMAP.md (D-14 · D-15 · D-19).
//
// `firebase.json` 의 Firestore · Storage 규칙 등록과 에뮬레이터 포트를 소스 계약으로
// 잠근다. 배포(`firebase deploy --only firestore,storage`)와 rules 에뮬레이터 테스트
// (`functions` 의 `pnpm test:rules`)가 같은 파일을 읽으므로, 등록이 빠지거나 포트가
// 바뀌면 rules 가 배포되지 않거나 에뮬레이터 스위트가 다른 포트를 찾는다.
//
// JSON 은 문자열 검색 대신 `jsonDecode` 로 파싱해 키 경로를 정확히 비교한다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

const String _firebaseJsonPath = 'firebase.json';
const String _storageRulesPath = 'storage.rules';
const String _firestoreIndexesPath = 'firestore.indexes.json';

/// [map] 의 [key] 값을 JSON object 로 돌려준다. 없거나 object 가 아니면 실패시킨다.
Map<String, Object?> readObject(Map<String, Object?> map, String key) {
  final Object? value = map[key];
  if (value is! Map<String, Object?>) {
    fail('firebase.json 의 "$key" 가 JSON object 가 아니다: $value');
  }
  return value;
}

/// 저장소 루트의 `firebase.json` 을 파싱해 최상위 object 를 돌려준다.
Map<String, Object?> readFirebaseJson() {
  final Object? decoded = jsonDecode(readTrackedFile(_firebaseJsonPath));
  return decoded as Map<String, Object?>;
}

/// [path] 가 git 에 tracked 된 파일인지 확인한다 (`git ls-files --error-unmatch`).
bool isTrackedByGit(String path) {
  final ProcessResult result = Process.runSync('git', <String>[
    'ls-files',
    '--error-unmatch',
    path,
  ]);
  return result.exitCode == 0;
}

void main() {
  group('Phase 17 firebase.json 등록 계약 (T-17-FBJSON)', () {
    test('T-17-FBJSON-01 firebase.json 이 rules · indexes · 에뮬레이터 포트를 등록한다', () {
      final Map<String, Object?> root = readFirebaseJson();
      final Map<String, Object?> firestore = readObject(root, 'firestore');
      final Map<String, Object?> storage = readObject(root, 'storage');
      final Map<String, Object?> emulators = readObject(root, 'emulators');

      expect(firestore['rules'], 'firestore.rules');
      expect(firestore['indexes'], 'firestore.indexes.json');
      expect(storage['rules'], 'storage.rules');
      expect(readObject(emulators, 'firestore')['port'], 8080);
      expect(readObject(emulators, 'storage')['port'], 9199);
      expect(emulators['singleProjectMode'], isTrue);
    });

    test('T-17-FBJSON-02 storage.rules · firestore.indexes.json 이 tracked 이고 '
        'storage.rules 가 users 경로 match 를 1개 가진다', () {
      expect(isTrackedByGit(_storageRulesPath), isTrue);
      expect(isTrackedByGit(_firestoreIndexesPath), isTrue);

      final String rules = stripSlashComments(
        readTrackedFile(_storageRulesPath),
      );
      expect(countOccurrences(rules, 'users/{userId}/{allPaths=**}'), 1);
    });
  });
}
