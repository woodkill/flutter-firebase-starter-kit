import 'dart:io';

import '../command_runner.dart';
import '../config_files.dart';
import '../confirm.dart';
import '../git_tree.dart';
import '../step.dart';
import '../terminal.dart';
import '../wizard.dart';
import 'billing_step.dart';
import 'identity_step.dart';
import 'user_files_step.dart';

/// Firestore `(default)` 데이터베이스 위치를 읽은 결과.
sealed class FirestoreLookup {
  /// 하위 클래스만 만든다.
  const FirestoreLookup();
}

/// 데이터베이스가 있다.
final class FirestoreFound extends FirestoreLookup {
  /// [locationId] 위치에 있는 데이터베이스.
  const FirestoreFound(this.locationId);

  /// gcloud 가 보인 위치 ID 그대로(예: 단일 리전 asia-northeast3 · 다중 리전 nam5).
  final String locationId;
}

/// 데이터베이스가 없다 — gcloud 가 `NOT_FOUND` 로 실패했다.
final class FirestoreMissing extends FirestoreLookup {
  /// 없음 결과를 만든다.
  const FirestoreMissing();
}

/// 위치를 읽지 못했다 — 「없음」 밖의 실패.
final class FirestoreLookupFailed extends FirestoreLookup {
  /// 실패한 명령 [result] 로 만든다.
  const FirestoreLookupFailed(this.result);

  /// 실패한 명령의 결과(출력 원문).
  final CommandResult result;

  /// 사유로 보일 첫 줄 — 표준 오류의 첫 줄, 없으면 종료 코드.
  String get firstLine {
    for (final String line in '${result.stderr}\n${result.stdout}'.split(
      '\n',
    )) {
      if (line.trim().isNotEmpty) return line.trim();
    }
    return '종료 코드 ${result.exitCode}';
  }
}

/// [projectId] 의 Firestore `(default)` 데이터베이스 위치를 읽는다.
///
/// 표준 오류에 `NOT_FOUND` 가 있는 실패만 「없음」 이고, 그 밖 실패 · 빈 출력은
/// [FirestoreLookupFailed] 다. 위치 · 기본 bucket 단계가 같은 명령으로 읽는다.
Future<FirestoreLookup> readFirestoreLocation(
  WizardContext context,
  String projectId,
) async {
  final CommandResult result = await context.runner.capture(
    FirestoreStep.buildDescribeCommand(projectId),
  );
  if (result.isSuccess) {
    final String location = result.stdout.trim();
    if (location.isNotEmpty) return FirestoreFound(location);
    return FirestoreLookupFailed(result);
  }
  if (result.stderr.contains('NOT_FOUND')) return const FirestoreMissing();
  return FirestoreLookupFailed(result);
}

/// 위치 · Firestore 단계 — 위치를 한 번 골라 Firestore 를 만들고 Functions 리전
/// 세 곳(`config/dev.json` · `functions/src/shared/region.ts` ·
/// `lib/core/config/app_config.dart`)에 같은 값을 쓴다.
///
/// 이미 있는 Firestore 의 위치는 바꾸지 않고 보여 주기만 하며, 세 리전 값이 서로
/// 다를 때만 Functions 리전을 고르게 한다. 고르기는 [singleRegions] 의 단일 리전만
/// 준다 — 다중 리전(nam5 · eur3 등)은 Functions · Storage 위치로 쓸 수 없다.
/// 데이터베이스 만들기는 값 확인 표 뒤에만 실행하고, 리전 파일은 값만 바꾸는
/// 그룹 보존 치환으로 쓴다. 고칠 추적 파일에 커밋하지 않은 변경이 있으면 멈춘다.
final class FirestoreStep implements Step {
  /// 위치 · Firestore 단계를 만든다.
  FirestoreStep();

  /// 단계 제목.
  static const String stepTitle = '위치 · Firestore';

