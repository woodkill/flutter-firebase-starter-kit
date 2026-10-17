import 'dart:convert';
import 'dart:io';

import '../command_runner.dart';
import '../config_files.dart';
import '../confirm.dart';
import '../flavor.dart';
import '../git_tree.dart';
import '../step.dart';
import '../terminal.dart';
import '../wizard.dart';
import 'identity_step.dart';

/// Firebase 프로젝트 단계 — 고른 flavor 의 프로젝트를 정하고
/// `config/<flavor>.json` 의 `firebaseProjectId` 와 `.firebaserc` 별칭에 쓴다.
///
/// 별칭은 dev 면 `default` · `dev`, stg · prod 면 그 flavor 이름 하나만 쓰고 다른
/// 별칭은 그대로 둔다. 프로젝트 ID 의 진실원은 그 config 의 `firebaseProjectId`
/// 하나다. 그 값이
/// 자리표시(빈 값 · example 값)가 아니면 묻지 않고 내 계정의 Firebase 프로젝트
/// 목록에 있는지 본다. 목록에 없으면 `gcloud projects describe` 로 내 Google
/// Cloud 프로젝트인지 보고, 맞으면 Firebase 추가만 남은 것으로 판정해 확인 표 뒤에
/// Firebase 를 추가한다.
/// 자리표시면 새로 만들기 · 기존 프로젝트에서 고르기를 묻는다. 새로 만들기는
/// 확인 표 뒤에 `gcloud projects create` 를 실행하고, Firebase 추가 **전에** 그
/// ID 를 config 와 별칭에 쓴 뒤 `firebase projects:addfirebase` 를 실행한다.
/// Firebase 추가가 실패하면 Firebase 콘솔에서 할 일을 보이고 Enter 를 기다려
/// 다시 검사한다. 모든 명령은 프로젝트 ID 를 인자로 명시하고 CLI 의 전역 설정을
/// 바꾸지 않는다.
final class FirebaseProjectStep implements Step {
  /// Firebase 프로젝트 단계를 만든다.
  FirebaseProjectStep();

  /// 단계 제목.
  static const String stepTitle = 'Firebase 프로젝트';

  /// 프로젝트 ID 를 읽고 쓰는 사용자 설정 키.
  static const String projectIdKey = 'firebaseProjectId';

  /// dev 기본값 — dev example config 의 자리표시 프로젝트 ID. 단계는
  /// `context.flavor.placeholderProjectId` 를 쓴다.
  static final String placeholderProjectId = Flavor.dev.placeholderProjectId;

  /// firebase CLI 별칭 파일(추적 파일).
  static const String firebasercPath = '.firebaserc';

  /// 프로젝트 prefix 상수를 읽는 스크립트(앱 정체성 단계가 이 값을 바꾼다).
  static const String configureScriptPath = 'scripts/firebase-configure.sh';

  /// dev 기본값 — 새 dev 프로젝트 ID 제안의 접미사. 단계는
  /// `context.flavor.projectIdSuffix` 를 쓴다.
  static final String devSuffix = Flavor.dev.projectIdSuffix;

  /// 같은 질문을 다시 묻는 최대 횟수.
  static const int maxInputAttempts = 3;

  /// 프로젝트 ID 규칙 — 소문자로 시작, 소문자 · 숫자 · `-`, `-` 로 끝나지 않는 6~30자.
  static final RegExp projectIdPattern = RegExp(
    r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$',
  );

  /// 내 계정의 Firebase 프로젝트 목록을 읽는 명령.
  static const Command projectsListCommand = Command('firebase', <String>[
    'projects:list',
    '--json',
  ]);

  /// 새로 만들기 · 고르기 질문.
  static const String projectChoiceQuestion = 'Firebase 프로젝트를 어떻게 정할까요?';

  /// 새로 만들기 선택지.
  static const String createOption = '새로 만들기';

  /// 기존 프로젝트에서 고르기 선택지.
  static const String pickOption = '기존 프로젝트에서 고르기';

  /// 새 프로젝트 ID 질문.
  static const String idQuestion =
      '새 프로젝트 ID — 소문자 · 숫자 · - 로 6~30자 (예: my-app-dev)';

