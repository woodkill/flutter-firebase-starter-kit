// 위저드가 ARB 파일의 `appTitle`(언어별 앱 이름)을 다루는 도우미.
//
// 어느 ARB 를 어떤 locale 로 읽는가는 빌드 생성기(`tool/launcher_names.dart`)의
// 공개 함수를 그대로 쓴다 — 위저드가 묻는 파일 집합과 빌드가 읽는 집합이 같다.
import '../launcher_names.dart'
    show L10nConfig, listArbFiles, localeFromArbFileName, readL10nConfig;

/// template(영어) 밖 ARB 파일 하나 — locale 과 두 경로.
final class LocalizedArb {
  /// [locale] · [relativePath] · [absolutePath] 로 ARB 파일 하나를 나타낸다.
  const LocalizedArb(this.locale, this.relativePath, this.absolutePath);

  /// 파일 이름에서 읽은 locale(`ko` · `pt_BR` · `zh_Hant`).
  final String locale;

  /// 프로젝트 루트 기준 경로(`lib/l10n/app_ko.arb`) — 화면 문구에 쓴다.
  final String relativePath;

  /// 읽기 · 쓰기에 쓰는 절대 경로.
  final String absolutePath;
}

/// [projectRoot] 의 `l10n.yaml` 이 가리키는 ARB 가운데 template 밖 파일을 돌려준다.
///
/// 순서는 파일 경로 순(ja → ko → pt → pt_BR → zh_Hant)이다. `l10n.yaml` 이
/// 없거나 · 파일 이름 꼴이 어긋나면 생성기와 같은 `GeneratorException` 을 그대로
/// 올린다 — 부르는 쪽이 그 문구를 사유로 보인다.
List<LocalizedArb> listLocalizedArbs(String projectRoot) {
  final L10nConfig config = readL10nConfig(projectRoot);
  return <LocalizedArb>[
    for (final file in listArbFiles(projectRoot, config))
      if (file.uri.pathSegments.last != config.templateArbFile)
        LocalizedArb(
          localeFromArbFileName(
            file.uri.pathSegments.last,
            config.arbFilePrefix,
            config.arbDir,
          ),
          '${config.arbDir}/${file.uri.pathSegments.last}',
          file.path,
        ),
  ];
}
