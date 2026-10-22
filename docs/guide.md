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

킷 위에 첫 기능을 만드는 길을 한 예로 따라간다. 예는 사용자별 메모 목록이다 — 로그인한
사용자마다 Firestore `users/{uid}/memos` 에 자기 메모를 두고, 홈에서 들어가는 목록 화면
하나에서 메모를 추가(입력 시트)하고 지운다. 메모는 정식 사용자만 쓴다. 게스트가 「메모
추가」 를 누르면 킷의 로그인 권유 시트(`LoginPromptSheet`)가 뜬다.

**전제:**

- 위저드로 dev 설정을 끝내 앱이 실행된다([설정 위저드로 앱 준비하기](setup.md)).
- rules 시험을 돌리려면 `functions/` 에서 `pnpm install` 을 한 번 해 두고 JDK(Java 11
  이상)가 있어야 한다.

폴더 구조 · Freezed · Riverpod generator · import 순서 · 문서 주석 같은 코딩 규칙의 원문은
[코딩 규칙](../.claude/rules/flutter.md) 에 있다. 이 절의 코드는 그 규칙을 따르고, 킷의
알림 토큰 저장소(`lib/features/notifications/`)와 같은 꼴로 쓴다.

### ① 기능 폴더 만들기

기능 하나는 `lib/features/<기능>/` 아래에 층별 폴더로 둔다. 메모 기능이 만드는 파일은
아래와 같다. 시험은 `test/` 아래 같은 경로에, rules 시험은 `functions/test/rules/` 에
둔다.

```text
lib/features/memos/
├── domain/memo.dart                   # Freezed 모델
├── data/memo_repository.dart          # withConverter 저장소
├── application/memo_providers.dart    # 목록 · 추가 · 삭제 provider
└── presentation/
    ├── memo_list_screen.dart          # 목록 화면
    └── _widgets/memo_add_sheet.dart   # 입력 시트
test/features/memos/
├── data/memo_repository_test.dart
└── presentation/memo_list_screen_test.dart
functions/test/rules/memos.rules.test.ts
```

같은 기능 안의 파일끼리는 상대 경로로 import 한다. `_widgets/` 는 그 화면에서만 쓰는
위젯을 둔다.

### ② Freezed 모델

`lib/features/memos/domain/memo.dart` 를 만든다. 시각 필드는 킷의 `TimestampConverter`
로 Firestore Timestamp 와 `DateTime` 을 바꾼다. 문서 id 는 저장하지 않고 읽을 때만 채운다.

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/firestore/timestamp_converter.dart';

part 'memo.freezed.dart';
part 'memo.g.dart';

/// 메모 본문의 최대 글자 수 — `firestore.rules` 의 memos 규칙과 같다.
const int kMemoMaxLength = 500;

/// `users/{uid}/memos/{memoId}` 문서 모델.
///
/// 저장하는 키는 [text] · [createdAt] 둘이고 `firestore.rules` 의 memos
/// `hasOnly` 목록과 같아야 한다 — 필드를 더하면 rules 도 함께 고친다.
/// [id] 는 문서 id 를 담는 자리라 저장하지 않는다.
@freezed
abstract class Memo with _$Memo {
  /// [Memo] 를 생성한다.
  const factory Memo({
    /// 메모 본문.
    required String text,

    /// 만든 시각 (Firestore Timestamp).
    @TimestampConverter() required DateTime createdAt,

    /// 문서 id — 읽을 때 저장소가 채운다.
    @Default('')
    @JsonKey(includeFromJson: false, includeToJson: false)
    String id,
  }) = _Memo;

  /// JSON(Firestore 문서 데이터)에서 [Memo] 를 만든다.
  factory Memo.fromJson(Map<String, dynamic> json) => _$MemoFromJson(json);
}
```

`kMemoMaxLength` 는 ⑧ 의 rules 와 같은 값이다 — 한쪽을 바꾸면 다른 쪽도 바꾼다.

### ③ withConverter 저장소

`lib/features/memos/data/memo_repository.dart` 를 만든다. 컬렉션 참조를
`withConverter<Memo>` 로 고정하고, 쓰기는 킷의 `guardResult` 로 감싸 `Result<void>` 를
돌려준다. `guardResult` 의 첫 인자는 `'<저장소>_<메서드>'` 꼴의 코드 경로 이름이다 —
사용자 값 · 메모 본문은 넣지 않는다.

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/crashlytics/crashlytics_service.dart';
import '../../../core/error/guard_result.dart';
import '../../../core/error/result.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/memo.dart';

part 'memo_repository.g.dart';

/// `users/{uid}/memos` 타입 안전 저장소.
///
/// 컬렉션 참조를 `withConverter` 로 [Memo] 에 고정해 raw map 을 다루지 않는다.
/// 쓰기는 [guardResult] 를 거쳐 [Result] 를 돌려준다 — 예상치 못한 오류는
/// Crashlytics 에 1회 기록하고 실패로 바꾼다.
class MemoRepository {
  /// [MemoRepository] 를 생성한다.
  MemoRepository({
    required FirebaseFirestore firestore,
    required CrashlyticsService crashlytics,
  }) : _firestore = firestore,
       _crashlytics = crashlytics;

  final FirebaseFirestore _firestore;
  final CrashlyticsService _crashlytics;

  /// [uid] 의 memos 서브컬렉션을 [Memo] typed 참조로 돌려준다.
  CollectionReference<Memo> _memos(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('memos')
      .withConverter<Memo>(
        fromFirestore: (snapshot, _) {
          final data = snapshot.data();
          if (data == null) {
            throw StateError('memos 문서 데이터가 없다');
          }
          return Memo.fromJson(data).copyWith(id: snapshot.id);
        },
        toFirestore: (memo, _) => memo.toJson(),
      );

  /// [uid] 의 메모를 만든 시각 내림차순으로 지켜본다.
  Stream<List<Memo>> watchAll(String uid) => _memos(uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => [for (final doc in snapshot.docs) doc.data()]);

  /// [text] 로 [uid] 의 새 메모를 만든다.
  Future<Result<void>> add({required String uid, required String text}) =>
      guardResult('memo_repository_add', () async {
        await _memos(uid).add(Memo(text: text, createdAt: DateTime.now()));
      }, crashlytics: _crashlytics);

  /// [uid] 의 [memoId] 메모를 지운다.
  Future<Result<void>> delete({required String uid, required String memoId}) =>
      guardResult(
        'memo_repository_delete',
        () => _memos(uid).doc(memoId).delete(),
        crashlytics: _crashlytics,
      );
}

/// [MemoRepository] Provider.
@Riverpod(keepAlive: true)
MemoRepository memoRepository(Ref ref) {
  return MemoRepository(
    firestore: ref.watch(firebaseFirestoreProvider),
    crashlytics: ref.watch(crashlyticsServiceProvider),
  );
}
```

### ④ Riverpod provider

`lib/features/memos/application/memo_providers.dart` 를 만든다. 목록은 킷의
`authStateProvider` 로 지금 사용자를 보고, 게스트(익명) · 로그아웃이면 빈 목록이다. 추가 ·
삭제는 정식 사용자가 아니면 저장소를 부르지 않는다.

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/error/result.dart';
import '../../../core/providers/firebase_providers.dart';
import '../data/memo_repository.dart';
import '../domain/memo.dart';

part 'memo_providers.g.dart';

/// 로그인한 정식 사용자의 메모 목록 (만든 시각 내림차순).
///
/// 게스트(익명) · 로그아웃 상태는 빈 목록이다 — 메모는 정식 사용자만 쓴다.
@riverpod
Stream<List<Memo>> memoList(Ref ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null || user.isAnonymous) {
    return Stream.value(const <Memo>[]);
  }
  return ref.watch(memoRepositoryProvider).watchAll(user.uid);
}

/// 메모 추가 · 삭제를 맡는다.
///
/// 정식 사용자가 아니면 저장소를 부르지 않고 [UnauthenticatedException] 실패를
/// 돌려준다 — 화면의 `AuthRequired` 와 `firestore.rules` 도 같은 조건으로 막는다.
@riverpod
class MemoEditor extends _$MemoEditor {
  @override
  void build() {}

  /// [text] 로 새 메모를 만든다.
  Future<Result<void>> add(String text) {
    final uid = _regularUid();
    if (uid == null) {
      return Future.value(const Result.failure(UnauthenticatedException()));
    }
    return ref.read(memoRepositoryProvider).add(uid: uid, text: text);
  }

  /// [memoId] 메모를 지운다.
  Future<Result<void>> delete(String memoId) {
    final uid = _regularUid();
    if (uid == null) {
      return Future.value(const Result.failure(UnauthenticatedException()));
    }
    return ref.read(memoRepositoryProvider).delete(uid: uid, memoId: memoId);
  }

  /// 정식 사용자의 uid 를 돌려준다 — 게스트 · 로그아웃이면 null 이다.
  String? _regularUid() {
    final user = ref.read(authStateProvider).value;
    return user == null || user.isAnonymous ? null : user.uid;
  }
}
```

### ⑤ 목록 화면 · 추가 시트

목록 화면 `lib/features/memos/presentation/memo_list_screen.dart` 를 만든다. 「메모 추가」
버튼은 킷의 `AuthRequired` 로 감싼다 — 정식 사용자면 `onAuthenticated` 가 입력 시트를
띄우고, 게스트 · 로그아웃이면 `showLoginPromptSheet` 가 로그인 권유 시트를 띄운다. 목록 ·
불러오기 실패(「다시 시도」 버튼)는 킷의 `AsyncValueView` 가, 삭제 실패는
`showErrorSnackBar` 가 그린다.

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/error_snack_bar.dart';
import '../../auth/presentation/_widgets/auth_required.dart';
import '../application/memo_providers.dart';
import '../domain/memo.dart';
import '_widgets/memo_add_sheet.dart';

/// 메모 목록 화면 — 메모를 추가(입력 시트)하고 지운다.
///
/// 「메모 추가」 는 [AuthRequired] 로 감싸 게스트가 누르면 로그인 권유 시트를
/// 띄운다.
class MemoListScreen extends ConsumerWidget {
  /// [MemoListScreen] 을 생성한다.
  const MemoListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.memoListTitle)),
      floatingActionButton: AuthRequired(
        onAuthenticated: () => unawaited(showMemoAddSheet(context)),
        child: FloatingActionButton.extended(
          onPressed: null,
          icon: const Icon(Icons.add),
          label: Text(l10n.memoAddAction),
        ),
      ),
      body: AsyncValueView<List<Memo>>(
        value: ref.watch(memoListProvider),
        onRetry: () => ref.invalidate(memoListProvider),
        data: (memos) => memos.isEmpty
            ? Center(child: Text(l10n.memoEmpty))
            : ListView.builder(
                itemCount: memos.length,
                itemBuilder: (context, index) => _MemoTile(
                  key: ValueKey(memos[index].id),
                  memo: memos[index],
                ),
              ),
      ),
    );
  }
}

/// 메모 한 줄 — 본문과 삭제 버튼.
class _MemoTile extends ConsumerWidget {
  const _MemoTile({required this.memo, super.key});

  final Memo memo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(memo.text),
      trailing: IconButton(
        tooltip: context.l10n.memoDeleteAction,
        icon: const Icon(Icons.delete_outline),
        onPressed: () => unawaited(_delete(context, ref)),
      ),
    );
  }

  /// 메모를 지우고, 실패하면 SnackBar 로 알린다.
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final result = await ref.read(memoEditorProvider.notifier).delete(memo.id);
    if (!context.mounted) {
      return;
    }
    if (result case Failure(:final exception)) {
      showErrorSnackBar(context, exception);
    }
  }
}
```

입력 시트 `lib/features/memos/presentation/_widgets/memo_add_sheet.dart` 를 만든다. 저장에
실패하면 시트를 닫지 않고 입력란 아래에 킷의 오류 문구를 보인다.

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../../core/error/result.dart';
import '../../../../core/l10n/exception_l10n.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../application/memo_providers.dart';
import '../../domain/memo.dart';

/// 메모 입력 시트를 띄운다.
Future<void> showMemoAddSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const MemoAddSheet(),
  );
}

/// 메모 한 줄을 입력해 저장하는 시트.
class MemoAddSheet extends ConsumerStatefulWidget {
  /// [MemoAddSheet] 를 생성한다.
  const MemoAddSheet({super.key});

  @override
  ConsumerState<MemoAddSheet> createState() => _MemoAddSheetState();
}

class _MemoAddSheetState extends ConsumerState<MemoAddSheet> {
  final _controller = TextEditingController();
  bool _isSaving = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 입력을 저장한다 — 성공하면 시트를 닫고, 실패하면 입력란 아래에 알린다.
  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSaving) {
      return;
    }
    setState(() => _isSaving = true);
    final result = await ref.read(memoEditorProvider.notifier).add(text);
    if (!mounted) {
      return;
    }
    switch (result) {
      case Success():
        Navigator.of(context).pop();
      case Failure(:final exception):
        setState(() {
          _isSaving = false;
          _errorText = resolveExceptionMessage(context, exception);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.lg,
        0,
        spacing.lg,
        spacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: kMemoMaxLength,
            decoration: InputDecoration(
              hintText: l10n.memoInputHint,
              errorText: _errorText,
            ),
            onSubmitted: (_) => unawaited(_save()),
          ),
          Gap(spacing.md),
          FilledButton(
            onPressed: _isSaving ? null : _save,
            child: Text(l10n.memoAddAction),
          ),
        ],
      ),
    );
  }
}
```

### ⑥ 홈 하위 라우트와 진입 버튼

1. `lib/core/router/app_routes.dart` 의 `AppRoutes` 에 경로 상수 셋(GoRoute 용 조각 · 전체
   경로 · name)을 더한다. `developerDemoName` 상수 다음에 빈 줄 하나를 두고 넣는다.

```dart
  /// 메모 목록 화면의 홈 하위 상대 경로 조각 — GoRoute.path 전용.
  static const String memosSegment = 'memos';

  /// 메모 목록 화면 path.
  static const String memos = '/$memosSegment';

  /// 메모 목록 화면 name.
  static const String memosName = 'memos';
```

2. `lib/core/router/app_router.dart` 에서 import 목록의 `home_screen.dart` 줄 다음에 아래
   줄을 넣는다.

```dart
import '../../features/memos/presentation/memo_list_screen.dart';
```

3. 같은 파일의 홈 `GoRoute`(`path: AppRoutes.home`) 의 `routes:` 목록 맨 끝 — 약관
   (`AppRoutes.termsPrivacySegment`) `GoRoute` 다음 — 에 아래를 넣는다. 홈 하위에 두면
   목록 화면에서 「뒤로」 가 홈으로 돌아온다.

```dart
          GoRoute(
            path: AppRoutes.memosSegment,
            name: AppRoutes.memosName,
            builder: (context, state) => const MemoListScreen(),
          ),
```

4. 라우트 개수를 세는 킷 시험을 고친다. `test/core/router/app_router_observers_test.dart`
   는 라우트 전체(하위 포함) 개수와 name 개수를 14 로 센다. 라우트 하나를 더했으므로 두
   곳을 15 로 바꾼다(최상위 개수 8 은 그대로).

```dart
        expect(
          collectGoRoutes(router.configuration.routes).length,
          15,
          reason: '재귀 15',
        );
```

```dart
      expect(names.length, 15);
```

   킷 업데이트를 받을 때 이 시험 파일이 충돌할 수 있다 — 합치는 법은
   [킷 업데이트 반영](#킷-업데이트-반영) 에 있다.

5. 홈 본문 `lib/features/home/presentation/home_body.dart` 에 진입 버튼을 둔다. 개발자 안내
   카드의 「데모 화면 열기」 버튼(`FilledButton.tonal`) 다음에 아래를 넣는다. release
   빌드의 홈 본문은 비어 있으므로, 내 홈 화면을 만들 때([홈 화면 바꾸기](#홈-화면-바꾸기))
   이 버튼을 그 본문으로 옮긴다.

```dart
              Gap(spacing.sm),
              FilledButton.tonal(
                onPressed: () => context.push(AppRoutes.memos),
                child: Text(l10n.memoListTitle),
              ),
```

   홈 본문이 바뀌므로 홈 golden 은 ⑩ 에서 다시 만든다.

### ⑦ ARB 세 언어

`lib/l10n/app_en.arb` · `app_ko.arb` · `app_ja.arb` 에 같은 키 다섯을 더한다. 각 파일의
맨 끝 항목(`app_en.arb` 는 `@` 설명 블록의 닫는 `}`, `app_ko.arb` · `app_ja.arb` 는 문자열
값) 뒤에 쉼표를 붙이고, 파일의 마지막 `}` 앞에 아래 줄을 넣는다. 설명(`@` 키)은 템플릿
파일인 `app_en.arb` 에만 둔다.

`lib/l10n/app_en.arb`:

```json
  "memoListTitle": "Memos",
  "@memoListTitle": {
    "description": "Memo list screen title and the home entry button label"
  },

  "memoAddAction": "Add memo",
  "@memoAddAction": {
    "description": "Memo list add button and memo input sheet save button label"
  },

  "memoEmpty": "No memos yet.",
  "@memoEmpty": {
    "description": "Memo list empty state message"
  },

  "memoInputHint": "Write a memo",
  "@memoInputHint": {
    "description": "Memo input sheet text field hint"
  },

  "memoDeleteAction": "Delete memo",
  "@memoDeleteAction": {
    "description": "Memo list delete button tooltip"
  }
```

`lib/l10n/app_ko.arb`:

```json
  "memoListTitle": "메모",
  "memoAddAction": "메모 추가",
  "memoEmpty": "아직 메모가 없어요.",
  "memoInputHint": "메모를 입력하세요",
  "memoDeleteAction": "메모 삭제"
```

`lib/l10n/app_ja.arb`:

```json
  "memoListTitle": "メモ",
  "memoAddAction": "メモを追加",
  "memoEmpty": "メモはまだありません。",
  "memoInputHint": "メモを入力",
  "memoDeleteAction": "メモを削除"
```

### ⑧ Firestore rules 와 rules 시험

`firestore.rules` 의 `match /users/{userId}` 안, 알림 토큰 블록(`match /fcmTokens/{token}`)
의 닫는 `}` 다음에 아래를 넣는다. 알림 토큰과 같은 꼴이다 — 본인(`isOwner`)이면서 정식
사용자(`isRegular`)만 읽고 쓰고, 저장 키는 `hasOnly` 로 모델의 두 키만 받는다. 본문 길이
상한은 ② 의 `kMemoMaxLength` 와 같다. 메모 고치기는 화면에 없으므로 `update` 는 열지
않는다.

```text
      // memos 서브컬렉션 — 정식 사용자 본인의 메모.
      match /memos/{memoId} {
        allow read, delete: if isOwner(userId) && isRegular();
        allow create: if isOwner(userId) && isRegular()
          && request.resource.data.keys().hasOnly(['text', 'createdAt'])
          && request.resource.data.text is string
          && request.resource.data.text.size() > 0
          && request.resource.data.text.size() <= 500
          && request.resource.data.createdAt is timestamp;
      }
```

rules 시험 `functions/test/rules/memos.rules.test.ts` 를 만든다. 본인 허용 · 키 · 길이
위반 거부 · 게스트 거부 · 다른 사용자 거부를 에뮬레이터에서 확인한다.

```ts
// `pnpm test:rules` 전용 — users/{uid}/memos 규칙을 에뮬레이터에서 확인한다.
import {readFileSync} from "fs";
import * as path from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import type {
  RulesTestContext,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  deleteDoc,
  doc,
  getDoc,
  setDoc,
  setLogLevel,
  Timestamp,
} from "firebase/firestore";

const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

let testEnv: RulesTestEnvironment;

/**
 * 정식(비익명) 사용자 context 를 만든다.
 * @param {string} uid 인증 uid.
 * @return {RulesTestContext} context.
 */
function regularUser(uid: string): RulesTestContext {
  return testEnv.authenticatedContext(uid, {
    firebase: {sign_in_provider: "google.com"},
  });
}

/**
 * 게스트(익명) 사용자 context 를 만든다.
 * @param {string} uid 익명 uid.
 * @return {RulesTestContext} context.
 */
function anonymousUser(uid: string): RulesTestContext {
  return testEnv.authenticatedContext(uid, {
    firebase: {sign_in_provider: "anonymous"},
  });
}

/**
 * 앱이 쓰는 꼴의 메모 문서를 만든다.
 * @param {string} text 본문.
 * @return {Record<string, unknown>} 메모 문서.
 */
function memo(text: string): Record<string, unknown> {
  return {text, createdAt: Timestamp.now()};
}

