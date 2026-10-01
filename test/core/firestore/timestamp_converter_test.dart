import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/firestore/timestamp_converter.dart';

void main() {
  group('Phase 17 FCM 토큰 저장소 (T-17-FCM)', () {
    const converter = TimestampConverter();

    test('T-17-FCM-01: DateTime → Timestamp → DateTime 왕복이 UTC 밀리초 '
        '동일', () {
      final original = DateTime.utc(2026, 10, 1, 12);

      final timestamp = converter.toJson(original);
      final restored = converter.fromJson(timestamp);

      expect(timestamp, isA<Timestamp>());
      expect(restored.isUtc, isTrue);
      expect(restored.millisecondsSinceEpoch, original.millisecondsSinceEpoch);
      expect(restored, original);
    });

    test('T-17-FCM-01: local DateTime 도 같은 instant 의 UTC 로 복원된다', () {
      final local = DateTime(2026, 10, 1, 21, 30);

      final restored = converter.fromJson(converter.toJson(local));

      expect(restored.isUtc, isTrue);
      expect(restored.millisecondsSinceEpoch, local.millisecondsSinceEpoch);
    });
  });
}
