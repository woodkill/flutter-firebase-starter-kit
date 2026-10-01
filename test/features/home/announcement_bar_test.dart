// Phase 17 Plan 17-13 — 홈 공지 배너 (UI-SPEC §(H) · Q1-B · D-37).
//
// T-17-RC-03 (Task 1): featureFlags override → 게스트 홈의 공지 배너가 게스트
// 바 위 · 문구 · semantics · 닫기 tooltip · 꺼짐이면 높이 0.
// T-17-RC-07 ~ 09 (Task 3): 닫기 기억(D-12) — 즉시 숨김 · 재시작 후 숨김 · 문구
// 변경 · 언어 전환 재표시 · 정확 일치 비교 · 로딩 전 숨김 · 읽기 실패 = 표시.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/config/app_config.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/providers/locale_provider.dart';
import 'package:flutter_starter_kit/core/remote_config/feature_flag.dart';
import 'package:flutter_starter_kit/core/remote_config/feature_flags_provider.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/home/application/dismissed_announcement.dart';
import 'package:flutter_starter_kit/features/home/presentation/_widgets/announcement_bar.dart';
import 'package:flutter_starter_kit/features/home/presentation/environment_info_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

class _MockRemoteConfig extends Mock implements FirebaseRemoteConfig {}

/// 읽기가 실패하는 SharedPreferences 스토어 (T-17-RC-09 — 로드 실패 재현).
///
/// `setMockInitialValues` 의 in-memory 스토어는 읽기가 항상 성공하므로
/// `getInstance()` 가 쓰는 두 읽기 경로를 모두 던지게 한다.
class _ReadFailingPrefsStore extends SharedPreferencesStorePlatform {
  @override
  Future<bool> clear() async => true;

  @override
  Future<Map<String, Object>> getAll() async {
    throw StateError('prefs read failed');
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    throw StateError('prefs read failed');
  }

  @override
  Future<bool> remove(String key) async => true;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      true;
}

/// 닫은 문구 저장 키 (D-12).
const String _dismissedKey = 'home_announcement_dismissed_text';

/// 공지 스위치 · 한국어 문구만 지정한 [FeatureFlagValues].
FeatureFlagValues _flags({required bool enabled, String ko = ''}) {
  return FeatureFlagValues(<FeatureFlag, Object>{
    FeatureFlag.announcementBannerEnabled: enabled,
    FeatureFlag.announcementMessageKo: ko,
  });
}

