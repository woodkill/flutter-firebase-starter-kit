import 'dart:io';

import '../command_runner.dart';
import '../rest_client.dart';
import '../step.dart';
import '../wizard.dart';
import 'billing_step.dart';
import 'storage_step.dart';
import 'user_files_step.dart';

/// Firestore · Storage rules 단계 — 저장소의 rules 파일을 프로젝트에 배포한다.
///
/// 검사는 Firebase Rules API 로 Firestore 릴리스([firestoreRelease])와 기본 bucket
/// 의 Storage 릴리스(`firebase.storage/<bucket>`)가 가리키는 ruleset 원문을 읽어
/// 저장소 [firestoreRulesPath] · [storageRulesPath] 와 비교한다(양쪽 끝 공백 ·
/// 개행만 정리). 둘 다 같으면 끝났고, 아니면 Firebase CLI 로 rules 와 색인을 함께
/// 배포한다. 색인은 같은 명령으로 배포되고 따로 검사하지 않는다.
final class RulesStep implements Step {
  /// rules 단계를 만든다.
  RulesStep();

  /// 단계 제목.
  static const String stepTitle = 'Firestore · Storage rules';

  /// Firebase Rules API 주소의 앞부분 — 뒤에 자원 이름이 붙는다.
  static const String rulesApiPrefix =
      'https://firebaserules.googleapis.com/v1/';

  /// 기본 Firestore 데이터베이스의 릴리스 이름.
  static const String firestoreRelease = 'cloud.firestore';

  /// Storage 릴리스 이름의 앞부분 — 뒤에 `/<bucket 이름>` 이 붙는다.
  static const String storageReleasePrefix = 'firebase.storage';

  /// 기본 bucket 이름을 읽지 못했을 때 쓰는 이름의 뒷부분(`<프로젝트 ID>` 뒤).
  static const String defaultBucketSuffix = '.firebasestorage.app';

  /// 저장소의 Firestore rules 파일.
  static const String firestoreRulesPath = 'firestore.rules';

  /// 저장소의 Storage rules 파일.
  static const String storageRulesPath = 'storage.rules';

  /// 배포 대상 — rules 두 개와 Firestore 색인.
  static const String deployTargets =
      'firestore:rules,firestore:indexes,storage';

  /// [projectId] 의 [releaseName] 릴리스를 읽는 요청을 만든다.
  static RestRequest buildReleaseRequest(
    String projectId,
    String releaseName,
  ) => RestRequest(
    method: 'GET',
    url: Uri.parse(
      '${rulesApiPrefix}projects/$projectId/releases/$releaseName',
    ),
    quotaProject: projectId,
  );

  /// [rulesetName](`projects/<p>/rulesets/<id>`) ruleset 을 읽는 요청을 만든다.
  static RestRequest buildRulesetRequest(
    String projectId,
    String rulesetName,
  ) => RestRequest(
    method: 'GET',
    url: Uri.parse('$rulesApiPrefix$rulesetName'),
    quotaProject: projectId,
  );

  /// [projectId] 에 rules · 색인을 배포하는 명령을 만든다.
  static Command buildDeployCommand(
    String projectId, {
    String? workingDirectory,
  }) => Command('firebase', <String>[
    'deploy',
    '--only',
    deployTargets,
    '--project',
    projectId,
    '--non-interactive',
  ], workingDirectory: workingDirectory);

  _RulesMode _mode = _RulesMode.unreadable;
  String _reason = '';
  String _projectId = '';
  CommandResult? _failedResult;

