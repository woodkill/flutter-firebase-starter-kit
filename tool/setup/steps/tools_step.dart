import '../command_runner.dart';
import '../step.dart';
import '../wizard.dart';

/// 개발 도구 단계 — 있으면 출처와 상관없이 그대로 쓰고, 없거나 낮으면 설치한다.
///
/// 검사는 PATH 의 명령을 읽기 전용으로 부른다. 최소 판을 넘으면 nvm · npm ·
/// 공식 설치 스크립트 등 어디서 왔든 그대로 쓴다. 없거나 낮은 도구만 Homebrew
/// 명령(FlutterFire CLI 는 `fvm dart pub global activate`)을 보이고 단계 확인 뒤
/// 하나씩 대화형으로 설치한다 — 진행률과 비밀번호 질문이 그대로 보인다. 관리자
/// 권한이 필요한 설치 경로는 쓰지 않는다.
final class ToolsStep implements Step {
  /// 개발 도구 단계를 만든다.
  ToolsStep();

  /// Node 최소 주 버전 — `functions/package.json` 의 `engines.node`.
  static const int minNodeMajor = 22;

  /// pnpm 최소 주 버전 — `functions/package.json` 의 `packageManager`.
  static const int minPnpmMajor = 10;

  /// Firebase CLI 최소 주 버전 — 위저드가 쓰는 옵션이 모두 있는 판.
  static const int minFirebaseMajor = 15;

  /// Homebrew ruby 를 설치한 뒤에도 PATH 의 ruby 가 시스템 ruby 일 때의 안내.
  static const String rubyPathGuidance =
      'PATH 에서 Homebrew 의 ruby 가 /usr/bin 보다 앞에 오게 셸 설정을 확인하세요';

  /// Homebrew 를 찾지 못했을 때의 안내.
  static const String homebrewMissingGuidance =
      'Homebrew 를 찾지 못했습니다 — 터미널 앱에서 저장소 루트의 ./setup.sh 로 '
      '실행하세요 (setup.sh 가 Homebrew 를 확인하고 설치 방법을 안내합니다)';

  static const Command _nodeVersion = Command('node', <String>['--version']);
  static const Command _pnpmVersion = Command('pnpm', <String>['--version']);
  static const Command _firebaseVersion = Command('firebase', <String>[
    '--version',
  ]);
  static const Command _gcloudVersion = Command('gcloud', <String>[
    '--version',
  ]);
  static const Command _jqVersion = Command('jq', <String>['--version']);

  /// `scripts/firebase-configure.sh` 의 전제 검사와 같은 술어.
  static const Command _xcodeprojCheck = Command('ruby', <String>[
    '-e',
    "require 'xcodeproj'",
  ]);
  static const Command _rubyPath = Command('ruby', <String>[
    '-e',
    'print RbConfig.ruby',
  ]);
  static const Command _brewPrefix = Command('brew', <String>['--prefix']);
  static const Command _pubGlobalList = Command('fvm', <String>[
    'dart',
    'pub',
    'global',
    'list',
  ]);

  static const Command _installNode = Command('brew', <String>[
    'install',
    'node',
  ]);
  static const Command _installPnpm = Command('brew', <String>[
    'install',
    'pnpm',
  ]);
  static const Command _installFirebase = Command('brew', <String>[
    'install',
    'firebase-cli',
  ]);
  static const Command _installGcloud = Command('brew', <String>[
    'install',
    '--cask',
    'gcloud-cli',
  ]);
  static const Command _installJq = Command('brew', <String>['install', 'jq']);
  static const Command _installRuby = Command('brew', <String>[
    'install',
    'ruby',
  ]);
  static const Command _installXcodeprojWithPathGem = Command('gem', <String>[
    'install',
    'xcodeproj',
  ]);
  static const Command _activateFlutterfire = Command('fvm', <String>[
    'dart',
    'pub',
    'global',
    'activate',
    'flutterfire_cli',
  ]);

  _ToolsState _state = const _ToolsState(<_ToolStatus>[]);

  /// 이 실행에서 Homebrew ruby 를 설치했으면 true — 재검사 사유를 고르는 데 쓴다.
  bool _hasInstalledHomebrewRuby = false;

  @override
  String get id => 'tools';

  @override
  String get title => '개발 도구';

