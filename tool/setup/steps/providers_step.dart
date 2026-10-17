import 'dart:io';

import '../config_files.dart';
import '../confirm.dart';
import '../providers/provider_catalog.dart';
import '../providers/provider_selection.dart';
import '../providers/sign_in_counts.dart';
import '../step.dart';
import '../wizard.dart';
import 'billing_step.dart';

/// 로그인 수단 단계 — 앱에 보일 소셜 로그인을 고르는 체크 목록을 연다.
///
/// 고른 결과의 진실원은 `config/<flavor>.json` 의 `enabledAuthProviders` 하나다.
/// 기본 실행은 지금 값을 점검표 한 줄로 보이기만 하고, `--providers` 로 요청한
/// 실행에서만 체크 목록을 연다. 고른 결과가 바뀌면 값 표 확인 뒤 CSV 를 쓰고
/// 위저드에 단계 목록을 다시 짜게 한다([Replan]) — 같은 실행 안에서 새 로그인
/// 수단의 단계가 이어진다. 이 단계는 CSV 에서 토큰을 빼기만 하고 그 로그인 수단의
/// 키 · secret 값은 남긴다.
///
/// 체크 목록에서 뺀 로그인 수단이 있으면 값 표를 묻기 전에 그 수단의 가입자 수를
/// 센다([countSignIns] — 개수만). 한 수단이라도 가입자가 있으면 CSV 를 바꾸지 않고
/// Remote Config kill switch 를 안내한 뒤 위저드 밖으로 끝낸다([ExitForUser]) —
/// 빼면 그 사용자들이 로그인 · 재인증 · 회원탈퇴를 못 하기 때문이다. 세지 못해도
/// CSV 를 바꾸지 않는다.
final class ProvidersStep implements Step {
  /// 로그인 수단 단계를 만든다.
  ProvidersStep();

  /// 단계 제목.
  static const String stepTitle = '로그인 수단';

  /// 체크 목록을 다시 여는 명령.
  static const String reopenCommand = './setup.sh --providers';

  /// 출시 뒤 로그인 수단 버튼을 숨기는 절차를 설명하는 매뉴얼 절 머리.
  static const String killSwitchManualHeading =
      '### RC Kill Switch 운영 절차 (Emergency Disable)';

  /// 가입자가 있는 로그인 수단을 뺄 때 안내 끝의 테스트 계정 정리 문장.
  static const String testAccountGuideLine =
      '테스트 계정만 있는 개발 프로젝트라면 그 계정을 먼저 지운 뒤 다시 실행하세요';

  /// 로그인 수단 [token] 의 버튼을 켜고 끄는 Remote Config 키를 만든다.
  ///
  /// 앱의 kill switch 키 규칙(`auth_provider_<token>_enabled`)과 같다.
  static String buildRemoteConfigKey(String token) =>
      'auth_provider_${token}_enabled';

  /// 가입자가 있는 로그인 수단을 빼려 할 때의 안내를 만든다.
  ///
  /// [blocked] 는 가입자가 있는 수단의 토큰 → 가입자 수(표 순서)다. 개수 밖의
  /// 사용자 정보는 싣지 않는다.
  static String buildRemovalBlockedGuide(Map<String, int> blocked) {
    final buffer = StringBuffer();
    for (final MapEntry<String, int> entry in blocked.entries) {
      final String name = findProvider(entry.key)?.displayName ?? entry.key;
      buffer.writeln(
        '${entry.value}명이 $name 로그인으로 가입했습니다 — '
        '빼면 이 사용자들이 로그인 · 재인증 · 회원탈퇴를 못 합니다',
      );
    }
    final String keys = blocked.keys.map(buildRemoteConfigKey).join(' · ');
    buffer
      ..writeln('그래서 로그인 수단 목록($enabledProvidersKey)을 바꾸지 않았습니다.')
      ..writeln(
        '앱에서 버튼만 숨기려면 Remote Config 에서 $keys 를 false 로 게시하세요 — '
        '${formatManualReference(killSwitchManualHeading)} '
        '(위저드는 Remote Config 를 바꾸지 않습니다)',
      )
      ..write(testAccountGuideLine);
    return buffer.toString();
  }

  _ProvidersMode _mode = _ProvidersMode.unreadable;
  String _reason = '';
  List<String> _known = const <String>[];
  List<String> _unknown = const <String>[];

  @override
  String get id => 'providers';

  @override
  String get title => stepTitle;