  /// 기존 프로젝트 고르기 질문.
  static const String pickQuestion = '쓸 프로젝트를 고르세요';

  /// 프로젝트 ID 형식 오류.
  static const String invalidIdMessage =
      '  프로젝트 ID 형식이 아닙니다 — 소문자로 시작하고 소문자 · 숫자 · - 만 쓰며 '
      '- 로 끝나지 않는 6~30자여야 합니다';

  /// 확인 표 제목.
  static const String confirmTitle = '새 Firebase 프로젝트 — 확인';

  /// 확인 표 경고.
  static const String permanentIdWarning =
      '프로젝트 ID 는 만든 뒤 바꿀 수 없고, 지운 뒤에도 다시 쓸 수 없습니다.';

  /// dev 기본값 — config 의 ID 가 내 목록에 없을 때의 안내.
  static final String accountPermissionGuidance =
      describeAccountPermissionGuidance(const FlavorPaths(Flavor.dev).json);

  /// [jsonPath] config 의 ID 가 내 목록에 없을 때의 안내를 만든다.
  static String describeAccountPermissionGuidance(String jsonPath) =>
      '로그인한 계정이 이 프로젝트에 접근할 수 있는지(계정 · 권한) 확인하세요 — '
      '다른 프로젝트를 쓰려면 $jsonPath 의 firebaseProjectId 를 고친 뒤 다시 실행하세요';

  /// [flavor] 실행이 `.firebaserc` 에 쓰는 별칭 — dev 는 `default` · `dev`,
  /// 다른 flavor 는 그 이름 하나다.
  static List<String> listAliasNames(Flavor flavor) => <String>[
    if (flavor == Flavor.dev) 'default',
    flavor.name,
  ];

  /// gcloud 가 ID 충돌(HTTP 409)을 자기 문구로 바꿔 보이는 조각(소문자).
  ///
  /// `gcloud projects create` 는 409 를 잡아 「The project ID you specified is
  /// already in use by another project」 로 다시 던진다(SDK
  /// `surface/projects/create.py`).
  static const String idTakenMarker = 'already in use by another project';

  /// gcloud 가 치환하지 않은 API 원문의 ID 충돌 조각(소문자) — 보조 술어.
  static const String apiConflictMarker = 'already exists';

  /// 이미 쓰이는 프로젝트 ID 일 때의 안내.
  static const String idTakenGuidance =
      '이미 쓰이는 프로젝트 ID 입니다 — 다시 시도에서 다른 ID 를 입력하세요';

  /// 프로젝트 만들기가 실패했을 때(이미 쓰이는 ID 가 아님)의 Google Cloud 약관 안내.
  static const String cloudTermsGuidance =
      '처음 쓰는 Google 계정이면 브라우저에서 https://console.cloud.google.com/ 을 '
      '열어 Google Cloud 약관에 동의한 뒤 다시 시도하세요';

  /// Firebase 추가만 남은 프로젝트의 확인 표 제목.
  static const String addFirebaseConfirmTitle = 'Firebase 추가 — 확인';

  /// Firebase 추가 확인 표의 경고.
  static const String addFirebaseIrreversibleWarning =
      'Google Cloud 프로젝트에 Firebase 를 추가하면 되돌릴 수 없습니다.';

  /// Firebase 콘솔 주소 — Firebase 추가가 실패하면 여기서 마저 진행한다.
  static const String firebaseConsoleUrl =
      'https://console.firebase.google.com/';

  /// 내 계정에 이미 있는 프로젝트라 만들기를 건너뛸 때의 줄.
  static const String existingProjectNotice =
      '  내 계정에 이미 있는 프로젝트입니다 — 만들기를 건너뛰고 Firebase 만 추가합니다';

  _ProjectMode _mode = _ProjectMode.unreadable;
  String _reason = '';
  String _projectId = '';
  CommandResult? _listResult;

  @override
  String get id => 'firebase_project';

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['login', 'identity'];

