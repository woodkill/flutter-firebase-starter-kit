import 'dart:io';

import '../command_runner.dart';
import '../config_files.dart';
import '../confirm.dart';
import '../flavor.dart';
import '../secret_store.dart';
import '../step.dart';
import '../steps/billing_step.dart';
import '../wizard.dart';
import 'fingerprints.dart';
import 'key_formats.dart';
import 'provider_catalog.dart';

/// 콘솔 작업을 마쳤는지 묻는 질문.
const String consoleReadyQuestion = '콘솔에서 키를 받았나요?';

/// 콘솔 질문의 진행 선택지.
const String consoleReadyOption = '네 — 키를 입력합니다';

/// 콘솔 질문의 나중 선택지.
const String consoleLaterOption = '아니요 — 끝내고 콘솔 작업 뒤 다시 실행';

/// 형식 · 서버 확인이 틀렸을 때 다시 묻는 최대 횟수.
const int maxKeyAttempts = 3;

/// 숨김 입력 질문 뒤에 붙는 안내 — 입력한 글자가 화면에 보이지 않는다.
const String hiddenInputHint = '(붙여 넣은 뒤 Enter — 입력이 화면에 보이지 않습니다)';

/// 맞춤 실행에서 자리 이름 표의 머리 뒤쪽(`<표시 이름> — <이 말>`).
const String alignSummarySuffix = 'config 값으로 맞출 자리';

/// 자리표시가 아닌 config 값과 다른 자리만 남았을 때의 사유 머리.
const String alignReasonPrefix = 'config 와 다른 자리: ';

/// 입력한 키가 다른 flavor 의 키와 같을 때 덧붙이는 안내.
const String duplicateInputHint = 'flavor 마다 새 콘솔 앱의 키를 넣으세요';

/// 로그인 수단 토큰 → 매뉴얼에서 flavor 마다 새 콘솔 앱을 만드는 절 머리의 앞부분.
///
/// 표에 없는 수단은 그 수단의 기본 절([ProviderEntry.manualSectionPrefix])을
/// 가리킨다.
const Map<String, String> flavorAppManualHeadings = <String, String>{
  'kakao': '## Kakao 검수',
  'naver': '## Naver 검수',
};

/// [entry] 의 flavor 별 새 앱 절 머리를 찾는다 — 표에 없으면 그 수단의 기본 절.
String findFlavorAppManualHeading(ProviderEntry entry) =>
    flavorAppManualHeadings[entry.token] ?? entry.manualSectionPrefix;

/// [flavor] 의 키와 같다는 문장을 만든다(`<flavor> 의 키와 같습니다 — <detail>`).
String buildDuplicateMessage(Flavor flavor, String detail) =>
    '${flavor.name} 의 키와 같습니다 — $detail';

/// 값이 들어가는 자리 하나 — 파일 경로(또는 `Secret Manager`)와 키 · 변수 이름.
typedef _Place = ({String location, String name});

/// 자리 하나를 화면 표시형(`<location> <name>`)으로 쓴다.
String _describePlace(_Place place) => '${place.location} ${place.name}';

/// 키 값 하나와 그 값이 들어가는 모든 자리.
///
/// config 키 · xcconfig 변수 · Secret Manager 이름 여러 개를 한 항목에 묶는다.
/// config 키가 없는 값(서버 전용 secret)은 [secretNames] 만 갖는다.
final class KeyField {
  /// 화면 이름 [label] · 형식 [format] 과 값이 들어갈 자리로 만든다.
  const KeyField({
    required this.label,
    required this.format,
    this.configKey,
    this.xcconfigVar,
    this.secretNames = const <String>[],
    this.isHidden = false,
  });

  /// 화면에 보일 값 이름.
  final String label;

  /// 입력 즉시 검사할 형식.
  final KeyFormat format;

  /// `config/<flavor>.json` 의 키 — 없으면 null.
  final String? configKey;

  /// `ios/Flutter/<flavor>.xcconfig` 의 변수 — 없으면 null.
  final String? xcconfigVar;

  /// 같은 값이 들어갈 Secret Manager 이름.
  final List<String> secretNames;

  /// 비밀 값이라 숨김 입력으로 받으면 true.
  final bool isHidden;

  /// Secret Manager 쓰기 표시형의 값 자리(`<label>`).
  String get valueLabel => '<$label>';
}

