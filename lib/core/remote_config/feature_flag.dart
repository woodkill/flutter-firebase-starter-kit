import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

/// Remote Config 로 켜고 끄는 typed Feature Flag 목록 (Phase 17 D-08).
///
/// 각 항목은 Remote Config 키 문자열과 기본값(`bool` 또는 `String`)을 함께
/// 갖는다. 기본값은 bootstrap 의 `setDefaults` 에 그대로 합산되어(D-11)
/// Remote Config 를 한 번도 가져오지 못한 상태에서도 앱 동작을 결정한다.
///
/// **커스터마이징 포인트 (manual):**
/// - 스위치 추가 = 이 enum 에 항목 1줄 (`myFeatureEnabled('my_feature_enabled',
///   false)`) — 콘솔에 같은 키를 만들고 [FeatureFlagValues.boolValue] 로 읽는다.
/// - 공지 언어 추가 = 이 enum 에 `announcementMessageXx` 1줄 +
///   [announcementMessageFlagFor] 의 `switch` 에 1줄.
///
/// 인증 provider kill switch(`auth_provider_*_enabled`)는 이 enum 이 아니라
/// 기존 `rcKeyForProvider` 경로가 담당한다 — 두 경로는 공존한다.
enum FeatureFlag {
  /// 홈 공지 배너 스위치 (D-09) — false 면 문구가 있어도 배너가 없다.
  announcementBannerEnabled('announcement_banner_enabled', false),

  /// 홈 공지 문구 — 한국어 앱 (D-36).
  announcementMessageKo('announcement_message_ko', ''),

  /// 홈 공지 문구 — 영어 앱 · 다른 언어 칸이 비었을 때의 대체 문구 (D-36).
  announcementMessageEn('announcement_message_en', ''),

  /// 홈 공지 문구 — 일본어 앱 (D-36).
  announcementMessageJa('announcement_message_ja', '');

  /// [key] 와 [defaultValue] 로 flag 를 정의한다.
  const FeatureFlag(this.key, this.defaultValue);

  /// Remote Config 매개변수 키.
  final String key;

  /// Remote Config 기본값 — `bool` 또는 `String` 이다.
  final Object defaultValue;
}

/// 앱 언어 [locale] 의 공지 문구 flag 를 고른다 (D-36).
///
/// ko · ja 는 각자의 칸, 그 밖의 언어는 en 칸이다. 언어를 추가하면 이
/// `switch` 에 1줄을 더한다.
FeatureFlag announcementMessageFlagFor(Locale locale) {
  return switch (locale.languageCode) {
    'ko' => FeatureFlag.announcementMessageKo,
    'ja' => FeatureFlag.announcementMessageJa,
    _ => FeatureFlag.announcementMessageEn,
  };
}

/// [FeatureFlag] 별 현재 값 묶음 (불변).
///
/// 지정하지 않은 flag 와 타입이 맞지 않는 값은 [FeatureFlag.defaultValue] 로
/// 읽는다.
@immutable
class FeatureFlagValues {
  /// flag → 값 맵으로 값 묶음을 만든다.
  const FeatureFlagValues(this._values);

  /// 모든 flag 가 기본값인 묶음 — Firebase 미초기화 · 가져오기 전 상태다.
  static FeatureFlagValues get defaults =>
      FeatureFlagValues(<FeatureFlag, Object>{
        for (final flag in FeatureFlag.values) flag: flag.defaultValue,
      });

  final Map<FeatureFlag, Object> _values;

  /// bool flag [flag] 의 값을 읽는다.
  bool boolValue(FeatureFlag flag) {
    final value = _values[flag];
    if (value is bool) return value;
    final fallback = flag.defaultValue;
    assert(fallback is bool, '${flag.key} 는 bool flag 가 아니다');
    return fallback is bool && fallback;
  }

  /// String flag [flag] 의 값을 읽는다 — 가공(trim · 정규화) 없이 그대로다.
  String stringValue(FeatureFlag flag) {
    final value = _values[flag];
    if (value is String) return value;
    final fallback = flag.defaultValue;
    assert(fallback is String, '${flag.key} 는 String flag 가 아니다');
    return fallback is String ? fallback : '';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FeatureFlagValues) return false;
    return FeatureFlag.values.every(
      (flag) => _valueOf(flag) == other._valueOf(flag),
    );
  }

  @override
  int get hashCode => Object.hashAll(FeatureFlag.values.map(_valueOf));

  Object _valueOf(FeatureFlag flag) => _values[flag] ?? flag.defaultValue;
}

/// 홈 공지 배너에 표시할 문구를 결정한다 (D-09 · D-36).
///
/// [FeatureFlag.announcementBannerEnabled] 가 false 면 null. 켜져 있으면 앱
/// 언어 [locale] 칸 → 비면 en 칸 → en 도 비면 null(배너 없음)이다. 공백만
/// 있는 칸은 빈 칸으로 본다 — 빈 배너를 그리지 않는다 (리뷰 IN-12). 표시할
/// 문구는 자르거나 다듬지 않고 원문 그대로 돌려준다(D-36 — 판정만 trim).
String? resolveAnnouncementText(FeatureFlagValues values, Locale locale) {
  if (!values.boolValue(FeatureFlag.announcementBannerEnabled)) return null;
  final localized = values.stringValue(announcementMessageFlagFor(locale));
  if (localized.trim().isNotEmpty) return localized;
  final english = values.stringValue(FeatureFlag.announcementMessageEn);
  return english.trim().isEmpty ? null : english;
}