/// [AnnouncementBar] 하나만 Scaffold 에 띄운다 — [overrides] 로 값을 준다.
///
/// [ProviderScope] 에 새 key 를 줘 매 호출이 새 컨테이너(= 앱 재시작)다.
Future<void> _pumpBar(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: overrides,
      // 앱(`app.dart`)처럼 MaterialApp 언어를 localeProvider 에 묶는다.
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          theme: AppTheme.light(),
          locale: ref.watch(localeProvider),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AnnouncementBar()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
  final en = lookupAppLocalizations(const Locale('en'));

  group('Phase 17 Remote Config 공지 (T-17-RC)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

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

    group('닫기 기억 (D-12)', () {
      testWidgets('T-17-RC-07 닫기 → 즉시 숨김 · 저장 · 재시작 후 숨김 · RC 문구 변경 → 재표시', (
        tester,
      ) async {
        // 콘솔 값 — onConfigUpdated 뒤 activate 가 바꾼다(D-10 실경로).
        final active = <String, Object>{
          'announcement_banner_enabled': true,
          'announcement_message_ko': '공지 A',
        };
        final rc = _MockRemoteConfig();
        when(() => rc.getBool(any())).thenAnswer((invocation) {
          final value = active[invocation.positionalArguments.first];
          return value is bool && value;
        });
        when(() => rc.getString(any())).thenAnswer((invocation) {
          final value = active[invocation.positionalArguments.first];
          return value is String ? value : '';
        });
        final updates = StreamController<RemoteConfigUpdate>.broadcast();
        addTearDown(updates.close);
        when(() => rc.onConfigUpdated).thenAnswer((_) => updates.stream);
        when(rc.activate).thenAnswer((_) async {
          active['announcement_message_ko'] = '공지 B';
          return true;
        });
        final overrides = <Override>[
          isFirebaseInitializedProvider.overrideWithValue(true),
          firebaseRemoteConfigProvider.overrideWithValue(rc),
          staticAuthProvidersProvider.overrideWithValue(<String, bool>{
            for (final id in kAllProviderIds) id: false,
          }),
          localeProvider.overrideWithBuild(
            (ref, notifier) => const Locale('ko'),
          ),
        ];

        await _pumpBar(tester, overrides: overrides);
        expect(find.text('공지 A'), findsOneWidget);

        await tester.tap(find.byTooltip(ko.homeAnnouncementDismiss));
        await tester.pump();
        expect(find.text('공지 A'), findsNothing);
        expect(tester.getSize(find.byType(AnnouncementBar)), Size.zero);
        await tester.pumpAndSettle();
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(_dismissedKey), '공지 A');

        // 앱 재시작(새 컨테이너) — 같은 문구는 숨김.
        await _pumpBar(tester, overrides: overrides);
        expect(find.text('공지 A'), findsNothing);
        expect(tester.takeException(), isNull);

        // 콘솔에서 문구 변경 → 실행 중 다시 표시.
        updates.add(RemoteConfigUpdate(<String>{'announcement_message_ko'}));
        await tester.pumpAndSettle();
        expect(find.text('공지 B'), findsOneWidget);
      });

      testWidgets('T-17-RC-08 정확 일치 비교 — 끝 공백 · 언어 전환은 다른 문구', (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          _dismissedKey: '공지 A',
        });
        await _pumpBar(
          tester,
          overrides: [
            localeProvider.overrideWithBuild(
              (ref, notifier) => const Locale('ko'),
            ),
            featureFlagsProvider.overrideWithBuild(
              (ref, notifier) => _flags(enabled: true, ko: '공지 A '),
            ),
          ],
        );
        expect(find.text('공지 A '), findsOneWidget);

        // en 으로 'Notice' 를 닫은 뒤 ko 로 바꾸면 ko 칸 문구가 보인다.
        SharedPreferences.setMockInitialValues(<String, Object>{});
        await _pumpBar(
          tester,
          overrides: [
            featureFlagsProvider.overrideWithBuild(
              (ref, notifier) => const FeatureFlagValues(<FeatureFlag, Object>{
                FeatureFlag.announcementBannerEnabled: true,
                FeatureFlag.announcementMessageKo: '공지 A',
                FeatureFlag.announcementMessageEn: 'Notice',
              }),
            ),
          ],
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(AnnouncementBar)),
        );
        await container
            .read(localeProvider.notifier)
            .setLocale(const Locale('en'));
        await tester.pumpAndSettle();
        expect(find.text('Notice'), findsOneWidget);

        await tester.tap(find.byTooltip(en.homeAnnouncementDismiss));
        await tester.pumpAndSettle();
        expect(find.text('Notice'), findsNothing);

        await container
            .read(localeProvider.notifier)
            .setLocale(const Locale('ko'));
        await tester.pumpAndSettle();
        expect(find.text('공지 A'), findsOneWidget);
      });

      testWidgets('T-17-RC-09 저장값 로딩 전 배너 0 · 읽기 실패면 닫은 적 없음 = 표시', (
        tester,
      ) async {
        final pending = Completer<String?>();
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              localeProvider.overrideWithBuild(
                (ref, notifier) => const Locale('ko'),
              ),
              featureFlagsProvider.overrideWithBuild(
                (ref, notifier) => _flags(enabled: true, ko: '공지 A'),
              ),
              dismissedAnnouncementProvider.overrideWithBuild(
                (ref, notifier) => pending.future,
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: AnnouncementBar()),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('공지 A'), findsNothing);
        expect(tester.getSize(find.byType(AnnouncementBar)), Size.zero);
        pending.complete(null);
        await tester.pumpAndSettle();
        expect(find.text('공지 A'), findsOneWidget);

        // 실제 Notifier · 읽기 실패 스토어 — 「닫은 적 없음」 으로 표시.
        final originalStore = SharedPreferencesStorePlatform.instance;
        SharedPreferencesStorePlatform.instance = _ReadFailingPrefsStore();
        SharedPreferences.resetStatic();
        addTearDown(() {
          SharedPreferencesStorePlatform.instance = originalStore;
          SharedPreferences.resetStatic();
        });
        await _pumpBar(
          tester,
          overrides: [
            localeProvider.overrideWithBuild(
              (ref, notifier) => const Locale('ko'),
            ),
            featureFlagsProvider.overrideWithBuild(
              (ref, notifier) => _flags(enabled: true, ko: '공지 A'),
            ),
          ],
        );
        expect(tester.takeException(), isNull);
        expect(find.text('공지 A'), findsOneWidget);
      });
    });
  });
}
