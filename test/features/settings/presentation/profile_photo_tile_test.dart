// Phase 17 Plan 17-17 — 프로필 사진 행 · 사진 메뉴 · Notifier 테스트 (T-17-PHOTO).
//
// - T-17-PHOTO-03: 설정 「내 계정」 첫 행 = 사진 행 → 탭 → 메뉴 2항목(사진
//   없음) → 「갤러리에서 사진 선택」 → 시트 닫힘 · 업로드 1회 · 성공 SnackBar.
// - T-17-PHOTO-10: Notifier 층 안전망(D-20 ②) — repository 밖 throw 는 기록 1회 ·
//   결과 failed · busy 해제, repository Failure 는 기록 0.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/notifications/application/notification_settings_notifier.dart';
import 'package:flutter_starter_kit/features/settings/application/profile_photo_notifier.dart';
import 'package:flutter_starter_kit/features/settings/data/profile_photo_repository.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/profile_photo_sheet.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/profile_photo_tile.dart';
import 'package:flutter_starter_kit/features/settings/presentation/settings_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

import 'settings_golden_harness.dart' show kGoldenSixStrategies;

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

class _MockFbUser extends Mock implements fb.User {}

class _FakeStackTrace extends Fake implements StackTrace {}

/// [ProfilePhotoRepository] 대체 — 호출 uid 를 기록하고 [onUpload] 결과를 준다.
class _FakeProfilePhotoRepository implements ProfilePhotoRepository {
  _FakeProfilePhotoRepository({required this.onUpload});

  /// pickAndUpload 동작.
  Future<Result<String?>> Function() onUpload;

  /// pickAndUpload 에 넘어온 uid 목록.
  final List<String> uploadUids = <String>[];

  @override
  Future<Result<String?>> pickAndUpload(String uid) {
    uploadUids.add(uid);
    return onUpload();
  }
}

/// 업로드 사진 · 소셜 사진 없는 정식 사용자 fixture.
final User _user = User(
  uid: 'u1',
  email: 'me@example.com',
  emailVerified: true,
  createdAt: DateTime.utc(2026, 10),
  providerIds: const <String>['google.com'],
  signUpProviderId: 'google.com',
);

/// 사진 출처 stream fixture — 업로드 사진 없음.
const UserProviderRecord _kNoPhotoRecord = (
  linkedProviderIds: <String>[],
  signUpProviderId: null,
  customPhotoUrl: null,
);

/// uid 'u1' · 비익명 Firebase 사용자 mock.
fb.User _regularFbUser() {
  final user = _MockFbUser();
  when(() => user.uid).thenReturn('u1');
  when(() => user.isAnonymous).thenReturn(false);
  return user;
}

