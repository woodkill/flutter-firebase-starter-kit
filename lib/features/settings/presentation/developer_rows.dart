// 설정 「개발자」 묶음에 더하는 내 개발용 행 목록 — 내 앱의 파일이다(킷 판은 빈 목록).
import 'package:flutter/widgets.dart';

/// 설정 화면 「개발자」 묶음에서 「개발자 · 데모 화면」 행 뒤에 펼칠 내 개발용 행을 만든다.
///
/// - 행 위젯은 `lib/features/<내 feature>/` 에 두고 이 파일에서 import 해 목록에 더한다.
/// - release 빌드에서는 「개발자」 묶음째 화면에서 빠진다. flavor 처럼 행마다 다른
///   조건은 목록 안에 `if (AppConfig.isDev) const MyDevToolRow(),` 꼴로 더한다.
/// - 묶음은 화면에서만 빠지고 행 코드는 release 앱에 남을 수 있으므로 비밀 값을 행에
///   넣지 않는다.
/// - 킷은 이 파일을 고치지 않는다. 킷 설정 시험 · golden 은 이 목록 대신 빈 목록을
///   넘겨 그린다(`SettingsScreen.developerRows`).
/// - 안내: `docs/guide.md` 「바꿀 수 있는 지점」 의 「설정 「개발자」 묶음에 개발용 행 더하기」.
List<Widget> buildAppDeveloperRows() => <Widget>[
  // 예: if (AppConfig.isDev) const MyDevToolRow(),
];
