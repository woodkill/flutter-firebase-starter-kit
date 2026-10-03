// Phase 17 Plan 17-17 — 프로필 사진 행 · 사진 메뉴 · Notifier 테스트 (T-17-PHOTO).
//
// - T-17-PHOTO-03: 계정 화면 「프로필」 첫 행 = 사진 행 → 탭 → 메뉴 2항목(사진
//   없음) → 「갤러리에서 사진 선택」 → 시트 닫힘 · 업로드 1회 · 성공 SnackBar.
// - T-17-PHOTO-05: 업로드 사진 있음 → 메뉴 3항목 · 삭제 아이콘 기본 색 · 확인
//   다이얼로그 없이 삭제 1회 · 성공 SnackBar · 취소 = 호출 0.
// - T-17-PHOTO-06: 행 상태 — 출처 loading(「불러오는 중」 · 탭 비활성) · error
//   (업로드 사진 없음 취급 · 탭 가능 · 배너 0) · busy(진행 링 · 「사진을 올리는
//   중…」 · 탭 비활성) · 업로드 실패(SnackBar · 값 이전 상태).
// - T-17-PHOTO-07: ja 280 — 값 「アップロードした写真」 2줄 · 삭제 항목 2줄 ·
//   overflow 0.
// - T-17-PHOTO-10: Notifier 층 안전망(D-20 ②) — repository 밖 throw 는 기록 1회 ·
//   결과 failed · busy 해제, repository Failure 는 기록 0.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:flutter_starter_kit/features/settings/presentation/account_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_starter_kit/shared/widgets/error_banner.dart';

import 'settings_golden_harness.dart' show kGoldenSixStrategies;

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

class _MockFbUser extends Mock implements fb.User {}

class _FakeStackTrace extends Fake implements StackTrace {}

/// [ProfilePhotoRepository] 대체 — 호출 uid 를 기록하고 [onUpload] ·
/// [onRemove] 결과를 준다.
class _FakeProfilePhotoRepository implements ProfilePhotoRepository {
  _FakeProfilePhotoRepository({required this.onUpload, this.onRemove});

  /// pickAndUpload 동작.
  Future<Result<String?>> Function() onUpload;

  /// remove 동작 (null = 성공).
  Future<Result<void>> Function()? onRemove;

  /// pickAndUpload 에 넘어온 uid 목록.
  final List<String> uploadUids = <String>[];

  /// remove 에 넘어온 uid 목록.
  final List<String> removeUids = <String>[];

  @override
  Future<Result<String?>> pickAndUpload(String uid) {
    uploadUids.add(uid);
    return onUpload();
  }

  @override
  Future<Result<void>> remove(String uid) {
    removeUids.add(uid);
    return onRemove?.call() ?? Future.value(const Result.success(null));
  }
}

/// 업로드 사진 URL fixture — 합성 값.
const String _kCustomUrl = 'https://example.com/avatar.jpg?alt=media&v=1';

/// 업로드 사진 · 소셜 사진 없는 정식 사용자 fixture.
final User _user = User(
  uid: 'u1',
  email: 'me@example.com',
  emailVerified: true,
  createdAt: DateTime.utc(2026, 10),
  providerIds: const <String>['google.com'],
  signUpProviderId: 'google.com',
);

