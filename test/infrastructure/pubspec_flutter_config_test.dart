// pubspec `flutter: config:` 가 web · 데스크톱 대상을 끄는 계약.
//
// **목적:** 킷은 Android · iOS 앱만 만든다. 그래서 `pubspec.yaml` 의 맨 위
// `flutter:` 절 안 `config:` 블록이 `enable-web` · `enable-macos-desktop` ·
// `enable-linux-desktop` · `enable-windows-desktop` 네 대상을 `false` 로 끈다.
// 이 값은 전역 `flutter config` 보다 앞서므로 `fvm flutter devices` 에 모바일
// 기기만 보이고, 기기를 지정하지 않은 `fvm flutter run` 이 그 대상의 Flutter
// 파일을 내려받지 않는다.
//
// **블록은 네 키만 담는다** — iOS SPM 스위치 키는 `test/ios/spm_policy_test.dart`
// 가 따로 보고, Android · iOS 대상을 끄는 키도 두지 않는다. 그래서 키 → 값 맵
// 전체 일치로 단언한다(키가 빠지거나 다른 키가 섞여도 실패한다).
//
// **YAML 을 파서 없이 줄 단위로 읽는다** — `package:yaml` 은 이 앱의 직접 의존이
// 아니어서 import 하면 `depend_on_referenced_packages` 진단이 난다.
//
// **주석을 먼저 걷어낸다** — pubspec 의 설명 주석이 키 이름을 말해도 단언이
// 공허하게 참이 되지 않게 한다.
//
// 사용자 안내: `docs/guide.md` 「Flutter SDK 상향 (FVM)」 ⑨.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

const String _pubspecPath = 'pubspec.yaml';

/// 킷이 `pubspec.yaml` `flutter: config:` 에 두는 값이다.
///
/// web 이나 데스크톱 대상을 켜면 pubspec 과 함께 이 맵에서도 그 줄을 지운다.
const Map<String, String> _expectedFlutterConfig = <String, String>{
  'enable-web': 'false',
  'enable-macos-desktop': 'false',
  'enable-linux-desktop': 'false',
  'enable-windows-desktop': 'false',
};

/// [pubspec] 의 맨 위 `flutter:` 절 안 `config:` 블록을 키 → 값 문자열 맵으로
/// 읽는다 — 없으면 빈 맵.
///
/// 들여쓰기 0 의 `flutter:` 첫 줄부터 다음 들여쓰기 0 줄 앞까지만 본다. 그 안에서
/// 들여쓰기 2 인 줄이 정확히 `  config:` 일 때만 블록 안으로 들어가고, 블록 안의
/// 들여쓰기 4 인 줄만 첫 `:` 앞뒤를 trim 해 담는다. 값은 문자열 그대로 둔다
/// (`false` 는 `'false'`).
Map<String, String> readFlutterConfig(String pubspec) {
  final List<String> lines = pubspec.split('\n');
  final int start = lines.indexOf('flutter:');
  if (start == -1) {
    return <String, String>{};
  }

  final config = <String, String>{};
  var inConfig = false;
  for (var i = start + 1; i < lines.length; i++) {
    final String line = lines[i];
    if (line.trim().isEmpty) {
      continue;
    }
    final int indent = line.length - line.trimLeft().length;
    if (indent == 0) {
      break;
    }
    if (indent == 2) {
      inConfig = line == '  config:';
      continue;
    }
    if (!inConfig || indent != 4) {
      continue;
    }
    final int colon = line.indexOf(':');
    if (colon == -1) {
      continue;
    }
    config[line.substring(0, colon).trim()] = line.substring(colon + 1).trim();
  }
  return config;
}