/// 키 짝 서버 확인 결과.
sealed class PairCheck {
  /// 하위 클래스만 만든다.
  const PairCheck();
}

/// 서버가 키를 받아들였다.
final class PairOk extends PairCheck {
  /// 맞음 결과를 만든다.
  const PairOk();
}

/// 서버가 [field] 값(과 [alsoFields])을 받아들이지 않았다 — 가리킨 값만 다시
/// 묻는다.
///
/// 서버가 어느 값이 틀렸는지 알려 주지 않으면 함께 다시 물을 값을 [alsoFields]
/// 에 둔다.
final class PairMismatch extends PairCheck {
  /// 틀린 [field] 와 화면에 보일 [reason] 으로 만든다 — 함께 다시 물을 값은
  /// [alsoFields].
  const PairMismatch(
    this.field,
    this.reason, {
    this.alsoFields = const <KeyField>[],
  });

  /// 다시 물을 값.
  final KeyField field;

  /// [field] 와 함께 다시 물을 값(순서대로).
  final List<KeyField> alsoFields;

  /// 화면에 보일 이유(상태만 — 응답 본문은 넣지 않는다).
  final String reason;

  /// 가리킨 값 전체 — [field] 뒤에 [alsoFields] 순서, 같은 값은 한 번만.
  List<KeyField> get pointedFields => <KeyField>{field, ...alsoFields}.toList();
}

/// 서버 확인이 없는 로그인 수단 · 확인할 값이 이번에 없다.
final class PairNotAvailable extends PairCheck {
  /// 확인 없음 결과를 만든다.
  const PairNotAvailable();
}

/// 서버 확인을 하지 못했다 — 아무것도 쓰지 않고 실패로 끝낸다.
final class PairFailed extends PairCheck {
  /// 실패 [reason] 으로 만든다.
  const PairFailed(this.reason);

  /// 실패 요약.
  final String reason;
}

/// 콘솔에서 받은 키를 한 번 입력받아 모든 자리에 쓰는 로그인 수단 단계의 공통 뼈대.
///
/// 검사 순서는 프로젝트 ID → config 값(자리표시가 아니고 형식에 맞음) → 다른
/// flavor 의 config 와 같은 값인지 → xcconfig 값 = config 값 · Secret Manager 값
/// (config 키가 있으면 config 값과 같음) → 서버 전용 secret 이 있음(자리표시가
/// 아님)이다. config 가 진실원이라 자리표시가 아닌 config 값은 묻지 않고, 어긋난
/// xcconfig · Secret Manager 값은 config 값으로 맞춘다(화면에는 자리 이름만).
/// 다른 flavor 와 같은 값은 자리표시처럼 새로 묻는다 — 다른 flavor 파일은 읽기만
/// 한다. 검사 한 번에 Secret Manager 를 이름마다 정확히 한 번 읽는다.
///
/// 물을 값이 있으면 실행은 값 표(콘솔에 넣을 값 · 콘솔 주소 · 할 일 · 매뉴얼 절)를
/// 보인 뒤 콘솔 작업을 마쳤는지 묻고 그 값만 받는다(비밀 값은 숨김 입력). 형식 ·
/// 다른 flavor 중복 · 서버 확인이 틀리면 그 값만 [maxKeyAttempts] 회까지 다시
/// 묻는다. 물을 값이 없으면(맞춤) 고칠 자리 이름 표만 보이고, 서버 확인이 있는
/// 수단은 config 값으로 짝을 먼저 확인한 뒤 쓴다. 두 경우 모두 서버 확인에는
/// 묻지 않은 서버 전용 secret 의 Secret Manager 값(메모리만)도 함께 넘겨 옛 콘솔
/// 앱의 secret 과 새 키가 짝 확인 없이 기록되지 않게 한다. 기록은 config → xcconfig →
/// Secret Manager(표준 입력) 순서다. 원격 자리가 있는 수단은 검사 끝에
/// [findRemoteProblem] 으로 그 자리를 보고, 기록 끝에 [writeRemote] 로 쓴다.
abstract class KeyedProviderStep implements Step {
  /// 하위 클래스만 만든다.
  KeyedProviderStep();

  /// Secret Manager 를 읽지 못한 검사 뒤의 계획 줄 — 이 한 줄만 있으면 실패
  /// 모드다(하위 클래스가 계획 줄을 덧붙일지 가를 때 쓴다).
  static const String failureCommandLine = '(명령 원문을 보입니다)';

