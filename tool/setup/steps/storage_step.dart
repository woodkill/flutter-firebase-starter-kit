import 'dart:convert';

import '../command_runner.dart';
import '../config_files.dart';
import '../confirm.dart';
import '../rest_client.dart';
import '../step.dart';
import '../wizard.dart';
import 'billing_step.dart';
import 'firestore_step.dart';
import 'user_files_step.dart';

/// 기본 Storage bucket 단계 — 프로젝트의 기본 Cloud Storage bucket 을 Firestore 와
/// 같은 위치에 만든다.
///
/// 검사는 Cloud Storage for Firebase 관리 API 의 기본 bucket GET 이다. 없으면(404)
/// Firestore 위치를 읽어 같은 위치로 만들고, Firestore 가 단일 리전 목록 밖(다중
/// 리전 등)이면 `config/dev.json` 의 `functionsRegion` 을 쓴다. 위치가
/// [alwaysFreeRegions] 밖이면 무료 사용량이 없다는 경고를 확인 표에 보인다.
/// 만들기는 확인 표 뒤에만 REST POST 로 요청한다.
final class StorageStep implements Step {
  /// 기본 Storage bucket 단계를 만든다.
  StorageStep();

  /// 단계 제목.
  static const String stepTitle = '기본 Storage bucket';

  /// 기본 bucket 관리 API 주소의 앞부분 — 뒤에 `<프로젝트 ID>/defaultBucket` 이 붙는다.
  static const String defaultBucketUrlPrefix =
      'https://firebasestorage.googleapis.com/v1alpha/projects/';

  /// 기본 bucket 이 Always Free 사용량을 받는 위치.
  static const List<String> alwaysFreeRegions = <String>[
    'us-central1',
    'us-east1',
    'us-west1',
  ];

  /// 확인 표 제목.
  static const String confirmTitle = '기본 Storage bucket — 확인';

  /// 위치를 바꿀 수 없다는 경고.
  static const String locationImmutableWarning =
      '기본 bucket 위치는 만든 뒤 바꿀 수 없습니다.';

  /// Always Free 밖 위치 경고.
  static const String alwaysFreeWarning =
      '이 위치의 기본 bucket 은 Always Free 사용량이 없습니다 — '
      '저장 · 다운로드 사용량이 처음부터 청구됩니다.';

  /// [projectId] 의 기본 bucket 주소를 만든다.
  static Uri buildBucketUrl(String projectId) =>
      Uri.parse('$defaultBucketUrlPrefix$projectId/defaultBucket');

  /// [projectId] 의 기본 bucket 을 읽는 요청을 만든다.
  static RestRequest buildGetRequest(String projectId) => RestRequest(
    method: 'GET',
    url: buildBucketUrl(projectId),
    quotaProject: projectId,
  );

  /// [projectId] 에 [location] 위치의 기본 bucket 을 만드는 요청을 만든다.
  static RestRequest buildCreateRequest(String projectId, String location) =>
      RestRequest(
        method: 'POST',
        url: buildBucketUrl(projectId),
        quotaProject: projectId,
        body: jsonEncode(<String, String>{'location': location}),
      );

  _StorageMode _mode = _StorageMode.unreadable;
  String _reason = '';
  String _projectId = '';
  String _location = '';
  String _locationNote = '';
  CommandResult? _failedResult;

  @override
  String get id => 'storage';

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['firestore'];

