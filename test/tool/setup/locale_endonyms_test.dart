// 위저드가 lib 의 언어 원어 이름 표를 글자로 읽는 도우미
// (`tool/setup/locale_endonyms.dart`)를 임시 트리로 고정한다.
//
// 파일은 `Directory.systemTemp` 아래 임시 프로젝트에만 쓰고 시험마다 지운다.
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/locale_endonyms.dart';

/// 시험 트리에 둘 원어 이름 표 사본 — 한 줄에 두 항목 · 끝 쉼표 없음 · 앞뒤 다른 코드.
const String fixtureEndonymsSource = '''
import 'package:flutter/widgets.dart' show Locale;

/// 지원 언어 표 — 문서 주석에도 kLocaleEndonyms 글자가 있다.
const Map<String, String> kLocaleEndonyms = <String, String>{
  'en': 'English', 'ko': '한국어',
  'ja': '日本語'
};

/// 표 뒤의 다른 맵 — 읽지 않는다.
const Map<String, String> otherNames = <String, String>{
  'fr': 'Français',
};

String localeDisplayName(Locale locale) =>
    kLocaleEndonyms[locale.languageCode] ?? locale.languageCode;
''';

void main() {
  late Directory tree;

  setUp(() {
    tree = Directory.systemTemp.createTempSync('locale_endonyms_test_');
  });

  tearDown(() {
    if (tree.existsSync()) tree.deleteSync(recursive: true);
  });

  /// 시험 트리의 표 파일 자리에 [content] 를 쓴다.
  void writeEndonymsFile(String content) {
    File('${tree.path}/$localeEndonymsPath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  test('T-23-ENDO-01: 표 사본에서 세 항목만 글자 그대로 읽는다', () {
    writeEndonymsFile(fixtureEndonymsSource);

    expect(readLocaleEndonyms(tree.path), <String, String>{
      'en': 'English',
      'ko': '한국어',
      'ja': '日本語',
    });
  });

  test('T-23-ENDO-02: 파일이 없으면 빈 맵', () {
    expect(readLocaleEndonyms(tree.path), isEmpty);
  });

  test('T-23-ENDO-02: kLocaleEndonyms 선언이 없으면 빈 맵', () {
    writeEndonymsFile(
      "const Map<String, String> names = <String, String>{'ko': '한국어'};\n",
    );

    expect(readLocaleEndonyms(tree.path), isEmpty);
  });

  group('T-23-ENDO-03: formatLocaleLabel', () {
    const endonyms = <String, String>{
      'ko': '한국어',
      'pt': 'Português',
      'zh': '中文',
    };

    test('T-23-ENDO-03: 항목이 있으면 코드 + 원어 이름 · 없으면 코드만', () {
      expect(formatLocaleLabel('ko', endonyms), 'ko (한국어)');
      expect(formatLocaleLabel('fr', endonyms), 'fr');
    });

    test('T-23-ENDO-03: 변형은 언어 부분으로 물러난다', () {
      expect(formatLocaleLabel('pt_BR', endonyms), 'pt_BR (Português)');
      expect(formatLocaleLabel('zh_Hant', endonyms), 'zh_Hant (中文)');
    });

    test('T-23-ENDO-03: 정확한 항목(pt-BR · pt_BR)을 먼저 쓴다', () {
      expect(
        formatLocaleLabel('pt_BR', <String, String>{
          ...endonyms,
          'pt-BR': 'Português (Brasil)',
        }),
        'pt_BR (Português (Brasil))',
      );
      expect(
        formatLocaleLabel('pt_BR', <String, String>{
          ...endonyms,
          'pt_BR': 'Português do Brasil',
        }),
        'pt_BR (Português do Brasil)',
      );
    });
  });
}
