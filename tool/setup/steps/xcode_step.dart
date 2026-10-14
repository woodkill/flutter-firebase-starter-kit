import 'dart:convert';
import 'dart:io';

import '../command_runner.dart';
import '../step.dart';
import '../wizard.dart';

/// Xcode 준비 단계 — 선택 · 라이선스 · 첫 실행 준비 · iOS 시뮬레이터 런타임.
final class XcodeStep implements Step {
  /// [xcodeAppPath] 의 Xcode 를 기준으로 검사하는 단계를 만든다.
  XcodeStep({this.xcodeAppPath = '/Applications/Xcode.app'});

  /// 선택할 Xcode 앱 경로.
  final String xcodeAppPath;

  /// Xcode 를 내려받는 App Store 주소.
  static const String appStoreUrl =
      'https://apps.apple.com/app/xcode/id497799835';

  /// sudo 명령 앞에 보이는 비밀번호 안내.
  static const String sudoNotice =
      'sudo 가 비밀번호를 물으면 macOS 로그인 비밀번호를 입력하세요 — '
      '위저드는 비밀번호를 받거나 저장하지 않습니다.';

  /// 런타임 내려받기 명령 앞에 보이는 크기 안내.
  static const String runtimeDownloadNotice =
      '(iOS 시뮬레이터 런타임 — 내려받기 크기는 수 GB 이고 네트워크에 따라 오래 걸립니다)';

  _XcodeState _state = const _XcodeState.unknown();

  @override
  String get id => 'xcode';

  @override
  String get title => 'Xcode 준비';

  @override
  List<String> get dependsOn => const <String>[];

  @override
  bool get isCostlyOrIrreversible => false;

  /// Xcode 의 개발자 디렉터리 경로.
  String get _developerDir => '$xcodeAppPath/Contents/Developer';

  Command get _selectCommand =>
      Command('sudo', <String>['xcode-select', '-s', _developerDir]);

  static const Command _licenseCommand = Command('sudo', <String>[
    'xcodebuild',
    '-license',
    'accept',
  ]);

  static const Command _firstLaunchCommand = Command('sudo', <String>[
    'xcodebuild',
    '-runFirstLaunch',
  ]);

  static const Command _runtimeCommand = Command('xcodebuild', <String>[
    '-downloadPlatform',
    'iOS',
  ]);

  @override
  Future<CheckResult> check(WizardContext context) async {
    _state = await _inspect(context);
    if (_state.isMissing) {
      return const Todo('Xcode 가 설치돼 있지 않습니다');
    }
    final List<String> missing = <String>[
      if (!_state.isSelected) 'Xcode 선택 필요',
      if (!_state.isLicenseAccepted) '라이선스 동의 필요',
      if (!_state.isFirstLaunchDone) '첫 실행 준비 필요',
      if (!_state.hasIosRuntime) 'iOS 시뮬레이터 런타임 없음',
    ];
    if (missing.isEmpty) {
      return const Done('Xcode 선택 · 라이선스 동의 · 첫 실행 준비 · iOS 런타임 확인');
    }
    return Todo(missing.join(' · '));
  }

  @override
  List<String> plannedCommandLines(WizardContext context) {
    if (_state.isMissing) return const <String>[];
    return <String>[
      if (!_state.isSelected) _selectCommand.render(),
      if (!_state.isLicenseAccepted) _licenseCommand.render(),
      if (!_state.isFirstLaunchDone) _firstLaunchCommand.render(),
      if (!_state.hasIosRuntime) ...<String>[
        runtimeDownloadNotice,
        _runtimeCommand.render(),
      ],
    ];
  }

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 결과(_state)를 그대로 쓴다.
    if (_state.isMissing) {
      return const ExitForUser(
        'Xcode 가 설치돼 있지 않습니다. App Store 에서 Xcode 를 설치하세요:\n'
        '  $appStoreUrl\n'
        '설치가 끝나면 Xcode 를 한 번 열어 추가 구성 요소 설치를 마친 뒤 진행하세요.',
      );
    }
    final bool needsSudo =
        !_state.isSelected ||
        !_state.isLicenseAccepted ||
        !_state.isFirstLaunchDone;
    if (needsSudo) context.terminal.writeLine(sudoNotice);

