# R10-FOLLOWUP-2 — `linkedProvidersStream` permission-denied race fix

**Created:** 2026-05-08
**Area:** client-side (`lib/features/auth/data/auth_repository.dart`)
**Phase context:** Phase 13 (Naver Login) 후속 — R6 → R9/R10/R12/R14 → R13 → R10-FOLLOWUP → **R10-FOLLOWUP-2**
**Discovered via:** T-13-UAT-NAVER-A1 후속 검증 (2026-05-08, R10-FOLLOWUP `b717d39` deploy 직후)

---

## 1. Problem

R10-FOLLOWUP fix (`b717d39`) 가 `findOrCreateUidForOAuth` helper 의 재로그인 path (isNewUser=false) 에 server-side `getAuth().updateUser(uid, profileFields)` 호출을 추가했다 (`functions/src/auth/identity_index.ts:186-227`). 이 호출이 client side 에서 다음 race window 를 노출한다:

1. server-side `updateUser` 가 Firebase Auth user record 변경 → client `onIdTokenChanged` emit 가능
2. `signInWithCustomToken` 직후 새 ID Token 검증 + Firestore SDK 의 token cache 갱신 propagate 사이의 짧은 timing window 가 존재
3. `linkedProvidersStream` listener 가 sign-in 직후 등록되면 stale token 으로 Firestore reach → `[cloud_firestore/permission-denied] The caller does not have permission to execute the specified operation.`
4. 기존 `linkedProvidersStream` 의 `handleError` (R6 D-41 — 영구 spinner 회피 정책) 가 즉시 빈 배열 emit → `AsyncData([])` 정착
5. `currentUserProvider` 의 R13 fix (`linkedAsync.when(data, loading, error)`) 는 AsyncLoading 분기에서만 cached value 보존 → AsyncData([]) 분기는 그대로 합산 → UI "로그인 수단 = -" 표시

### Reproduction (2026-05-08 검증 데이터)

1. starter-kit dev 빌드 + Galaxy Z Fold6 (R3CY70431XT) 설치
2. Naver 계정으로 첫 로그인 (Phase 13 시나리오 2 의 uid `CUyumlgF…`)
3. logout → "네이버로 시작하기" 1-tap 재로그인
4. **결과**: photoURL 갱신 ✅ (R10-FOLLOWUP fix 검증), 프로바이더 "-" ❌ (본 race)
5. 앱 종료 → 다시 실행 (cold start, 이미 로그인) → 프로바이더 "네이버" 정상

logcat evidence (UTC 09:18:49):

```
I flutter : linkedProvidersStream 에러 (fallback empty):
  [cloud_firestore/permission-denied] The caller does not have permission
  to execute the specified operation.
```

server-side timeline (UTC):

- 09:18:41 Cloud Function instance start
- 09:18:43 `naver_custom_token_issued isNewUser=false` (R10-FOLLOWUP `updateUser` 실행 후 customToken 발급)
- 09:18:49 client linkedProvidersStream permission-denied (~6s 후 — Cloud Function cold start 시간 포함)

### Impact

- **사용자 경험**: 본 starter-kit 을 fork 한 production app 의 일반 사용자가 "재로그인" 시점에 첫 frame 의 EnvironmentInfoScreen 카드 "로그인 수단" 이 잠시 "-" 표시 → 이상한 UX (앱 재시작 시 정상 회복)
- **production blocker 아님**: 일시적 race, cold start 후 정상
- **starter-kit 완성도**: production-ready default 측면에서 fix 권장

---

## 2. Why R13 fix 가 cover 하지 않는가

R13 fix (commit `f4030f9`, `auth_repository.dart:912-967`) 는 `currentUserProvider` 에 `linkedAsync.when(data, loading, error)` 3-way pattern matching 을 적용한다:

- **AsyncLoading**: `linkedAsync.value` (직전 cached emit) 보존 → race 회복
- **AsyncError**: 빈 배열 fallback (영구 spinner 회피)

본 R10-FOLLOWUP-2 race 는 stream-level `handleError` 가 빈 배열을 emit 하므로 `AsyncData([])` 로 정착 — R13 의 Loading/Error 분기를 거치지 않는다. 즉, race 흡수 책임이 잘못된 계층에 있다.

---

## 3. Why Firestore SDK 의 자동 회복에 의존하지 못하는가

