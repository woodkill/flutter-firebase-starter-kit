// Phase 16.8 D-03 · D-05 · D-11 · D-19 — 연결된 계정 해제 버튼 여부 규칙.
//
// 설정 「내 계정」 「연결된 계정」 값에서 어느 provider 이름을 밑줄 해제 버튼으로
// 그릴지 정하는 provider 중립 순수 함수. 위젯 · notifier 어디에도 같은 조건을
// 다시 쓰지 않는다 — 해제 가능 규칙을 바꾸려면 이 파일 한 곳만 고친다.
import '../../../core/auth/provider_id.dart';
import '../../auth/domain/user.dart';

/// [user] 의 연결된 계정 [providerId] 를 설정 화면에서 해제할 수 있는지
/// 판정한다 (Phase 16.8 D-03 · D-05 · D-11 · D-19).
///
/// 아래 3조건이 모두 참일 때만 `true`:
/// 1. 가입 수단 기록이 있다 (`signUpProviderId` non-null — D-05). null 은
///    첫 emit 전 · Firestore 읽기 실패 fallback 이라 가입 수단이 연결된 계정
///    목록에 섞여 있을 수 있다 → 전부 일반 텍스트.
/// 2. 자격증명이 2개 이상이다 (`providerIds` 길이 ≥ 2 — D-03). 1개면 그것을
///    해제하는 순간 로그인 수단 0 계정이 된다(가입 기록 덮어쓰기 사례). 이
///    조건은 행 전체에 같은 값으로 적용된다.
/// 3. id 가 식별된다 (`AccountProvider.tryParse` non-null — D-11). 미지 값은
///    native/CT 라우팅과 다이얼로그 문구를 정할 수 없어 일반 텍스트다. 해제
///    가능 · 불가 이름이 한 행에 섞이는 경우는 이 조건에서만 생긴다.
///
/// **연결 가능 집합 목록을 조건으로 쓰지 않는 이유 (D-04 provider 중립 ·
/// D-19):** 연결된 계정에 나타난 provider 는 어떤 것이든 같은 규칙으로
/// 해제할 수 있어야 한다. 목록을 조건에 넣으면 새 provider(예: Naver 연결이
/// 생길 때)마다 이 함수를 고쳐야 하고, 빠뜨리면 해제 경로가 조용히 사라진다.
///
/// 가입 수단 자체는 `splitAccountProviders` 가 연결된 계정 목록에서 이미
/// 뺐으므로 여기로 오지 않는다 — 가입 수단을 없애는 방법은 회원탈퇴뿐이다
/// (D-01).
bool canUnlinkProvider(User? user, String providerId) {
  if (user == null) return false;
  return user.signUpProviderId != null &&
      user.providerIds.length >= 2 &&
      AccountProvider.tryParse(providerId) != null;
}
