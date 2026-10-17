import 'dart:io';

import '../config_files.dart';
import '../flavor.dart';
import '../providers/provider_catalog.dart';
import '../providers/provider_selection.dart';
import '../step.dart';
import '../wizard.dart';

/// 사용자 설정 파일 단계 — example 복사 · 킷 새 판의 빠진 키 채우기.
///
/// 고른 flavor 의 `config/<flavor>.json` · `ios/Flutter/<flavor>.xcconfig` 는
/// 사용자 파일(gitignored)이다. 없으면 example 을 그대로 복사하고, 있으면
/// example 에만 있는 키 · 변수를 example 값으로 더한다. 기존 값은 바꾸지 않고
/// 값을 묻지도 않는다 — 위저드가 아는 값은 그 값을 아는 뒤 단계가 쓴다.
///
/// dev 가 아닌 flavor 의 config 를 이 실행에서 처음 만들면, dev config 에서 켠
/// 로그인 수단을 미리 체크한 체크 목록을 한 번 연다.
final class UserFilesStep implements Step {
  /// 사용자 설정 파일 단계를 만든다.
  UserFilesStep();

  /// dev 기본값 — 앱 설정 JSON example (저장소에 추적). 단계는
  /// `context.paths` 를 쓴다.
  static const String jsonExamplePath = 'config/dev.example.json';

  /// dev 기본값 — 앱 설정 JSON 사용자 파일.
  static const String jsonUserPath = 'config/dev.json';

  /// dev 기본값 — iOS xcconfig example (저장소에 추적).
  static const String xcconfigExamplePath = 'ios/Flutter/dev.example.xcconfig';

  /// dev 기본값 — iOS xcconfig 사용자 파일.
  static const String xcconfigUserPath = 'ios/Flutter/dev.xcconfig';

  /// 새 flavor 의 체크 목록 앞에 보이는 안내 한 줄.
  static const String newFlavorProvidersNotice =
      'dev 에서 켠 로그인 수단을 미리 골라 두었습니다 — 키는 복사하지 않습니다'
      '(flavor 마다 새 콘솔 앱).';

  /// [jsonPath] 사용자 JSON 을 읽지 못했을 때의 사유를 만든다.
  static String describeUnreadableJson(String jsonPath) =>
      '$jsonPath 을 JSON 으로 읽지 못했습니다';

  _UserFilesState _state = const _UserFilesState();

  @override
  String get id => 'user_files';

  @override
  String get title => '사용자 설정 파일';