  /// 고를 수 있는 단일 리전과 도시 — 첫 항목이 킷 기본값이다.
  ///
  /// Firestore · Cloud Functions · Cloud Storage 위치 문서 세 곳 모두에 있는 리전만
  /// 둔다. 다른 리전을 더할 때도 세 문서에 모두 있는지 확인한다.
  static const Map<String, String> singleRegions = <String, String>{
    'asia-northeast3': '서울',
    'asia-northeast1': '도쿄',
    'us-central1': '아이오와',
    'us-east1': '사우스캐롤라이나',
    'us-west1': '오리건',
    'europe-west1': '벨기에',
  };

  /// Functions 리전을 담은 저장소 TypeScript 파일.
  static const String regionTsPath = 'functions/src/shared/region.ts';

  /// Dart 기본 리전 상수를 담은 저장소 파일.
  static const String appConfigPath = 'lib/core/config/app_config.dart';

  /// 사용자 설정 파일의 Functions 리전 키.
  static const String functionsRegionKey = 'functionsRegion';

  /// region.ts 의 `REGION = "…"` — group 2 = 리전 값(앞뒤 그룹은 그대로 둔다).
  static final RegExp regionTsPattern = RegExp(r'(REGION\s*=\s*")([^"]+)(")');

  /// app_config.dart 의 `defaultFunctionsRegion = '…'` — group 2 = 리전 값.
  static final RegExp appConfigRegionPattern = RegExp(
    r"(defaultFunctionsRegion\s*=\s*')([^']+)(')",
  );

  /// 위치 고르기 질문(데이터베이스를 만들 때).
  static const String locationChoiceQuestion =
      'Firestore 위치를 고르세요 — Functions 리전도 같은 값이 됩니다';

  /// Functions 리전 고르기 질문(데이터베이스가 이미 있을 때).
  static const String regionChoiceQuestion = 'Functions 리전을 고르세요';

  /// 확인 표 제목.
  static const String confirmTitle = 'Firestore 위치 — 확인';

  /// 확인 표 경고.
  static const String locationImmutableWarning =
      'Firestore 위치는 만든 뒤 바꿀 수 없습니다.';

  /// 리전 세 곳을 함께 바꾼다는 안내.
  static const String regionFilesNotice =
      'Functions 리전을 바꾸면 config/dev.json · functions/src/shared/region.ts · '
      'lib/core/config/app_config.dart 세 곳이 함께 바뀝니다.';

  /// [projectId] 의 `(default)` 데이터베이스 위치를 읽는 명령을 만든다.
  static Command buildDescribeCommand(String projectId) =>
      Command('gcloud', <String>[
        'firestore',
        'databases',
        'describe',
        '--database=(default)',
        '--project',
        projectId,
        '--format=value(locationId)',
      ]);

  /// [projectId] 에 [location] 위치의 `(default)` 데이터베이스를 만드는 명령을 만든다.
  static Command buildCreateCommand(String location, String projectId) =>
      Command('gcloud', <String>[
        'firestore',
        'databases',
        'create',
        '--location=$location',
        '--project',
        projectId,
      ]);

  _FirestoreMode _mode = _FirestoreMode.unreadable;
  String _reason = '';
  String _projectId = '';
  String _firestoreLocation = '';
  _RegionValues? _regions;
  CommandResult? _failedResult;

  @override
  String get id => 'firestore';

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['apis'];

