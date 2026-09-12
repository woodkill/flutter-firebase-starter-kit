import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/l10n/l10n_extensions.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// [BuildContext.l10n] 을 한 번 호출하고 결과를 그리는 최소 위젯.
class _L10nProbe extends StatelessWidget {
  const _L10nProbe();

  @override
  Widget build(BuildContext context) => Text(context.l10n.appTitle);
}

void main() {
  group('L10nX', () {
    testWidgets('delegate 가 등록된 트리에서는 현재 로케일의 번역을 반환한다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _L10nProbe(),
        ),
      );

      expect(find.text(await _appTitle(const Locale('en'))), findsOneWidget);
    });

    // WR-05 (Phase 04 리뷰) — delegate 누락 시 생성 코드의 `!` 가
    // "Null check operator used on a null value" 만 남기고 죽어 원인도 해법도
    // 드러나지 않는다. debug 빌드의 assert 가 원인을 지목하는지 잠근다.
    testWidgets('delegate 가 없으면 원인을 지목하는 assert 로 실패한다', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _L10nProbe()));

      final exception = tester.takeException();
      expect(exception, isA<AssertionError>());
      expect(exception.toString(), contains('AppLocalizations delegate 가 없다'));
    });
  });
}

/// 지정한 [locale] 의 `appTitle` 번역을 반환한다.
Future<String> _appTitle(Locale locale) async {
  final l10n = await AppLocalizations.delegate.load(locale);
  return l10n.appTitle;
}
