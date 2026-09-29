// ignore_for_file: subtype_of_sealed_class
//
// 본 테스트는 cloud_firestore 의 sealed class (DocumentReference ·
// DocumentSnapshot) 를 mock 으로 implements 한다 — fake_cloud_firestore 부재로
// mocktail 직접 mock 채택 (auth_repository_current_user_test 와 같은 관례).
// 본 ignore 는 테스트 파일 한정이다.
//
// Phase 16.10 review WR-01 · iteration 2 IN-03 — [fetchProviderIdsFromServer] 계약.
//
//   SP1: 서버 소스(`Source.server`)로 1회 읽고 providerData ∪ linkedProviders 를 돌려준다
//   SP2: 문서 부재 → providerData 만 (서버 확정 빈 연결)
//   SP3: 읽기 실패(FirebaseException) → 흡수 없이 그대로 던진다 (fail-closed)
//   SP4: 로그인 사용자 부재 → 빈 목록 · Firestore 호출 0
//   SP5: 잘못된 entry 는 스트림과 같은 파서가 거른다 · signUpProviderId 무관
//   SP6: (IN-03) native 절반은 reload 뒤 사용자에서 읽는다 — 다른 기기에서 연결한 google.com 포함
//   SP7: (IN-03) reload 실패 → 흡수 없이 그대로 던진다 · Firestore 호출 0
//   SP8: (IN-03) reload 뒤 로그인 사용자 부재 → throw · Firestore 호출 0
//   SP9: (IN-03) reload 뒤 uid 가 다르다 → throw · Firestore 호출 0

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserInfo extends Mock implements fb.UserInfo {}

class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class _MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

const String _uid = 'uid-server-read';

/// [uid] · [providerIds](providerData)를 가진 Firebase 사용자 mock 을 만든다.
_MockFbUser _userWith(List<String> providerIds, {String uid = _uid}) {
  final user = _MockFbUser();
  final infos = <_MockUserInfo>[];
  for (final id in providerIds) {
    final info = _MockUserInfo();
    when(() => info.providerId).thenReturn(id);
    infos.add(info);
  }
  when(() => user.uid).thenReturn(uid);
  when(() => user.providerData).thenReturn(infos);
  return user;
}

/// [providerIds] 를 providerData 로 가진 로그인 사용자를 [auth] 에 싣는다.
///
/// `reload()` 는 성공하고 reload 뒤 `currentUser` 는 같은 사용자다 (IN-03 —
/// 서버와 캐시가 같은 기본 경우).
_MockFbUser _signIn(_MockFirebaseAuth auth, List<String> providerIds) {
  final user = _userWith(providerIds);
  when(user.reload).thenAnswer((_) async {});
  when(() => auth.currentUser).thenReturn(user);
  return user;
}

/// 캐시 사용자 [cached] 가 `reload()` 뒤 [afterReload] 로 바뀌게 [auth] 를
/// stub 한다 (IN-03 — SDK 가 reload 로 `currentUser` 를 갱신하는 모양).
void _signInReloadingTo(
  _MockFirebaseAuth auth,
  _MockFbUser cached,
  fb.User? afterReload,
) {
  fb.User? current = cached;
  when(cached.reload).thenAnswer((_) async {
    current = afterReload;
  });
  when(() => auth.currentUser).thenAnswer((_) => current);
}

