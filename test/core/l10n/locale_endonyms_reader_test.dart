import 'package:flutter_starter_kit/core/l10n/locale_display_names.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/setup/locale_endonyms.dart';

void main() {
  // 위저드는 Flutter 를 import 하지 못해 원어 이름 표를 소스 글자로 읽는다.
  // 읽은 맵이 앱이 쓰는 상수와 같아야 위저드 질문의 언어 표시가 앱 언어 선택
  // 화면과 어긋나지 않는다 — 표가 바뀌면 이 시험이 먼저 깨진다.
  test('T-23-ENDO-04: 위저드가 글자로 읽은 원어 이름 표 == kLocaleEndonyms', () {
    final Map<String, String> read = readLocaleEndonyms('.');

    expect(read, isNotEmpty);
    expect(read, kLocaleEndonyms);
  });
}
