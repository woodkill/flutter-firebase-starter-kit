import 'dart:convert';
import 'dart:io';

import '../command_runner.dart';
import '../config_files.dart';
import '../firebase_app_files.dart';
import '../rest_client.dart';
import '../step.dart';
import '../uuid.dart';
import '../wizard.dart';
import 'billing_step.dart';
import 'user_files_step.dart';

/// App Check 디버그 토큰 단계 — debug 빌드가 쓸 토큰을 만들어 config 에 두고 dev
/// 의 iOS · Android 앱에 등록한다.
///
/// 토큰은 위저드가 `context.random`(실행 때는 `Random.secure()`)으로 만든 UUID4 다.
/// `config/dev.json` 의 [tokenKey] 에 쓰고, 같은 값을 두 앱 모두에 App Check REST
/// 로 등록한다(표시 이름 = [displayName]). 다음 빌드가 `--dart-define-from-file`
/// 로 이 값을 앱에 넣는다. 재검사는 두 앱의 디버그 토큰 목록에 [displayName]
/// 항목이 있는지다 — 목록 응답은 토큰 값을 주지 않는다. 토큰을 새로 만들 때는
/// 같은 표시 이름의 옛 항목을 먼저 지운다(앱마다 20개 한도).
///
/// 토큰과 앱 ID 는 가림 함수에 등록해 화면 · 기록에 나가지 않는다. 화면의 요청
/// 표시형에는 토큰 대신 [tokenDisplay] 를 보인다.
final class AppCheckStep implements Step {
  /// App Check 디버그 토큰 단계를 만든다.
  AppCheckStep();

  /// 단계 제목.
  static const String stepTitle = 'App Check 디버그 토큰';

  /// 위저드가 등록하는 디버그 토큰의 고정 표시 이름 — 재검사 술어다.
  static const String displayName = 'setup-wizard-dev';

  /// 토큰을 두는 config 키.
  static const String tokenKey = 'appCheckDebugToken';

  /// 화면 · 기록의 요청 본문에서 토큰 자리에 보이는 표시형.
  static const String tokenDisplay = '<config/dev.json 의 appCheckDebugToken>';

  /// App Check API 주소의 앞부분 — 뒤에 자원 이름이 붙는다.
  static const String appCheckApiPrefix =
      'https://firebaseappcheck.googleapis.com/v1/';

  /// 적용을 마친 뒤 보이는 안내.
  static const String rebuildNotice = '앱을 다시 빌드해야 새 토큰이 들어갑니다 — 마지막 단계가 빌드합니다.';

  /// [projectId] 의 [appId] 앱 디버그 토큰 목록 주소.
  static Uri buildTokensUrl(String projectId, String appId) => Uri.parse(
    '${appCheckApiPrefix}projects/$projectId/apps/$appId/debugTokens',
  );

  /// [appId] 앱의 디버그 토큰 목록을 읽는 요청을 만든다.
  static RestRequest buildListRequest(String projectId, String appId) =>
      RestRequest(
        method: 'GET',
        url: buildTokensUrl(projectId, appId),
        quotaProject: projectId,
      );

  /// [appId] 앱에 [token] 을 [displayName] 으로 등록하는 요청을 만든다.
  ///
  /// 화면 · 기록에는 토큰 대신 [tokenDisplay] 가 든 본문을 보인다.
  static RestRequest buildCreateRequest(
    String projectId,
    String appId,
    String token,
  ) => RestRequest(
    method: 'POST',
    url: buildTokensUrl(projectId, appId),
    quotaProject: projectId,
    body: jsonEncode(<String, String>{
      'displayName': displayName,
      'token': token,
    }),
    bodyDisplay: jsonEncode(<String, String>{
      'displayName': displayName,
      'token': tokenDisplay,
    }),
  );

  /// 디버그 토큰 항목 [name](`projects/<p>/apps/<앱>/debugTokens/<id>`)을 지우는
  /// 요청을 만든다.
  static RestRequest buildDeleteRequest(String projectId, String name) =>
      RestRequest(
        method: 'DELETE',
        url: Uri.parse('$appCheckApiPrefix$name'),
        quotaProject: projectId,
      );

  _AppCheckMode _mode = _AppCheckMode.unreadable;
  String _reason = '';
  String _projectId = '';
  String _token = '';
  List<_App> _apps = const <_App>[];
  List<_App> _missingApps = const <_App>[];
  CommandResult? _failedResult;

