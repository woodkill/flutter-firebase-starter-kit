// Phase 17.1 Plan 13 — 홈 · 데모 lib 전체 source guard
// (D-01 · D-17 · 17 D-04 · 10.2 D-A4 · 성공 기준 1 · 3).
//
// T-171-HOME-14: 알림 탭 리스너(`PendingNotificationRouteListener`) 생성은
//   lib 전체에서 홈 배선 파일 하나뿐이다. 「리스너 2개면 이동 2번」 테스트는 쓰지
//   않는다 — consume 이 값을 비워 이동은 1번이지만, 두 번째 리스너는 홈 밖에서
//   값을 소비해 홈 교체 실수를 숨긴다(RESEARCH §R-04). 그래서 소스로 잠근다.
// T-171-HOME-15: 데모 화면은 알림 리스너 · 공지 배너 · 라우트 상수 · 테마
//   provider 를 import 하지 않는다(production 배선 0 · D-17).
// T-171-HOME-16: 로그아웃은 `signOutAndResetOnboarding()` 한 함수로만 하고(10.2
//   D-A4), 로그아웃 확인 다이얼로그 함수는 계정 화면 한 곳에만 정의된다.
// T-171-HOME-17: 옛 홈 화면(데모 · production 이 섞여 있던 1532줄 파일)은
//   클래스 이름 · 파일 모두 저장소에 없다. 옛 이름은 리터럴 없이 조각을 이어
//   만든다 — 이 파일 자신이 lib · test 부재 grep 에 걸리지 않게 하기 위해서다.
//
// 주석 제거 규칙: 존재 집합(14 · 16)은 행 주석 + 블록 주석을 걷어 낸 lib 코드로
// 센다(KDoc 언급 오탐 방지). 부재 단언(17)은 행 주석만 걷어 낸다 — test 트리에는
// `'config/*.json'` 같은 glob 문자열이 있어 블록 주석 정규식이 코드 덩어리를
// 삼키면 부재가 공허하게 참이 되기 때문이다(덜 걷어 내는 쪽이 더 엄격하다).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/source_text.dart';

/// 새 홈 배선 파일 — 알림 리스너가 생성되는 유일한 곳.
const String _homeScreenPath =
    'lib/features/home/presentation/home_screen.dart';

/// 리스너 정의 파일 — 생성자 선언이 있으므로 순회에서 제외한다.
const String _listenerDefinitionPath =
    'lib/features/notifications/presentation/pending_notification_route_listener.dart';

/// 로그아웃 정의 파일 — 메서드 선언이 있으므로 순회에서 제외한다.
const String _authRepositoryPath =
    'lib/features/auth/data/auth_repository.dart';

/// 데모 화면 파일 (release 제외 · production 배선 0).
const String _demoScreenPath =
    'lib/features/demo/presentation/demo_screen.dart';

/// 계정 화면 파일 — 로그아웃 확인 다이얼로그의 유일한 자리.
const String _accountScreenPath =
    'lib/features/settings/presentation/account_screen.dart';

/// 옛 홈 클래스 이름 조각 — 이어 붙여야 이름이 된다(리터럴 0 · T-171-HOME-17).
const List<String> _legacyParts = <String>['Environment', 'Info', 'Screen'];

