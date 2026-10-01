// Phase 17 Plan 17-13 — 홈 공지 배너 (UI-SPEC §(H) · Q1-B · D-37).
//
// T-17-RC-03 (Task 1): featureFlags override → 게스트 홈의 공지 배너가 게스트
// 바 위 · 문구 · semantics · 닫기 tooltip · 꺼짐이면 높이 0.

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/providers/locale_provider.dart';
import 'package:flutter_starter_kit/core/remote_config/feature_flag.dart';
import 'package:flutter_starter_kit/core/remote_config/feature_flags_provider.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/home/presentation/_widgets/announcement_bar.dart';
import 'package:flutter_starter_kit/features/home/presentation/environment_info_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

/// 공지 스위치 · 한국어 문구만 지정한 [FeatureFlagValues].
FeatureFlagValues _flags({required bool enabled, String ko = ''}) {
  return FeatureFlagValues(<FeatureFlag, Object>{
    FeatureFlag.announcementBannerEnabled: enabled,
    FeatureFlag.announcementMessageKo: ko,
  });
}

/// 게스트(익명) 홈을 ko 로 띄운다 — [flags] 가 `featureFlagsProvider` 값이다.
Future<void> _pumpGuestHome(
  WidgetTester tester, {
  required FeatureFlagValues flags,
}) async {
  tester.view.physicalSize = const Size(400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final anon = _MockFbUser();
  when(() => anon.isAnonymous).thenReturn(true);
  when(() => anon.uid).thenReturn('anon-uid');
  final auth = _MockFirebaseAuth();
  when(() => auth.currentUser).thenReturn(anon);

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(false),
        firebaseAuthProvider.overrideWithValue(auth),
        authStateProvider.overrideWith((ref) => Stream.value(anon)),
        currentUserProvider.overrideWith((ref) => null),
        authRepositoryProvider.overrideWithValue(_MockAuthRepository()),
        localeProvider.overrideWithBuild((ref, notifier) => const Locale('ko')),
        featureFlagsProvider.overrideWithBuild((ref, notifier) => flags),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const EnvironmentInfoScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final ko = lookupAppLocalizations(const Locale('ko'));

  group('Phase 17 Remote Config 공지 (T-17-RC)', () {
    testWidgets('T-17-RC-03 켜짐 + ko 문구 → 게스트 바 위 배너 · 꺼짐 → 높이 0', (
      tester,
    ) async {
      const message = '공지 A';
      final semantics = tester.ensureSemantics();
      await _pumpGuestHome(tester, flags: _flags(enabled: true, ko: message));

      expect(tester.takeException(), isNull);
      expect(find.byType(AnnouncementBar), findsOneWidget);
      final text = find.descendant(
        of: find.byType(AnnouncementBar),
        matching: find.text(message),
      );
      expect(text, findsOneWidget);
      expect(
        find.bySemanticsLabel('${ko.homeAnnouncementLabel}: $message'),
        findsOneWidget,
      );
      expect(find.byTooltip(ko.homeAnnouncementDismiss), findsOneWidget);
      expect(
        tester.getRect(find.byType(AnnouncementBar)).bottom,
        lessThanOrEqualTo(tester.getRect(find.text(ko.homeGuestBanner)).top),
      );
      expect(
        tester.getRect(find.byType(AnnouncementBar)).top,
        tester.getRect(find.byType(AppBar)).bottom,
      );
      semantics.dispose();

      await _pumpGuestHome(tester, flags: _flags(enabled: false, ko: message));
      expect(tester.takeException(), isNull);
      expect(find.byType(AnnouncementBar), findsOneWidget);
      expect(tester.getSize(find.byType(AnnouncementBar)), Size.zero);
      expect(find.text(message), findsNothing);
      expect(find.text(ko.homeGuestBanner), findsOneWidget);
    });
  });
}
