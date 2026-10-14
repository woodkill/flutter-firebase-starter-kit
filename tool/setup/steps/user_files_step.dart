import 'dart:io';

import '../config_files.dart';
import '../step.dart';
import '../wizard.dart';

/// 사용자 설정 파일 단계 — example 복사 · 킷 새 판의 빠진 키 채우기.
///
/// `config/dev.json` · `ios/Flutter/dev.xcconfig` 는 사용자 파일(gitignored)이다.
/// 없으면 example 을 그대로 복사하고, 있으면 example 에만 있는 키 · 변수를
/// example 값으로 더한다. 기존 값은 바꾸지 않고 값을 묻지도 않는다 — 위저드가
/// 아는 값은 그 값을 아는 뒤 단계가 쓴다.
final class UserFilesStep implements Step {
  /// 사용자 설정 파일 단계를 만든다.
  UserFilesStep();

  /// 앱 설정 JSON example (저장소에 추적).
  static const String jsonExamplePath = 'config/dev.example.json';

  /// 앱 설정 JSON 사용자 파일.
  static const String jsonUserPath = 'config/dev.json';

  /// iOS xcconfig example (저장소에 추적).
  static const String xcconfigExamplePath = 'ios/Flutter/dev.example.xcconfig';

  /// iOS xcconfig 사용자 파일.
  static const String xcconfigUserPath = 'ios/Flutter/dev.xcconfig';

  /// 사용자 JSON 을 읽지 못했을 때의 사유.
  static const String unreadableJsonReason = '$jsonUserPath 을 JSON 으로 읽지 못했습니다';

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
    final List<String> problems = <String>[
      if (_state.missingExamples.isNotEmpty)
        '킷 example 없음: ${_state.missingExamples.join(', ')}',
      if (_state.isJsonUnreadable) unreadableJsonReason,
      if (!_state.hasJsonUser) '$jsonUserPath 없음',
      if (!_state.hasXcconfigUser) '$xcconfigUserPath 없음',
      if (_state.missingJsonKeys.isNotEmpty)
        '$jsonUserPath 에 빠진 키: ${_state.missingJsonKeys.join(', ')}',
      if (_state.missingXcconfigVars.isNotEmpty)
        '$xcconfigUserPath 에 빠진 변수: ${_state.missingXcconfigVars.join(', ')}',
    ];
    if (problems.isEmpty) {
      return const Done(
        '$jsonUserPath · $xcconfigUserPath 에 example 의 키가 모두 있음',
      );
    }
    return Todo(problems.join(' · '));
  }

  @override
  List<String> plannedCommandLines(WizardContext context) {
    if (_state.missingExamples.isNotEmpty || _state.isJsonUnreadable) {
      return const <String>[];
    }
    return <String>[
      if (!_state.hasJsonUser) 'cp $jsonExamplePath $jsonUserPath',
      if (!_state.hasXcconfigUser) 'cp $xcconfigExamplePath $xcconfigUserPath',
      if (_state.missingJsonKeys.isNotEmpty)
        '($jsonUserPath 에 빠진 키 추가 (example 값): '
            '${_state.missingJsonKeys.join(', ')})',
      if (_state.missingXcconfigVars.isNotEmpty)
        '($xcconfigUserPath 에 빠진 변수 추가 (example 값): '
            '${_state.missingXcconfigVars.join(', ')})',
    ];
  }

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 실행 직전 상태로 다시 판단한다 — 사용자 파일은 덮어쓰지 않는다.
    final _UserFilesState state = _inspect(context);
    if (state.missingExamples.isNotEmpty) {
      return Failed(
        '킷 example 파일이 없습니다 (${state.missingExamples.join(', ')}) — '
        '저장소를 킷 최신 판과 맞춘 뒤 다시 실행하세요',
      );
    }
    if (state.isJsonUnreadable) {
      return const Failed(
        '$unreadableJsonReason — 위저드는 이 파일을 덮어쓰지 않습니다. '
        '파일을 손으로 고친 뒤 다시 실행하세요',
      );
    }
    try {
      if (!state.hasJsonUser) {
        File(
          context.resolve(jsonExamplePath),
        ).copySync(context.resolve(jsonUserPath));
      } else if (state.missingJsonKeys.isNotEmpty) {
        addMissingJsonKeys(
          examplePath: context.resolve(jsonExamplePath),
          userPath: context.resolve(jsonUserPath),
        );
      }
      if (!state.hasXcconfigUser) {
        File(
          context.resolve(xcconfigExamplePath),
        ).copySync(context.resolve(xcconfigUserPath));
      } else if (state.missingXcconfigVars.isNotEmpty) {
        addMissingXcconfigVars(
          examplePath: context.resolve(xcconfigExamplePath),
          userPath: context.resolve(xcconfigUserPath),
        );
      }
    } on FormatException catch (e) {
      return Failed('$jsonUserPath 에 키를 더하지 못했습니다 — 원본을 되돌렸습니다 ($e)');
    } on FileSystemException catch (e) {
      return Failed('사용자 설정 파일을 쓰지 못했습니다 — $e');
    }
    return const Applied();
  }

  /// 두 사용자 파일의 존재 · 빠진 키 · 변수를 읽기 전용으로 살핀다.
  _UserFilesState _inspect(WizardContext context) {
    final List<String> missingExamples = <String>[
      for (final String path in <String>[jsonExamplePath, xcconfigExamplePath])
        if (!File(context.resolve(path)).existsSync()) path,
    ];
    if (missingExamples.isNotEmpty) {
      return _UserFilesState(missingExamples: missingExamples);
    }
    final bool hasJsonUser = File(context.resolve(jsonUserPath)).existsSync();
    final bool hasXcconfigUser = File(
      context.resolve(xcconfigUserPath),
    ).existsSync();

    Set<String> missingJsonKeys = const <String>{};
    bool isJsonUnreadable = false;
    if (hasJsonUser) {
      try {
        missingJsonKeys = findMissingJsonKeys(
          examplePath: context.resolve(jsonExamplePath),
          userPath: context.resolve(jsonUserPath),
        );
      } on FormatException {
        isJsonUnreadable = true;
      }
    }
    final Set<String> missingXcconfigVars = hasXcconfigUser
        ? findMissingXcconfigVars(
            examplePath: context.resolve(xcconfigExamplePath),
            userPath: context.resolve(xcconfigUserPath),
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
