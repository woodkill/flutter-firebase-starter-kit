// Phase 17 — see ROADMAP.md (D-14 · D-15 · D-19).
//
// `firebase.json` 의 Firestore · Storage 규칙 등록과 에뮬레이터 포트를 소스 계약으로
// 잠근다. 배포(`firebase deploy --only firestore,storage`)와 rules 에뮬레이터 테스트
// (`functions` 의 `pnpm test:rules`)가 같은 파일을 읽으므로, 등록이 빠지거나 포트가
// 바뀌면 rules 가 배포되지 않거나 에뮬레이터 스위트가 다른 포트를 찾는다.
//
// Hosting 결과 페이지 · Trigger Email 확장 선언과 확장 env 의 추적 범위(공유 값 · 예시만)
// 도 같은 파일에서 잠근다.
//
// JSON 은 문자열 검색 대신 `jsonDecode` 로 파싱해 키 경로를 정확히 비교한다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

const String _firebaseJsonPath = 'firebase.json';
const String _storageRulesPath = 'storage.rules';
const String _firestoreIndexesPath = 'firestore.indexes.json';
const String _hostingPublicDir = 'build/hosting/public';
const String _mailExtensionId = 'firestore-send-email';
const String _mailExtensionRef = 'firebase/firestore-send-email@0.2.10';
const String _mailEnvBase = 'extensions/firestore-send-email';
const List<String> _securityHeaderKeys = <String>[
  'X-Frame-Options',
  'Content-Security-Policy',
  'Referrer-Policy',
  'X-Content-Type-Options',
];

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

/// [path] 가 `.gitignore` 로 무시되는지 돌려준다 (`git check-ignore -q`).
///
/// 파일이 없어도 판정한다. 종료 코드가 0 · 1 이 아니면(git 오류) 실패시킨다.
bool isIgnoredByGit(String path) {
  final ProcessResult result = Process.runSync('git', <String>[
    'check-ignore',
    '-q',
    path,
  ]);
  if (result.exitCode != 0 && result.exitCode != 1) {
    fail('git check-ignore 오류(${result.exitCode}): ${result.stderr}');
  }
  return result.exitCode == 0;
}

/// [hosting] 블록의 `headers[].headers[].key` 를 모두 모아 돌려준다.
List<String> readHostingHeaderKeys(Map<String, Object?> hosting) {
  final Object? rules = hosting['headers'];
  if (rules is! List<Object?>) {
    fail('firebase.json hosting.headers 가 배열이 아니다: $rules');
  }
  return <String>[
    for (final Object? rule in rules)
      if (rule case {'headers': final List<Object?> headers})
        for (final Object? header in headers)
          if (header case {'key': final String key}) key,
  ];
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

  group('메일 발송 · Hosting 선언 계약 (T-175-FBJSON)', () {
    test('T-175-FBJSON-01: firebase.json 이 Hosting 결과 페이지와 '
        'Trigger Email 확장을 선언한다', () {
      final Map<String, Object?> root = readFirebaseJson();
      final Map<String, Object?> hosting = readObject(root, 'hosting');

      expect(hosting['public'], _hostingPublicDir);
      // 배포 대상 프로젝트의 config 로 매번 다시 빌드한다 — 다른 flavor 산출물 업로드 방지.
      final Object? predeploy = hosting['predeploy'];
      if (predeploy is! List<Object?>) {
        fail('firebase.json hosting.predeploy 가 배열이 아니다: $predeploy');
      }
      expect(predeploy, hasLength(1));
      expect(predeploy.single, contains('hosting/build.mjs'));
      expect(predeploy.single, contains(r'$GCLOUD_PROJECT'));

      expect(readHostingHeaderKeys(hosting), containsAll(_securityHeaderKeys));

      final Map<String, Object?> extensions = readObject(root, 'extensions');
      expect(extensions[_mailExtensionId], _mailExtensionRef);
    });

    test('T-175-FBJSON-02: 확장 env 는 공유 값 · 예시만 추적되고 '
        '프로젝트별 실 값 · secret 은 gitignore 된다', () {
      // check-ignore 종료 코드 — 0 = 무시됨 · 1 = 무시 안 됨.
      const Map<String, bool> expectedIgnored = <String, bool>{
        '$_mailEnvBase.env': false,
        '$_mailEnvBase.env.example': false,
        '$_mailEnvBase.env.your-project-dev': true,
        '$_mailEnvBase.env.local': true,
        '$_mailEnvBase.secret.local': true,
      };
      for (final MapEntry<String, bool> entry in expectedIgnored.entries) {
        expect(isIgnoredByGit(entry.key), entry.value, reason: entry.key);
      }

      expect(isTrackedByGit('$_mailEnvBase.env'), isTrue);
      expect(isTrackedByGit('$_mailEnvBase.env.example'), isTrue);
    });
  });
}
