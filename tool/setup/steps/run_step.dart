import 'dart:convert';
import 'dart:io';

import '../build_inputs.dart';
import '../command_runner.dart';
import '../flavor.dart';
import '../providers/provider_catalog.dart';
import '../rest_client.dart';
import '../step.dart';
import '../wizard.dart';
import 'billing_step.dart';

/// 앱 실행 · 로그인 확인 단계 — 위저드의 마지막 단계다.
///
/// 검사는 Identity Toolkit 의 사용자 목록(`accounts:batchGet`)을 끝 페이지까지
/// 읽어 이메일이 인증된 비밀번호 사용자 수를 센다. 끝 판정은 인증된 이메일
/// 사용자 수다 — 1명 이상이면 끝이다(앱이 떴는지가 아니라 사용자가 가입 · 인증까지
/// 마쳤는지로 판정한다). 다만 사용자가 1명 이상이어도 이번 실행에서 빌드가
/// 필요하면([findRebuildReasons] — 예: 같은 실행에서 App Check 디버그 토큰을
/// 등록함) 할 일로 두고 앱을 다시 빌드해 띄운다. 응답의 이메일 · uid · 표시 이름은
/// 화면 · 기록에 쓰지 않고 개수만 보인다.
///
/// 실행은 패키지 받기 → 코드 생성 → 실행 대상 고르기(iOS · Android 만 · 기본값은
/// iOS 시뮬레이터) → 할 일 안내 → 대화형 `flutter run` 이다. 사용자가 없으면 가입 ·
/// 이메일 인증 안내를, 다시 빌드면 새 빌드에서 확인할 것을 안내한다. 대상이 없으면
/// `xcrun simctl` 로 iPhone 시뮬레이터 하나를 켜고 Xcode 의 시뮬레이터 화면 앱을
/// 연 뒤 다시 찾는다. 실행이 끝나 돌아오면 위저드가 다시 검사한다.
final class RunStep implements Step {
  /// 앱 실행 · 로그인 확인 단계를 만든다.
  ///
  /// [delay] 는 iOS 시뮬레이터를 켠 뒤 기기 목록을 다시 보기 전에 기다리는
  /// 함수다(기본 = 실제로 기다림 · 테스트는 기다리지 않는 함수를 넣는다).
  RunStep({Future<void> Function(Duration duration)? delay})
    : _delay = delay ?? _waitFor;

  /// 단계 제목.
  static const String stepTitle = '앱 실행 · 로그인 확인';

  /// 사용자 목록 API 주소의 앞부분 — 뒤에 `<프로젝트 ID>/accounts:batchGet` 이 붙는다.
  static const String usersUrlPrefix =
      'https://identitytoolkit.googleapis.com/v1/projects/';

  /// 사용자 목록 한 페이지의 최대 사용자 수(API 상한).
  static const int pageSize = 1000;

  /// 사용자 목록을 끝까지 읽을 때의 최대 페이지 수 — 응답이 끝나지 않는 경우를 막는다.
  static const int maxPages = 1000;

  /// iOS 시뮬레이터를 켠 뒤 기기 목록을 다시 보는 간격.
  static const Duration launchPollInterval = Duration(seconds: 3);

  /// iOS 시뮬레이터를 켠 뒤 기기 목록을 다시 보는 최대 횟수.
  static const int maxLaunchPolls = 20;

  /// simctl 기기 목록에서 iOS 런타임 키의 앞부분 — 뒤에 `<주>-<부>` 판 번호가 붙는다.
  static const String iosRuntimeKeyPrefix =
      'com.apple.CoreSimulator.SimRuntime.iOS-';

  /// simctl 기기형 id 에서 iPhone 을 가리키는 부분.
  static const String iphoneDeviceTypeMarker = 'SimDeviceType.iPhone';

  /// 쓸 수 있는 시뮬레이터 목록을 JSON 으로 읽는 명령.
  static const Command simulatorListCommand = Command('xcrun', <String>[
    'simctl',
    'list',
    'devices',
    'available',
    '-j',
  ]);

  /// 선택된 Xcode 의 개발자 디렉터리(`<Xcode>.app/Contents/Developer`)를 읽는 명령.
  static const Command developerDirCommand = Command('xcode-select', <String>[
    '-p',
  ]);

  /// 실행 대상을 고르는 질문.
  static const String targetChoiceQuestion = '앱을 실행할 기기를 고르세요';

  /// 할 일 안내의 마지막 줄.
  static const String quitLine = '끝나면 이 터미널에서 q 를 눌러 실행을 끝냅니다 — 위저드가 가입을 확인합니다';