  /// 이 단계가 다루는 로그인 수단의 표 행.
  ProviderEntry get entry;

  /// 입력받아 기록할 값 목록(물을 순서).
  List<KeyField> get fields;

  /// 콘솔에 넣을 값 표의 행(패키지명 · 번들 ID 등 — 비밀 값은 넣지 않는다).
  ///
  /// 실행은 이 함수를 부르기 전에 세션 지문([readDebugFingerprints])을 계산해
  /// 두므로 키 해시 · SHA-1 행은 세션 값만 읽으면 된다.
  List<SummaryRow> buildValueRows(WizardContext context);

  /// 콘솔에서 할 일 — 기능 이름으로 쓴 3 ~ 5줄.
  List<String> get todoLines;

  /// 입력받은 [values] 를 서버로 확인한다 — 확인이 없으면 [PairNotAvailable].
  Future<PairCheck> verifyPair(
    WizardContext context,
    Map<KeyField, String> values,
  );

  /// 보이는 값 [field] 를 물을 때 Enter 로 고를 제안 기본값 — 없으면 null.
  ///
  /// 기본은 제안이 없다. 숨김 값에는 이 값을 쓰지 않는다(숨김 입력은 기본값을
  /// 받지 않는다).
  String? suggestValue(WizardContext context, KeyField field) => null;

  /// 파일 · Secret Manager 밖의 원격 자리(예: Firebase 로그인 수단 설정)가
  /// [values] 와 어긋나는지 본다 — 어긋나면 화면에 보일 자리 이름(값 없음), 맞으면
  /// null.
  ///
  /// 검사가 파일 · Secret Manager 를 모두 읽은 뒤(읽기 실패가 없을 때) 부른다.
  /// [values] 는 자리표시가 아닌 config 값과 이번 검사에서 Secret Manager 로 읽은
  /// 서버 전용 secret 값(메모리만)이다 — 물을 값은 들어 있지 않다. 기본은 원격
  /// 자리가 없다(요청 0).
  Future<String?> findRemoteProblem(
    WizardContext context,
    Map<KeyField, String> values,
  ) async => null;

  /// 원격 자리에 [values] 를 쓴다 — 실패면 단계 결과로 보일 [Failed], 아니면 null.
  ///
  /// 실행(입력 · 맞춤 모두)이 config → xcconfig → Secret Manager 를 모두 쓴
  /// 뒤 마지막에 부른다. [values] 는 그 기록에 쓴 값(입력값이 우선)과 서버 전용
  /// secret 의 Secret Manager 값(메모리만)이다. 실패해도 앞에서 쓴 자리는 되돌리지
  /// 않는다. 기본은 아무것도 쓰지 않는다(요청 0).
  Future<Failed?> writeRemote(
    WizardContext context,
    Map<KeyField, String> values,
  ) async => null;

  _KeyedMode _mode = _KeyedMode.unreadable;
  String _reason = '';
  CommandResult? _failedResult;
  String _projectId = '';
  List<KeyField> _askFields = const <KeyField>[];
  Map<KeyField, String> _knownValues = const <KeyField, String>{};
  Map<KeyField, String> _serverSecretValues = const <KeyField, String>{};
  String? _remoteProblem;
  List<KeyField> _xcconfigFixes = const <KeyField>[];
  Map<KeyField, List<String>> _secretWrites = const <KeyField, List<String>>{};
  List<_Place> _places = const <_Place>[];
  Map<KeyField, Map<Flavor, String>> _otherFlavorValues =
      const <KeyField, Map<Flavor, String>>{};

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    final String? projectId = readConfiguredProjectId(context);
    if (projectId == null) {
      return _mark(
        _KeyedMode.unreadable,
        '${context.paths.json} 에서 프로젝트 ID 를 읽지 못했습니다',
      );
    }
    final String jsonPath = context.resolve(context.paths.json);
    final String xcconfigPath = context.resolve(context.paths.xcconfig);
    final askFields = <KeyField>[];
    final knownValues = <KeyField, String>{};
    final serverSecretValues = <KeyField, String>{};
    final xcconfigFixes = <KeyField>[];
    final secretWrites = <KeyField, List<String>>{};
    final pending = <_Place>[];
    final duplicates = <String>[];
    final otherFlavorValues = <KeyField, Map<Flavor, String>>{};
    var secretCount = 0;

