// 약관 동의 묶음 필수 확인 행 자리의 행 타입 · 입력 객체 · builder 꼴 — 킷 파일이다
// (내 행은 app_terms_confirmations.dart 에 둔다).
import 'package:flutter/widgets.dart';

/// 약관 동의 묶음에 더할 필수 확인 행 목록을 만드는 함수 꼴이다.
///
/// 행 문구는 [AppTermsConfirmationsInput.context] 로 내 ARB 문구
/// (`input.context.l10n`)를 읽어 만든다.
typedef AppTermsConfirmationsBuilder =
    List<AppTermsConfirmation> Function(AppTermsConfirmationsInput input);

/// 필수 확인 행 목록을 만드는 함수가 받는 값이다.
///
/// 지금은 [context] 하나다. 킷이 나중에 더하는 값은 기본값이 있는 선택 인자로
/// 더한다 — 이 객체를 받는 내 함수는 그대로 컴파일된다.
@immutable
class AppTermsConfirmationsInput {
  /// [AppTermsConfirmationsInput] 을 생성한다.
  const AppTermsConfirmationsInput({required this.context});

  /// 약관 슬라이드를 그리는 자리의 context — 내 ARB 문구를 읽는 데 쓴다.
  final BuildContext context;
}

/// 약관 동의 묶음의 필수 확인 행 하나 — 행 문구와 체크하지 않았을 때의 안내다.
///
/// - 행은 개인정보처리방침 아래 · 마케팅 위에 [필수] 배지와 함께 그려지고,
///   「상세 보기」 는 없다. 행이 여럿이면 목록 순서대로 그린다.
/// - 이 행을 모두 체크해야 「시작하기」 로 진행한다. 「전체 동의」 가 이 행도
///   함께 켜고 끈다.
/// - 킷이 나중에 필드를 더할 때는 기본값 있는 선택 인자로 더한다 — 이 행을
///   만드는 내 코드는 그대로 컴파일된다.
@immutable
class AppTermsConfirmation {
  /// [AppTermsConfirmation] 을 생성한다.
  const AppTermsConfirmation({required this.label, this.missingHint});

  /// 행 문구 — 내 ARB 키로 만든 문구다.
  final String label;

  /// 이 행을 체크하지 않고 「시작하기」 를 눌렀을 때 행 아래에 오류 색으로 보일
  /// 안내다.
  ///
  /// null 이면 행 안내 없이 묶음 아래 공통 문구만 보인다.
  final String? missingHint;
}