  /// 앱을 실행하기 전에 보이는 할 일 안내(마지막 줄은 [quitLine]).
  static const List<String> signUpGuideLines = <String>[
    '  앱에서 할 일 (화면 문구는 기기 언어가 한국어일 때의 문구 · 괄호 안은 영어):',
    '    1. 첫 안내 화면을 넘기고(「건너뛰기」 Skip) 약관에 동의한 뒤(「전체 동의」 Accept all) 「시작하기」(Get started)',
    '    2. 홈 오른쪽 위 「로그인」(Sign in) → 「계정이 없으신가요? 가입하기」(No account? Create one) → 이름 · 이메일 · 비밀번호를 넣고 「가입하기」(Create account)',
    '    3. 받은 메일의 인증 링크를 엽니다 — 메일이 보이지 않으면 스팸함을 확인하세요',
    "    4. 앱으로 돌아와 「인증 확인」(I've verified my email)",
    '  $quitLine',
  ];

  /// 앱 실행이 실패했을 때의 요약.
  static const String runFailedSummary = '앱 실행이 실패했습니다';

  /// 시뮬레이터를 띄운 뒤에도 실행 대상이 없을 때의 요약.
  static const String noTargetSummary =
      '실행할 iOS · Android 기기를 찾지 못했습니다 — iOS 시뮬레이터를 띄우지 못했거나 아직 '
      '켜지는 중입니다. 시뮬레이터가 켜진 뒤 다시 시도하세요';

  /// 켤 iPhone 시뮬레이터를 고르지 못했을 때의 요약.
  static const String noSimulatorSummary =
      '쓸 수 있는 iPhone 시뮬레이터가 없습니다 — 「Xcode 준비」 단계가 받는 iOS '
      '시뮬레이터 런타임이 있어야 합니다. 위저드를 다시 실행해 그 단계를 마치고, '
      '그래도 이 안내가 나오면 Xcode 에서 iPhone 시뮬레이터를 하나 만든 뒤 다시 '
      '시도하세요';

  /// 시뮬레이터 화면 앱을 찾지 못했을 때의 요약.
  static const String noScreenAppSummary =
      '시뮬레이터 화면 앱을 찾지 못했습니다 — Xcode 를 한 번 열어 iOS 시뮬레이터를 '
      '띄운 뒤 다시 시도하세요';

  /// 사용자가 없을 때의 할 일 사유.
  static const String noUserReason =
      '인증된 이메일 사용자가 없습니다 — 앱에서 가입 · 이메일 인증을 마쳐야 합니다';

  /// 다시 빌드해야 할 때의 할 일 사유 앞부분 — 뒤에 사유가 ` · ` 로 이어 붙는다.
  static const String rebuildReasonPrefix = '앱을 다시 빌드해야 합니다 — ';

  /// 이번 실행에서 App Check 디버그 토큰을 새로 만들거나 등록했을 때의 다시 빌드
  /// 사유.
  static const String appCheckTokenReason = '이번 실행에서 App Check 디버그 토큰을 등록했습니다';

  /// 다시 빌드 계획에서 앱을 띄우기 전 안내를 설명하는 괄호 줄.
  static const String rebuildPlanNote =
      '(앱을 띄우기 전에 새 빌드에서 확인할 것을 보여 줍니다 — 켠 로그인 수단의 버튼)';

  /// 다시 빌드 안내의 마지막 줄 — 사용자가 이미 있으므로 가입 확인을 말하지 않는다.
  static const String rebuildQuitLine = '끝나면 이 터미널에서 q 를 눌러 실행을 끝냅니다';

  /// 이번 실행에서 앱을 다시 빌드해 띄워야 하는 사유를 순서대로 모은다 — 없으면
  /// 빈 목록.
  ///
  /// 이번 실행에서 지금 빌드 입력 그대로 앱을 띄웠으면(`launchedBuildInputs` 가
  /// 지금 지문과 같으면) 사유가 없다 — 다시 빌드한 뒤의 재검사가 되풀이하지
  /// 않는다. 그 밖에는 App Check 디버그 토큰을 이번 실행에서 등록했으면
  /// [appCheckTokenReason] 이다.
  static List<String> findRebuildReasons(WizardContext context) {
    final WizardSession session = context.session;
    final Map<String, String?>? launched = session.launchedBuildInputs;
    if (launched != null &&
        _isSameDigests(launched, readBuildInputDigests(context))) {
      return const <String>[];
    }
    return <String>[
      if (session.hasRegisteredAppCheckToken) appCheckTokenReason,
    ];
  }

