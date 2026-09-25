// Phase 09 code review WR-01 회귀 가드 (2026-09-12).
//
// **왜 이 파일이 필요한가.**
// provider 1개 추가 시 presentation 계층에서 4곳을 고쳐야 하는데, 그중 3곳의
// 누락 증상이 "analyze 통과 → 앱 실행 중 런타임 crash" 다.
//
// | 수정 지점 | 누락 시 방어선 |
// | --- | --- |
// | `kAllProviderIds` + `AccountProvider` enum | 컴파일 (exhaustive switch) |
// | `social_provider_resolver.dart` 의 `resolveSocialProvider` switch | **없었음** |
// | `social_button.dart` 의 `providerId` switch | **없었음** |
// | `social_button.dart` 의 `_resolveLabel` switch | **없었음** |
//
// 아래 3곳은 모두 `_ => throw UnsupportedError(...)` 로 끝나며,
// `resolveSocialProvider` 는 `LoginScreen.build()` / `LoginPromptSheet.build()`
// 안에서 호출되므로 누락 시 `/login` 진입 즉시 화면 전체가 red screen 이 된다.
//
// **이 테스트의 계약:** 진실원인 [kAllProviderIds] 를 순회하며 위 3개 switch
// 가 전부 해당 슬러그를 처리하는지 단언한다. 새 provider 를 [kAllProviderIds]
// 에 추가하면 (1항이 컴파일로 강제하므로 반드시 추가된다) 나머지 3곳을
// 빠뜨린 순간 **게이트 단계에서** FAIL 한다 — 사용자 단말의 crash 로 미루지
// 않는다.
//
// **컴파일 시점 방어의 대안이 아니다.** 근본 해법은 `AuthStrategy.providerId`
// 를 `String` → enum 으로 좁혀 3개 switch 를 exhaustive 로 만드는 것이지만
// (09-REVIEW WR-01 Fix), 그 전환은 lib 99곳 · test 38파일 184곳에 파급되고
// Firebase 자체의 `User.providerData[i].providerId` (String URI) 와 이름이
// 겹쳐 별도 phase 가 필요하다. 본 테스트는 그 전환 전까지의 게이트 방어선이며,
// 전환이 완료되면 3개 switch 가 컴파일로 강제되므로 폐기해도 된다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_helpers/social_provider_resolver.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_button.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// 등록 커버리지 검증 전용 [AuthStrategy] 대역.
///
/// `signIn` 은 호출되지 않는다 — 본 테스트는 `isDisabled: true` 로만 렌더하며
/// 탭 동작이 아니라 **switch 커버리지**를 검증한다.
final class _ProbeStrategy extends AuthStrategy {
  const _ProbeStrategy(this._providerId, this._labelKey) : super();

  final String _providerId;
  final String _labelKey;

  @override
  String get providerId => _providerId;

  @override
  String get labelKey => _labelKey;

  @override
  Future<void> signIn(WidgetRef ref) async {
    throw UnsupportedError('커버리지 probe 는 signIn 을 호출하지 않는다.');
  }
}

/// 슬러그 → ARB 라벨 키 규약 (`auth{Provider}SignIn`).
///
/// `auth_strategies_registry.dart` 신규 provider 체크리스트 7항이 못 박은
/// 명명 규약이며, 6 production strategy 전부가 이 규약을 따른다
/// (`authGoogleSignIn` / `authLineSignIn` ...).
String _labelKeyFor(String providerId) =>
    'auth${providerId[0].toUpperCase()}${providerId.substring(1)}SignIn';

/// 영문 로케일 + light theme 으로 pump 하는 helper
/// (`social_button_test.dart` 의 동명 helper mirror).
Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('WR-01 — 신규 provider 등록 누락 회귀 가드 (kAllProviderIds 순회)', () {
    test('진실원 자체가 비어 있지 않다 (순회 테스트의 vacuous pass 차단)', () {
      expect(kAllProviderIds, isNotEmpty);
    });

    for (final providerId in kAllProviderIds) {
      test('resolveSocialProvider 가 "$providerId" 를 처리한다 '
          '(누락 시 /login build 중 UnsupportedError → red screen)', () {
        expect(() => resolveSocialProvider(providerId), returnsNormally);
      });

      testWidgets('SocialButton 이 "$providerId" 를 렌더한다 — providerId switch + '
          '_resolveLabel switch 동시 커버 (누락 시 버튼 렌더 중 UnsupportedError)', (
        tester,
      ) async {
        // 자상 + 라벨 Row 가 기본 800x600 에서 overflow 하므로 모바일 폭으로
        // 좁힌다 (`social_button_test.dart` 의 412dp 선례 동일).
        await tester.binding.setSurfaceSize(const Size(412, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _wrap(
            SocialButton(
              strategy: _ProbeStrategy(providerId, _labelKeyFor(providerId)),
              isDisabled: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(BrandedSocialButton), findsOneWidget);
      });
    }
  });
}