    for (final KeyField field in fields) {
      var needsInput = false;
      String? configValue;
      final String? configKey = field.configKey;
      if (configKey != null) {
        final Map<Flavor, String> others = _readOtherFlavorValues(
          context,
          configKey,
          isHidden: field.isHidden,
        );
        if (others.isNotEmpty) otherFlavorValues[field] = others;
        final String? raw = readJsonString(jsonPath, configKey)?.trim();
        // 숨김 값은 Secret Manager 에서 읽을 때와 같이 읽자마자 가림 함수에 등록한다.
        if (raw != null &&
            field.isHidden &&
            !_isPlaceholder(context, raw, configKey)) {
          context.redactor.register(raw);
        }
        final Flavor? sameFlavor = raw == null
            ? null
            : _findSameFlavor(others, raw);
        if (raw == null ||
            _isPlaceholder(context, raw, configKey) ||
            !field.format.matches(raw)) {
          needsInput = true;
          pending.add((location: context.paths.json, name: configKey));
        } else if (sameFlavor != null) {
          // 다른 flavor 와 같은 키는 진실원으로 쓰지 않고 새로 묻는다.
          needsInput = true;
          duplicates.add(buildDuplicateMessage(sameFlavor, field.label));
          pending.add((location: context.paths.json, name: configKey));
        } else {
          configValue = raw;
        }
      }
      final String? xcconfigVar = field.xcconfigVar;
      if (xcconfigVar != null) {
        if (!File(xcconfigPath).existsSync()) {
          return _mark(
            _KeyedMode.unreadable,
            '${context.paths.xcconfig} 이 없습니다',
          );
        }
        final String? current = readXcconfigValue(xcconfigPath, xcconfigVar);
        if (current == null) {
          return _mark(
            _KeyedMode.unreadable,
            '${context.paths.xcconfig} 에 $xcconfigVar 변수가 없습니다',
          );
        }
        if (needsInput || current != configValue) {
          xcconfigFixes.add(field);
          pending.add((location: context.paths.xcconfig, name: xcconfigVar));
        }
      }
      final mismatchedSecrets = <String>[];
      for (final String name in field.secretNames) {
        secretCount++;
        final SecretRead read = await readSecret(context, name, projectId);
        switch (read) {
          case SecretReadFailed(
            :final String reason,
            :final CommandResult result,
          ):
            return _mark(_KeyedMode.failed, reason, result: result);
          case SecretFound(:final String value) when configKey != null:
            if (needsInput || value != configValue) mismatchedSecrets.add(name);
          case SecretFound(:final String value):
            if (value.isEmpty || value == secretPlaceholderValue) {
              needsInput = true;
            } else {
              // 서버 확인 · 원격 자리 비교 · 원격 기록에만 쓴다(메모리만) — 묻지
              // 않으므로 파일 · Secret Manager 에는 다시 쓰지 않는다.
              serverSecretValues[field] = value;
            }
          case SecretMissing():
            if (configKey != null) {
              mismatchedSecrets.add(name);
            } else {
              needsInput = true;
            }
        }
      }
      final List<String> writeNames = needsInput
          ? field.secretNames
          : mismatchedSecrets;
      if (writeNames.isNotEmpty) {
        secretWrites[field] = writeNames;
        pending.addAll(<_Place>[
          for (final String name in writeNames)
            (location: 'Secret Manager', name: name),
        ]);
      }
      if (needsInput) {
        askFields.add(field);
      } else if (configValue != null) {
        knownValues[field] = configValue;
      }
    }

