import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../command_runner.dart';
import '../rest_client.dart';
import '../wizard.dart';

/// 홈 디렉터리 기준 Android 디버그 서명 키스토어의 상대 경로.
const String debugKeystoreRelativePath = '.android/debug.keystore';

/// 화면 · 기록에 보일 디버그 키스토어 경로 — 사용자 이름이 든 홈 경로를 숨긴다.
const String debugKeystoreDisplayPath = '~/$debugKeystoreRelativePath';

/// 디버그 키스토어의 별칭.
const String debugKeyAlias = 'androiddebugkey';

/// 디버그 키스토어 · 키의 비밀번호 — Android 도구가 쓰는 공개 기본값이다.
const String debugKeystorePassword = 'android';

/// 지문을 계산할 수 없을 때 Android 쪽 줄에 보이는 안내.
const String unavailableFingerprintGuide =
    'Android 도구(JDK)와 디버그 서명 키가 없어 지문을 계산하지 못했습니다 — '
    'Android 도구를 설치하고 Android 빌드를 한 번 한 뒤 ./setup.sh 를 다시 '
    '실행하면 지문을 보여 줍니다';

/// Firebase Management API 주소 머리.
const String firebaseManagementApiPrefix =
    'https://firebase.googleapis.com/v1beta1/';

/// Firebase Android 앱 SHA 인증서 종류 — SHA-1.
const String shaCertTypeSha1 = 'SHA_1';

/// Firebase Android 앱 SHA 인증서 종류 — SHA-256.
const String shaCertTypeSha256 = 'SHA_256';

/// [keystorePath] 의 디버그 인증서를 PEM 으로 내보내는 keytool 명령을 만든다.
///
/// 인증서(공개 정보)만 읽는다 — 키를 만들거나 키스토어를 바꾸지 않는다. 셸 없이
/// 고정 인자 배열로 실행한다. [displayKeystorePath] 를 주면 화면 · 기록에는 그
/// 경로를 보인다.
Command buildExportCertificateCommand(
  String keystorePath, {
  String? displayKeystorePath,
}) {
  final List<String> arguments = buildExportCertificateArguments(keystorePath);
  final shownPath = displayKeystorePath;
  return Command(
    'keytool',
    arguments,
    display: shownPath == null
        ? null
        : <String>[
            'keytool',
            ...buildExportCertificateArguments(shownPath),
          ].map(quoteForShellDisplay).join(' '),
  );
}

/// [keystorePath] 를 읽는 keytool 인자 배열을 만든다.
List<String> buildExportCertificateArguments(String keystorePath) => <String>[
  '-exportcert',
  '-rfc',
  '-alias',
  debugKeyAlias,
  '-keystore',
  keystorePath,
  '-storepass',
  debugKeystorePassword,
  '-keypass',
  debugKeystorePassword,
];

/// Android 디버그 서명 키 지문 계산 결과.
sealed class DebugFingerprints {
  /// 하위 클래스만 만든다.
  const DebugFingerprints();
}

/// 지문을 계산했다.
final class FingerprintsAvailable extends DebugFingerprints {
  /// SHA-1 · SHA-256(소문자 hex · 콜론 없음)과 키 해시로 결과를 만든다.
  const FingerprintsAvailable({
    required this.sha1Hex,
    required this.sha256Hex,
    required this.keyHash,
  });

  /// SHA-1 — 소문자 hex 40자 · 콜론 없음(Firebase 가 받는 형식).
  final String sha1Hex;

  /// SHA-256 — 소문자 hex 64자 · 콜론 없음(Firebase 가 받는 형식).
  final String sha256Hex;

  /// 키 해시 — SHA-1 바이트의 base64 28자(Kakao · Facebook 이 받는 형식).
  final String keyHash;
}

/// 지문을 계산할 수 없다 — 위저드는 도구를 설치하거나 키를 만들지 않는다.
final class FingerprintsUnavailable extends DebugFingerprints {
  /// 계산할 수 없는 까닭을 [reason] 으로 적는다.
  const FingerprintsUnavailable(this.reason);

  /// 기록에 남길 까닭 — 경로는 홈 기준 표시형만 쓴다.
  final String reason;
}

/// PEM 출력에서 첫 인증서 블록을 읽어 지문을 계산한다.
///
/// 블록 앞뒤의 다른 줄(경고 등)은 무시한다. 블록이 없거나 비었거나 base64 가
/// 아니면 [FingerprintsUnavailable] 을 돌려준다.
DebugFingerprints parseCertificatePem(String pem) {
  final RegExpMatch? match = RegExp(
    r'-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----',
  ).firstMatch(pem);
  if (match == null) {
    return const FingerprintsUnavailable('keytool 출력에 인증서가 없습니다');
  }
  final String body = (match.group(1) ?? '').replaceAll(RegExp(r'\s'), '');
  if (body.isEmpty) {
    return const FingerprintsUnavailable('keytool 출력의 인증서가 비었습니다');
  }
  final List<int> der;
  try {
    der = base64Decode(body);
  } on FormatException {
    return const FingerprintsUnavailable('keytool 출력의 인증서를 읽지 못했습니다');
  }
  if (der.isEmpty) {
    return const FingerprintsUnavailable('keytool 출력의 인증서가 비었습니다');
  }
  final Digest sha1Digest = sha1.convert(der);
  return FingerprintsAvailable(
    sha1Hex: sha1Digest.toString(),
    sha256Hex: sha256.convert(der).toString(),
    keyHash: base64Encode(sha1Digest.bytes),
  );
}

