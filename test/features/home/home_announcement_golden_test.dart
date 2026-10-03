// Phase 17 Plan 17-13 Task 3 — 홈 공지 배너 golden (UI-SPEC §Golden 캡처 계약).
// Phase 17.1 Plan 03 — 대상을 production home(HomeScreen)으로 대체(D-23 · Q9-A).
//
// **캡처 계약:** 게스트 홈 · ko · 280×800 logical · DPR 3 · production 폰트
// FontLoader + KR · JP subset `fontFamilyFallback` · `find.byType(MaterialApp)`
// 전체 캡처 · `featureFlagsProvider` override(켜짐 + mockup 예시 ko 문구 fixture) ·
// `dismissedAnnouncementProvider` override(닫은 적 없음) · non-release 안내 카드.
// 비교 원본 =
// `.planning/phases/17.1-production-home-and-404-screen-split/mockups/adopted_home_guest_announcement_ko_280_{light,dark}.png`
// (사용자 sign-off 2026-10-03) — golden 은 그 PNG 와 byte 동일해야 한다(`cmp`).
// 불일치면 채택 PNG 를 덮어쓰지 말고 원인을 먼저 찾는다.
//
// 공지 문구는 mockup · golden fixture 전용 예시다 — ARB · RC 기본값이 아니다.

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/providers/locale_provider.dart';
import 'package:flutter_starter_kit/core/remote_config/feature_flag.dart';
import 'package:flutter_starter_kit/core/remote_config/feature_flags_provider.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/home/application/dismissed_announcement.dart';
import 'package:flutter_starter_kit/features/home/presentation/_widgets/announcement_bar.dart';
import 'package:flutter_starter_kit/features/home/presentation/home_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/presentation/settings_golden_harness.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

/// golden viewport 너비 (logical px) — 지원 최소 폭.
const double _goldenWidth = 280;

/// mockup harness 의 ko 예시 공지 문구 (`p17Copy['ko']['sample']` verbatim).
const String _sampleKo = '9월 30일(수) 오전 2시~4시에 서버 점검이 있어요. 점검 중에는 로그인할 수 없어요.';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await loadGoldenFonts();
  });

  group('Phase 17 Remote Config 공지 golden (T-17-RC)', () {
    for (final brightness in Brightness.values) {
      final mode = brightness.name;
      testWidgets(
        'T-171-HOME-golden · T-17-RC-10 게스트 ko 280×800 $mode = 채택 mockup byte 동일',
        (tester) async {
          tester.view.devicePixelRatio = kGoldenDpr;
          tester.view.physicalSize =
              const Size(_goldenWidth, kGoldenHeight) * kGoldenDpr;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);

          final anon = _MockFbUser();
          when(() => anon.isAnonymous).thenReturn(true);
          when(() => anon.uid).thenReturn('anon-uid');
          final auth = _MockFirebaseAuth();
          when(() => auth.currentUser).thenReturn(anon);

          await tester.pumpWidget(
            ProviderScope(
              key: UniqueKey(),
              overrides: [
                currentUserProvider.overrideWith((ref) => null),
                authRepositoryProvider.overrideWithValue(_MockAuthRepository()),
                isFirebaseInitializedProvider.overrideWithValue(false),
                firebaseAuthProvider.overrideWithValue(auth),
                authStateProvider.overrideWith((ref) => Stream.value(anon)),
                localeProvider.overrideWithBuild(
                  (ref, notifier) => const Locale('ko'),
                ),
                featureFlagsProvider.overrideWithBuild(
                  (ref, notifier) =>
                      const FeatureFlagValues(<FeatureFlag, Object>{
                        FeatureFlag.announcementBannerEnabled: true,
                        FeatureFlag.announcementMessageKo: _sampleKo,
                      }),
                ),
                dismissedAnnouncementProvider.overrideWithBuild(
                  (ref, notifier) async => null,
                ),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: goldenTheme(brightness, 'ko'),
                locale: const Locale('ko'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const HomeScreen(),
              ),
            ),
          );
          await settleGoldenAssets(tester);

          expect(tester.takeException(), isNull);
          final ko = lookupAppLocalizations(const Locale('ko'));
          expect(
            find.descendant(
              of: find.byType(AnnouncementBar),
              matching: find.text(_sampleKo),
            ),
            findsOneWidget,
          );
          expect(find.text(ko.homeGuestBanner), findsOneWidget);

          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              'goldens/home_171_guest_announcement_ko_280_$mode.png',
            ),
          );
        },
      );
    }
  });
}