  @override
  List<String> get dependsOn => const <String>['xcode'];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    _state = await _inspect(context);
    final List<String> problems = <String>[
      for (final _ToolStatus tool in _state.tools)
        if (tool.problem != null) tool.problem!,
    ];
    if (problems.isEmpty) {
      return Done(
        _state.tools.map((_ToolStatus tool) => tool.summary).join(' · '),
      );
    }
    return Todo(problems.join(' · '));
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => <String>[
    if (_state.needsHomebrew && _state.homebrewPrefix == null)
      '($homebrewMissingGuidance)',
    for (final Command command in _state.installCommands) command.render(),
  ];

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 결과(_state)를 그대로 쓴다.
    if (_state.needsHomebrew && _state.homebrewPrefix == null) {
      return const Failed(homebrewMissingGuidance);
    }
    for (final Command command in _state.installCommands) {
      final int code = await context.runner.interactive(command);
      if (code != 0) {
        return Failed(
          '${command.render()} 이 실패했습니다 (종료 코드 $code) — 위 출력을 확인하세요',
        );
      }
      if (identical(command, _installRuby)) _hasInstalledHomebrewRuby = true;
    }
    return const Applied();
  }

  /// 일곱 도구를 읽기 전용 명령으로 검사하고, 빠진 도구의 설치 명령을 정한다.
  Future<_ToolsState> _inspect(WizardContext context) async {
    final List<_ToolStatus> tools = <_ToolStatus>[
      await _inspectVersioned(
        context,
        name: 'Node',
        command: _nodeVersion,
        minMajor: minNodeMajor,
        install: _installNode,
      ),
      await _inspectVersioned(
        context,
        name: 'pnpm',
        command: _pnpmVersion,
        minMajor: minPnpmMajor,
        install: _installPnpm,
      ),
      await _inspectVersioned(
        context,
        name: 'Firebase CLI',
        command: _firebaseVersion,
        minMajor: minFirebaseMajor,
        install: _installFirebase,
      ),
      await _inspectVersioned(
        context,
        name: 'Google Cloud CLI',
        command: _gcloudVersion,
        install: _installGcloud,
      ),
      await _inspectVersioned(
        context,
        name: 'jq',
        command: _jqVersion,
        install: _installJq,
      ),
    ];

    final _ToolStatus xcodeproj = await _inspectXcodeproj(context);
    final _ToolStatus flutterfire = await _inspectFlutterfire(context);

    final bool needsHomebrew =
        tools.any((_ToolStatus tool) => tool.problem != null) ||
        xcodeproj.needsHomebrew;
    String? homebrewPrefix;
    if (needsHomebrew) {
      final CommandResult prefix = await context.runner.capture(_brewPrefix);
      final String trimmed = prefix.stdout.trim();
      if (prefix.isSuccess && trimmed.isNotEmpty) homebrewPrefix = trimmed;
    }

    return _ToolsState(
      <_ToolStatus>[
        ...tools,
        xcodeproj.withHomebrewPrefix(homebrewPrefix),
        flutterfire,
      ],
      needsHomebrew: needsHomebrew,
      homebrewPrefix: homebrewPrefix,
    );
  }

  /// `--version` 으로 판을 읽는 도구를 검사한다 — [minMajor] 가 null 이면 있으면 된다.
  Future<_ToolStatus> _inspectVersioned(
    WizardContext context, {
    required String name,
    required Command command,
    required Command install,
    int? minMajor,
  }) async {
    final CommandResult result = await context.runner.capture(command);
    if (!result.isSuccess) {
      return _ToolStatus(
        summary: name,
        problem: '$name 없음',
        installs: <Command>[install],
      );
    }
    final int? major =
        parseMajorVersion(result.stdout) ?? parseMajorVersion(result.stderr);
    final String summary = major == null ? name : '$name $major';
    if (minMajor == null) return _ToolStatus(summary: summary);
    if (major == null) {
      return _ToolStatus(
        summary: summary,
        problem: '$name 판을 읽지 못함 ($minMajor 이상 필요)',
        installs: <Command>[install],
      );
    }
    if (major < minMajor) {
      return _ToolStatus(
        summary: summary,
        problem: '$name $major ($minMajor 이상 필요)',
        installs: <Command>[install],
      );
    }
    return _ToolStatus(summary: summary);
  }

  /// ruby `xcodeproj` gem 을 검사하고, 없으면 관리자 권한 없는 설치 경로를 정한다.
  ///
  /// PATH 의 ruby 가 시스템 ruby 면 시스템 gem 경로에 쓰려면 관리자 권한이 필요하므로
  /// Homebrew ruby 를 설치하고 그 gem 으로 설치한다. 다른 ruby(Homebrew · rbenv 등)면
  /// PATH 의 gem 을 그대로 쓴다.
  Future<_ToolStatus> _inspectXcodeproj(WizardContext context) async {
    final CommandResult result = await context.runner.capture(_xcodeprojCheck);
    if (result.isSuccess) return const _ToolStatus(summary: 'xcodeproj');

    final CommandResult rubyPath = await context.runner.capture(_rubyPath);
    final bool isSystemRuby =
        !rubyPath.isSuccess || isSystemRubyPath(rubyPath.stdout.trim());
    if (!isSystemRuby) {
      return const _ToolStatus(
        summary: 'xcodeproj',
        problem: 'ruby xcodeproj 없음',
        installs: <Command>[_installXcodeprojWithPathGem],
      );
    }
    return _ToolStatus(
      summary: 'xcodeproj',
      problem: _hasInstalledHomebrewRuby
          ? 'ruby xcodeproj 없음 — $rubyPathGuidance'
          : 'ruby xcodeproj 없음',
      needsHomebrew: true,
    );
  }

  /// FlutterFire CLI 가 FVM Dart 의 전역 패키지로 있는지 검사한다.
  Future<_ToolStatus> _inspectFlutterfire(WizardContext context) async {
    final CommandResult result = await context.runner.capture(_pubGlobalList);
    final String? line = result.isSuccess
        ? result.stdout
              .split('\n')
              .map((String text) => text.trim())
              .where((String text) => text.startsWith('flutterfire_cli '))
              .firstOrNull
        : null;
    if (line == null) {
      return const _ToolStatus(
        summary: 'FlutterFire CLI',
        problem: 'FlutterFire CLI 없음',
        installs: <Command>[_activateFlutterfire],
      );
    }
    final int? major = parseMajorVersion(line);
    return _ToolStatus(
      summary: major == null ? 'FlutterFire CLI' : 'FlutterFire CLI $major',
    );
  }

  /// [text] 에서 첫 숫자 묶음을 찾아 주 버전으로 돌려준다 — 없으면 null.
  ///
  /// `v26.11.1` → 26 · `jq-1.7.1-apple` → 1 · `Google Cloud SDK 566.0.0` → 566.
  static int? parseMajorVersion(String text) {
    final RegExpMatch? match = RegExp(r'(\d+)(?:\.\d+)*').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  /// [rubyPath] 가 macOS 시스템 ruby 경로면 true.
  ///
  /// `/usr/bin/ruby` 의 `RbConfig.ruby` 는 `/System/Library/Frameworks/…` 를 가리킨다.
  static bool isSystemRubyPath(String rubyPath) =>
      rubyPath.isEmpty ||
      rubyPath.startsWith('/usr/bin/') ||
      rubyPath.startsWith('/System/');

  /// Homebrew ruby 의 gem 으로 xcodeproj 를 설치하는 명령을 만든다.
  static Command _buildHomebrewGemInstall(String? homebrewPrefix) {
    if (homebrewPrefix == null) {
      // Homebrew 가 없으면 실행하지 않는다 — 계획 줄 표시용.
      return const Command('gem', <String>[
        'install',
        'xcodeproj',
      ], display: r'$(brew --prefix)/bin/gem install xcodeproj');
    }
    return Command('$homebrewPrefix/bin/gem', const <String>[
      'install',
      'xcodeproj',
    ]);
  }
}