/// production [SettingsScreen] 을 ko 로 pump 한다 (800×600 기본 viewport).
Future<void> _pumpSettings(
  WidgetTester tester, {
  required ProfilePhotoRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => _user),
        activeStrategiesProvider.overrideWithValue(kGoldenSixStrategies),
        notificationSettingsProvider.overrideWithBuild(
          (ref, notifier) => false,
        ),
        linkedProvidersStreamProvider(
          'u1',
        ).overrideWith((ref) => Stream.value(_kNoPhotoRecord)),
        authStateProvider.overrideWithValue(AsyncData(_regularFbUser())),
        profilePhotoRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeStackTrace());
  });

  group('Phase 17 프로필 사진 (T-17-PHOTO)', () {
    testWidgets('T-17-PHOTO-03: 첫 행 사진 행(값 「없음」) → 메뉴 2항목 → 선택 → '
        '시트 닫힘 · 업로드 1회 · 성공 SnackBar', (tester) async {
      final repository = _FakeProfilePhotoRepository(
        onUpload: () async => const Result.success('https://x/avatar?v=1'),
      );
      await _pumpSettings(tester, repository: repository);

      // 「내 계정」 heading 다음 · 이메일 행 위 = 사진 행.
      final row = find.descendant(
        of: find.byType(ProfilePhotoTile),
        matching: find.byType(ListTile),
      );
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('프로필 사진')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('없음')),
        findsOneWidget,
      );
      final emailRow = find.ancestor(
        of: find.byIcon(Icons.alternate_email),
        matching: find.byType(ListTile),
      );
      expect(
        tester.getTopLeft(find.text('내 계정')).dy,
        lessThan(tester.getTopLeft(row).dy),
      );
      expect(
        tester.getTopLeft(row).dy,
        lessThan(tester.getTopLeft(emailRow).dy),
      );

      await tester.tap(row);
      await tester.pumpAndSettle();

      // 사진 메뉴 — 제목 · 선택 · 취소 (업로드 사진 없음 = 2항목).
      final sheet = find.byType(ProfilePhotoSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.text('프로필 사진')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.byType(ListTile)),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: sheet, matching: find.text('갤러리에서 사진 선택')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('취소')),
        findsOneWidget,
      );
      expect(find.text('올린 사진 삭제'), findsNothing);

      await tester.tap(find.text('갤러리에서 사진 선택'));
      await tester.pumpAndSettle();

      expect(find.byType(ProfilePhotoSheet), findsNothing);
      expect(repository.uploadUids, <String>['u1']);
      expect(find.text('프로필 사진을 변경했습니다.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('T-17-PHOTO-03: 취소 항목 → 시트 닫힘 · 업로드 0 · SnackBar 0', (
      tester,
    ) async {
      final repository = _FakeProfilePhotoRepository(
        onUpload: () async => const Result.success('https://x/avatar?v=1'),
      );
      await _pumpSettings(tester, repository: repository);

      await tester.tap(
        find.descendant(
          of: find.byType(ProfilePhotoTile),
          matching: find.byType(ListTile),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(find.byType(ProfilePhotoSheet), findsNothing);
      expect(repository.uploadUids, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('T-17-PHOTO-03: 갤러리 취소(Success(null)) → SnackBar 0', (
      tester,
    ) async {
      final repository = _FakeProfilePhotoRepository(
        onUpload: () async => const Result<String?>.success(null),
      );
      await _pumpSettings(tester, repository: repository);

      await tester.tap(
        find.descendant(
          of: find.byType(ProfilePhotoTile),
          matching: find.byType(ListTile),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('갤러리에서 사진 선택'));
      await tester.pumpAndSettle();

      expect(repository.uploadUids, <String>['u1']);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('Phase 17 프로필 사진 Notifier 층 안전망 (D-20 ②)', () {
    late _MockCrashlyticsService crashlytics;

    setUp(() {
      crashlytics = _MockCrashlyticsService();
      when(
        () => crashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      ).thenAnswer((_) async {});
    });

    /// [repository] 를 주입한 container — notifier 를 listen 해 살려 둔다.
    ProviderContainer createContainer(ProfilePhotoRepository repository) {
      final container = ProviderContainer.test(
        overrides: [
          profilePhotoRepositoryProvider.overrideWithValue(repository),
          crashlyticsServiceProvider.overrideWithValue(crashlytics),
          authStateProvider.overrideWithValue(AsyncData(_regularFbUser())),
        ],
      );
      container.listen(profilePhotoProvider, (_, _) {});
      return container;
    }

    test('T-17-PHOTO-10: repository 밖 StateError → failed · busy false · '
        '기록 1회(reason profile_photo_notifier_upload)', () async {
      final container = createContainer(
        _FakeProfilePhotoRepository(onUpload: () => throw StateError('boom')),
      );

      final result = await container
          .read(profilePhotoProvider.notifier)
          .pickAndUpload();

      expect(result, ProfilePhotoActionResult.failed);
      expect(container.read(profilePhotoProvider), isFalse);
      verify(
        () => crashlytics.recordError(
          any<Object>(that: isA<StateError>()),
          any<StackTrace?>(),
          reason: 'profile_photo_notifier_upload',
          fatal: false,
        ),
      ).called(1);
    });

    test('T-17-PHOTO-10: repository Failure(ProfilePhotoUploadException) → '
        'failed · notifier 층 기록 0', () async {
      final container = createContainer(
        _FakeProfilePhotoRepository(
          onUpload: () async =>
              const Result<String?>.failure(ProfilePhotoUploadException()),
        ),
      );

      final result = await container
          .read(profilePhotoProvider.notifier)
          .pickAndUpload();

      expect(result, ProfilePhotoActionResult.failed);
      expect(container.read(profilePhotoProvider), isFalse);
      verifyNever(
        () => crashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      );
    });

    test('T-17-PHOTO-10: 진행 중 busy true · 완료 뒤 false · 성공', () async {
      final completer = Completer<Result<String?>>();
      final container = createContainer(
        _FakeProfilePhotoRepository(onUpload: () => completer.future),
      );
      final notifier = container.read(profilePhotoProvider.notifier);

      final pending = notifier.pickAndUpload();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(profilePhotoProvider), isTrue);
      // 진행 중 재호출 = cancelled (동시 업로드 0).
      expect(
        await notifier.pickAndUpload(),
        ProfilePhotoActionResult.cancelled,
      );

      completer.complete(const Result.success('https://x/avatar?v=1'));
      expect(await pending, ProfilePhotoActionResult.success);
      expect(container.read(profilePhotoProvider), isFalse);
    });

    test('T-17-PHOTO-10: 익명 사용자 → failed · repository 호출 0', () async {
      final anonymous = _MockFbUser();
      when(() => anonymous.uid).thenReturn('anon');
      when(() => anonymous.isAnonymous).thenReturn(true);
      final repository = _FakeProfilePhotoRepository(
        onUpload: () async => const Result.success('https://x/avatar?v=1'),
      );
      final container = ProviderContainer.test(
        overrides: [
          profilePhotoRepositoryProvider.overrideWithValue(repository),
          crashlyticsServiceProvider.overrideWithValue(crashlytics),
          authStateProvider.overrideWithValue(AsyncData(anonymous)),
        ],
      );
      container.listen(profilePhotoProvider, (_, _) {});

      final result = await container
          .read(profilePhotoProvider.notifier)
          .pickAndUpload();

      expect(result, ProfilePhotoActionResult.failed);
      expect(repository.uploadUids, isEmpty);
    });
  });
}