    _projectId = projectId;
    _askFields = askFields;
    _knownValues = knownValues;
    _serverSecretValues = serverSecretValues;
    _xcconfigFixes = xcconfigFixes;
    _secretWrites = secretWrites;
    _places = pending;
    _otherFlavorValues = otherFlavorValues;
    final String? remoteProblem = await findRemoteProblem(
      context,
      <KeyField, String>{...knownValues, ...serverSecretValues},
    );
    _remoteProblem = remoteProblem;
    if (pending.isEmpty && remoteProblem == null) {
      _mode = _KeyedMode.done;
      return Done('키 · secret $secretCount개 · iOS 쪽 맞음');
    }
    final String places = <String>[
      ...pending.map(_describePlace),
      ?remoteProblem,
    ].join(' · ');
    if (duplicates.isNotEmpty) {
      return _mark(_KeyedMode.duplicate, duplicates.join(' · '));
    }
    if (askFields.isNotEmpty) {
      return _mark(_KeyedMode.fill, '채울 자리: $places');
    }
    return _mark(_KeyedMode.align, '$alignReasonPrefix$places');
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => switch (_mode) {
    _KeyedMode.fill || _KeyedMode.duplicate => <String>[
      '(${entry.displayName} 콘솔에 넣을 값 · 할 일을 보입니다)',
      if (_askFields.isNotEmpty)
        '(콘솔에서 받은 키를 묻습니다 — 비밀 값은 화면에 보이지 않게 받고, 형식 · 서버 확인 뒤에 기록합니다)',
      ..._buildWriteLines(context),
    ],
    _KeyedMode.align => <String>[
      '(${entry.displayName} — config 값으로 맞출 자리 이름을 보입니다 · 키는 묻지 않습니다)',
      ..._buildWriteLines(context),
    ],
    _KeyedMode.failed => const <String>[failureCommandLine],
    _KeyedMode.unreadable || _KeyedMode.done => const <String>[],
  };