/// [_user] 에 업로드 사진이 있는 fixture (D-17 — 표시 사진 = 업로드 사진).
final User _customUser = _user.copyWith(
  customPhotoUrl: _kCustomUrl,
  photoUrl: _kCustomUrl,
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

/// production [AccountScreen] 을 pump 한다 (기본 ko · 800×600 viewport).
///
/// Phase 17.1 D-02 — 사진 행은 정식 사용자 계정 화면의 첫 행이다(17 D-18 정정).
///
/// [records] 는 사진 출처 stream (기본 = 업로드 사진 없음 data 1회). 재시도는
/// 끈다 — error 상태가 재구독으로 흔들리지 않게 한다.
Future<void> _pumpAccount(
  WidgetTester tester, {
  required ProfilePhotoRepository repository,
  User? user,
  Stream<UserProviderRecord> Function()? records,
  Locale locale = const Locale('ko'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        currentUserProvider.overrideWith((ref) => user ?? _user),
        activeStrategiesProvider.overrideWithValue(kGoldenSixStrategies),
        notificationSettingsProvider.overrideWithBuild(
          (ref, notifier) => false,
        ),
        linkedProvidersStreamProvider('u1').overrideWith(
          (ref) => records?.call() ?? Stream.value(_kNoPhotoRecord),
        ),
        authStateProvider.overrideWithValue(AsyncData(_regularFbUser())),
        profilePhotoRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AccountScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 계정 화면의 사진 행 [ListTile].
Finder _photoRow() => find.descendant(
  of: find.byType(ProfilePhotoTile),
  matching: find.byType(ListTile),
);

/// [finder] 문단의 렌더 줄 수 — 같은 폭 · maxLines · ellipsis 로 재배치해 센다.
int _lineCountOf(WidgetTester tester, Finder finder) {
  final rp = tester.renderObject<RenderParagraph>(finder);
  expect(rp.maxLines, isNull, reason: '줄 수 제한 없음(자르지 않음)');
  expect(rp.didExceedMaxLines, isFalse);
  final painter = TextPainter(
    text: rp.text,
    textDirection: rp.textDirection,
    textScaler: rp.textScaler,
    locale: rp.locale,
    strutStyle: rp.strutStyle,
    textWidthBasis: rp.textWidthBasis,
    textHeightBehavior: rp.textHeightBehavior,
  )..layout(maxWidth: rp.constraints.maxWidth);
  final count = painter.computeLineMetrics().length;
  painter.dispose();
  return count;
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
      await _pumpAccount(tester, repository: repository);

      // 「프로필」 heading 다음 · 이메일 행 위 = 사진 행 (Phase 17.1 계정 화면).
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
        tester.getTopLeft(find.text('프로필')).dy,
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
      await _pumpAccount(tester, repository: repository);

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
      await _pumpAccount(tester, repository: repository);

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

  group('Phase 17 사진 메뉴 · 삭제 · 행 상태 (T-17-PHOTO)', () {
    testWidgets('T-17-PHOTO-05: 업로드 사진 있음 → 메뉴 3항목 · 삭제 아이콘 기본 색 · '
        '확인 없이 삭제 1회 · 성공 SnackBar', (tester) async {
      final repository = _FakeProfilePhotoRepository(
        onUpload: () async => const Result.success(_kCustomUrl),
      );
      await _pumpAccount(tester, repository: repository, user: _customUser);

      final row = _photoRow();
      expect(
        find.descendant(of: row, matching: find.text('직접 올린 사진')),
        findsOneWidget,
      );
      await tester.tap(row);
      await tester.pumpAndSettle();

      final sheet = find.byType(ProfilePhotoSheet);
      expect(
        find.descendant(of: sheet, matching: find.byType(ListTile)),
        findsNWidgets(3),
      );
      // 삭제 항목 — destructive 색 아님(기본 색 · Icon.color 미지정).
      final deleteIcon = tester.widget<Icon>(
        find.descendant(of: sheet, matching: find.byIcon(Icons.delete_outline)),
      );
      expect(deleteIcon.color, isNull);
      final deleteTitle = tester.widget<Text>(
        find.descendant(of: sheet, matching: find.text('올린 사진 삭제')),
      );
      final scheme = Theme.of(tester.element(sheet)).colorScheme;
      expect(deleteTitle.style?.color, isNot(scheme.error));

      await tester.tap(find.text('올린 사진 삭제'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ProfilePhotoSheet), findsNothing);
      expect(repository.removeUids, <String>['u1']);
      expect(repository.uploadUids, isEmpty);
      expect(find.text('올린 사진을 삭제했습니다.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('T-17-PHOTO-05: 업로드 사진 있음 · 취소 → 시트 닫힘 · 호출 0', (tester) async {
      final repository = _FakeProfilePhotoRepository(
        onUpload: () async => const Result.success(_kCustomUrl),
      );
      await _pumpAccount(tester, repository: repository, user: _customUser);

      await tester.tap(_photoRow());
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(find.byType(ProfilePhotoSheet), findsNothing);
      expect(repository.removeUids, isEmpty);
      expect(repository.uploadUids, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('T-17-PHOTO-05: 삭제 실패 → errorProfilePhotoRemoveFailed '
        'SnackBar · 값 이전 상태', (tester) async {
      final repository = _FakeProfilePhotoRepository(
        onUpload: () async => const Result.success(_kCustomUrl),
        onRemove: () async =>
            const Result<void>.failure(ProfilePhotoRemoveException()),
      );
      await _pumpAccount(tester, repository: repository, user: _customUser);

      await tester.tap(_photoRow());
      await tester.pumpAndSettle();
      await tester.tap(find.text('올린 사진 삭제'));
      await tester.pumpAndSettle();

      expect(find.text('사진을 삭제하지 못했습니다. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
      expect(
        find.descendant(of: _photoRow(), matching: find.text('직접 올린 사진')),
        findsOneWidget,
      );
    });

    testWidgets('T-17-PHOTO-06: 출처 loading → 「불러오는 중」 · 탭 비활성', (tester) async {
      final controller = StreamController<UserProviderRecord>();
      addTearDown(controller.close);
      await _pumpAccount(
        tester,
        repository: _FakeProfilePhotoRepository(
          onUpload: () async => const Result.success(_kCustomUrl),
        ),
        records: () => controller.stream,
      );

      final row = _photoRow();
      expect(
        find.descendant(of: row, matching: find.text('불러오는 중')),
        findsOneWidget,
      );
      expect(tester.widget<ListTile>(row).onTap, isNull);
    });

    testWidgets('T-17-PHOTO-06: 출처 error → 업로드 사진 없음 취급 · 탭 가능 · '
        '배너 0 · 메뉴 2항목', (tester) async {
      await _pumpAccount(
        tester,
        repository: _FakeProfilePhotoRepository(
          onUpload: () async => const Result.success(_kCustomUrl),
        ),
        // currentUser 는 업로드 사진을 들고 있어도 출처 읽기 실패면 없음 취급.
        user: _customUser,
        records: () => Stream.error(StateError('read failed')),
      );

      final row = _photoRow();
      expect(
        find.descendant(of: row, matching: find.text('없음')),
        findsOneWidget,
      );
      expect(find.byType(ErrorBanner), findsNothing);
      expect(tester.widget<ListTile>(row).onTap, isNotNull);

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ProfilePhotoSheet),
          matching: find.byType(ListTile),
        ),
        findsNWidgets(2),
      );
      expect(find.text('올린 사진 삭제'), findsNothing);
    });

    testWidgets('T-17-PHOTO-06: 업로드 중 → 진행 링(40 dp) · 「사진을 올리는 중…」 · '
        '탭 비활성 → 실패 SnackBar · 값 이전 상태', (tester) async {
      final completer = Completer<Result<String?>>();
      await _pumpAccount(
        tester,
        repository: _FakeProfilePhotoRepository(
          onUpload: () => completer.future,
        ),
      );

      await tester.tap(_photoRow());
      await tester.pumpAndSettle();
      await tester.tap(find.text('갤러리에서 사진 선택'));
      // 진행 링이 계속 돌아 settle 하지 않는다 — 시트 닫힘 전환만 흘린다.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final row = _photoRow();
      expect(
        find.descendant(of: row, matching: find.text('사진을 올리는 중…')),
        findsOneWidget,
      );
      expect(tester.widget<ListTile>(row).onTap, isNull);
      final ring = find.descendant(
        of: row,
        matching: find.byType(CircularProgressIndicator),
      );
      expect(ring, findsOneWidget);
      expect(tester.getSize(ring), const Size(40, 40));

      completer.complete(
        const Result<String?>.failure(ProfilePhotoUploadException()),
      );
      await tester.pumpAndSettle();

      expect(find.text('사진을 올리지 못했습니다. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
      expect(
        find.descendant(of: _photoRow(), matching: find.text('없음')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.widget<ListTile>(_photoRow()).onTap, isNotNull);
    });

    testWidgets('T-17-PHOTO-07: ja 280 — 값 「アップロードした写真」 2줄 · 삭제 항목 '
        '2줄 · overflow 0', (tester) async {
      tester.view.physicalSize = const Size(280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpAccount(
        tester,
        repository: _FakeProfilePhotoRepository(
          onUpload: () async => const Result.success(_kCustomUrl),
        ),
        user: _customUser,
        locale: const Locale('ja'),
      );
      expect(tester.takeException(), isNull);

      final value = find.descendant(
        of: _photoRow(),
        matching: find.text('アップロードした写真'),
      );
      expect(value, findsOneWidget);
      expect(_lineCountOf(tester, value), 2);

      await tester.tap(_photoRow());
      await tester.pumpAndSettle();
      final removeItem = find.descendant(
        of: find.byType(ProfilePhotoSheet),
        matching: find.text('アップロードした写真を削除'),
      );
      expect(removeItem, findsOneWidget);
      expect(_lineCountOf(tester, removeItem), 2);
      expect(tester.takeException(), isNull);
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

  group('ProfilePhotoSheet 가로 모드 (Phase 3 D-09 · quick 261003-0fp)', () {
    for (final size in _landscapeSizes) {
      for (final locale in _sweepLocales) {
        for (final hasPhoto in const <bool>[true, false]) {
          final itemCount = hasPhoto ? 3 : 2;
          final label =
              '${_formatSize(size)} · ${locale.languageCode} · '
              '항목 $itemCount개';
          testWidgets('L ($label): 시트 넘침 0 · 취소 도달 · 261003-0fp', (
            tester,
          ) async {
            _setLogicalViewport(tester, size);
            await _pumpAccount(
              tester,
              repository: _FakeProfilePhotoRepository(
                onUpload: () async => const Result.success(_kCustomUrl),
              ),
              user: hasPhoto ? _customUser : null,
              locale: locale,
            );
            expect(tester.takeException(), isNull, reason: '$label 계정 화면');

            await _openPhotoSheet(tester);
            final sheet = find.byType(ProfilePhotoSheet);
            expect(sheet, findsOneWidget, reason: '$label 시트 열림');
            expect(
              find.descendant(of: sheet, matching: find.byType(ListTile)),
              findsNWidgets(itemCount),
              reason: '$label 항목 수',
            );
            expect(tester.takeException(), isNull, reason: '$label 시트 넘침');

            final cancel = find.descendant(
              of: sheet,
              matching: find.widgetWithText(
                ListTile,
                lookupAppLocalizations(locale).commonCancel,
              ),
            );
            await tester.ensureVisible(cancel);
            await tester.pumpAndSettle();
            expect(
              cancel.hitTestable(),
              findsOneWidget,
              reason: '$label 「취소」 도달',
            );
            await tester.tap(cancel);
            await tester.pumpAndSettle();
            expect(sheet, findsNothing, reason: '$label 「취소」 로 닫힘');
            expect(tester.takeException(), isNull, reason: '$label 닫은 뒤');
          });
        }
      }
    }

    for (final hasPhoto in const <bool>[true, false]) {
      final itemCount = hasPhoto ? 3 : 2;
      final expected = hasPhoto
          ? _portraitSheetRectsThreeItems
          : _portraitSheetRectsTwoItems;
      testWidgets('P (360x800 · ko · 항목 $itemCount개): 세로 rect 고정 · '
          '261003-0fp', (tester) async {
        _setLogicalViewport(tester, _portraitSize);
        await _pumpAccount(
          tester,
          repository: _FakeProfilePhotoRepository(
            onUpload: () async => const Result.success(_kCustomUrl),
          ),
          user: hasPhoto ? _customUser : null,
        );
        await _openPhotoSheet(tester);
        expect(tester.takeException(), isNull);

        final sheet = find.byType(ProfilePhotoSheet);
        final tiles = find.descendant(
          of: sheet,
          matching: find.byType(ListTile),
        );
        final actual = <Rect>[
          tester.getRect(find.byType(BottomSheet)),
          tester.getRect(
            find.descendant(
              of: sheet,
              matching: find.text(
                lookupAppLocalizations(const Locale('ko')).authAccountPhotoUrl,
              ),
            ),
          ),
          for (var i = 0; i < itemCount; i++) tester.getRect(tiles.at(i)),
        ];
        expect(actual.length, expected.length);
        for (var i = 0; i < expected.length; i++) {
          _expectRectNear(actual[i], expected[i], reason: '항목 $itemCount개 #$i');
        }
      });
    }
  });
}

/// 360x800 · ko · 항목 3개 시트의 수정 전 rect — BottomSheet · 제목 · ListTile
/// 3개 (quick 261003-0fp 가 lib 수정 전 트리에서 실측).
const _portraitSheetRectsThreeItems = <Rect>[
  Rect.fromLTRB(0, 544, 360, 800),
  Rect.fromLTRB(24, 592, 336, 616),
  Rect.fromLTRB(0, 624, 360, 680),
  Rect.fromLTRB(0, 680, 360, 736),
  Rect.fromLTRB(0, 736, 360, 792),
];

/// 360x800 · ko · 항목 2개 시트의 수정 전 rect — BottomSheet · 제목 · ListTile
/// 2개 (quick 261003-0fp 가 lib 수정 전 트리에서 실측).
const _portraitSheetRectsTwoItems = <Rect>[
  Rect.fromLTRB(0, 600, 360, 800),
  Rect.fromLTRB(24, 648, 336, 672),
  Rect.fromLTRB(0, 680, 360, 736),
  Rect.fromLTRB(0, 736, 360, 792),
];

/// [actual] 의 네 변이 [expected] 와 ±0.5 안인지 단언한다.
void _expectRectNear(Rect actual, Rect expected, {required String reason}) {
  expect(actual.left, closeTo(expected.left, 0.5), reason: '$reason left');
  expect(actual.top, closeTo(expected.top, 0.5), reason: '$reason top');
  expect(actual.right, closeTo(expected.right, 0.5), reason: '$reason right');
  expect(
    actual.bottom,
    closeTo(expected.bottom, 0.5),
    reason: '$reason bottom',
  );
}

/// 가로 모드 점검 크기 (logical px).
///
/// - 780x360: SM-S942N 가로 실측 w780dp h360dp.
/// - 560x280: 지원 최소 폭 280dp 의 가로 — 최악.
const _landscapeSizes = <Size>[Size(780, 360), Size(560, 280)];

/// 세로 rect 고정 가드(P) 크기 — 일반 세로 폰.
const _portraitSize = Size(360, 800);

/// 점검 언어 — ko 먼저(R2), en, ja.
const _sweepLocales = <Locale>[Locale('ko'), Locale('en'), Locale('ja')];

/// 테스트 view 를 logical [size] 로 맞춘다 (DPR 1.0 · pump 전에 호출).
///
/// `setSurfaceSize` 는 MediaQuery 를 갱신하지 않으므로 쓰지 않는다
/// (quick 260929-pze 선례).
void _setLogicalViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 계정 화면의 사진 행을 화면에 보이게 한 뒤 탭해 사진 메뉴 시트를 연다.
Future<void> _openPhotoSheet(WidgetTester tester) async {
  await tester.ensureVisible(_photoRow());
  await tester.pumpAndSettle();
  await tester.tap(_photoRow());
  await tester.pumpAndSettle();
}

/// [size] 를 테스트 이름용 `WxH` 문자열로 만든다.
String _formatSize(Size size) => '${size.width.toInt()}x${size.height.toInt()}';