  /// 두 빌드 입력 지문 모음이 같은 경로 · 같은 값인지 본다.
  static bool _isSameDigests(
    Map<String, String?> left,
    Map<String, String?> right,
  ) {
    if (left.length != right.length) return false;
    for (final MapEntry<String, String?> entry in left.entries) {
      if (!right.containsKey(entry.key)) return false;
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// 다시 빌드한 앱을 띄우기 전에 보이는 안내를 만든다(마지막 줄은
  /// [rebuildQuitLine]).
  ///
  /// 켠 로그인 수단은 config 의 `enabledAuthProviders` 에서 읽는다. 켠 소셜 수단이
  /// 있을 때만 그 수단으로 한 번 로그인하라는 줄을 더한다.
  static List<String> buildRebuildGuideLines(WizardContext context) {
    final Set<String> enabled = readEnabledProviders(
      context.resolve(context.paths.json),
    );
    return <String>[
      '  앱을 새 빌드로 띄웁니다 — 로그인 화면에 켠 로그인 수단(${describeProviders(enabled)})의 버튼이 보이는지 확인합니다',
      if (enabled.isNotEmpty)
        '  켠 소셜 로그인 수단으로 아직 로그인하지 않았으면 그 수단으로 한 번 로그인합니다 — 다음 「소셜 로그인 확인」 단계가 수단마다 로그인 수를 셉니다',
      '  $rebuildQuitLine',
    ];
  }

  /// 패키지를 받는 명령을 만든다.
  static Command buildPubGetCommand({String? workingDirectory}) => Command(
    'fvm',
    const <String>['flutter', 'pub', 'get'],
    workingDirectory: workingDirectory,
  );

  /// 코드 생성 명령을 만든다.
  static Command buildCodegenCommand({String? workingDirectory}) =>
      Command('fvm', const <String>[
        'dart',
        'run',
        'build_runner',
        'build',
        '--delete-conflicting-outputs',
      ], workingDirectory: workingDirectory);

  /// 실행 대상 목록을 JSON 으로 읽는 명령을 만든다.
  static Command buildDevicesCommand({String? workingDirectory}) => Command(
    'fvm',
    const <String>['flutter', 'devices', '--machine'],
    workingDirectory: workingDirectory,
  );

  /// [udid] 시뮬레이터를 켜는 명령을 만든다.
  ///
  /// [udid] 는 simctl 목록의 값 그대로다 — 화면 · 기록의 명령 줄에서는 가림
  /// 패턴(UUID)이 가린다.
  static Command buildBootSimulatorCommand(
    String udid, {
    String? workingDirectory,
  }) => Command('xcrun', <String>[
    'simctl',
    'boot',
    udid,
  ], workingDirectory: workingDirectory);

  /// [appPath] 의 시뮬레이터 화면 앱을 여는 명령을 만든다(셸 없이 인자 배열).
  static Command buildOpenScreenAppCommand(
    String appPath, {
    String? workingDirectory,
  }) => Command('open', <String>[
    '-a',
    appPath,
  ], workingDirectory: workingDirectory);

  /// [deviceId] 기기에서 [flavor] 앱을 그 flavor 의 config 로 실행하는 명령을
  /// 만든다(기본 dev).
  static Command buildRunCommand(
    String deviceId, {
    String? workingDirectory,
    Flavor flavor = Flavor.dev,
  }) => Command('fvm', <String>[
    'flutter',
    'run',
    '--flavor',
    flavor.name,
    '--dart-define-from-file=${FlavorPaths(flavor).json}',
    '-d',
    deviceId,
  ], workingDirectory: workingDirectory);

  /// 앱을 띄우기 전 준비([prepareAppBuild])의 계획 줄을 만든다 — 패키지 받기 ·
  /// 코드 생성 순이다.
  static List<String> buildPrepareBuildPlanLines() => <String>[
    buildPubGetCommand().render(),
    buildCodegenCommand().render(),
  ];

  /// 앱을 띄우는 경로([launchAppForSignIn])의 계획 줄을 만든다 — 기기 목록 ·
  /// 시뮬레이터 켜기 · [guideNote] · `flutter run` 순이다.
  ///
  /// [guideNote] 는 앱을 띄우기 전에 보일 안내를 설명하는 괄호 줄이다.
  static List<String> buildLaunchPlanLines(
    WizardContext context, {
    required String guideNote,
  }) => <String>[
    buildDevicesCommand().render(),
    '(iOS · Android 기기만 보여 주고 고르게 합니다 — 기본값은 iOS 시뮬레이터입니다. 대상이 없으면 아래 명령으로 쓸 수 있는 iPhone 시뮬레이터 하나를 켜고 화면 앱을 연 뒤 다시 찾습니다 — 이미 켜진 iPhone 이 있으면 화면 앱만 엽니다)',
    simulatorListCommand.render(),
    developerDirCommand.render(),
    'xcrun simctl boot <고른 iPhone 시뮬레이터>',
    'open -a <Xcode 의 시뮬레이터 화면 앱>',
    guideNote,
    'fvm flutter run --flavor ${context.flavor.name} --dart-define-from-file=${context.paths.json} -d <고른 기기>',
  ];

  /// [projectId] 의 사용자 목록 한 페이지를 읽는 요청을 만든다.
  ///
  /// 응답에 이메일 · uid · 비밀번호 해시가 실리므로 민감 응답으로 둔다.
  /// [pageToken] 이 있으면 그 페이지부터 읽는다.
  static RestRequest buildBatchGetRequest(
    String projectId, {
    String? pageToken,
  }) {
    final url = StringBuffer()
      ..write('$usersUrlPrefix$projectId/accounts:batchGet')
      ..write('?maxResults=$pageSize');
    if (pageToken != null) {
      url.write('&nextPageToken=${Uri.encodeQueryComponent(pageToken)}');
    }
    return RestRequest(
      method: 'GET',
      url: Uri.parse(url.toString()),
      quotaProject: projectId,
      isResponseSensitive: true,
    );
  }

  /// 사용자 목록 응답의 사용자 하나가 인증된 이메일 · 비밀번호 사용자인지 본다.
  static bool isVerifiedPasswordUser(Object? user) {
    if (user is! Map<String, Object?>) return false;
    if (user['emailVerified'] != true) return false;
    final Object? providers = user['providerUserInfo'];
    if (providers is! List<Object?>) return false;
    return providers.any(
      (Object? provider) =>
          provider is Map<String, Object?> &&
          provider['providerId'] == 'password',
    );
  }

  /// 기기 목록 출력에서 iOS · Android 실행 대상을 꺼낸다 — 해석할 수 없으면 null.
  ///
  /// `targetPlatform` 이 `ios` 또는 `android` 로 시작하는 항목만 남기고, Flutter 가
  /// 이 프로젝트를 실행할 수 없다고 표시한 항목(`isSupported` 가 false)은 뺀다.
  /// 표준 출력 앞에 JSON 이 아닌 줄이 있으면 `[` 로 시작하는 첫 줄부터 읽는다.
  static List<RunTarget>? parseRunTargets(String stdout) {
    final List<String> lines = const LineSplitter().convert(stdout);
    final int start = lines.indexWhere(
      (String line) => line.trimLeft().startsWith('['),
    );
    if (start < 0) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(lines.sublist(start).join('\n'));
    } on FormatException {
      return null;
    }
    if (decoded is! List<Object?>) return null;
    final targets = <RunTarget>[];
    for (final Object? item in decoded) {
      if (item is! Map<String, Object?>) continue;
      final Object? name = item['name'];
      final Object? id = item['id'];
      final Object? platform = item['targetPlatform'];
      if (name is! String || id is! String || platform is! String) continue;
      if (!platform.startsWith('ios') && !platform.startsWith('android')) {
        continue;
      }
      if (item['isSupported'] == false) continue;
      targets.add(
        RunTarget(
          name: name,
          id: id,
          isIos: platform.startsWith('ios'),
          isEmulator: item['emulator'] == true,
        ),
      );
    }
    return targets;
  }

  /// 기본으로 고를 대상의 번호(0부터) — 첫 iOS 시뮬레이터, 없으면 첫 대상.
  static int findDefaultTargetIndex(List<RunTarget> targets) {
    final int simulator = targets.indexWhere(
      (RunTarget target) => target.isIos && target.isEmulator,
    );
    return simulator < 0 ? 0 : simulator;
  }

  /// simctl 기기 목록 출력에서 켤 iPhone 시뮬레이터를 고른다 — 후보가 없거나
  /// 해석할 수 없으면 null.
  ///
  /// 런타임 키가 [iosRuntimeKeyPrefix] 로 시작하는 iOS 런타임만 보고, 그 아래
  /// 쓸 수 있는(`isAvailable`) iPhone 만 후보로 둔다(iPad · watch 제외). 이미
  /// 켜졌거나 켜지는 중인 iPhone 이 있으면 그 기기를 고르고, 없으면 판 번호가
  /// 가장 높은 iOS 런타임의 첫 후보를 고른다 — JSON 키 순서는 판 순서가 아니므로
  /// 판 번호를 숫자로 비교한다.
  static SimulatorPick? pickSimulator(String stdout) {
    final Object? decoded;
    try {
      decoded = jsonDecode(stdout);
    } on FormatException {
      return null;
    }
    if (decoded case {'devices': final Map<String, Object?> runtimes}) {
      final iosRuntimes = <_IosRuntime>[
        for (final MapEntry<String, Object?> entry in runtimes.entries)
          if (_readIosRuntime(entry) case final _IosRuntime runtime) runtime,
      ]..sort(_compareNewestFirst);
      final candidates = <SimulatorPick>[
        for (final _IosRuntime runtime in iosRuntimes) ...runtime.iphones,
      ];
      for (final candidate in candidates) {
        if (candidate.isBooted) return candidate;
      }
      return candidates.isEmpty ? null : candidates.first;
    }
    return null;
  }

  /// `xcode-select -p` 출력(개발자 디렉터리)에서 시뮬레이터 화면 앱 경로를
  /// 찾는다 — 있는 디렉터리가 없으면 null.
  ///
  /// 경로는 출력에서 만든다 — `<Xcode>.app/Contents/Developer` 의 한 단계 위
  /// `Contents/Applications/DeviceHub.app`(최신 Xcode), 그다음 개발자 디렉터리
  /// 아래 `Applications/Simulator.app`(이전 Xcode) 순서로 처음 있는 디렉터리다.
  static String? findScreenAppPath(String developerDir) {
    String dir = developerDir.trim();
    while (dir.length > 1 && dir.endsWith('/')) {
      dir = dir.substring(0, dir.length - 1);
    }
    final int cut = dir.lastIndexOf('/');
    if (!dir.startsWith('/') || cut <= 0) return null;
    for (final candidate in <String>[
      '${dir.substring(0, cut)}/Applications/DeviceHub.app',
      '$dir/Applications/Simulator.app',
    ]) {
      if (Directory(candidate).existsSync()) return candidate;
    }
    return null;
  }

  /// simctl 목록의 런타임 하나가 iOS 런타임이면 판 번호와 iPhone 후보를 읽는다.
  static _IosRuntime? _readIosRuntime(MapEntry<String, Object?> entry) {
    if (!entry.key.startsWith(iosRuntimeKeyPrefix)) return null;
    final version = <int>[];
    for (final String part
        in entry.key.substring(iosRuntimeKeyPrefix.length).split('-')) {
      final int? number = int.tryParse(part);
      if (number == null) break;
      version.add(number);
    }
    final Object? devices = entry.value;
    if (version.isEmpty || devices is! List<Object?>) return null;
    return _IosRuntime(version, <SimulatorPick>[
      for (final Object? device in devices)
        if (_readIphone(device) case final SimulatorPick pick) pick,
    ]);
  }

  /// 판 번호가 높은 런타임이 앞에 오게 비교한다.
  static int _compareNewestFirst(_IosRuntime a, _IosRuntime b) {
    final int length = a.version.length > b.version.length
        ? a.version.length
        : b.version.length;
    for (var i = 0; i < length; i++) {
      final int left = i < a.version.length ? a.version[i] : 0;
      final int right = i < b.version.length ? b.version[i] : 0;
      if (left != right) return right.compareTo(left);
    }
    return 0;
  }

  /// simctl 기기 항목 하나가 쓸 수 있는 iPhone 이면 고른 기기로 만든다.
  static SimulatorPick? _readIphone(Object? device) {
    if (device is! Map<String, Object?>) return null;
    if (device['isAvailable'] != true) return null;
    final Object? type = device['deviceTypeIdentifier'];
    final Object? name = device['name'];
    final Object? udid = device['udid'];
    if (type is! String || !type.contains(iphoneDeviceTypeMarker)) return null;
    if (name is! String || udid is! String || udid.isEmpty) return null;
    final Object? state = device['state'];
    return SimulatorPick(
      name: name,
      udid: udid,
      isBooted: state == 'Booted' || state == 'Booting',
    );
  }

  final Future<void> Function(Duration duration) _delay;
  _RunMode _mode = _RunMode.unreadable;
  String _reason = '';
  String _projectId = '';
  CommandResult? _failedResult;

  @override
  String get id => 'run';

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>[
    'functions',
    'app_check',
    'sign_in',
    'rules',
    'configure',
  ];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      return _mark(
        _RunMode.unreadable,
        '${context.paths.json} 에서 프로젝트 ID 를 읽지 못했습니다',
      );
    }
    _projectId = projectId;
    final _UserCount count = await _countVerifiedUsers(context, projectId);
    switch (count) {
      case _UserCountFailed(:final String reason, :final CommandResult? result):
        return _mark(_RunMode.requestFailed, reason, result: result);
      case _UserCountOk(:final int verified) when verified > 0:
        final List<String> reasons = findRebuildReasons(context);
        if (reasons.isNotEmpty) {
          return _mark(
            _RunMode.rebuild,
            '$rebuildReasonPrefix${reasons.join(' · ')}',
          );
        }
        _mode = _RunMode.done;
        return Done('인증된 이메일 사용자 $verified명');
      case _UserCountOk():
        return _mark(_RunMode.run, noUserReason);
    }
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _RunMode.run => <String>[
      ...buildPrepareBuildPlanLines(),
      ...buildLaunchPlanLines(
        context,
        guideNote: '(앱을 띄우기 전에 앱에서 할 일을 보여 줍니다 — 가입 · 이메일 인증)',
      ),
      ..._buildRecountPlanLines(),
    ],
    _RunMode.rebuild => <String>[
      ...buildPrepareBuildPlanLines(),
      ...buildLaunchPlanLines(context, guideNote: rebuildPlanNote),
      ..._buildRecountPlanLines(),
    ],
    _RunMode.requestFailed => <String>['(응답 원문을 보입니다)'],
    _RunMode.unreadable || _RunMode.done => const <String>[],
  };

  /// 실행이 끝난 뒤 인증된 이메일 사용자를 다시 세는 계획 줄.
  List<String> _buildRecountPlanLines() => <String>[
    '(실행이 끝나면 아래 요청으로 인증된 이메일 사용자를 다시 셉니다 — 개수만 보입니다)',
    buildBatchGetRequest(_projectId).displayCurl(),
  ];

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    return switch (_mode) {
      _RunMode.run => await _runApp(context),
      _RunMode.rebuild => await _rebuildApp(context),
      _RunMode.requestFailed => Failed(_reason, result: _failedResult),
      _RunMode.unreadable => Failed(_reason),
      _RunMode.done => const Applied(),
    };
  }

  /// 패키지 받기 → 코드 생성 → 대상 고르기 → 할 일 안내 → 앱 실행.
  Future<StepOutcome> _runApp(WizardContext context) async {
    final Failed? prepared = await prepareAppBuild(context);
    if (prepared != null) return prepared;

    return await launchAppForSignIn(context, guideLines: signUpGuideLines);
  }

  /// 패키지 받기 → 코드 생성 → 대상 고르기 → 다시 빌드 안내 → 앱 실행.
  ///
  /// 사용자가 이미 있으므로 가입 안내 대신 새 빌드에서 확인할 것을 안내한다.
  Future<StepOutcome> _rebuildApp(WizardContext context) async {
    final Failed? prepared = await prepareAppBuild(context);
    if (prepared != null) return prepared;

    return await launchAppForSignIn(
      context,
      guideLines: buildRebuildGuideLines(context),
    );
  }

  /// 앱을 띄우기 전에 저장소 루트에서 패키지를 받고 코드를 생성한다.
  ///
  /// 실행 단계와 소셜 로그인 확인 단계가 [launchAppForSignIn] 앞에 함께 쓴다.
  /// 패키지 받기가 실패하면 코드 생성을 하지 않고 그 실패를, 코드 생성이
  /// 실패하면 그 실패를 출력 원문과 함께 돌려주고, 둘 다 성공하면 null 이다.
  Future<Failed?> prepareAppBuild(WizardContext context) async {
    final String root = context.projectRoot;
    final CommandResult pubGet = await context.runner.stream(
      buildPubGetCommand(workingDirectory: root),
    );
    if (!pubGet.isSuccess) {
      return Failed('패키지를 받지 못했습니다', result: pubGet);
    }
    final CommandResult codegen = await context.runner.stream(
      buildCodegenCommand(workingDirectory: root),
    );
    if (!codegen.isSuccess) {
      return Failed('코드 생성이 실패했습니다', result: codegen);
    }
    return null;
  }

  /// 실행 대상을 고르고 [guideLines] 를 보인 뒤 대화형 `flutter run` 으로 앱을
  /// 띄운다 — 패키지 받기 · 코드 생성은 하지 않는다(부르는 쪽이
  /// [prepareAppBuild] 를 먼저 부른다).
  ///
  /// 실행 단계와 소셜 로그인 확인 단계가 함께 쓴다. [guideLines] 는 한 줄씩
  /// 그대로 쓴다(들여쓰기는 넘기는 쪽 몫). 대상 목록을 읽지 못하거나 대상이
  /// 없으면 실패, 고르기 입력이 끝나면 [Declined], 실행 종료 코드가 0 이 아니면
  /// 실패, 아니면 [Applied] 다. 띄우기에 성공하면 지금 빌드 입력 지문을 세션에
  /// 남긴다 — 실행 단계의 재검사가 같은 빌드로 다시 빌드하지 않는다.
  Future<StepOutcome> launchAppForSignIn(
    WizardContext context, {
    required List<String> guideLines,
  }) async {
    final root = context.projectRoot;
    final _TargetLookup lookup = await _findTargets(context);
    final List<RunTarget> targets;
    switch (lookup) {
      case _TargetLookupFailed(:final StepOutcome outcome):
        return outcome;
      case _TargetLookupOk(targets: final List<RunTarget> found):
        targets = found;
    }

    final int? choice = context.terminal.choose(targetChoiceQuestion, <String>[
      for (final RunTarget target in targets) target.label,
    ], defaultIndex: findDefaultTargetIndex(targets));
    if (choice == null) return const Declined();
    final RunTarget target = targets[choice];

    for (final line in guideLines) {
      context.terminal.writeLine(line);
    }
    final int code = await context.runner.interactive(
      buildRunCommand(
        target.id,
        workingDirectory: root,
        flavor: context.flavor,
      ),
    );
    if (code != 0) {
      return Failed('$runFailedSummary (종료 코드 $code)');
    }
    context.session.launchedBuildInputs = readBuildInputDigests(context);
    return const Applied();
  }

  /// 실행 대상을 찾는다 — 없으면 iPhone 시뮬레이터를 켜고 기다리며 다시 찾는다.
  ///
  /// 켜진 시뮬레이터가 `flutter devices` 목록에 나타나기까지 시간이 걸리므로,
  /// 켠 뒤의 판정은 명령 종료 코드가 아니라 기기 목록 재조회로 한다.
  Future<_TargetLookup> _findTargets(WizardContext context) async {
    final _TargetLookup first = await _readTargets(context);
    if (first is! _TargetLookupOk || first.targets.isNotEmpty) return first;

    final Failed? startFailure = await _startSimulator(context);
    if (startFailure != null) return _TargetLookupFailed(startFailure);
    for (var poll = 0; poll < maxLaunchPolls; poll++) {
      await _delay(launchPollInterval);
      final _TargetLookup next = await _readTargets(context);
      if (next is! _TargetLookupOk || next.targets.isNotEmpty) return next;
    }
    return const _TargetLookupFailed(Failed(noTargetSummary));
  }

  /// iPhone 시뮬레이터 하나를 골라 켜고 화면 앱을 연다 — 실패하면 실패 결과.
  ///
  /// 목록 · 개발자 디렉터리 읽기는 capture, 상태를 바꾸는 켜기 · 열기는 stream
  /// 으로 실행한다. 이미 켜진 기기는 다시 켜지 않는다(켜진 기기에 boot 를 부르면
  /// 오류다). 화면 앱이 없으면 켜지 않는다 — 화면 없이 켜진 시뮬레이터로는 가입 ·
  /// 인증을 할 수 없다.
  Future<Failed?> _startSimulator(WizardContext context) async {
    final String root = context.projectRoot;
    final CommandResult list = await context.runner.capture(
      simulatorListCommand,
    );
    final SimulatorPick? pick = list.isSuccess
        ? pickSimulator(list.stdout)
        : null;
    if (pick == null) {
      return Failed(noSimulatorSummary, result: list.isSuccess ? null : list);
    }
    final CommandResult developerDir = await context.runner.capture(
      developerDirCommand,
    );
    final String? appPath = developerDir.isSuccess
        ? findScreenAppPath(developerDir.stdout)
        : null;
    if (appPath == null) {
      return Failed(
        noScreenAppSummary,
        result: developerDir.isSuccess ? null : developerDir,
      );
    }
    context.terminal.writeLine(
      pick.isBooted
          ? '  이미 켜진 iOS 시뮬레이터의 화면 앱을 엽니다 — ${pick.name}'
          : '  iOS 시뮬레이터를 켜고 화면 앱을 엽니다 — ${pick.name}',
    );
    if (!pick.isBooted) {
      final CommandResult boot = await context.runner.stream(
        buildBootSimulatorCommand(pick.udid, workingDirectory: root),
      );
      if (!boot.isSuccess) {
        return Failed('iOS 시뮬레이터를 켜지 못했습니다', result: boot);
      }
    }
    final CommandResult open = await context.runner.stream(
      buildOpenScreenAppCommand(appPath, workingDirectory: root),
    );
    if (!open.isSuccess) {
      return Failed('시뮬레이터 화면 앱을 열지 못했습니다', result: open);
    }
    return null;
  }

  /// 기기 목록을 한 번 읽어 실행 대상을 꺼낸다.
  Future<_TargetLookup> _readTargets(WizardContext context) async {
    final CommandResult result = await context.runner.capture(
      buildDevicesCommand(workingDirectory: context.projectRoot),
    );
    final List<RunTarget>? targets = result.isSuccess
        ? parseRunTargets(result.stdout)
        : null;
    if (targets == null) {
      return _TargetLookupFailed(Failed('실행 대상 목록을 읽지 못했습니다', result: result));
    }
    return _TargetLookupOk(targets);
  }

  /// 사용자 목록을 끝 페이지까지 읽어 인증된 이메일 · 비밀번호 사용자를 센다.
  ///
  /// 응답 본문은 메모리에서 개수만 세고 버린다.
  Future<_UserCount> _countVerifiedUsers(
    WizardContext context,
    String projectId,
  ) async {
    var verified = 0;
    String? pageToken;
    for (var page = 0; page < maxPages; page++) {
      final RestResponse response = await context.rest.send(
        buildBatchGetRequest(projectId, pageToken: pageToken),
      );
      if (!response.isOk) {
        return _UserCountFailed(
          '로그인 사용자 목록을 읽지 못했습니다 — ${describeRestStatus(response)}',
          // 실패 응답은 오류 설명뿐이라 원문을 보인다 — 사용자 목록이 아니다.
          toFailureResult(response),
        );
      }
      final Object? decoded = response.decodeJson();
      if (decoded is! Map<String, Object?>) {
        return const _UserCountFailed('로그인 사용자 목록 응답을 해석하지 못했습니다', null);
      }
      final Object? users = decoded['users'];
      if (users is List<Object?>) {
        verified += users.where(isVerifiedPasswordUser).length;
      }
      final Object? next = decoded['nextPageToken'];
      if (next is! String || next.isEmpty || next == pageToken) break;
      pageToken = next;
    }
    return _UserCountOk(verified);
  }

  /// [mode] 판정과 사유를 두고 할 일 결과를 만든다.
  CheckResult _mark(_RunMode mode, String reason, {CommandResult? result}) {
    _mode = mode;
    _reason = reason;
    _failedResult = result;
    return Todo(reason);
  }

  /// 실제로 [duration] 만큼 기다린다.
  static Future<void> _waitFor(Duration duration) =>
      Future<void>.delayed(duration);
}

