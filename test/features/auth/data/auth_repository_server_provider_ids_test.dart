// ignore_for_file: subtype_of_sealed_class
//
// 본 테스트는 cloud_firestore 의 sealed class (DocumentReference ·
// DocumentSnapshot) 를 mock 으로 implements 한다 — fake_cloud_firestore 부재로
// mocktail 직접 mock 채택 (auth_repository_current_user_test 와 같은 관례).
// 본 ignore 는 테스트 파일 한정이다.
//
// Phase 16.10 review WR-01 — [fetchProviderIdsFromServer] 계약.
//
//   SP1: 서버 소스(`Source.server`)로 1회 읽고 providerData ∪ linkedProviders 를 돌려준다
//   SP2: 문서 부재 → providerData 만 (서버 확정 빈 연결)
//   SP3: 읽기 실패(FirebaseException) → 흡수 없이 그대로 던진다 (fail-closed)
//   SP4: 로그인 사용자 부재 → 빈 목록 · Firestore 호출 0
//   SP5: 잘못된 entry 는 스트림과 같은 파서가 거른다 · signUpProviderId 무관

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

/// [providerIds] 를 providerData 로 가진 로그인 사용자를 [auth] 에 싣는다.
void _signIn(_MockFirebaseAuth auth, List<String> providerIds) {
  final user = _MockFbUser();
  final infos = <_MockUserInfo>[];
  for (final id in providerIds) {
    final info = _MockUserInfo();
    when(() => info.providerId).thenReturn(id);
    infos.add(info);
  }
  when(() => user.uid).thenReturn(_uid);
  when(() => user.providerData).thenReturn(infos);
  when(() => auth.currentUser).thenReturn(user);
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
}