  // 확인 표는 새로 만들기(고르기 모드 안) · Firebase 추가에서만 보인다 — 별칭
  // 쓰기 · 실패 전용 모드에는 안내가 붙지 않는다.
  @override
  bool get isCostlyOrIrreversible =>
      _mode == _ProjectMode.choose || _mode == _ProjectMode.addFirebase;

  /// [value] 가 프로젝트 ID 규칙에 맞으면 true.
  static bool isValidProjectId(String value) =>
      projectIdPattern.hasMatch(value);

  /// `gcloud projects describe` 명령을 만든다 — 내 계정에 이미 있는지 확인한다.
  static Command buildDescribeCommand(String projectId) => Command(
    'gcloud',
    <String>['projects', 'describe', projectId, '--format=value(projectId)'],
  );

  /// `gcloud projects create` 명령을 만든다 — 표시 이름도 ID 와 같게 둔다.
  static Command buildCreateCommand(String projectId) => Command(
    'gcloud',
    <String>['projects', 'create', projectId, '--name=$projectId'],
  );

  /// `firebase projects:addfirebase` 명령을 만든다.
  static Command buildAddFirebaseCommand(String projectId) =>
      Command('firebase', <String>['projects:addfirebase', projectId]);

  /// Firebase 추가가 실패했을 때 Firebase 콘솔에서 할 일을 안내한다.
  ///
  /// 처음 쓰는 Google 계정은 콘솔에서 프로젝트에 Firebase 를 추가하는 흐름
  /// 중간에서 약관에 동의해야 명령이 통한다. 위저드는 이 안내 뒤 Enter 를
  /// 기다려 그 자리에서 다시 검사한다. 콘솔 라벨은 「」 로 감싼 화면 원문이다.
  /// 애널리틱스를 켜 둔 채 진행할 때 나오는 약관 체크도 함께 안내한다.
  static String buildAddFirebaseGuide(String projectId) => <String>[
    '  Firebase 를 추가하지 못했습니다 — 처음 쓰는 Google 계정이면 Firebase 콘솔에서 이 프로젝트에 Firebase 를 추가하면서 약관에 동의해야 합니다.',
    '  브라우저에서 아래를 차례로 진행하세요:',
    '    1. $firebaseConsoleUrl 을 엽니다',
    '    2. 「Firebase 프로젝트를 설정하여 시작하기」 를 누르고, 기존 Google Cloud 프로젝트에 Firebase 를 추가하는 메뉴로 갑니다',
    '    3. 프로젝트 목록에서 $projectId 를 고르고 약관에 동의합니다',
    '    4. 「Google Cloud 프로젝트에 Firebase를 추가할 때 유의해야 할 사항」 화면에서 「계속」 을 누릅니다',
    '    5. 「Firebase 프로젝트를 위한 Google 애널리틱스」 화면은 켜든 끄든 위저드 진행과 관계없습니다',
    '    6. 「이 프로젝트에서 Google 애널리틱스 사용 설정」 을 켜 둔 채(기본값) 진행하면 「Google 애널리틱스 구성」 화면에서 「Google 애널리틱스 약관에 동의합니다.」 를 체크해야 「Firebase 추가」 를 누를 수 있습니다',
    '    7. 「Firebase 프로젝트가 준비되었습니다.」 가 보일 때까지 진행합니다',
    '  다 끝내고 Enter 를 누르면 위저드가 $projectId 를 다시 확인합니다.',
  ].join('\n');

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String configPath = context.resolve(context.paths.json);
    final String? configured = File(configPath).existsSync()
        ? readJsonString(configPath, projectIdKey)
        : null;
    if (configured == null) {
      _mode = _ProjectMode.unreadable;
      _reason = '${context.paths.json} 에서 $projectIdKey 를 읽지 못했습니다';
      return Todo(_reason);
    }
    _projectId = configured.trim();
    if (_projectId.isEmpty ||
        _projectId == context.flavor.placeholderProjectId) {
      _mode = _ProjectMode.choose;
      _reason = 'Firebase 프로젝트가 아직 정해지지 않았습니다';
      return Todo(_reason);
    }