  @override
  List<String> get dependsOn => const <String>['sign_in', 'firestore'];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String path = context.resolve(context.paths.json);
    if (!File(path).existsSync()) {
      return _mark(
        _ProvidersMode.unreadable,
        '${context.paths.json} 이 없어 로그인 수단을 읽지 못했습니다',
      );
    }
    final String? csv = readJsonString(path, enabledProvidersKey);
    if (csv == null) {
      return _mark(
        _ProvidersMode.unreadable,
        '${context.paths.json} 에 $enabledProvidersKey 문자열 값이 없습니다',
      );
    }
    final ({List<String> known, List<String> unknown}) parsed =
        parseProviderCsv(csv);
    _known = parsed.known;
    _unknown = parsed.unknown;
    if (_unknown.isNotEmpty) {
      return _mark(
        _ProvidersMode.choose,
        '알 수 없는 로그인 수단: ${_unknown.join(' · ')} — 고쳐 씁니다',
      );
    }
    if (context.session.isProviderSelectionRequested) {
      return _mark(
        _ProvidersMode.choose,
        '체크 목록을 엽니다 — 지금: ${describeProviders(_known)}',
      );
    }
    _mode = _ProvidersMode.done;
    return Done('${describeProviders(_known)} · 바꾸기: $reopenCommand');
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _ProvidersMode.choose => <String>[
      '(체크 목록에서 고른 결과를 ${context.paths.json} 의 $enabledProvidersKey 에 씁니다 — 바뀌면 단계 목록을 다시 만듭니다)',
    ],
    _ProvidersMode.unreadable || _ProvidersMode.done => const <String>[],
  };

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정(_mode)을 그대로 쓴다.
    return switch (_mode) {
      _ProvidersMode.choose => await _applyChoose(context),
      _ProvidersMode.unreadable => Failed(_reason),
      _ProvidersMode.done => const Applied(),
    };
  }

  /// 체크 목록을 열어 고른 결과를 값 표 확인 뒤 CSV 에 쓴다.
  ///
  /// 뺀 로그인 수단이 있으면 값 표를 묻기 전에 가입자 수를 검사한다.
  Future<StepOutcome> _applyChoose(WizardContext context) async {
    final Set<String> current = _known.toSet();
    final Set<String>? chosen = chooseProviders(
      context.terminal,
      current: current,
    );
    if (chosen == null) return const Declined();
    final bool isSetChanged =
        chosen.length != current.length || !chosen.containsAll(current);
    if (!isSetChanged && _unknown.isEmpty) {
      context.session.isProviderSelectionRequested = false;
      return const Applied();
    }
    final removedTokens = <String>[
      for (final ProviderEntry entry in providerCatalog)
        if (current.contains(entry.token) && !chosen.contains(entry.token))
          entry.token,
    ];
    if (removedTokens.isNotEmpty) {
      final StepOutcome? blocked = await _guardRemoval(context, removedTokens);
      if (blocked != null) return blocked;
    }
    final removed = <String>[
      for (final String token in removedTokens)
        findProvider(token)?.displayName ?? token,
    ];
    final added = <String>[
      for (final ProviderEntry entry in providerCatalog)
        if (!current.contains(entry.token) && chosen.contains(entry.token))
          entry.displayName,
    ];
    final bool isConfirmed = confirmSummary(
      context.terminal,
      title: '로그인 수단 — ${context.flavor.name}',
      rows: <SummaryRow>[
        SummaryRow('지금', describeProviders(current)),
        SummaryRow('새 값', describeProviders(chosen)),
        if (removed.isNotEmpty) SummaryRow('뺀 것', removed.join(' · ')),
        if (added.isNotEmpty) SummaryRow('더한 것', added.join(' · ')),
        if (_unknown.isNotEmpty) SummaryRow('지울 토큰', _unknown.join(' · ')),
        SummaryRow(
          '기록',
          '${context.paths.json} $enabledProvidersKey = '
              '"${formatProviderCsv(chosen)}"',
        ),
      ],
    );
    if (!isConfirmed) return const Declined();
    try {
      writeEnabledProviders(context.resolve(context.paths.json), chosen);
    } on FileSystemException catch (e) {
      return Failed('${context.paths.json} 을 쓰지 못했습니다 — ${e.message}');
    } on FormatException catch (e) {
      return Failed('${context.paths.json} 을 쓰지 못했습니다 — ${e.message}');
    } on ConfigEditException catch (e) {
      return Failed('${context.paths.json} 을 쓰지 못했습니다 — ${e.message}');
    }
    context.session.isProviderSelectionRequested = false;
    return isSetChanged ? const Replan() : const Applied();
  }

  /// 뺀 로그인 수단 [removedTokens] 의 가입자 수를 센다.
  ///
  /// 모두 0명이면 null(진행). 가입자가 있으면 [ExitForUser], 프로젝트 ID 를 읽지
  /// 못하거나 세지 못하면 [Failed] 다 — 어느 쪽이든 CSV 는 쓰지 않는다.
  Future<StepOutcome?> _guardRemoval(
    WizardContext context,
    List<String> removedTokens,
  ) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      return Failed(
        '${context.paths.json} 에서 프로젝트 ID 를 읽지 못해 뺀 로그인 수단의 '
        '가입자 수를 세지 못했습니다 — CSV 는 그대로입니다',
      );
    }
    context.terminal.writeLine(
      '  뺀 로그인 수단의 가입자 수를 셉니다 (개수만): '
      '${removedTokens.map((String t) => findProvider(t)?.displayName ?? t).join(' · ')}',
    );
    final SignInCount counted = await countSignIns(
      context,
      projectId,
      removedTokens.toSet(),
    );
    switch (counted) {
      case SignInCountFailed(:final String reason, :final result):
        return Failed(
          '뺀 로그인 수단의 가입자 수를 세지 못했습니다 — $reason · CSV 는 그대로입니다',
          result: result,
        );
      case SignInCountOk(:final Map<String, int> countsByToken):
        final blocked = <String, int>{
          for (final String token in removedTokens)
            if ((countsByToken[token] ?? 0) > 0) token: countsByToken[token]!,
        };
        if (blocked.isEmpty) return null;
        return ExitForUser(buildRemovalBlockedGuide(blocked));
    }
  }

  /// [mode] 판정과 사유를 두고 할 일 결과를 만든다.
  CheckResult _mark(_ProvidersMode mode, String reason) {
    _mode = mode;
    _reason = reason;
    return Todo(reason);
  }
}

/// 직전 검사의 판정.
enum _ProvidersMode {
  /// 체크 목록을 연다.
  choose,

  /// config 를 읽지 못했다.
  unreadable,

  /// 끝남.
  done,
}
