// 설정 화면에 더하는 내 앱 고유 묶음 목록 — 내 앱의 파일이다(킷 판은 빈 목록).
import 'package:flutter/widgets.dart';

import 'app_settings_slot.dart';

/// 설정 화면에서 알림 섹션 뒤 · 「개발자」 묶음 앞에 그릴 내 앱 고유 묶음을 만든다.
///
/// - 묶음 하나는 `AppSettingsSection(title: …, rows: […])` 이다. 제목은 내 ARB
///   키(`context.l10n.<키>`)로 만들고, 행 위젯은 `lib/features/<내 feature>/` 에
///   두고 이 파일에서 import 한다.
/// - 게스트(익명)에게 숨길 묶음 · 행은 앞에 `if (!isAnonymous)` 를 붙인다.
/// - release 빌드에서도 보인다. 개발 중에만 쓰는 행은 `developer_rows.dart` 에
///   둔다.
/// - 킷은 이 파일을 고치지 않는다. 설정 화면을 직접 그리는 킷 설정 시험 ·
///   golden 은 이 함수 대신 빈 목록을 돌려주는 함수를 넘겨 그린다
///   (`SettingsScreen.appSectionsBuilder`).
/// - 안내: `docs/guide.md` 「설정 화면에 앱 고유 묶음 · 행 더하기」.
List<AppSettingsSection> buildAppSettingsSections(
  BuildContext context, {
  required bool isAnonymous,
}) => <AppSettingsSection>[
  // 예: AppSettingsSection(title: context.l10n.mySection, rows: const [MyRow()]),
];
