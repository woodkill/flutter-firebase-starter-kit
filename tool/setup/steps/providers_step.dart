import 'dart:io';

import '../config_files.dart';
import '../confirm.dart';
import '../providers/provider_catalog.dart';
import '../providers/provider_selection.dart';
import '../step.dart';
import '../wizard.dart';

/// 로그인 수단 단계 — 앱에 보일 소셜 로그인을 고르는 체크 목록을 연다.
///
/// 고른 결과의 진실원은 `config/<flavor>.json` 의 `enabledAuthProviders` 하나다.
/// 기본 실행은 지금 값을 점검표 한 줄로 보이기만 하고, `--providers` 로 요청한
/// 실행에서만 체크 목록을 연다. 고른 결과가 바뀌면 값 표 확인 뒤 CSV 를 쓰고
/// 위저드에 단계 목록을 다시 짜게 한다([Replan]) — 같은 실행 안에서 새 로그인
/// 수단의 단계가 이어진다. 이 단계는 CSV 에서 토큰을 빼기만 하고 그 로그인 수단의
/// 키 · secret 값은 남긴다.
final class ProvidersStep implements Step {
  /// 로그인 수단 단계를 만든다.
  ProvidersStep();

  /// 단계 제목.
  static const String stepTitle = '로그인 수단';

  /// 체크 목록을 다시 여는 명령.
  static const String reopenCommand = './setup.sh --providers';

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
      _ProvidersMode.choose => _applyChoose(context),
      _ProvidersMode.unreadable => Failed(_reason),
      _ProvidersMode.done => const Applied(),
    };
  }

  /// 체크 목록을 열어 고른 결과를 값 표 확인 뒤 CSV 에 쓴다.
  StepOutcome _applyChoose(WizardContext context) {
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
    final removed = <String>[
      for (final ProviderEntry entry in providerCatalog)
        if (current.contains(entry.token) && !chosen.contains(entry.token))
          entry.displayName,
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
    } on StateError catch (e) {
      return Failed('${context.paths.json} 을 쓰지 못했습니다 — ${e.message}');
    }
    context.session.isProviderSelectionRequested = false;
    return isSetChanged ? const Replan() : const Applied();
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