  @override
  String get id => 'app_check';

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['configure', 'apis'];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      return _mark(
        _AppCheckMode.unreadable,
        '${UserFilesStep.jsonUserPath} 에서 프로젝트 ID 를 읽지 못했습니다',
      );
    }
    _projectId = projectId;
    final List<_App>? apps = _readApps(context);
    if (apps == null) {
      return _mark(
        _AppCheckMode.unreadable,
        '앱 등록 설정 파일에서 iOS · Android 앱 ID 를 읽지 못했습니다 — '
        '앱 등록 단계를 먼저 끝내야 합니다',
      );
    }
    _apps = apps;

    final String token =
        readJsonString(context.resolve(UserFilesStep.jsonUserPath), tokenKey) ??
        '';
    if (!isUuidV4(token)) {
      _token = '';
      return _mark(
        _AppCheckMode.create,
        '${UserFilesStep.jsonUserPath} 에 디버그 토큰이 없습니다 — '
        '새로 만들어 iOS · Android 앱에 등록합니다',
      );
    }
    context.redactor.register(token);
    _token = token;

    final missing = <_App>[];
    for (final _App app in apps) {
      final RestResponse response = await context.rest.send(
        buildListRequest(projectId, app.appId),
      );
      final List<String>? names = _parseWizardTokenNames(response);
      if (names == null) {
        return _mark(
          _AppCheckMode.requestFailed,
          '${app.label} 앱의 디버그 토큰 목록을 읽지 못했습니다 — '
          '${describeRestStatus(response)}',
          result: toFailureResult(response, redactor: context.redactor),
        );
      }
      if (names.isEmpty) missing.add(app);
    }
    if (missing.isNotEmpty) {
      _missingApps = missing;
      return _mark(
        _AppCheckMode.register,
        '디버그 토큰이 등록되지 않은 앱: '
        '${missing.map((_App app) => app.label).join(' · ')}',
      );
    }
    _mode = _AppCheckMode.done;
    return const Done('iOS · Android 앱에 디버그 토큰 등록됨 ($displayName)');
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _AppCheckMode.create => <String>[
      '(UUID4 디버그 토큰을 위저드 안에서 만들고, 두 앱의 옛 항목을 지운 뒤 ${UserFilesStep.jsonUserPath} 의 $tokenKey 에 씁니다 — 외부 명령을 부르지 않습니다)',
      for (final _App app in _apps) ...<String>[
        '(${app.label} 앱: 목록에서 표시 이름 $displayName 인 옛 항목을 지운 뒤 새 토큰을 등록합니다)',
        buildListRequest(_projectId, app.appId).displayCurl(),
        buildCreateRequest(_projectId, app.appId, '').displayCurl(),
      ],
    ],
    _AppCheckMode.register => <String>[
      for (final _App app in _missingApps) ...<String>[
        '(${app.label} 앱에 config 의 토큰을 등록합니다)',
        buildCreateRequest(_projectId, app.appId, '').displayCurl(),
      ],
    ],
    _AppCheckMode.requestFailed => <String>['(응답 원문을 보입니다)'],
    _AppCheckMode.unreadable || _AppCheckMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    final StepOutcome outcome;
    try {
      outcome = switch (_mode) {
        _AppCheckMode.create => await _applyCreate(context),
        _AppCheckMode.register => await _registerAll(
          context,
          _missingApps,
          _token,
        ),
        _AppCheckMode.requestFailed => Failed(_reason, result: _failedResult),
        _AppCheckMode.unreadable => Failed(_reason),
        _AppCheckMode.done => const Applied(),
      };
    } on FileSystemException catch (e) {
      return Failed('${UserFilesStep.jsonUserPath} 에 토큰을 쓰지 못했습니다 — $e');
    } on FormatException catch (e) {
      return Failed('${UserFilesStep.jsonUserPath} 에 토큰을 쓰지 못했습니다 — $e');
    } on ConfigEditException catch (e) {
      return Failed(
        '${UserFilesStep.jsonUserPath} 에 토큰을 쓰지 못했습니다 — ${e.message}',
      );
    }
    if (outcome is Applied && _mode != _AppCheckMode.done) {
      context.terminal.writeLine('  $rebuildNotice');
    }
    return outcome;
  }

  /// 새 토큰을 만들고 두 앱의 옛 항목을 지운 뒤 config 에 써서 등록한다.
  ///
  /// config 쓰기는 옛 항목을 모두 지운 **뒤**다. 목록 응답은 토큰 값을 주지
  /// 않으므로, 먼저 쓰면 삭제 중 실패 뒤 재검사가 「config 토큰 UUID4 + 옛
  /// 항목 있음」 을 ✓ 로 오판한다. 지금 순서면 삭제 중 실패 → config 는 여전히
  /// 무효 → `create`, 등록 중 실패 → 목록에 항목 없음 → `register` 로 다시 간다.
  Future<StepOutcome> _applyCreate(WizardContext context) async {
    final String token = generateUuidV4(context.random);
    context.redactor.register(token);
    for (final _App app in _apps) {
      final RestResponse list = await context.rest.send(
        buildListRequest(_projectId, app.appId),
      );
      final List<String>? names = _parseWizardTokenNames(list);
      if (names == null) {
        return Failed(
          '${app.label} 앱의 디버그 토큰 목록을 읽지 못했습니다 — ${describeRestStatus(list)}',
          result: toFailureResult(list, redactor: context.redactor),
        );
      }
      for (final String name in names) {
        final RestResponse deleted = await context.rest.send(
          buildDeleteRequest(_projectId, name),
        );
        if (!deleted.isOk) {
          return Failed(
            '${app.label} 앱의 옛 디버그 토큰을 지우지 못했습니다 — '
            '${describeRestStatus(deleted)}',
            result: toFailureResult(deleted, redactor: context.redactor),
          );
        }
      }
    }
    replaceJsonString(
      context.resolve(UserFilesStep.jsonUserPath),
      tokenKey,
      token,
    );
    _token = token;
    return await _registerAll(context, _apps, token);
  }

  /// [apps] 에 [token] 을 등록한다.
  Future<StepOutcome> _registerAll(
    WizardContext context,
    List<_App> apps,
    String token,
  ) async {
    for (final app in apps) {
      final RestResponse response = await context.rest.send(
        buildCreateRequest(_projectId, app.appId, token),
      );
      if (!response.isOk) {
        return Failed(
          '${app.label} 앱에 디버그 토큰을 등록하지 못했습니다 — '
          '${describeRestStatus(response)}',
          result: toFailureResult(response, redactor: context.redactor),
        );
      }
    }
    return const Applied();
  }

  /// 앱 등록 설정 파일에서 iOS · Android 앱 ID 를 읽고 가림 함수에 등록한다.
  ///
  /// 하나라도 읽지 못하면 null.
  static List<_App>? _readApps(WizardContext context) {
    final String? packageName = readDevAndroidPackage(context.projectRoot);
    if (packageName == null) return null;
    final files = FirebaseAppFiles.read(context.projectRoot);
    if (files.isOptionsPlaceholder) return null;
    final String? iosAppId = files.iosAppId;
    final String? androidAppId = files.androidAppIdFor(packageName);
    if (iosAppId == null || androidAppId == null) return null;
    context.redactor
      ..register(iosAppId)
      ..register(androidAppId);
    return <_App>[_App('iOS', iosAppId), _App('Android', androidAppId)];
  }

  /// 목록 응답에서 [displayName] 항목의 자원 이름을 모은다 — 실패 · 모양이 다르면
  /// null.
  static List<String>? _parseWizardTokenNames(RestResponse response) {
    if (!response.isOk) return null;
    final Object? decoded = response.decodeJson();
    if (decoded is! Map<String, Object?>) return null;
    // 항목이 없으면 응답에 debugTokens 키가 빠진다.
    final Object tokens = decoded['debugTokens'] ?? const <Object?>[];
    if (tokens is! List<Object?>) return null;
    return <String>[
      for (final Object? item in tokens)
        if (item is Map<String, Object?> &&
            item['displayName'] == displayName &&
            item['name'] is String)
          item['name']! as String,
    ];
  }

  /// [mode] 판정과 사유를 두고 할 일 결과를 만든다.
  CheckResult _mark(
    _AppCheckMode mode,
    String reason, {
    CommandResult? result,
  }) {
    _mode = mode;
    _reason = reason;
    _failedResult = result;
    return Todo(reason);
  }
}

/// 토큰을 등록할 앱 하나.
final class _App {
  const _App(this.label, this.appId);

  /// 화면에 보일 플랫폼 이름.
  final String label;

  /// Firebase 앱 ID — 화면 · 기록에 쓰지 않는다.
  final String appId;
}

/// 직전 검사의 판정.
enum _AppCheckMode {
  /// config 에 토큰이 없다 — 새로 만들어 두 앱에 등록한다.
  create,

  /// 토큰은 있고 등록되지 않은 앱이 있다.
  register,

  /// 목록을 읽지 못했다.
  requestFailed,

  /// 프로젝트 ID · 앱 ID 를 읽지 못했다.
  unreadable,

  /// 끝남.
  done,
}
