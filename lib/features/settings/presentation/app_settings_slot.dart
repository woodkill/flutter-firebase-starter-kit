// 설정 화면 앱 고유 묶음 자리의 묶음 타입과 builder 꼴 — 킷 파일이다(내 묶음은
// app_settings_sections.dart 에 둔다).
import 'package:flutter/widgets.dart';

/// 설정 화면에 그릴 앱 고유 묶음 목록을 만드는 함수 꼴이다.
///
/// [context] 로 내 ARB 문구(`context.l10n`)를 읽는다. `isAnonymous` 는 지금
/// 사용자가 게스트(익명)인지다 — 설정 화면이 계산해 넘긴다(인증 상태를 읽는
/// 중 · 읽기 오류는 false).
typedef AppSettingsSectionsBuilder =
    List<AppSettingsSection> Function(
      BuildContext context, {
      required bool isAnonymous,
    });

/// 설정 화면의 앱 고유 묶음 하나 — 묶음 제목과 그 아래 행 목록이다.
///
/// 설정 화면이 묶음마다 간격 · 묶음 제목 · 행을 차례로 그린다. 행이 없는 묶음은
/// 제목도 그리지 않는다. 행 위젯은 설정 목록의 행으로 그대로 들어간다.
@immutable
class AppSettingsSection {
  /// [AppSettingsSection] 을 생성한다.
  const AppSettingsSection({required this.title, required this.rows});

  /// 묶음 제목 — 내 ARB 키로 만든 문구다.
  final String title;

  /// 묶음 행 — 위에서부터 화면 순서다.
  final List<Widget> rows;
}