검증 결과 (2026-05-08, [flutterfire #11146](https://github.com/firebase/flutterfire/issues/11146), [firebase-android-sdk #5101](https://github.com/firebase/firebase-android-sdk/issues/5101), [flutterfire #4181](https://github.com/FirebaseExtended/flutterfire/issues/4181)):

> Firestore SDK ought to pick up the fresh auth token under the hood, and reattach the snapshot event listeners without the user having to do this step manually. **— firebase-android-sdk #5101 (open since 2023-06)**
>
> The only workaround currently available to users is to restart the app, a solution that is far from intuitive. **— flutterfire #11146**

**결론**: SDK 가 token cache 갱신 후 stream 자동 재구독을 하지 않는다 (known open bug). 권장 workaround 일치 — manual cancel + resubscribe.

이 사실로 인해 다음 옵션이 탈락:

- **handleError 에서 `permission-denied` rethrow + R13 error 분기 cached 보존**: 자동 재구독 가정에 의존 → cached value 영원히 stale
- **Subscribe 시점 지연 (onIdTokenChanged 첫 emit 후 stream 등록)**: SDK 내부 race 와 동일 표현 — listener reattach 가 ID Token refresh 전에 일어남이 #11146 의 root cause. heuristic. 추가로 cold start path (이미 로그인 상태) 도 영향, helper-1곳-fix (D-08) 위반

---

## 4. Solution — `linkedProvidersStream` 자체에 selective retry

### 4.1 Architecture / 변경 범위

- **변경 위치**: `lib/features/auth/data/auth_repository.dart::linkedProvidersStream` (1곳)
- **변경 형태**: 기존 stream factory style → `async*` generator 로 재작성
- **무수정**: `currentUserProvider` (R13 fix 보존)
- **helper-1곳-fix 모델 (D-08) 보존**: Phase 14 후속 OAuth Custom Token provider (LINE) 자동 상속

### 4.2 책임 경계

| 계층 | 책임 |
|---|---|
| `linkedProvidersStream` (data, stream level) | SDK 의 token cache propagate race 를 stream 내부에서 흡수 — `permission-denied` retry, 다른 에러 D-41 fallback |
| `currentUserProvider` (도메인, consumer level, R13 fix) | retry 중 직전 emit 의 cached value 를 UI 에 노출 — AsyncLoading 분기 유지 (yield 안 함) |

### 4.3 Retry 정책

- **선택 backoff**: 고정 1s × 5회 (총 5s envelope)
- **선택 근거**:
  - 실측 race window 는 server cold start 6s 포함 — Firestore SDK token cache propagate 자체는 sub-second 추정
  - 5s envelope 면 일반 propagate (sub-second) + cold start 보정 모두 cover
  - 단순함이 D-41 (영구 spinner 회피) 의도와 일치 — exponential backoff 는 envelope 만 늘리고 race 회복 시간은 동일

### 4.4 Data flow (5 시나리오)

| 시나리오 | linkedProvidersStream emit | currentUserProvider 분기 | UI 표시 |
|---|---|---|---|
| 정상 | `AsyncData([naver])` | `data` | "네이버" |
| 재로그인 race (1차) | retry 진입, yield 안 함 | `loading` (cached `AsyncData([naver])` 보존) | "네이버" (R13 cached fallback) |
| 재로그인 race recovery (1s 후) | `AsyncData([naver])` 재emit | `data` | "네이버" |
| 다른 FirebaseException (network 등) | `AsyncData([])` (D-41 fallback) | `data` | "-" (영구 spinner 회피) |
| retry exhausted (5회 = 5s) | `AsyncData([])` escape | `data` | "-" |

### 4.5 Implementation sketch

```dart
@Riverpod(keepAlive: true)
Stream<List<String>> linkedProvidersStream(Ref ref, String uid) async* {
  final firestore = ref.watch(firebaseFirestoreProvider);
  var permissionDeniedRetries = 0;
  const maxRetries = 5;
  const retryDelay = Duration(seconds: 1);

  while (true) {
    try {
      await for (final snap in firestore.collection('users').doc(uid).snapshots()) {
        permissionDeniedRetries = 0; // 정상 emit 도달 시 카운터 리셋
        if (!snap.exists) {
          yield const <String>[];
          continue;
        }
        final raw = snap.data()?['linkedProviders'] as List<dynamic>?;
        if (raw == null) {
          yield const <String>[];
          continue;
        }
        yield raw
            .whereType<Map<String, dynamic>>()
            .map((m) => m['providerId'] as String?)
            .whereType<String>()
            .toList(growable: false);
      }
      // source stream 정상 종료 (provider dispose 등) — loop 탈출
      break;
    } on FirebaseException catch (e, st) {
      if (e.code == 'permission-denied' && permissionDeniedRetries < maxRetries) {
        // R10-FOLLOWUP-2: sign-in 직후 SDK token cache propagate race.
        // 직전 cached value 유지 (yield 안 함) + 1s 후 재구독.
        // currentUserProvider 의 R13 fix (linkedAsync.value) 가 cached emit 보존.
        permissionDeniedRetries += 1;
        if (kDebugMode) {
          debugPrint(
            'linkedProvidersStream permission-denied retry '
            '$permissionDeniedRetries/$maxRetries: $e',
          );
        }
        await Future<void>.delayed(retryDelay);
        continue;
      }
      // (1) 다른 FirebaseException (network 등) — D-41 정책: 빈 배열 fallback.
      // (2) permission-denied 5회 retry 후에도 지속 — escape hatch (영구 spinner 회피).
      if (kDebugMode) {
        debugPrint('linkedProvidersStream 에러 (fallback empty): $e\n$st');
      }
      yield const <String>[];
      break;
    }
  }
}
```

### 4.6 Invariants

- **I1 (D-41 보존)**: 영구 spinner / 영구 "-" 회피 — escape hatch + 다른 에러 fallback 모두 빈 배열 emit
- **I2 (R13 호환)**: retry 중 yield 안 함 → consumer 의 AsyncLoading 분기 유지 → cached value 노출
- **I3 (카운터 리셋)**: 정상 emit 도달 시 retry 카운터 0 — 장기 세션에서 token 재만료 시 다시 retry 가능
- **I4 (Type-safe parsing)**: 기존 `whereType<Map<String, dynamic>>().whereType<String>()` filter 동일 보존

---

## 5. Testing — Layer 1 (회귀 가드)

위치: `test/features/auth/data/auth_repository_current_user_test.dart` (기존 `linkedProvidersStream` 회귀 가드 + R13 fix 회귀 가드가 위치한 파일)

신규 5 케이스:

| # | 시나리오 | mock 동작 | 기대 emit |
|---|---|---|---|
| 1 | 정상 emit (회귀) | Firestore mock `[{providerId: 'naver'}]` | `AsyncData(['naver'])` |
| 2 | permission-denied 1회 후 정상 (R10-FOLLOWUP-2 핵심) | 1차 throw `permission-denied`, 2차 정상 | 1s delay 후 `AsyncData(['naver'])` |
| 3 | permission-denied 5회 escape | 5회 연속 throw `permission-denied` | 5s 후 `AsyncData([])` |
| 4 | 다른 FirebaseException → 즉시 빈 배열 (D-41 보존) | throw `unavailable` | 즉시 `AsyncData([])` |
| 5 | 카운터 리셋 | 1회 throw → 1회 정상 → 다시 throw | retry 가능 (5회 누적 아님) |

기대 결과:

- `fvm flutter test` 695 → 700 PASS / 0 FAIL
- `fvm dart analyze` 0 issues

> **테스트 인프라 주의 (memory: feedback_mock_transaction_constraint)**: mock-test 가 SDK 의 정확한 race semantics 를 100% 재현하지는 않는다. 그러나 본 fix 는 transaction-level invariant 가 아닌 stream-level error handling 이므로 mock 으로 충분.

---

## 6. Defense layers

| Layer | 형태 | 위치 |
|---|---|---|
| Layer 1 | 회귀 가드 5 케이스 (위 §5) | `test/features/auth/data/auth_repository_current_user_test.dart` |
| Layer 2 | manual UAT row 갱신 | `.planning/phases/13-naver-login/13-HUMAN-UAT.md` A1 row 의 R10-FOLLOWUP 단락에 R10-FOLLOWUP-2 추가 — Naver 1-tap 재로그인 직후 첫 frame "로그인 수단 = 네이버" 정상 표시 (cold start 없이) |
| Layer 3 | escape hatch (코드 내장) | `maxRetries = 5` — 5s 후 빈 배열 fallback (D-41 영구 spinner 회피) |
| Doc | manual.md 단락 갱신 | `docs/manual.md` "## IdP 프로필 동기화 정책 (R10-FOLLOWUP)" 절에 R10-FOLLOWUP-2 race 명시 + retry 정책 (5회 × 1s) |

---

## 7. Why now (Backlog 가치)

- 일시적 race — 사용자 production 진입 시 manual.md 언급으로 인지 가능
- cold start 시 회복 — production blocker 아님
- starter-kit 완성도 ↑ — fork 사용자가 즉시 production-ready 상태 기대
- 후속 phase (Phase 14 LINE) 추가 시 동일 race 영향 → helper 1곳 fix → 모든 provider 자동 상속 (D-08)

---

## 8. References

### 본 race 발견 trigger

- R10-FOLLOWUP commit `b717d39` (2026-05-08) — `.planning/todos/completed/2026-05-08-relogin-idp-profile-propagation.md`
- R10-FOLLOWUP race trigger 위치: `functions/src/auth/identity_index.ts:186-227` (server-side `updateUser` 호출)

### Code

- Root cause: `lib/features/auth/data/auth_repository.dart:990-1019` — 기존 `linkedProvidersStream`
- R13 fix pattern (consumer level cached fallback): `lib/features/auth/data/auth_repository.dart:912-967` — `currentUserProvider`

### 일관성 모델

- R13 commit `f4030f9` — `currentUserProvider` AsyncLoading 분기 cached value 보존 (옵션 A pattern matching)
- R6 commit (D-41) — `linkedProvidersStream` handleError 빈 배열 fallback (영구 spinner 회피 정책 — 본 fix 시 보존 의무)

### Firestore SDK race (옵션 평가 근거)

- [flutterfire #11146 — Snapshot Listeners Attaching Before ID Token Refresh, Resulting in Stale Data](https://github.com/firebase/flutterfire/issues/11146)
- [firebase-android-sdk #5101 — Firestore is not picking up fresh auth token and reinitialising event listeners](https://github.com/firebase/firebase-android-sdk/issues/5101)
- [flutterfire #4181 — First snapshot has cached data but should get permission-denied](https://github.com/FirebaseExtended/flutterfire/issues/4181)

### 후속 갱신 대상 (구현 단계에서 작성)

- `.planning/phases/13-naver-login/13-HUMAN-UAT.md` A1 row R10-FOLLOWUP 단락
- `docs/manual.md` "## IdP 프로필 동기화 정책 (R10-FOLLOWUP)" 절

---

## 9. Out of scope

- Firestore SDK 자체의 자동 재구독 bug 수정 (#5101, #11146) — Firebase team 책임. 본 fix 는 client-side workaround
- 키 회전 / git history 시크릿 정화 — 별도 backlog (`2026-06-04-bundle-cleanup-step1.md`, `2026-07-04-bundle-cleanup-step2.md`)
- iOS 실 단말 검증 — 별도 backlog (`2026-05-05-ios-naver-uat-deferred.md`); Android 검증으로 본 fix 의 race 흡수 invariant 충분
- 다른 Firestore stream (e.g., `currentUser` 외 후속 phase 의 별도 stream) 으로의 retry 패턴 일반화 — 본 fix 의 helper-1곳-fix (D-08) 모델로 충분, 일반화는 YAGNI

---

## 10. Acceptance criteria

- [ ] `linkedProvidersStream` 이 `async*` generator 로 재작성, `permission-denied` 1s × 5회 retry 정책 구현
- [ ] retry 중 yield 안 함 (R13 cached fallback 유지)
- [ ] 다른 FirebaseException → 즉시 빈 배열 (D-41 보존)
- [ ] 5회 escape → 빈 배열 (D-41 보존)
- [ ] 정상 emit 도달 시 카운터 리셋
- [ ] `fvm dart analyze` 0 issues
- [ ] `fvm flutter test` 695 → 700 PASS / 0 FAIL
- [ ] `13-HUMAN-UAT.md` A1 row R10-FOLLOWUP-2 단락 추가 (cold start 없이 재로그인 정상 표시 검증)
- [ ] `docs/manual.md` IdP 프로필 동기화 정책 절에 R10-FOLLOWUP-2 + retry 정책 명시
- [ ] todo 파일 `pending → completed` 이동
- [ ] STATE.md `last_activity` 갱신