  /// 기록할 자리마다 계획 줄 하나 — 값은 넣지 않는다.
  List<String> _buildWriteLines(WizardContext context) => <String>[
    for (final KeyField field in fields)
      if (field.configKey != null && _askFields.contains(field))
        '(${context.paths.json} ${field.configKey} 에 씁니다)',
    for (final KeyField field in _xcconfigFixes)
      '(${context.paths.xcconfig} ${field.xcconfigVar} 에 씁니다)',
    for (final MapEntry<KeyField, List<String>> write in _secretWrites.entries)
      for (final String name in write.value)
        buildSecretWriteCommand(
          name,
          _projectId,
          value: '',
          valueLabel: write.key.valueLabel,
        ).render(),
  ];

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    // 위저드는 실행 직전에 check 를 부르므로 그 판정을 그대로 쓴다.
    return switch (_mode) {
      _KeyedMode.fill => await _applyFill(context),
      _KeyedMode.duplicate => await _applyFill(context, isDuplicate: true),
      _KeyedMode.align => await _applyAlign(context),
      _KeyedMode.failed => Failed(_reason, result: _failedResult),
      _KeyedMode.unreadable => Failed(_reason),
      _KeyedMode.done => const Applied(),
    };
  }

  /// 값 표 → 콘솔 질문 → 물을 값 입력 · 형식 · 서버 확인 → 모든 자리 기록.
  ///
  /// [isDuplicate] 면 다른 flavor 와 같은 키라는 사유와 flavor 별 새 앱 절을 함께
  /// 보인다.
  Future<StepOutcome> _applyFill(
    WizardContext context, {
    bool isDuplicate = false,
  }) async {
    // 값 표의 키 해시 · SHA-1 행은 세션 지문을 읽는다 — `<token>_android` 줄이
    // 아직 검사되지 않은 바퀴면 여기서 한 번 계산한다(세션 캐시라 keytool 은
    // 한 실행에 한 번).
    await readDebugFingerprints(context);
    final String newAppHeading = findFlavorAppManualHeading(entry);
    writeSummary(
      context.terminal,
      title: '${entry.displayName} 콘솔에 넣을 값 — ${context.flavor.name}',
      rows: buildValueRows(context),
      notes: <String>[
        if (isDuplicate) _reason,
        '콘솔: ${entry.consoleUrl}',
        ...todoLines,
        if (isDuplicate)
          'flavor 마다 새 앱 만들기: ${formatManualReference(newAppHeading)}',
        '자세한 절차: ${formatManualReference(entry.manualSectionPrefix)}',
      ],
    );
    final values = Map<KeyField, String>.of(_knownValues);
    if (_askFields.isNotEmpty) {
      final int? choice = context.terminal.choose(
        consoleReadyQuestion,
        const <String>[consoleReadyOption, consoleLaterOption],
        defaultIndex: null,
      );
      if (choice == null) return const Declined();
      if (choice == 1) {
        return ExitForUser(
          _buildLaterGuide(
            isDuplicate ? newAppHeading : entry.manualSectionPrefix,
          ),
        );
      }
      for (final KeyField field in _askFields) {
        final String? value = _askValue(context, field);
        if (value == null) return const Declined();
        values[field] = value;
      }
      final StepOutcome? rejected = await _verifyValues(context, values);
      if (rejected != null) return rejected;
    }
    return await _writeValues(context, values);
  }

  /// 고칠 자리 이름 표 → (서버 확인이 있으면) config 값으로 짝 확인 → 기록.
  ///
  /// 키는 묻지 않는다. 서버 확인에는 config 에서 읽은 값과 검사가 Secret Manager
  /// 에서 읽은 서버 전용 secret 값(메모리만)을 함께 넘긴다 — 기록 값에는 섞지
  /// 않는다. 짝이 틀리거나 확인하지 못하면 아무것도 쓰지 않고 실패로 끝낸다.
  Future<StepOutcome> _applyAlign(WizardContext context) async {
    writeSummary(
      context.terminal,
      title: '${entry.displayName} — $alignSummarySuffix',
      rows: <SummaryRow>[
        for (final _Place place in _places)
          SummaryRow(place.location, place.name),
      ],
      notes: <String>[
        ?_remoteProblem,
        '${context.paths.json} 의 값으로 씁니다 — 값은 화면에 보이지 않습니다',
      ],
    );
    final values = Map<KeyField, String>.of(_knownValues);
    final PairCheck result = await verifyPair(
      context,
      _buildVerifyValues(values),
    );
    switch (result) {
      case PairFailed(:final String reason):
        return Failed(reason);
      case PairMismatch(:final String reason) && final PairMismatch mismatch:
        return _buildMismatchFailure(context, reason, mismatch.pointedFields);
      case PairOk() || PairNotAvailable():
        return await _writeValues(context, values);
    }
  }

  /// 서버 확인에 넘길 값 — 검사가 읽은 서버 전용 secret 값 위에 [values] 를
  /// 덮는다(입력값이 우선). [values] 자체는 바꾸지 않는다.
  Map<KeyField, String> _buildVerifyValues(Map<KeyField, String> values) =>
      <KeyField, String>{..._serverSecretValues, ...values};

  /// 이번에 묻지 않은 값을 가리킨 짝 불일치의 실패 — 고칠 자리 이름과 되돌리는
  /// 방법을 보인다(값은 넣지 않는다).
  ///
  /// config 키가 있는 값은 config 자리를 고치거나 자리표시로 되돌리게 하고,
  /// 서버 전용 secret 은 `Secret Manager <이름>` 을 고치거나
  /// [secretPlaceholderValue] 로 되돌리게 한다 — 다음 실행이 그 값을 새로 묻는다.
  Failed _buildMismatchFailure(
    WizardContext context,
    String reason,
    List<KeyField> pointedFields,
  ) {
    final configPlaces = <String>[];
    final secretPlaces = <String>[];
    for (final field in pointedFields) {
      final String? configKey = field.configKey;
      if (configKey != null) {
        configPlaces.add('${context.paths.json} $configKey');
      } else if (field.secretNames.isEmpty) {
        configPlaces.add(field.label);
      } else {
        secretPlaces.addAll(<String>[
          for (final String name in field.secretNames) 'Secret Manager $name',
        ]);
      }
    }
    final guides = <String>[];
    if (configPlaces.isNotEmpty) {
      guides.add(
        '${configPlaces.join(' · ')} 값을 고치거나, 자리표시로 되돌린 뒤 다시 '
        '실행해 새로 입력하세요',
      );
    }
    if (secretPlaces.isNotEmpty) {
      guides.add(
        '${secretPlaces.join(' · ')} 값을 고치거나 $secretPlaceholderValue 으로 '
        '되돌린 뒤 다시 실행하면 새로 묻습니다 '
        '(${formatManualReference(providersManualHeading)} 「켜기」 ④)',
      );
    }
    return Failed('$reason — ${guides.join(' · ')}');
  }

  /// 콘솔 작업이 남았을 때의 위저드 밖 작업 안내 — [heading] 절을 가리킨다.
  String _buildLaterGuide(String heading) =>
      '  ${entry.displayName} 콘솔에서 위 할 일을 마치고 키를 받은 뒤 다시 실행하세요 — '
      '${formatManualReference(heading)}\n'
      '  급하면 ./setup.sh --providers 로 ${entry.displayName} 로그인을 잠시 끌 수 '
      '있습니다.';

  /// [field] 값을 형식에 맞을 때까지 묻는다 — 입력 끝 · [maxKeyAttempts] 회
  /// 틀림이면 null.
  ///
  /// 비밀 값은 숨김 입력으로 받아 바로 가림 함수에 등록하고, 받은 뒤에는 글자 수 ·
  /// 형식 판정만 보인다. 형식에 맞아도 다른 flavor 의 config 값과 같으면 그
  /// flavor 를 알리고 다시 묻는다(같은 횟수 상한). 보이는 값은 [suggestValue]
  /// 가 있으면 그 값을 Enter 기본값으로 둔다.
  String? _askValue(WizardContext context, KeyField field) {
    final String? suggestion = field.isHidden
        ? null
        : suggestValue(context, field);
    for (var attempt = 0; attempt < maxKeyAttempts; attempt++) {
      final String? answer = field.isHidden
          ? context.terminal.askSecret('${field.label} $hiddenInputHint')
          : context.terminal.ask(field.label, defaultValue: suggestion);
      if (answer == null) return null;
      if (field.isHidden) context.redactor.register(answer);
      if (field.format.matches(answer)) {
        final Flavor? sameFlavor = _findSameFlavor(
          _otherFlavorValues[field] ?? const <Flavor, String>{},
          answer,
        );
        if (sameFlavor != null) {
          context.terminal.writeLine(
            '  ${buildDuplicateMessage(sameFlavor, duplicateInputHint)}',
          );
          continue;
        }
        context.terminal.writeLine(
          '  ${field.label} — ${answer.length}자 · 형식 맞음',
        );
        return answer;
      }
      context.terminal.writeLine(
        '  ${field.label} 형식이 맞지 않습니다 — ${answer.length}자 · '
        '규칙: ${field.format.description}',
      );
    }
    return null;
  }

  /// 서버 확인을 하고, 틀린 값만 [maxKeyAttempts] 회까지 다시 묻는다.
  ///
  /// 서버 확인에는 [values] 와 검사가 Secret Manager 에서 읽은 서버 전용 secret
  /// 값(메모리만 · 이번에 묻지 않은 값)을 함께 넘긴다. 불일치가 가리킨 값
  /// ([PairMismatch.pointedFields]) 가운데 이번에 물은 값만 순서대로 다시 묻는다 —
  /// 하나도 없으면 고칠 자리 이름과 되돌리는 방법을 보이고 실패로 끝낸다. 통과하면
  /// null, 아니면 단계 결과(거절 · 실패)를 돌려준다.
  Future<StepOutcome?> _verifyValues(
    WizardContext context,
    Map<KeyField, String> values,
  ) async {
    for (var attempt = 0; attempt < maxKeyAttempts; attempt++) {
      final PairCheck result = await verifyPair(
        context,
        _buildVerifyValues(values),
      );
      switch (result) {
        case PairOk() || PairNotAvailable():
          return null;
        case PairFailed(:final String reason):
          return Failed(reason);
        case PairMismatch(:final String reason) && final PairMismatch mismatch:
          context.terminal.writeLine('  $reason');
          final retryFields = <KeyField>[
            for (final KeyField field in mismatch.pointedFields)
              if (_askFields.contains(field)) field,
          ];
          if (retryFields.isEmpty) {
            return _buildMismatchFailure(
              context,
              reason,
              mismatch.pointedFields,
            );
          }
          if (attempt == maxKeyAttempts - 1) return const Declined();
          for (final field in retryFields) {
            final String? value = _askValue(context, field);
            if (value == null) return const Declined();
            values[field] = value;
          }
      }
    }
    return const Declined();
  }

  /// config → xcconfig → Secret Manager 순서로 값을 쓴다.
  Future<StepOutcome> _writeValues(
    WizardContext context,
    Map<KeyField, String> values,
  ) async {
    final String jsonPath = context.resolve(context.paths.json);
    final String xcconfigPath = context.resolve(context.paths.xcconfig);
    try {
      for (final KeyField field in _askFields) {
        final String? configKey = field.configKey;
        if (configKey == null) continue;
        replaceJsonString(jsonPath, configKey, values[field]!);
      }
      for (final KeyField field in _xcconfigFixes) {
        replaceXcconfigValue(xcconfigPath, field.xcconfigVar!, values[field]!);
      }
    } on FileSystemException catch (e) {
      return Failed('${entry.displayName} 키를 파일에 쓰지 못했습니다 — $e');
    } on FormatException catch (e) {
      return Failed('${entry.displayName} 키를 파일에 쓰지 못했습니다 — $e');
    } on ConfigEditException catch (e) {
      return Failed('${entry.displayName} 키를 파일에 쓰지 못했습니다 — ${e.message}');
    }
    for (final MapEntry<KeyField, List<String>> write
        in _secretWrites.entries) {
      final String? value = values[write.key];
      if (value == null) continue;
      for (final String name in write.value) {
        final Command command = buildSecretWriteCommand(
          name,
          _projectId,
          value: value,
          valueLabel: write.key.valueLabel,
        );
        context.terminal.writeCommand(command.render());
        final CommandResult written = await context.runner.capture(command);
        if (!written.isSuccess) {
          // 민감 출력이라 표준 출력은 버리고 오류 원문만 보인다.
          return Failed(
            'Secret Manager 의 $name 을 쓰지 못했습니다 (종료 코드 ${written.exitCode})',
            result: written.withoutStdout(),
          );
        }
      }
    }
    final Failed? remoteFailure = await writeRemote(context, <KeyField, String>{
      ..._serverSecretValues,
      ...values,
    });
    return remoteFailure ?? const Applied();
  }

  /// [raw] 가 그 flavor example config 의 같은 키 값(자리표시)이거나 빈 값이면 true.
  static bool _isPlaceholder(
    WizardContext context,
    String raw,
    String configKey,
  ) => _isPlaceholderIn(context, context.paths.jsonExample, raw, configKey);

  /// [raw] 가 [exampleRelativePath] example config 의 같은 키 값이거나 빈 값이면
  /// true.
  static bool _isPlaceholderIn(
    WizardContext context,
    String exampleRelativePath,
    String raw,
    String configKey,
  ) {
    if (raw.isEmpty) return true;
    final String examplePath = context.resolve(exampleRelativePath);
    if (!File(examplePath).existsSync()) return false;
    return readJsonString(examplePath, configKey)?.trim() == raw;
  }

  /// 지금 flavor 밖 flavor 들의 config(파일이 있을 때만)에서 [configKey] 의
  /// 자리표시가 아닌 값을 읽는다 — 읽기만 하고, 읽지 못한 파일은 건너뛴다.
  ///
  /// [isHidden] 이면 읽은 값을 바로 가림 함수에 등록한다.
  static Map<Flavor, String> _readOtherFlavorValues(
    WizardContext context,
    String configKey, {
    required bool isHidden,
  }) {
    final values = <Flavor, String>{};
    for (final Flavor other in Flavor.values) {
      if (other == context.flavor) continue;
      final paths = FlavorPaths(other);
      final String path = context.resolve(paths.json);
      if (!File(path).existsSync()) continue;
      final String? raw;
      try {
        raw = readJsonString(path, configKey)?.trim();
      } on FileSystemException {
        continue;
      }
      if (raw == null ||
          _isPlaceholderIn(context, paths.jsonExample, raw, configKey)) {
        continue;
      }
      if (isHidden) context.redactor.register(raw);
      values[other] = raw;
    }
    return values;
  }

  /// [others] 가운데 값이 [value] 와 같은 첫 flavor — 없으면 null.
  static Flavor? _findSameFlavor(Map<Flavor, String> others, String value) {
    for (final MapEntry<Flavor, String> other in others.entries) {
      if (other.value == value) return other.key;
    }
    return null;
  }

  /// [mode] 판정과 사유를 두고 할 일 결과를 만든다.
  CheckResult _mark(_KeyedMode mode, String reason, {CommandResult? result}) {
    _mode = mode;
    _reason = reason;
    _failedResult = result;
    return Todo(reason);
  }
}

/// 직전 검사의 판정.
enum _KeyedMode {
  /// 물을 값 · 맞출 자리가 있다.
  fill,

  /// 다른 flavor 와 같은 키가 있다 — 그 값을 새로 묻는다.
  duplicate,

  /// 물을 값은 없고 config 값으로 맞출 자리만 있다.
  align,

  /// Secret Manager 를 읽지 못했다.
  failed,

  /// 프로젝트 ID · xcconfig 를 읽지 못했다.
  unreadable,

  /// 끝남.
  done,
}
