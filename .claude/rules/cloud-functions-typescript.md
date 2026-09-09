---
paths:
  - "functions/**/*.ts"
---

# Cloud Functions TypeScript Coding Style

## Formatting
- Prettier 기본 설정 준수
- trailing comma 사용 (멀티라인)
- import 순서: 외부 패키지 → firebase-admin/functions → 내부 모듈 → 상대 경로, 각 그룹 사이 빈 줄
- barrel export (`index.ts`) 남용 금지 — 콜드 스타트 시간에 영향

## Naming
- 변수/함수/매개변수: camelCase
- 클래스/인터페이스/타입: PascalCase
- 상수: UPPER_SNAKE_CASE (모듈 레벨 불변 값)
- 파일명: kebab-case (`custom-token.ts`, `kakao-auth.ts`)
- Cloud Functions 함수명: camelCase (`issueCustomToken`, `onUserCreated`)
- boolean: `is`, `has`, `should`, `can` 접두사

## Type System
- `any` 사용 금지 — `unknown` + 타입 가드로 대체
- `as` 타입 단언 최소화 — 타입 가드 우선
- non-null assertion (`!`) 최소화 — optional chaining 우선
- 함수 반환 타입 명시 (public API 필수)
- `type` 기본 사용 — `interface`는 `implements`, 선언 병합 필요 시만
- `enum` 대신 `as const` 객체 + `typeof` 타입 추출 권장
- `null` vs `undefined`: Firestore 필드 부재는 `undefined`, 명시적 비어있음은 `null`

## 모듈 & Import
- ES Modules 사용 (CommonJS `require` 금지)
- `import type { ... }` — 타입 전용 import 분리
- named export 기본 — default export 사용 금지
- 순환 의존성 금지
- firebase-admin 초기화는 단일 진입점에서만 수행

## 함수 & 에러 처리
- 매개변수 3개 초과 시 객체 매개변수 사용
- `catch (error: unknown)` — `catch (error: any)` 금지
- early return으로 중첩 줄이기
- Cloud Functions 에러: `HttpsError` 사용 (적절한 에러 코드 포함)
- 클라이언트에 내부 에러 상세 노출 금지 — 로그에만 기록

## Documentation
- 모든 public 함수/타입에 JSDoc (`@param`, `@returns`) 작성
- Cloud Functions의 호출 조건, 인증 요구사항 명시

# Cloud Functions Architecture

## Cloud Functions 패턴
- Callable Functions (`onCall`): 클라이언트에서 직접 호출하는 함수
- Trigger Functions (`onDocumentCreated` 등): Firestore/Auth 이벤트 반응
- 함수 하나당 하나의 책임 — 하나의 함수에 여러 로직 금지
- `index.ts`에는 export만 — 로직 금지

## Firebase Admin SDK
- `admin.initializeApp()`은 `config/` 내 단일 파일에서만 호출
- 다른 파일에서는 초기화된 인스턴스를 import하여 사용
- Firestore, Auth 등 서비스 접근은 헬퍼 함수로 래핑 권장

## 보안
- Callable Functions에서 `context.auth` 검증 필수
- 민감 정보(API 키 등)는 Secret Manager 또는 환경 변수 사용
- 소스 코드에 시크릿 하드코딩 금지
- CORS 설정 명시적으로 관리

## 성능
- 글로벌 스코프에서 무거운 초기화 지양 (콜드 스타트 영향)
- 불필요한 import 지양 — 사용하는 모듈만 import (콜드 스타트 영향)
- Firestore 배치 작업: `batch()` 또는 `bulkWriter()` 사용
- 타임아웃/메모리 설정: 함수별 적절한 값 지정

# TypeScript Tooling & Configuration

## 금지 사항
- `any`, `Function`, `Object`/`String`/`Number`/`Boolean` 래퍼 타입 사용 금지
- `@ts-ignore` 금지 — `@ts-expect-error` + 사유 주석으로 대체
- `var`, `==`/`!=`, `eval()`, `arguments` 사용 금지
- CommonJS (`require`, `module.exports`) 사용 금지
- `strict: true` 해제 금지
- `admin.initializeApp()` 중복 호출 금지
- Cloud Functions 내에서 `console.log` 대신 `functions.logger` 사용