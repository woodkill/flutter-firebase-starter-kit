import '../command_runner.dart';
import '../step.dart';
import '../wizard.dart';
import 'billing_step.dart';

/// 필요한 Google Cloud API 단계 — 킷이 쓰는 API 가 켜져 있는지 보고 꺼진 것만 켠다.
///
/// 검사는 프로젝트에서 켜진 서비스 목록이다. 켜기 명령은 꺼진 서비스만 한 번에
/// 넘기고 프로젝트를 `--project` 로 명시한다. Cloud Functions 배포에 필요한 API 는
/// firebase CLI 가 배포 때 켜므로 이 목록에 넣지 않는다.
final class ApisStep implements Step {
  /// API 단계를 만든다.
  ApisStep();

  /// 단계 제목.
  static const String stepTitle = '필요한 Google Cloud API';

  /// 켜져 있어야 하는 서비스(전체 이름) — 킷 기능을 더하면 여기에 더한다.
  ///
  /// Firestore · Authentication(Identity Toolkit) · Cloud Storage for Firebase ·
  /// App Check · 보안 규칙 배포 · Functions secret 저장소 순서다.
  static const List<String> requiredServices = <String>[
    'firestore.googleapis.com',
    'identitytoolkit.googleapis.com',
    'firebasestorage.googleapis.com',
    'firebaseappcheck.googleapis.com',
    'firebaserules.googleapis.com',
    'secretmanager.googleapis.com',
  ];

  /// [projectId] 에서 켜진 서비스 이름을 한 줄에 하나씩 읽는 명령을 만든다.
  static Command buildEnabledListCommand(String projectId) =>
      Command('gcloud', <String>[
        'services',
        'list',
        '--enabled',
        '--project',
        projectId,
        '--format=value(config.name)',
      ]);

  /// [projectId] 에서 [services] 를 켜는 명령을 만든다.
  static Command buildEnableCommand(String projectId, List<String> services) =>
      Command('gcloud', <String>[
        'services',
        'enable',
        ...services,
        '--project',
        projectId,
      ]);

  _ApisMode _mode = _ApisMode.unreadable;
  String _reason = '';
  String _projectId = '';
  List<String> _missing = const <String>[];
  CommandResult? _failedResult;

  @override
  String get id => 'apis';

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['billing'];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      _mode = _ApisMode.unreadable;
      _reason = '${context.paths.json} 에서 프로젝트 ID 를 읽지 못했습니다';
      return Todo(_reason);
    }
    _projectId = projectId;
    final CommandResult result = await context.runner.capture(
      buildEnabledListCommand(projectId),
    );
    if (!result.isSuccess) {
      _mode = _ApisMode.listFailed;
      _reason = '$projectId 에서 켜진 API 목록을 읽지 못했습니다';
      _failedResult = result;
      return Todo(_reason);
    }
    final enabled = <String>{
      for (final String line in result.stdout.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    };
    _missing = <String>[
      for (final String service in requiredServices)
        if (!enabled.contains(service)) service,
    ];
    if (_missing.isEmpty) {
      _mode = _ApisMode.done;
      return Done('${requiredServices.length}개 모두 켜짐');
    }
    _mode = _ApisMode.enable;
    _reason = '꺼진 API: ${_missing.join(' · ')}';
    return Todo(_reason);
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _ApisMode.enable => <String>[
      buildEnableCommand(_projectId, _missing).render(),
    ],
    _ApisMode.listFailed ||
    _ApisMode.unreadable ||
    _ApisMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    switch (_mode) {
      case _ApisMode.enable:
        final CommandResult result = await context.runner.stream(
          buildEnableCommand(_projectId, _missing),
        );
        if (result.isSuccess) return const Applied();
        return Failed('API 를 켜지 못했습니다', result: result);
      case _ApisMode.listFailed:
        return Failed(_reason, result: _failedResult);
      case _ApisMode.unreadable:
        return Failed(_reason);
      case _ApisMode.done:
        return const Applied();
    }
  }
}

/// 직전 검사의 판정.
enum _ApisMode {
  /// 꺼진 API 를 켠다.
  enable,

  /// 켜진 API 목록 명령이 실패했다.
  listFailed,

  /// 프로젝트 ID 를 읽지 못했다.
  unreadable,

  /// 끝남.
  done,
}