void main() {
  group('pubspec flutter: config: — web · 데스크톱 대상 끄기', () {
    test('킷 pubspec 의 flutter: config: 는 web · 데스크톱 네 대상만 false 로 끈다', () {
      final String pubspec = stripHashComments(readTrackedFile(_pubspecPath));

      // 양성 대조 — 맨 위 flutter: 절을 실제로 읽었다.
      expect(
        countExactLines(pubspec, 'flutter:'),
        1,
        reason: 'pubspec.yaml 에서 맨 위 flutter: 줄을 하나 찾지 못했다',
      );

      expect(
        readFlutterConfig(pubspec),
        equals(_expectedFlutterConfig),
        reason:
            'pubspec.yaml 의 flutter: config: 가 킷 값과 다르다 — web · 데스크톱 대상을 '
            '일부러 켰다면 이 시험의 _expectedFlutterConfig 에서도 그 줄을 '
            '지운다(docs/guide.md 「Flutter SDK 상향 (FVM)」 ⑨). 일부러가 아니면 merge · '
            'Flutter 상향이 그 줄을 바꿨는지 git diff pubspec.yaml 로 확인한다.',
      );
    });

    test('읽기 함수는 맨 위 flutter: 절의 config: 블록만 읽는다', () {
      // (a) dependencies 아래 들여쓴 flutter: 는 맨 위 절이 아니다.
      const nestedFlutter =
          'dependencies:\n'
          '  flutter:\n'
          '    sdk: flutter\n'
          '  config:\n'
          '    enable-web: false\n';
      expect(
        readFlutterConfig(nestedFlutter),
        isEmpty,
        reason: '들여쓴 flutter: 를 맨 위 절로 읽었다',
      );

      // (b) 다른 맨 위 절의 config: 는 읽지 않는다.
      const otherSection =
          'flutter:\n'
          '  generate: true\n'
          'other:\n'
          '  config:\n'
          '    enable-web: false\n';
      expect(
        readFlutterConfig(otherSection),
        isEmpty,
        reason: 'flutter: 절 밖의 config: 를 읽었다',
      );

      // (c) config: 뒤의 다른 키 · assets 목록은 담지 않는다.
      const withAssets =
          'flutter:\n'
          '  config:\n'
          '    enable-web: false\n'
          '\n'
          '  generate: true\n'
          '  assets:\n'
          '    - assets/x/\n';
      expect(
        readFlutterConfig(withAssets),
        equals(<String, String>{'enable-web': 'false'}),
        reason: 'config: 블록 밖의 줄을 담았다',
      );

      // (d) 주석 줄은 stripHashComments 뒤 사라진다.
      final String withComment = stripHashComments(
        'flutter:\n'
        '  config:\n'
        '    # enable-android: false\n'
        '    enable-web: false\n',
      );
      expect(
        readFlutterConfig(withComment),
        equals(<String, String>{'enable-web': 'false'}),
        reason: '주석 줄의 키를 담았다',
      );
    });

    test('네 키 가운데 하나가 true 이거나 빠지거나 다른 대상 키가 더해지면 기대값과 다르다', () {
      final String pubspec = stripHashComments(readTrackedFile(_pubspecPath));

      final mutants = <String, String>{
        'enable-web 을 true 로 바꿈': pubspec.replaceFirst(
          '    enable-web: false',
          '    enable-web: true',
        ),
        'enable-linux-desktop 줄 삭제': pubspec.replaceFirst(
          '    enable-linux-desktop: false\n',
          '',
        ),
        'enable-android: false 더함': pubspec.replaceFirst(
          '  config:\n',
          '  config:\n    enable-android: false\n',
        ),
        'enable-ios: false 더함': pubspec.replaceFirst(
          '  config:\n',
          '  config:\n    enable-ios: false\n',
        ),
      };

      mutants.forEach((String description, String mutant) {
        // 양성 대조 — 바꿀 자리가 실제로 있었다.
        expect(
          mutant,
          isNot(equals(pubspec)),
          reason: '변이 「$description」 의 바꿀 자리가 pubspec.yaml 에 없다',
        );
        expect(
          readFlutterConfig(mutant),
          isNot(equals(_expectedFlutterConfig)),
          reason: '변이 「$description」 를 기대값이 잡지 못했다',
        );
      });
    });
  });
}
