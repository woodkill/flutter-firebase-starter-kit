import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/providers/sign_in_counts.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/steps/run_step.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID(가짜).
const String projectId = 'demo-project';

/// 응답 fixture 에 넣는 가짜 사용자 값 — 화면 · 기록 · 사유에 나오면 안 된다.
const List<String> fakePersonalValues = <String>[
  'user-1@example.invalid',
  'user-2@example.invalid',
  'uid-fake-1',
  'uid-fake-2',
  'kakao:fake-1',
  'naver:fake-2',
  'naver:fake-3',
];

/// 가짜 사용자 하나 — [providerIds] 의 로그인 수단으로 가입했다.
Map<String, Object?> buildUser(
  String uid,
  String email,
  List<String> providerIds,
) => <String, Object?>{
  'localId': uid,
  'email': email,
  'emailVerified': true,
  'providerUserInfo': <Object?>[
    for (final String id in providerIds)
      <String, Object?>{'providerId': id, 'email': email, 'rawId': uid},
  ],
};

/// 가짜 identity_index 문서 하나 — 마스크 덕에 provider 필드만 실린다.
Map<String, Object?> buildIndexDocument(String docId, String provider) =>
    <String, Object?>{
      'name':
          'projects/$projectId/databases/(default)/documents/identity_index/'
          '$docId',
      'fields': <String, Object?>{
        'provider': <String, Object?>{'stringValue': provider},
      },
    };

/// 로그인 대조 fixture 의 기준 시각(가짜) — 문서 `createTime` 이 이 값이다.
final DateTime indexCreatedAt = DateTime.utc(2031, 5, 6, 7, 8, 9);

/// [time] 을 Auth 사용자 기록의 epoch ms 문자열로 바꾼다.
String toEpochMs(DateTime time) => time.millisecondsSinceEpoch.toString();

/// 문서 주인 [uid] 의 Auth 사용자 기록 — 마지막 로그인은 기준 시각 + [loginOffset].
///
/// [isCustomAuth] 가 false 면 `customAuth` 를 싣지 않는다(익명 사용자 모양).
Map<String, Object?> buildOwner(
  String uid, {
  Duration loginOffset = const Duration(seconds: 2),
  bool isCustomAuth = true,
}) => <String, Object?>{
  'localId': uid,
  if (isCustomAuth) 'customAuth': true,
  'lastLoginAt': toEpochMs(indexCreatedAt.add(loginOffset)),
  'createdAt': toEpochMs(indexCreatedAt.subtract(const Duration(minutes: 5))),
};

/// 로그인 대조 모드의 identity_index 문서 하나 — 주인 uid · `createTime` 을 싣는다.
///
/// [ownerUid] · [createTime] 이 null 이면 그 값을 싣지 않는다.
Map<String, Object?> buildOwnedDocument(
  String docId,
  String provider, {
  required String? ownerUid,
  String? createTime,
}) => <String, Object?>{
  'name':
      'projects/$projectId/databases/(default)/documents/identity_index/'
      '$docId',
  'fields': <String, Object?>{
    'provider': <String, Object?>{'stringValue': provider},
    if (ownerUid != null)
      'firebaseUid': <String, Object?>{'stringValue': ownerUid},
  },
  'createTime': ?createTime,
  'updateTime': ?createTime,
};

/// [body] 를 JSON 으로 담은 200 응답.
RestResponse buildOkResponse(Map<String, Object?> body) =>
    RestResponse(200, jsonEncode(body));

/// 사용자 목록 한 페이지의 주소.
String buildUsersUrl({String? pageToken}) => RunStep.buildBatchGetRequest(
  projectId,
  pageToken: pageToken,
).url.toString();

/// identity_index 한 페이지의 주소.
String buildIndexUrl({String? pageToken}) =>
    buildIdentityIndexRequest(projectId, pageToken: pageToken).url.toString();

/// 로그인 대조 모드 identity_index 한 페이지의 주소.
String buildSignedInIndexUrl({String? pageToken}) => buildIdentityIndexRequest(
  projectId,
  pageToken: pageToken,
  basis: SignInBasis.signedIn,
).url.toString();

