import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/l10n/app_title.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

void main() {
  // Phase 17.1 D-12 — 앱 제목 식은 resolveAppTitle 1곳이다(onGenerateTitle ·
  // 홈 AppBar 공유). appName 이 비면 로케일 ARB 제목, 아니면 그 값이다.
  group('Phase 17.1 production home (T-171-HOME)', () {
    for (final code in const ['ko', 'en', 'ja']) {
      test('T-171-HOME-02: $code — appName 비면 ARB appTitle · 있으면 appName', () {
        final l10n = lookupAppLocalizations(Locale(code));

        expect(resolveAppTitle(l10n, appName: ''), l10n.appTitle);
        expect(resolveAppTitle(l10n, appName: 'My App'), 'My App');
      });
    }
  });
}