beforeAll(async () => {
  setLogLevel("error");
  testEnv = await initializeTestEnvironment({
    projectId: "demo-starter-kit",
    firestore: {rules: readFileSync(RULES_PATH, "utf8")},
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

afterAll(async () => {
  await testEnv.cleanup();
});

describe("users/{uid}/memos rules", () => {
  it("정식 사용자 본인은 메모를 쓰고 읽고 지운다", async () => {
    const alice = regularUser("alice").firestore();
    const memoPath = "users/alice/memos/m1";
    await assertSucceeds(setDoc(doc(alice, memoPath), memo("hello")));
    await assertSucceeds(getDoc(doc(alice, memoPath)));
    await assertSucceeds(deleteDoc(doc(alice, memoPath)));
  });

  it("정한 키 밖 · 빈 본문 · 너무 긴 본문은 거부한다", async () => {
    const alice = regularUser("alice").firestore();
    await assertFails(
      setDoc(doc(alice, "users/alice/memos/m2"), {...memo("hi"), extra: 1}),
    );
    await assertFails(setDoc(doc(alice, "users/alice/memos/m3"), memo("")));
    await assertFails(
      setDoc(doc(alice, "users/alice/memos/m4"), memo("a".repeat(501))),
    );
  });

  it("게스트 · 다른 사용자는 거부한다", async () => {
    const ghost = anonymousUser("ghost").firestore();
    await assertFails(setDoc(doc(ghost, "users/ghost/memos/m5"), memo("hi")));
    const bob = regularUser("bob").firestore();
    await assertFails(setDoc(doc(bob, "users/alice/memos/m6"), memo("hi")));
    await assertFails(getDoc(doc(bob, "users/alice/memos/m6")));
  });
});
```

저장소 루트에서 rules 시험을 돌린다. Firestore · Storage 에뮬레이터가 `demo-` 프로젝트로
떠서 실제 Firebase 프로젝트에 접속하지 않는다.

```bash
cd functions && pnpm test:rules
```

### ⑨ unit · widget 시험

저장소 시험 `test/features/memos/data/memo_repository_test.dart` 를 만든다. Firestore 는
mocktail 로 대신하고(킷의 `fcm_token_repository_test.dart` 와 같은 꼴), 추가 성공 · 저장
키 · 오류 처리를 본다. 저장 키 시험은 모델의 키가 ⑧ 의 `hasOnly` 목록과 어긋나면 실패한다.

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/memos/data/memo_repository.dart';
import 'package:flutter_starter_kit/features/memos/domain/memo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

// cloud_firestore 의 sealed 타입을 mocktail mock 으로 대신하는 시험 전용 우회다.
// ignore: subtype_of_sealed_class
class _MockRawCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

// cloud_firestore 의 sealed 타입을 mocktail mock 으로 대신하는 시험 전용 우회다.
// ignore: subtype_of_sealed_class
class _MockRawDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

// cloud_firestore 의 sealed 타입을 mocktail mock 으로 대신하는 시험 전용 우회다.
// ignore: subtype_of_sealed_class
class _MockMemoCollection extends Mock implements CollectionReference<Memo> {}

// cloud_firestore 의 sealed 타입을 mocktail mock 으로 대신하는 시험 전용 우회다.
// ignore: subtype_of_sealed_class
class _MockMemoDoc extends Mock implements DocumentReference<Memo> {}

class _FakeStackTrace extends Fake implements StackTrace {}

void main() {
  late _MockCrashlyticsService crashlytics;
  late _MockMemoCollection memos;
  late MemoRepository repository;
  ToFirestore<Memo>? capturedToFirestore;

  setUpAll(() {
    registerFallbackValue(_FakeStackTrace());
    registerFallbackValue(
      Memo(text: 'fallback', createdAt: DateTime.utc(2026)),
    );
    // mocktail 은 `element is T` 로 fallback 을 찾는다 — 파라미터 타입을
    // 명시한 함수 선언이라야 런타임 타입이 typedef 와 같아진다.
    Memo fromFallback(
      DocumentSnapshot<Map<String, dynamic>> _,
      SnapshotOptions? _,
    ) => throw UnimplementedError();
    Map<String, Object?> toFallback(Memo _, SetOptions? _) =>
        <String, Object?>{};
    registerFallbackValue(fromFallback);
    registerFallbackValue(toFallback);
  });

  setUp(() {
    crashlytics = _MockCrashlyticsService();
    memos = _MockMemoCollection();
    capturedToFirestore = null;
    final firestore = _MockFirestore();
    final users = _MockRawCollection();
    final userDoc = _MockRawDoc();
    final rawMemos = _MockRawCollection();

    when(
      () => crashlytics.recordError(
        any<Object>(),
        any<StackTrace?>(),
        reason: any(named: 'reason'),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});
    when(() => firestore.collection('users')).thenReturn(users);
    when(() => users.doc(any())).thenReturn(userDoc);
    when(() => userDoc.collection('memos')).thenReturn(rawMemos);
    when(
      () => rawMemos.withConverter<Memo>(
        fromFirestore: any(named: 'fromFirestore'),
        toFirestore: any(named: 'toFirestore'),
      ),
    ).thenAnswer((invocation) {
      final to = invocation.namedArguments[#toFirestore];
      if (to is ToFirestore<Memo>) capturedToFirestore = to;
      return memos;
    });

    repository = MemoRepository(firestore: firestore, crashlytics: crashlytics);
  });

  test('add 는 typed 컬렉션에 메모를 더하고 성공을 돌려준다', () async {
    when(() => memos.add(any())).thenAnswer((_) async => _MockMemoDoc());

    final result = await repository.add(uid: 'alice', text: 'hello');

    expect(result, isA<Success<void>>());
    final added = verify(() => memos.add(captureAny())).captured.single;
    expect(added, isA<Memo>().having((memo) => memo.text, 'text', 'hello'));
  });

  test('저장하는 키는 rules 의 hasOnly 목록과 같다', () async {
    when(() => memos.add(any())).thenAnswer((_) async => _MockMemoDoc());
    await repository.add(uid: 'alice', text: 'hello');

    final toFirestore = capturedToFirestore;
    if (toFirestore == null) {
      fail('withConverter 의 toFirestore 를 받지 못했다');
    }
    final json = toFirestore(
      Memo(text: 'hello', createdAt: DateTime.utc(2026)),
      null,
    );
    expect(json.keys.toSet(), {'text', 'createdAt'});
  });

  test('Firestore 오류는 실패로 바꾸고 Crashlytics 에 기록한다', () async {
    when(() => memos.add(any())).thenThrow(
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
    );

    final result = await repository.add(uid: 'alice', text: 'hello');

    expect(
      result,
      isA<Failure<void>>().having(
        (failure) => failure.exception,
        'exception',
        isA<UnknownException>(),
      ),
    );
    verify(
      () => crashlytics.recordError(
        any<Object>(),
        any<StackTrace?>(),
        reason: 'memo_repository_add',
        fatal: any(named: 'fatal'),
      ),
    ).called(1);
  });
}
```

목록 화면 시험 `test/features/memos/presentation/memo_list_screen_test.dart` 를 만든다.
목록 provider 를 override 해 빈 상태와 메모 줄을 본다.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/features/memos/application/memo_providers.dart';
import 'package:flutter_starter_kit/features/memos/domain/memo.dart';
import 'package:flutter_starter_kit/features/memos/presentation/memo_list_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// [memos] 를 목록 provider 값으로 주고 [MemoListScreen] 을 띄운다.
Future<void> _pumpScreen(WidgetTester tester, List<Memo> memos) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [memoListProvider.overrideWith((ref) => Stream.value(memos))],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MemoListScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  testWidgets('메모가 없으면 빈 상태 문구와 추가 버튼을 보인다', (tester) async {
    await _pumpScreen(tester, const <Memo>[]);

    expect(find.text(en.memoEmpty), findsOneWidget);
    expect(find.text(en.memoAddAction), findsOneWidget);
  });

  testWidgets('메모마다 본문과 삭제 버튼을 보인다', (tester) async {
    await _pumpScreen(tester, [
      Memo(id: 'm2', text: 'second', createdAt: DateTime.utc(2026, 2, 3)),
      Memo(id: 'm1', text: 'first', createdAt: DateTime.utc(2026, 2, 2)),
    ]);

    expect(find.text('second'), findsOneWidget);
    expect(find.text('first'), findsOneWidget);
    expect(find.byTooltip(en.memoDeleteAction), findsNWidgets(2));
  });
}
```

### ⑩ 코드 생성 · 분석 · 시험

저장소 루트에서 차례로 돌린다. Freezed · Riverpod 코드를 만들고, ARB 문구를 생성한다.

```bash
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter gen-l10n
```

⑥ 에서 홈 본문에 버튼을 더했으므로 홈 golden 두 장을 이 파일 하나로 다시 만든다.

```bash
fvm flutter test --update-goldens test/features/home/home_announcement_golden_test.dart
```

분석 두 가지와 전체 시험, rules 시험을 돌린다. 분석은 둘 다 `No issues found!` 여야 한다
— Riverpod 규칙 진단은 `fvm dart analyze` 에만 나온다.

```bash
fvm flutter analyze
fvm dart analyze
fvm flutter test
cd functions && pnpm test:rules
```

### 확인 방법

1. 바꾼 rules 를 dev 프로젝트에 올린다. `<your-project-id>` 는 `config/dev.json` 의
   `firebaseProjectId` 값이다.

```bash
firebase deploy --only firestore:rules --project <your-project-id>
```

2. 앱을 실행한다.

```bash
fvm flutter run --flavor dev --dart-define-from-file=config/dev.json
```

3. 정식 사용자로 로그인한 뒤 홈의 「Memos」(한국어 화면은 「메모」) 버튼을 누른다. 「메모
   추가」 → 입력 → 「메모 추가」 를 누르면 시트가 닫히고 메모가 목록 맨 위에 생긴다.
   Firebase 콘솔 Firestore 의 `users/<uid>/memos` 에 문서가 하나 생긴다. 휴지통 아이콘을
   누르면 목록과 콘솔에서 사라진다.
4. 로그아웃한 뒤 게스트로 들어가 홈의 같은 버튼으로 목록을 연다. 목록은 비어 있고,
   「메모 추가」 를 누르면 로그인 권유 시트가 뜬다.

- **정식 사용자인데 저장하면 입력란 아래에 오류 문구가 나오거나, 목록이 「다시 시도」 와
  함께 오류를 보인다:** 프로젝트의 rules 에 memos 블록이 없다 — 1번의 배포를 하지 않았거나
  다른 프로젝트에 올렸다. `--project` 값을 확인하고 다시 배포한 뒤 「다시 시도」 를 누른다.

### 되돌리기

1. 만든 파일을 지운다 — `lib/features/memos/` · `test/features/memos/` ·
   `functions/test/rules/memos.rules.test.ts`.
2. ⑥ 에서 더한 경로 상수 셋 · import 줄 · `GoRoute` · 홈 진입 버튼을 지우고,
   `app_router_observers_test.dart` 의 두 개수를 14 로 돌린다.
3. ⑦ 의 ARB 키 다섯을 세 파일에서 지우고 `fvm flutter gen-l10n` 을 돌린다.
4. ⑧ 의 `match /memos/{memoId}` 블록을 지우고 확인 방법 1번의 명령으로 rules 를 다시
   배포한다. 이미 쓴 메모 문서는 Firebase 콘솔에서 지운다.
5. ⑩ 의 순서(코드 생성 → 홈 golden 다시 만들기 → 분석 · 시험)를 다시 돌린다.

## 디자인 토큰 바꾸기

앱의 색 · 글자 스타일 · 간격 · 아이콘 크기 · 화면 폭 분기 · 키보드 포커스 테두리를 내 앱에 맞게 바꾸는 절차다. 브랜드 색 하나만 바꾸려면 아래 1번의 `brandColor` 만 고친다.

**전제:** 위저드로 처음 설정을 끝내 `config/dev.json` 이 있다([설정 위저드로 앱 준비하기](setup.md)).

킷의 디자인 토큰은 **`ThemeExtension` 4종** 이다.

| Extension | 파일 | 담는 것 |
|---|---|---|
| `AppColors` | `lib/core/theme/app_colors.dart` | `ColorScheme` 에 없는 앱 고유 시맨틱 컬러 6종 |
| `AppTypography` | `lib/core/theme/app_typography.dart` | M3 `TextTheme` 15 스타일의 **override 레이어** |
| `AppSpacing` | `lib/core/theme/app_spacing.dart` | 4 의 배수 간격 스케일 7단계 |
| `AppIconSizes` | `lib/core/theme/app_icon_sizes.dart` | 아이콘 크기 토큰 — `sm` 20 1단계 |

네 extension 을 `ThemeData` 로 조립하는 곳은 `AppTheme.light()` / `AppTheme.dark()`
(`lib/core/theme/app_theme.dart`) 이고, 앱이 테마를 넘기는 곳은 `lib/app.dart` 의
`theme: AppTheme.light(seedColor: seed),` / `darkTheme: AppTheme.dark(seedColor: seed),`
두 줄이다. `ColorScheme` 은 시드 색 하나에서 `ColorScheme.fromSeed` 로 파생되고,
extension 4종은 `AppColors.fromBrightness(...)` · `AppTypography.empty` ·
`const AppSpacing()` · `const AppIconSizes()` 순서로 등록된다.

이 밖에 반응형은 `AppBreakpoint` + `ResponsiveX`
(`lib/core/theme/app_breakpoint.dart`) 가, 키보드 focus outline 은
`BrandFocusWrapper` (`lib/core/theme/brand_focus_wrapper.dart`) 가 맡는다.

앱 코드는 `ThemeX` extension(`lib/core/theme/theme_extensions.dart`) 의
**여섯 getter** 로 토큰을 읽는다.

| getter | 반환 | extension 미등록 테마에서의 동작 |
|---|---|---|
| `context.appColors` | `AppColors` | `AppColors.fromBrightness(theme.brightness)` 로 폴백 |
| `context.appTypography` | `AppTypography` (합성 결과) | 테마 `textTheme` 기하를 그대로 반영 |
| `context.appSpacing` | `AppSpacing` | `const AppSpacing()` 으로 폴백 |
| `context.appIconSizes` | `AppIconSizes` | `const AppIconSizes()` 으로 폴백 |
| `context.colorScheme` | `ColorScheme` | `Theme.of` 직통 |
| `context.textTheme` | `TextTheme` | `Theme.of` 직통 — **extension override 미반영** |

네 토큰 getter 는 extension 이 등록되지 않은 테마에서도 기본 토큰으로 폴백하므로,
자체 `ThemeData` 를 쓰거나 위젯 테스트에서 맨몸 `MaterialApp()` 을 써도 크래시하지
않는다.

소셜 로그인 버튼(`lib/features/auth/presentation/_widgets/branded_social_button.dart`)은
앱 테마의 색 · 글자 스타일을 읽지 않는다 — 디자인 토큰을 바꿔도 버튼 외관은 그대로다.
버튼 높이 `kBrandButtonHeight`(48) · 모서리 `kBrandButtonRadius`(12) 같은 파일 상단
상수는 여섯 provider 버튼이 함께 쓰는 공통 골격이고 각 provider 의 브랜드 가이드에 맞춘
값이라, 디자인 토큰 작업에서는 고치지 않는다.

### 1. 시드 컬러 교체 — M3 팔레트 전체 전환

앱의 시드 색은 config 의 `brandColor` 다. `lib/app.dart` 가 이 값을 읽어 라이트 · 다크
테마에 같은 시드로 넘긴다.

```dart
final Color seed =
    AppConfig.parseBrandColor(AppConfig.brandColor) ?? AppTheme.seedColor;
```

**① config 의 `brandColor` 를 바꾼다.** `config/dev.json` 의 `brandColor` 를 `#RRGGBB`
형식으로 쓴다. 아래는 example 파일의 값이다.

```json
"brandColor": "#673AB7"
```

비우거나 형식이 틀리면 `app_theme.dart` 의 상수 `AppTheme.seedColor`
(`Colors.deepPurple`)로 칠한다. 같은 `brandColor` 가 `kit` 발송 모드 메일과 결과
페이지의 색에도 쓰인다 — `kit` 모드면 [발송 모드 절](#인증-메일-발송-모드-켜고-끄기)
「켜기」 ④ · ⑥ 을 다시 한다. stg · prod 는 `config/stg.json` · `config/prod.json` 의
같은 키다.

**② 앱을 다시 빌드한다.** `brandColor` 는 빌드 때 들어간다.

```bash
fvm flutter run --flavor dev --dart-define-from-file=config/dev.json
```

- 시드 하나에서 `ColorScheme.fromSeed` 가 M3 팔레트 **전체**(primary /
  secondary / tertiary / surface / error 및 각 `on-` 쌍)를 파생하므로,
  개별 색을 일일이 지정하지 않아도 된다.
- 앱 색만 메일 · 결과 페이지와 다르게 하려면 `lib/app.dart` 의 두 줄에 시드를 직접
  넘긴다(예: `theme: AppTheme.light(seedColor: Colors.teal),` /
  `darkTheme: AppTheme.dark(seedColor: Colors.teal),`). **라이트와 다크에 같은 시드를
  넘긴다** — 서로 다른 시드를 넘기면 두 모드의 팔레트가 어긋난다.
- 상수 `AppTheme.seedColor` 를 고쳐도 되지만 킷 새 판을 받을 때 충돌하므로 config 의
  `brandColor` 를 쓴다.

### 2. 타이포그래피 계약 — `context.appTypography` 가 유일한 경로

1. **`AppTheme` 이 등록하는 extension 은 `AppTypography.empty` 다.** 15 필드가 모두
   빈 `TextStyle()` 인 **순수 override 레이어**이고, 기하(fontSize / fontWeight /
   baseline / fontFamily)를 하나도 담지 않는다.
2. **완성된 스타일은 반드시 `context.appTypography` 로 얻는다.**
   `ThemeX.appTypography` 는 호출 시점에
   `AppTypography.fromTextTheme(Theme.of(context).textTheme).merge(등록된 override)`
   를 계산한다. 로케일 기하가 적용된 테마 `textTheme` 을 밑바탕으로 사용자 override 를
   얹은 **합성 결과**다.
3. **⚠ `Theme.of(context).extension<AppTypography>()` 를 직접 읽지 않는다.**
   등록된 값이 `AppTypography.empty` 라 **빈 스타일**이 돌아온다. 크래시도 경고도
   없이 글자가 기본값으로 그려져 늦게 발견된다.
4. **override 를 등록하지 않은 기본 상태에서는 `context.appTypography.X` 와
   `context.textTheme.X` 가 같은 값이다.** ko/ja 로케일의 dense 기하
   (`textBaseline: ideographic`)가 Flutter 의 `ThemeData.localize` 를 거쳐 자동
   반영되게 하려는 구조다. 기하를 extension 에 미리 넣어 두면 로케일을 바꿀 때
   어긋난다.
5. **글꼴은 `ThemeData(fontFamily:)` 또는 `textTheme` 으로 바꾼다** — extension 을
   건드리지 않는다. 등록 레이어에 `fontFamily` 가 있으면 `merge` 단계에서 사용자가
   바꾼 글꼴을 다시 덮어쓴다. 등록 레이어를 `empty` 로 두는 까닭이다.

일부 스타일만 바꾸려면 `AppTypography.empty.copyWith(...)` 로 override 를 채워
등록한다. `lib/app.dart` 의 `theme:` 줄에서 `AppTheme.light(seedColor: seed)` 뒤에
`copyWith` 를 붙인다(다크도 같은 꼴로 `Brightness.dark` 를 쓴다).

```dart
// 타이포그래피 부분 override — extensions 리스트에 4종을 모두 넣는다.
theme: AppTheme.light(seedColor: seed).copyWith(
  extensions: <ThemeExtension<dynamic>>[
    AppColors.fromBrightness(Brightness.light),
    const AppSpacing(),
    const AppIconSizes(),
    AppTypography.empty.copyWith(
      bodyMedium: const TextStyle(fontSize: 15, height: 1.5),
      titleLarge: const TextStyle(fontWeight: FontWeight.w700),
    ),
  ],
),
```

> ⚠ **`ThemeData.copyWith(extensions:)` 는 기존 extension map 을 통째로
> 교체한다** (병합하지 않는다). 위 리스트에서 `AppTypography` 만 넘기면
> `AppColors` · `AppSpacing` · `AppIconSizes` 가 **등록에서 사라진다**.
> `ThemeX` 의 폴백 덕에 크래시는 나지 않지만, `copyWith` 로 조정해 둔 색 · 간격
> 값이 조용히 기본 토큰으로 돌아간다. **항상 네 원소를 모두 나열한다.**

`copyWith` 에 넘길 수 있는 인자는 M3 15 스타일과 같은 이름이다 —
`displayLarge` / `displayMedium` / `displaySmall` / `headlineLarge` /
`headlineMedium` / `headlineSmall` / `titleLarge` / `titleMedium` /
`titleSmall` / `bodyLarge` / `bodyMedium` / `bodySmall` / `labelLarge` /
`labelMedium` / `labelSmall`. 지정하지 않은 속성은 `TextStyle.merge` 로 테마 값이
유지되므로, `fontSize` 만 바꾸고 `fontWeight` 는 테마를 따르는 부분 override 를 할
수 있다.

### 3. 시맨틱 컬러 · 간격 커스터마이징

**`AppColors`** 는 `ColorScheme` 에 없는 앱 고유 시맨틱 컬러 6종
(`success` / `warning` / `info` + 각각의 `onSuccess` / `onWarning` / `onInfo`)
을 담는다. `AppColors.fromBrightness(Brightness)` 로 라이트/다크 기본 토큰을
만들고 `copyWith` 로 개별 색만 바꾼다.

```dart
AppColors.fromBrightness(Brightness.light)
    .copyWith(success: const Color(0xFF00897B));
```

**`AppSpacing`** 은 **4 의 배수 7단계**다(등차 4dp 가 아니다 — `xl` 은 `lg` 의
+8 이다).

| 토큰 | 값 (dp) | 토큰 | 값 (dp) |
|---|---|---|---|
| `xs` | 4 | `xl` | 24 |
| `sm` | 8 | `xxl` | 32 |
| `md` | 12 | `xxxl` | 48 |
| `lg` | 16 | | |

`const AppSpacing()` 이 기본값이고, `const AppSpacing().copyWith(md: 16)` 처럼
개별 단계만 조정한다.

**`AppIconSizes`** 는 아이콘 크기 토큰이다. `sm` = 20(본문 줄과 나란히 놓이는
인라인 아이콘 — 공용 `ErrorBanner` 의 `error_outline`) 1단계만 둔다. 기본 아이콘
크기 24 는 `IconThemeData` 가 정하므로 토큰을 두지 않고 `size` 를 생략한다.
`const AppIconSizes().copyWith(sm: 18)` 처럼 조정하면 오류 배너 아이콘이 함께
바뀐다. 로그인 · 인증 화면 일부 아이콘은 크기를 숫자로 정해 이 토큰을 따르지 않는다.

세 extension(`AppColors` · `AppSpacing` · `AppIconSizes`) 모두 위 2번의
`extensions:` 리스트에 함께 넣어 등록한다.

- **네 extension 은 모든 필드로 `==` / `hashCode` 를 비교한다.** 그래서 `lib/app.dart`
  처럼 `build` 안에서 테마를 매번 새로 만들어도 `ThemeData` 가 같다고 판정되고,
  `copyWith` 로 바꾼 테마도 App 을 다시 그릴 때마다 테마 전환 애니메이션이 다시 돌지
  않는다. 직접 extension 을 더 만들 때도 `==` / `hashCode` 를 모든 필드로 구현한다.
- **extension 이 등록되지 않은 테마에서도 네 토큰 getter 는 크래시하지 않는다.**
  `AppTheme` 을 쓰지 않고 자체 `ThemeData` 를 만들거나 위젯 테스트가 맨몸
  `MaterialApp()` 을 써도 기본 토큰으로 폴백한다.

### 4. 반응형 breakpoint 계약

모바일 전용 3단계다(`lib/core/theme/app_breakpoint.dart`).

| breakpoint | 범위 (dp) | 대상 |
|---|---|---|
| `compact` | 280 이상 ~ 360 미만 | 소형 디바이스 |
| `medium` | 360 이상 ~ 600 미만 | 일반 모바일 |
| `expanded` | 600 이상 ~ 674 미만 | 대형 모바일 / 폴더블 |

- **하한 포함, 상한 배타**다. 판정 기준은
  `contains(width) => width >= minWidth && width < maxWidth` 하나이고
  `fromWidth` 가 거기서 파생되므로, **인접한 두 breakpoint 가 동시에 참인
  경계값은 없다**(360dp 는 `medium` 단독, 600dp 는 `expanded` 단독).
- 지원 범위(280~674dp) 밖은 **양끝으로 포화**한다 — 279dp 는 `compact`,
  가로 모드의 800dp 는 `expanded` 로 떨어진다.

> ⚠ **`maxWidth` 를 실제 가용 폭으로 쓰지 않는다.** `maxWidth` 는 「선언된 지원
> 상한」 이다. 포화 정책 때문에 800dp 화면에서도 `expanded.maxWidth` 는 674 를
> 돌려주므로, 이 값을 `clamp` 등 레이아웃 계산에 그대로 넣으면 화면이 674dp 로
> 잘린다.

컨테이너의 **지역 제약**을 기준으로 분기하려면 `LayoutBuilder` 안에서
`fromWidth` 를 직접 호출한다.

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final bp = AppBreakpoint.fromWidth(constraints.maxWidth);
    return bp == AppBreakpoint.compact ? const _Narrow() : const _Wide();
  },
);
```

`context.breakpoint` 는 `MediaQuery.sizeOf(context).width`, 즉 **화면 전체 폭**
기준이다. 그래서 bottom sheet, 분할 레이아웃, 패딩된 칼럼 안에서는 실제 가용 폭과
어긋난다 — 640dp 화면 안의 300dp 컨테이너에서 `context.breakpoint` 는 `expanded`
지만 지역 breakpoint 는 `compact` 다. 화면 방향은 `context.isLandscape` /
`context.isPortrait`(후자는 전자의 부정으로 파생) 로 읽는다.

### 5. 키보드 focus outline (접근성)

`BrandFocusWrapper` (`lib/core/theme/brand_focus_wrapper.dart`) 는 브랜드 규격이
고정된 버튼을 감싸 **키보드 focus 도착 시에만** outline 을 그린다
(WCAG 2.1 SC 2.4.7 Focus Visible, Level AA). 소셜 로그인 버튼은 이 wrapper 로
감싸져 있고, 내 버튼에도 같은 wrapper 를 쓸 수 있다.

- 생성자는 다음과 같고, `borderRadius` 는 음수를 `assert` 로 거부한다.

  ```dart
  BrandFocusWrapper({
    required Widget child,
    required double borderRadius,
    bool isEnabled = true,
  })
  ```

- **Tab 1회당 버튼 1개다.** wrapper 는 traversal 정지점을 만들지 않는다 —
  내부 `Focus` 가 `canRequestFocus: false` + `skipTraversal: true` 라 버튼 앞에
  「Enter 가 먹지 않는 죽은 Tab stop」 이 생기지 않는다. `isEnabled: false` 면
  `descendantsAreFocusable` 로 자손 focus 진입 자체를 막는다(disabled button).
- **outline 은 키보드 조작에서만 보인다.** 조건은 자손 focus 보유 **그리고**
  `FocusManager.highlightMode == FocusHighlightMode.traditional` 의 AND 다.
  손가락 터치로 들어온 focus, 다이얼로그 닫힘 후 focus 복원, 코드에서 호출한
  `requestFocus()` 에서는 그리지 않는다. 입력 수단이 실행 중에 바뀌면 구독한
  리스너가 outline 을 다시 계산한다.
- **외관은 hardcode 다** — 2dp solid border, 2dp offset(padding), 라이트 테마는
  검정 `Color(0xFF000000)` / 다크 테마는 흰 `Color(0xFFFFFFFF)`, outline 모서리는
  `borderRadius + 4`(2dp offset + 2dp border 만큼 바깥에 그려진다). M3
  `colorScheme` / `textTheme` 토큰을 읽지 않으므로 `ThemeData` 를 어떻게 바꿔도
  focus indicator 가 달라지지 않는다. `ThemeData.focusColor` 나
  `colorScheme.primary` 로 바꾸지 않는다 — 테마 tint 로 물들면 outline 과 버튼
  배경의 대비가 깨진다.

> ⚠ **wrapper 는 child 제약을 가로 · 세로 각 8dp 잠식한다.** border 2dp +
> padding 2dp 로 사방 4dp 씩 줄어든다. 부모가 크기를 정하면 **300x48 → child
> 292x40** 이 되어 브랜드 규정 높이(48dp)와 최소 터치 타겟이 함께 깨진다.
> **버튼 높이는 wrapper 바깥이 아니라 child 안에서 정한다** — 소셜 로그인 버튼은
> child 안의 `SizedBox(height: kBrandButtonHeight)` 로 높이를 정한다.

**a11y 위임:** 감싸는 버튼이 `Semantics(excludeSemantics: true)` 로 자손의
focus 의미론을 막는 경우가 있다. 그래서 wrapper 는 `includeSemantics: false` 로
자기 의미론을 숨기는 대신 `Semantics(focusable:, onFocus:)` 를 직접 노출하고,
focus 요청을 첫 traversal 자손(실제 버튼의 `InkWell`)에게 넘긴다. 스크린리더의
focus 요청이 실제 버튼에 닿는다.

### 확인 방법

- 앱을 다시 빌드해 실행한다. 설정 「일반」 묶음의 테마 행에서 라이트 · 다크를 바꿔
  가며 바꾼 색 · 글자 · 간격이 두 모드에 모두 맞는지 본다.

  ```bash
  fvm flutter run --flavor dev --dart-define-from-file=config/dev.json
  ```

- 토큰 시험을 돌린다. 기본값을 바꿨다면 그 값을 단언하는 시험도 함께 고친다.

  ```bash
  fvm flutter test test/core/theme
  ```

- 전체 시험을 돌린다(`fvm flutter test`). 화면 golden 시험은 `AppTheme.light()` /
  `AppTheme.dark()` 의 기본 시드로 그리므로, config 의 `brandColor` 만 바꿨으면 golden
  이 바뀌지 않는다. `lib/core/theme/` 의 상수 · 기본 토큰을 바꿨으면 화면 golden 이
  실패한다 — 테스트 파일 옆 `failures/` 의 비교 이미지를 보고, 의도한 변화일 때만 실패한
  golden 시험 파일 하나를 대상으로 `fvm flutter test --update-goldens <파일>` 로 기준
  이미지를 다시 만든다. 다시 만든 기준 이미지는 눈으로 확인한 뒤 커밋한다
  ([테스트 돌리기](#테스트-돌리기)).
- `BrandFocusWrapper` 로 감싼 버튼을 바꿨다면 실제 기기에서 세 가지를 본다 — 위젯
  시험이 외부 키보드 · 스크린리더 동작을 모두 대신하지 못한다.
  1. 외부 키보드 Tab 1회당 버튼 1개씩 이동하고, Tab 직후 Enter 로 바로 동작한다
     (중간에 아무 반응 없는 정지점이 끼지 않는다).
  2. TalkBack / VoiceOver 스와이프로 각 버튼에 닿고 더블탭으로 동작한다.
  3. 손가락으로 터치한 뒤에는 outline 이 보이지 않는다.

### 문제 해결

- **글자가 기본 스타일로 나온다.** `Theme.of(context).extension<AppTypography>()` 를
  직접 읽으면 등록된 `AppTypography.empty` 의 빈 스타일이 돌아온다. 완성된 스타일은
  `context.appTypography` 로만 얻는다.
- **`copyWith` 로 바꾼 색 · 간격이 기본값으로 돌아갔다.** `copyWith(extensions:)` 는
  map 을 통째로 교체하므로 `AppColors` · `AppTypography` · `AppSpacing` ·
  `AppIconSizes` 넷을 항상 함께 나열한다.
- **가로 모드 · 큰 화면에서 레이아웃이 674dp 로 잘린다.** `AppBreakpoint.maxWidth`
  를 가용 폭으로 썼다. 레이아웃 계산에는 `LayoutBuilder` 의 `constraints.maxWidth`
  를 쓴다.
- **`BrandFocusWrapper` 로 감싼 버튼이 8dp 작아졌다.** 부모가 wrapper 의 크기를
  정했다. border 2dp + padding 2dp 가 사방 4dp 를 먹으므로 규격 크기는 child 안에서
  정한다.
- **라이트와 다크의 팔레트가 어긋난다.** `AppTheme.light()` 와 `AppTheme.dark()` 에
  서로 다른 `seedColor` 를 넘겼다. 두 줄에 같은 시드를 넘긴다.
- **`brandColor` 를 바꿨는데 앱 색이 보라색이다.** 값이 `#RRGGBB` 형식이 아니면
  `AppTheme.seedColor` 로 칠한다. 형식을 고친 뒤 앱을 다시 빌드한다.

### 되돌리기

- 커밋하기 전의 코드 변경은 `git checkout -- lib/app.dart lib/core/theme/` 로
  되돌린다. 다시 만든 golden 기준 이미지도 같은 꼴로 그 `goldens/` 디렉터리를 되돌린다.
- `brandColor` 는 example 값 `#673AB7` 로 되돌리고 앱을 다시 빌드한다(`kit` 모드면
  [발송 모드 절](#인증-메일-발송-모드-켜고-끄기) 「켜기」 ④ · ⑥ 도 다시 한다).
- 킷 새 판을 받을 때 `lib/core/theme/` 토큰은 내 값이다 —
  [킷 업데이트 반영](#킷-업데이트-반영) 의 사용자 소유 표면 표 21행대로 처리한다.

## 앱 아이콘 바꾸기

홈 화면 · 앱 목록에 보이는 앱 아이콘을 내 아이콘으로 바꾸는 절차다. 로그인 수단 콘솔(Google 동의 화면 · Facebook 앱 등)에 올리는 아이콘은 위저드의 앱 아이콘 단계가 `.setup/icons/` 에 따로 만든다 — 이 절의 앱 아이콘 파일과 다른 파일이고, 위저드는 이 절의 파일을 건드리지 않는다.

**전제:**

- 정사각 PNG 원본이 있다 — 1024x1024 픽셀 이상.
- iOS 앱 아이콘에는 투명 배경 · 알파 채널을 쓰지 않는다 — App Store 업로드 검사가 투명하거나 알파 채널이 있는 큰 앱 아이콘을 거절한다. 원본은 배경을 채운 PNG 로 만든다.
- 크기별 PNG 를 만드는 도구가 있다 — macOS 의 `sips`(아래 명령) 또는 Android Studio 의 Image Asset 도구 같은 아이콘 도구.

바꿀 파일은 둘이다.

| 플랫폼 | 파일 | 크기 |
|---|---|---|
| iOS | `ios/Runner/Assets.xcassets/AppIcon.appiconset/` 의 `Icon-App-<크기>@<배율>x.png` 15장 · `Contents.json` | `Contents.json` 의 크기 × 배율 픽셀 — 20 · 29 · 40 · 58 · 60 · 76 · 80 · 87 · 120 · 152 · 167 · 180 · 1024 |
| Android | `android/app/src/main/res/mipmap-<밀도>/ic_launcher.png` 5장 | `mdpi` 48 · `hdpi` 72 · `xhdpi` 96 · `xxhdpi` 144 · `xxxhdpi` 192 픽셀 |

### 단계

예시의 `icon-1024.png` 는 내 원본 파일 경로다. 명령은 저장소 루트에서 실행한다.

**① iOS 아이콘을 만든다.** 파일 이름과 `Contents.json` 은 그대로 두고, 같은 이름의 PNG 를 크기에 맞게 덮어쓴다. `sips -z <높이> <너비> <원본> --out <파일>` 꼴이다(`-z` 는 높이가 먼저다).

```bash
SRC=icon-1024.png
DIR=ios/Runner/Assets.xcassets/AppIcon.appiconset
for spec in 20x20@1x:20 20x20@2x:40 20x20@3x:60 29x29@1x:29 29x29@2x:58 29x29@3x:87 40x40@1x:40 40x40@2x:80 40x40@3x:120 60x60@2x:120 60x60@3x:180 76x76@1x:76 76x76@2x:152 83.5x83.5@2x:167 1024x1024@1x:1024; do
  px=${spec##*:}
  sips -z "$px" "$px" "$SRC" --out "$DIR/Icon-App-${spec%%:*}.png"
done
```

**② Android 아이콘을 만든다.** `AndroidManifest.xml` 의 `android:icon="@mipmap/ic_launcher"` 가 이 파일을 쓴다.

```bash
SRC=icon-1024.png
RES=android/app/src/main/res
for spec in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  px=${spec##*:}
  sips -z "$px" "$px" "$SRC" --out "$RES/mipmap-${spec%%:*}/ic_launcher.png"
done
```

**③ (선택) Android adaptive 아이콘을 만든다.** 킷의 Android 아이콘은 위 PNG 5장뿐이고 `mipmap-anydpi-v26` 이 없어 adaptive 아이콘이 아니다. 기기마다 다른 모양(원 · 둥근 사각형 등)으로 잘리는 adaptive 아이콘을 쓰려면 Android Studio 에서 `android/` 를 열고 `res` 폴더의 New → Image Asset 으로 만든다. 결과는 `res/mipmap-anydpi-v26/ic_launcher.xml` 의 `<adaptive-icon>`(`<foreground>` · `<background>` · `<monochrome>`)과 그 레이어 그림이다. 레이어 크기와 안전 영역은 아래와 같다.

- 레이어는 108x108 dp 다.
- 안쪽 66x66 dp 가 안전 영역이다 — 기기의 마스크가 이 안은 자르지 않는다.
- 로고는 48x48 dp 이상 66x66 dp 이하로 안전 영역 안에 둔다.
- 바깥 18 dp 는 마스크 · 움직임 효과에 쓰인다 — 잘려도 되는 배경만 둔다.

**Apple 로그인 화면의 아이콘.** Apple 로 로그인 동의 화면은 Services ID 의 primary App ID 로 정한 앱의 App Icon 을 보인다([Apple 로그인 켜기](setup.md#apple-로그인-켜기)).

### 확인 방법

- 파일 크기 · 알파 채널을 본다. iOS 1024 아이콘은 `hasAlpha: no` 여야 한다.

  ```bash
  sips -g pixelWidth -g pixelHeight -g hasAlpha ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png
  ```

- 앱을 다시 빌드해 기기에 설치하고 홈 화면 · 앱 목록의 아이콘을 본다.

  ```bash
  fvm flutter run --flavor dev --dart-define-from-file=config/dev.json
  ```

### 문제 해결

- **홈 화면에 예전 아이콘이 남아 있다.** 기기가 아이콘을 캐시한다. 앱을 지우고 다시 설치한다.
- **App Store 업로드가 큰 앱 아이콘 오류로 거절된다.** 1024 아이콘에 투명 영역이나 알파 채널이 있다. 배경을 채우고 알파 채널이 없는 원본으로 ① 을 다시 한다.

### 되돌리기

- 커밋하기 전이면 `git checkout -- ios/Runner/Assets.xcassets/AppIcon.appiconset/ android/app/src/main/res/mipmap-*/ic_launcher.png` 로 킷 아이콘으로 되돌린다. ③ 에서 새로 생긴 파일(`mipmap-anydpi-v26/` 과 레이어 그림)은 지운다.
- 킷 새 판을 받을 때 앱 아이콘 파일은 내 파일이다 — [킷 업데이트 반영](#킷-업데이트-반영) 의 사용자 소유 표면 표 16행대로 충돌이 나면 `git checkout --ours -- <파일>` 로 내 파일을 남긴다.

## 스플래시 바꾸기

앱을 켤 때 처음 보이는 네이티브 스플래시(배경색 · 로고)를 내 것으로 바꾸는 절차다. 킷의 스플래시 로고 `assets/images/splash/logo.png` · `logo_dark.png` 는 128x128 투명 PNG 라 화면에 보이지 않는다 — 배경색(라이트 흰색 · 다크 검은색)만 보인다. 내 로고로 바꿔야 스플래시에 로고가 나온다.

**전제:** 스플래시 파일은 dev 의존성 `flutter_native_splash`(`pubspec.yaml`)가 만든다. 설정은 저장소 루트의 `flutter_native_splash.yaml` 이다.

### 단계

**① 로고 그림을 바꾼다.** `assets/images/splash/logo.png`(라이트) · `logo_dark.png`(다크)를 같은 이름의 내 그림으로 덮어쓴다.

- PNG 이고 128x128 이상이다(알파 채널 유지). 권장 크기는 512x512 다.
- 128x128 보다 작게 두지 않는다 — iOS 는 `LaunchImage.imageset` 의 @1x · @2x · @3x 그림을 이 원본에서 만들고, 원본이 1x1 이면 파생 그림이 깨져 Xcode 빌드가 `Distill failed for unknown reasons` 로 실패한다. 로고를 넣기 전 자리 그림도 128x128 이상 투명 PNG 로 둔다.
- Android 12 이상은 로고를 원 안에 잘라 보인다. 원 밖이 잘려도 되게 여백을 둔다 — `flutter_native_splash` README 는 아이콘 배경이 없을 때 1152x1152 픽셀 그림의 지름 768 픽셀 원 안에 로고를 두라고 안내한다.

**② 색 · 그림 경로를 정한다.** `flutter_native_splash.yaml` 에서 고친다.

- `color` · `color_dark` — 라이트 · 다크 배경색(킷 값 `"#FFFFFF"` · `"#000000"`).
- `image` · `image_dark` — 로고 그림 경로(킷 값 `assets/images/splash/logo.png` · `assets/images/splash/logo_dark.png`).
- `android_12:` 블록 — Android 12 이상의 OS SplashScreen 설정이다. 같은 이름의 `image` · `image_dark` · `color` · `color_dark` 를 따로 둔다. 위의 값과 함께 고친다.
- `android: true` · `ios: true` · `web: false` 는 그대로 둔다(웹은 킷 지원 범위 밖이다).
- 그 밖의 옵션(로고 배치 `ios_content_mode` 등)은 `flutter_native_splash` 공식 README 를 본다.

**③ 네이티브 스플래시 파일을 다시 만든다.**

```bash
fvm flutter pub get
fvm dart run flutter_native_splash:create
```

**④ 다시 만든 파일을 모두 커밋한다.** 이 명령이 덮어쓰는 파일이다.

- `android/app/src/main/res/drawable*/` 의 `launch_background.xml` · `background.png` · `splash.png` · `android12splash.png`
- `android/app/src/main/res/values*/styles.xml`(`values` · `values-night` · `values-v31` · `values-night-v31`)
- `ios/Runner/Assets.xcassets/LaunchImage.imageset/` · `ios/Runner/Assets.xcassets/LaunchBackground.imageset/`
- `ios/Runner/Base.lproj/LaunchScreen.storyboard`

**iOS LaunchImage.** `flutter_native_splash:create` 가 `ios/Runner/Assets.xcassets/LaunchImage.imageset/` 의 `LaunchImage.png` · `LaunchImage@2x.png` · `LaunchImage@3x.png`(라이트)와 `LaunchImageDark.png` · `LaunchImageDark@2x.png` · `LaunchImageDark@3x.png`(다크) 6개를 만든다. 이 파일들을 Xcode 에서 직접 덮어쓰지 않는다 — 다음 `flutter_native_splash:create` 가 다시 덮어쓴다. `assets/images/splash/` 원본과 `flutter_native_splash.yaml` 을 고친 뒤 ③ 으로 반영한다. `ios/Runner/Base.lproj/LaunchScreen.storyboard` 도 `flutter_native_splash` 가 관리한다 — 배경색 · 로고 위치는 Storyboard 를 손으로 고치지 말고 `flutter_native_splash.yaml` 의 `color` · `color_dark` · `ios_content_mode` 로 정한다.

### 확인 방법

- `git status` 에 ④ 의 파일이 바뀐 것으로 보인다.
- 앱을 완전히 종료한 뒤 다시 실행해 스플래시를 본다. 기기를 라이트 · 다크 모드로 바꿔 가며 두 그림을 모두 본다. Android 는 12 이상 기기와 그 아래 기기의 모양이 다르다.

  ```bash
  fvm flutter run --flavor dev --dart-define-from-file=config/dev.json
  ```

### 문제 해결

- **iOS 빌드가 `Distill failed for unknown reasons` 로 실패한다.** 로고 원본이 너무 작다. 128x128 이상 PNG 로 바꾸고 ③ 을 다시 한다.
- **스플래시에 로고가 보이지 않는다.** 로고가 킷의 투명 그림 그대로다. ① 대로 내 그림으로 바꾸고 ③ 을 다시 한다.
- **Android 12 이상에서 로고 가장자리가 잘린다.** 로고가 원 밖으로 나간다. ① 의 여백을 두고 ③ 을 다시 한다.

### 되돌리기

- 커밋하기 전이면 `git checkout -- assets/images/splash/ flutter_native_splash.yaml` 로 원본과 설정을 되돌리고 ③ 을 다시 한다.
- 킷 새 판을 받을 때 스플래시 설정 · 로고는 내 값이고 생성물은 다시 만들어 덮어쓴다 — [킷 업데이트 반영](#킷-업데이트-반영) 의 사용자 소유 표면 표 14행 · 15행대로 처리한다.

## 인증 메일 발송 모드 켜고 끄기

이메일 인증 메일과 비밀번호 재설정 메일을 누가 보내는지 고르는 절차다. 기본값 `firebase` 는 Firebase 가 기본 템플릿으로 보낸다 — 설정할 것이 없고, 메일 언어는 앱 언어를 따른다. `kit` 은 앱 이름 · `brandColor` · 로고를 넣은 킷의 메일을 내 발송 서비스로 보낸다. Firebase Console 에서는 인증 메일 본문을 바꿀 수 없으므로, 인증 메일 본문까지 앱 브랜드로 보내려면 `kit` 을 켠다. 기본값 그대로 쓰면 이 절을 건너뛴다. `kit` 메일의 링크는 앱 이름 · 색 · 로고를 넣은 킷의 결과 페이지(인증 · 비밀번호 재설정)로 열리고, `firebase` 메일의 링크는 Firebase 기본 페이지로 열린다.

| 모드 | 보내는 쪽 | 메일 모양 | 링크가 여는 페이지 | 필요한 설정 |
|---|---|---|---|---|
| `firebase` (기본 · 빈 값) | Firebase Authentication | Firebase 기본 템플릿 — Console 에서 발신자 이름 · 제목 · 재설정 메일 본문을 고칠 수 있다 | Firebase 기본 페이지 | 없음 |
| `kit` | 킷의 메일 함수 + Trigger Email 확장 + 내 발송 서비스 | 앱 이름 · 색 · 로고 · 앱 언어 | 킷의 결과 페이지(`https://<your-project-id>.web.app/`) | 아래 「켜기」 |

**전제 (`kit`):**

- Firebase 프로젝트가 Blaze 요금제다. Trigger Email 확장이 Blaze 를 요구한다.
- 메일을 보낼 도메인(또는 하위 도메인)이 있고 그 DNS 레코드를 고칠 수 있다.
- SMTP URI 를 주는 발송 서비스면 무엇이든 쓸 수 있다 — 그 서비스의 계정이 있다. 아래 「켜기」 에는 Resend 예시가 있다.
- 위저드로 처음 설정을 끝내 함수가 한 번 배포돼 있다([위저드 실행](setup.md#위저드-실행)).
- Firebase Hosting 기본 사이트(`<your-project-id>.web.app`)가 있다 — `kit` 메일의 링크가 여는 결과 페이지가 여기에 올라간다. 기본 사이트가 없는 프로젝트는 Firebase Console → Hosting 에서 「시작하기」 로 먼저 만든다 — 공식 안내: <https://firebase.google.com/docs/hosting/default-site>.
- `<your-project-id>.web.app` 은 Firebase Authentication 의 승인된 도메인에 기본으로 들어 있어 따로 더하지 않는다.
- Firebase Console → App Check 에서 Authentication 의 시행(enforcement)을 켜면 결과 페이지의 요청이 거부된다. `kit` 을 쓰는 동안에는 Authentication 시행을 켜지 않는다.
- PATH 에 Firebase CLI(`firebase`) · `node` · `jq` · `gcloud` 가 있고 `firebase login` · `gcloud auth login` 이 되어 있다.
- 메일 · 결과 페이지의 앱 이름 · 색은 config 의 `appName` · `brandColor` 다([위저드가 채우는 설정 키](setup.md#위저드가-채우는-설정-키) 표). 로고를 넣으려면 ④ 전에 [결과 페이지 절](#인증-결과-페이지-바꾸기) ② 대로 `hosting/public/logo.png` 를 둔다.

### 켜기

예시는 dev flavor 기준이고, stg · prod 는 `dev` 자리에 flavor 이름을 넣는다. `<your-project-id>` 는 `config/dev.json` 의 `firebaseProjectId` 값이다.

**① 보내는 도메인을 인증한다.** 발송 서비스는 받는 사람의 메일 서버까지 메일을 실제로 배달하는 SMTP 서버이고, 도메인 인증은 받는 쪽 메일 서버가 보낸 사람을 믿게 하는 단계다. 발송 서비스에 메일을 보낼 도메인을 추가하고, 서비스가 알려 주는 SPF · DKIM 레코드를 그 도메인의 DNS 에 등록한다. DMARC 는 최소 아래 값을 `_dmarc.<내 도메인>` 의 TXT 레코드로 둔다. 하위 도메인으로 보내도 DMARC 레코드는 루트 도메인의 `_dmarc` 하나면 된다 — 하위 도메인은 루트 도메인의 정책을 따른다. `rua` 는 DMARC 보고를 받을 주소이고, 보고를 받을 때만 넣는다.

```
v=DMARC1; p=none; rua=mailto:<보고 받을 주소>
```

받는 쪽의 발신자 요건은 공식 안내에 있다 — Gmail: <https://support.google.com/a/answer/81126> · Yahoo: <https://senders.yahooinc.com/best-practices/>. 두 곳 모두 보낸 사람 주소의 도메인이 SPF 나 DKIM 도메인과 맞기를 요구하므로, ③ 의 `DEFAULT_FROM` 은 인증한 도메인의 주소로 쓴다.

**예시 — Resend.**

1. Resend 대시보드의 Domains 에서 도메인을 추가한다.
2. 화면에 나온 DNS 레코드를 도메인의 DNS 에 등록한다. DNS 화면마다 열 이름이 다르다 — Resend 의 Name 은 DNS 화면의 호스트 칸에, Content 는 값(위치) 칸에 넣는다. 등록한 뒤 Resend 의 그 도메인 화면에서 인증을 시작하는 버튼을 눌러야 확인이 시작된다 — 누르기 전에는 Domains 목록의 Status 가 `Not Started` 에 머문다. Status 가 `Verified` 가 될 때까지 기다린다. 화면은 몇 시간 걸릴 수 있다고 안내하지만, DNS 레코드가 이미 퍼져 있으면 더 빨리 끝난다.
3. API Keys 에서 API key 를 만든다. 이 key 가 SMTP 비밀번호다(④ 에서 넣는다).
4. SMTP URI 는 `smtps://resend@smtp.resend.com:465` 다 — 사용자 이름 `resend` · 포트 465.

Resend 는 도메인을 인증하기 전에는 Resend 계정의 이메일 주소로만 보낸다.

**② config 에서 모드를 켠다.** `config/dev.json` 의 `emailDelivery` 를 `kit` 으로 바꾼다.

```json
"emailDelivery": "kit"
```

같은 파일의 `firebaseWebApiKey` 에 **웹 API 키**(`AIza` 로 시작)를 넣는다. 키는 Google Cloud Console → API 및 서비스(APIs & Services) → 사용자 인증 정보(Credentials) 의 「API 키」 표에 있는 `Browser key (auto created by Firebase)` 다 — Firebase 가 프로젝트를 만들 때 함께 만든다. 「키 표시」 로 연 창에서 값을 복사하고, 키 이름을 눌러 연 화면에서 애플리케이션 제한사항이 「없음」 인지 확인한다. 「없음」 이 아니면 [결과 페이지 절](#인증-결과-페이지-바꾸기) 「문제 해결」 의 「문제가 발생했습니다」 항목대로 고친다. 결과 페이지는 이 키로만 Firebase Authentication 을 부르고, 메일 링크에 실린 키는 쓰지 않는다. 비어 있거나 example 파일의 자리표시 값 그대로면 ④ 의 결과 페이지 빌드가 `FAIL:` 로 멈춘다.

**③ 확장 값 파일을 만든다.** 프로젝트마다 한 번, example 파일을 복사한다. 복사한 파일은 git 이 무시한다.

```bash
cp extensions/firestore-send-email.env.example extensions/firestore-send-email.env.<your-project-id>
```

복사한 파일의 네 줄을 내 값으로 바꾼다. 아래는 example 파일의 값이다.

```
DATABASE_REGION=asia-northeast3
DEFAULT_FROM="StarterKit Dev <no-reply@mail.example.com>"
SMTP_CONNECTION_URI=smtps://resend@smtp.resend.com:465
SMTP_PASSWORD=projects/<your-project-number>/secrets/firestore-send-email-SMTP_PASSWORD/versions/latest
```

- `DATABASE_REGION` — Firestore 데이터베이스 위치. `gcloud firestore databases describe --project <your-project-id>` 출력의 `locationId` 값이다.
- `DEFAULT_FROM` — 보낸 사람. `앱 이름 <no-reply@인증한 도메인>` 꼴로 쓴다.
- `SMTP_CONNECTION_URI` — 발송 서비스가 주는 SMTP URI. 비밀번호는 넣지 않는다.
- `SMTP_PASSWORD` — SMTP 비밀번호 자체가 아니라 그 비밀번호를 담을 Secret Manager secret 의 이름이다. `<your-project-number>` 만 프로젝트 번호(Firebase Console → 프로젝트 설정 → 일반)로 바꾼다.

같은 디렉터리의 `extensions/firestore-send-email.env` 는 킷이 관리하는 공통 값이라 고치지 않는다.

**④ 메일 브랜드 값 · 결과 페이지 · 확장을 배포한다.** 먼저 옵션 없이 실행한다. 이 명령은 `config/dev.json` 으로 결과 페이지를 빌드하고 계획을 출력할 뿐 Firebase 와 함수 env 파일에는 아무것도 바꾸지 않는다.

```bash
bash scripts/deploy_email.sh dev kit
```

`BUILD OK` 줄의 `logo=` 가 로고 파일 유무(`1` = 있음 · `0` = 없음)와 맞는지, `env:` 네 줄이 메일에 들어갈 앱 이름 · 색 · 로고 주소(로고 파일이 없으면 빈 값) · 결과 페이지 주소 `https://<your-project-id>.web.app/` 인지, `command:` 두 줄이 결과 페이지(`--only hosting`) → 확장(`--only extensions`) 순인지, 마지막 줄이 `DRY-RUN OK dev target=kit mode=kit` 인지 본다. 맞으면 `--apply` 를 붙여 실행한다. 이 명령은 결과 페이지를 Firebase Hosting 에 먼저 배포하고, 성공하면 `functions/.env.<your-project-id>` 의 `EMAIL_APP_NAME` · `EMAIL_BRAND_COLOR` · `EMAIL_LOGO_URL` · `EMAIL_RESULT_PAGE_URL` 네 줄을 쓰고(다른 줄은 그대로 둔다) Trigger Email 확장을 설치한다. 결과 페이지 배포가 실패하면 네 줄과 확장은 바꾸지 않고 `FAIL:` 로 멈춘다. SMTP 비밀번호 secret 이 아직 없으면 Firebase CLI 가 값을 묻는다 — 발송 서비스의 SMTP 비밀번호(Resend 는 API key)를 넣는다. 터미널 입력을 받을 수 있는 터미널에서 실행한다.

```bash
bash scripts/deploy_email.sh dev kit --apply
```

마지막 줄이 `DEPLOY OK dev target=kit mode=kit` 이면 끝난 것이다 — `https://<your-project-id>.web.app/` 에 결과 페이지가 올라가 있고, `kit` 메일의 링크가 이 페이지를 연다. `functions/.env.<your-project-id>` 의 네 줄은 이 명령이 config 로 다시 쓰므로 직접 고치지 않는다. `appName` 은 비어 있으면 안 되고 `"` · `\` · `$` · 백틱 · 줄바꿈을 쓸 수 없다. `appName` · `brandColor` · 로고를 바꾸면 ④ 와 ⑥ 을 다시 한다. 출력의 `next:` 세 줄은 ⑤ · ⑥ · ⑦ 에서 그 순서로 실행할 명령이다.

**⑤ 메일 문서를 지우는 TTL 정책을 켠다.** 프로젝트마다 한 번 실행한다. 확장은 보낸 메일마다 `mail` 컬렉션에 문서(받는 주소 · 링크가 들어 있다)를 남기는데, 이 정책을 켜면 하루 뒤 지워진다. 실제 삭제는 만료 뒤 보통 24시간 안에 일어난다. 이 명령은 끝날 때까지 몇 분 걸릴 수 있다.

```bash
gcloud firestore fields ttls update delivery.expireAt --collection-group=mail --enable-ttl --project <your-project-id>
```

**⑥ 메일 함수를 배포한다.** 아래 배포 스크립트로 배포한다. 옵션 없이 실행한 출력에 `mode: kit` 이 있고 `functions` 목록에 `sendVerificationMail` · `sendPasswordResetMail` 이 있는지 본 뒤 `--apply` 를 붙인다. ④ 의 `--apply` 를 하지 않았으면 `--apply` 가 `FAIL:` 로 멈춘다. 위저드 함수 단계는 이 두 함수의 공개 호출을 확인하지 않는다 — 인증 없이 보낸 POST(`curl -X POST <함수 URL> -H 'Content-Type: application/json' -d '{"data":{}}'`)가 `401` 이면 정상이고, `403` 이면 첫 배포가 도중에 끊겨 공개 호출이 빠진 것이다 — Google Cloud 콘솔 → Cloud Run 의 그 서비스(`sendverificationmail` · `sendpasswordresetmail`)에서 [[LABEL: Google Cloud 콘솔 — Cloud Run 서비스의 공개 호출 허용 칸]] 을 켠다.

```bash
bash scripts/deploy_functions.sh dev
bash scripts/deploy_functions.sh dev --apply
```

배포는 배포 스크립트로만 한다 — 인자 없는 `firebase deploy` 는 `firebase.json` 의 모든 대상(확장 포함)을 배포하므로 쓰지 않는다.

**⑦ 확장 함수에 호출 권한을 준다.** 프로젝트마다 한 번 실행한다. Trigger Email 확장이 메일 문서를 받아 처리하는 함수(`ext-firestore-send-email-processqueue`)는 기본 Compute 서비스 계정으로 호출된다. 조직 정책 등으로 이 계정에 권한이 자동으로 붙지 않은 프로젝트에서는 호출이 거부돼 메일이 나가지 않으므로, 이 단계는 모든 프로젝트에서 실행한다 — 이미 권한이 있어도 다시 실행한 결과는 같다. 아래 명령은 ④ 출력의 `next:` 셋째 줄과 같고, 프로젝트 번호는 명령 안의 `gcloud projects describe` 가 채운다.

```bash
gcloud run services add-iam-policy-binding ext-firestore-send-email-processqueue --region=us-central1 --member=serviceAccount:$(gcloud projects describe <your-project-id> --format='value(projectNumber)')-compute@developer.gserviceaccount.com --role=roles/run.invoker --project <your-project-id>
```

성공하면 `Updated IAM policy for service [ext-firestore-send-email-processqueue].` 가 나온다.

**⑧ 앱을 다시 빌드해 실행한다.** `emailDelivery` 는 빌드 때 들어간다.

```bash
fvm flutter run --flavor dev --dart-define-from-file=config/dev.json
```

**메일 문구 · 모양 바꾸기.** 문구는 `functions/src/email/copy.json` 의 `mail.` 로 시작하는 키(ko · en · ja), 모양은 `functions/src/email/templates/` 의 `verify_email.hbs` · `reset_password.hbs` 다. 바꾼 뒤 ⑥ 으로 함수를 다시 배포한다.

### 확인 방법

- Resend 를 쓰면 Resend 대시보드의 Domains 목록에서 그 도메인의 Status 가 `Verified` 다.
- 앱에서 이메일로 가입하거나 인증 대기 화면에서 「인증 메일 재전송」 을 누른다. 받은 메일의 보낸 사람이 `DEFAULT_FROM` 이고, 머리에 앱 이름(로고를 올렸으면 로고) · 버튼 색이 `brandColor` · 문구가 앱 언어다. 메일의 링크를 열면 결과 페이지(`https://<your-project-id>.web.app/`)에 앱 언어로 「이메일 인증 완료」 가 보이고, 앱으로 돌아가면 인증이 반영된다(바로 반영되지 않으면 「인증 확인」 을 누른다).
- 이메일 로그인 화면의 「비밀번호를 잊으셨나요?」 로 받은 재설정 메일도 같은 모양이고, 링크를 열면 「새 비밀번호 설정」 폼이 보인다. 8자 이상으로 바꾸면 「비밀번호 변경 완료」 가 보이고, 앱에서 새 비밀번호로 로그인된다.
- Firebase Console → Firestore Database 의 `mail` 컬렉션에 보낸 메일마다 문서가 생기고, 문서의 `delivery.state` 가 `SUCCESS` 가 된다.

### 문제 해결

- **메일이 오지 않는다.** Firebase Console → Firestore Database 의 `mail` 컬렉션에서 최근 문서를 연다.
  - 문서가 없으면 메일 함수가 메일을 만들지 못한 것이다. Firebase Console → Functions 의 로그에서 `sendVerificationMail` · `sendPasswordResetMail` 의 오류를 본다. `email_brand_unset` 이나 `email_result_page_unset` 이 있으면 ④ 의 `--apply` 뒤 ⑥ 으로 함수를 다시 배포한다.
  - 문서는 있는데 `delivery` 필드가 없으면 아래 「메일 문서에 `delivery` 가 생기지 않는다」 를 본다.
  - `delivery.state` 가 `ERROR` 면 `delivery.error` 에 발송 서비스가 거부한 사유가 있다. Resend 는 도메인을 인증하기 전 Resend 계정 주소가 아닌 받는 사람을 `You can only send testing emails to your own email address` 로 거부한다 — ① 의 도메인 인증을 끝내고 `DEFAULT_FROM` 을 그 도메인 주소로 바꾼 뒤 ④ 를 다시 한다. `DEFAULT_FROM` 의 도메인 인증이 끝나지 않았으면 Resend 는 `550 The <내 도메인> domain is not verified` 로 거부한다 — Domains 목록의 Status 가 `Verified` 가 된 뒤 앱에서 다시 보낸다.
  - `delivery.state` 가 `SUCCESS` 인데 받은 편지함에 없으면 스팸함을 보고 ① 의 SPF · DKIM · DMARC 레코드를 확인한다.
- **메일 문서에 `delivery` 가 생기지 않는다.** 확장 함수가 문서를 처리하지 못한 것이다. Google Cloud Console → Cloud Run 에서 `ext-firestore-send-email-processqueue` 서비스의 로그에 HTTP 403 이 있으면 확장 함수를 부르는 서비스 계정에 호출 권한이 없다. 아래 명령(「켜기」 ⑦ 과 같다)을 실행한다. 권한이 생기면 기다리던 메일은 하루 안에 다시 전달된다.

```bash
gcloud run services add-iam-policy-binding ext-firestore-send-email-processqueue --region=us-central1 --member=serviceAccount:$(gcloud projects describe <your-project-id> --format='value(projectNumber)')-compute@developer.gserviceaccount.com --role=roles/run.invoker --project <your-project-id>
```

- **메일 링크를 열면 「문제가 발생했습니다」 가 뜬다.** [결과 페이지 절](#인증-결과-페이지-바꾸기) 「문제 해결」 을 본다.
- **앱에 「요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.」 가 뜬다.** 같은 계정이나 같은 주소로 짧은 시간에 여러 번 보냈다. 잠시 뒤 다시 보낸다. 한도는 `functions/src/email/send_verification_mail.ts` · `functions/src/email/send_password_reset_mail.ts` 위쪽 상수다.
- **`deploy_email.sh` 가 `FAIL:` 줄을 출력하고 멈춘다.** 그 줄이 고칠 것을 알려 준다 — `emailDelivery` 가 `kit` 이 아니다(②) · `firebaseWebApiKey` 가 비었거나 자리표시 값이다(②) · 확장 값 파일이 없거나 값이 빈 키 · 예시 자리표시(`<your-…>`)가 남은 키(③) · `appName` 이 비었거나 쓸 수 없는 문자 · 결과 페이지 빌드 · 배포 실패(④). 고친 뒤 다시 실행한다.
- **④ 의 `--apply` 가 `Could not determine the default site for the project.` 를 출력하고 `FAIL:` 로 멈춘다.** Hosting 기본 사이트가 없다. 「전제」 의 안내대로 만든 뒤 ④ 를 다시 한다.
- **④ 의 `--apply` 가 secret 값을 묻지 못하고 끝난다.** 터미널 입력을 받을 수 없는 환경에서 실행했다. 일반 터미널에서 다시 실행한다.
- **④ 의 `--apply` 가 확장 단계에서 `Permission denied while using the Eventarc Service Agent` 를 출력하고 `FAIL:` 로 멈춘다.** 프로젝트에서 Eventarc 를 처음 쓰면 권한이 퍼질 때까지 몇 분 걸린다. 몇 분 뒤 ④ 의 `--apply` 를 다시 실행한다. SMTP 비밀번호 secret 이 이미 만들어졌으면 값을 다시 묻지 않는다.
- **`firebase` 모드에서 재설정 메일이 앱 언어와 다른 언어로 온다.** Console 에서 재설정 메일 본문을 직접 고치면 그 본문 하나가 쓰인다. 앱 언어마다 다른 본문이 필요하면 `kit` 을 쓴다.

### 끄기

`config/dev.json` 의 `emailDelivery` 를 빈 값(`""`) 또는 `firebase` 로 바꾸고 앱을 다시 빌드한다. 그 뒤 메일은 Firebase 가 보내고, 메일 링크는 Firebase 기본 페이지로 열린다. `kit` 으로 이미 보낸 메일의 링크는 결과 페이지로 계속 열린다 — 결과 페이지는 지우지 않고 둔다. `firebase` 모드에서는 `bash scripts/deploy_functions.sh dev` 가 메일 함수를 배포하지 않고 `deploy_email.sh` 의 `kit` · `hosting` 대상은 `FAIL:` 로 멈춘다.

이미 설치한 확장과 메일 함수는 남겨 둬도 된다 — 앱이 부르지 않는다. 지우려면 아래 명령을 쓴다. 함수는 이름으로 지운다.

```bash
firebase functions:delete sendVerificationMail sendPasswordResetMail --region asia-northeast3 --project <your-project-id>
```

확장은 저장소 밖의 빈 디렉터리에서 지운다. 저장소 안에서 실행하면 Firebase CLI 가 `firebase.json` 의 확장 항목과 `extensions/firestore-send-email.env` 까지 지운다. 아래 명령은 임시 디렉터리에서 실행하고 삭제 여부를 한 번 묻는다.

```bash
( cd "$(mktemp -d)" && firebase ext:uninstall firestore-send-email --immediate --project <your-project-id> )
```

`mail` 컬렉션의 TTL 정책은 남겨 둬도 된다.

## 인증 결과 페이지 바꾸기

`kit` 발송 모드 메일의 링크를 눌렀을 때 열리는 웹 페이지(결과 페이지)의 앱 이름 · 색 · 로고 · 문구 · 모양을 바꾸는 절차다. 결과 페이지는 [발송 모드 절](#인증-메일-발송-모드-켜고-끄기) 「켜기」 ④ 가 함께 배포하고, 인증 · 비밀번호 재설정 링크를 메일 링크의 언어(한국어 · 영어 · 일본어)로 표시한다 — 앱이 보내는 메일의 언어는 앱 언어다. `firebase` 모드에서는 메일 링크가 Firebase 기본 페이지로 열리고 이 페이지를 쓰지 않으므로 이 절을 건너뛴다. `kit` 모드에서 이 절을 하지 않아도 페이지는 config 의 `appName` · `brandColor` 와 로고 파일대로 나온다.

**전제:**

- [발송 모드 절](#인증-메일-발송-모드-켜고-끄기) 「켜기」 를 끝내 `config/dev.json` 의 `emailDelivery` 가 `kit` 이다.
- PATH 에 Firebase CLI(`firebase`) · `node` · `jq` 가 있고 `firebase login` 이 되어 있다.

### 바꾸고 배포하기

예시는 dev flavor 기준이고, stg · prod 는 `dev` 자리에 flavor 이름을 넣는다. `<your-project-id>` 는 `config/dev.json` 의 `firebaseProjectId` 값이다.

**① 앱 이름 · 색을 정한다.** `config/dev.json` 의 `appName` 이 페이지 머리에 나오는 이름이고, `brandColor` 가 버튼 · 강조 색이다. `brandColor` 는 `#RRGGBB` 형식이고, 비우거나 형식이 틀리면 `#673AB7` 로 칠한다. 같은 `brandColor` 가 앱 테마 색에도 쓰인다([위저드가 채우는 설정 키](setup.md#위저드가-채우는-설정-키) 표). 아래는 example 파일의 값이다.

```json
"appName": "StarterKit Dev",
"brandColor": "#673AB7"
```

**② (선택) 로고 파일을 넣는다.** 로고를 PNG 로 `hosting/public/logo.png` 에 둔다. 높이 120px(화면에는 높이 40px 로 줄여 보인다) · 폭 480px 이하를 권장한다. 결과 페이지에서 로고는 흰 바탕 위에 놓이므로(다크 모드에서도 같다) 흰 바탕에서 잘 보이는 그림을 쓴다. SVG 는 쓸 수 없다 — 메일 앱이 SVG 를 표시하지 않는다. 파일이 없으면 페이지 머리에 `appName` 이 글자로 나온다. 같은 로고 파일이 `kit` 발송 모드 메일의 머리에도 쓰인다. 메일 앱은 다크 모드에서 메일 바탕을 어둡게 바꿀 수 있으므로 투명 바탕 대신 바탕을 채운 PNG 를 쓴다.

**③ 페이지를 다시 배포한다.** 문구 · 모양만 바꿨을 때 쓴다. 먼저 옵션 없이 실행한다. 이 명령은 `config/dev.json` 으로 페이지를 빌드하고 프로젝트 ID 와 배포 명령을 출력할 뿐 Firebase 에는 아무것도 바꾸지 않는다.

```bash
bash scripts/deploy_email.sh dev hosting
```

출력의 `project:` 가 내 프로젝트 ID 인지, `BUILD OK` 줄의 `logo=` 가 로고 파일 유무(`1` = 있음 · `0` = 없음)와 맞는지, 마지막 줄이 `DRY-RUN OK dev target=hosting` 으로 시작하는지 본다. 맞으면 `--apply` 를 붙여 배포한다. 마지막 줄이 `DEPLOY OK dev target=hosting` 으로 시작하면 `https://<your-project-id>.web.app/` 에 페이지가 올라간 것이다.

```bash
bash scripts/deploy_email.sh dev hosting --apply
```

`config/dev.json` 의 `emailDelivery` 가 `kit` 이 아니면 이 명령은 `FAIL:` 로 멈춘다. 앱 이름 · 색 · 로고는 `kit` 메일에도 들어가므로, 바꿨다면 ③ 대신 [발송 모드 절](#인증-메일-발송-모드-켜고-끄기) 「켜기」 ④ · ⑥ 을 다시 한다 — ④ 가 결과 페이지도 다시 배포한다.

배포는 배포 스크립트로만 한다 — 인자 없는 `firebase deploy` 는 `firebase.json` 의 모든 대상(확장 포함)을 배포하므로 쓰지 않는다.

페이지만 바꿀 때는 앱을 다시 빌드하지 않아도 된다. `brandColor` 를 바꿨다면 앱 테마 색도 바뀌므로 앱을 다시 빌드한다.

### 문구 · 모양 바꾸기

- **문구.** `functions/src/email/copy.json` 의 `page.` 로 시작하는 키다(ko · en · ja). 세 언어의 키는 같아야 한다 — `functions/` 에서 `pnpm test` 가 확인한다. 같은 파일의 `mail.` 로 시작하는 키는 `kit` 발송 모드 메일 문구다.
- **앱 버튼 이름과 함께 바꾼다.** 페이지 문구는 앱 버튼 이름 「인증 확인」 · 「인증 메일 재전송」 · 「비밀번호를 잊으셨나요?」 를 그대로 인용한다. `lib/l10n/app_*.arb` 에서 그 버튼 이름을 바꾸면 `copy.json` 의 같은 문구도 고친다.
- **모양.** `hosting/public/` 의 `index.html` · `page.css` · `page.js` 다.
- 바꾼 뒤에는 「바꾸고 배포하기」 ③ 으로 다시 배포한다. `mail.` 키를 바꿨다면 [발송 모드 절](#인증-메일-발송-모드-켜고-끄기) 「켜기」 ⑥ 으로 함수도 다시 배포한다.

### 커스텀 도메인

메일 링크가 여는 결과 페이지 주소는 `https://<your-project-id>.web.app/` 다 — 배포 스크립트가 이 주소를 메일 함수 값으로 쓴다. Hosting 에 내 도메인을 연결해도(공식 안내: <https://firebase.google.com/docs/hosting/custom-domain>) 메일 링크 주소는 바뀌지 않는다. 내 도메인에서 페이지를 열려면 같은 도메인을 Firebase Console → Authentication → 설정 → 승인된 도메인에도 추가한다 — 페이지의 Authentication 요청이 그 도메인에서 나간다.

### 확인 방법

- 브라우저로 `https://<your-project-id>.web.app/?lang=ko` 를 열면 앱 이름(로고를 넣었으면 로고) 머리 아래 「이 링크는 사용할 수 없습니다」 화면이 보인다 — 메일 링크 없이 열었기 때문이다.
- 메일 링크로 여는 확인은 [발송 모드 절](#인증-메일-발송-모드-켜고-끄기) 「확인 방법」 이다.

### 문제 해결

- **링크를 열면 「문제가 발생했습니다」 가 뜬다.** 페이지의 Firebase Authentication 요청이 거부된 것이다. `config/dev.json` 의 `firebaseWebApiKey` 가 Google Cloud Console → API 및 서비스(APIs & Services) → 사용자 인증 정보(Credentials) 에서 `Browser key (auto created by Firebase)` 의 「키 표시」 로 본 값과 같은지 확인하고, 고쳤으면 「바꾸고 배포하기」 ③ 으로 다시 배포한다. Firebase Console → App Check 에서 Authentication 시행이 켜져 있으면 끈다. 결과 페이지는 요청에 Referer 를 싣지 않으므로, 웹사이트(HTTP 리퍼러) 제한이 걸린 키는 허용 목록에 무엇을 적어도 이 페이지에서 거부된다. Google Cloud Console → API 및 서비스(APIs & Services) → 사용자 인증 정보(Credentials) 에서 그 키의 애플리케이션 제한사항이 「없음」 이 아니면, 그 제한을 「없음」 으로 되돌리거나 애플리케이션 제한사항이 「없음」 인 키(Firebase 가 만든 Browser key 기본값)를 따로 골라 `firebaseWebApiKey` 에 넣고 「바꾸고 배포하기」 ③ 으로 다시 배포한다. 그래도 같으면 브라우저 개발자 도구의 네트워크 탭에서 `identitytoolkit.googleapis.com` 요청의 응답 코드와 메시지를 본다.
- **배포 스크립트가 `FAIL:` 줄을 출력하고 멈춘다.** 그 줄이 고칠 것을 알려 준다(예: `config/dev.json` 이 없다 · `emailDelivery` 가 `kit` 이 아니다 · `appName` 이 비어 있다 · `firebaseWebApiKey` 가 비었거나 자리표시 값이다). 고친 뒤 다시 실행한다.
- **`warn:` 줄이 `brandColor` 형식을 알린다.** 값을 `#RRGGBB` 로 고친다. 고치기 전에는 `#673AB7` 로 칠한다.
- **로고가 보이지 않는다.** `BUILD OK` 줄이 `logo=0` 이면 파일 위치 · 이름(`hosting/public/logo.png`)을 확인한다. 로고를 바꾼 뒤에는 [발송 모드 절](#인증-메일-발송-모드-켜고-끄기) 「켜기」 ④ · ⑥ 을 다시 한다.

### 되돌리기

로고를 빼려면 `hosting/public/logo.png` 를 지우고 [발송 모드 절](#인증-메일-발송-모드-켜고-끄기) 「켜기」 ④ · ⑥ 을 다시 한다 — 페이지와 메일 머리가 `appName` 글자로 돌아간다. 문구 · 모양은 바꾼 파일을 킷 판으로 되돌린 뒤 「바꾸고 배포하기」 ③ 으로 다시 배포한다. 결과 페이지를 쓰지 않으려면 발송 모드를 `firebase` 로 끈다([발송 모드 절](#인증-메일-발송-모드-켜고-끄기) 「끄기」) — 그 뒤 메일 링크는 Firebase 기본 페이지로 열린다.

## Firebase 서비스 쓰기

킷에 들어 있는 Firebase 서비스 — 알림(FCM) · Remote Config · Cloud Storage · Firestore · Cloud Functions — 를 내 앱에 맞게 쓰는 법이다. Firestore · Storage rules 배포 · 기본 버킷 · 함수 배포는 위저드가 이미 했다. 이 절은 그 뒤 내가 고치는 파일과 직접 하는 일만 다룬다. 예시는 dev flavor 기준이고, `<your-project-id>` 는 `config/dev.json` 의 `firebaseProjectId` 값이다.

### FCM 알림

앱이 포그라운드 · 백그라운드 · 종료 상태 어디에 있든 같은 모양의 시스템 알림이 뜨고, 알림을 탭하면 payload `data.route` 의 화면이 열린다. 알림은 내 서버나 함수가 `users/{uid}/fcmTokens` 의 기기 토큰으로 보낸다. 킷이 직접 보내는 알림은 [알림 시험 발송](#알림-시험-발송) 하나다. 받은 알림을 모아 보여 주는 앱 안 알림함은 없다 — 필요하면 보낼 때 사용자 문서 아래에 알림 문서를 함께 쓰고 목록 화면을 더한다.

**알림 받기 켜기:** 앱의 설정 → 「알림」 → 「알림 받기」 다. 게스트가 아닌 사용자에게만 이 섹션이 있다. 켤 때만 OS 알림 권한을 묻는다 — 앱 시작 · 홈 · 온보딩에서는 묻지 않는다. 허용하면 이 기기의 토큰이 `users/{uid}/fcmTokens/{token}` 에 저장되고, 거부하면 꺼짐 그대로 휴대폰 설정에서 허용하라는 안내가 뜬다. 끄면 이 기기의 문서만 지운다. 한 계정이 여러 기기를 쓰면 기기마다 문서가 하나다.

**앱이 하는 일:**

- **포그라운드 표시:** Android 는 앱이 떠 있을 때 받은 알림을 로컬 알림(`flutter_local_notifications`)으로 띄우고, iOS 는 OS 기본 모양으로 띄운다. Android 알림 채널은 `general` 하나다.
- **탭 이동:** `data.route` 문자열이 허용 목록 `kNotificationRoutableRoutes`(`lib/features/notifications/application/notification_route.dart`)의 경로와 정확히 같을 때만 그 화면으로 가고, 목록 밖 · 없음 · 외부 URL 은 홈이다. 이동은 홈 화면이 그려진 뒤에 일어난다 — 앱이 종료된 상태에서 탭해도 스플래시 → 홈 → 대상 순서다. 목록과 새 화면을 더하는 법은 [④ 알림 탭으로 열 화면](#-알림-탭으로-열-화면--허용-목록) 에 있다.
- **결과 스택:** 허용 목록 가운데 홈이 아닌 경로(설정 · 계정 정보 · 약관 둘)는 홈 하위 route 라, 알림으로 열면 홈 → (설정) → 대상 스택이 만들어진다 — 계정 정보 화면은 홈 · 설정 · 계정 정보 3장, 설정 · 약관은 2장이고, 앱바 ← · Android 뒤로 · iOS 스와이프 뒤로로 홈까지 돌아온다. 홈이 맨 아래에 남으므로 계정 정보 화면 위에서도 다음 알림을 받아 이동한다. 중간 화면(설정)도 보이지 않는 아래 장으로 그려지므로, 부모 화면에 처음 그려질 때 도는 작업을 넣으면 이 알림 경로에서도 돈다.
- **로그아웃 · 탈퇴:** 로그아웃 직전에 이 기기의 토큰 문서를 지우고 알림 받기를 꺼짐으로 돌린다 — 같은 기기에 다른 계정으로 로그인하면 알림은 꺼짐으로 시작한다. OS 알림 권한은 건드리지 않는다. 오프라인 등으로 정리가 끝나지 못하면 앱이 기기에 표식을 남겨 다음 기회(같은 계정으로 다시 로그인 · 다른 계정이 알림을 켤 때 · 로그아웃 상태로 앱 시작)에 문서를 지우거나 이전 토큰을 폐기한다. 그 전까지는 이전 계정 앞으로 보낸 알림이 이 기기에 뜰 수 있다.
- **앱 언어 변경:** 켜진 기기 문서의 `locale` 을 바로 바꾼다(`ko` · `en` · `ja`, 그 밖은 `en`). 서버는 이 값으로 알림 문구 언어를 고른다.
- **앱 밖에서 OS 알림 권한을 끔:** 앱으로 돌아오면 스위치가 꺼지고 문서가 지워진다. 다시 허용하고 돌아오면 켜진다.
- **오래 열지 않은 기기:** 켜진 기기는 앱 시작 · 복귀 · 언어 변경 때마다 문서의 `expireAt` 을 지금 + 30일로 다시 쓴다. 지난 문서는 Firestore TTL 정책이 지운다 — 위저드는 이 정책을 켜지 않으므로 아래 명령을 프로젝트마다 한 번 실행한다. 둘째 명령의 상태가 `ACTIVE` 가 되면 켜진 것이다. 실제 삭제는 만료 뒤 보통 24시간 안에 일어나고, 그 사이 남은 문서는 시험 발송 함수가 건너뛰고 지운다.

```bash
gcloud firestore fields ttls update expireAt --collection-group=fcmTokens --enable-ttl --project <your-project-id>
gcloud firestore fields ttls list --collection-group=fcmTokens --project <your-project-id>
```

**iOS 앱 쪽 설정:** APNs 인증 키는 [APNs 인증 키 올리기](setup.md#apns-인증-키-올리기) 대로 올린다. 앱에는 Xcode Runner 타깃 → Signing & Capabilities 의 Push Notifications capability 가 있고, `ios/Runner/Runner.entitlements` 의 `aps-environment` 는 `development` 다 — App Store · TestFlight 로 내보내는 빌드는 `production` 이어야 하고 프로비저닝 프로파일과 맞아야 한다. `ios/Runner/Info.plist` 의 `UIBackgroundModes` 에 `remote-notification` 이 있다. 번들 ID 를 바꿨으면 같은 번들 ID 의 프로비저닝 프로파일에 Push Notifications 가 켜져 있는지 본다.

**Android 빌드 요건:** `flutter_local_notifications` 는 core library desugaring 이 필요하다 — `android/app/build.gradle.kts` 의 `isCoreLibraryDesugaringEnabled = true` 와 `coreLibraryDesugaring(...)` 두 줄을 지우면 Android 빌드가 실패한다.

**백그라운드에서 할 일:** `lib/features/notifications/data/firebase_messaging_background_handler.dart` 의 함수는 지금 아무 일도 하지 않는다. data 전용 메시지로 백그라운드 작업을 하려면 여기에 넣는다. 별도 isolate 에서 돌므로 다른 Firebase 서비스를 쓰려면 `Firebase.initializeApp()` 을 먼저 부른다.

### Remote Config

앱을 다시 배포하지 않고 값을 바꾸는 스위치 · 문구는 `FeatureFlag` enum(`lib/core/remote_config/feature_flag.dart`)에 둔다. enum 이 Remote Config 키 이름과 기본값을 함께 갖고, 앱이 시작할 때 그 기본값을 넣으므로 콘솔에 키가 없어도 기본값으로 동작한다. 값은 `featureFlagsProvider` 로 읽는다. 앱이 떠 있으면 콘솔에서 게시한 값이 곧 반영된다. 로그인 수단 버튼을 숨기는 키는 이 enum 밖에 있다 — [Kill Switch 로 로그인 수단 막기](#kill-switch-로-로그인-수단-막기).

**본보기 = 홈 공지 배너:**

| 키 | 데이터 유형 | 기본값 | 뜻 |
|---|---|---|---|
| `announcement_banner_enabled` | Boolean | `false` | 배너 스위치 |
| `announcement_message_ko` | String | `''` | 한국어 앱 문구 |
| `announcement_message_en` | String | `''` | 영어 앱 문구 · 다른 언어 칸이 비었을 때의 대체 문구 |
| `announcement_message_ja` | String | `''` | 일본어 앱 문구 |

- **보이는 조건:** 스위치가 `true` 이고, 앱 언어 칸 → 비었으면 en 칸 순서로 고른 문구가 비어 있지 않고(공백만 있는 칸도 빈 칸으로 본다), 그 문구가 사용자가 닫은 문구와 다를 때다. 게스트 · 가입자 모두에게 홈 AppBar 바로 아래에 보인다.
- **닫기:** 사용자가 닫은 문구를 기기에 기억한다. 같은 공지를 다시 보이려면 문구를 바꾼다 — 공백 하나만 달라도 다른 문구다. 앱은 문구를 자르거나 다듬지 않고 링크 · 마크업도 해석하지 않는다.
- **문구 길이:** 360 dp 폭에서 3줄 이내(한국어 약 60자)를 권장한다. 배너가 고정이라 길수록 본문을 가린다.

**콘솔에 키 만들기:** 위저드는 Remote Config 를 바꾸지 않는다. [Kill Switch](#kill-switch-로-로그인-수단-막기) 단계 ① ~ ③ 과 같은 화면에서 위 표의 네 키를 이름 · 데이터 유형 그대로 만들고 게시한다. 스위치를 `true` 로, `announcement_message_ko` 에 문구를 넣고 게시하면 실행 중인 앱에 배너가 나타난다.

**스위치 더하기:** `FeatureFlag` enum 에 `myFeatureEnabled('my_feature_enabled', false),` 꼴로 한 줄을 더하고, 쓰는 곳에서 `ref.watch(featureFlagsProvider).boolValue(FeatureFlag.myFeatureEnabled)` 로 읽는다. 기본값은 앱 시작 때 함께 들어간다. 콘솔에 같은 이름의 키를 만들어 값을 바꾼다.

### Cloud Storage · 프로필 사진

킷의 Storage 본보기는 프로필 사진이다. 사진은 `users/{uid}/profile/avatar.jpg` 하나를 덮어쓴다(`profilePhotoPath` · `lib/features/settings/data/profile_photo_repository.dart`).

- **쓰는 법(앱 사용자):** 설정 → 계정 정보 화면 「프로필」 의 첫 행(프로필 사진)을 누르면 시트가 뜬다. 「갤러리에서 사진 선택」 으로 고른 사진은 올리기 전에 줄여(`maxWidth: 1024` · `imageQuality: 85`) 올리고, 설정 계정 행 · 계정 정보 화면이 다시 시작하지 않아도 새 사진을 보인다. 「올린 사진 삭제」 는 확인 창 없이 지우고 소셜 계정 사진(없으면 기본 아바타)으로 돌아간다. 게스트에게는 사진 행이 없다.
- **권한 창이 없다:** Android 는 Photo Picker, iOS 는 PHPicker 를 쓴다 — 저장소 · 사진 권한 창이 뜨지 않는다. 카메라 촬영은 없다. iOS 의 `ios/Runner/Info.plist` `NSPhotoLibraryUsageDescription` 은 영어 한 문장이다.
- **rules:** `storage.rules` 는 본인 `users/{uid}/` 아래만 읽고 쓰게 하고, 쓰기는 게스트가 아닌 사용자 · 5MB 이하 · `image/` 형식만 허용한다. 본인 경로 아래는 어떤 경로 · 몇 개든 쓸 수 있다 — 사진 한 장만 쓸 거면 match 를 `match /users/{userId}/profile/avatar.jpg` 로 좁히고 rules 시험의 경계 경우를 함께 고친다. 앱도 올리기 전에 같은 상한(`kProfilePhotoMaxBytes`)으로 크기를 본다 — 상한을 바꾸면 두 곳을 함께 고친다.
- **보이는 사진 · 이름의 순서:** 설정 계정 행 · 계정 정보 화면이 같은 규칙을 쓴다(`lib/features/auth/domain/profile_display.dart`).

| 순서 | 사진 | 이름 |
|---|---|---|
| 1 | 앱에 올린 사진(`users/{uid}.customPhotoUrl`) | 계정 이름(Auth `displayName`) |
| 2 | 계정 사진(Auth `photoURL`) | 로그인 수단 프로필 이름(가입 수단 먼저, 없으면 연결된 수단 가운데 첫 값) |
| 3 | 로그인 수단 프로필 사진(같은 순서) | 계정 정보 화면은 「-」, 설정 계정 행은 이메일(없으면 「-」) |
| 4 | 기본 아바타 | — |

- **자르기 화면은 없다:** 사진은 원형 40 dp 에 가운데를 맞춰 그린다. 자르기 · 필터를 넣으려면 패키지를 고르기 전에 [iOS 의존성 관리 (SPM)](#ios-의존성-관리-spm) ③ 대로 SPM 지원부터 확인하고, `profile_photo_repository.dart` 의 `pickImage` 뒤 · `putFile` 앞에 끼운다. 올릴 때 넣는 `contentType` 은 자른 결과 형식에 맞춘다.
- **탈퇴하면:** 서버가 `users/{uid}/` 아래 Storage 파일을 계정 삭제보다 먼저 모두 지운다. 본인 경로 아래 파일이 많을수록 탈퇴가 오래 걸린다.

### Firestore 저장소 · 보안 규칙

**저장소 본보기:** `users/{uid}/fcmTokens` 저장소(`lib/features/notifications/data/fcm_token_repository.dart`)가 킷의 타입 고정 Firestore 저장소다 — 컬렉션 참조를 `withConverter` 로 Freezed 모델(`FcmToken`)에 묶고, 날짜는 `@TimestampConverter()`(`lib/core/firestore/timestamp_converter.dart`)로 바꾸고, 메서드는 `guardResult` 로 감싸 `Result<T>` 를 돌려준다. 새 컬렉션을 처음부터 만드는 과정은 튜토리얼 [③ withConverter 저장소](#-withconverter-저장소) · [⑧ Firestore rules 와 rules 시험](#-firestore-rules-와-rules-시험) 이 이 꼴을 그대로 따른다. 문서 전체를 앱이 가지는 서브컬렉션은 이 꼴이 맞고, 필드가 적고 서버와 한 문서를 나눠 쓰면 `set(…, SetOptions(merge: true))` 의 map 쓰기가 맞다(예: 약관 동의 기록).

**`users/{uid}` 필드 규칙(`firestore.rules`):**

| 대상 | 규칙 |
|---|---|
| 읽기 | 본인만 |
| 앱이 쓸 수 있는 키 | `clientKeys()` 의 `termsAccepted` · `signUpProviderId` · `customPhotoUrl` 셋만. 바꾸는 키만 검사하므로 사진만 바꾸는 쓰기는 다른 키를 다시 검사하지 않는다 |
| 서버만 쓰는 키 | `linkedProviders` · `providerLinkedAt` · `email` · `emailVerified` · 로그인 수단 프로필 사본 — Cloud Functions 가 쓴다 |
| `signUpProviderId` | 한 번만 쓴다 — 바꾸거나 지울 수 없다 |
| `termsAccepted` | 지울 수 없고, 버전은 줄지 않고, 필수 두 항목(`service` · `privacy`)이 `true` 이고, `acceptedAt` 은 미래일 수 없다 |
| `customPhotoUrl` | `null` 이거나 2048자 이하의 Firebase Storage 내려받기 주소(`https://firebasestorage.googleapis.com` 으로 시작) |
| 문서 삭제 | 앱은 못 한다(탈퇴는 서버가 지운다) |
| `users/{uid}/fcmTokens/{token}` | 본인만 읽고 지운다. 만들기 · 고치기는 게스트가 아닌 본인만, 키 다섯(`token` · `platform` · `locale` · `updatedAt` · `expireAt`)만, `expireAt` 은 지금 + 60일 이하 |

**새 필드를 쓰려면:** 앱이 `users/{uid}` 에 새 키를 쓰면 `firestore.rules` 의 `clientKeys()` 에 그 키를 더하고 rules 시험도 더한다 — 안 하면 앱의 쓰기가 `permission-denied` 로 거부된다. `FcmToken` 에 필드를 더하면 fcmTokens 규칙의 `hasOnly` 목록도 고친다. 규칙은 형식뿐 아니라 값의 범위도 검사하는 것이 기본이다 — 새 필드에도 길이 · 형식 상한을 둔다. 사진을 Storage 밖(CDN 등)에 두면 `photoOk` 의 주소 정규식을, `kFcmTokenTtl`(`lib/features/notifications/domain/fcm_token.dart`)을 60일 넘게 늘리면 fcmTokens 규칙의 `duration.value(60, 'd')` 를 함께 고친다.

**rules 시험과 배포:** rules 를 고치면 에뮬레이터에서 시험을 돌린다. 실제 Firebase 프로젝트에는 접속하지 않는다. Java 11 이상이 필요하고, 처음 한 번은 에뮬레이터 파일을 내려받는다. 포트 8080(Firestore) · 9199(Storage) · 9150 이 비어 있어야 한다. 쓰는 법은 튜토리얼 [⑧](#-firestore-rules-와-rules-시험) 에 있다.

```bash
cd functions && pnpm test:rules
```

시험이 통과하면 고친 rules 를 올린다. Storage rules 는 `--only storage` 로 올린다.

```bash
firebase deploy --only firestore:rules --project <your-project-id>
firebase deploy --only storage --project <your-project-id>
```

**오류 처리:** 데이터 계층과 화면 상태 계층이 예상 못 한 예외를 한 번씩 잡아 Crashlytics 에 남기고, 사용자에게는 앱 문구로 보인다. 킷이 분류한 오류(`AppException`)는 기록하지 않는다.

| 상황 | 쓸 것 | 하는 일 |
|---|---|---|
| 저장소 메서드 본문 | `guardResult('<저장소>_<메서드>', () async { … }, crashlytics: …)`(`lib/core/error/guard_result.dart`) | `AppException` 은 그대로 `Result.failure`, 그 밖은 기록 뒤 `UnknownException` |
| Notifier 의 비동기 작업 | `state = await guardAsyncValue(() => …, reason: '<notifier>_<메서드>', crashlytics: …)` | `AppException` 이 아닌 것만 기록 |
| 화면 안 고정 위치의 오류(폼 위 등) | `ErrorBanner(exception: e)`(`lib/shared/widgets/error_banner.dart`) | `null` 이면 높이 0 |
| 고정 위치가 없는 잠깐의 오류(버튼 동작 실패 등) | `showErrorSnackBar(context, e)`(`lib/shared/widgets/error_snack_bar.dart`) | 연달아 부르면 마지막 하나만 남는다 |
| provider 의 `AsyncValue` 를 그대로 그릴 때 | `AsyncValueView<T>(value: …, data: …, onRetry: …)`(`lib/shared/widgets/async_value_view.dart`) | 기본 로딩 · 오류(+「다시 시도」), 또는 `loading:` · `error:` builder |

- **기록 이름:** `'<저장소>_<메서드>'` 꼴의 코드 경로 이름만 쓴다. 이메일 · 토큰 · URL · 파일 경로 · 서버 메시지는 넣지 않는다.
- **문구:** 세 표면 모두 `lib/core/l10n/exception_l10n.dart` 의 `resolveExceptionMessage` 를 거친다. 새 `AppException` 종류를 만들면 그 파일의 switch 에 항목을 더하고 그 시험에도 항목을 더한다 — 빠지면 debug 는 assert 로 멈추고 release 는 일반 오류 문구를 보인다.
- **깨진 화면 대체 `ErrorFallback`:** release · profile 빌드에서 위젯을 그리다 예외가 나면 빨간 화면 대신 「문제가 발생했습니다」 / 「앱을 종료한 뒤 다시 실행해 주세요.」(ARB `errorWidgetFallbackTitle` · `errorWidgetFallbackBody`)를 그리고, 앱을 실행할 때마다 처음 한 번만 non-fatal 을 남긴다. debug 빌드는 빨간 화면 그대로이므로 `--profile` 이나 `--release` 로 확인한다. 위젯은 `lib/shared/widgets/error_fallback.dart` 다.
- **App Check 차단 안내:** callable 함수가 App Check 로 거부되면 앱은 「요청을 확인하지 못했습니다. 잠시 후 다시 시도해 주세요. 계속되면 앱을 최신 버전으로 업데이트해 주세요.」(ARB `errorAppCheckFailed`)를 보이고 다시 로그인하라고 보내지 않는다. 판정은 `classifyAppCheckRejection`(`lib/core/functions/callable_rejection.dart`) 하나가 하고 non-fatal `app_check_rejected_<함수 이름>` 을 남긴다 — 내 callable 을 부르는 코드도 `FirebaseFunctionsException` 을 이 함수에 먼저 넘긴다. App Check 등록은 [App Check 등록 확인](setup.md#app-check-등록-확인) 이다.
- **오프라인 배너는 없다:** 요청이 실패하면 인터넷 연결 오류 문구가 위 표면으로 나간다. 늘 보이는 오프라인 배너가 필요하면 연결 감지 패키지를 더하고 그 상태를 앱 화면 틀에 그린다.

### Cloud Functions 함수 더하기

내가 만든 callable 함수를 킷 배포에 더하는 절차다.

**① 함수 파일과 export.** `functions/src/` 에 `onCall` 함수 파일을 두고 `functions/src/index.ts` 에 export 한 줄을 더한다. 아래 예시는 `functions/src/my_function.ts` 로 그대로 저장해도 `pnpm run build` · `pnpm run lint` 를 통과한다. region 은 `functions/src/index.ts` 의 전역 설정을 따른다.

```typescript
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import {defineSecret} from "firebase-functions/params";

// secret 이 없는 함수는 이 줄과 아래 secrets 옵션을 지운다.
const MY_SECRET = defineSecret("MY_SECRET");

export const myFunction = onCall(
  {enforceAppCheck: true, secrets: [MY_SECRET]},
  (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "errorUnauthenticated");
    }
    const uid = request.auth.uid;
    logger.info({event: "my_function_invoked", uid}, "myFunction invoked");
    // secret 값은 MY_SECRET.value() 로 읽는다. 로그에 남기지 않는다.
    return {ok: true};
  },
);
```

`functions/src/index.ts` 에 더할 줄:

```typescript
export {myFunction} from "./my_function";
```

**② 시험.** `functions/test/` 에 시험을 둔다. 킷의 함수 시험처럼 `firebase-functions-test` 로 함수를 감싸 부른다.

**③ secret.** 함수가 secret 을 쓰면 예시처럼 `defineSecret` 으로 선언해 `secrets` 옵션에 넣고, 배포 전에 값을 등록한다.

```bash
firebase functions:secrets:set MY_SECRET --project <your-project-id>
```

**④ 배포 목록에 이름을 더한다.** 함수 이름(예: `myFunction`)을 `scripts/functions_manifest.json` 의 `common` 배열에 더한다. 빠뜨리면 `functions/` 의 `pnpm test` 에서 배포 목록 대조 시험이 실패하고, 배포 스크립트가 그 함수를 배포하지 않는다.

**⑤ 게이트.**

```bash
cd functions
pnpm run lint
pnpm run build
pnpm test
cd ..
```

**⑥ 배포.** 먼저 옵션 없이 실행해 출력의 `functions` 목록에 새 함수가 있는지 보고, 맞으면 `--apply` 로 배포한다. 처음 배포한 함수는 공개 호출이 켜졌는지 본다 — [인증 메일 발송 모드 켜고 끄기](#인증-메일-발송-모드-켜고-끄기) 「켜기」 ⑥ 과 같은 방법으로, 인증 없이 보낸 POST 가 `401` 이면 정상이고 `403` 이면 공개 호출이 빠진 것이다(Google Cloud 콘솔 → Cloud Run 의 그 서비스에서 같은 칸을 켠다).

```bash
bash scripts/deploy_functions.sh dev
bash scripts/deploy_functions.sh dev --apply
```

앱에서 부를 때 거부 처리는 위 「오류 처리」 의 App Check 차단 안내를 따른다.

### 공개 프로필 · 이름 편집 넓히기

킷에는 공개 프로필과 이름 편집이 없다 — 앱에 필요하면 아래 방향으로 더한다. Firebase 는 Auth 사용자 객체에 속성을 더하지 말고 다른 저장소에 두라고 안내한다 — 「You cannot add other properties to the user object directly; instead, you can store the additional properties in any other storage services, like Google Cloud Firestore.」 (<https://firebase.google.com/docs/auth/users>).

1. **공개 프로필은 별도 문서(예: `profiles/{uid}`)에 둔다.** Firestore rules 는 문서 단위로 읽는다 — 「Reads in Rules are performed at the document level. You either retrieve the full document, or you retrieve nothing.」 (<https://firebase.google.com/docs/firestore/security/rules-fields>). `users/{uid}` 는 비공개 필드(`email` · `linkedProviders` · `termsAccepted`)를 담고 본인만 읽으므로, 공개할 값은 별도 문서로 뺀다.
2. **편집할 값의 원본을 옮긴다.** 공개 프로필을 더하면 `customPhotoUrl` 과 이름 필드(더했다면)의 원본을 공개 문서로 옮긴다. 두 문서에 사본을 두지 않는다 — 사본은 어긋난다.
3. **공개 문서 규칙:** 이메일을 넣지 않는다. 공개 여부 필드를 두고 rules 에서 그 값(또는 본인)으로 읽기를 판정한다. 쓰기는 본인 + 키 허용 목록(`users/{uid}` 의 `clientKeys()` 와 같은 방식)으로 한다.
4. **이름 편집은 사진과 같은 꼴이다:** 앱이 가지는 Firestore 필드(예: `customDisplayName`)를 더한다 — `firestore.rules` `clientKeys()` 에 키 하나 + rules 시험, 사용자 문서를 읽는 모델 · 파서에 필드 하나, 표시 이름 계산에서 `resolveProfileValue` 결과보다 먼저 쓴다. Auth `displayName` 에는 쓰지 않는다 — 가입 수단으로 다시 로그인하면 로그인 수단 프로필로 덮어쓴다([알아 둘 동작](#알아-둘-동작) 의 프로필 갱신).

### 바꿀 수 있는 지점

| 바꾸고 싶은 것 | 고칠 곳 |
|---|---|
| Remote Config 스위치 추가 | `FeatureFlag` enum 에 한 줄 — 위 「Remote Config」 의 「스위치 더하기」 |
| 공지 언어 추가 | `FeatureFlag` enum 에 `announcementMessageXx('announcement_message_xx', '')` 한 줄 + `announcementMessageFlagFor` 의 switch 한 줄. 앱 언어 자체(ARB · supportedLocales)를 더하는 일은 따로다 |
| 알림 채널 id | `kNotificationChannelId` + Android manifest 의 `default_notification_channel_id` 두 곳. 이미 설치된 기기의 채널 중요도는 OS 가 사용자 설정을 앞세우므로 바꾸려면 새 id 를 쓴다 |
| 알림 채널 이름 · 설명 | ARB `notificationChannelGeneralName` · `notificationChannelGeneralDescription` |
| 알림 아이콘 | `android/app/src/main/res/drawable/ic_notification.xml` 하나 — 흰색 단색 vector 로 브랜드 실루엣을 넣는다(색을 넣어도 OS 는 투명도만 쓴다) |
| 알림 색 | `android/app/src/main/res/values/colors.xml` 의 `notification_color` + `lib/features/notifications/data/local_notifications_service.dart` 의 `_kNotificationColor` 두 곳(지금 `#673AB7`). 시드 색을 바꾸면 함께 바꾼다 |
| 알림 문구 언어 추가 | 서버 `functions/src/messaging/test_push_copy.ts` 의 `TestPushLocale` · `TEST_PUSH_COPY` + 앱 `normalizeFcmLocale` 이 받는 언어 + `firestore.rules` fcmTokens 의 `locale` 허용 목록. ARB 와 별개다 |
| 알림 탭으로 열 화면 | 새 화면은 홈 GoRoute 의 `routes` 안에 두고, 경로를 `kNotificationRoutableRoutes` 에 더한다 — 단계 · 넣지 않는 화면 · 정식 사용자 전용 화면은 [④ 알림 탭으로 열 화면](#-알림-탭으로-열-화면--허용-목록). 경로는 문자열이 정확히 같아야 하므로 query · 경로 변수는 쓸 수 없다 |
| 앱 링크(딥링크)로 여는 화면 | Android 앱은 알림 data 의 `route` 를 앱 시작 경로로 받지 않도록 `lib/core/router/app_router.dart` 의 `overridePlatformDefaultLocation: true` 로 늘 스플래시에서 시작한다. MainActivity 에 App Links 를 붙이면 이 설정을 함께 다시 본다 |
| 기기 토큰 만료 기간 | `kFcmTokenTtl`(`lib/features/notifications/domain/fcm_token.dart`) 하나. TTL 정책은 `expireAt` 필드 기준이라 다시 켜지 않아도 된다. 60일 넘게 늘리면 rules 의 `duration.value(60, 'd')` 도 고친다 |
| 알림 섹션 위치 | `lib/features/settings/presentation/settings_screen.dart` 의 `const NotificationsSection()` 한 줄 |
| Storage 경로 · 크기 · 형식 | `storage.rules` 의 그 줄(예: 5MB = `5 * 1024 * 1024`) + rules 시험 경계 경우 → `pnpm test:rules`. 크기를 바꾸면 `kProfilePhotoMaxBytes` 도, 경로를 바꾸면 `profilePhotoPath` 도 고친다 |
| 올리는 사진 크기 | `profile_photo_repository.dart` 의 `pickImage` 인자(`maxWidth` · `imageQuality`) |
| 사진 고르는 중 앱이 종료되면 | 킷은 되찾지 않는다 — Android 는 갤러리가 떠 있는 동안 메모리가 모자라 앱이 종료되면 고른 사진이 사라진다. 필요하면 계정 정보 화면에 들어올 때 `ImagePicker.retrieveLostData()`(Android 전용)를 한 번 보고, 파일이 있으면 `ProfilePhotoRepository` 의 올리기 단계를 이어 간다 |
| 보이는 사진 · 이름의 순서 | `lib/features/auth/domain/profile_display.dart` 의 `resolveProfileValue` 한 곳 |
| 오류 표시 모양 | `lib/shared/widgets/error_banner.dart` · `error_snack_bar.dart` · `async_value_view.dart` — 모든 화면이 이 셋을 거친다 |
| 깨진 화면 대체 문구 | ARB `errorWidgetFallbackTitle` · `errorWidgetFallbackBody`(바꾸면 그 위젯의 golden 그림이 바뀐다) |
| 시험 알림 끄기 · 함수 빼기 | [알림 시험 발송](#알림-시험-발송) 의 「끄기」 · [③ 데모 화면](#-데모-화면--위치--노출-조건--지우는-법) 의 지우는 법 |
| 사진 권한 문구 번역 | `ios/Runner/Info.plist` 의 `NSPhotoLibraryUsageDescription` 은 영어 한 문장이다. 한국어 · 일본어는 `InfoPlist.strings` 를 더해 번역한다 |
| 공개 프로필 · 이름 편집 | 위 「공개 프로필 · 이름 편집 넓히기」 |

## 빌드 · 출시

### 릴리스 서명(keystore)

## 출시 전 점검

### 로그인 수단 검수 · 인증

### 소셜 로고 · 브랜드 자산

### ATT 와 iOS Facebook 로그인

## 앱 운영하기

출시한 앱을 운영하면서 하는 일 — 로그인 수단 버튼을 급히 숨기기, 오류 보고 · 사용 통계 확인, 시험 알림 보내기, 게스트 계정 정리 — 을 모은다. 예시는 dev flavor 기준이다. flavor 마다 Firebase 프로젝트가 다르므로 콘솔 작업은 그 flavor 의 프로젝트에서 한다.

### Kill Switch 로 로그인 수단 막기

출시 뒤 한 로그인 수단을 급히 막아야 할 때(그 수단의 장애 · 키 유출 등), 또는 가입자가 있어 로그인 수단 목록에서 뺄 수 없는 수단의 버튼을 숨길 때 쓴다. 앱을 다시 빌드하거나 배포하지 않고 Firebase Remote Config 값 하나로 버튼을 숨긴다. 위저드는 Remote Config 를 바꾸지 않으므로 이 절차는 직접 한다.

**키:** 수단마다 `auth_provider_<토큰>_enabled` 하나다. `<토큰>` 은 `enabledAuthProviders` 에 쓰는 토큰(`google` · `apple` · `facebook` · `kakao` · `naver` · `line`)이다 — 예: `auth_provider_kakao_enabled`.

| 로그인 수단 목록(`enabledAuthProviders`) | Remote Config 키 | 버튼 |
|---|---|---|
| 있음 | 키가 없거나 `true` | 보인다 |
| 있음 | `false` | 숨긴다 |
| 없음 | 무엇이든 | 숨긴다 — Remote Config 로는 켤 수 없다 |

콘솔에 키가 없어도 앱은 목록에 있는 수단을 보인다 — 앱이 목록대로 기본값을 넣는다. 그래서 키는 막을 때만 만든다.

**단계:**

1. Firebase 콘솔(<https://console.firebase.google.com>)에서 막을 flavor 의 프로젝트를 열고 Remote Config 화면으로 간다 — [[LABEL: Firebase — Remote Config 메뉴 위치]].
2. 매개변수를 더한다 — [[LABEL: Firebase — Remote Config 매개변수 추가 창(이름 · 데이터 유형 · 기본값 칸)]]. 이름은 위 키(예: `auth_provider_kakao_enabled`), 데이터 유형은 `Boolean`, 기본값은 `false` 다. 같은 이름의 매개변수가 이미 있으면 그 값을 `false` 로 바꾼다.
3. 변경사항을 게시한다 — [[LABEL: Firebase — Remote Config 변경사항 게시 버튼]]. 게시하기 전의 값은 앱에 가지 않는다.

**언제 반영되나:** 앱은 시작할 때 Remote Config 를 가져와 적용한다. dev 는 시작할 때마다 새 값을 가져오고, stg · prod 는 마지막으로 가져온 지 12시간이 지난 뒤에 새 값을 가져온다. 앱이 떠 있는 동안(홈 화면을 한 번 연 뒤)에는 게시한 값이 다시 시작하지 않아도 곧 반영될 수 있다.

**확인 방법:** 앱을 다시 시작한 뒤 로그인 화면 · 게스트에게 뜨는 로그인 권유 시트 · 계정 정보 화면의 「계정 연결」 에서 그 수단의 버튼이 없다. 버튼만 숨기므로 그 수단으로 가입한 계정은 그대로 남는다.

**문제 해결:**

- **게시했는데 버튼이 그대로 보인다.** 매개변수 이름이 위 키와 글자까지 같은지(토큰은 소문자), 데이터 유형이 `Boolean` 인지, 막을 flavor 의 프로젝트에 게시했는지 본다. stg · prod 는 마지막으로 가져온 지 12시간이 지나야 새 값을 가져온다 — 바로 확인하려면 앱을 지웠다가 다시 설치한다.
- **목록에 없는 수단을 `true` 로 게시했는데 버튼이 없다.** Remote Config 는 목록에 있는 수단만 숨길 수 있다. 수단을 켜는 일은 [로그인 수단 켜기](setup.md#로그인-수단-켜기) 다.

**되돌리기:** 그 매개변수를 `true` 로 바꾸거나 매개변수를 지우고 게시한다 — 키가 없으면 버튼이 보인다. 반영 시점은 위 「언제 반영되나」 와 같다. 수단을 목록에서 아예 빼는 법은 [로그인 수단 끄기](setup.md#로그인-수단-끄기) 다 — 가입자가 있는 수단은 목록에서 빼지 않는다.

### Crashlytics · Analytics

오류 보고(Crashlytics)와 사용 통계(Analytics) 코드는 모든 flavor 에서 켜져 있다. 할 일은 받는 쪽 확인이다 — Firebase 콘솔에서 그 프로젝트의 Crashlytics 를 쓰기 시작하기 전이면 오류 보고가 들어오지 않는다.

**첫 화면 확인:** Firebase 콘솔에서 그 프로젝트의 Crashlytics 를 열어 [[LABEL: Firebase — Crashlytics 첫 화면(사용 설정 · 온보딩 화면이면 그 버튼)]] 을 확인한다. 프로젝트마다 한 번 본다.

**오류 보고 시험(dev):**

1. debug 빌드로 실행한다.

   ```bash
   fvm flutter run --flavor dev --dart-define-from-file=config/dev.json
   ```

2. 데모 화면의 Dev Tools 에서 「테스트 에러 전송」 을 누른다. Dev Tools 는 debug 빌드에만 있다 — 데모 화면 위치는 [③ 데모 화면](#-데모-화면--위치--노출-조건--지우는-법).
3. Firebase 콘솔의 Crashlytics 에 non-fatal 오류 `Dev Tools test error` 가 나타난다. 나타나기까지 시간이 걸릴 수 있다.

**사용 통계 확인(DebugView):** Analytics 의 일반 보고서는 늦게 반영되고, DebugView 는 디버그 모드로 켠 기기의 이벤트를 바로 보여 준다. 킷은 디버그 모드를 저절로 켜지 않으므로 기기에서 켠다.

```bash
# Android 에뮬레이터 · 실기기 (dev flavor 의 패키지 이름)
adb shell setprop debug.firebase.analytics.app com.slimpumpkin.flutter_starter_kit.dev

# Android 디버그 모드 끄기
adb shell setprop debug.firebase.analytics.app .none.
```

패키지 이름을 바꿨으면 `com.slimpumpkin.flutter_starter_kit` 자리에 내 패키지 이름을 쓴다(dev flavor 는 끝에 `.dev`). iOS 는 Xcode → Product → Scheme → Edit Scheme → Run → Arguments 의 Arguments Passed On Launch 에 `-FIRDebugEnabled` 를 더한다. 켠 뒤 Dev Tools 의 「Analytics 이벤트 전송」 을 누르면 [[LABEL: Firebase — Analytics DebugView 메뉴 위치]] 에 이벤트 `dev_tools_test_event` 가 나타난다.

**출시 빌드:** release 빌드의 크래시 위치를 읽으려면 dSYM(iOS) · NDK 기호(Android)를 올린다 — [빌드 · 출시](#빌드--출시) 에 있다.

**문제 해결:**

- **오류 보고가 들어오지 않는다.** 앱 실행 로그에 `"firebase_crashlytics_enabled": false` 가 보이면 그 프로젝트에서 Crashlytics 를 쓰기 시작하기 전이다. 위 「첫 화면 확인」 대로 콘솔에서 Crashlytics 사용 설정을 확인한 뒤 「테스트 에러 전송」 을 다시 누른다. `android/app/src/main/AndroidManifest.xml` 에 `firebase_crashlytics_collection_enabled` 를 `false` 로 넣었다면 지운다 — 킷은 이 값을 넣지 않는다.
- **DebugView 에 이벤트가 없다.** 위 명령의 패키지 이름이 실행한 flavor 의 패키지 이름과 같은지 본다. 명령을 실행한 뒤 앱을 다시 시작한다.

### 알림 시험 발송

알림이 내 기기까지 오는지, 탭하면 화면이 열리는지 볼 때 쓴다. 데모 화면 Dev Tools 의 「나에게 테스트 알림 보내기」 가 내 계정에서 알림 받기를 켠 모든 기기로 시험 알림을 보낸다. 서버의 보내기 스위치 `SEND_TEST_PUSH_ENABLED` 는 기본으로 꺼져 있다 — 개발 프로젝트에서만 켜고, 시험을 마치면 끈다.

**전제:**

- [FCM 알림](#fcm-알림) 대로 알림을 받을 수 있다(iOS 는 [APNs 인증 키 올리기](setup.md#apns-인증-키-올리기)).
- debug 빌드에 게스트가 아닌 계정으로 로그인했고, 설정 → 「알림」 → 「알림 받기」 를 켰다.

**켜기:**

1. `functions/.env.<your-project-id>` 에 아래 한 줄을 넣는다. `<your-project-id>` 는 `config/dev.json` 의 `firebaseProjectId` 값이다. 파일이 없으면 새로 만든다. 이 파일은 git 이 무시하므로 커밋하지 않는다.

   ```
   SEND_TEST_PUSH_ENABLED=true
   ```

2. 함수를 다시 배포한다. 옵션 없이 실행한 출력의 `functions` 목록에 `sendTestPush` 가 있는지 본 뒤 `--apply` 를 붙인다.

   ```bash
   bash scripts/deploy_functions.sh dev
   bash scripts/deploy_functions.sh dev --apply
   ```

3. 앱의 데모 화면 Dev Tools 에서 「나에게 테스트 알림 보내기」 를 누른다.

**확인 방법:** 누른 뒤 아래 안내 가운데 하나가 뜬다. 앱을 홈 화면으로 내린 상태에서도 알림이 오고, 알림을 탭하면 설정 화면이 열린다.

| 안내 | 뜻 |
|---|---|
| 「기기 N대에 테스트 알림을 보냈어요.」 | 보냈다 — N 은 알림을 받아 간 기기 수다 |
| 「알림을 받을 기기가 없어요. 설정에서 알림 받기를 켜 주세요.」 | 내 계정에 알림 받기를 켠 기기가 없다 |
| 「이 환경에서는 테스트 알림을 보낼 수 없어요.」 | 스위치가 꺼져 있다 — 「켜기」 ① · ② 를 본다 |
| 「게스트 상태에서는 테스트 알림을 보낼 수 없어요. 로그인한 뒤 설정에서 알림 받기를 켜 주세요.」 | 게스트로 눌렀다 — 게스트는 알림을 받지 않는다 |
| 그 밖의 오류 안내 | 네트워크 · App Check 등으로 실패했다. 같은 계정으로 1분에 10번을 넘게 누르면 잠시 거부한다 |

**끄기(운영 필수):** 그 줄을 지우거나 값을 `false` 로 바꾸고 「켜기」 ② 로 다시 배포한다. 값이 정확히 `true` 가 아니면 꺼져 있다. stg · prod 의 파일에는 이 줄을 넣지 않는다. [인증 메일 발송 모드](#인증-메일-발송-모드-켜고-끄기) 의 배포 스크립트는 같은 파일의 메일 줄만 고치고 이 줄은 그대로 둔다. 함수 자체를 앱에서 빼는 법은 [③ 데모 화면](#-데모-화면--위치--노출-조건--지우는-법) 의 지우는 법에 있다.

### 익명 계정 정리

게스트(익명) 계정이 쌓이는 것을 정리하고 싶을 때 쓴다. 앱은 로그인하지 않은 사용자를 익명 계정으로 두므로, 앱을 연 기기마다 익명 계정이 생기고 로그아웃할 때마다 빈 익명 계정이 하나 더 남는다. Firebase 는 만든 지 30일이 지난 익명 계정을 자동으로 지우는 기능을 준다. 이 기능을 켜려면 프로젝트를 Identity Platform 으로 업그레이드해야 하고, 위저드는 업그레이드도 자동 정리도 하지 않는다.

공식 문서 「Automatic clean-up」(<https://firebase.google.com/docs/auth/web/anonymous-auth>):

> "If you've upgraded your project to Firebase Authentication with Identity Platform, you can enable automatic clean-up in the Firebase console."
> "…automatically delete anonymous accounts older than 30 days."
> "If you 'upgrade' an anonymous account by linking it to any sign-in method, the account will not get automatically deleted."
> "In projects with automatic clean-up enabled, anonymous authentication will not count toward usage limits or billing quotas."

**켜기:**

1. Firebase 콘솔의 Authentication 설정에서 프로젝트를 Identity Platform 으로 업그레이드한다 — [[LABEL: Firebase — Authentication 설정의 Identity Platform 업그레이드 버튼]]. 앱 코드는 바꾸지 않아도 된다(「You do not need to change your apps when upgrading from Firebase Authentication to Identity Platform…」 — <https://docs.cloud.google.com/identity-platform/docs/product-comparison>). 요금 · MAU 한도 · 되돌릴 수 있는지는 공식 문서(<https://firebase.google.com/pricing> · 위 product-comparison 페이지)로 확인한다.
2. 같은 설정에서 익명 계정 자동 정리를 켠다 — [[LABEL: Firebase — Authentication 설정의 익명 계정 자동 정리 칸]].

**알아 둘 것:**

- **기준은 만든 시점이다(쓰지 않은 기간이 아니다).** 만든 지 30일이 지난 익명 계정이 지워진다. 켜기 전에 만든 계정은 켠 때부터 30일 뒤가 대상이다. 로그인 수단을 연결해 정식 계정이 된 계정은 지워지지 않는다.
- **Auth 계정이 지워져도 Firestore · Storage 의 데이터는 남는다.** 그래서 킷은 익명 사용자에게 데이터를 만들지 않는다 — 기기 알림 토큰과 프로필 사진은 rules(`firestore.rules` · `storage.rules`)가 익명의 쓰기를 막고 앱도 정식 사용자에게만 그 메뉴를 보이며, `users/{uid}` 문서도 익명에게는 만들지 않는다. 익명 사용자에게 데이터를 저장하는 기능을 더하면 그 데이터를 정리하는 수단(예: 예약 실행 함수)도 함께 만든다.
- **30일 넘게 게스트로만 쓰는 사용자도 지워진다.** 지워진 계정은 다음 ID 토큰 갱신 때 로그아웃처럼 나타나고, 앱은 새 익명 계정으로 온보딩 · 약관 동의를 다시 보여 준다. 게스트 기간을 보장해야 하는 앱은 자동 정리를 끄거나 게스트에게 가입을 권한다.

**끄기:** 같은 설정에서 익명 계정 자동 정리를 끈다. 이미 지워진 계정은 되살아나지 않는다.

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

킷의 analyze 규칙은 `woody_lints` 패키지에서 온다. 규칙이나 riverpod_lint
진단을 끄거나 woody_lints 판을 올릴 때 이 절을 본다.

### 구성

`pubspec.yaml` 의 `dev_dependencies` 가 woody_lints 를 공개 GitHub 저장소의
tag 로 받는다.

```yaml
dev_dependencies:
  woody_lints:
    git:
      url: https://github.com/woodkill/woody_lints.git
      ref: v2.0.0
```

`analysis_options.yaml` 은 묶음 프리셋 하나를 include 한다. 기본 규칙 ·
riverpod_lint plugin · 코드 생성(freezed · json_serializable) 설정이 함께
들어온다.

```yaml
include: package:woody_lints/recommended.yaml
```

- 킷 옵션 파일의 `analyzer: exclude:` 목록(생성 파일 `**/*.g.dart` ·
  `**/*.freezed.dart`, `functions/**`, 플랫폼 폴더)은 지우지 않는다. 프리셋에도
  생성 파일 제외가 있지만 riverpod_lint 진단에는 닿지 않아, 프로젝트의 옵션
  파일에 직접 적어야 막힌다.
- riverpod_lint 는 프리셋의 `plugins:` 가 `^3.1.9` 범위로 선언하고, 분석할 때
  pub.dev 에서 받는다. 그래서 분석에는 네트워크가 필요하고, `pubspec.yaml` ·
  `pubspec.lock` 에는 riverpod_lint 를 따로 적지 않는다. woody_lints 를 tag 로
  고정해도 plugin 은 그 범위 안의 최신 판으로 풀린다.
- woody_lints 2.0.0 은 Dart 3.13 이상이 필요하다. 킷의 `.fvmrc` 가 고정한
  Flutter 가 이를 충족한다.

### 확인 방법

저장소 루트에서 두 명령을 모두 실행하고, 둘 다 `No issues found!` 인지 본다.

```bash
fvm flutter analyze
fvm dart analyze
```

- `fvm flutter analyze` 는 info 진단도 실패로 친다.
- riverpod_lint 진단은 `fvm dart analyze` 에만 나온다.

plugin 준비가 실패하면 출력에 `An error occurred while executing an analyzer plugin:`
머리말이 보인다(첫 줄이 아닐 수 있다). 이때도 종료 코드는 남은 진단대로 나오므로
종료 코드만으로는 알 수 없다.

### 진단 고치기

```bash
fvm dart fix --dry-run
fvm dart fix --apply
```

`--dry-run` 으로 자동으로 고칠 것을 보고 `--apply` 로 고친다. 한 규칙만 고치려면
`--code=<규칙>` 을 붙인다. riverpod_lint 진단은 `dart fix` 가 고치지 않으므로,
자동으로 고쳐지지 않은 진단과 함께 손으로 고친다.

### 한 줄 · 파일 단위로 끄기

- 한 줄: 진단이 시작하는 줄 바로 위에 `// ignore: <규칙>` 을 적는다.
- 파일: 파일 맨 위에 `// ignore_for_file: <규칙>` 을 적는다.
- riverpod_lint 진단은 `riverpod_lint/<규칙>` 처럼 접두사를 붙인다. 접두사가
  없으면 꺼지지 않는다.
- 무시 주석 바로 윗줄에는 끄는 까닭을 적은 주석을 둔다. 없으면 그 무시 주석에
  `document_ignores` info 가 붙는다.
- `///` 문서 주석이 있는 멤버는 진단이 `///` 첫 줄에서 시작하므로, 이유 주석 →
  무시 주석 → `///` 블록 순서로 적는다.

```dart
// 서버가 보낸 표기를 그대로 보여 주는 진단 화면이라 큰따옴표를 둔다.
// ignore: prefer_single_quotes
const String serverSample = "ok";

// 이 자리에서는 <규칙> 이 맞지 않는 까닭을 적는다.
// ignore: riverpod_lint/<규칙>
final items = ref.watch(itemsProvider);
```

### 프로젝트 전체에서 끄기

- 규칙: 킷 `analysis_options.yaml` 에 이미 있는 `linter:` → `rules:` 아래에
  `<규칙>: false` 를 맵 꼴로 더한다. 같은 `rules:` 에 목록 꼴(`- 이름`)을 섞으면
  YAML 이 깨져 `fvm dart analyze` 가 진단 없이 종료 코드 3 으로 끝난다.
- riverpod_lint 진단: 파일 끝에 최상위 `plugins:` → `riverpod_lint:` 를 두고, 그
  아래에 `version: ^3.1.9` 와 `diagnostics:` → `<규칙>: false` 를 적는다.
  - `version` 없이 `diagnostics:` 만 적으면 경고 없이 무시된다.
  - 이 블록이 프리셋의 plugin 선언을 대신하므로 `version` 값은 프리셋 선언과
    같게 적는다.
  - `analyzer: errors:` 로는 riverpod_lint 진단을 끌 수 없다.

```yaml
linter:
  rules:
    prefer_final_locals: false

plugins:
  riverpod_lint:
    version: ^3.1.9
    diagnostics:
      avoid_public_notifier_properties: false
```

바꾼 뒤에는 IDE 의 Analysis Server 를 재시작한다 — VS Code 는 명령 팔레트의
`Dart: Restart Analysis Server`.

### woody_lints 판 올리기

1. 새 tag 의 woody_lints `CHANGELOG.md` 에서 「새로 생기는 경고」 와 요구 SDK 를
   본다.
2. `pubspec.yaml` 의 `ref:` 를 새 tag 로 고친다.
3. `fvm flutter pub get`
4. `pubspec.yaml` 과 `pubspec.lock` 을 함께 커밋한다 — `ref:` 만 바꾸고 lock 을
   그대로 두면 `fvm flutter pub get --enforce-lockfile` 이 실패한다.
5. `fvm flutter analyze` · `fvm dart analyze` 로 새 진단을 본다.
6. `fvm dart fix --apply` 로 고칠 수 있는 것을 고치고, 남은 것은 손으로 고친다.
7. IDE 의 Analysis Server 를 재시작한다.

### 테스트 작성 규칙

- generator provider 를 override 하는 `ProviderScope` 는
  `await tester.pumpWidget(ProviderScope(...))` 처럼 **pumpWidget 의 직접
  인자**로 넘긴다. helper 가 `ProviderScope` 위젯을 반환하거나 다른 위젯으로
  감싸면 규칙이 root scope 로 보지 않아 `scoped_providers_should_specify_dependencies`
  가 난다 → helper 는 `WidgetTester` 를 받아 직접 pump 한다
  (예: `Future<void> _pumpApp(WidgetTester tester, {...})`).
- fake Notifier 에 public 카운터 · 기록 필드 · getter 를 두지 않는다
  (`avoid_public_notifier_properties`). 호출 기록은 생성자로 받은 **외부
  recorder** 객체에 남기고, 테스트는 recorder 를 단언한다.

### 새 코드를 쓸 때의 규칙

1. **Notifier 는 불변 state 만 노출한다.** public 필드 · getter 를 두지 말고
   값을 `state` 에 담는다. 값이 여러 개면 record 나 freezed 값 객체로 묶고,
   파생값은 notifier 밖 순수 함수 · extension 으로 뺀다. 킷의 `TermsState` 가
   그 예다 — 약관 동의 스냅샷 JSON 은 `buildAcceptanceSnapshotJson()` 이 만들고,
   `lastReloadedUid` 는 `ref.read(termsProvider).lastReloadedUid` 로 읽는다.
2. **provider 는 `Listenable` 같은 가변 객체를 값으로 반환하지 않는다.**
   필요하면 **소비하는 쪽**이 만들어 소유하고 `ref.listen` 으로 값을 받아
   올린다 — 그 객체는 소비자의 구현 세부이고, 정리(`ref.onDispose`)도
   소비자 책임이다. `AuthRefresh` notifier 는 인증 상태를 불변 state 로만
   내고, GoRouter 가 요구하는 `Listenable` 은 `appRouter` 의
   `RouterRefreshListenable` 이 만들어 소유한다.

킷 코드(lib · test · tool · bin)에는 riverpod_lint 무시 주석이 없다.

### 문제 해결

- riverpod_lint 진단이 보이지 않는다:
  - `fvm flutter analyze` 로 보고 있다 → `fvm dart analyze` 로 본다.
  - 출력에 `An error occurred while executing an analyzer plugin:` 이 있다 →
    pub.dev 에 닿는지 네트워크를 확인하고 다시 분석한다.
  - 끄는 설정이 듣지 않는다 → `plugins:` 의 `riverpod_lint:` 아래에 `version`
    을 적었는지 본다.
- Analysis Server 를 재시작해도 plugin 준비가 계속 실패하면 woody_lints README 의
  「문제 해결」 을 본다 — <https://github.com/woodkill/woody_lints#문제-해결>.

### 되돌리기

- 끈 줄(`linter: rules:` 의 `<규칙>: false` · `diagnostics:` 아래 줄 · 무시
  주석)을 지우면 다시 켜진다. `plugins:` 블록을 통째로 지우면 프리셋의 plugin
  선언으로 돌아간다.
- 판을 되돌리려면 `pubspec.yaml` 의 `ref:` 를 전 tag 로 고치고
  `fvm flutter pub get` 을 한 뒤 `pubspec.yaml` 과 `pubspec.lock` 을 함께
  커밋한다.

## Git Hooks 활성화 (선택)

실제 Firebase 키가 저장소에 커밋되지 않게 커밋 때마다 검사하고 싶을 때 켠다. 켜지
않아도 빌드 · 시험에는 영향이 없다.

hook(`scripts/git-hooks/pre-commit`)은 커밋할 때 stage 된 파일에 가드 넷을 돌린다.
1 ~ 3 은 **실제 Firebase 키가 저장소에 커밋되는 것을 막는다** — 아래 설정 파일은
자리표시 값으로 tracked 되어 있어, 실제 키로 다시 만든 파일이 그대로 커밋 대상이 되기
때문이다. 4 는 코드 주석의 phase 참조 · `TODO` 주석 검사로, 킷 유지보수자 저장소에서만
돈다 — 킷 사용자 저장소에서는 `[SKIP]` 을 출력하고 커밋을 막지 않는다(규칙과 예시:
[유지보수자 문서](maintainer/code-comment-refs.md)).

| 가드 | 대상 | 막는 조건 |
|------|------|-----------|
| 1 | `lib/core/firebase/firebase_options_{dev,stg,prod}.dart` | index 내용에 FlutterFire CLI 생성 마커가 있음 |
| 2 | `android/app/src/{stg,prod}/google-services.json` | Google API 키 접두사가 있거나 placeholder `project_number` 가 사라짐 |
| 3 | `ios/config/dev/GoogleService-Info.plist` · `ios/config/stg/GoogleService-Info.plist` · `ios/config/prod/GoogleService-Info.plist` | Google API 키 접두사가 있거나 placeholder `GCM_SENDER_ID` 가 사라짐 |
| 4 | 코드 주석의 phase 참조 · `TODO` 주석 | 킷 유지보수자 저장소에서만 검사 — 킷 사용자 저장소에서는 건너뜀 |

**켜기** (clone 직후 1회):

```bash
# scripts/git-hooks/pre-commit 을 .git/hooks/pre-commit 으로 symlink.
# .git/hooks/ 디렉토리 자체는 git tracked 불가 — scripts/git-hooks/pre-commit
# 만 tracked 상태로 두고 symlink 로 활성화한다.
ln -s ../../scripts/git-hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

이후 커밋할 때마다 hook 이 돈다. 가드 1 ~ 3 에 걸리면 커밋이 막히고, 걸린 파일과 해제
절차(`git restore --staged` → `git update-index --skip-worktree`)가 함께 출력된다.
자리표시 파일 자체를 일부러 고치려면 자리표시 값을 남긴 채 실제 키만 지우고 커밋한다.

**끄기:** `rm .git/hooks/pre-commit`.

> ⚠ hook 은 **dart format · analyze · test 를 돌리지 않는다** — 커밋 전
> `fvm dart format --output=none --set-exit-if-changed lib test bin tool` 를 따로
> 돌린다(나머지 검사는 [테스트 돌리기](#테스트-돌리기)).

## Flutter SDK 상향 (FVM)

**내 프로젝트의 Flutter 를 올릴 때** 보는 절이다 — 절차 · 도구가 자동으로 고치는
파일 · 함정을 정리한다. 킷의 지금 Flutter 는 **3.47.5(Dart 3.13.4)** 다.

### ① 버전 pin 의 진실원

| 대상 | 값 | 비고 |
|---|---|---|
| `.fvmrc` | `{"flutter": "3.47.5"}` | **유일한 추적 pin.** 여기만 바꾸면 된다 |
| `.fvm/flutter_sdk` | `~/fvm/versions/<버전>` 심볼릭 링크 | 추적하지 않는다 |
| `.vscode/settings.json` | `"dart.flutterSdkPath": ".fvm/flutter_sdk"` | **심볼릭 링크 경로로 고정** |
| `.mcp.json` dart 서버 | `.fvm/flutter_sdk/bin/dart` | 링크를 따라가므로 수정 불필요 |

- `fvm use <버전>` 은 `.vscode/settings.json` 을 `.fvm/versions/<버전>` 같은
  **버전 박힌 경로**로 바꿔 버린다. 그대로 커밋하면 다음 상향마다 이 파일이
  또 바뀐다 → **`git checkout -- .vscode/settings.json` 으로 되돌린다.**
- `fvm use` 뒤 dart MCP 서버 · IDE 의 Analysis Server 는 옛 SDK 프로세스를 물고
  있을 수 있다 → 세션/IDE 재시작을 권한다.

### ② 상향 절차

1. **같은 HEAD 에서 현재 SDK 기준선을 먼저 잰다** — `pub get` → `build_runner` →
   `flutter analyze` → `dart analyze` → `dart format --output=none
   --set-exit-if-changed lib test bin` → **전체 test**. 이 수치가 유일한 비교 기준이다.
   여기서 이미 실패가 있으면 상향하지 말고 그것부터 해결한다.
2. **iOS 네이티브 SDK 의 고정 상태를 먼저 확인한다** — 두 `Package.resolved` 가
   같은 내용인지(`cmp -s`) 보고, 상향 뒤 그대로인지 대조할 기준으로 삼는다
   (「iOS 의존성 관리 (SPM)」 ②).
3. `fvm install <버전> --skip-pub-get` → `fvm use <버전> --skip-pub-get`
4. `.vscode/settings.json` 복원 · `fvm flutter --version --machine` 으로
   framework/dart 버전 확인
5. `fvm flutter pub get` — **`pub upgrade` 는 쓰지 않는다.** 원인 분리가 깨진다
   (SDK 변화와 패키지 변화가 섞여 실패 원인을 좁힐 수 없게 된다)
6. `fvm dart run build_runner build --delete-conflicting-outputs`
7. `fvm flutter analyze` **그리고** `fvm dart analyze` — 둘 다 필요하다.
   Flutter 3.47.5 의 `flutter analyze` 는 analyzer plugin(riverpod_lint) 진단을
   **표시하지 않는다**(「정적 분석」 절 참고)
8. `fvm dart format --output=none --set-exit-if-changed lib test bin`
9. 전체 `fvm flutter test` — 기준선과 pass/skip/fail 수를 비교
10. iOS `fvm flutter build ios --no-codesign --flavor dev
    --dart-define-from-file=config/dev.json` · Android `fvm flutter build apk
    --debug --flavor dev --dart-define-from-file=config/dev.json`
11. 실기기 smoke — 기동 · 대표 provider 로그인 · 콜드 재기동 세션 복원

### ③ 도구가 자동으로 고치는 tracked 파일 (되돌리지 말고 함께 커밋)

3.41.9 → 3.47.5 에서 실제로 바뀐 것은 다음 3개다. **손으로 되돌려도 다음
`pub get` · 빌드에서 다시 생긴다.**

| 파일 | 원인 | 실제 diff |
|---|---|---|
| `analysis_options.yaml` | 3.47 `AnalysisOptionsMigration`(`flutter pub get` 이 호출) | `analyzer.exclude` 에 `build/**` · `android/**` · `ios/**` · `web/**` · `windows/**` · `macos/**` · `linux/**` **7줄 append**(+7/-0, 기존 주석 보존). stdout 에 `Upgrading analysis_options.yaml …` |
| `android/gradle.properties` | 3.47 `DisableBuiltInKotlin` · `DisableNewDsl` migrator(**모든 Android 빌드 직전** 실행) | `android.builtInKotlin=false` · `android.newDsl=false` + 각 설명 주석 **4줄 append** |
| `pubspec.lock` | SDK 가 고정하는 pub 핀 변화 | 직접 의존성은 `test` · `intl` 둘뿐, transitive 5건(`matcher` · `meta` · `test_api` · `test_core` · `vector_math`). codegen 스택은 불변 |

- `lib/l10n/generated/*.dart`(tracked) 도 SDK 템플릿이 바뀌면 재생성된다 — 재생성되면 함께 커밋한다.
- SPM 통합은 **이미 적용돼 있다.** `ios/Runner.xcodeproj/project.pbxproj` ·
  `ios/Runner.xcodeproj/xcshareddata/xcschemes/*.xcscheme` · `Package.resolved` 가
  바뀌면 **diff 를 읽고 원인을 확인한다** — 도구의 새 migration, 아직 빌드한 적 없는
  scheme 의 첫 빌드, 또는 **SPM 미지원 플러그인의 유입**(「iOS 의존성 관리 (SPM)」 ④)
  셋 중 하나다.

### ④ iOS Swift Package Manager — 기본값(on)을 그대로 쓴다

- `pubspec.yaml` 에 SPM 스위치 키를 **두지 않는다.** Flutter 3.44+ 는 SPM 이 기본 on
  이고 `flutter create` 산출물에도 그 키가 없다 — 킷은 표준 모양을 따른다.
- **실효 증거 3종**(설정값이 아니라 결과로 판정한다): `project.pbxproj` 의
  `FlutterGeneratedPluginSwiftPackage` 참조 ≥ 1 · `ios/Flutter/ephemeral/Packages`
  존재 · `ios/Podfile` 부재.
- 해석 우선순위는 **pubspec `flutter: config:` → 전역 `flutter config` → 환경변수**
  다. `flutter config --list` 는 전역 설정이라 이 프로젝트의 판정 근거가 못 된다.
- 옛 키 `disable-swift-package-manager: true` 는 3.47 에서 **manifest 오류**다.
- iOS 네이티브 의존성의 운영(버전 고정 · 새 플러그인 확인 · 배포 타겟 · 미지원
  플러그인 증상)은 **「iOS 의존성 관리 (SPM)」**(`#ios-의존성-관리-spm`) 절에 있다.

### ⑤ Android 빌드 도구 — 지금 값과 정상 출력

Flutter 를 올렸거나 킷 업데이트를 merge 한 뒤 Android 빌드 로그에서 경고 · 오류를
볼 때 이 항목을 본다. 어떤 출력이 정상인지와 지우면 안 되는 줄을 적는다.

**지금 값**

| 항목 | 킷 값 | 어디에 있나 | 3.47.5 오류 하한 | 3.47.5 경고 하한 |
|---|---|---|---|---|
| Gradle | `9.3.1` | `android/gradle/wrapper/gradle-wrapper.properties` 의 `distributionUrl` | 8.14.0 | 9.1.0 |
| Android Gradle Plugin (AGP) | `9.1.0` | `android/settings.gradle.kts` 의 `id("com.android.application")` | 8.11.1 | 9.0.1 |
| Kotlin Gradle Plugin (KGP) | `2.4.0` | `android/settings.gradle.kts` 의 `id("org.jetbrains.kotlin.android")` | 2.2.20 | 2.3.20 |
| google-services Gradle 플러그인 | `4.5.0` | `android/settings.gradle.kts` 의 `id("com.google.gms.google-services")` | 없음 | 없음 |
| Crashlytics Gradle 플러그인 | `3.0.8` | `android/settings.gradle.kts` 의 `id("com.google.firebase.crashlytics")` | 없음 | 없음 |

- Flutter 는 Gradle · AGP · KGP 가 오류 하한보다 낮으면 빌드를 멈추고, 경고 하한보다
  낮으면 지원 종료 경고를 낸다. 킷 값은 셋 모두 경고 하한 이상이다.

**정상 출력**

- 지원 종료 경고(`Warning: Flutter support for your project's … will soon be dropped`)는
  나오지 않는다.
- 대신 모든 Android 빌드에 Kotlin Gradle Plugin 적용 경고 1줄이 나온다. 그 줄은 다음과
  같다(플러그인 목록은 `…` 로 줄였다).
  ```
  WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): …
  ```
  정상이다 — 목록의 FlutterFire 플러그인 빌드 파일이 Kotlin Gradle Plugin 을 조건에 따라
  적용하는 줄을 담고 있어 Flutter 도구가 경고한다. 앱 모듈은 AGP 의 내장 Kotlin 을 쓴다.
  이 경고는 빌드를 멈추지 않는다.
- `--verbose` 를 붙인 release 빌드 로그에는 AGP 안내 1줄
  `WARNING: The option setting 'android.newDsl=false' is deprecated.` 도 보인다. 새 DSL 을
  아직 끈 상태라서 정상이다(아래 「남은 단계」).

**지우지 말 것**

| 줄 | 파일 | 이유 |
|---|---|---|
| `android.builtInKotlin=true` | `android/gradle.properties` | 앱 모듈이 AGP 의 내장 Kotlin 을 쓴다. `false` 로 되돌리지 않는다 — 끄는 옵션은 AGP 10.0 에서 사라진다 |
| `android.newDsl=false` | `android/gradle.properties` | 옛 DSL 을 쓴다. 켜는 조건은 아래 「남은 단계」 |
| `id("org.jetbrains.kotlin.android") version "2.4.0" apply false` | `android/settings.gradle.kts` | 지우면 AGP 가 함께 가져오는 KGP 2.2.10 이 쓰이고, Flutter 3.47.x 오류 하한 2.2.20 보다 낮아 빌드가 멈춘다(https://github.com/flutter/flutter/issues/192167) |
| `resValues = true` | `android/app/build.gradle.kts` | AGP 9 는 리소스 값 기능이 기본으로 꺼져 있다. 지우면 그 아래 `resValue(...)` 5곳 때문에 설정 단계에서 빌드가 멈춘다(아래 「문제 해결」 첫 항목) |

**남은 단계가 필요해지는 조건**

- **새 DSL 켜기** — `android.newDsl=true` 로 바꾼다. Flutter Gradle 플러그인이 새 DSL 을
  지원할 때 한다(https://github.com/flutter/flutter/issues/180137).
- Flutter 상향과 **별도 작업**으로 한다 — ② 의 원인 분리와 같은 이유다.
- 이 단계는 Android 빌드 설비 계약 시험이 고정한 줄을 바꾼다. 줄을 바꾸면
  `fvm flutter test` 가 실패하므로, 실패한 시험의 기대값 `android.newDsl=false` 를
  `android.newDsl=true` 로 고치고 `fvm flutter test` 를 다시 돌린다.

  같은 계약 시험은 `android/app/build.gradle.kts` 에 Kotlin Gradle Plugin 적용 줄이
  없음과 `android.builtInKotlin=true` 도 고정한다.

**확인 방법**

파일을 남기지 않는 한 줄로 본다(새 clone 처럼 `build/` 가 없어도 된다).

```bash
fvm flutter build apk --debug --flavor dev --dart-define-from-file=config/dev.json 2>&1 | grep -E 'will soon be dropped|WARNING: Your |✓ Built'
```

- `WARNING: Your ` 로 시작하는 줄 1개와 `✓ Built` 줄 1개가 나오면 정상이다.
- `will soon be dropped` 가 든 줄이 보이면 위 표의 값이 경고 하한 아래다.
- `✓ Built` 줄이 없으면 경고 줄이 보여도 빌드가 실패한 것이다(KGP 적용 경고는 빌드
  설정 단계에서 먼저 찍힌다). 같은 빌드 명령을 파이프 없이 다시 돌려 오류를 본다.

**문제 해결**

- `defaultConfig contains custom resource values, but the feature is disabled.` 로 설정
  단계에서 빌드가 멈춘다 → `android/app/build.gradle.kts` 의 `android { buildFeatures { resValues = true } }`
  가 빠졌다(merge 등). 되살린다 — 그 아래 `resValue(...)` 5곳이 Facebook · Naver 값을
  리소스로 넣는데, AGP 9 는 이 기능이 기본으로 꺼져 있다.
- 스크립트 컴파일 오류 `'var jvmTarget: String' is deprecated. Please migrate to the compilerOptions DSL.`
  → 옛 Kotlin 옵션 블록(`kotlinOptions { jvmTarget = … }`)이 들어왔다. 지우고 `flutter {}`
  앞에 `kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }`
  를 둔다.
- Android Studio 로 `android/` 를 열 때 AGP 9.1 을 지원하지 않는다는 안내가 나온다 →
  Android Studio 2025.3.2 이상으로 올린다.

### ⑥ iOS 환경 요구치

- 최소 deployment target: 3.47 은 **iOS 15.0**(3.41 은 13.0). 킷은 15.6 이라 여유가 있다.
- Xcode: 필수 ≥ 15, 권장 ≥ 16. 3.47.4 · 3.47.5 에 **Xcode 27 대응 핫픽스**가
  들어 있다(흰 화면 hang · iOS 27 실기기 디버깅 간헐 크래시) — 3.47.x 를 쓸 거면
  **3.47.5 이상**을 권한다.
- 번들 `iproxy` 는 3.47.5 에서도 여전히 **x86_64** 다 → Apple Silicon 에서 실기기
  실행에 **Rosetta 2 가 필요**하다. macOS major 업그레이드가 Rosetta 를 지울 수
  있으니 `arch -x86_64 /usr/bin/true` 로 확인한다.
- 실기기 debug 실행은 **USB 연결이 필수**다(무선은 디버거 미부착 → JIT 불가).
- **CocoaPods 는 iOS 빌드에 필요하지 않다**(iOS 네이티브 의존성은 SPM 이 관리한다 —
  [iOS 의존성 관리 (SPM)](#ios-의존성-관리-spm)). 이 킷에는 `macos/` 디렉터리가 없다. `flutter doctor` 의 CocoaPods
  항목은 **설치 여부와 무관하게 계속 표시된다** — Xcode 워크플로에 조건 없이
  등록된 검사라 그렇다.

### ⑦ golden test — SDK 상향은 렌더를 바꾼다

- SDK 를 올리면 **golden 이 실패할 수 있다** — 엔진 래스터가 바뀌면 버튼 둥근 모서리
  안티에일리어싱 같은 작은 차이가 생긴다. 상향 전 같은 커밋의 기준선이 green 이면
  원인은 SDK 쪽이다.
- 절차: **같은 HEAD 기준선이 green 인지 먼저 확인** → 실패 golden 의
  `failures/*_isolatedDiff.png` · `*_maskedDiff.png` 를 **눈으로 확인** → 그 뒤에만
  실패한 test 파일만 대상으로 `--update-goldens` → 전체 test 재실행 → 별도 `test:` 커밋.
- 일괄 `--update-goldens` 는 하지 않는다(진짜 회귀를 덮어쓴다).
- iOS 변형 `*_ios.png` 는 Apple Font License 때문에 **gitignore** 라 로컬에서만
  재생성된다 — git 으로 복원할 수 없으니 재생성 전 디렉터리 백업을 권한다.

### ⑧ `environment: sdk` 하한은 별개 작업이다

`pubspec.yaml` 의 `environment: sdk: ^3.11.1` 은 SDK 를 올릴 때 **함께 올리지 않는다.**
Dart 3.13 포매터의 스타일 변경 중 상당수(import 섹션 분리 · 호출 체인 split ·
파라미터 block formatting)는 **language version 3.13 이상에서만** 켜지기 때문에,
하한을 올리면 대량 재포맷과 언어 규칙 변화가 한꺼번에 들어온다. SDK 상향과
**분리해서** 별도 작업으로 다뤄라.

> 단, **language version 과 무관한** 포매터 수정은 하한을 안 올려도 적용된다.
> 그래서 SDK 를 올리면 하한을 그대로 두어도 일부 파일이 재포맷될 수 있다 — 재포맷은
> `style:` 커밋으로 따로 둔다. `dart format --set-exit-if-changed` 를
> analyze · test 와 동급 게이트로 두면(`.claude/rules/dart-format.md`) 이런 drift 가
> 누적되지 않는다.

## iOS 의존성 관리 (SPM)

**iOS 네이티브 의존성을 다룰 때** 보는 절이다 — 이 킷의 iOS 네이티브 의존성 관리자는
**Swift Package Manager(SPM)** 이고, 이 절은 개념 · 버전 고정 · 새 플러그인 사전
확인 · 배포 타겟 변경 절차를 정리한다.

### ① SPM 이 무엇이고 이 킷이 왜 SPM 인가

**Swift Package Manager(SPM)** 는 Apple 이 Swift 도구체인과 Xcode 에 내장한 의존성
관리자다. CocoaPods 가 하던 일(네이티브 SDK 선언 · 버전 해석 · 내려받기 · Xcode
프로젝트 연결)을 **별도 도구 설치 없이** Xcode 와 Flutter 도구가 직접 수행한다.
Flutter 3.44+ 는 SPM 이 **기본 on** 이고 `flutter create` 는 `ios/Podfile` 을
만들지 않는다 — 이 킷도 그 표준 모양(별도 스위치 없이 기본값)을 따른다.

| 항목 | CocoaPods | SPM (이 킷) |
|---|---|---|
| 의존성 선언 | `ios/Podfile` + 각 플러그인의 `<name>.podspec` | 각 플러그인의 `Package.swift` + Flutter 가 매 빌드마다 생성하는 `FlutterGeneratedPluginSwiftPackage` |
| 잠금 파일 | `ios/Podfile.lock` (1개) | `Package.resolved` (**2곳** — ② 참고) |
| 내려받은 산출물 | `ios/Pods/` · `ios/.symlinks/` (프로젝트 안, gitignored) | `build/ios/SourcePackages/checkouts/` (빌드 디렉터리 안, gitignored) |
| 설치 요구 | ruby gem `cocoapods` 를 개발자가 따로 설치 | **없다** — Xcode · Flutter 도구에 내장 |

**왜 SPM 인가 (공식 공지 2건):**

- Firebase 는 CocoaPods 로 **신규 버전 배포를 멈춘다**고 공지했다 — 배포를 멈춘 뒤의
  Firebase 새 판은 SPM 으로만 받는다
  (https://firebase.google.com/docs/ios/cocoapods-deprecation).
- CocoaPods 레지스트리는 영구 **read-only** 가 된다고 공지됐다 — 레지스트리가 읽기
  전용이 된 뒤에는 CocoaPods 로 새 SDK 판을 받을 수 없다
  (https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers).

**Flutter 가 「SPM 비활성화」 와 CocoaPods fallback 을 막는 시점은 미공개다.** 도구는
예고만 한다 — 아래 두 문장이 Flutter 3.47.5 소스의 원문이다.

- `Disabling Swift Package Manager will not be allowed in a future version of Flutter.`
- `This will become an error in a future version of Flutter. Please contact the plugin maintainers to request Swift Package Manager adoption.`

- 특정 Flutter 버전 · 날짜를 추정해 계획을 세우지 않는다. 위 두 예고에는 버전도
  날짜도 없다.
- **범위:** SPM 은 `ios/` 에만 해당한다.
  이 킷은 모바일 전용이라 `macos/` 디렉터리가 없다.

### ② 네이티브 SDK 버전은 어디에 고정돼 있나

**진실원 표**

| 대상 | 값 | 비고 |
|---|---|---|
| `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved` | 20개 핀의 `version` · `revision` | **빌드가 존중하는 쪽.** 실제 빌드가 `-workspace Runner.xcworkspace` 로 돌기 때문 |
| `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | 위와 **바이트 동일**해야 한다 | Flutter 의 사전 해석(prefetch)이 이 컨테이너를 쓴다. 지우면 **핀을 무시한 최신값으로 자동 재생성**된다 |

- 두 파일 모두 tracked 다. 한쪽만 추적하면 fresh clone 의 첫 빌드에서 다른 쪽이
  최신값으로 생기고 `git status` 가 더러워진다.
- 같은지 확인: `cmp -s ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved && echo SAME`
- **이 불변식은 `fvm flutter test` 가 지킨다** — 두 파일이 다르면 시험이 실패한다.
  Xcode 는 **해석한 컨테이너 한쪽만** 갱신하므로(`.xcodeproj` 를
  직접 열면 project 쪽, `Runner.xcworkspace` 를 열면 workspace 쪽) 한쪽만 바뀌는
  것이 **정상 동작**이다. 이 시험이 실패하면 아래 ⚠ 박스가 말하는 핀 drift 가 이미
  시작된 것이다 — 의도한 쪽을 다른 쪽으로 복사해 같은 커밋에 담는다.

**Firebase · 소셜 로그인 SDK 의 현재 고정값** (Google 로그인 SDK 가 끌어오는 전이 의존 `appauth-ios` 도 함께 싣는다 · 표에 없는 핀은 해석 결과를 그대로 수용한다)

| Swift package identity | 고정 버전 | 비고 |
|---|---|---|
| `firebase-ios-sdk` | 12.19.0 | 플러그인이 `exact` 로 고정 — 값을 손댈 필요가 없다 |
| `appauth-ios` | 2.0.0 | `GoogleSignIn-iOS` · `GTMAppAuth` 의 전이 의존 — 두 패키지가 `2.0.0 ..< 3.0.0` 을 요구해 핀이 유지된다 |
| `googlesignin-ios` | 9.1.0 | **명시 고정.** 그래프가 우연히 준 값이다 — 상향 시 `GoogleSignIn-iOS` 가 요구하는 AppAuth 범위와 함께 확인한다 |
| `facebook-ios-sdk` | 18.0.2 | 선언이 `"18.0.2" ..< "19.0.0"` 이라 고정하지 않으면 18.1.1 로 올라간다 |
| `line-sdk-ios-swift` | **5.17.0** | `flutter_line_sdk` 3.0.0 의 선언이 `from: "5.17.0"` 이라 고정하지 않으면 5.18 이상으로 올라간다 · 아래 경고 박스 참고 |
| `naveridlogin-sdk-ios-swift` | 5.2.1 | 선언이 `.upToNextMinor(from: "5.2.0")` |

**상향 절차** — 값 문자열만 고치는 편집이다.

1. 두 `Package.resolved` 에서 대상 핀의 `version` · `revision` **문자열만** 고친다.
2. 두 파일을 **같은 내용**으로 맞춘다(`cmp -s`).
3. `revision` 은 추측하지 말고 태그에서 얻는다 — annotated 태그는 **peeled sha** 를 쓴다.
   ```bash
   git ls-remote --tags <repo-url> | grep -E 'refs/tags/<tag>(\^\{\})?$'
   ```
   - `--refs` 를 붙이면 `^{}` 줄이 **버려져** annotated 태그에서 태그 객체 sha(틀린 값)를 집는다.
4. 재빌드한 뒤 실제 checkout 으로 확인한다.
   ```bash
   ls build/ios/SourcePackages/checkouts          # 디렉터리 이름을 먼저 확인
   git -C build/ios/SourcePackages/checkouts/<디렉터리> describe --tags
   ```
   - **디렉터리 이름은 identity 가 아니라 repo 이름이다.** 위 표의 열 제목이
     「Swift package identity」(소문자)라 헷갈리기 쉬운데, SPM 은 checkout 디렉터리를
     저장소 URL 의 **마지막 경로 요소에서 `.git` 접미사를 뗀 이름**으로 만든다
     (`https://github.com/google/GoogleUtilities.git` → `GoogleUtilities`).
     현재 핀 20개 중 **16개의 `location` 이 `.git` 으로 끝나므로 URL 의 마지막 경로
     요소를 그대로 쓰면 안 된다** — `.git` 이 붙은 이름으로 `git -C` 를 걸면
     `No such file or directory` 가 난다. 재현:
     ```bash
     R=ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved
     jq '.pins | length' "$R"                             # 20
     jq -r '.pins[].location' "$R" | grep -c '\.git$'      # 16
     ```
     identity(소문자)와도 20개 중 6개가 어긋난다 —
     `appauth-ios` → `AppAuth-iOS`, `googlesignin-ios` → `GoogleSignIn-iOS`,
     `googleappmeasurement` → `GoogleAppMeasurement`, `googledatatransport` →
     `GoogleDataTransport`, `googleutilities` → `GoogleUtilities`, `gtmappauth` →
     `GTMAppAuth`.
   - macOS 기본 APFS 는 대소문자를 무시하므로 소문자 identity 로도
     **통한다**. 대소문자 구분 볼륨이나 Linux CI 에서는
     `No such file or directory` 가 난다 — 그래서 `ls` 를 먼저 둔다.
5. 두 파일을 **같은 커밋**에 함께 담는다.

- FlutterFire 계열(`firebase_*` · `cloud_*`)은 플러그인이 `exact` 로 고정하므로 **pub
  패키지를 올리면 네이티브 SDK 가 따라 올라간다** — `Package.resolved` 는 손으로
  고치지 않는다.

> ⚠ **`Package.resolved` 를 지우지 말고, Xcode 의 *Update to Latest Package Versions* 를
> 누르지 말 것.**
>
> 핀이 풀리면 위 표의 SDK 6개가 같은 조작 한 번에 함께 다시 해석된다. `exact` 로 선언된
> `firebase-ios-sdk` 는 값이 그대로다. 범위로 선언된 4개(`googlesignin-ios` ·
> `facebook-ios-sdk` · `line-sdk-ios-swift` · `naveridlogin-sdk-ios-swift`)는 각자 선언
> 범위 안에서, 전이 의존인 `appauth-ios` 는 그것을 쓰는 패키지가 요구하는 범위 안에서
> 다시 해석된다. LINE 은 `flutter_line_sdk` 3.0.0 이 `from: "5.17.0"` 으로 선언하므로
> **5.17.0** 을 벗어나 5.18 이상으로 올라간다.
>
> 지금 킷은 `flutter_line_sdk` 3.0.0(iOS 15.0 이상 · LineSDK 5.17 이상 요구)과 핀
> **5.17.0** 을 함께 쓴다. LINE 핀을 올리려면 위 「상향 절차」 를 따른다.

- **SPM 경로에서는 `firebase_app_check` 가 `RecaptchaEnterprise`(바이너리 XCFramework,
  `recaptcha-enterprise-mobile-sdk` 18.9.1)를 함께 링크한다** — CocoaPods 경로에는 없던
  SDK 다. 앱 크기 · privacy manifest · 심사 신고 대상 판단에 넣을 것.
- **`flutter clean` 은 SPM checkout(`build/ios/SourcePackages`)까지 지운다** — 다음 빌드가
  수백 MB 를 다시 받아 수 분이 걸린다. 캐시 문제를 풀려는 목적이라면 ⑥ 을 먼저 볼 것.

### ③ 새 플러그인을 넣기 전에 확인할 것

**(가) `Package.swift` 가 있는가** — native 코드를 가진 iOS 플러그인 전수 검사.

```bash
jq -r '.plugins.ios[] | select(.native_build) | "\(.name)\t\(.path)"' .flutter-plugins-dependencies \
  | while IFS=$'\t' read -r n p; do
      if [ -f "${p}ios/$n/Package.swift" ] || [ -f "${p}darwin/$n/Package.swift" ]; then
        echo "SPM-OK $n"; else echo "SPM-MISSING $n"; fi
    done | sort
```

- `select(.native_build)` 필터를 빼면 `path_provider_foundation` 같은 **Dart 전용
  플러그인**(`dartPluginClass` 만 있고 네이티브 패키지가 아예 없다)이 `SPM-MISSING` 으로
  오탐된다.
- `SPM-MISSING` 이 0줄인 것만으로 끝내지 말고 **대상 개수가 0 이 아닌지** 함께 본다 —
  0개를 검사하고 통과한 것과 구분되지 않는다.

**(나) 플러그인과 그 의존 SDK 의 `platforms` 하한을 대조한다.**

- 플러그인 `Package.swift` 의 `platforms: [.iOS(...)]` 와, 그 플러그인이
  `.package(url:)` 로 끌어오는 SDK 의 같은 값을 비교한다. **의존 SDK 의 하한이 더 높으면
  SPM 이 타깃 그래프 구성 단계에서 빌드를 막는다.**
- 예: LineSDK 5.17.0 의 하한은 iOS 15.0 이고 `flutter_line_sdk` 3.0.0 의 `Package.swift`
  도 15.0 이라 맞는다. 플러그인 하한이 의존 SDK 하한보다 낮으면 이 불일치는 **앱의 배포
  타겟을 올려도 해소되지 않는다** — Flutter 는 자기가 생성하는
  패키지의 하한만 끌어올리고 플러그인 자신의 `Package.swift` 는 건드리지 않기 때문이다.

**(다) FlutterFire 계열은 `firebaseSdkVersion` 이 기존 플러그인들과 같은지 본다.**

`fvm flutter pub get` 을 먼저 돌린 뒤 실행한다 — `.flutter-plugins-dependencies` 는
gitignored 생성물이라 fresh clone 에는 없다.

```bash
EXPECTED=$(jq -r '[.plugins.ios[] | select(.native_build)
                   | select(.name | startswith("firebase_") or startswith("cloud_"))]
                  | length' .flutter-plugins-dependencies)
jq -r '.plugins.ios[] | select(.native_build) | "\(.name)\t\(.path)"' .flutter-plugins-dependencies \
  | while IFS=$'\t' read -r n p; do
      f="${p}ios/$n/Package.swift"; [ -f "$f" ] || f="${p}darwin/$n/Package.swift"
      [ -f "$f" ] && grep -h '^let firebaseSdkVersion' "$f"
    done | sort | uniq -c
echo "기대 FlutterFire 플러그인 수: $EXPECTED"
```

- **합격 기준: 선언 줄이 정확히 1줄이고, 그 줄의 맨 앞 개수가 `$EXPECTED` 와 같다.**
  현재 킷의 실제 출력은 아래 2줄이다.
  ```
     8 let firebaseSdkVersion: Version = "12.19.0"
  기대 FlutterFire 플러그인 수: 8
  ```
- **개수가 `$EXPECTED` 보다 작으면 합격이 아니다.** 이 명령은 플러그인마다
  `<path>ios/<name>/Package.swift` 와 `<path>darwin/<name>/Package.swift` **두 경로만**
  본다. 어느 쪽에도 없는 플러그인은 **조용히 건너뛴다** — 8개 중 3개만 읽혀도 출력은
  여전히 1줄이라, 「1줄」 조건만으로는 **읽히지 않은 플러그인이 다른 값을 선언하고
  있어도 통과한다.** 이 명령의 존재 이유가 바로 그 값 불일치 검출이므로, 표본이
  빠지면 검출력이 그만큼 조용히 줄어든다. 그래서 「1줄」 과 「개수 = `$EXPECTED`」 를
  **함께** 본다.
- **0줄이면 합격이 아니라 공허한 통과다** — 플러그인을 하나도 읽지 못한 것이다
  (`pub get` 미실행, 또는 `.flutter-plugins-dependencies` 의 구조가 바뀌었다).
  그래서 `sort -u` 가 아니라 `sort | uniq -c` 로 **개수까지 함께** 본다. 0줄은 위
  개수 대조에도 걸리지만 원인이 다르므로 따로 적는다.
- `$EXPECTED` 는 `firebase_` · `cloud_` **접두사**로 센다. 이 접두사를 쓰지 않는
  FlutterFire 플러그인을 넣거나, `firebaseSdkVersion` 을 선언하지 않는 `firebase_*`
  플러그인이 생기면 개수가 어긋난다 — 둘 다 **시끄럽게 실패하는 방향**이므로
  그때 필터를 함께 고친다.
- **2줄 이상이면 충돌이다.** 킷이 쓰는 `firebase_core` 4.15.0 은 firebase-ios-sdk 를
  `exact: firebaseSdkVersion` 으로 고정하므로, 값이 갈리면 `exact` ↔ `exact` 충돌로
  **해석 단계에서 즉시 실패**한다.
  - **버전 조건:** 이 `exact` 서술은 현재 세대 기준이다. 옛 FlutterFire
    (`firebase_core` **4.7.0 이하**)는 식별자부터 다르고(`firebase_sdk_version`)
    `from:` 으로 건다 — 위 명령의 `^let firebaseSdkVersion` 패턴이 잡지 못한다.
    - **「충돌하지도 않는다」 는 조건부로만 참이다.** `from: X` 와 `exact: Y` 는
      **`Y >= X` 일 때만** 함께 해석된다. 옛 세대가 새 세대보다 **높은 하한**을
      걸고 있으면(예: `from: 13.0.0` vs `exact: 12.19.0`) 해석이 실패한다 —
      즉 **이 명령이 잡지 못하는 충돌이 존재한다.** 두 세대를 섞게 되면 옛 쪽
      선언을 직접 읽어 값을 비교할 것.
      ```bash
      grep -n -e '^let firebase_sdk_version' -e '^let firebaseSdkVersion' \
        "$(jq -r '.plugins.ios[] | select(.name=="firebase_core") | .path' .flutter-plugins-dependencies)ios/firebase_core/Package.swift"
      ```
      `.pub-cache` 원문으로 보면 `firebase_core` **4.7.0** 은
      `let firebase_sdk_version: Version = "12.12.0"` + `from:`,
      **4.15.0** 은 `let firebaseSdkVersion: Version = "12.19.0"` + `exact:` 다.
- ⚠ `grep -h 'firebaseSdkVersion' ~/.pub-cache/…/Package.swift | sort -u` 형태로
  pub-cache 를 직접 훑지 말 것. 패턴이 **선언 줄과 사용 줄 양쪽**에 매칭돼 정상
  트리에서도 2줄이 나오고(정상 상태를 충돌로 오판한다), 해석되지 않은 옛 버전까지
  함께 읽는다.

**최종 판정은 iOS 빌드다.** 위 세 검사는 사전 선별일 뿐이고, 전이 의존성의 하한 문제는
실제 빌드에서만 드러난다.

### ④ SPM 을 지원하지 않는 플러그인을 넣으면 생기는 일

Flutter 는 **에러가 아니라 경고**를 내고 CocoaPods 로 되돌아간다. 빌드 로그의 문구는
다음과 같다.

```
The following plugins do not support Swift Package Manager for ios: <플러그인 이름>
```

이어서 일어나는 일:

1. **`ios/Podfile` 이 조용히 재생성된다** — 그리고 **빌드는 성공할 수도 있다.** 이것이
   이 절이 존재하는 이유다(조용한 실패).
2. 도구가 되돌리는 xcconfig 는 **`ios/Flutter/Debug.xcconfig` · `ios/Flutter/Release.xcconfig`
   두 개뿐**이다. 나머지 flavor xcconfig 9개는 복구되지 않아 **flavor 빌드만 링크 에러**가
   날 수 있다.
3. **`ios/Podfile` 이 없어야 한다는 시험이 실패한다** — `fvm flutter test` 가 이
   이유로 red 면 위 1·2 가 이미 벌어진 것이다.

**대응:** 그 플러그인의 SPM 지원 버전을 찾거나, 넣지 않는다. 재생성된 `ios/Podfile` 을
지우는 것만으로는 원인이 사라지지 않는다 — 다음 해석에서 다시 생긴다.

### ⑤ iOS 최소 배포 타겟을 바꾸려면

| 대상 | 값 | 비고 |
|---|---|---|
| `ios/Runner.xcodeproj/project.pbxproj` 의 `IPHONEOS_DEPLOYMENT_TARGET` | **12개** (현재 전부 15.6) | **유일한 진실원.** 12 build configuration 각각에 하나씩 있다 |

- Xcode 의 **PROJECT > Runner > Build Settings > iOS Deployment Target** 을 한 번 바꾸면
  12개가 함께 바뀐다. 손으로 고칠 때는 12개를 **전부 같은 값**으로 맞춘다 —
  `fvm flutter test` 가 「12개가 전부 같은 값」 을 강제한다.
- ⚠ **하한은 15.0 이다 — 그 아래로는 내릴 수 없다.** 같은 test 가 「12개 일치」와
  함께 **15.0 미만을 금지**한다(`_minSupportedIosTarget`). 14.0 으로 내리려 하면
  빌드가 아니라 `fvm flutter test` 가 먼저 red 가 된다.
  - 근거는 진실원의 복제가 아니라 **외부 의존이 부과하는 독립 제약**이다 —
    Flutter 3.47 이 지원하는 iOS 최소 버전이자 킷이 고정한 LineSDK 5.17.0 의
    `platforms` 하한이 둘 다 15.0 이다. 그래서 15.6 → 15.7 같은 정상 상향은
    그대로 통과한다.
  - 하한 자체를 올리거나 내리려면 test 의 `_minSupportedIosTarget` 과 이 bullet 을
    **함께** 고친다.
- Flutter 는 **빌드 때마다 이 값을 읽어** 자기가 생성하는 패키지의 `platforms` 를
  끌어올린다. CocoaPods 시절의 `post_install` 하한 보정 루프 같은 장치는 필요 없다.
- 의존 SDK 의 하한보다 **낮게** 내리면 SPM 이 빌드를 막는다(③ (나)).

### ⑥ 흔한 실수

SPM 빌드에서 **자주 겪는** 증상과, 킷이 **손으로 넣은 패치**의 취급을 적는다.

- **`project.pbxproj` 의 Crashlytics 업로드 단계는 upstream 템플릿에 없는 킷의 패치다.**
  `flutterfire_cli` 1.3.2 가 생성하는 원본은 DerivedData 경로 한 줄을 무조건
  대입하는데, Flutter 는 모든 iOS `xcodebuild` 호출에
  `-clonedSourcePackagesDirPath <project>/build/ios/SourcePackages` 를 붙이므로
  SPM checkout 은 **DerivedData 밑에 없다.** 그래서 킷은 이 단계에 Flutter 경로를
  먼저 보는 **probe 루프**와, 두 후보가 모두 없을 때 probe 한 경로를 찍으며
  `exit 1` 하는 분기가 들어 있다.
  - ⚠ **알려진 제약 — Xcode 를 직접 열어 빌드하면 stale `build/ios/SourcePackages`
    가 우선한다.** probe 순서(Flutter 경로 먼저)는 `fvm flutter build` ·
    `fvm flutter run` 경로에서만 옳다. **Xcode IDE 빌드에는
    `-clonedSourcePackagesDirPath` 가 붙지 않아** 권위 있는 checkout 은 DerivedData
    쪽인데, 직전 `flutter build` 가 남긴 **오래된** `build/ios/SourcePackages` 가
    있으면 후보 1이 먼저 히트해 **실제로 링크된 SDK 와 다른 버전의 업로드
    스크립트**가 쓰인다. 두 경로 모두 gitignored 빌드 산출물이라 버전이 갈라지는 것은
    흔한 상태다. `exit 1` 분기는 「둘 다 없음」만 막고 이 경우는 막지 못한다.
    - **순서를 자동으로 뒤집지 않는 이유:** 두 호출을 구분하는 build setting 이
      없다. `BUILD_DIR` 은 archive 가 아닐 때만 Flutter 가 덮어쓰고
      (`flutter_tools/lib/src/ios/mac.dart:426-427`), `-clonedSourcePackagesDirPath`
      는 archive 를 포함한 **모든** 호출에 붙는다(`:333-338` →
      `xcodeproj.dart:214-228`). 「DerivedData 쪽 checkout 이 존재하면 그쪽 우선」
      같은 조건은 Xcode 를 한 번이라도 연 머신에서 **`flutter build` 를 거꾸로
      망가뜨린다** — 같은 결함을 방향만 바꿔 옮기는 셈이다.
    - **대신 어느 후보를 골랐는지 빌드 로그에 남긴다.** 이 단계는
      `note: Crashlytics upload script = <경로>` 를 출력한다. Xcode 에서 직접 빌드한
      뒤 심볼이 엉뚱해 보이면 이 줄의 경로를 확인하고, `build/ios/SourcePackages` 를
      가리키고 있다면 그 디렉터리를 지운 뒤 다시 빌드한다(다음 `flutter build` 가
      다시 받는다).
  - **수동으로 `fff configure` 를 돌리면 이 build phase 가 upstream 모양으로
    재생성되어 패치가 조용히 사라진다.** 돌린 뒤에는 이 build phase 의 diff 를
    반드시 확인하고 복원할 것. `scripts/firebase-configure.sh` 경로는 이 파일을
    스냅샷·복원하므로 안전하다.
  - `fvm flutter test` 가 이 패치를 지킨다 — 패치가 사라지면 시험이 red 가 된다.
  - 빌드 로그에 `error: firebase-ios-sdk Crashlytics/run not found. Probed: …` 이
    찍히면 두 후보 경로가 모두 없다는 뜻이다. Xcode 의 build location 을
    custom/relative 로 바꿔 `BUILD_ROOT` 에 `DerivedData` 문자열이 없는 머신에서
    일어난다 — 한 번 `fvm flutter build ios` 를 돌려 `build/ios/SourcePackages` 를
    채우거나, build location 을 기본값으로 되돌린다.
- **SDK 버전을 고친 뒤 첫 빌드가 헤더 불일치로 실패한다** — 에러는
  `A precompiled file has been changed since last built. Please run "flutter clean"` 이고
  직전 줄이 `File '…/FBSDKCoreKit.framework/Headers/….h' has been modified since the module
  file '…/SwiftExplicitPrecompiledModules/….pcm' was built` 다. Xcode 의 explicit module
  캐시(`.pcm`)가 **옛 버전 헤더로** 만들어져 있어서 그렇다.
  - 도구가 권하는 `flutter clean` 을 그대로 따르지 말고 **에러가 지목한 그 프로젝트의
    DerivedData 디렉터리 하나만** 지운다. `flutter clean` 은 `build/ios/SourcePackages`
    (수백 MB)까지 함께 날린다. checkout 은 DerivedData 밑에 없다 — Flutter 가
    `-clonedSourcePackagesDirPath build/ios/SourcePackages` 를 붙이기 때문이다.
- **`Xcode build done` 은 성공 마커가 아니다** — `** BUILD FAILED **` 로 끝난 로그에도
  `Xcode build done. 84.1s` 가 찍힌다(Flutter 가 경과 시간 status 를 성패와 무관하게
  닫는다). 빌드 성패는 **`✓ Built` 와 종료 코드**로 판정한다.

## 테스트 돌리기

코드를 바꾼 뒤 · 커밋 전 · 킷 새 판을 받은 뒤에 돌린다. 명령은 저장소 루트에서 실행한다.

- **앱 전체 시험:** `fvm flutter test`. 생성 코드(`*.g.dart` · `*.freezed.dart`)가
  없으면(clone 직후 등) 먼저
  `fvm dart run build_runner build --delete-conflicting-outputs` 를 돌린다.
- **Cloud Functions 시험:** `cd functions && pnpm test`.
- **golden 이 실패하면:** `failures/` 의 비교 이미지를 보고, 의도한 변화일 때만 실패한
  golden 시험 파일 하나를 대상으로 `fvm flutter test --update-goldens <파일>` 로 기준
  이미지를 다시 만든다. 모든 시험에 한꺼번에 `--update-goldens` 를 쓰지 않는다.
- **커밋 전 검사:** format 검사 · `fvm flutter analyze` · `fvm dart analyze` ·
  `fvm flutter test` 넷이 오류 없이 끝나야 한다.

자세한 것(디렉터리 구조 · 이름 짓기 · 기능을 바꾸거나 지울 때 시험 다루기 · macOS 의
iOS 변형 golden)은 [테스트 안내](../test/README.md) 에 있다.

## 알아 둘 동작