/// 집계 한 번에 쓰는 가짜 REST · 화면 · 기록 묶음.
final class _Harness {
  _Harness(this.root) {
    context = buildTestContext(
      projectRoot: root,
      terminal: screen,
      rest: rest,
      log: log,
    );
  }

  final String root;
  final FakeRestClient rest = FakeRestClient();
  final ScriptedTerminal screen = ScriptedTerminal(const <String?>[]);
  final MemoryLogSink log = MemoryLogSink(Redactor());
  late final WizardContext context;

  /// 사용자 목록 요청 수.
  int countUserRequests() => rest.requests
      .where(
        (RestRequest request) =>
            request.url.toString().startsWith(RunStep.usersUrlPrefix),
      )
      .length;

  /// identity_index 요청 수.
  int countIndexRequests() => rest.requests
      .where(
        (RestRequest request) =>
            request.url.toString().startsWith(identityIndexUrlPrefix),
      )
      .length;
}

/// [text] 에 가짜 사용자 값이 몇 번 나오는지 센다.
int countPersonalValues(String text) => fakePersonalValues
    .map((String value) => value.allMatches(text).length)
    .fold(0, (int sum, int count) => sum + count);

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sign_in_counts_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('T-20-COUNT-01: 사용자 목록을 끝 페이지까지 읽어 Google · Apple · Facebook 가입자를 센다 '
      '· 민감 응답', () async {
    final h = _Harness(tempDir.path);
    h.rest
      ..on(
        'GET',
        buildUsersUrl(),
        RestResponse(
          200,
          jsonEncode(<String, Object?>{
            'users': <Object?>[
              buildUser('uid-fake-1', 'user-1@example.invalid', <String>[
                'google.com',
              ]),
              buildUser('uid-fake-2', 'user-2@example.invalid', <String>[
                'password',
              ]),
            ],
            'nextPageToken': 'page-2',
          }),
        ),
      )
      ..on(
        'GET',
        buildUsersUrl(pageToken: 'page-2'),
        RestResponse(
          200,
          jsonEncode(<String, Object?>{
            'users': <Object?>[
              buildUser('uid-fake-3', 'user-3@example.invalid', <String>[
                'google.com',
                'password',
              ]),
              buildUser('uid-fake-4', 'user-4@example.invalid', <String>[
                'apple.com',
              ]),
            ],
          }),
        ),
      );

    final SignInCount counted = await countSignIns(
      h.context,
      projectId,
      const <String>{'google', 'apple', 'facebook'},
    );

    expect(counted, isA<SignInCountOk>());
    expect((counted as SignInCountOk).countsByToken, <String, int>{
      'google': 2,
      'apple': 1,
      'facebook': 0,
    });
    expect(h.rest.requests, hasLength(2));
    expect(
      h.rest.requests.every((RestRequest r) => r.isResponseSensitive),
      isTrue,
    );
    expect(h.countIndexRequests(), 0);
  });

  test(
    'T-20-COUNT-02: identity_index 를 끝 페이지까지 provider 필드만 읽어 Kakao · Naver · '
    'LINE 가입자를 센다',
    () async {
      final h = _Harness(tempDir.path);
      h.rest
        ..on(
          'GET',
          buildIndexUrl(),
          RestResponse(
            200,
            jsonEncode(<String, Object?>{
              'documents': <Object?>[
                buildIndexDocument('kakao:fake-1', 'kakao'),
                buildIndexDocument('naver:fake-2', 'naver'),
              ],
              'nextPageToken': 'next/page=',
            }),
          ),
        )
        ..on(
          'GET',
          buildIndexUrl(pageToken: 'next/page='),
          RestResponse(
            200,
            jsonEncode(<String, Object?>{
              'documents': <Object?>[
                buildIndexDocument('naver:fake-3', 'naver'),
              ],
            }),
          ),
        );

      final SignInCount counted = await countSignIns(
        h.context,
        projectId,
        const <String>{'kakao', 'naver', 'line'},
      );

      expect(counted, isA<SignInCountOk>());
      expect((counted as SignInCountOk).countsByToken, <String, int>{
        'kakao': 1,
        'naver': 2,
        'line': 0,
      });
      expect(h.rest.requests, hasLength(2));
      expect(
        buildIndexUrl(),
        'https://firestore.googleapis.com/v1/projects/demo-project/databases/'
        '(default)/documents/identity_index?pageSize=300&'
        'mask.fieldPaths=provider',
      );
      expect(
        buildIndexUrl(pageToken: 'next/page='),
        endsWith('mask.fieldPaths=provider&pageToken=next%2Fpage%3D'),
      );
      for (final RestRequest request in h.rest.requests) {
        expect(request.url.toString(), contains('mask.fieldPaths=provider'));
        expect(request.isResponseSensitive, isTrue);
        expect(request.method, 'GET');
      }
      expect(h.countUserRequests(), 0);
    },
  );

  group('T-20-COUNT-03: 필요한 쪽만 요청한다', () {
    test('Kakao 만 세면 사용자 목록 요청이 없다', () async {
      final h = _Harness(tempDir.path);
      h.rest.on('GET', buildIndexUrl(), const RestResponse(200, '{}'));

      final SignInCount counted = await countSignIns(
        h.context,
        projectId,
        const <String>{'kakao'},
      );

      expect((counted as SignInCountOk).countsByToken, <String, int>{
        'kakao': 0,
      });
      expect(h.countUserRequests(), 0);
      expect(h.countIndexRequests(), 1);
    });

    test('Google 만 세면 Firestore 요청이 없다', () async {
      final h = _Harness(tempDir.path);
      h.rest.on('GET', buildUsersUrl(), const RestResponse(200, '{}'));

      final SignInCount counted = await countSignIns(
        h.context,
        projectId,
        const <String>{'google'},
      );

      expect((counted as SignInCountOk).countsByToken, <String, int>{
        'google': 0,
      });
      expect(h.countUserRequests(), 1);
      expect(h.countIndexRequests(), 0);
    });
  });

  group('T-20-COUNT-04: 읽지 못하면 실패 · 가입자 값은 어디에도 남지 않는다', () {
    /// 실패 결과의 사유 · 원문과 화면 · 기록에 가짜 사용자 값이 0회인지 본다.
    void expectNoPersonalValues(_Harness h, SignInCountFailed failed) {
      final CommandResult? result = failed.result;
      expect(countPersonalValues(failed.reason), 0);
      expect(countPersonalValues(result?.stdout ?? ''), 0);
      expect(countPersonalValues(result?.stderr ?? ''), 0);
      expect(countPersonalValues(h.screen.output.toString()), 0);
      expect(countPersonalValues(h.log.text), 0);
    }

    test('둘째 페이지가 403 이면 사유에 상태를 적는다', () async {
      final h = _Harness(tempDir.path);
      h.rest
        ..on(
          'GET',
          buildUsersUrl(),
          RestResponse(
            200,
            jsonEncode(<String, Object?>{
              'users': <Object?>[
                buildUser('uid-fake-1', 'user-1@example.invalid', <String>[
                  'google.com',
                ]),
              ],
              'nextPageToken': 'page-2',
            }),
          ),
        )
        ..on(
          'GET',
          buildUsersUrl(pageToken: 'page-2'),
          const RestResponse(
            403,
            '{"error":{"code":403,"status":"PERMISSION_DENIED"}}',
          ),
        );

      final SignInCount counted = await countSignIns(
        h.context,
        projectId,
        const <String>{'google'},
      );

      expect(counted, isA<SignInCountFailed>());
      final failed = counted as SignInCountFailed;
      expect(failed.reason, contains('HTTP 403'));
      expect(failed.result?.stderr, contains('PERMISSION_DENIED'));
      expectNoPersonalValues(h, failed);
    });

    test('요청하지 못하면(상태 0) 사유에 그 사실을 적는다', () async {
      final h = _Harness(tempDir.path);
      h.rest
        ..on(
          'GET',
          buildIndexUrl(),
          RestResponse(
            200,
            jsonEncode(<String, Object?>{
              'documents': <Object?>[
                buildIndexDocument('kakao:fake-1', 'kakao'),
              ],
              'nextPageToken': 'p2',
            }),
          ),
        )
        ..on('GET', buildIndexUrl(pageToken: 'p2'), const RestResponse(0, ''));

      final SignInCount counted = await countSignIns(
        h.context,
        projectId,
        const <String>{'kakao'},
      );

      expect(counted, isA<SignInCountFailed>());
      final failed = counted as SignInCountFailed;
      expect(failed.reason, contains('요청하지 못했습니다'));
      expect(failed.result, isNull);
      expectNoPersonalValues(h, failed);
    });

    test('JSON 이 아닌 응답은 본문을 싣지 않고 해석 실패로 둔다', () async {
      final h = _Harness(tempDir.path);
      h.rest.on(
        'GET',
        buildUsersUrl(),
        const RestResponse(
          200,
          'user-1@example.invalid uid-fake-1 kakao:fake-1',
        ),
      );

      final SignInCount counted = await countSignIns(
        h.context,
        projectId,
        const <String>{'apple'},
      );

      expect(counted, isA<SignInCountFailed>());
      final failed = counted as SignInCountFailed;
      expect(failed.reason, contains('해석하지 못했습니다'));
      expect(failed.result, isNull);
      expectNoPersonalValues(h, failed);
    });
  });

  group('T-20-COUNT-05: hasSignedInAfter 판정 표', () {
    final String createTime = indexCreatedAt.toIso8601String();
    final String loginLater = toEpochMs(
      indexCreatedAt.add(const Duration(seconds: 2)),
    );

    test('T-20-COUNT-05: Custom Token 로그인이 아니면 거짓', () {
      expect(
        hasSignedInAfter(
          isCustomAuth: false,
          lastLoginAt: loginLater,
          createTime: createTime,
        ),
        isFalse,
      );
    });

    test('T-20-COUNT-05: 로그인 시각이 없거나 · 비었거나 · 숫자가 아니면 거짓', () {
      for (final lastLoginAt in <String?>[null, '', 'not-a-number']) {
        expect(
          hasSignedInAfter(
            isCustomAuth: true,
            lastLoginAt: lastLoginAt,
            createTime: createTime,
          ),
          isFalse,
          reason: '$lastLoginAt',
        );
      }
    });

    test('T-20-COUNT-05: 문서 시각이 없거나 시각이 아니면 거짓', () {
      for (final value in <String?>[null, '', 'not-a-time']) {
        expect(
          hasSignedInAfter(
            isCustomAuth: true,
            lastLoginAt: loginLater,
            createTime: value,
          ),
          isFalse,
          reason: '$value',
        );
      }
    });

    test('T-20-COUNT-05: 같은 ms 는 참 · 1ms 앞은 거짓 · 2초 뒤는 참', () {
      bool judge(DateTime login) => hasSignedInAfter(
        isCustomAuth: true,
        lastLoginAt: toEpochMs(login),
        createTime: createTime,
      );

      expect(judge(indexCreatedAt), isTrue);
      expect(
        judge(indexCreatedAt.subtract(const Duration(milliseconds: 1))),
        isFalse,
      );
      expect(judge(indexCreatedAt.add(const Duration(seconds: 2))), isTrue);
    });

    test('T-20-COUNT-05: 9자리 소수 초 문서 시각을 읽는다', () {
      // Firestore 는 나노초까지 적는다 — 앞 19자(초까지) 뒤에 소수 9자리를 붙인다.
      final nanoTime =
          '${indexCreatedAt.toIso8601String().substring(0, 19)}.123456789Z';
      final DateTime atMillis = indexCreatedAt.add(
        const Duration(milliseconds: 123),
      );

      expect(DateTime.tryParse(nanoTime), isNotNull);
      expect(
        hasSignedInAfter(
          isCustomAuth: true,
          lastLoginAt: toEpochMs(atMillis),
          createTime: nanoTime,
        ),
        isTrue,
      );
      expect(
        hasSignedInAfter(
          isCustomAuth: true,
          lastLoginAt: toEpochMs(
            atMillis.subtract(const Duration(milliseconds: 1)),
          ),
          createTime: nanoTime,
        ),
        isFalse,
      );
    });
  });

  test('T-20-COUNT-06: 로그인 대조 모드 — 두 페이지씩 읽어 로그인 기록 있는 문서만 '
      '센다 · 주인 없음 · firebaseUid 없음 · createTime 없음은 세지 않는다', () async {
    final h = _Harness(tempDir.path);
    final String createTime = indexCreatedAt.toIso8601String();
    h.rest
      ..on(
        'GET',
        buildUsersUrl(),
        buildOkResponse(<String, Object?>{
          'users': <Object?>[
            buildOwner('owner-kakao-1'),
            buildOwner('owner-naver-1'),
          ],
          'nextPageToken': 'users-2',
        }),
      )
      ..on(
        'GET',
        buildUsersUrl(pageToken: 'users-2'),
        buildOkResponse(<String, Object?>{
          'users': <Object?>[
            buildOwner('owner-kakao-2'),
            // 문서보다 먼저 로그인 — 그 뒤 로그인 기록 없음.
            buildOwner(
              'owner-naver-2',
              loginOffset: const Duration(seconds: -60),
            ),
            // 익명 사용자 모양 — Custom Token 로그인 아님.
            buildOwner('owner-line-1', isCustomAuth: false),
          ],
        }),
      )
      ..on(
        'GET',
        buildSignedInIndexUrl(),
        buildOkResponse(<String, Object?>{
          'documents': <Object?>[
            buildOwnedDocument(
              'kakao:doc-1',
              'kakao',
              ownerUid: 'owner-kakao-1',
              createTime: createTime,
            ),
            buildOwnedDocument(
              'naver:doc-1',
              'naver',
              ownerUid: 'owner-naver-1',
              createTime: createTime,
            ),
            // 주인이 사용자 목록에 없다.
            buildOwnedDocument(
              'kakao:doc-2',
              'kakao',
              ownerUid: 'owner-kakao-missing',
              createTime: createTime,
            ),
          ],
          'nextPageToken': 'index-2',
        }),
      )
      ..on(
        'GET',
        buildSignedInIndexUrl(pageToken: 'index-2'),
        buildOkResponse(<String, Object?>{
          'documents': <Object?>[
            buildOwnedDocument(
              'kakao:doc-3',
              'kakao',
              ownerUid: 'owner-kakao-2',
              createTime: createTime,
            ),
            // firebaseUid 필드가 없다.
            buildOwnedDocument(
              'kakao:doc-4',
              'kakao',
              ownerUid: null,
              createTime: createTime,
            ),
            buildOwnedDocument(
              'naver:doc-2',
              'naver',
              ownerUid: 'owner-naver-2',
              createTime: createTime,
            ),
            buildOwnedDocument(
              'line:doc-1',
              'line',
              ownerUid: 'owner-line-1',
              createTime: createTime,
            ),
            // createTime 이 없다.
            buildOwnedDocument(
              'naver:doc-3',
              'naver',
              ownerUid: 'owner-naver-1',
            ),
          ],
        }),
      );

    final SignInCount counted = await countSignIns(
      h.context,
      projectId,
      const <String>{'kakao', 'naver', 'line'},
      basis: SignInBasis.signedIn,
    );

    expect(counted, isA<SignInCountOk>());
    expect((counted as SignInCountOk).countsByToken, <String, int>{
      'kakao': 2,
      'naver': 1,
      'line': 0,
    });
    expect(h.countUserRequests(), 2);
    expect(h.countIndexRequests(), 2);
    expect(
      h.rest.requests.every((RestRequest r) => r.isResponseSensitive),
      isTrue,
    );
  });

  group('T-20-COUNT-07: 로그인 대조 모드는 사용자 목록을 한 번만 읽는다', () {
    test('T-20-COUNT-07: Google + Kakao — 사용자 목록 페이지마다 1회 · '
        'identity_index 는 로그인 대조 주소만', () async {
      final h = _Harness(tempDir.path);
      h.rest
        ..on(
          'GET',
          buildUsersUrl(),
          buildOkResponse(<String, Object?>{
            'users': <Object?>[
              buildUser('uid-fake-1', 'user-1@example.invalid', <String>[
                'google.com',
              ]),
            ],
            'nextPageToken': 'users-2',
          }),
        )
        ..on(
          'GET',
          buildUsersUrl(pageToken: 'users-2'),
          buildOkResponse(<String, Object?>{
            'users': <Object?>[buildOwner('owner-kakao-1')],
          }),
        )
        ..on(
          'GET',
          buildSignedInIndexUrl(),
          buildOkResponse(<String, Object?>{
            'documents': <Object?>[
              buildOwnedDocument(
                'kakao:doc-1',
                'kakao',
                ownerUid: 'owner-kakao-1',
                createTime: indexCreatedAt.toIso8601String(),
              ),
            ],
          }),
        );

      final SignInCount counted = await countSignIns(
        h.context,
        projectId,
        const <String>{'google', 'kakao'},
        basis: SignInBasis.signedIn,
      );

      expect((counted as SignInCountOk).countsByToken, <String, int>{
        'google': 1,
        'kakao': 1,
      });
      expect(h.rest.countRequests('GET', buildUsersUrl()), 1);
      expect(
        h.rest.countRequests('GET', buildUsersUrl(pageToken: 'users-2')),
        1,
      );
      expect(h.countUserRequests(), 2);
      expect(h.rest.countRequests('GET', buildSignedInIndexUrl()), 1);
      expect(h.rest.countRequests('GET', buildIndexUrl()), 0);
      expect(h.countIndexRequests(), 1);
    });

    test('T-20-COUNT-07: Kakao 만 켜도 사용자 목록을 1회 읽는다', () async {
      final h = _Harness(tempDir.path);
      h.rest
        ..on('GET', buildUsersUrl(), const RestResponse(200, '{}'))
        ..on('GET', buildSignedInIndexUrl(), const RestResponse(200, '{}'));

      final SignInCount counted = await countSignIns(
        h.context,
        projectId,
        const <String>{'kakao'},
        basis: SignInBasis.signedIn,
      );

      expect((counted as SignInCountOk).countsByToken, <String, int>{
        'kakao': 0,
      });
      expect(h.countUserRequests(), 1);
      expect(h.rest.countRequests('GET', buildIndexUrl()), 0);
      expect(h.countIndexRequests(), 1);
    });
  });

  test('T-20-COUNT-08: 기본값(가입 흔적)은 그대로 — 사용자 목록 0 · 문서 존재로 '
      '1명 · 주소가 provider 마스크 하나', () async {
    final h = _Harness(tempDir.path);
    h.rest.on(
      'GET',
      buildIndexUrl(),
      buildOkResponse(<String, Object?>{
        'documents': <Object?>[
          // 주인의 로그인 기록이 없어도 가입 흔적으로는 센다.
          buildOwnedDocument(
            'kakao:doc-1',
            'kakao',
            ownerUid: 'owner-kakao-missing',
          ),
        ],
      }),
    );

    final SignInCount counted = await countSignIns(
      h.context,
      projectId,
      const <String>{'kakao'},
    );

    expect((counted as SignInCountOk).countsByToken, <String, int>{'kakao': 1});
    expect(h.countUserRequests(), 0);
    expect(h.rest.requests, hasLength(1));
    expect(
      h.rest.requests.single.url.toString(),
      'https://firestore.googleapis.com/v1/projects/demo-project/databases/'
      '(default)/documents/identity_index?pageSize=300&'
      'mask.fieldPaths=provider',
    );
    expect(buildIndexUrl(), isNot(buildSignedInIndexUrl()));
  });
}
