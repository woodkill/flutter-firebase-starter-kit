# AccountProvider 확장 (유지보수자 문서)

> 킷 사용자 문서가 아니다 — 사용자는 로그인 수단을 켜고 끄기만 한다([로그인 수단 켜기](../setup.md#로그인-수단-켜기)).

---

`AccountProvider`(`lib/core/auth/provider_id.dart`)는 앱이 아는 로그인 수단 하나하나를 값으로 갖는 enum 이다. 지금 값은 일곱이다 — `google` · `apple` · `facebook` · `email` · `kakao` · `naver` · `line`(알 수 없는 값을 뜻하는 자리는 없다 — 모르는 slug 는 `AccountProvider.tryParse` 가 `null` 로 돌려준다). 이 문서는 enum 에 값 하나를 더할 때 함께 고치는 곳을 적는다. 새 Custom Token 로그인 수단 전체(서버 함수 · SDK · 설정 키 · 배포 목록)를 더하는 절차는 [Custom Token provider 추가 · 제거](custom-token-provider-add-remove.md#추가-가이드) 에 있다. 그 절차의 「Provider ID 등록」 단계에서 enum 값을 더할 때 이 문서의 표와 절차로 빠진 곳을 찾는다 — 그 절차 내용은 여기에 다시 적지 않는다.

## 값이 쓰이는 곳

| 쓰는 곳 | 하는 일 |
|---|---|
| `lib/core/auth/provider_id.dart` | enum 정의와 getter `isNative` · `slug` · `arbKey` · `tryParse` — 모두 값마다 한 갈래를 갖는 switch 다. 로그인 수단이면 `kProviderId<Provider>` 상수와 `kAllProviderIds` 도 이 파일에 있다 |
| `lib/core/error/app_exception.dart` | 같은 이메일 충돌 예외 `AccountExistsWithDifferentCredential.existingProvider` — 기존 가입 수단을 담는다(`null` 이면 수단을 모름) |
| `lib/core/l10n/exception_l10n.dart` | `_resolveAccountExists` 가 충돌 문구를 고르고, `_resolveProviderLabel` 이 값을 ARB 라벨 `authAccountProvider<X>` 로 바꾼다 |
| `lib/l10n/app_en.arb` · `app_ko.arb` · `app_ja.arb` | 수단 라벨 `authAccountProvider<X>` — 세 언어 모두. 브랜드 이름은 각 수단의 공식 표기를 쓴다 |
| `lib/shared/auth/provider_label_formatter.dart` | Firebase `providerData` id(`google.com` · `password` …)와 Custom Token slug 를 라벨로 바꾼다 — 문자열 switch 라 빠뜨려도 analyze 가 잡지 않는다 |
| `lib/core/auth/provider_order.dart` | 계정 정보 화면 「계정 연결」 후보와 탈퇴 진행 화면 행의 표시 순서 |
| `lib/features/auth/data/auth_repository.dart` | 기존 수단으로 로그인(같은 이메일 안내 시트의 버튼) · 연결 callable 이름 · 연결 대상 로그아웃 등 값마다 갈리는 분기 |
| `lib/features/auth/presentation/_widgets/account_linking_sheet.dart` | 같은 이메일 안내 시트의 수단 버튼 |
| `lib/features/settings/presentation/_widgets/account_linking_section.dart` | 「계정 연결」 의 수단 라벨 · 버튼 |
| `lib/features/settings/presentation/settings_notifier.dart` | 수단마다 연결 · 해제를 나누는 분기 |
| `lib/features/settings/data/disconnect/disconnect_steps.dart` 와 같은 폴더의 step 파일 | 로그인 수단 쪽 연결 끊기 목록 — 끊을 연결이 없는 수단(이메일/비밀번호)은 목록에 없다 |
| `lib/features/auth/presentation/reauth_notifier.dart` · `lib/features/settings/presentation/withdrawal_disconnect_notifier.dart` · `lib/features/auth/data/naver_sdk_client.dart` | 재인증 · 탈퇴 진행 · 네이버 SDK 의 값 하나짜리 참조 |
| `functions/src/auth/lookup_sign_in_methods.ts` · `functions/src/auth/identity_index.ts` | 서버가 충돌 이메일의 기존 수단을 slug 로 돌려준다 — 클라이언트는 그 slug 를 `AccountProvider.tryParse` 로 읽는다. Custom Token 수단 목록은 `lookup_sign_in_methods.ts` 의 `CUSTOM_TOKEN_PROVIDERS` 다 |

목록은 아래 명령으로 다시 만든다. 생성 파일과 ARB 생성 코드는 뺀다.

```bash
grep -rn 'AccountProvider\.' lib functions/src | grep -vE '\.(g|freezed)\.dart:|/l10n/generated/'
grep -rn 'AccountProvider' lib functions/src -l | grep -vE '\.(g|freezed)\.dart$|/l10n/generated/'
```

## 값 하나를 더하는 절차

1. **enum 에 값을 더한다.** `lib/core/auth/provider_id.dart` 의 `AccountProvider` 에 값을 더하고, 같은 파일의 `isNative`(Firebase Auth 가 직접 연결하면 `true`, Custom Token 이면 `false`) · `slug` · `arbKey` · `tryParse` 에 그 값의 갈래를 더한다. 로그인 수단이면 `kProviderId<Provider>` 상수를 더하고 `kAllProviderIds` 에 slug 를 넣는다 — 순서 규칙은 [Custom Token provider 추가 · 제거](custom-token-provider-add-remove.md#추가-가이드) 의 「Provider ID 등록」 이다.
2. **라벨을 더한다.** 세 ARB 파일에 `authAccountProvider<X>` 를 더하고(영어 파일에는 `@authAccountProvider<X>` 설명도) `fvm flutter gen-l10n` 으로 생성 코드를 다시 만든다. `lib/core/l10n/exception_l10n.dart` 의 `_resolveProviderLabel` 에 갈래를 더한다.
3. **analyze 가 알려 주는 switch 를 모두 채운다.** enum switch 는 값마다 갈래가 있어야 하므로, 값을 더한 뒤 `fvm dart analyze` 가 빠진 곳을 오류로 알린다. 위 표의 파일이 대상이다. 오류가 0 이 될 때까지 되풀이한다.
4. **analyze 가 잡지 않는 곳을 손으로 고친다.** 문자열 switch(`provider_label_formatter.dart` 의 providerData id · slug 갈래) · 순서 목록(`provider_order.dart`) · 끊기 목록(`disconnect_steps.dart`) · 서버 목록(`CUSTOM_TOKEN_PROVIDERS` 와 slug 를 돌려주는 분기)은 빠뜨려도 컴파일이 된다. 위 grep 결과를 한 줄씩 대조한다.
5. **시험을 고친다.** 값 개수 · 라벨 · 순서 · 버튼 수를 세는 시험은 새 값만큼 기대값이 바뀐다. 화면 golden 이 바뀌면 다시 만든 그림을 열어 버튼만 바뀌었는지 본 뒤 커밋한다.
6. **게이트를 돌린다.**

   ```bash
   fvm dart format --output=none --set-exit-if-changed lib test bin tool
   fvm flutter analyze
   fvm dart analyze
   fvm flutter test
   cd functions && pnpm run lint && pnpm run build && pnpm test && cd ..
   ```

## 값을 빼는 절차

더하는 절차의 역순이다 — 먼저 끊기 목록 · 순서 목록 · 서버 목록 · 문자열 switch 에서 빼고, 그다음 enum 값과 getter 갈래 · ARB 라벨을 지운 뒤 `fvm flutter gen-l10n` 과 위 게이트를 돌린다. 로그인 수단 전체를 빼는 절차는 [Custom Token provider 추가 · 제거](custom-token-provider-add-remove.md#제거-가이드) 다. 이미 그 수단으로 가입한 사용자가 있는 앱에서는 값을 빼지 않는다 — 킷 사용자는 수단을 끄거나([로그인 수단 끄기](../setup.md#로그인-수단-끄기)) 버튼만 숨긴다([Kill Switch 로 로그인 수단 막기](../guide.md#kill-switch-로-로그인-수단-막기)).