    final CommandResult list = await context.runner.capture(
      projectsListCommand,
    );
    _listResult = list;
    final List<_ProjectEntry>? projects = _parseProjects(list);
    if (projects == null) {
      _mode = _ProjectMode.listFailed;
      _reason = 'Firebase 프로젝트 목록을 읽지 못했습니다';
      return Todo(_reason);
    }
    if (!projects.any((_ProjectEntry entry) => entry.projectId == _projectId)) {
      // Firebase 목록에 없어도 내 Google Cloud 프로젝트면 Firebase 추가만 남았다.
      final CommandResult described = await context.runner.capture(
        buildDescribeCommand(_projectId),
      );
      if (described.isSuccess && described.stdout.trim() == _projectId) {
        _mode = _ProjectMode.addFirebase;
        _reason = '$_projectId 에 아직 Firebase 가 추가되지 않았습니다';
        return Todo(_reason);
      }
      _mode = _ProjectMode.missing;
      _reason = '$_projectId 가 내 계정의 Firebase 프로젝트 목록에 없습니다';
      return Todo(_reason);
    }
    if (!_hasMatchingAliases(context, _projectId)) {
      _mode = _ProjectMode.writeAliases;
      _reason =
          '$firebasercPath 의 ${_describeAliases(context)} 가 $_projectId 가 아닙니다';
      return Todo(_reason);
    }
    _mode = _ProjectMode.done;
    return Done(_projectId);
  }

  @override
  List<String> plannedCommandLines(WizardContext context) {
    final String aliases = _describeAliases(context);
    final String guidance = describeAccountPermissionGuidance(
      context.paths.json,
    );
    final aliasLine =
        '(${context.paths.json} 의 $projectIdKey · $firebasercPath 의 '
        '$aliases 를 정한 ID 로 씀)';
    return switch (_mode) {
      _ProjectMode.choose => <String>[
        '(새로 만들기 / 기존 프로젝트에서 고르기를 묻습니다 — 새로 만들면 확인 표 뒤에 아래 명령을 실행합니다)',
        'gcloud projects create <프로젝트 ID> --name=<프로젝트 ID>',
        'firebase projects:addfirebase <프로젝트 ID>',
        aliasLine,
        '(Firebase 추가가 실패하면 콘솔에서 할 일을 보이고 Enter 를 기다립니다)',
      ],
      _ProjectMode.addFirebase => <String>[
        buildAddFirebaseCommand(_projectId).render(),
        '(이 Google Cloud 프로젝트에 Firebase 를 추가합니다 — 되돌릴 수 없어 실행 전에 확인 표를 보이고, 실패하면 콘솔에서 할 일을 보입니다)',
      ],
      _ProjectMode.writeAliases => <String>[
        '($firebasercPath 의 $aliases 를 $_projectId 로 씀)',
      ],
      _ProjectMode.missing => <String>['($guidance)'],
      _ProjectMode.listFailed => <String>[
        '(${projectsListCommand.render()} 의 출력을 보입니다)',
      ],
      _ProjectMode.unreadable || _ProjectMode.done => const <String>[],
    };
  }

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    try {
      return switch (_mode) {
        _ProjectMode.choose => await _applyChoose(context),
        _ProjectMode.writeAliases => await _applyAliasesOnly(context),
        _ProjectMode.addFirebase => await _applyAddFirebase(context),
        _ProjectMode.missing => Failed(
          '$_reason — '
          '${describeAccountPermissionGuidance(context.paths.json)}',
        ),
        _ProjectMode.listFailed => Failed(_reason, result: _listResult),
        _ProjectMode.unreadable => Failed(_reason),
        _ProjectMode.done => const Applied(),
      };
    } on GitTreeException catch (e) {
      return Failed(e.message, result: e.result);
    } on FileSystemException catch (e) {
      return Failed('파일을 고치지 못했습니다 — $e');
    } on FormatException catch (e) {
      return Failed('설정 파일을 고치지 못했습니다 — $e');
    } on ConfigEditException catch (e) {
      return Failed('프로젝트 ID 를 쓰지 못했습니다 — ${e.message}');
    }
  }

  /// `.firebaserc` 별칭만 config 의 ID 로 맞춘다.
  Future<StepOutcome> _applyAliasesOnly(WizardContext context) async {
    final Failed? dirty = await _findDirtyFirebaserc(context);
    if (dirty != null) return dirty;
    _writeAliases(context, _projectId);
    return const Applied();
  }

  /// Firebase 추가만 남은 config 의 프로젝트에 확인 표 뒤 Firebase 를 추가한다.
  ///
  /// 위저드가 앞 실행에서 확정한 ID 인지 가릴 수 없으므로 실행 직전에 값 표를
  /// 한 번 보인다(Enter · N · 입력 끝 = 실행 · 파일 변경 없이 멈춤). 별칭이 이미
  /// 그 ID 면 `.firebaserc` 를 쓰지 않고 미커밋 변경도 검사하지 않는다. 다르면
  /// 미커밋 변경 검사 → 표 → 별칭 쓰기 → 실행 순서다.
  Future<StepOutcome> _applyAddFirebase(WizardContext context) async {
    final bool hasAliases = _hasMatchingAliases(context, _projectId);
    if (!hasAliases) {
      final Failed? dirty = await _findDirtyFirebaserc(context);
      if (dirty != null) return dirty;
    }
    if (!confirmSummary(
      context.terminal,
      title: addFirebaseConfirmTitle,
      rows: <SummaryRow>[
        SummaryRow('프로젝트 ID', _projectId),
        const SummaryRow('하는 일', 'Google Cloud 프로젝트에 Firebase 추가'),
      ],
      warnings: const <String>[addFirebaseIrreversibleWarning],
    )) {
      return const Declined();
    }
    if (!hasAliases) _writeAliases(context, _projectId);
    return await _addFirebaseOrGuide(context, _projectId);
  }

  /// 새로 만들기 · 고르기를 묻고 고른 쪽을 진행한다.
  Future<StepOutcome> _applyChoose(WizardContext context) async {
    // 프로젝트를 만든 뒤 별칭을 못 쓰는 일이 없도록 쓰기 대상부터 검사한다.
    final Failed? dirty = await _findDirtyFirebaserc(context);
    if (dirty != null) return dirty;
    final int? choice = context.terminal.choose(
      projectChoiceQuestion,
      const <String>[createOption, pickOption],
    );
    if (choice == null) return const Declined();
    return await (choice == 0 ? _applyCreate(context) : _applyPick(context));
  }

  /// 새 ID 를 받아 확인 표 뒤에 프로젝트를 만들고, 기록한 뒤 Firebase 를 추가한다.
  Future<StepOutcome> _applyCreate(WizardContext context) async {
    final Terminal terminal = context.terminal;
    final String? suggested = _readSuggestedId(context);
    final String? projectId = _askProjectId(terminal, suggested);
    if (projectId == null) return const Declined();
    if (projectId.isEmpty) {
      return const Failed('프로젝트 ID 형식이 맞지 않아 진행하지 않았습니다');
    }
    if (!confirmSummary(
      terminal,
      title: confirmTitle,
      rows: <SummaryRow>[
        SummaryRow('프로젝트 ID', projectId),
        SummaryRow('표시 이름', projectId),
        const SummaryRow('만드는 곳', 'Google Cloud 프로젝트 + Firebase 추가'),
      ],
      warnings: const <String>[permanentIdWarning],
    )) {
      return const Declined();
    }

    final CommandResult described = await context.runner.capture(
      buildDescribeCommand(projectId),
    );
    if (described.isSuccess && described.stdout.trim() == projectId) {
      terminal.writeLine(existingProjectNotice);
    } else {
      final CommandResult created = await context.runner.stream(
        buildCreateCommand(projectId),
      );
      if (!created.isSuccess) {
        final String output = '${created.stdout}\n${created.stderr}'
            .toLowerCase();
        // gcloud 문구가 1차 술어, API 원문은 다른 출력 경로를 위한 보조 술어다.
        final String guidance =
            output.contains(idTakenMarker) || output.contains(apiConflictMarker)
            ? idTakenGuidance
            : cloudTermsGuidance;
        return Failed('프로젝트를 만들지 못했습니다 — $guidance', result: created);
      }
    }

    // Firebase 추가가 막혀도 Enter 재검사 · 다시 실행이 같은 ID 로 이어지게 먼저 쓴다.
    _writeProjectId(context, projectId);
    return await _addFirebaseOrGuide(context, projectId);
  }

  /// [projectId] 에 Firebase 를 추가한다 — 실패하면 콘솔 안내 뒤 Enter 를 기다린다.
  ///
  /// 실패 출력 원문은 실행 중에 이미 화면에 흘렀으므로 다시 싣지 않는다. 출력
  /// 문자열이 아니라 실패 자체로 안내한다.
  Future<StepOutcome> _addFirebaseOrGuide(
    WizardContext context,
    String projectId,
  ) async {
    final CommandResult added = await context.runner.stream(
      buildAddFirebaseCommand(projectId),
    );
    if (added.isSuccess) return const Applied();
    return WaitForUser(buildAddFirebaseGuide(projectId));
  }

  /// 내 계정의 Firebase 프로젝트 목록에서 하나를 고르게 하고 기록한다.
  Future<StepOutcome> _applyPick(WizardContext context) async {
    final CommandResult list = await context.runner.capture(
      projectsListCommand,
    );
    final List<_ProjectEntry>? projects = _parseProjects(list);
    if (projects == null) {
      return Failed('Firebase 프로젝트 목록을 읽지 못했습니다', result: list);
    }
    if (projects.isEmpty) {
      return const Failed('내 계정에 Firebase 프로젝트가 없습니다 — 다시 시도에서 새로 만들기를 고르세요');
    }
    // 결제 · 위치가 뒤따르는 선택이라 Enter 만으로 고르지 않는다(기본값 없음).
    final int? index = context.terminal.choose(pickQuestion, <String>[
      for (final _ProjectEntry entry in projects) entry.label,
    ], defaultIndex: null);
    if (index == null) return const Declined();
    _writeProjectId(context, projects[index].projectId);
    return const Applied();
  }

  /// 새 ID 를 규칙에 맞을 때까지 [maxInputAttempts] 번까지 묻는다.
  ///
  /// 입력 끝이면 null, 끝까지 틀리면 빈 문자열을 돌려준다.
  String? _askProjectId(Terminal terminal, String? suggested) {
    for (var attempt = 0; attempt < maxInputAttempts; attempt++) {
      final String? answer = terminal.ask(idQuestion, defaultValue: suggested);
      if (answer == null) return null;
      final String trimmed = answer.trim();
      if (isValidProjectId(trimmed)) return trimmed;
      terminal.writeLine(invalidIdMessage);
    }
    return '';
  }

  /// configure 스크립트의 `PROJECT_ID_PREFIX="…"` 줄로 `<prefix>-<flavor>` 를
  /// 제안한다.
  ///
  /// 줄 머리가 `PROJECT_ID_PREFIX=` 인 줄만 읽는다(주석 · 들여쓴 계산 줄 제외).
  /// 파일 · 줄이 없거나 제안값이 규칙에 맞지 않으면 null.
  String? _readSuggestedId(WizardContext context) {
    final script = File(context.resolve(configureScriptPath));
    if (!script.existsSync()) return null;
    final RegExpMatch? match = RegExp(
      '^PROJECT_ID_PREFIX="([^"]*)"',
      multiLine: true,
    ).firstMatch(script.readAsStringSync());
    if (match == null) return null;
    final suggested = '${match.group(1)}${context.flavor.projectIdSuffix}';
    return isValidProjectId(suggested) ? suggested : null;
  }

  /// `.firebaserc` 에 커밋하지 않은 변경이 있으면 실패 결과를, 없으면 null.
  Future<Failed?> _findDirtyFirebaserc(WizardContext context) async {
    final List<String> dirty = await findDirtyTrackedFiles(
      context,
      const <String>[firebasercPath],
    );
    if (dirty.isEmpty) return null;
    return Failed(
      '고칠 파일에 커밋하지 않은 변경이 있습니다 — ${IdentityStep.dirtyTreeGuidance}\n'
      '${dirty.map((String path) => '    $path').join('\n')}',
    );
  }

  /// config 의 프로젝트 ID 와 `.firebaserc` 별칭을 [projectId] 로 쓴다.
  void _writeProjectId(WizardContext context, String projectId) {
    replaceJsonString(
      context.resolve(context.paths.json),
      projectIdKey,
      projectId,
    );
    _writeAliases(context, projectId);
  }

  /// `.firebaserc` 에서 고른 flavor 의 별칭([listAliasNames])을 [projectId] 로
  /// 쓴다.
  ///
  /// 다른 키 · 별칭은 그대로 두고 2칸 들여쓰기 + 끝 개행으로 원자적으로 쓴다.
  /// 파일이 없으면 그 flavor 의 별칭만 담아 만든다.
  void _writeAliases(WizardContext context, String projectId) {
    final file = File(context.resolve(firebasercPath));
    final Map<String, Object?> root = file.existsSync()
        ? _decodeObject(file.readAsStringSync())
        : <String, Object?>{};
    final Object? existing = root['projects'];
    final Map<String, Object?> projects = existing is Map<String, Object?>
        ? existing
        : <String, Object?>{};
    for (final String alias in listAliasNames(context.flavor)) {
      projects[alias] = projectId;
    }
    root['projects'] = projects;
    writeFileAtomically(
      file.path,
      '${const JsonEncoder.withIndent('  ').convert(root)}\n',
    );
  }

  /// `.firebaserc` 에서 고른 flavor 의 별칭이 모두 [projectId] 면 true.
  bool _hasMatchingAliases(WizardContext context, String projectId) {
    final file = File(context.resolve(firebasercPath));
    if (!file.existsSync()) return false;
    final Map<String, Object?> root;
    try {
      root = _decodeObject(file.readAsStringSync());
    } on FormatException {
      return false;
    }
    final Object? projects = root['projects'];
    return projects is Map<String, Object?> &&
        listAliasNames(
          context.flavor,
        ).every((String alias) => projects[alias] == projectId);
  }

  /// 고른 flavor 의 별칭을 화면 표기(`default · dev` · `stg`)로 잇는다.
  static String _describeAliases(WizardContext context) =>
      listAliasNames(context.flavor).join(' · ');

  /// [content] 를 JSON 객체로 읽는다 — 객체가 아니면 [FormatException].
  static Map<String, Object?> _decodeObject(String content) {
    final Object? decoded = jsonDecode(content);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('$firebasercPath 최상위가 JSON 객체가 아닙니다');
    }
    return decoded;
  }

  /// `firebase projects:list --json` 결과를 읽는다 — 실패 · 모양이 다르면 null.
  static List<_ProjectEntry>? _parseProjects(CommandResult result) {
    if (!result.isSuccess) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(result.stdout);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final Object? items = decoded['result'];
    if (items is! List<Object?>) return null;
    return <_ProjectEntry>[
      for (final Object? item in items)
        if (item is Map<String, Object?> && item['projectId'] is String)
          _ProjectEntry(
            item['projectId']! as String,
            item['displayName'] is String ? item['displayName']! as String : '',
          ),
    ];
  }
}

/// 목록의 프로젝트 하나.
final class _ProjectEntry {
  const _ProjectEntry(this.projectId, this.displayName);

  final String projectId;
  final String displayName;

  /// 고르기 선택지 문구 — 표시 이름이 ID 와 다르면 괄호로 덧붙인다.
  String get label => displayName.isEmpty || displayName == projectId
      ? projectId
      : '$projectId ($displayName)';
}

/// 직전 검사의 판정.
enum _ProjectMode {
  /// config 가 자리표시 — 새로 만들기 · 고르기를 묻는다.
  choose,

  /// 프로젝트는 맞고 `.firebaserc` 별칭만 다르다.
  writeAliases,

  /// config 의 ID 가 내 Google Cloud 프로젝트인데 Firebase 가 아직 추가되지 않았다.
  addFirebase,

  /// config 의 ID 가 내 Firebase 목록에도, 내 Google Cloud 프로젝트에도 없다.
  missing,

  /// 프로젝트 목록 명령이 실패했다.
  listFailed,

  /// config 를 읽지 못했다.
  unreadable,

  /// 끝남.
  done,
}