/// 디버그 서명 키 지문을 읽는다 — 한 실행 안에서는 한 번만 계산한다.
///
/// 결과(계산할 수 없음 포함)는 [WizardSession.debugFingerprints] 에 담아 두고
/// 다시 부르면 그 값을 돌려준다. 홈 디렉터리를 모르거나 키스토어가 없으면
/// keytool 을 부르지 않는다. keytool 이 없거나(127) 실패하면 종료 코드를 담은
/// 「계산할 수 없음」 이다.
Future<DebugFingerprints> readDebugFingerprints(WizardContext context) async {
  final DebugFingerprints? cached = context.session.debugFingerprints;
  if (cached != null) return cached;
  final DebugFingerprints result = await _computeDebugFingerprints(context);
  context.session.debugFingerprints = result;
  return result;
}

/// 홈의 디버그 키스토어에서 지문을 계산한다 — 캐시를 보지 않는다.
Future<DebugFingerprints> _computeDebugFingerprints(
  WizardContext context,
) async {
  final String home = context.homeDirectory;
  if (home.isEmpty) {
    return const FingerprintsUnavailable('홈 디렉터리를 알 수 없습니다');
  }
  final keystorePath = '$home/$debugKeystoreRelativePath';
  if (!File(keystorePath).existsSync()) {
    return const FingerprintsUnavailable(
      '디버그 서명 키($debugKeystoreDisplayPath)가 없습니다',
    );
  }
  final CommandResult result = await context.runner.capture(
    buildExportCertificateCommand(
      keystorePath,
      displayKeystorePath: debugKeystoreDisplayPath,
    ),
  );
  if (!result.isSuccess) {
    final what = result.exitCode == ProcessCommandRunner.commandNotFoundExitCode
        ? 'keytool 을 찾지 못했습니다'
        : 'keytool 이 인증서를 읽지 못했습니다';
    return FingerprintsUnavailable('$what — 종료 코드 ${result.exitCode}');
  }
  return parseCertificatePem(result.stdout);
}

/// 소문자 hex SHA-1 [sha1Hex] 를 대문자 · 콜론 표시형(59자)으로 바꾼다.
///
/// LINE 콘솔이 받는 형식이다.
String formatSha1Colon(String sha1Hex) {
  final String upper = normalizeShaHash(sha1Hex).toUpperCase();
  final pairs = <String>[
    for (var i = 0; i < upper.length; i += 2)
      upper.substring(i, i + 2 > upper.length ? upper.length : i + 2),
  ];
  return pairs.join(':');
}

/// SHA 지문을 Firebase 가 받는 형식(소문자 · 콜론 없음)으로 바꾼다.
String normalizeShaHash(String shaHash) =>
    shaHash.replaceAll(':', '').trim().toLowerCase();

/// [projectId] 의 Android 앱 [androidAppId] SHA 인증서 목록 주소를 만든다.
Uri buildShaUrl(String projectId, String androidAppId) => Uri.parse(
  '${firebaseManagementApiPrefix}projects/$projectId/androidApps/'
  '$androidAppId/sha',
);

/// Android 앱 [androidAppId] 의 SHA 인증서 목록을 읽는 요청을 만든다.
RestRequest buildShaListRequest(String projectId, String androidAppId) =>
    RestRequest(
      method: 'GET',
      url: buildShaUrl(projectId, androidAppId),
      quotaProject: projectId,
    );

/// Android 앱 [androidAppId] 에 SHA 인증서를 등록하는 요청을 만든다.
///
/// [shaHash] 는 소문자 · 콜론 없음으로 바꿔 싣는다. [certType] 은
/// [shaCertTypeSha1] · [shaCertTypeSha256] 가운데 하나다.
RestRequest buildShaCreateRequest(
  String projectId,
  String androidAppId, {
  required String shaHash,
  required String certType,
}) => RestRequest(
  method: 'POST',
  url: buildShaUrl(projectId, androidAppId),
  quotaProject: projectId,
  body: jsonEncode(<String, String>{
    'shaHash': normalizeShaHash(shaHash),
    'certType': certType,
  }),
);

/// SHA 인증서 목록 응답에서 등록된 해시를 소문자 집합으로 읽는다.
///
/// 목록 키가 없으면(등록 0건) 빈 집합이다. 성공 응답이 아니거나 JSON 모양이
/// 아니면 null — 「읽지 못함」 을 「0건」 과 가른다.
Set<String>? parseShaHashes(RestResponse response) {
  if (!response.isOk) return null;
  final Object? json = response.decodeJson();
  if (json is! Map<String, Object?>) return null;
  final Object? certificates = json['certificates'];
  if (certificates == null) return <String>{};
  if (certificates is! List<Object?>) return null;
  return <String>{
    for (final Object? item in certificates)
      if (item case {'shaHash': final String hash}) normalizeShaHash(hash),
  };
}