  // 확인 표는 bucket 만들기에서만 보인다 — 실패 전용 모드에는 안내가 붙지 않는다.
  @override
  bool get isCostlyOrIrreversible => _mode == _StorageMode.create;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      return _markFailed(
        _StorageMode.unreadable,
        '${UserFilesStep.jsonUserPath} 에서 프로젝트 ID 를 읽지 못했습니다',
      );
    }
    _projectId = projectId;
    final RestResponse response = await context.rest.send(
      buildGetRequest(projectId),
    );
    if (response.isOk) {
      _mode = _StorageMode.done;
      final Object? decoded = response.decodeJson();
      final Object? location = decoded is Map<String, Object?>
          ? decoded['location']
          : null;
      return Done(location is String ? '있음 — 위치 $location' : '있음');
    }
    if (response.statusCode != 404) {
      return _markFailed(
        _StorageMode.requestFailed,
        '기본 bucket 을 확인하지 못했습니다 — ${describeRestStatus(response)}',
        result: toFailureResult(response),
      );
    }
    return _resolveLocation(context, projectId);
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _StorageMode.create => <String>[
      '($_locationNote)',
      buildCreateRequest(_projectId, _location).displayCurl(),
    ],
    _StorageMode.requestFailed ||
    _StorageMode.locationUnknown => <String>['(응답 원문을 보입니다)'],
    _StorageMode.unreadable || _StorageMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    return switch (_mode) {
      _StorageMode.create => await _applyCreate(context),
      _StorageMode.requestFailed ||
      _StorageMode.locationUnknown => Failed(_reason, result: _failedResult),
      _StorageMode.unreadable => Failed(_reason),
      _StorageMode.done => const Applied(),
    };
  }

  /// 확인 표 뒤에 기본 bucket 을 만든다.
  Future<StepOutcome> _applyCreate(WizardContext context) async {
    if (!confirmSummary(
      context.terminal,
      title: confirmTitle,
      rows: <SummaryRow>[
        SummaryRow('프로젝트 ID', _projectId),
        SummaryRow('위치', _location),
        SummaryRow('bucket 이름', '$_projectId.firebasestorage.app'),
      ],
      warnings: <String>[
        locationImmutableWarning,
        if (!alwaysFreeRegions.contains(_location)) alwaysFreeWarning,
      ],
    )) {
      return const Declined();
    }
    final RestResponse response = await context.rest.send(
      buildCreateRequest(_projectId, _location),
    );
    if (response.isOk) return const Applied();
    return Failed(
      '기본 bucket 을 만들지 못했습니다 — ${describeRestStatus(response)}',
      result: toFailureResult(response),
    );
  }

  /// 기본 bucket 이 없을 때 만들 위치를 정한다.
  Future<CheckResult> _resolveLocation(
    WizardContext context,
    String projectId,
  ) async {
    final FirestoreLookup lookup = await readFirestoreLocation(
      context,
      projectId,
    );
    switch (lookup) {
      case FirestoreFound(:final String locationId)
          when FirestoreStep.singleRegions.containsKey(locationId):
        _location = locationId;
        _locationNote = '위치 $locationId — Firestore 와 같은 위치';
      case FirestoreFound(:final String locationId):
        final String? region = readJsonString(
          context.resolve(UserFilesStep.jsonUserPath),
          FirestoreStep.functionsRegionKey,
        )?.trim();
        if (region == null || region.isEmpty) {
          return _markFailed(
            _StorageMode.locationUnknown,
            'Firestore 위치 $locationId 는 단일 리전이 아니고 '
            '${UserFilesStep.jsonUserPath} 에서 ${FirestoreStep.functionsRegionKey} '
            '를 읽지 못했습니다',
          );
        }
        _location = region;
        _locationNote =
            '위치 $region — Firestore 위치 $locationId 는 단일 리전이 아니라 '
            'Functions 리전을 씁니다';
      case FirestoreMissing():
        return _markFailed(
          _StorageMode.locationUnknown,
          'Firestore 데이터베이스가 없어 위치를 정하지 못했습니다',
        );
      case FirestoreLookupFailed(:final CommandResult result):
        return _markFailed(
          _StorageMode.locationUnknown,
          'Firestore 위치를 읽지 못했습니다 — ${lookup.firstLine}',
          result: result,
        );
    }
    _mode = _StorageMode.create;
    _reason = '$projectId 에 기본 Storage bucket 이 없습니다';
    return Todo(_reason);
  }

  /// [mode] 판정과 사유를 두고 할 일 결과를 만든다.
  CheckResult _markFailed(
    _StorageMode mode,
    String reason, {
    CommandResult? result,
  }) {
    _mode = mode;
    _reason = reason;
    _failedResult = result;
    return Todo(reason);
  }
}

/// 직전 검사의 판정.
enum _StorageMode {
  /// 기본 bucket 이 없다 — 확인 표 뒤에 만든다.
  create,

  /// 기본 bucket 을 확인하지 못했다.
  requestFailed,

  /// 만들 위치를 정하지 못했다.
  locationUnknown,

  /// 프로젝트 ID 를 읽지 못했다.
  unreadable,

  /// 끝남.
  done,
}
