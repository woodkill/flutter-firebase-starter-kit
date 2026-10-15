import '../step.dart';
import 'identity_step.dart';
import 'login_step.dart';
import 'tools_step.dart';
import 'user_files_step.dart';
import 'xcode_step.dart';

/// 개발(dev) 환경을 준비하는 단계 목록을 순서대로 만든다.
///
/// 위저드는 이 순서대로 검사하고 진행한다. 새 단계는 진행 순서에 맞는 자리에
/// 끼운다.
List<Step> buildDevSteps() => <Step>[
  XcodeStep(),
  ToolsStep(),
  UserFilesStep(),
  IdentityStep(),
  LoginStep(),
];