/// [root] 아래 모든 `.dart` 파일 경로를 `/` 구분자로 정렬해 돌려준다.
List<String> _listDartFiles(String root) {
  final List<String> paths =
      Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .map((File file) => file.path.replaceAll(r'\', '/'))
          .where((String path) => path.endsWith('.dart'))
          .toList()
        ..sort();
  return paths;
}

/// [path] 소스에서 행 주석과 블록 주석을 걷어 낸 코드만 돌려준다.
String _readCodeWithoutComments(String path) =>
    stripBlockComments(stripSlashComments(readTrackedFile(path)));

/// [path] 소스에서 행 주석만 걷어 낸 코드를 돌려준다 (부재 단언용 · 더 엄격).
String _readCodeWithoutLineComments(String path) =>
    stripSlashComments(readTrackedFile(path));

void main() {
  group('Phase 17.1 홈 · 데모 source guard (T-171-HOME)', () {
    test('T-171-HOME-14: lib 에서 알림 리스너를 생성하는 파일은 홈 배선 파일 하나다 '
        '(D-17 · 17 D-04)', () {
      // 양성 대조: 제외하는 정의 파일 · 기대 파일이 실제로 있다.
      expect(File(_listenerDefinitionPath).existsSync(), isTrue);
      expect(File(_homeScreenPath).existsSync(), isTrue);

      final RegExp creation = RegExp(r'PendingNotificationRouteListener\s*\(');
      final List<String> creators = _listDartFiles('lib')
          .where((String path) => path != _listenerDefinitionPath)
          .where(
            (String path) => creation.hasMatch(_readCodeWithoutComments(path)),
          )
          .toList();

      expect(
        creators,
        <String>[_homeScreenPath],
        reason:
            '알림 탭 리스너는 홈 한 곳에서만 만든다 — 다른 화면에 두면 그 화면이 '
            '이동 값을 먼저 소비해 홈 교체 실수가 숨는다(RESEARCH §R-04)',
      );
    });

    test('T-171-HOME-15: 데모 화면은 알림 리스너 · 공지 배너 · 라우트 상수 · 테마 '
        'provider 를 import 하지 않는다 (D-17)', () {
      final List<String> importLines = _readCodeWithoutComments(_demoScreenPath)
          .split('\n')
          .where((String line) => line.trimLeft().startsWith('import '))
          .toList();

      // 양성 대조: 같은 추출이 실제 import 를 읽는다.
      expect(
        importLines.where(
          (String line) => line.contains('firebase_providers.dart'),
        ),
        hasLength(1),
        reason: 'import 줄 추출이 비어 부재 단언이 공허해졌다',
      );

      const List<String> bannedImports = <String>[
        'pending_notification_route_listener.dart',
        'announcement_bar.dart',
        'app_routes.dart',
        'theme_provider.dart',
      ];
      for (final String banned in bannedImports) {
        expect(
          importLines.where((String line) => line.contains(banned)),
          isEmpty,
          reason: '데모 화면은 production 배선($banned)을 import 하지 않는다',
        );
      }
    });

    test('T-171-HOME-16: 로그아웃 호출 파일 집합이 고정되고 확인 다이얼로그는 계정 '
        '화면에만 있다 (10.2 D-A4 · D-05)', () {
      // 양성 대조: 제외하는 정의 파일에 실제 선언이 있다.
      expect(
        RegExp(
          r'Future<void>\s+signOutAndResetOnboarding\s*\(',
        ).hasMatch(_readCodeWithoutComments(_authRepositoryPath)),
        isTrue,
      );

      final List<String> libFiles = _listDartFiles('lib');
      final RegExp signOutCall = RegExp(r'signOutAndResetOnboarding\s*\(');
      final Set<String> callers = libFiles
          .where((String path) => path != _authRepositoryPath)
          .where(
            (String path) =>
                signOutCall.hasMatch(_readCodeWithoutComments(path)),
          )
          .toSet();

      expect(
        callers,
        <String>{
          _accountScreenPath,
          _demoScreenPath,
          'lib/features/settings/presentation/settings_notifier.dart',
          'lib/features/auth/presentation/verify_email_notifier.dart',
        },
        reason:
            '로그아웃은 signOutAndResetOnboarding() 한 함수로만 — 호출 위치가 '
            '늘거나 줄면 이 집합을 결정과 함께 갱신한다',
      );

      // 정의 형태(`BuildContext` 매개변수)만 잡는다 — 호출 `(context, ref)` 는 제외.
      final RegExp confirmDialogDefinition = RegExp(
        r'\b_?confirmSignOut\w*\s*\(\s*BuildContext\b',
      );
      final List<String> dialogOwners = libFiles
          .where(
            (String path) => confirmDialogDefinition.hasMatch(
              _readCodeWithoutComments(path),
            ),
          )
          .toList();

      expect(dialogOwners, <String>[
        _accountScreenPath,
      ], reason: '로그아웃 확인 다이얼로그는 계정 화면 한 곳에만 정의된다');
    });

    test('T-171-HOME-17: 옛 홈 화면의 클래스 이름 · 파일이 lib · test 에 없다 '
        '(D-01 · D-09)', () {
      // 옛 이름은 리터럴 없이 조립한다(이 파일이 부재 grep 에 걸리지 않게).
      final String legacyClassName = _legacyParts.join();
      final String legacyFileStem = _legacyParts
          .map((String part) => part.toLowerCase())
          .join('_');

      final List<String> scannedFiles = <String>[
        ..._listDartFiles('lib'),
        ..._listDartFiles('test'),
      ];

      // 양성 대조: 같은 순회 · 같은 주석 규칙이 새 홈 클래스를 찾는다.
      final List<String> homeClassFiles = scannedFiles
          .where(
            (String path) =>
                _readCodeWithoutLineComments(path).contains('HomeScreen'),
          )
          .toList();
      expect(homeClassFiles, contains(_homeScreenPath));
      expect(
        homeClassFiles.where((String path) => path.startsWith('test/')),
        isNotEmpty,
        reason: 'test 트리 순회가 비어 부재 단언이 공허해졌다',
      );

      final List<String> legacyClassFiles = scannedFiles
          .where(
            (String path) =>
                _readCodeWithoutLineComments(path).contains(legacyClassName),
          )
          .toList();
      expect(
        legacyClassFiles,
        isEmpty,
        reason: '옛 홈 클래스는 production 홈 · 데모로 나뉘어 사라졌다(D-01)',
      );

      // 파일 부재 — 양성 대조: 같은 경로 규칙의 새 홈 파일은 있다.
      expect(File(_homeScreenPath).existsSync(), isTrue);
      expect(
        File(
          'lib/features/home/presentation/$legacyFileStem.dart',
        ).existsSync(),
        isFalse,
      );
      expect(
        scannedFiles.where((String path) => path.contains(legacyFileStem)),
        isEmpty,
        reason: '옛 홈 화면 · 테스트 파일이 lib · test 에 남아 있다',
      );
    });
  });
}
