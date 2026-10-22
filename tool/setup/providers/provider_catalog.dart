import 'dart:io';

import '../config_files.dart';

/// config 에서 켠 로그인 수단 목록(쉼표로 이은 토큰)을 담는 키.
const String enabledProvidersKey = 'enabledAuthProviders';

/// 위저드가 가리키는 문서의 절 하나 — 문서 파일 경로와 그 절의 머리 줄.
///
/// 화면에는 [formatDocReference] 로 `<파일> 「<절 제목>」` 꼴로 보인다. 머리 줄은
/// 문서의 그 줄과 글자가 같아야 한다 — 시험이 문서에서 그 줄을 찾는다.
final class DocRef {
  /// [file] 문서의 [heading] 절을 가리킨다.
  const DocRef(this.file, this.heading);

  /// 저장소 루트 상대 문서 경로.
  final String file;

  /// `#` 로 시작하는 문서 머리 한 줄.
  final String heading;
}

/// [ref] 를 화면 표시형 `<파일> 「<절 제목>」` 으로 바꾼다 — 머리의 `#` 은 뺀다.
String formatDocReference(DocRef ref) =>
    '${ref.file} 「${ref.heading.replaceFirst(RegExp(r'^#+\s*'), '')}」';

/// Google 로그인을 켜는 절.
const DocRef googleDocRef = DocRef('docs/setup.md', '### Google 로그인 켜기');

/// Apple 로그인을 켜는 절.
const DocRef appleDocRef = DocRef('docs/setup.md', '### Apple 로그인 켜기');

/// 로그인 수단마다 이메일을 받도록 설정하는 절.
const DocRef emailDocRef = DocRef('docs/setup.md', '### 로그인 수단에서 이메일 받기');

/// 콘솔 주소를 따로 두지 않은 로그인 수단이 쓰는 Firebase 콘솔 주소.
const String firebaseConsoleUrl = 'https://console.firebase.google.com';

/// 로그인 수단 하나의 표 행.
final class ProviderEntry {
  /// 토큰 · 표시 이름 · 문서 절 · 콘솔 주소로 행을 만든다.
  const ProviderEntry({
    required this.token,
    required this.displayName,
    required this.docRef,
    required this.consoleUrl,
  });

  /// `enabledAuthProviders` · 배포 스크립트가 쓰는 토큰.
  final String token;

  /// 화면에 보일 이름.
  final String displayName;

  /// 이 로그인 수단을 켜는 절차를 설명하는 문서 절.
  final DocRef docRef;

  /// 키를 발급받는 콘솔 주소.
  final String consoleUrl;
}

/// 위저드가 켜고 끌 수 있는 로그인 수단 표 — 순서가 체크 목록 번호 · CSV 순서다.
///
/// 토큰은 `scripts/functions_manifest.json` 의 `providers` 키와 같다. 새 로그인
/// 수단을 더하려면 이 표에 행을 더하고 그 수단의 단계를 단계 목록에 끼운다.
const List<ProviderEntry> providerCatalog = <ProviderEntry>[
  ProviderEntry(
    token: 'google',
    displayName: 'Google',
    docRef: googleDocRef,
    consoleUrl: firebaseConsoleUrl,
  ),
  ProviderEntry(
    token: 'apple',
    displayName: 'Apple',
    docRef: appleDocRef,
    consoleUrl: firebaseConsoleUrl,
  ),
  ProviderEntry(
    token: 'facebook',
    displayName: 'Facebook',
    docRef: DocRef('docs/setup.md', '### Facebook 로그인 켜기'),
    consoleUrl: firebaseConsoleUrl,
  ),
  ProviderEntry(
    token: 'kakao',
    displayName: 'Kakao',
    docRef: DocRef('docs/setup.md', '### Kakao 로그인 켜기'),
    consoleUrl: 'https://developers.kakao.com/console/app',
  ),
  ProviderEntry(
    token: 'naver',
    displayName: 'Naver',
    docRef: DocRef('docs/setup.md', '### Naver 로그인 켜기'),
    consoleUrl: 'https://developers.naver.com',
  ),
  ProviderEntry(
    token: 'line',
    displayName: 'LINE',
    docRef: DocRef('docs/setup.md', '### LINE 로그인 켜기'),
    consoleUrl: 'https://developers.line.biz/console/',
  ),
];

/// [token] 의 표 행을 찾는다 — 없으면 null.
ProviderEntry? findProvider(String token) {
  for (final ProviderEntry entry in providerCatalog) {
    if (entry.token == token) return entry;
  }
  return null;
}

/// CSV 를 표에 있는 토큰(표 순서)과 모르는 토큰(나온 순서)으로 나눈다.
///
/// 앞뒤 공백을 떼고 빈 토큰은 버리며 중복은 한 번만 센다.
({List<String> known, List<String> unknown}) parseProviderCsv(String csv) {
  final seen = <String>{};
  final unknown = <String>[];
  for (final String raw in csv.split(',')) {
    final String token = raw.trim();
    if (token.isEmpty || !seen.add(token)) continue;
    if (findProvider(token) == null) unknown.add(token);
  }
  return (
    known: <String>[
      for (final ProviderEntry entry in providerCatalog)
        if (seen.contains(entry.token)) entry.token,
    ],
    unknown: unknown,
  );
}

/// [tokens] 를 표 순서의 CSV 로 만든다 — 표에 없는 토큰은 뺀다.
String formatProviderCsv(Iterable<String> tokens) {
  final Set<String> wanted = tokens.toSet();
  return <String>[
    for (final ProviderEntry entry in providerCatalog)
      if (wanted.contains(entry.token)) entry.token,
  ].join(',');
}

/// 켠 로그인 수단을 한 줄로 적는다 — `이메일만` 또는 `이메일 + Google · Kakao`.
String describeProviders(Iterable<String> tokens) {
  final Set<String> wanted = tokens.toSet();
  final names = <String>[
    for (final ProviderEntry entry in providerCatalog)
      if (wanted.contains(entry.token)) entry.displayName,
  ];
  return names.isEmpty ? '이메일만' : '이메일 + ${names.join(' · ')}';
}

/// [jsonPath] config 에서 켠 로그인 수단 토큰을 읽는다.
///
/// 파일이 없거나 읽지 못하거나 키가 없으면 빈 집합이다. 모르는 토큰은 뺀다 —
/// 로그인 수단 단계가 따로 알린다.
Set<String> readEnabledProviders(String jsonPath) {
  final file = File(jsonPath);
  if (!file.existsSync()) return const <String>{};
  final String? csv;
  try {
    csv = readJsonString(jsonPath, enabledProvidersKey);
  } on FileSystemException {
    return const <String>{};
  }
  if (csv == null) return const <String>{};
  return parseProviderCsv(csv).known.toSet();
}