/// 앱을 실행할 수 있는 기기 하나.
final class RunTarget {
  /// 기기 이름 · id · 플랫폼 · 에뮬레이터 여부로 대상을 만든다.
  const RunTarget({
    required this.name,
    required this.id,
    required this.isIos,
    required this.isEmulator,
  });

  /// 기기 이름.
  final String name;

  /// `flutter run -d` 에 넘기는 기기 id — 고르기 목록에는 보이지 않는다.
  final String id;

  /// iOS 기기 · 시뮬레이터면 true(아니면 Android).
  final bool isIos;

  /// 시뮬레이터 · 에뮬레이터면 true.
  final bool isEmulator;

  /// 고르기 목록에 보일 문구 — 이름과 종류만(id 는 보이지 않는다).
  String get label {
    final String kind = switch ((isIos, isEmulator)) {
      (true, true) => 'iOS 시뮬레이터',
      (true, false) => 'iOS 기기',
      (false, true) => 'Android 에뮬레이터',
      (false, false) => 'Android 기기',
    };
    return '$name ($kind)';
  }
}

/// simctl 목록에서 고른 iPhone 시뮬레이터 하나.
final class SimulatorPick {
  /// 기기 이름 · UDID · 켜짐 여부로 고른 기기를 만든다.
  const SimulatorPick({
    required this.name,
    required this.udid,
    required this.isBooted,
  });

