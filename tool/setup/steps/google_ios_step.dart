import 'dart:io';

import '../config_files.dart';
import '../firebase_app_files.dart';
import '../providers/key_formats.dart';
import '../providers/provider_catalog.dart';
import '../step.dart';
import '../wizard.dart';

/// Google 로그인의 iOS 쪽 단계 — iOS 설정 파일의 `REVERSED_CLIENT_ID` 를 사용자
/// xcconfig 의 같은 이름 변수에 쓴다.
///
/// 값은 Google 로그인을 켠 뒤 다시 받은 설정 파일에서만 읽는다 — 사용자에게 묻지
/// 않는다. 설정 파일에 값이 없거나 형식이 맞지 않으면 실행이 실패로 끝나고 매뉴얼
/// 절을 가리킨다. `Info.plist` 의 URL scheme 은 이 xcconfig 변수를 읽는다.
final class GoogleIosStep implements Step {
  /// Google iOS 쪽 단계를 만든다.
  GoogleIosStep();

  /// 단계 제목.
  static const String stepTitle = 'Google — iOS 쪽';

  /// 설정 파일 · xcconfig 의 변수 이름.
  static const String variableName = 'REVERSED_CLIENT_ID';

  _GoogleIosMode _mode = _GoogleIosMode.failed;
  String _reason = '';
  String _value = '';

  @override
  String get id => 'google_ios';

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['google', 'configure'];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? value = FirebaseAppFiles.read(
      context.projectRoot,
      flavor: context.flavor,
    ).iosReversedClientId;
    if (value == null) {
      return _mark(
        _GoogleIosMode.failed,
        '${context.paths.iosPlist} 에 $variableName 가 없습니다 — '
        '${formatManualReference(providersManualHeading)}',
      );
    }
    if (!reversedClientId.matches(value)) {
      return _mark(
        _GoogleIosMode.failed,
        '${context.paths.iosPlist} 의 $variableName 가 형식에 맞지 않습니다 '
        '(${reversedClientId.description}) — '
        '${formatManualReference(providersManualHeading)}',
      );
    }
    final String xcconfigPath = context.resolve(context.paths.xcconfig);
    if (!File(xcconfigPath).existsSync()) {
      return _mark(
        _GoogleIosMode.failed,
        '${context.paths.xcconfig} 이 없습니다 — 사용자 파일 단계를 먼저 끝내세요',
      );
    }
    _value = value;
    if (readXcconfigValue(xcconfigPath, variableName) == value) {
      _mode = _GoogleIosMode.done;
      return Done('${context.paths.xcconfig} 의 $variableName 가 설정 파일과 같음');
    }
    return _mark(
      _GoogleIosMode.write,
      '${context.paths.xcconfig} 의 $variableName 가 설정 파일과 다릅니다',
    );
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _GoogleIosMode.write => <String>[
      '(설정 파일의 $variableName 를 ${context.paths.xcconfig} 에 씁니다)',
    ],
    _GoogleIosMode.failed || _GoogleIosMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    switch (_mode) {
      case _GoogleIosMode.failed:
        return Failed(_reason);
      case _GoogleIosMode.done:
        return const Applied();
      case _GoogleIosMode.write:
        try {
          replaceXcconfigValue(
            context.resolve(context.paths.xcconfig),
            variableName,
            _value,
          );
          return const Applied();
        } on ConfigEditException catch (e) {
          return Failed('$variableName 를 쓰지 못했습니다 — ${e.message}');
        } on FileSystemException catch (e) {
          return Failed('$variableName 를 쓰지 못했습니다 — $e');
        }
    }
  }

  /// [mode] 판정과 사유를 두고 할 일 결과를 만든다.
  CheckResult _mark(_GoogleIosMode mode, String reason) {
    _mode = mode;
    _reason = reason;
    return Todo(reason);
  }
}

/// 직전 검사의 판정.
enum _GoogleIosMode {
  /// xcconfig 값이 설정 파일과 다르다 — 설정 파일 값을 쓴다.
  write,

  /// 설정 파일 값이 없거나 형식이 맞지 않다 — 실행하면 실패로 끝난다.
  failed,

  /// 끝남.
  done,
}