  @override
  String get id => 'rules';

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['firestore', 'storage'];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      return _mark(
        _RulesMode.unreadable,
        '${UserFilesStep.jsonUserPath} 에서 프로젝트 ID 를 읽지 못했습니다',
      );
    }
    _projectId = projectId;
    final String? firestoreLocal = _readLocal(context, firestoreRulesPath);
    final String? storageLocal = _readLocal(context, storageRulesPath);
    if (firestoreLocal == null || storageLocal == null) {
      return _mark(
        _RulesMode.unreadable,
        '$firestoreRulesPath · $storageRulesPath 를 읽지 못했습니다',
      );
    }

    final String bucket = await _readBucketName(context, projectId);
    final comparisons = <_Comparison>[
      await _compare(
        context,
        projectId,
        'Firestore',
        firestoreRelease,
        firestoreLocal,
      ),
      await _compare(
        context,
        projectId,
        'Storage',
        '$storageReleasePrefix/$bucket',
        storageLocal,
      ),
    ];
    final failed = <_Comparison>[
      for (final _Comparison comparison in comparisons)
        if (comparison.result != null) comparison,
    ];
    if (failed.isNotEmpty) {
      return _mark(
        _RulesMode.requestFailed,
        failed.map((_Comparison c) => c.problem).join(' · '),
        result: failed.first.result,
      );
    }
    final problems = <String>[
      for (final _Comparison comparison in comparisons)
        if (comparison.problem.isNotEmpty) comparison.problem,
    ];
    if (problems.isNotEmpty) {
      return _mark(_RulesMode.deploy, problems.join(' · '));
    }
    _mode = _RulesMode.done;
    return const Done('배포된 Firestore · Storage rules 가 저장소 파일과 같음');
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _RulesMode.deploy => <String>[
      '($firestoreRulesPath · firestore.indexes.json · $storageRulesPath 를 '
          '배포합니다 — 색인도 같은 명령으로 함께 배포됩니다)',
      buildDeployCommand(_projectId).render(),
    ],
    _RulesMode.requestFailed => <String>['(응답 원문을 보입니다)'],
    _RulesMode.unreadable || _RulesMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    switch (_mode) {
      case _RulesMode.deploy:
        final CommandResult result = await context.runner.stream(
          buildDeployCommand(_projectId, workingDirectory: context.projectRoot),
        );
        if (result.isSuccess) return const Applied();
        return Failed('rules 를 배포하지 못했습니다', result: result);
      case _RulesMode.requestFailed:
        return Failed(_reason, result: _failedResult);
      case _RulesMode.unreadable:
        return Failed(_reason);
      case _RulesMode.done:
        return const Applied();
    }
  }

  /// 기본 bucket 이름을 읽는다 — 읽지 못하면 `<프로젝트 ID>.firebasestorage.app`.
  ///
  /// 기본 bucket 응답의 `bucket.name`(`projects/<p>/buckets/<이름>`) 마지막 조각을
  /// 쓴다. Firebase CLI 가 Storage rules 를 배포할 bucket 을 고르는 방법과 같다.
  static Future<String> _readBucketName(
    WizardContext context,
    String projectId,
  ) async {
    final RestResponse response = await context.rest.send(
      StorageStep.buildGetRequest(projectId),
    );
    final fallback = '$projectId$defaultBucketSuffix';
    if (!response.isOk) return fallback;
    final Object? decoded = response.decodeJson();
    if (decoded is! Map<String, Object?>) return fallback;
    final Object? bucket = decoded['bucket'];
    if (bucket is! Map<String, Object?>) return fallback;
    final Object? name = bucket['name'];
    if (name is! String || name.trim().isEmpty) return fallback;
    final String last = name.split('/').last.trim();
    return last.isEmpty ? fallback : last;
  }

  /// [releaseName] 릴리스의 ruleset 원문을 [local] 과 비교한다.
  static Future<_Comparison> _compare(
    WizardContext context,
    String projectId,
    String label,
    String releaseName,
    String local,
  ) async {
    final RestResponse release = await context.rest.send(
      buildReleaseRequest(projectId, releaseName),
    );
    if (release.statusCode == 404) {
      return _Comparison('$label rules 가 배포되지 않았습니다');
    }
    if (!release.isOk) {
      return _Comparison.failed(
        '$label rules 릴리스를 읽지 못했습니다 — ${describeRestStatus(release)}',
        release,
      );
    }
    final Object? decoded = release.decodeJson();
    final Object? rulesetName = decoded is Map<String, Object?>
        ? decoded['rulesetName']
        : null;
    if (rulesetName is! String || rulesetName.isEmpty) {
      return _Comparison('$label rules 릴리스에 ruleset 이 없습니다');
    }
    final RestResponse ruleset = await context.rest.send(
      buildRulesetRequest(projectId, rulesetName),
    );
    if (!ruleset.isOk) {
      return _Comparison.failed(
        '$label ruleset 을 읽지 못했습니다 — ${describeRestStatus(ruleset)}',
        ruleset,
      );
    }
    final String? deployed = _readSingleContent(ruleset);
    if (deployed == null || deployed.trim() != local.trim()) {
      return _Comparison('배포된 $label rules 가 저장소 파일과 다릅니다');
    }
    return const _Comparison('');
  }

  /// ruleset 응답의 `source.files[]` 가 하나면 그 `content` 를 돌려준다.
  static String? _readSingleContent(RestResponse response) {
    final Object? decoded = response.decodeJson();
    if (decoded is! Map<String, Object?>) return null;
    final Object? source = decoded['source'];
    if (source is! Map<String, Object?>) return null;
    final Object? files = source['files'];
    if (files is! List<Object?> || files.length != 1) return null;
    final Object? file = files.single;
    if (file is! Map<String, Object?>) return null;
    final Object? content = file['content'];
    return content is String ? content : null;
  }

  /// 저장소 파일을 읽는다 — 없거나 읽지 못하면 null.
  static String? _readLocal(WizardContext context, String relativePath) {
    final file = File(context.resolve(relativePath));
    if (!file.existsSync()) return null;
    try {
      return file.readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  /// [mode] 판정과 사유를 두고 할 일 결과를 만든다.
  CheckResult _mark(_RulesMode mode, String reason, {CommandResult? result}) {
    _mode = mode;
    _reason = reason;
    _failedResult = result;
    return Todo(reason);
  }
}

/// 릴리스 하나의 비교 결과 — [problem] 이 비었으면 같다.
final class _Comparison {
  const _Comparison(this.problem) : result = null;

  _Comparison.failed(this.problem, RestResponse response)
    : result = toFailureResult(response);

  /// 사유(같으면 빈 문자열).
  final String problem;

  /// 요청 실패 응답 원문 — 실패가 아니면 null.
  final CommandResult? result;
}

/// 직전 검사의 판정.
enum _RulesMode {
  /// 배포가 필요하다.
  deploy,

  /// 릴리스 · ruleset 을 읽지 못했다.
  requestFailed,

  /// 프로젝트 ID · 저장소 파일을 읽지 못했다.
  unreadable,

  /// 끝남.
  done,
}
