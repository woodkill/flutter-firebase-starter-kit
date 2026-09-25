// IN-01 정정 (Phase 7 review): `Locale` import 폐기 — 유일한 소비처였던
// `defaultPriorityFor(Locale)` 가 dead API 로 제거됐다 (SOCL-10 폐기).
// 로케일별 우선순위를 재도입한다면 이 import 와 메서드를 함께 되살린다.
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 소셜 로그인 Strategy — Provider 식별 + signIn delegation 책임만 보유
/// (Phase 11 D-10).
///
/// 버튼 렌더링은 [SocialButton] 책임 (Phase 11-04). `lib/core/auth` (도메인)
/// ↔ `lib/features/auth/presentation` (UI) 경계 명확.
///
/// **Phase 9.1 race-fix 의무 (D-15, Pitfall 8):** 기존 `*SignInNotifier` 위임
/// 구현체 ([GoogleAuthStrategy] / [AppleAuthStrategy] / [FacebookAuthStrategy])
/// 는 `AuthRepository` 가 이미 `socialLinkInProgress.begin/end` 를 try-finally
/// 로 호출한다. Strategy 단계에서 **추가 begin/end 호출 절대 금지** — 이중
/// begin race 회귀 (T-11-RACE-01) 가 발생한다.
///
/// Phase 12+ Custom Token Strategy 가 `AuthRepository` 외부에서 Custom Token
/// 호출을 직접 수행하는 경우에는 Strategy 의 `signIn` 안에서 try-finally 로
/// `socialLinkInProgress.begin/end` 호출 의무.
///
/// **반환 타입 결정 (Q&A):** `Future<void>` — `*SignInNotifier` 가
/// `AsyncValue<void>` 만 노출하므로 Result 이중 진실을 회피한다. UI 는
/// `ref.listen(googleSignInProvider, ...)` 등 Notifier 의 [AsyncValue] 로
/// success/error 분기 (Phase 11-04 마이그레이션).
///
/// **IN-01 정정 (Phase 7 review) — dead API 2종 제거:** `iconAsset` 은
/// production 참조 0건이었다 (실제 렌더는 `branded_social_button.dart` 의
/// [BrandSpec] 분기가 단일 진실원). `defaultPriorityFor` 는 override 0건 +
/// 호출 0건이었다 (SOCL-10 폐기). 두 멤버가 7 strategy + 7 테스트 파일에
/// 반복 선언/검증되어 provider 추가 시마다 의미 없는 14파일 수정을
/// 유발했으므로 제거했다. 로케일 우선순위 재도입 진입점은
/// [activeStrategies] 문서에 있다.
abstract class AuthStrategy {
  /// `const` 생성자 — 구현체는 모두 stateless / immutable.
  const AuthStrategy();

  /// 도메인 ProviderId — 단순 slug 형식 (D-20, Phase 11-04 hotfix).
  ///
  /// `'google'` / `'apple'` / `'facebook'` / `'kakao'` / `'naver'` / `'line'`.
  /// 정적 config key
  /// (`authProvider_{providerId}_enabled`) 와 Remote Config 키
  /// (`auth_provider_{providerId}_enabled`) prefix 모두 이 슬러그를 직접 사용.
  ///
  /// **Firebase Auth providerId 와 분리**: `User.providerData[i].providerId`
  /// 가 노출하는 OAuth URI 형식 (`'google.com'` 등) 은 Firebase 가 자체적으로
  /// 반환하는 외부 식별자이며 도메인 식별자가 아니다. URI ↔ slug 매핑은
  /// boundary ([provider_label_formatter]) 에서만 처리한다.
  String get providerId;

  /// ARB 키 (예: `'authGoogleSignIn'`).
  String get labelKey;

  /// 로그인 실행 진입점.
  ///
  /// 위임 대상 Notifier 가 `AsyncValue<void>` 로 상태를 노출한다. UI 는
  /// `ref.listen(*SignInProvider, ...)` 으로 success/error 를 구독한다.
  ///
  /// **인자 타입 결정 (Phase 11-04, Rule 1 fix):** Riverpod 3.x 에서
  /// `ConsumerWidget` 의 [WidgetRef] 와 Provider 내부 [Ref] 는 별개 타입이며
  /// 호환되지 않는다. UI ([SocialButton]) 진입점이 직접 호출하므로
  /// [WidgetRef] 를 받는다. Strategy 구현체는 `ref.read(...).signInWith...()`
  /// 위임만 수행하며, [WidgetRef] 의 `read` 가 충분하다.
  Future<void> signIn(WidgetRef ref);
}