void main() {
  late _MockFirebaseAuth auth;
  late _MockFirebaseFirestore firestore;
  late _MockDocumentReference doc;

  setUpAll(() {
    registerFallbackValue(const GetOptions());
  });

  setUp(() {
    auth = _MockFirebaseAuth();
    firestore = _MockFirebaseFirestore();
    final collection = _MockCollectionReference();
    doc = _MockDocumentReference();
    when(() => firestore.collection('users')).thenReturn(collection);
    when(() => collection.doc(_uid)).thenReturn(doc);
  });

  /// `users/{uid}` 서버 읽기가 [data] 를 돌려주게 stub 한다 (null = 문서 부재).
  void stubDoc(Map<String, dynamic>? data) {
    final snap = _MockDocumentSnapshot();
    when(() => snap.exists).thenReturn(data != null);
    when(snap.data).thenReturn(data);
    when(() => doc.get(any())).thenAnswer((_) async => snap);
  }

  test('SP1: 서버 소스로 1회 읽고 providerData ∪ linkedProviders 를 돌려준다', () async {
    _signIn(auth, <String>['google.com']);
    stubDoc(<String, dynamic>{
      'linkedProviders': <Map<String, dynamic>>[
        <String, dynamic>{'providerId': 'kakao'},
        <String, dynamic>{'providerId': 'google.com'},
        <String, dynamic>{'providerId': 'line'},
      ],
    });

    final ids = await fetchProviderIdsFromServer(
      auth: auth,
      firestore: firestore,
    );

    expect(ids, <String>['google.com', 'kakao', 'line']);
    final options =
        verify(() => doc.get(captureAny())).captured.single as GetOptions;
    expect(options.source, Source.server);
  });

  test('SP2: 문서 부재 → providerData 만', () async {
    _signIn(auth, <String>['password']);
    stubDoc(null);

    final ids = await fetchProviderIdsFromServer(
      auth: auth,
      firestore: firestore,
    );

    expect(ids, <String>['password']);
  });

  test('SP3: 읽기 실패는 흡수하지 않고 그대로 던진다', () async {
    _signIn(auth, <String>[]);
    when(() => doc.get(any())).thenThrow(
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
    );

    await expectLater(
      fetchProviderIdsFromServer(auth: auth, firestore: firestore),
      throwsA(
        isA<FirebaseException>().having((e) => e.code, 'code', 'unavailable'),
      ),
    );
  });

  test('SP4: 로그인 사용자 부재 → 빈 목록 · Firestore 호출 0', () async {
    when(() => auth.currentUser).thenReturn(null);

    final ids = await fetchProviderIdsFromServer(
      auth: auth,
      firestore: firestore,
    );

    expect(ids, isEmpty);
    verifyNever(() => firestore.collection(any()));
  });

  test('SP5: 잘못된 entry 는 스트림과 같은 파서가 거른다', () async {
    _signIn(auth, <String>[]);
    stubDoc(<String, dynamic>{
      'signUpProviderId': 'kakao',
      'linkedProviders': <Object?>[
        <String, dynamic>{'providerId': 'kakao'},
        'not-a-map',
        <String, dynamic>{'other': 'x'},
      ],
    });

    final ids = await fetchProviderIdsFromServer(
      auth: auth,
      firestore: firestore,
    );

    expect(ids, <String>['kakao']);
  });

  test(
    'SP6 (IN-03): native 절반은 reload 뒤 사용자에서 읽는다 — 다른 기기에서 연결한 google.com 포함',
    () async {
      // 이 기기의 SDK 캐시는 다른 기기에서 연결한 google.com 을 모른다.
      final cached = _userWith(<String>['password']);
      _signInReloadingTo(
        auth,
        cached,
        _userWith(<String>['password', 'google.com']),
      );
      stubDoc(<String, dynamic>{
        'linkedProviders': <Map<String, dynamic>>[
          <String, dynamic>{'providerId': 'kakao'},
        ],
      });

      final ids = await fetchProviderIdsFromServer(
        auth: auth,
        firestore: firestore,
      );

      expect(ids, <String>['password', 'google.com', 'kakao']);
      verify(cached.reload).called(1);
    },
  );

  test('SP7 (IN-03): reload 실패는 흡수하지 않고 그대로 던진다 · Firestore 호출 0', () async {
    final cached = _userWith(<String>['google.com']);
    when(() => auth.currentUser).thenReturn(cached);
    when(
      cached.reload,
    ).thenThrow(fb.FirebaseAuthException(code: 'network-request-failed'));

    await expectLater(
      fetchProviderIdsFromServer(auth: auth, firestore: firestore),
      throwsA(
        isA<fb.FirebaseAuthException>().having(
          (e) => e.code,
          'code',
          'network-request-failed',
        ),
      ),
    );
    verifyNever(() => firestore.collection(any()));
  });

  test('SP8 (IN-03): reload 뒤 로그인 사용자 부재 → throw · Firestore 호출 0', () async {
    _signInReloadingTo(auth, _userWith(<String>['google.com']), null);

    await expectLater(
      fetchProviderIdsFromServer(auth: auth, firestore: firestore),
      throwsA(isA<StateError>()),
    );
    verifyNever(() => firestore.collection(any()));
  });

  test('SP9 (IN-03): reload 뒤 uid 가 다르다 → throw · Firestore 호출 0', () async {
    _signInReloadingTo(
      auth,
      _userWith(<String>['google.com']),
      _userWith(<String>['google.com'], uid: 'uid-other'),
    );

    await expectLater(
      fetchProviderIdsFromServer(auth: auth, firestore: firestore),
      throwsA(isA<StateError>()),
    );
    verifyNever(() => firestore.collection(any()));
  });
}