    if (!_state.isSelected) {
      final int code = await context.runner.interactive(_selectCommand);
      if (code != 0) return Failed('Xcode 를 선택하지 못했습니다 (종료 코드 $code)');
      // 선택이 바뀌면 라이선스 · 첫 실행 · 런타임 판정이 달라질 수 있어 다시 검사한다.
      _state = await _inspect(context);
    }
    if (!_state.isLicenseAccepted) {
      final int code = await context.runner.interactive(_licenseCommand);
      if (code != 0) return Failed('라이선스에 동의하지 못했습니다 (종료 코드 $code)');
    }
    if (!_state.isFirstLaunchDone) {
      final int code = await context.runner.interactive(_firstLaunchCommand);
      if (code != 0) return Failed('첫 실행 준비를 마치지 못했습니다 (종료 코드 $code)');
    }
    if (!_state.hasIosRuntime) {
      final CommandResult result = await context.runner.stream(_runtimeCommand);
      if (!result.isSuccess) {
        return Failed('iOS 시뮬레이터 런타임을 내려받지 못했습니다', result: result);
      }
    }
    return const Applied();
  }

  /// 네 가지 상태를 읽기 전용 명령으로 검사한다.
  Future<_XcodeState> _inspect(WizardContext context) async {
    final CommandResult selected = await context.runner.capture(
      const Command('xcode-select', <String>['-p']),
    );
    final bool isSelected =
        selected.isSuccess &&
        selected.stdout.trim().endsWith('.app/Contents/Developer');
    if (!isSelected && !Directory(xcodeAppPath).existsSync()) {
      return const _XcodeState.missing();
    }
    if (!isSelected) {
      // Command Line Tools 가 선택된 상태에서는 나머지 검사가 의미 없다 —
      // 선택 뒤 다시 검사해 필요한 것만 실행한다.
      return const _XcodeState(
        isSelected: false,
        isLicenseAccepted: false,
        isFirstLaunchDone: false,
        hasIosRuntime: false,
      );
    }
    final CommandResult license = await context.runner.capture(
      const Command('xcodebuild', <String>['-license', 'check']),
    );
    final CommandResult firstLaunch = await context.runner.capture(
      const Command('xcodebuild', <String>['-checkFirstLaunchStatus']),
    );
    final CommandResult runtimes = await context.runner.capture(
      const Command('xcrun', <String>['simctl', 'list', 'runtimes', '-j']),
    );
    return _XcodeState(
      isSelected: true,
      isLicenseAccepted: license.isSuccess,
      isFirstLaunchDone: firstLaunch.isSuccess,
      hasIosRuntime: runtimes.isSuccess && _hasAvailableIosRuntime(runtimes),
    );
  }

  /// `simctl list runtimes -j` 출력에 쓸 수 있는 iOS 런타임이 있는지 본다.
  static bool _hasAvailableIosRuntime(CommandResult result) {
    final Object? decoded;
    try {
      decoded = jsonDecode(result.stdout);
    } on FormatException {
      return false;
    }
    if (decoded case {'runtimes': final List<Object?> runtimes}) {
      return runtimes.any(_isAvailableIosRuntime);
    }
    return false;
  }

  /// 런타임 항목 하나가 쓸 수 있는 iOS 런타임인지 본다.
  static bool _isAvailableIosRuntime(Object? runtime) {
    if (runtime is! Map<String, Object?>) return false;
    final Object? platform = runtime['platform'];
    final Object? identifier = runtime['identifier'];
    final bool isIos =
        platform == 'iOS' ||
        (identifier is String && identifier.contains('SimRuntime.iOS-'));
    return isIos && runtime['isAvailable'] == true;
  }
}

/// 직전 검사에서 읽은 Xcode 상태.
final class _XcodeState {
  const _XcodeState({
    required this.isSelected,
    required this.isLicenseAccepted,
    required this.isFirstLaunchDone,
    required this.hasIosRuntime,
  }) : isMissing = false;

  const _XcodeState.missing()
    : isMissing = true,
      isSelected = false,
      isLicenseAccepted = false,
      isFirstLaunchDone = false,
      hasIosRuntime = false;

  const _XcodeState.unknown()
    : isMissing = false,
      isSelected = false,
      isLicenseAccepted = false,
      isFirstLaunchDone = false,
      hasIosRuntime = false;

  final bool isMissing;
  final bool isSelected;
  final bool isLicenseAccepted;
  final bool isFirstLaunchDone;
  final bool hasIosRuntime;
}