/// 도구 하나의 검사 결과.
final class _ToolStatus {
  const _ToolStatus({
    required this.summary,
    this.problem,
    this.installs = const <Command>[],
    this.needsHomebrew = false,
  });

  /// 점검표 요약 조각 — 도구 이름과 주 버전만.
  final String summary;

  /// 할 일 사유. null 이면 통과.
  final String? problem;

  /// 설치 명령(순서대로).
  final List<Command> installs;

  /// Homebrew 가 필요한 설치면 true.
  final bool needsHomebrew;

  /// Homebrew ruby 경로가 필요한 xcodeproj 설치 명령을 [homebrewPrefix] 로 채운다.
  _ToolStatus withHomebrewPrefix(String? homebrewPrefix) {
    if (problem == null || installs.isNotEmpty) return this;
    return _ToolStatus(
      summary: summary,
      problem: problem,
      installs: <Command>[
        ToolsStep._installRuby,
        ToolsStep._buildHomebrewGemInstall(homebrewPrefix),
      ],
      needsHomebrew: true,
    );
  }
}

/// 직전 검사에서 읽은 도구 상태.
final class _ToolsState {
  const _ToolsState(
    this.tools, {
    this.needsHomebrew = false,
    this.homebrewPrefix,
  });

  final List<_ToolStatus> tools;
  final bool needsHomebrew;
  final String? homebrewPrefix;

  /// 빠진 도구의 설치 명령(도구 순서대로).
  List<Command> get installCommands => <Command>[
    for (final _ToolStatus tool in tools) ...tool.installs,
  ];
}
