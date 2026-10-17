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

/// 사용자 목록 한 페이지의 주소.
String buildUsersUrl({String? pageToken}) => RunStep.buildBatchGetRequest(
  projectId,
  pageToken: pageToken,
).url.toString();

/// identity_index 한 페이지의 주소.
String buildIndexUrl({String? pageToken}) =>
    buildIdentityIndexRequest(projectId, pageToken: pageToken).url.toString();

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
}
