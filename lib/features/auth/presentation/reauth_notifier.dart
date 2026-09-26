import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/auth/auth_strategy.dart';
import '../../../core/auth/provider_id.dart';
import '../../../core/error/result.dart';
import '../data/auth_repository.dart';
import '../domain/user.dart';

part 'reauth_notifier.g.dart';

/// 재인증 모드 로그인 화면이 쓸 수 있는 수단 (debug reauth-login-auto-merge).
///
/// [strategies] 는 활성 소셜 Strategy 중 현재 계정에 **이미 연결된** 것만
/// registry 순서 그대로 담는다. 연결 안 된 provider 를 노출하면 그 버튼이
/// 다른 계정 전환 · 같은 email 자동 합류 · 무동의 연결의 입구가 된다.
/// [hasPassword] 는 비밀번호(`password`) 연결 여부다.
typedef ReauthMethods = ({List<AuthStrategy> strategies, bool hasPassword});

/// 현재 계정 [user] 와 활성 [activeStrategies] 로 재인증 수단을 계산한다.
///
/// `User.providerIds` 는 native URI 형식(`google.com` · `apple.com` ·
/// `facebook.com` · `password`) 과 Custom Token slug(`kakao` 등) 의
/// 합집합이다 (`currentUserProvider` D-16). URI · slug 모두
/// [AccountProvider.tryParse] 가 인식한다 (Phase 16.7 — 매핑 단일화). 재인증은
/// `password` 도 수단이라 제외하지 않는다. [user] 가 null 이면 수단 0 이다.
ReauthMethods resolveReauthMethods(
  User? user,
  List<AuthStrategy> activeStrategies,
) {
  final linked = <AccountProvider>{
    for (final providerId in user?.providerIds ?? const <String>[])
      ?AccountProvider.tryParse(providerId),
  };
  return (
    strategies: <AuthStrategy>[
      for (final strategy in activeStrategies)
        if (linked.contains(AccountProvider.tryParse(strategy.providerId)))
          strategy,
    ],
    hasPassword: linked.contains(AccountProvider.email),
  );
}

/// 재인증 모드 소셜 버튼의 재인증 상태를 관리한다
/// (debug reauth-login-auto-merge).
///
/// 상태 계약 (`AsyncValue<bool>`):
/// - `AsyncData(false)` — 초기 · 사용자 취소 (화면 이동 없음).
/// - `AsyncLoading` — [AuthRepository.reauthenticate] 진행 중.
/// - `AsyncData(true)` — 같은 계정으로 재인증 완료.
/// - `AsyncError` — 실패 ([ReauthUserMismatch] 포함 [AppException]).
///
/// 일반 로그인 notifier (`*SignInNotifier`) 와 분리한 이유: 그 notifier 들은
/// 새 로그인을 호출하고 취소 · 성공을 같은 `AsyncData(null)` 로 표현해,
/// 재인증 화면이 "취소도 성공처럼 홈 이동" 하던 원인이었다.
@riverpod
class SocialReauthNotifier extends _$SocialReauthNotifier {
  @override
  FutureOr<bool> build() => false;

  /// [provider] 로 현재 계정을 재인증한다. 진행 중 재호출은 무시한다.
  Future<void> reauthenticate(AccountProvider provider) async {
    if (state is AsyncLoading) return;
    state = const AsyncLoading<bool>();
    final result = await ref
        .read(authRepositoryProvider)
        .reauthenticate(provider);
    if (!ref.mounted) return;
    state = switch (result) {
      null => const AsyncData<bool>(false),
      Success<User>() => const AsyncData<bool>(true),
      Failure<User>(exception: final ex) => AsyncError<bool>(
        ex,
        StackTrace.current,
      ),
    };
  }
}

/// 재인증 모드 이메일 화면의 비밀번호 재인증 상태를 관리한다
/// (debug reauth-login-auto-merge).
///
/// 상태 계약은 [SocialReauthNotifier] 와 같다 (취소 상태만 없음). 선택 화면이
/// 진행 중 여부를 watch 해 소셜 버튼을 잠그고, 완료 처리는 이메일 화면이
/// `pop(true)` 로 선택 화면에 넘긴다 — 두 화면이 같은 성공 신호로 이중 이동
/// 하지 않게 한다.
@riverpod
class PasswordReauthNotifier extends _$PasswordReauthNotifier {
  @override
  FutureOr<bool> build() => false;

  /// [password] 로 현재 계정을 재인증한다. 진행 중 재호출은 무시한다.
  Future<void> reauthenticate({required String password}) async {
    if (state is AsyncLoading) return;
    state = const AsyncLoading<bool>();
    final result = await ref
        .read(authRepositoryProvider)
        .reauthenticateWithPassword(password: password);
    if (!ref.mounted) return;
    state = switch (result) {
      Success<User>() => const AsyncData<bool>(true),
      Failure<User>(exception: final ex) => AsyncError<bool>(
        ex,
        StackTrace.current,
      ),
    };
  }
}
