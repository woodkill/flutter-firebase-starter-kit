import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'dismissed_announcement.g.dart';

/// 사용자가 닫은 홈 공지 문구를 기억하는 Notifier (Phase 17 D-12).
///
/// 「실제로 표시된 문구」 를 [SharedPreferences] 에 그대로 저장하고, 공지
/// 배너는 표시 문구가 이 값과 정확히 같을 때(Dart `==` — trim · 정규화 없음)만
/// 숨는다. 문구가 바뀌거나 언어 전환으로 다른 칸이 표시되면 다시 보인다.
///
/// 저장값을 읽기 전(loading)에는 배너를 그리지 않아 깜빡임이 없다. 읽기
/// 실패는 「닫은 적 없음」(null)으로, 쓰기 실패는 화면 상태만 갱신하고 넘어간다
/// — 공지 기억은 앱 사용을 막을 만큼 중요하지 않다.
@Riverpod(keepAlive: true)
class DismissedAnnouncementNotifier extends _$DismissedAnnouncementNotifier {
  /// 닫은 문구의 SharedPreferences 키.
  static const String storageKey = 'home_announcement_dismissed_text';

  @override
  Future<String?> build() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(storageKey);
    } on Object catch (e) {
      _debugLog('load', e);
      return null;
    }
  }

  /// 배너에 표시된 문구 [shownText] 를 닫은 문구로 기억한다.
  ///
  /// 화면에서는 즉시 사라지고(state 먼저 갱신), 저장은 그 뒤에 한다.
  Future<void> dismiss(String shownText) async {
    state = AsyncData(shownText);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, shownText);
    } on Object catch (e) {
      _debugLog('save', e);
    }
  }
}

/// debug 빌드에서만 실패 단계와 오류 타입을 남긴다 (문구 · release 로그 0).
void _debugLog(String stage, Object error) {
  if (kDebugMode) {
    debugPrint('dismissed_announcement $stage failed: ${error.runtimeType}');
  }
}
