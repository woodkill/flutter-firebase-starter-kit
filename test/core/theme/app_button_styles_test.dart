// 삭제(파괴) 버튼 스타일 도우미 계약 — 라이트 · 다크에서 `error` / `onError` 를
// 쓰고 비활성 모양은 위젯 기본에 맡긴다.

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/core/theme/app_button_styles.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('삭제 버튼 스타일', () {
    const enabled = <WidgetState>{};
    const disabled = <WidgetState>{WidgetState.disabled};

    test('라이트 · 다크의 error 가 서로 다르다 (아래 단언이 공허하지 않다)', () {
      expect(
        AppTheme.light().colorScheme.error,
        isNot(AppTheme.dark().colorScheme.error),
      );
    });

    for (final (String label, ColorScheme Function() build)
        in <(String, ColorScheme Function())>[
          ('light', () => AppTheme.light().colorScheme),
          ('dark', () => AppTheme.dark().colorScheme),
        ]) {
      test('$label — TextButton 은 글자가 error 다', () {
        final ColorScheme scheme = build();
        final ButtonStyle style = scheme.destructiveTextButtonStyle;

        expect(style.foregroundColor!.resolve(enabled), scheme.error);
        expect(style.foregroundColor!.resolve(disabled), isNull);
      });

      test('$label — FilledButton 은 바탕이 error · 글자가 onError 다', () {
        final ColorScheme scheme = build();
        final ButtonStyle style = scheme.destructiveFilledButtonStyle;

        expect(style.backgroundColor!.resolve(enabled), scheme.error);
        expect(style.foregroundColor!.resolve(enabled), scheme.onError);
        expect(style.backgroundColor!.resolve(disabled), isNull);
        expect(style.foregroundColor!.resolve(disabled), isNull);
      });

      test('$label — OutlinedButton 은 글자가 error 다', () {
        final ColorScheme scheme = build();
        final ButtonStyle style = scheme.destructiveOutlinedButtonStyle;

        expect(style.foregroundColor!.resolve(enabled), scheme.error);
        expect(style.foregroundColor!.resolve(disabled), isNull);
      });
    }
  });
}