  // 확인 표는 데이터베이스 만들기에서만 보인다 — 리전 맞추기는 위치를 바꾸지
  // 않아 표 없이 고르기만 하고, 실패 전용 모드에는 안내가 붙지 않는다.
  @override
  bool get isCostlyOrIrreversible => _mode == _FirestoreMode.create;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      return _markUnreadable(
        '${UserFilesStep.jsonUserPath} 에서 프로젝트 ID 를 읽지 못했습니다',
      );
    }
    _projectId = projectId;
    final String? unreadable = _readRegions(context);
    if (unreadable != null) return _markUnreadable(unreadable);
    final _RegionValues regions = _regions!;

    final FirestoreLookup lookup = await readFirestoreLocation(
      context,
      projectId,
    );
    switch (lookup) {
      case FirestoreMissing():
        _mode = _FirestoreMode.create;
        _reason = '$projectId 에 Firestore 데이터베이스가 없습니다';
        return Todo(_reason);
      case FirestoreLookupFailed(:final CommandResult result):
        _mode = _FirestoreMode.lookupFailed;
        _reason = 'Firestore 위치를 읽지 못했습니다 — ${lookup.firstLine}';
        _failedResult = result;
        return Todo(_reason);
      case FirestoreFound(:final String locationId):
        _firestoreLocation = locationId;
        if (regions.isConsistent) {
          _mode = _FirestoreMode.done;
          return Done(
            '${_describeLocation(locationId)} · Functions 리전: ${regions.config}',
          );
        }
        _mode = _FirestoreMode.alignRegion;
        _reason =
            'Functions 리전 값이 세 곳에서 다릅니다 — '
            '${UserFilesStep.jsonUserPath} ${regions.config} · '
            'region.ts ${regions.regionTs} · '
            'app_config.dart ${regions.appConfig}';
        return Todo(_reason);
    }
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _FirestoreMode.create => <String>[
      '(위치를 고르고 확인 표 뒤에 아래 명령을 실행합니다)',
      'gcloud firestore databases create --location=<위치> '
          '--project $_projectId',
      '(고른 위치가 지금 Functions 리전과 다르면 세 파일의 리전 값을 함께 바꿉니다)',
    ],
    _FirestoreMode.alignRegion => <String>[
      '(Firestore 는 그대로 두고 Functions 리전을 골라 세 파일에 같은 값을 씁니다)',
    ],
    _FirestoreMode.lookupFailed => <String>[
      '(${buildDescribeCommand(_projectId).render()} 의 오류를 보입니다)',
    ],
    _FirestoreMode.unreadable || _FirestoreMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    try {
      return switch (_mode) {
        _FirestoreMode.create => await _applyCreate(context),
        _FirestoreMode.alignRegion => await _applyAlign(context),
        _FirestoreMode.lookupFailed => Failed(_reason, result: _failedResult),
        _FirestoreMode.unreadable => Failed(_reason),
        _FirestoreMode.done => const Applied(),
      };
    } on GitTreeException catch (e) {
      return Failed(e.message, result: e.result);
    } on FileSystemException catch (e) {
      return Failed('리전 파일을 고치지 못했습니다 — $e');
    } on FormatException catch (e) {
      return Failed('${UserFilesStep.jsonUserPath} 을 고치지 못했습니다 — $e');
    } on StateError catch (e) {
      return Failed('리전 값을 쓰지 못했습니다 — ${e.message}');
    }
  }

  /// 위치를 고르게 하고 확인 표 뒤에 데이터베이스를 만든 다음 세 파일을 맞춘다.
  Future<StepOutcome> _applyCreate(WizardContext context) async {
    final Terminal terminal = context.terminal;
    final _RegionValues regions = _regions!;
    terminal.writeLine('  $regionFilesNotice');
    final String? location = _chooseRegion(
      terminal,
      locationChoiceQuestion,
      preferred: regions.config,
    );
    if (location == null) return const Declined();
    final List<String> changedPaths = _listChangedPaths(regions, location);
    if (!confirmSummary(
      terminal,
      title: confirmTitle,
      rows: <SummaryRow>[
        SummaryRow('프로젝트 ID', _projectId),
        SummaryRow('Firestore 위치', location),
        SummaryRow('Functions 리전', location),
        SummaryRow(
          '바꿀 파일',
          changedPaths.isEmpty ? '없음 (지금 값과 같음)' : changedPaths.join(' · '),
        ),
      ],
      warnings: const <String>[locationImmutableWarning],
    )) {
      return const Declined();
    }

    final StepOutcome? dirty = await _guardDirtyFiles(
      context,
      regions,
      location,
    );
    if (dirty != null) return dirty;
    final CommandResult created = await context.runner.stream(
      buildCreateCommand(location, _projectId),
    );
    if (!created.isSuccess) {
      return Failed('Firestore 데이터베이스를 만들지 못했습니다', result: created);
    }
    _writeRegions(context, regions, location);
    return const Applied();
  }

  /// 이미 있는 Firestore 는 그대로 두고 Functions 리전만 골라 세 파일을 맞춘다.
  Future<StepOutcome> _applyAlign(WizardContext context) async {
    final Terminal terminal = context.terminal;
    final _RegionValues regions = _regions!;
    terminal
      ..writeLine('  ${_describeLocation(_firestoreLocation)}')
      ..writeLine('  $regionFilesNotice');
    final String? region = _chooseRegion(
      terminal,
      regionChoiceQuestion,
      preferred: singleRegions.containsKey(_firestoreLocation)
          ? _firestoreLocation
          : regions.config,
    );
    if (region == null) return const Declined();
    final StepOutcome? dirty = await _guardDirtyFiles(context, regions, region);
    if (dirty != null) return dirty;
    _writeRegions(context, regions, region);
    return const Applied();
  }

  /// 단일 리전 목록에서 하나를 고르게 한다 — 입력 끝이면 null.
  ///
  /// [preferred] 가 목록에 있으면 그 항목이 기본값이고, 없으면 첫 항목이다.
  String? _chooseRegion(
    Terminal terminal,
    String question, {
    required String preferred,
  }) {
    final List<String> regions = singleRegions.keys.toList();
    final int preferredIndex = regions.indexOf(preferred);
    final int? index = terminal.choose(question, <String>[
      for (final String region in regions) '$region (${singleRegions[region]})',
    ], defaultIndex: preferredIndex < 0 ? 0 : preferredIndex);
    return index == null ? null : regions[index];
  }

  /// [region] 으로 바꿀 때 값이 달라지는 파일의 저장소 상대 경로를 모은다.
  List<String> _listChangedPaths(_RegionValues regions, String region) =>
      <String>[
        if (regions.config != region) UserFilesStep.jsonUserPath,
        if (regions.regionTs != region) regionTsPath,
        if (regions.appConfig != region) appConfigPath,
      ];

  /// 고칠 추적 파일(region.ts · app_config.dart 가운데 값이 바뀌는 것)에 커밋하지
  /// 않은 변경이 있으면 실패를 돌려준다 — 고칠 추적 파일이 없으면 git 을 부르지 않는다.
  Future<StepOutcome?> _guardDirtyFiles(
    WizardContext context,
    _RegionValues regions,
    String region,
  ) async {
    final List<String> trackedTargets = <String>[
      if (regions.regionTs != region) regionTsPath,
      if (regions.appConfig != region) appConfigPath,
    ];
    if (trackedTargets.isEmpty) return null;
    final List<String> dirty = await findDirtyTrackedFiles(
      context,
      trackedTargets,
    );
    if (dirty.isEmpty) return null;
    return Failed(
      '고칠 파일에 커밋하지 않은 변경이 있습니다 — ${IdentityStep.dirtyTreeGuidance}\n'
      '${dirty.map((String path) => '    $path').join('\n')}',
    );
  }

  /// 값이 [region] 과 다른 파일만 골라 리전 값을 쓴다 — 나머지 바이트는 그대로다.
  void _writeRegions(
    WizardContext context,
    _RegionValues regions,
    String region,
  ) {
    if (regions.config != region) {
      replaceJsonString(
        context.resolve(UserFilesStep.jsonUserPath),
        functionsRegionKey,
        region,
      );
    }
    if (regions.regionTs != region) {
      _replaceRegionValue(
        context.resolve(regionTsPath),
        regionTsPattern,
        region,
      );
    }
    if (regions.appConfig != region) {
      _replaceRegionValue(
        context.resolve(appConfigPath),
        appConfigRegionPattern,
        region,
      );
    }
  }

  /// [path] 에서 [pattern] 의 값 그룹만 [region] 으로 바꿔 쓴다.
  ///
  /// 일치가 정확히 한 곳이 아니면 쓰지 않고 [StateError] 를 던진다.
  static void _replaceRegionValue(String path, RegExp pattern, String region) {
    final String original = File(path).readAsStringSync();
    final List<RegExpMatch> matches = pattern.allMatches(original).toList();
    if (matches.length != 1) {
      throw StateError('$path 에서 리전 값 자리를 하나로 찾지 못했습니다');
    }
    final RegExpMatch match = matches.single;
    writeFileAtomically(
      path,
      original.replaceRange(
        match.start,
        match.end,
        '${match.group(1)}$region${match.group(3)}',
      ),
    );
  }

  /// 세 곳의 리전 값을 읽는다 — 읽지 못하면 사유를, 읽으면 null 을 돌려준다.
  String? _readRegions(WizardContext context) {
    final String configPath = context.resolve(UserFilesStep.jsonUserPath);
    final String? config = readJsonString(
      configPath,
      functionsRegionKey,
    )?.trim();
    if (config == null || config.isEmpty) {
      return '${UserFilesStep.jsonUserPath} 에서 $functionsRegionKey 를 읽지 못했습니다';
    }
    final String? regionTs = _readRegionValue(
      context.resolve(regionTsPath),
      regionTsPattern,
    );
    if (regionTs == null) return '$regionTsPath 에서 REGION 값을 읽지 못했습니다';
    final String? appConfig = _readRegionValue(
      context.resolve(appConfigPath),
      appConfigRegionPattern,
    );
    if (appConfig == null) {
      return '$appConfigPath 에서 defaultFunctionsRegion 값을 읽지 못했습니다';
    }
    _regions = _RegionValues(
      config: config,
      regionTs: regionTs,
      appConfig: appConfig,
    );
    return null;
  }

  /// [path] 에서 [pattern] 이 정확히 한 곳에 맞으면 값 그룹을 돌려준다.
  static String? _readRegionValue(String path, RegExp pattern) {
    final File file = File(path);
    if (!file.existsSync()) return null;
    final List<RegExpMatch> matches = pattern
        .allMatches(file.readAsStringSync())
        .toList();
    return matches.length == 1 ? matches.single.group(2) : null;
  }

  /// 판정을 「읽지 못함」 으로 두고 할 일 결과를 만든다.
  CheckResult _markUnreadable(String reason) {
    _mode = _FirestoreMode.unreadable;
    _reason = reason;
    return Todo(reason);
  }

  /// 위치 안내 문구를 만든다.
  static String _describeLocation(String locationId) =>
      'Firestore 위치: $locationId (바꿀 수 없음)';
}

/// 세 곳의 Functions 리전 값.
final class _RegionValues {
  const _RegionValues({
    required this.config,
    required this.regionTs,
    required this.appConfig,
  });

  /// `config/dev.json` 의 값.
  final String config;

  /// `region.ts` 의 값.
  final String regionTs;

  /// `app_config.dart` 의 값.
  final String appConfig;

  /// 세 값이 모두 같으면 true.
  bool get isConsistent => config == regionTs && regionTs == appConfig;
}

/// 직전 검사의 판정.
enum _FirestoreMode {
  /// 데이터베이스가 없다 — 위치를 골라 만든다.
  create,

  /// 데이터베이스는 있고 리전 값이 서로 다르다 — Functions 리전만 맞춘다.
  alignRegion,

  /// 위치를 읽지 못했다.
  lookupFailed,

  /// 프로젝트 ID · 리전 값을 읽지 못했다.
  unreadable,

  /// 끝남.
  done,
}
