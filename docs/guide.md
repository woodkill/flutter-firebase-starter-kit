# 직접 하는 일 — 내 앱 만들고 출시하기

이 문서는 위저드로 준비한 앱을 내 앱으로 바꾸고 출시 · 운영하는 일 — 화면 · 기능 · 디자인 바꾸기, Firebase 서비스 쓰기, 빌드 · 출시, 운영, 킷 업데이트 반영 — 을 다룬다. 먼저 [설정 위저드로 앱 준비하기](setup.md) 로 처음 설정을 끝낸다.

## 목차

1. [홈 화면 바꾸기](#홈-화면-바꾸기)
2. [내 기능 추가하기](#내-기능-추가하기)
3. [디자인 토큰 바꾸기](#디자인-토큰-바꾸기)
4. [앱 아이콘 바꾸기](#앱-아이콘-바꾸기)
5. [스플래시 바꾸기](#스플래시-바꾸기)
6. [인증 메일 발송 모드 켜고 끄기](#인증-메일-발송-모드-켜고-끄기)
7. [인증 결과 페이지 바꾸기](#인증-결과-페이지-바꾸기)
8. [Firebase 서비스 쓰기](#firebase-서비스-쓰기)
9. [빌드 · 출시](#빌드--출시)
10. [출시 전 점검](#출시-전-점검)
11. [앱 운영하기](#앱-운영하기)
12. [킷 업데이트 반영](#킷-업데이트-반영)
13. [정적 분석 — woody_lints · riverpod_lint](#정적-분석--woody_lints--riverpod_lint)
14. [Git Hooks 활성화 (선택)](#git-hooks-활성화-선택)
15. [Flutter SDK 상향 (FVM)](#flutter-sdk-상향-fvm)
16. [iOS 의존성 관리 (SPM)](#ios-의존성-관리-spm)
17. [테스트 돌리기](#테스트-돌리기)
18. [알아 둘 동작](#알아-둘-동작)

---

## 홈 화면 바꾸기

앱 홈을 내 화면으로 바꿀 때 보는 절이다. 킷의 홈(`/`)은 킷 사용자가 바꾸는
**본문**과 킷이 유지하는 **배선**으로 나뉘어 있다. 계정 정보 · 데모 · 404 화면은 홈
밖의 설정 · 계정 정보 화면 · 데모 화면에 있다(맨 아래 표).

| 파일 | 맡는 일 | 킷 사용자가 |
|------|---------|-------------|
| `lib/features/home/presentation/home_screen.dart` (`HomeScreen`) | AppBar(앱 제목 · 게스트 「로그인」 · 설정 아이콘) · 알림 탭 이동 리스너 · 운영 공지 배너 · 게스트 안내 바 · 본문 자리 | 그대로 둔다 |
| `lib/features/home/presentation/home_body.dart` (`HomeBody`) | 본문 | **바꾼다** |
| `lib/features/home/presentation/_widgets/announcement_bar.dart` · `guest_banner.dart` | 공지 배너 · 게스트 안내 바 위젯 | 모양 · 문구를 바꿀 때만 |

### ① 기본 방법 — `home_body.dart` 만 바꾼다

1. `HomeBody` 의 `build` 를 앱 홈 내용으로 바꾼다. 클래스 이름과 `const HomeBody()`
   로 부를 수 있는 생성자는 남긴다 — `home_screen.dart` 가
   `const Expanded(child: HomeBody())` 로 부른다. 개발자 안내 카드가 필요 없으면
   `showsDeveloperGuide` 인자와 카드 코드를 지워도 된다(그때는
   `test/features/home/home_body_test.dart` 도 함께 고친다).
2. `home_screen.dart` 는 손대지 않는다. 알림 탭 이동 · 공지 · 게스트 안내 · 설정
   진입은 이 파일이 맡으므로, 본문을 통째로 바꿔도 그 기능은 그대로 남는다.
3. 지금 본문 — **release 빌드는 빈 본문**(`SizedBox.shrink`)이다. 그 밖 빌드(debug ·
   profile)는 개발자 안내 카드 1장(「이 본문을 앱 홈으로 바꾸세요」 + 「데모 화면
   열기」 버튼)이다. 분기는 `showsDeveloperGuide` 기본값 const `!kReleaseMode` 하나다.
4. 본문은 `Expanded` 안에 들어가 높이가 정해져 있다. 내용이 길면 스크롤 위젯으로
   감싼다(280 dp 폭 · 가로 회전에서도 넘치지 않게).
5. **앱 이름** — config `appName`(`config/{flavor}.json` → `--dart-define-from-file`)
   하나를 바꾸면 OS 최근 앱 화면의 제목(`onGenerateTitle`)과 홈 AppBar 제목이 함께
   바뀐다. 두 곳이 `resolveAppTitle`(`lib/core/l10n/app_title.dart`) 한 함수를
   쓴다. 값이 비어 있으면 로케일별 ARB `appTitle` 이다. 게스트 홈은 AppBar
   오른쪽에 「로그인」 · 설정 아이콘이 있어 280 dp 에서 긴 이름은 한 줄로 말줄임된다.

### ② 화면을 통째로 바꿀 때 — 옮길 배선 체크리스트

`home_screen.dart` 를 다른 화면으로 바꾸거나 `AppRoutes.home` 의 builder 가 다른
위젯을 띄우게 할 때는 아래 5가지를 새 화면에 옮기고, 6번째(홈 GoRoute 의
`routes:`)는 라우터에 그대로 둔다 — 빠뜨리면 생기는 일은 표에 있다.

| 배선 | 지금 위치 | 빠뜨리면 생기는 일 |
|------|-----------|--------------------|
| 알림 탭 이동 리스너 `PendingNotificationRouteListener` | `lib/features/notifications/presentation/pending_notification_route_listener.dart` · `home_screen.dart` 본문 맨 위 | 알림을 탭해도 대상 화면으로 가지 않는다 — **오류 · 로그 없이 끊긴다.** 저장된 이동 요청을 꺼내 쓰는 곳이 이 위젯 하나다 |
| 운영 공지 배너 `AnnouncementBar` | `_widgets/announcement_bar.dart` · AppBar 바로 아래(게스트 · 정식 모두) | Remote Config 공지([Firebase 서비스 쓰기](#firebase-서비스-쓰기) 의 Remote Config)가 어디에도 보이지 않는다 |
| 게스트 안내 바 `GuestBanner` | `_widgets/guest_banner.dart` · 공지 배너 아래(게스트일 때만) | 게스트에게 가입 안내가 사라진다 |
| 게스트 「로그인」 버튼 | `home_screen.dart` AppBar `actions`(게스트일 때 `context.push(AppRoutes.login)`) | 게스트가 로그인 화면으로 가는 길이 설정의 「로그인 · 가입」 행 하나만 남는다 |
| 설정 아이콘 | `home_screen.dart` AppBar `actions`(`context.push(AppRoutes.settings)` · 게스트 포함) | 설정 · 계정 정보 · 알림 받기 · 데모 화면으로 가는 길이 사라진다 |
| 홈 GoRoute 의 하위 route `routes:`(설정 · 계정 · 탈퇴 · 데모 · 약관 2) | `lib/core/router/app_router.dart` 의 `AppRoutes.home` GoRoute | 알림으로 연 설정 · 계정 · 약관 화면이 스택 1장(「뒤로」 없음)이 되고 홈 리스너가 트리에서 빠진다 — `test/core/router/app_router_nesting_test.dart` 의 구조 시험이 실패한다. builder 만 바꾸고 `routes:` 는 그대로 둔다 |

- **리스너는 위젯 트리에 1개만, 홈 화면에만 둔다.** 종료 상태에서 알림을 탭하면
  스플래시 → 홈 → 대상 순서로 가는데, 이 순서는 홈이 그려진 뒤 홈의 리스너가 요청을
  꺼내 쓰기 때문에 성립한다. 다른 화면에 두면 그 화면이 먼저 요청을
  꺼내 쓸 수 있어 이 순서가 보장되지 않는다.
- **테스트가 실수를 잡는다** — `test/features/home/home_listener_source_guard_test.dart`.
  이 파일의 한 시험은 `lib` 에서 리스너를 만드는 파일이 홈 배선 파일 하나인지 본다
  (빠뜨리거나 다른 파일에 하나 더 두면 실패). **홈 파일 이름을 바꾸면 이 테스트의
  `_homeScreenPath` 도 바꾼다.** 같은 파일의 다른 시험은 세션 종료 관리자
  (`sessionEndingProvider.notifier`)를 쓰는 파일 집합과 `signOutAndResetOnboarding()` 을 직접
  부르는 파일(관리자 1개)을 고정한다 — 로그아웃 버튼을 다른 화면에 더하면 그 화면에서
  `SessionEnding.signOut()` 을 부르고 그 파일을 기대 집합에 더한다. 홈 화면 테스트(`test/features/home/home_screen_test.dart`)와
  홈 golden `home_171_guest_announcement_ko_280_{light,dark}.png`
  (`home_announcement_golden_test.dart`)도 새 화면 기준으로 다시 만든다.
  홈 파일 · 클래스 이름을 바꾸면(예: `my_home_screen.dart` · `MyHomeScreen`) lib ·
  test 에서 옛 이름을 쓰는 곳을 모두 새 이름으로 바꾼다 — `grep -rlw HomeScreen lib test`
  · `grep -rlF home_screen.dart lib test` 로 찾는다(import · `find.byType` · doc 참조 ·
  source guard `_homeScreenPath`). 이 절의 문구를 지키는
  `test/features/home/manual_home_replacement_contract_test.dart` 의 토큰 목록은
  이 절을 함께 고칠 때만 바꾼다.

### ③ 데모 화면 — 위치 · 노출 조건 · 지우는 법

- **위치:** `lib/features/demo/presentation/demo_screen.dart`(`DemoScreen` 한 파일) ·
  경로 `/settings/developer`(`AppRoutes.developerDemo`) — 설정 GoRoute 의 하위
  route(`AppRoutes.developerDemoSegment`)다. 개발 · 데모
  기능이 여기 있다 — 환경 정보 카드 · 날짜 · 숫자 · 복수형 쇼케이스 · 색 · 글꼴 ·
  간격 쇼케이스 · 보호된 기능 예시 · **계정 디버그 정보**(UID 탭 복사 · 가입 수단 ·
  연결된 계정 · 프로필 사진 URL 썸네일) · Dev Tools.
- **노출 조건:**
  - **release 빌드에는 없다.** 데모 GoRoute 를 `if (!kReleaseMode)` 로만 등록하므로
    (`lib/core/router/app_router.dart`) release 에서는 그 경로가 404(`NotFoundScreen`)
    이고, 진입점 2곳도 같은 조건으로 사라진다. 스토어 배포본은 release 로 만든다.
  - **profile 빌드에서는 열린다.** 실기기에서 계정 디버그 정보를 확인 화면으로
    쓸 때를 위한 것이다. profile 빌드를 배포하면 UID · 환경 정보가
    보이므로 배포에 쓰지 않는다.
  - **Dev Tools 는 debug 빌드만**(`kDebugMode`) — 온보딩 초기화 · 테스트 오류 ·
    테스트 Analytics · 테스트 알림 · 강제 로그아웃. ID 토큰 복사도 debug 빌드만이다.
    profile 데모에서는 보이지 않는다.
- **진입 2곳:** 설정 맨 아래 「개발자」 묶음의 「개발자 · 데모 화면」 행(게스트 포함 ·
  `SettingsScreen.showsDemoRow` 기본값 `!kReleaseMode`)과 홈 개발자 안내 카드의
  「데모 화면 열기」 버튼. 둘 다 데모 위젯을 import 하지 않고 경로 문자열
  (`context.push(AppRoutes.developerDemo)`)만 쓴다 — release 바이너리에 데모 코드가
  남지 않게 하려는 것이다. `home_body.dart` 를 바꿔 카드가 사라져도 설정 행은 남는다.
- **데모에 production 배선을 넣지 않는다.** 데모 화면이 알림 리스너 · 공지 배너 ·
  라우트 상수 · 테마 provider 를 import 하면
  `test/features/home/home_listener_source_guard_test.dart` 의 시험이 실패한다. 테마 ·
  언어 바꾸기는 설정 한 곳이다.
- **게스트 로그아웃은 없다.** 개발 중 처음 상태로 돌리려면 데모 Dev Tools 의 강제
  로그아웃(debug)을 쓴다. profile · release 빌드의 게스트는 앱 데이터 삭제로만 처음
  상태가 된다.
- **지우는 법(데모를 앱에서 빼기):**
  1. `app_router.dart` 설정 GoRoute 의 `routes` 안에 있는 `if (!kReleaseMode)` 데모
     GoRoute(`path: AppRoutes.developerDemoSegment`) 1개와 `demo_screen.dart`
     import 를 지운다. `AppRoutes` 의 데모 상수 3개(`developerDemo` ·
     `developerDemoName` · `developerDemoSegment`)는 남겨도 테스트가 그대로
     통과한다. 상수까지 지우면 쓰는 곳도 함께 고친다 —
     `test/core/router/app_routes_test.dart` T-172-ROUTES-01~03 의 데모 항목
     1줄씩(`hasLength` 14 → 13 · 14 → 13 · 6 → 5, 테스트 이름 · reason 의 개수도),
     `test/core/router/auth_guard_test.dart` T-171-ROUTER-06 삭제,
     `settings_screen_test.dart` · `home_body_test.dart` 하네스의 데모 stub
     GoRoute(`path: AppRoutes.developerDemo`) 삭제, `home_body.dart` doc 의
     `[AppRoutes.developerDemo]` 참조 삭제. 상수를 지우면 그 상수를 쓰는 2단계의
     진입점 2곳(`settings_screen.dart` · `home_body.dart`)과 4단계에서 정리할
     테스트(`app_router_observers_test.dart` · `test/features/demo/`)가 그 단계를
     마칠 때까지 컴파일되지 않는다 — 4단계까지 이어서 하고, 확인(analyze · `grep`)은
     4단계 끝에서 한 번에 한다.
  2. 진입점 2곳 — `settings_screen.dart` 의 「개발자」 묶음(`showsDemoRow`)과
     `home_body.dart` 카드의 버튼 — 을 지운다.
  3. `lib/features/demo/` 폴더를 지운다.
  4. 테스트를 정리한다 — 아래 항목을 위에서부터 차례로 따라 한다.
     - `test/features/demo/` — 폴더째(3파일) 지운다.
     - `test/core/router/app_router_observers_test.dart` — T-171-ROUTER-02 · 03
       이 든 group 을 통째로 지우고, Test 2 · 3 의 재귀 개수 `14`(비 release)를
       `13` 으로 고친다(최상위 `8` 은 그대로 · Test 2 이름의 「14개」 ·
       `developerDemo` 도). `test/helpers/route_tree.dart` 는 남기되(다른 테스트
       여러 파일이 import 한다) `buildRoutesWithoutNamed` 만 지운다 —
       T-171-ROUTER-03 전용이라 그 group 과 함께 호출자가 사라진다.
     - `test/features/home/home_listener_source_guard_test.dart` — T-171-HOME-15
       를 지우고, T-171-HOME-16 기대 집합에서 `demo_screen.dart`(상수
       `_demoScreenPath`)를 뺀다.
     - `test/features/settings/presentation/settings_screen_test.dart` —
       T-171-SETTINGS-06 · 07 은 지운다. 데모 행 · 「개발자」 묶음을 보는 01 ·
       11 · 13 · 15 · 17 ②~④ · T-17-NOTIF-12 는 지우지 말고, 그 기대를 빼거나
       기준을 새 마지막 행(정식은 알림 스위치 · 게스트는 언어 행 — 13 · 15 는
       둘 다, 01 은 게스트로 본다)으로 바꾼다. 17 ③ 은 거기에 더해
       (c) 데모 경로 탭 단언을 지우고, `screenHeight` 640 을 목록이 넘치는
       값(예: 400)으로 줄인다 — 목록이 짧아져 스크롤이 생기지 않으므로 전제
       단언(`maxScrollExtent > 0`)이 실패한다. 전제 단언은 지우지 않는다(지우면
       (b) geometry 단언이 스크롤 없이 통과해 회귀 가드가 빈다). 같은 테스트의
       `safeBottom` 옆 주석 `// 592.0` 은 새 값(400 이면 `352.0`)으로, (b)
       reason 문자열의 「말단 행(데모 행)」 은 「말단 행(알림 스위치)」 로 고친다.
     - `test/features/settings/presentation/notifications_section_test.dart` —
       T-17-NOTIF-05 위치 테스트(「… 개발자 위에 있다」)는 지우지 말고 「개발자」
       기준 단언만 뺀다.
     - `test/features/home/home_body_test.dart` — T-171-HOME-11 에서 버튼 · 데모
       경로 이동 단언을 지운다.
     - 매뉴얼 계약 테스트 2파일 — 이 ③ 절을 매뉴얼에서 함께 지울 때만 고친다(③ 을
       남기면 그대로 둔다). `test/features/home/manual_nested_routes_contract_test.dart`
       는 T-172-DOCS-07(바로 위 주석 1줄 포함)과 그 테스트용 선언(상수
       `_demoHeading` · `_demoSegmentParts`, `main` 의 `demoSection` 과
       T-172-DOCS-06 의 `demoSection` 줄)을 지우고, ③ 을 가리키는 주석도 지운다 —
       파일 머리말의 `T-172-DOCS-07` 줄 · 안전 규칙 끝의 ③ 항목 2개(「③ 데모 상수
       이름은」 · 「예외:」), T-172-DOCS-06 안의 「매뉴얼 ③ 이 … 인용한다」 주석
       1줄. T-172-DOCS-06 이 이 파일 자신을 읽는 코드는 그대로 둔다(해가 없다).
       `test/features/home/manual_home_replacement_contract_test.dart`
       는 T-171-DOCS-02 필수 토큰 목록에서 `lib/features/demo/presentation/demo_screen.dart`
       1줄을 뺀다(그 경로는 ③ 에만 있다).
     - `test/features/settings/presentation/settings_screen_golden_test.dart` ·
       `test/features/home/home_announcement_golden_test.dart` — 데모 행 · 카드가
       찍힌 golden(설정 8장 · 홈 2장)을 이 두 파일만 다시 만든다. 두 경로를 인자로
       준 아래 명령을 그대로 쓴다 — 인자 없이 돌리면 모든 golden 이 다시 찍힌다:
       ```bash
       fvm flutter test --no-pub --update-goldens \
         test/features/settings/presentation/settings_screen_golden_test.dart \
         test/features/home/home_announcement_golden_test.dart
       git status --short -- '*.png'
       ```
       마지막 줄(`git status`)의 출력이 정확히 10장(설정 `settings_171_*` 8 · 홈
       `home_171_*` 2 · 모두 `M`)인지 확인한다.
     - 끝으로 `fvm dart analyze` 가 0 건이 될 때까지, 지운 파일을 가리키거나 쓰는
       곳이 없어진 import · 선언 · 지역 변수를 lib · test 모두에서 지운다(라우터
       테스트의 `demo_screen.dart` · 테스트 전용 import · mock 클래스와 그 뒤
       2차로 드러나는 `auth_repository.dart` import, source guard 의
       `_demoScreenPath`, 알림 섹션 테스트의 `sectionBottom`, 2단계 뒤
       `home_body.dart` 의 `go_router` · `settings_screen.dart` 의
       `foundation.dart` 등). 하나를 지우면 다른 것이 새로 드러날 수 있으므로
       analyze 는 0 건이 될 때까지 되풀이한다. analyze 가 0 건이면
       `grep -rn developerDemo lib test` 도 본다 — 1단계에서 상수까지 지웠다면
       0 건이어야 한다. 상수를 남겼다면 `lib/core/router/app_routes.dart` 의 상수
       3개와 1단계에 적은 상수 참조처(`app_routes_test.dart` ·
       `auth_guard_test.dart` T-171-ROUTER-06 · 두 하네스의 데모 stub GoRoute ·
       `home_body.dart` doc)만 남는다.
  5. Dev Tools 의 테스트 알림 버튼이 같이 사라진다. 서버 함수 `sendTestPush` 까지
     빼려면 `functions/src/index.ts` 의 `export {sendTestPush} …` 줄과
     `functions/src/messaging/` 를 지우고, 클라이언트
     `lib/features/notifications/data/test_push_client.dart` 와 그 시험도 함께 지운
     뒤 배포된 함수를
     `firebase functions:delete sendTestPush --region <functionsRegion> --project <your-project-id>`
     로 지운다(`--region` 은 `config/dev.json` 의 `functionsRegion` 값). export 만
     남기면 다음 배포가 함수를 다시 만든다.

### ④ 알림 탭으로 열 화면 — 허용 목록

- 알림 payload `data.route` 로 열 수 있는 화면은 `kNotificationRoutableRoutes`
  (`lib/features/notifications/application/notification_route.dart`) **5개**다 —
  `/`(홈) · `/settings`(설정) · `/settings/account`(계정 정보) ·
  `/terms/service` · `/terms/privacy`. 문자열이 정확히 같을 때만 그 화면으로 가고,
  목록 밖 · 없음 · 외부 URL 은 홈이다([FCM 알림](#fcm-알림) 의 「탭 이동」).
- **새 화면을 더하는 법:** 아래 6단계를 차례로 따른다(예시 이름 = 공지 화면
  `notices`). 알림으로 연 화면에 「뒤로」 가 있고 홈 리스너가 트리에 남으려면 새
  화면이 홈 하위 route 여야 한다([FCM 알림](#fcm-알림) 의 「결과 스택」).
  1. `AppRoutes`(`lib/core/router/app_routes.dart`)에 조각 · 전체 경로 · name 상수
     3개를 더한다 — 예: `noticesSegment = 'notices'` · `notices = '/$noticesSegment'`
     · `noticesName = 'notices'`.
     ```dart
     static const String noticesSegment = 'notices';
     static const String notices = '/$noticesSegment';
     static const String noticesName = 'notices';
     ```
  2. 새 화면(예: `lib/features/notices/presentation/notices_screen.dart` 의
     `NoticesScreen`)을 만들고, `lib/core/router/app_router.dart` 에서 그 파일을
     import 한 뒤 **홈 GoRoute(`AppRoutes.home`)의 `routes:` 안에**(앱 안 부모 화면이
     있으면 그 GoRoute 의 `routes:` 안에) 등록한다. 하위 route 의 `path` 는 `/` 없는
     조각 상수다. `name` 은 필수다(GA4 screen name · Test 3).
     ```dart
     GoRoute(
       path: AppRoutes.noticesSegment,
       name: AppRoutes.noticesName,
       builder: (context, state) => const NoticesScreen(),
     ),
     ```
  3. `kNotificationRoutableRoutes` 에 `AppRoutes.notices` 1줄을 더한다.
  4. `test/features/notifications/application/notification_route_test.dart` 의
     허용 목록 기대 Set 에 `AppRoutes.notices` 1줄을 더한다.
  5. `test/core/router/app_router_observers_test.dart` Test 2 · 3 의 재귀 개수
     (Test 2 의 `collectGoRoutes(…).length` · Test 3 의 `names.length` 기대값)
     `14` 를 `15` 로 고친다. Test 2 이름의 「14개」 도 「15개」 로 고친다. 최상위
     `8` 은 그대로다(데모를 지웠다면 `13` → `14` — 지금 값에 1 을 더한다).
  6. `fvm dart analyze` 가 0 건인지, 전체 `fvm flutter test` 가 통과하는지 본다.

  **최상위에 두면 실패한다.** 알림으로 열었을 때 「뒤로」 가 없고 홈 리스너가
  트리에서 빠지므로 `test/core/router/app_router_nesting_test.dart` 의 구조 시험이
  아래 메시지로 실패한다(예시 `/notices`):
  ```text
  알림 허용 목록 경로 /notices 가 홈 하위 route 가 아니다 (첫 match = /notices). lib/core/router/app_router.dart 의 홈 GoRoute routes 안으로 옮긴다 — docs/manual.md 「홈 화면 바꾸기」 ④
  ```
  query · 경로 변수는 쓸 수 없다.
- **넣지 않는 화면:** 앞 단계 상태 없이 열리면 안 되는 흐름 화면(스플래시 · 온보딩 ·
  로그인 · 가입 · 이메일 로그인 · 비밀번호 찾기 · 이메일 인증 · 탈퇴 진행)과 release
  에 없는 데모 경로 `/settings/developer`.
- **정식 사용자 전용 화면은 guard 로 막는다.** 계정 정보 화면이 선례다 — 게스트가 알림
  탭 · 딥링크 · 앱 안 이동으로 `/settings/account` 에 오면 `lib/core/router/auth_guard.dart`
  분기 (3) 이 `/settings` 로 돌린다. 새 정식 전용 화면도 같은 분기에 조건 1개를 더한다.

### 계정 정보 · 데모 · 404 화면 위치

| 항목 | 위치 |
|------------|-----------|
| 테마 · 언어 바꾸기 | 설정 「일반」 묶음의 테마 · 언어 행(누르면 아래 시트) |
| 계정 정보(프로필 사진 · 이름 · 이메일 · 가입일 · 가입 수단 · 연결된 계정) · 연결 해제 · 계정 연결 · 로그아웃 · 회원탈퇴 | 설정 → 내 계정(계정 정보 화면 · `lib/features/settings/presentation/account_screen.dart` · `/settings/account`) — 정식 사용자만. 설정 맨 위 계정 행이 유일한 진입점이다 |
| UID 복사 · 프로필 사진 URL · ID 토큰 복사 · 환경 정보 · 디자인 쇼케이스 · Dev Tools | 데모 화면(위 ③) |
| 404 화면 | `NotFoundScreen`(`lib/features/not_found/presentation/not_found_screen.dart`) — 요청 경로 · 쿼리는 개인 정보가 섞일 수 있어 그리지 않는다. 404 화면을 바꾸려면 이 파일 하나만 고친다 |

## 내 기능 추가하기

## 디자인 토큰 바꾸기

## 앱 아이콘 바꾸기

## 스플래시 바꾸기

## 인증 메일 발송 모드 켜고 끄기

## 인증 결과 페이지 바꾸기

## Firebase 서비스 쓰기

### FCM 알림

## 빌드 · 출시

### 릴리스 서명(keystore)

## 출시 전 점검

### 로그인 수단 검수 · 인증

### 소셜 로고 · 브랜드 자산

### ATT 와 iOS Facebook 로그인

## 앱 운영하기

### Kill Switch 로 로그인 수단 막기

### Crashlytics · Analytics

## 킷 업데이트 반영

킷의 새 판을 내 앱 저장소에 받는 절차다. 앱 저장소를 만들 때 기준점을 한 번 만들고, 새 판이 나오면 그 판의 태그를 `git merge` 한다. 판마다 태그(`v1.0.0-rc.1` 꼴) · `KIT_VERSION` · `CHANGELOG.md` 의 그 판 절이 함께 나온다.

**전제:** git 과 GitHub 계정이 있다. 앱 저장소는 private 으로 만든다. 킷 저장소를 **fork 하지 않는다** — 공개 저장소의 fork 는 공개로만 만들어져 앱 코드가 공개된다.

### 시작하기 — template 로 앱 저장소 만들기

**① 저장소 만들기.** 킷 저장소 페이지에서 **Use this template** → **Create a new repository** 를 누르고 **Private** 을 고른다. 새 저장소의 이력은 커밋 1개로 시작하고 킷 이력과 이어져 있지 않다.

**② clone.** `git clone <your-repo-url>` 로 받은 뒤 그 디렉터리로 들어간다.

**③ 킷 저장소를 upstream 으로 더하고 기준점을 만든다.** 처음 한 번만 한다. 기준점 merge 는 파일을 바꾸지 않고 「이 판까지 받았다」 는 표시만 남긴다.

```bash
git remote add upstream https://github.com/woodkill/flutter-firebase-starter-kit.git
git fetch upstream --tags
git merge -s ours --allow-unrelated-histories "v$(cat KIT_VERSION)" -m "킷 기준점 v$(cat KIT_VERSION)"
git push
```

### 시작하기 — clone 으로 시작한 경우

킷 저장소를 그대로 clone 해 시작했다면 내 저장소의 이력이 킷 이력과 이어져 있어 기준점 merge 가 필요 없다. 킷 저장소를 `upstream` 으로 바꾸고, GitHub 에 내 private 저장소를 만들어 `origin` 으로 둔다.

```bash
git remote rename origin upstream
git remote add origin <your-private-repo-url>
git push -u origin main
```

새 판은 「새 판 받기」 그대로 받는다.

### 새 판 받기

**① 새 판 확인.** 킷 저장소 페이지에서 **Watch → Custom → Releases** 를 켜 두면 새 판이 나올 때 알림이 온다. 지금 받아 둔 판은 `cat KIT_VERSION` 으로 본다.

**② 그 판의 CHANGELOG 절을 읽는다.** 판 절 맨 앞에 `### 사용자 조치` 가 있으면 merge 뒤 그 조치를 한다. 판 번호 첫 자리(MAJOR)가 올라간 판에는 늘 이 절이 있다. `### 사용자 조치` 가 없는 판은 merge 만으로 끝난다. 여러 판을 건너뛰어 받을 때는 그 사이 판의 절도 모두 읽는다.

**③ 받기.** `TAG` 에 받을 판의 태그를 넣는다.

```bash
TAG=v1.0.0-rc.2
git fetch upstream --tags
git merge "$TAG" -m "킷 $TAG 반영"
```

**④ 충돌이 없으면** 의존성과 생성 코드를 맞춘다. 충돌이 나면 「충돌 풀기」 를 먼저 한다.

```bash
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
```

**⑤ 올리기.** 「확인 방법」 을 마친 뒤 `git push` 한다.

### 충돌 풀기

merge 가 `CONFLICT` 줄을 출력하고 멈추면 `git status` 로 충돌 파일을 보고 아래 규칙대로 푼다. 모두 풀었으면 merge 를 끝낸다.

```bash
git commit --no-edit
```

**규칙 1 — 내가 지운 파일을 킷이 고쳤다.** merge 가 `CONFLICT (modify/delete)` 를 출력하고 `git status` 에 그 파일이 `deleted by us` 로 보인다. 지운 상태를 그대로 둔다.

```bash
git rm <파일>
```

**규칙 2 — 사용자 소유 표면의 같은 줄을 둘 다 고쳤다.** merge 가 `CONFLICT (content)` 를 출력하고 `git status` 에 그 파일이 `both modified` 로 보인다. 「사용자 소유 표면」 표에 있는 파일이면 그 행의 「충돌 시 조치」 를 따른다. 파일 전체를 내 판으로 남길 때는 아래처럼 한다 — 이렇게 하면 그 파일에서 킷이 바꾼 다른 줄도 받지 않으므로, 다른 줄을 받아야 하면 파일을 열어 `<<<<<<<` · `>>>>>>>` 표시 사이를 직접 합친 뒤 `git add <파일>` 한다. 표에 없는 파일도 같은 방법으로 직접 합친다.

```bash
git checkout --ours -- <파일>
git add <파일>
```

**규칙 3 — 데모를 지웠다면 매번 같은 조치.** [홈 화면 바꾸기](#홈-화면-바꾸기) 의 ③ 「지우는 법」 으로 데모를 지웠다면, 킷이 데모 파일을 고친 판마다 규칙 1 의 충돌이 난다. 같은 `git rm <파일>` 로 풀고, 코드는 고칠 것이 없다. 충돌이 날 데모 파일은 그 판 CHANGELOG 절의 `### 사용자 조치` 에 적힌다.

**규칙 4 — skip-worktree 파일 때문에 merge 가 시작되지 않는다.** `scripts/firebase-configure.sh` 는 실 값으로 덮어쓴 저장소 파일(dev 는 `lib/core/firebase/firebase_options_dev.dart` · `ios/config/dev/GoogleService-Info.plist`)에 `--skip-worktree` 를 걸어 git 이 그 변경을 보지 않게 한다. 킷이 그 파일을 고친 판을 받으면 merge 가 시작되지 않고 아래 메시지로 멈춘다.

```
error: Your local changes to the following files would be overwritten by merge:
	lib/core/firebase/firebase_options_dev.dart
Please commit your changes or stash them before you merge.
Aborting
```

한국어 git 은 같은 자리에 `병합하기 전에 변경 사항을 커밋하거나 스태시하십시오.` 를 출력한다. skip-worktree 가 걸린 파일은 `git ls-files -v | grep '^S'` 로 본다. 목록에 그 밖의 파일이 있으면 그 변경을 먼저 커밋한다. skip-worktree 파일은 아래 순서로 푼다 — 실 값 파일을 저장소 밖에 복사해 두고, skip-worktree 를 풀고, 그 파일을 저장소 판으로 되돌린 뒤 merge 하고, 복사본을 되돌려 놓고, skip-worktree 를 다시 건다.

```bash
mkdir -p ../kit-merge-backup
cp lib/core/firebase/firebase_options_dev.dart ios/config/dev/GoogleService-Info.plist ../kit-merge-backup/
git update-index --no-skip-worktree lib/core/firebase/firebase_options_dev.dart ios/config/dev/GoogleService-Info.plist
git checkout -- lib/core/firebase/firebase_options_dev.dart ios/config/dev/GoogleService-Info.plist
git merge "$TAG" -m "킷 $TAG 반영"
cp ../kit-merge-backup/firebase_options_dev.dart lib/core/firebase/firebase_options_dev.dart
cp ../kit-merge-backup/GoogleService-Info.plist ios/config/dev/GoogleService-Info.plist
git update-index --skip-worktree lib/core/firebase/firebase_options_dev.dart ios/config/dev/GoogleService-Info.plist
```

블록의 `git merge` 가 다른 충돌로 멈추면 규칙 1 · 2 로 풀고 `git commit --no-edit` 한 뒤 남은 세 줄을 실행한다. stg · prod 에도 `scripts/firebase-configure.sh` 를 실행했다면 그 flavor 의 파일도 같은 줄에 더한다.

### 바꾸지 않는 것

**Dart 패키지명 `flutter_starter_kit` 은 그대로 둔다.** 킷의 import 는 모두 `package:flutter_starter_kit/` 로 시작한다. 패키지명을 바꾸면 킷이 고친 파일마다 import 줄이 충돌한다. 앱 이름 · 번들 ID · Android 앱 ID 는 config · xcconfig 와 아래 도구로 바꾼다.

**앱 ID 는 `bin/rename.dart` 로 바꾼다.** 이 도구는 Android `applicationId` · `namespace` · Kotlin 소스 디렉터리, iOS 번들 ID, `scripts/firebase-configure.sh` 의 `PROJECT_ID_PREFIX` · `IOS_BUNDLE_ID_PREFIX` · `ANDROID_PACKAGE_PREFIX`, 내 config 파일(`config/dev.json` · `config/stg.json` · `config/prod.json`)의 `appName` 을 바꾼다. iOS 번들 ID 는 `ios/Runner.xcodeproj/project.pbxproj` 와 내 xcconfig 파일(`ios/Flutter/dev.xcconfig` · `ios/Flutter/stg.xcconfig` · `ios/Flutter/prod.xcconfig`)의 `PRODUCT_BUNDLE_IDENTIFIER` 에서 바뀌고, 킷의 `*.example.xcconfig` 는 바꾸지 않는다. 키 없이 빌드하기 위한 Firebase placeholder 파일(`android/app/src/stg/google-services.json` · `android/app/src/prod/google-services.json` 의 `package_name`, `ios/config/dev/GoogleService-Info.plist` · `ios/config/stg/GoogleService-Info.plist` · `ios/config/prod/GoogleService-Info.plist` 의 `BUNDLE_ID`)도 새 앱 ID 로 바뀌어 rename 뒤에도 `--flavor stg` · `--flavor prod` 빌드가 그대로 된다. `scripts/firebase-configure.sh` 가 실 값으로 바꾼 파일은 건드리지 않는다. Dart 패키지명과 import 는 그대로다.

rename 은 위저드가 config example 을 복사한 뒤 실행한다 — 도구는 내 config 파일의 `appName` 만 바꾸고 `config/*.example.json` 은 바꾸지 않는다.
xcconfig 도 같다 — 위저드가 xcconfig 예시를 복사한 뒤에 실행해야 flavor 빌드의 iOS 번들 ID 가 바뀐다.

먼저 바뀔 목록만 보고, 맞으면 `--apply` 를 붙여 다시 실행한다(묻는 말에 `y` 로 답한다).

```bash
fvm dart run bin/rename.dart --org com.mycompany --name my_app --project-prefix my-company-app
fvm dart run bin/rename.dart --org com.mycompany --name my_app --project-prefix my-company-app --apply
```

`--project-prefix` 는 Firebase 프로젝트 ID 의 앞부분이다. `scripts/firebase-configure.sh` 가 `<prefix>-dev` · `<prefix>-stg` · `<prefix>-prod` 를 Firebase 프로젝트 ID 로 쓴다. 생략하면 `--name` 의 `_` 를 `-` 로 바꾼 값을 쓴다.

**`pubspec.yaml` 의 `version:` 은 내 앱 버전이다.** 킷은 이 줄을 고치지 않는다. 킷 판 번호는 `KIT_VERSION` 에 있다.

**`fvm flutter pub upgrade` 는 킷 업데이트와 별개다.** 킷 판은 그 판으로 테스트한 `pubspec.lock` 과 함께 나온다. 의존성을 올리려면 킷 업데이트 merge 와 따로 실행해 따로 커밋한다.

### 사용자 소유 표면

merge 뒤 사용자가 손봐야 하는 판은 MAJOR 다 — 사용자 소유 표면 표에서 킷이 고칠 가능성이 `낮음` 인 파일의 변경 · 표의 「충돌 시 조치」 칸 밖의 손질이 필요한 변경 · 콘솔 재설정 · 데이터 마이그레이션. 아래 표는 앱마다 바꾸는 자리와, 킷이 그 파일을 고칠 가능성 · 충돌이 났을 때의 조치를 적는다. MAJOR 판은 CHANGELOG 판 절 맨 앞 `### 사용자 조치` 에 할 일과 충돌이 날 파일이 적힌다. 표에 없는 파일(`lib/core/` · `lib/features/auth/` · `functions/src/auth/` · `scripts/` 본문 등)을 고쳤다면 그 충돌은 직접 푼다.

「킷이 고칠 가능성」 칸: `높음` · `중간` 은 킷이 판마다 고칠 수 있는 파일이고 충돌은 「충돌 시 조치」 칸대로 푼다. `낮음` 은 킷이 고치지 않는 파일이고, 고치면 그 판은 MAJOR 다. `없음` 은 킷이 손대지 않는다.

| # | 파일 | 사용자가 바꾸는 것 | 킷이 고칠 가능성 | 충돌 시 조치 |
|---|---|---|---|---|
| 1 | `config/dev.json` · `config/stg.json` · `config/prod.json` (git 밖 · 예시는 `config/*.example.json`) | 키 값 전부(`appName` · `firebaseProjectId` · 로그인 수단 키 · `enabledAuthProviders` · `brandColor` · `emailDelivery` 등) | 높음 (새 키 추가 · 내 파일은 git 밖) | 충돌 없음. merge 뒤 `diff config/dev.example.json config/dev.json` 으로 새 키를 내 파일에 옮겨 적는다 |
| 2 | `ios/Flutter/dev.xcconfig` · `stg.xcconfig` · `prod.xcconfig` (git 밖 · 예시는 `*.example.xcconfig`) | 변수 값 전부 · `DEVELOPMENT_TEAM` | 높음 (새 변수 추가 · 내 파일은 git 밖) | 충돌 없음. merge 뒤 `diff ios/Flutter/dev.example.xcconfig ios/Flutter/dev.xcconfig` 로 새 변수를 내 파일에 옮겨 적는다 |
| 3 | `lib/core/firebase/firebase_options_dev.dart` · `_stg.dart` · `_prod.dart` · `ios/config/<flavor>/GoogleService-Info.plist` · `android/app/src/stg/google-services.json` · `android/app/src/prod/google-services.json` (저장소 값은 자리표시 · 실 값은 skip-worktree) | `scripts/firebase-configure.sh` 가 실 값으로 덮어쓴다 | 낮음 | 「충돌 풀기」 규칙 4 |
| 4 | `scripts/firebase-configure.sh` 의 `PROJECT_ID_PREFIX` · `IOS_BUNDLE_ID_PREFIX` · `ANDROID_PACKAGE_PREFIX` | 내 프로젝트 식별자 3개(`bin/rename.dart` 가 바꾼다) — 프로젝트 ID 는 `config/<flavor>.json` 의 `firebaseProjectId` 가 있으면 그 값을 먼저 쓰고, 상수는 그 값이 없을 때만 쓴다 | 중간 (스크립트 개선) | 같은 줄이 충돌하면 파일을 열어 상수 3줄만 내 값으로 남기고 나머지는 킷 값을 받는다 |
| 5 | `.firebaserc` | 내 Firebase 프로젝트 ID | 낮음 | 내 값 |
| 6 | `firebase.json` 의 `flutter.platforms` 프로젝트 ID · 앱 ID | FlutterFire CLI 가 쓰는 내 프로젝트 ID · 앱 ID | 중간 (`functions` · `emulators` · `hosting` · `extensions` 설정) | 다른 줄은 자동 병합 · 프로젝트 ID · 앱 ID 줄은 내 값 |
| 7 | `android/app/build.gradle.kts` 의 `namespace` · `applicationId` · flavor 접미사 · `release` 서명 설정 | 앱 ID(`bin/rename.dart`) · 릴리스 서명 | 중간 (Android Gradle Plugin · Flutter 상향) | 앱 ID · 서명 줄은 내 값 · 나머지는 킷 값 |
| 8 | `android/app/src/main/kotlin/` 아래 앱 패키지 디렉터리의 `*.kt` | 패키지 경로(`bin/rename.dart` 가 디렉터리를 옮긴다) | 낮음 | 킷이 옛 경로의 파일을 고쳐 규칙 1 의 충돌이 나면 옛 경로를 `git rm` 하고 그 변경을 새 경로 파일에 옮겨 적는다 |
| 9 | `ios/Runner.xcodeproj/project.pbxproj` | 번들 ID(`bin/rename.dart`) · Xcode 가 저장하는 설정 | 중간 (Flutter · Xcode 상향 · 플러그인) | 충돌이 잦다. 번들 ID 줄은 내 값 · 나머지는 킷 값을 받고 Xcode 로 열어 확인한다 |
| 10 | `ios/Flutter/*.example.xcconfig` · `config/*.example.json` | 고치지 않는다(복사 원본) | 높음 | 충돌 없음(고치지 않았다면) |
| 11 | `pubspec.yaml` 의 `version:` | 앱 버전 · 빌드 번호 | 없음 (킷은 이 줄을 고치지 않는다) | 충돌 없음 |
| 12 | `pubspec.yaml` 의 `description:` · `dependencies` | 앱 설명 · 의존성 추가 | 높음 (의존성 상향) | 다른 줄은 자동 병합 · 같은 줄은 내 값 |
| 13 | `pubspec.lock` | `fvm flutter pub upgrade` 결과 | 높음 | 충돌하면 킷 판(`git checkout --theirs -- pubspec.lock` · `git add pubspec.lock`)을 받고 `fvm flutter pub get` |
| 14 | `flutter_native_splash.yaml` · `assets/images/splash/logo.png` · `logo_dark.png` | 스플래시 색 · 로고 | 낮음 | 내 값 · `fvm dart run flutter_native_splash:create` 로 다시 만든다 |
| 15 | 스플래시 생성물(`android/app/src/main/res/drawable*/launch_background.xml` · `values*/styles.xml` · `ios/Runner/Assets.xcassets/LaunchImage.imageset/` · `ios/Runner/Base.lproj/LaunchScreen.storyboard`) | 14 를 다시 만든 결과 | 낮음 | 다시 만들어 덮어쓴다 |
| 16 | 앱 아이콘(`android/app/src/main/res/mipmap-*/ic_launcher.png` · `ios/Runner/Assets.xcassets/AppIcon.appiconset/`) | 내 아이콘 | 낮음 | 내 파일(`git checkout --ours -- <파일>`) |
| 17 | `lib/l10n/app_en.arb` · `app_ko.arb` · `app_ja.arb` (+ `lib/l10n/generated/`) | 앱 제목 · 문구 | 높음 (기능마다 키 추가) | 다른 줄은 자동 병합 · 같은 키는 내 값 · merge 뒤 `fvm flutter gen-l10n` 으로 다시 만들어 커밋 |
| 18 | `lib/features/home/presentation/home_body.dart` | 홈 본문 | 중간 | 내 값 · 「홈 화면 바꾸기」 의 배선 체크리스트는 지킨다 |
| 19 | `lib/features/home/presentation/home_screen.dart` · `lib/core/router/app_router.dart` 의 홈 라우트 | 화면 교체 · 라우트 추가 | 높음 (라우트 · 리스너) | 자동 병합을 먼저 보고, 충돌은 직접 합친다 · 구조 테스트가 결과를 검사한다 |
| 20 | `lib/features/demo/` · `test/features/demo/` · 데모를 지우며 고친 테스트 | 데모 삭제(「홈 화면 바꾸기」 ③ 지우는 법) | 중간 | 규칙 1(`git rm`) · 「데모를 지웠다면」 규칙 3 |
| 21 | `lib/core/theme/` 토큰 (브랜드 색은 `config/*.json` 의 `brandColor`) | 테마 토큰 | 중간 | 내 값 |
| 22 | `android/app/src/main/res/drawable/ic_notification.xml` · `values/colors.xml` 의 `notification_color` · `lib/features/notifications/data/local_notifications_service.dart` 의 `_kNotificationColor` | 알림 아이콘 · 색 | 낮음 | 내 값 |
| 23 | `ios/Runner/Info.plist` · `InfoPlist.strings` | 권한 문구 · 추적 허용 문구 | 중간 (새 로그인 수단 키 · URL scheme) | 다른 키는 자동 병합 · 같은 키는 내 값 |
| 24 | `android/app/src/main/AndroidManifest.xml` | 권한 · 메타데이터 | 중간 | 자동 병합을 먼저 보고, 충돌은 직접 합친다 |
| 25 | `firestore.rules` · `storage.rules` · `firestore.indexes.json` (+ `functions/test/rules/`) | 허용 필드 · 크기 제한 · 인덱스 | 중간 | 직접 합친 뒤 `functions/` 에서 `pnpm test:rules` |
| 26 | `functions/src/shared/region.ts` 의 `REGION` · `lib/core/config/app_config.dart` 의 `defaultFunctionsRegion` | 리전(`./setup.sh` 가 두 곳과 `config/dev.json` 의 `functionsRegion` 을 함께 바꾼다) | 중간 (`app_config.dart` 는 새 config 키마다 바뀐다) | 같은 줄이 충돌하면 리전 상수 줄만 내 값으로 남기고 나머지는 킷 값을 받는다 |
| 27 | `functions/src/messaging/test_push_copy.ts` 등 알림 문구 서버 파일 | 알림 문구 · 언어 | 중간 | 직접 합친다 |
| 28 | `ios/Runner/Runner.entitlements` | capability 추가 | 낮음 | 자동 병합을 먼저 보고, 충돌은 직접 합친다 |
| 29 | `README.md` | 내 앱 소개로 교체 | 중간 (킷이 안내를 고친다) | 내 값 |
| 30 | `.gitignore` · `.fvmrc` · `.vscode/settings.json` | 항목 추가 · Flutter SDK 버전 | 중간 (SDK 상향) | `.gitignore` 는 자동 병합 · SDK 버전은 킷 값을 받은 뒤 `fvm install` |
| 31 | `lib/features/<내 feature>/` · `test/features/<내 feature>/` | 사용자 전용 | 없음 | 충돌 없음 |
| 32 | `KIT_VERSION` · `CHANGELOG.md` · `LICENSE` · `CONTRIBUTING.md` · `.github/` · `setup.sh` · `bin/setup.dart` · `tool/setup/` | 고치지 않는다(킷 전용) | 높음 | 충돌 없음(고치지 않았다면) |
| 33 | `hosting/public/logo.png` | 결과 페이지 · 메일 로고 (킷 기본은 파일 없음) | 없음 | 충돌 없음 |
| 34 | `hosting/public/index.html` · `page.css` · `page.js` | 결과 페이지 모양 | 중간 | 직접 합친 뒤 `kit` 모드에서 `bash scripts/deploy_email.sh dev hosting` 으로 빌드를 확인한다 |
| 35 | `functions/src/email/copy.json` · `functions/src/email/templates/*.hbs` | 메일 · 결과 페이지 문구 · 메일 본문 | 중간 | 직접 합친 뒤 `functions/` 에서 `pnpm test` |
| 36 | `extensions/firestore-send-email.env.<projectId>` (git 밖 · 예시는 `extensions/firestore-send-email.env.example`) | 발송 서비스 값(`DATABASE_REGION` · `DEFAULT_FROM` · `SMTP_CONNECTION_URI` · `SMTP_PASSWORD`) | 높음 (새 파라미터 추가 · 내 파일은 git 밖) | 충돌 없음. merge 뒤 `diff extensions/firestore-send-email.env.example extensions/firestore-send-email.env.<projectId>` 로 새 키를 내 파일에 옮겨 적는다 |
| 37 | `functions/.env.<projectId>` (git 밖) | 함수 환경 값(`SEND_TEST_PUSH_ENABLED` 등) — `EMAIL_APP_NAME` · `EMAIL_BRAND_COLOR` · `EMAIL_LOGO_URL` · `EMAIL_RESULT_PAGE_URL` 네 줄은 `scripts/deploy_email.sh` 가 쓴다 | 없음 | 충돌 없음 |

### 확인 방법

`cat KIT_VERSION` 이 받은 판(`TAG` 에서 앞의 `v` 를 뺀 값)을 보여 주고, `git log -1 --format=%s` 가 merge 커밋 메시지(`킷 v1.0.0-rc.2 반영` 꼴)를 보여 주면 merge 가 끝난 것이다. 이어서 분석과 테스트를 돌린다.

```bash
fvm dart analyze
fvm flutter test
```

`No issues found!` 와 `All tests passed!` 가 나오면 된다. macOS 에서 iOS golden 이미지가 없다는 실패가 나오면 「문제 해결」 을 본다.

### 문제 해결

- **`fatal: refusing to merge unrelated histories`.** template 로 만든 저장소에서 기준점 없이 새 판을 merge 했다. 「시작하기 — template 로 앱 저장소 만들기」 ③ 의 기준점 merge 를 먼저 한다.
- **merge 가 「Your local changes … would be overwritten by merge」 로 시작되지 않는다.** 「충돌 풀기」 규칙 4 를 따른다. 목록에 skip-worktree 파일이 아닌 파일이 있으면 그 변경을 먼저 커밋한다.
- **macOS 에서 `goldens/*_ios.png` 가 없다는 테스트 실패 12건.** iOS 변형 golden 이미지는 폰트 라이선스 때문에 저장소에 없다. 내 Mac 에서 한 번 만든다.

```bash
fvm flutter test --update-goldens --plain-name '(iOS)' test/features/auth/presentation/_widgets/branded_social_button_golden_test.dart
```

- **패치 파일이나 `git apply -3` 으로 받지 않는다.** 내가 지운 파일이 하나라도 있으면 패치 전체가 적용되지 않는다. 판은 `git merge` 로만 받는다.

### 되돌리기

merge 도중이면(충돌을 풀다가 그만두려면) merge 전 상태로 돌아간다.

```bash
git merge --abort
```

「충돌 풀기」 규칙 4 의 블록 도중이었다면 이어서 블록의 마지막 세 줄로 복사본을 되돌려 놓고 skip-worktree 를 다시 건다.

merge 를 끝낸 뒤라면 그 merge 를 되돌리는 커밋을 더한다. 기록을 지우지 않고 반대 커밋을 더하는 방식이다. `<merge 커밋>` 에는 `git log --merges -1 --format=%H` 가 보여 주는 값을 넣는다.

```bash
git revert -m 1 <merge 커밋>
```

되돌린 판을 다시 받으려면 그 revert 커밋을 `git revert` 한다.

자세한 배경: 킷이 판을 내는 방법과 판 번호 규칙은 [유지보수자 문서](maintainer/kit-release-publishing.md)에 있다.

## 정적 분석 — woody_lints · riverpod_lint

## Git Hooks 활성화 (선택)

## Flutter SDK 상향 (FVM)

## iOS 의존성 관리 (SPM)

## 테스트 돌리기

## 알아 둘 동작
