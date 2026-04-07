import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

// Task 1 단계 placeholder.
//
// `_mapFirebaseUser`는 `auth_repository.dart`의 file-private 함수이므로
// 외부 테스트 파일에서 직접 호출할 수 없다 (Dart library privacy 규칙).
// 따라서 매퍼의 실제 동작 검증은 Task 3에서 작성될 `signInWithEmail` 성공
// 케이스 (모든 필드 / null email / null creationTime) 3종으로 통합 검증된다.
//
// 본 placeholder는 Task 1 단계에서도 파일이 컴파일되고 테스트 명령이
// 종료 코드 0을 반환하도록 유지하기 위한 smoke 테스트이다.
void main() {
  group('AuthRepository (Task 1 skeleton smoke)', () {
    test('AuthRepository는 FirebaseAuth 의존성을 받아 인스턴스화된다', () {
      final mockAuth = _MockFirebaseAuth();

      // Task 1 단계에서는 메서드가 비어 있으므로 인스턴스화만 검증한다.
      // 실제 동작 검증은 Task 3에서 추가된다.
      final repository = AuthRepository(mockAuth);
      expect(repository, isNotNull);
    });
  });
}
