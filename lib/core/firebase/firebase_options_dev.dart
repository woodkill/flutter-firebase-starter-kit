// 이 파일은 `./scripts/firebase-configure.sh dev` 로 재생성됩니다.
// 현재는 placeholder이며, Firebase 프로젝트 연결 후 실제 값으로 대체됩니다.
//
// placeholder 를 tracked 로 두는 이유: 이 파일이 repo 에 없으면 fresh clone /
// worktree 직후 `firebase_initializer.dart` 의 import 가 `uri_does_not_exist`
// 로 깨져 analyze/build 게이트 전체가 오염된다 (stg/prod 와 동일한 패턴).
//
// 재생성된 실제 옵션 파일이 실수로 커밋되지 않도록 두 겹의 가드가 있다.
//   1. `./scripts/firebase-configure.sh` 가 생성 직후 `git update-index
//      --skip-worktree` 를 적용한다.
//   2. `scripts/git-hooks/pre-commit` 이 FlutterFire CLI 생성 마커를 감지해
//      커밋을 거부한다.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// dev 환경 Firebase 설정 placeholder.
///
/// `./scripts/firebase-configure.sh dev` 로 실제 옵션 파일을 재생성한다.
class DefaultFirebaseOptions {
  /// 현재 플랫폼에 맞는 Firebase 옵션을 반환한다.
  ///
  /// placeholder 상태에서는 항상 [UnsupportedError] 를 던진다. 호출자
  /// (`initializeFirebase`) 는 이를 "미연결" 로 해석해 앱을 Firebase 없이
  /// 정상 실행한다.
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'dev 환경 Firebase 프로젝트가 아직 연결되지 않았습니다. '
      './scripts/firebase-configure.sh dev 를 실행하세요.',
    );
  }
}
