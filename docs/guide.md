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
