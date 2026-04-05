import 'package:flutter_starter_kit/core/bootstrap.dart';

/// 앱 엔트리포인트.
///
/// [bootstrap]을 호출하여 초기화 시퀀스를 시작한다.
/// flavor는 `--dart-define-from-file`로 주입된
/// `String.fromEnvironment('flavor')`에서 읽는다.
void main() {
  bootstrap();
}