  /// 기기 이름 — 화면 안내에 보이는 값.
  final String name;

  /// `simctl boot` 에 넘기는 UDID — 화면 안내에는 쓰지 않는다.
  final String udid;

  /// 이미 켜졌거나 켜지는 중이면 true — 다시 켜지 않고 화면 앱만 연다.
  final bool isBooted;
}

/// simctl 목록의 iOS 런타임 하나 — 판 번호와 그 아래 iPhone 후보.
final class _IosRuntime {
  const _IosRuntime(this.version, this.iphones);

  /// 런타임 키의 판 번호(`<주>-<부>` → [주, 부]).
  final List<int> version;

  /// 이 런타임 아래의 쓸 수 있는 iPhone(목록 순서).
  final List<SimulatorPick> iphones;
}

/// 직전 검사의 판정.
enum _RunMode {
  /// 인증된 사용자가 없다 — 앱을 실행한다.
  run,

  /// 인증된 사용자는 있지만 이번 실행에서 빌드가 필요하다 — 다시 빌드해 앱을
  /// 띄운다.
  rebuild,

  /// 사용자 목록을 읽지 못했다.
  requestFailed,

  /// 프로젝트 ID 를 읽지 못했다.
  unreadable,

  /// 끝남.
  done,
}

/// 사용자 수 세기 결과.
sealed class _UserCount {
  const _UserCount();
}

/// 센 결과.
final class _UserCountOk extends _UserCount {
  const _UserCountOk(this.verified);

  final int verified;
}

/// 읽지 못한 결과.
final class _UserCountFailed extends _UserCount {
  const _UserCountFailed(this.reason, this.result);

  final String reason;
  final CommandResult? result;
}

/// 실행 대상 찾기 결과.
sealed class _TargetLookup {
  const _TargetLookup();
}

/// 찾은 대상(비어 있을 수 있다).
final class _TargetLookupOk extends _TargetLookup {
  const _TargetLookupOk(this.targets);

  final List<RunTarget> targets;
}

/// 찾지 못해 단계를 끝낼 결과.
final class _TargetLookupFailed extends _TargetLookup {
  const _TargetLookupFailed(this.outcome);

  final StepOutcome outcome;
}
