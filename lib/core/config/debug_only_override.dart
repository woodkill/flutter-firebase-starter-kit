/// 테스트 전용 override 필드를 debug/profile 빌드에서만 기록하는 공용 헬퍼.
///
/// `assert` 표현식은 debug/profile 빌드에서만 평가되므로, 부작용을 IIFE 로
/// 감싸 `assert` 안에 두면 **release 빌드에서는 write 자체가 실행되지 않는다**
/// (Phase 10 WR-02 방어 패턴). 프로덕션 코드가 실수로 테스트 seam 에 대입해도
/// 릴리스 동작이 오염되지 않는다.
library;

/// [value] 를 [write] 로 기록하되, release 빌드에서는 아무것도 하지 않는다.
///
/// [message] 는 assert 실패 시 표시할 설명이다 (실제로는 IIFE 가 항상 true 를
/// 반환하므로 발동하지 않으며, 의도를 코드에 남기는 용도다).
///
/// 코드 리뷰 IN-07: 이 IIFE 는 `SplashConfig` 와 `AuthRetryConfig` 두 곳에
/// verbatim 복제되어 있었다. 한 곳으로 모아 패턴이 갈라지지 않게 한다.
///
/// ```dart
/// @visibleForTesting
/// static set overrideMinDuration(Duration? value) => writeIfDebug<Duration?>(
///   (v) => _overrideMinDuration = v,
///   value,
///   'overrideMinDuration must not be set outside debug/test builds',
/// );
/// ```
void writeIfDebug<T>(void Function(T) write, T value, String message) {
  assert(() {
    write(value);
    return true;
  }(), message);
}