  @override
  List<String> get dependsOn => const <String>[];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    _state = _inspect(context);
    final FlavorPaths paths = context.paths;
    final List<String> problems = <String>[
      if (_state.missingExamples.isNotEmpty)
        '킷 example 없음: ${_state.missingExamples.join(', ')}',
      if (_state.isJsonUnreadable) describeUnreadableJson(paths.json),
      if (!_state.hasJsonUser) '${paths.json} 없음',
      if (!_state.hasXcconfigUser) '${paths.xcconfig} 없음',
      if (_state.missingJsonKeys.isNotEmpty)
        '${paths.json} 에 빠진 키: ${_state.missingJsonKeys.join(', ')}',
      if (_state.missingXcconfigVars.isNotEmpty)
        '${paths.xcconfig} 에 빠진 변수: '
            '${_state.missingXcconfigVars.join(', ')}',
    ];
    if (problems.isEmpty) {
      return Done('${paths.json} · ${paths.xcconfig} 에 example 의 키가 모두 있음');
    }
    return Todo(problems.join(' · '));
  }

  @override
  List<String> plannedCommandLines(WizardContext context) {
    if (_state.missingExamples.isNotEmpty || _state.isJsonUnreadable) {
      return const <String>[];
    }
    final FlavorPaths paths = context.paths;
    return <String>[
      if (!_state.hasJsonUser) 'cp ${paths.jsonExample} ${paths.json}',
      if (!_state.hasXcconfigUser)
        'cp ${paths.xcconfigExample} ${paths.xcconfig}',
      if (_state.missingJsonKeys.isNotEmpty)
        '(${paths.json} 에 빠진 키 추가 (example 값): '
            '${_state.missingJsonKeys.join(', ')})',
      if (_state.missingXcconfigVars.isNotEmpty)
        '(${paths.xcconfig} 에 빠진 변수 추가 (example 값): '
            '${_state.missingXcconfigVars.join(', ')})',
    ];
  }

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 실행 직전 상태로 다시 판단한다 — 사용자 파일은 덮어쓰지 않는다.
    final _UserFilesState state = _inspect(context);
    final FlavorPaths paths = context.paths;
    if (state.missingExamples.isNotEmpty) {
      return Failed(
        '킷 example 파일이 없습니다 (${state.missingExamples.join(', ')}) — '
        '저장소를 킷 최신 판과 맞춘 뒤 다시 실행하세요',
      );
    }
    if (state.isJsonUnreadable) {
      return Failed(
        '${describeUnreadableJson(paths.json)} — 위저드는 이 파일을 덮어쓰지 '
        '않습니다. 파일을 손으로 고친 뒤 다시 실행하세요',
      );
    }
    try {
      if (!state.hasJsonUser) {
        File(
          context.resolve(paths.jsonExample),
        ).copySync(context.resolve(paths.json));
      } else if (state.missingJsonKeys.isNotEmpty) {
        addMissingJsonKeys(
          examplePath: context.resolve(paths.jsonExample),
          userPath: context.resolve(paths.json),
        );
      }
      if (!state.hasXcconfigUser) {
        File(
          context.resolve(paths.xcconfigExample),
        ).copySync(context.resolve(paths.xcconfig));
      } else if (state.missingXcconfigVars.isNotEmpty) {
        addMissingXcconfigVars(
          examplePath: context.resolve(paths.xcconfigExample),
          userPath: context.resolve(paths.xcconfig),
        );
      }
    } on FormatException catch (e) {
      return Failed('${paths.json} 에 키를 더하지 못했습니다 — 원본을 되돌렸습니다 ($e)');
    } on FileSystemException catch (e) {
      return Failed('사용자 설정 파일을 쓰지 못했습니다 — $e');
    }
    // 처음 만든 새 flavor config 에만 dev 의 로그인 수단을 제안한다 — 두 사용자
    // 파일을 다 쓴 뒤라 여기서 멈춰도 파일은 남는다.
    if (!state.hasJsonUser && context.flavor != Flavor.dev) {
      return _proposeDevProviders(context);
    }
    return const Applied();
  }

  /// dev config 에서 켠 로그인 수단을 미리 체크한 체크 목록을 열고 고른 값을
  /// 새 flavor config 에 쓴다.
  ///
  /// dev config 가 없거나 켠 수단이 없으면 묻지 않는다. 입력이 끝나면 example
  /// 값(이메일만)을 그대로 두고, 고른 수단이 있으면 단계 목록을 다시 짠다.
  StepOutcome _proposeDevProviders(WizardContext context) {
    final Set<String> devTokens = readEnabledProviders(
      context.resolve(const FlavorPaths(Flavor.dev).json),
    );
    if (devTokens.isEmpty) return const Applied();
    context.terminal.writeLine(newFlavorProvidersNotice);
    final Set<String>? chosen = chooseProviders(
      context.terminal,
      current: devTokens,
    );
    if (chosen == null) return const Applied();
    final String jsonPath = context.paths.json;
    try {
      writeEnabledProviders(context.resolve(jsonPath), chosen);
    } on FileSystemException catch (e) {
      return Failed('$jsonPath 에 로그인 수단을 쓰지 못했습니다 — ${e.message}');
    } on FormatException catch (e) {
      return Failed('$jsonPath 에 로그인 수단을 쓰지 못했습니다 — ${e.message}');
    } on StateError catch (e) {
      return Failed('$jsonPath 에 로그인 수단을 쓰지 못했습니다 — ${e.message}');
    }
    return chosen.isEmpty ? const Applied() : const Replan();
  }

  /// 두 사용자 파일의 존재 · 빠진 키 · 변수를 읽기 전용으로 살핀다.
  _UserFilesState _inspect(WizardContext context) {
    final FlavorPaths paths = context.paths;
    final List<String> missingExamples = <String>[
      for (final String path in <String>[
        paths.jsonExample,
        paths.xcconfigExample,
      ])
        if (!File(context.resolve(path)).existsSync()) path,
    ];
    if (missingExamples.isNotEmpty) {
      return _UserFilesState(missingExamples: missingExamples);
    }
    final bool hasJsonUser = File(context.resolve(paths.json)).existsSync();
    final bool hasXcconfigUser = File(
      context.resolve(paths.xcconfig),
    ).existsSync();

    Set<String> missingJsonKeys = const <String>{};
    bool isJsonUnreadable = false;
    if (hasJsonUser) {
      try {
        missingJsonKeys = findMissingJsonKeys(
          examplePath: context.resolve(paths.jsonExample),
          userPath: context.resolve(paths.json),
        );
      } on FormatException {
        isJsonUnreadable = true;
      }
    }
    final Set<String> missingXcconfigVars = hasXcconfigUser
        ? findMissingXcconfigVars(
            examplePath: context.resolve(paths.xcconfigExample),
            userPath: context.resolve(paths.xcconfig),
          )
        : const <String>{};

    return _UserFilesState(
      hasJsonUser: hasJsonUser,
      hasXcconfigUser: hasXcconfigUser,
      isJsonUnreadable: isJsonUnreadable,
      missingJsonKeys: missingJsonKeys.toList(),
      missingXcconfigVars: missingXcconfigVars.toList(),
    );
  }
}

/// 직전 검사에서 읽은 사용자 파일 상태.
final class _UserFilesState {
  const _UserFilesState({
    this.missingExamples = const <String>[],
    this.hasJsonUser = true,
    this.hasXcconfigUser = true,
    this.isJsonUnreadable = false,
    this.missingJsonKeys = const <String>[],
    this.missingXcconfigVars = const <String>[],
  });

  final List<String> missingExamples;
  final bool hasJsonUser;
  final bool hasXcconfigUser;
  final bool isJsonUnreadable;
  final List<String> missingJsonKeys;
  final List<String> missingXcconfigVars;
}
