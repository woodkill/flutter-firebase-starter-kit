# 설정 위저드로 앱 준비하기

이 문서는 설정 위저드(`./setup.sh`)로 앱을 처음 준비하는 일 — 위저드 실행 · 로그인 수단 켜고 끄기 · 알림과 App Check · stg · prod 설정 — 을 다룬다. 위저드를 끝낸 뒤 앱을 바꾸고 출시하는 일은 [직접 하는 일](guide.md) 에 있다.

> 콘솔 언어를 한국어로 두면 화면의 라벨이 이 문서와 같다. 한국어 화면이 없는 콘솔(LINE 등)은 영어 라벨을 그대로 쓴다.

## 목차

1. [시작 전 준비](#시작-전-준비)
2. [위저드 실행](#위저드-실행)
3. [로그인 수단 켜기](#로그인-수단-켜기)
4. [알림(APNs) · App Check](#알림apns--app-check)
5. [stg · prod 설정](#stg--prod-설정)
6. [로그인 수단 끄기](#로그인-수단-끄기)
7. [위저드를 끝낸 뒤](#위저드를-끝낸-뒤)
8. [문제가 생기면](#문제가-생기면)

---

## 시작 전 준비

위저드를 처음 실행하기 전에 아래를 갖춘다.
- 개발 도구 대부분은 위저드가 확인하고 없으면 설치하므로, 사람이 미리 할 일은 계정 · 결제 수단 · Homebrew · Xcode 다.

**사람이 미리 갖출 것**

- **macOS 와 터미널 앱** — 위저드는 macOS 에서만 돈다.
  - 개발자 도구가 한 번도 설치되지 않은 Mac 에서는 처음 `git clone` 을 실행할 때 macOS 가 Command Line Tools 설치 창을 띄운다 — 「설치」 를 누르고 끝나면 같은 `git clone` 명령을 다시 실행한다.
- **Homebrew** — 없으면 `./setup.sh` 가 설치 명령을 보이고 끝난다.
  - 설치한 뒤 같은 명령을 다시 실행한다.
- **Xcode** — App Store 에서 설치한다.
  - 없으면 위저드의 「Xcode 준비」 단계가 App Store 주소를 보이고 끝난다.
  - 설치한 뒤 Xcode 를 한 번 열어 추가 구성 요소 설치를 마치고 `./setup.sh` 를 다시 실행한다.
  - Xcode 선택 · 라이선스 · 첫 실행 준비 · iOS 시뮬레이터 런타임은 위저드가 진행한다 — sudo 비밀번호는 그 명령이 직접 묻는다.
- **Google 계정** — Firebase · Google Cloud 에 로그인할 계정이다.
  - 처음 쓰는 계정이면 위저드 안내대로 약관에 동의한다([위저드 실행](#위저드-실행) 의 「사용자가 하는 일」).
- **조직(Google Workspace) 계정으로 만든 프로젝트** — 조직 정책 때문에 함수 빌드 계정의 역할과 공개 호출 예외가 더 필요할 수 있다.
  - 「Cloud Functions 배포」 단계가 막히면 원인과 명령을 보이고, 절차는 [조직 계정 프로젝트에서 함수 배포가 막히면](#조직-계정-프로젝트에서-함수-배포가-막히면) 에 있다.
- **결제 수단과 Blaze 요금제** — 위저드의 「결제 계정 (Blaze 요금제)」 단계가 열린 결제 계정을 골라 Firebase 프로젝트에 연결한다.
  - 연결하면 프로젝트가 Blaze(종량제) 요금제로 바뀌고, 무료 사용량을 넘는 사용분이 그 결제 계정으로 청구된다 — 쓴 만큼 낸다.
  - Cloud Functions 배포에 Blaze 가 필요하다.
  - 요금은 [Firebase 가격 안내](https://firebase.google.com/pricing) 에서 확인한다.
  - 열린 결제 계정이 없으면 위저드가 브라우저에서 결제 계정을 만든 뒤 Enter 를 누르라고 안내한다.
- **Apple Developer 계정** — Apple 로그인 · APNs(푸시 알림) · DeviceCheck · iOS 실기기 서명에 쓴다.
  - Apple 로그인과 DeviceCheck 에는 Apple Developer 에서 만든 `.p8` 키가 필요하다.
- **켤 로그인 수단의 개발자 콘솔 계정** — Facebook · Kakao · Naver · LINE 은 그 회사의 개발자 콘솔에 앱을 등록한다.
  - Google 은 Google 계정, Apple 은 Apple Developer 계정을 그대로 쓴다.
  - 수단마다 필요한 것은 [켜는 순서와 수단별로 필요한 것](#켜는-순서와-수단별로-필요한-것) 에 있다.

**위저드가 확인하고 없으면 설치하는 것**

- **FVM 과 Flutter** — `setup.sh` 가 위저드를 띄우기 전에 FVM · `.fvmrc` 가 고정한 Flutter 판 · 패키지를 확인한다.
  - FVM 이 없으면 설치 명령을 보이고 `y` 를 받았을 때만 설치한다.
- **개발 도구** — 「개발 도구」 단계가 Node(22 이상) · pnpm(10 이상) · Firebase CLI(15 이상) · gcloud · jq · ruby 의 xcodeproj · FlutterFire CLI 를 확인한다.
  - 있으면 어디서 설치했든 그대로 쓰고, 없거나 판이 낮은 것만 설치 명령을 보인 뒤 확인을 받고 하나씩 설치한다 — Homebrew 로 설치하고, FlutterFire CLI 는 `fvm dart pub global activate` 로 설치한다.
  - Functions 의존성(`pnpm -C functions install --frozen-lockfile`)은 「Cloud Functions 배포」 단계가 설치한다.

**Android 도구 · JDK**

- 위저드의 「앱 실행 · 로그인 확인」 단계는 iOS 시뮬레이터를 기본으로 앱을 띄운다.
  - Android 기기나 에뮬레이터에서 돌리려면 Android 도구(Android SDK · 에뮬레이터)를 직접 설치한다 — 위저드는 Android 도구를 설치하지 않는다.
- JDK 는 Android 디버그 서명 키의 지문(SHA-1 · 키 해시)을 계산하는 데 쓰인다 — Google · Facebook · Kakao · LINE 콘솔에 넣는 Android 쪽 값이다.
  - JDK 나 디버그 서명 키가 없으면 위저드는 지문 줄만 미루고 뒤 단계는 그대로 진행한다.
  - 이때 `Android 도구(JDK)와 디버그 서명 키가 없어 지문을 계산하지 못했습니다 — Android 도구를 설치하고 Android 빌드를 한 번 한 뒤 ./setup.sh 를 다시 실행하면 지문을 보여 줍니다` 가 보인다.
- Firestore · Storage rules 시험(`functions/` 에서 `pnpm test:rules`)이 쓰는 Firebase 에뮬레이터도 JDK 가 있어야 돈다.

## 위저드 실행

> **처음 설정은 저장소 루트에서 `./setup.sh` 하나로 한다 — 설정 위저드가 단계를 차례로 진행하고, 사람만 할 수 있는 일은 그 자리에서 안내한다.**

위저드는 macOS 에서만 돈다.
- 먼저 [시작 전 준비](#시작-전-준비) 의 계정 · 도구를 갖춘다.
- template 로 만든 앱 저장소(또는 킷 clone)를 받은 직후 저장소 루트에서 실행한다.

**명령**

```bash
# dev flavor 처음 설정 — flavor 를 주지 않으면 dev 다
./setup.sh

# 로그인 수단 체크 목록을 열어 켜고 끌 수단을 고른다
./setup.sh --providers

# stg · prod 설정 — 그 flavor 의 Firebase 프로젝트에 같은 흐름을 적용한다
./setup.sh --flavor stg
./setup.sh --flavor prod

# 사용법 보기
./setup.sh --help
```

| 옵션 | 하는 일 |
|---|---|
| (없음) | dev flavor 를 준비한다 |
| `--providers` | 로그인 수단 체크 목록을 연다 — 켠 수단의 단계가 이어서 돈다([로그인 수단 켜기](#로그인-수단-켜기)) |
| `--flavor <dev\|stg\|prod>` | 그 flavor 의 Firebase 프로젝트에 같은 흐름을 적용한다 — 기본값은 `dev` 다([stg · prod 설정](#stg--prod-설정)) |
| `--help` (`-h`) | 사용법을 보인다 |

`setup.sh` 는 위저드를 띄우기 전에 Homebrew · FVM · `.fvmrc` 가 고정한 Flutter 판 · 패키지를 확인한다.
- Homebrew 가 없으면 설치 명령을 보이고 끝난다 — 설치한 뒤 같은 명령을 다시 실행한다.
- FVM 이 없으면 설치 명령을 보이고 `y` 를 받았을 때만 설치한다.

**단계 목록**

위저드는 아래 순서로 단계를 검사하고, 끝나지 않은 단계만 진행한다. 「단계」 칸은 위저드 화면의 단계 제목이다. 조건이 붙은 단계는 그 조건일 때만 목록에 든다.

| # | 단계 | 언제 도는가 |
|---|---|---|
| 1 | Xcode 준비 | 항상 |
| 2 | 개발 도구 | 항상 |
| 3 | 사용자 설정 파일 | 항상 |
| 4 | 앱 정체성 | 항상 |
| 5 | Firebase · Google Cloud 로그인 | 항상 |
| 6 | Firebase 프로젝트 | 항상 |
| 7 | 결제 계정 (Blaze 요금제) | 항상 |
| 8 | 필요한 Google Cloud API | 항상 |
| 9 | 위치 · Firestore | 항상 |
| 10 | 기본 Storage bucket | 항상 |
| 11 | 로그인 수단 (이메일 · 익명) | 항상 |
| 12 | 로그인 수단 | 항상 — `--providers` 로 실행하면 체크 목록을 연다 |
| 13 | 앱 아이콘 | 콘솔에 앱 아이콘 칸이 있는 수단(Naver · Kakao · LINE · Facebook · Google)을 켰을 때 |
| 14 | Google 로그인 | Google 을 켰을 때 |
| 15 | 앱 등록 · 설정 파일 | 항상 |
| 16 | Google — iOS 쪽 | Google 을 켰을 때 |
| 17 | Google — Android 쪽 | Google 을 켰을 때 |
| 18 | Firestore · Storage rules | 항상 |
| 19 | App Check 디버그 토큰 | 항상 |
| 20 | Apple 로그인 — iOS 쪽 | Apple 을 켰을 때 |
| 21 | Apple 로그인 — Android 쪽 | Apple 을 켰을 때 |
| 22 | Facebook 로그인 | Facebook 을 켰을 때 |
| 23 | Facebook — Android 쪽 | Facebook 을 켰을 때 |
| 24 | Kakao 로그인 | Kakao 를 켰을 때 |
| 25 | Kakao — Android 쪽 | Kakao 를 켰을 때 |
| 26 | Naver 로그인 | Naver 를 켰을 때 |
| 27 | Naver — Android 쪽 | Naver 를 켰을 때 |
| 28 | LINE 로그인 | LINE 을 켰을 때 |
| 29 | LINE — Android 쪽 | LINE 을 켰을 때 |
| 30 | Cloud Functions 배포 | 항상 |
| 31 | Custom Token 서명 권한 | Kakao · Naver · LINE 가운데 하나라도 켰을 때 |
| 32 | 앱 실행 · 로그인 확인 | 항상 |
| 33 | 소셜 로그인 확인 | 소셜 로그인 수단을 하나라도 켰을 때 |
| 34 | App Check — Play Integrity | 항상 — 출시용 단계(미룰 수 있다) |
| 35 | App Check — DeviceCheck | 항상 — 출시용 단계(미룰 수 있다) |
| 36 | APNs 키 | 항상 — 출시용 단계(미룰 수 있다) |

**위저드가 하는 일**

위저드는 개발 도구를 확인하고, 없는 도구는 확인을 받은 뒤 설치한다.
- 이어서 Xcode 를 준비하고, 앱 정체성을 정하고, CLI 에 로그인하고, Firebase 프로젝트를 만들거나 고르고, 결제 계정을 연결한다.
- Firestore · 기본 Storage bucket · 이메일 로그인 · 익명 로그인을 켜고, 앱을 등록해 설정 파일을 만들고, rules 를 배포하고, App Check 디버그 토큰을 등록하고, Cloud Functions 를 배포한다.
- 이어서 코드를 생성하고 dev flavor 앱을 실행해 로그인을 확인한다.
- 끝으로 출시용 단계 — App Check 의 Play Integrity · DeviceCheck 등록과 APNs 키 업로드 안내 — 를 진행한다.
- 출시용 단계는 「지금 안 함」 으로 미룰 수 있다.

`./setup.sh --providers` 로 수단을 켜면, 켠 수단마다 provider 콘솔에 넣을 값을 보여 주고, 콘솔에서 받은 키를 한 번 입력받아 설정에 기록한 뒤 함수를 배포하고, 앱에서 그 수단으로 로그인했는지 확인한다.
- 위저드가 채우는 설정 키는 [위저드가 채우는 설정 키](#위저드가-채우는-설정-키) 에 있다.
- 뺀 수단은 가입자 수를 세어, 가입자가 있으면 목록을 바꾸지 않고 Remote Config 로 버튼만 숨기는 방법을 안내한다([로그인 수단 끄기](#로그인-수단-끄기)).

- 위저드가 실행하는 명령은 화면에 그대로 보인다.
- 비용이 들거나 되돌릴 수 없는 선택은 값 표를 보여 주고 `y` 를 받은 뒤에만 진행한다.

**사용자가 하는 일**

- 처음 `git clone` 때 macOS 가 띄우는 Command Line Tools 설치 창을 확인한다.
- 브라우저에서 로그인한다.
  - 처음 쓰는 Google 계정이면 위저드 안내대로 Google Cloud 콘솔에서 Google Cloud 약관에, Firebase 콘솔에서 프로젝트에 Firebase 를 추가하며 Firebase 약관에 동의한다.
  - 애널리틱스를 켜 두면 같은 흐름에서 Google 애널리틱스 약관에도 동의한다.
- 결제 수단을 등록하고, Homebrew 와 Xcode 를 설치한다.
  - sudo 비밀번호는 Xcode 준비 명령이 직접 묻는다 — 위저드는 비밀번호를 받지 않는다.
- 그 밖에는 위저드 질문에 답하고, 실행된 앱에서 가입한 뒤 인증 메일의 링크를 연다.
- 로그인 수단을 켜면 그 provider 의 개발자 콘솔에 앱을 등록하고 위저드가 보여 주는 값을 넣은 뒤 키를 받아 온다.
- Apple 로그인과 DeviceCheck 에는 Apple Developer 에서 만든 `.p8` 키를, Apple 로그인에는 Services ID 도 준비한다.
  - APNs 키는 Firebase 콘솔에 직접 올린다([알림(APNs) · App Check](#알림apns--app-check)).
- prod 의 Play Integrity 에는 Play 에 앱을 올린 뒤 Play 앱 서명 키의 SHA-256 을 입력한다.

**앱 아이콘 단계**

켠 수단 가운데 콘솔에 앱 아이콘 칸이 있는 수단(Naver · Kakao · LINE · Facebook · Google)이 있으면 위저드가 원본 이미지 경로를 묻는다.

1. 정사각 · 1024x1024 이상 이미지 하나를 준비한다(PNG · JPEG · HEIC 등 — PDF · SVG 같은 벡터는 받지 않는다).
2. 위저드가 경로를 물으면 Finder 에서 그 파일을 터미널 창으로 끌어다 놓는다 — 경로가 입력된다.
   - 빈 값으로 답하면 「지금 안 함」 으로 미룬다.
   - 정사각이 아니거나 작은 이미지는 까닭을 보이고 경로를 다시 묻는다.
3. 위저드가 provider 마다 콘솔 규격의 PNG 를 `.setup/icons/` 에 만들고 그 폴더를 Finder 로 연 뒤, provider 의 값 표에 파일 경로를 보인다.
4. provider 콘솔의 파일 선택 창에서 ⌘⇧G 로 `provider 콘솔에 올릴 앱 아이콘` 표 끝 줄이 보이는 `.setup/icons` 전체 경로를 붙여 넣거나, 열린 Finder 창에서 파일을 끌어다 놓아 올린다.
   - 그 경로는 저장소의 절대 경로라 파일 선택 창이 어느 폴더를 열고 있어도 그 폴더로 간다.
   - Naver 는 로고가 없으면 콘솔에서 앱이 저장되지 않는다.

아이콘을 바꾸려면 `.setup/icons` 를 지우고 위저드를 다시 실행한다.

**중단 · 다시 실행 · 실행 기록**

- 언제든 Ctrl-C 로 끝낼 수 있다.
  - 터미널 상태는 `setup.sh` 가 되돌린다.
- 단계가 실패하면 「다시 시도」 와 「멈춤」 가운데 고른다.
  - 멈추거나 끝낸 뒤에는 같은 명령을 다시 실행하면 이어진다.
- 위저드 밖에서 할 일(콘솔 작업 · 도구 설치 등)을 안내하고 끝났으면, 그 일을 마친 뒤 `./setup.sh` 를 다시 실행한다.
- 다시 실행하면 끝난 단계는 검사만 하고 건너뛰고, 킷 새 판에서 생긴 config 키를 채운다.
- 실행 기록은 실행마다 `.setup/logs/` 에 파일 하나로 남는다 — 화면 출력 · 입력한 답 · 실행한 명령 · 종료 코드 · 명령 출력 · REST 요청과 응답 · 단계 검사 판정이 들고, 비밀 값은 가린 채 남는다.
  - 폴더와 파일은 소유자만 열 수 있고, `.setup/` 은 `.gitignore` 에 들어 있어 저장소에 커밋되지 않는다.
- 할 수 있는 단계를 모두 지나면, 미룬 일과 위저드가 확인할 수 없는 일이 「release 빌드 전에 끝내야 할 일」 목록으로 보인다.
- 끝에 위저드가 바꾼 추적 파일 목록과 커밋 명령을 보인다.
  - 위저드는 스테이징 · 커밋 · push 를 하지 않는다 — 목록을 확인한 뒤 직접 커밋한다.
  - 다음에 할 일은 [위저드를 끝낸 뒤](#위저드를-끝낸-뒤) 에 있다.

### 위저드가 채우는 설정 키

위저드는 `config/<flavor>.json`(dev 면 `config/dev.json`)을 example 파일에서 만들고 아래 키를 채운다.
- 손으로 고칠 일은 드물고, 킷 새 판에서 키가 늘면 위저드를 다시 실행해 채운다.

| 키 | 값 출처 | off 면 비워도 됨 | 비고 |
|----|---------|------------------|------|
| `appName` | 앱 표시 이름 — example 값 `StarterKit Dev` | 아니요 | flavor 마다 다르게 둔다. Android 에서는 Naver 동의 화면의 앱 이름으로도 쓰인다. 따옴표 같은 특수문자는 피하고 영숫자 · 공백만 쓴다 |
| `appSuffix` | ApplicationId · Bundle ID 접미사 — example 값 `.dev` | 아니요 | flavor 마다 앱을 따로 설치하고 Firebase 앱을 나누는 데 쓴다 |
| `firebaseProjectId` | Firebase Console → 프로젝트 설정 → 일반 | 아니요 | 본인 Firebase 프로젝트 ID. 함수 배포 스크립트도 이 값으로 배포할 프로젝트를 정한다 |
| `firebaseWebApiKey` | **웹 API 키** — Google Cloud Console → API 및 서비스(APIs & Services) → 사용자 인증 정보(Credentials) 의 「API 키」 표에서 `Browser key (auto created by Firebase)` 의 「키 표시」 | `emailDelivery` 가 `kit` 이 아니면 예 | `kit` 발송 모드의 결과 페이지가 이 키로 Firebase Authentication 을 부른다. `AIza` 로 시작하는 값이다. Android · iOS 앱 전용으로 제한한 키는 브라우저에서 거부되고, 웹사이트(HTTP 리퍼러) 제한이 걸린 키도 이 페이지에서 거부된다(페이지가 Referer 를 보내지 않는다). 애플리케이션 제한사항이 「없음」 인 키(Firebase 가 만든 Browser key 기본값)를 쓴다. 결과 페이지 빌드는 이 값이 비었거나 자리표시 값이면 `FAIL:` 로 멈춘다 |
| `googleServerClientId` | Google Cloud Console → API 및 서비스(APIs & Services) → 사용자 인증 정보(Credentials) → OAuth 2.0 Client IDs → **Web application** | Google 을 끄면 예 | Firebase 가 만든 OAuth Web Client ID. iOS · Android 용이 아니라 Web 용을 쓴다 |
| `facebookAppId` | [Facebook 로그인 켜기](#facebook-로그인-켜기) 의 콘솔 단계 | Facebook 을 끄면 예 | 숫자 문자열. iOS 는 xcconfig `FACEBOOK_APP_ID` 에 같은 값 |
| `facebookClientToken` | [Facebook 로그인 켜기](#facebook-로그인-켜기) 의 콘솔 단계 | Facebook 을 끄면 예 | iOS 는 xcconfig `FACEBOOK_CLIENT_TOKEN` 에 같은 값 |
| `kakaoNativeAppKey` | [Kakao 로그인 켜기](#kakao-로그인-켜기) 의 콘솔 단계 | Kakao 를 끄면 예 | REST API 키가 아니다. iOS 는 xcconfig `KAKAO_NATIVE_APP_KEY` 에 같은 값. OIDC 활성화는 [Kakao 로그인 켜기](#kakao-로그인-켜기) 에서 한다 |
| `naverClientId` | [Naver 로그인 켜기](#naver-로그인-켜기) 의 콘솔 단계 | Naver 를 끄면 예 | iOS 는 xcconfig `NAVER_CLIENT_ID` 에 같은 값. 다르면 1-tap 과 웹 로그인이 서로 다른 앱으로 로그인한다 |
| `naverClientSecret` | [Naver 로그인 켜기](#naver-로그인-켜기) 의 콘솔 단계 | Naver 를 끄면 예 | iOS 는 xcconfig `NAVER_CLIENT_SECRET` 에 같은 값. Secret Manager 의 `NAVER_CLIENT_SECRET` 과도 같은 값이다 |
| `naverUrlScheme` | [Naver 로그인 켜기](#naver-로그인-켜기) 의 콘솔 단계 | Naver 를 끄면 예 | iOS 는 xcconfig `NAVER_URL_SCHEME` 에 같은 값. 웹 로그인의 콜백 scheme 으로도 쓰이므로 소문자 영숫자여야 한다 |
| `lineChannelId` | [LINE 로그인 켜기](#line-로그인-켜기) 의 콘솔 단계 | LINE 을 끄면 예 | iOS 는 xcconfig `LINE_CHANNEL_ID` 에 같은 값. Secret Manager 의 `LINE_CHANNEL_ID` 와도 같은 값이다 |
| `functionsRegion` | Cloud Functions 리전 — example 값 `asia-northeast3` | 아니요 | 바꿀 때는 `functions/src/shared/region.ts` 의 `REGION` 도 함께 바꾼다([stg · prod 설정](#stg--prod-설정)) |
| `splashMinDurationMs` | 스플래시 최소 노출 시간(ms) — example 값 `2000` | 아니요 | 첫 화면 전환 시점 조정용 |
| `enabledAuthProviders` | 로그인 화면에 켤 소셜 로그인 — 쉼표로 구분 | — (켤 provider 목록 · 비우면 소셜 0개 = 기본값) | example 값이 빈 문자열이라 clone 직후 로그인 화면에는 「이메일로 계속」 만 보인다. 값은 빌드 때 들어가므로 바꾼 뒤 다시 빌드한다 |
| `brandColor` | 앱 · 결과 페이지 · 메일의 브랜드 색 — `#RRGGBB`, example 값 `#673AB7` | 아니요 | 비우거나 형식이 틀리면 `#673AB7` 로 동작한다. 앱은 이 색을 seed 로 Material 3 색을 계산하고 결과 페이지 · 메일은 이 색을 그대로 칠한다. 바꾼 뒤 다시 빌드한다 |
| `emailDelivery` | 인증 · 재설정 메일을 보내는 쪽 — `firebase` 또는 `kit` | — (비우면 `firebase` = 기본값) | 기본값은 Firebase 가 보내고 추가 설정이 없다. `kit` 은 발송 서비스 · 확장 설정이 필요하다. 그 밖의 값은 배포 스크립트가 거부한다 |
| `appCheckDebugToken` | debug 빌드의 App Check 디버그 토큰 — `./setup.sh` 가 만들어 넣고 Firebase 의 iOS · Android 앱에 등록한다. example 값은 빈 문자열 | 예 | 비우면 앱이 실행될 때 토큰을 만들어 로그에 출력한다 — 그 토큰을 Firebase Console 의 App Check 에 등록해야 회원탈퇴 같은 보호된 기능이 동작한다. release 빌드는 이 값을 쓰지 않는다. 다른 키처럼 저장소에 올리지 않는다 |

끈 provider 의 키는 비워 둬도 된다 — 무엇을 켤 때 무엇이 필요한지는 [로그인 수단 켜기](#로그인-수단-켜기).

키 하나하나의 자세한 뜻과 쓰는 곳은 [config/README.md](../config/README.md) 에 있다.

## 로그인 수단 켜기

> **로그인 수단은 저장소 루트에서 `./setup.sh --providers` 로 켠다 — 설정 위저드가 체크 목록을 열고, 수단마다 콘솔에 넣을 값을 보여 준 뒤 키를 받아 기록하고 배포한다.**

clone 직후 기본값은 소셜 로그인 0개라 로그인 화면에는 「이메일로 계속」 과 가입 링크만 보인다.
- 켠 수단만 provider 콘솔 등록과 키가 필요하고, 끈 수단은 콘솔 등록 · 키 · 함수가 필요 없다.
- 이 절은 수단마다 콘솔에서 할 일을 위저드 값 표의 행 이름과 이어서 적는다.

### 켜는 순서와 수단별로 필요한 것

**전제**

- [위저드 실행](#위저드-실행) 으로 그 flavor 의 처음 설정이 끝나 있다.
- 켤 수단의 개발자 콘솔 계정이 있다([시작 전 준비](#시작-전-준비)).

**위저드 흐름**

1. 저장소 루트에서 체크 목록을 연다.
   - stg · prod 는 `--flavor stg` · `--flavor prod` 를 함께 준다.

   ```bash
   ./setup.sh --providers
   ```

2. 위저드가 `로그인 수단 — 이메일 로그인은 늘 켜져 있습니다` 아래에 번호 목록을 보인다.
   - 번호를 묻는 질문에 **켤 수단과 이미 켜 둔 수단의 번호**를 띄어 써서 입력한다 — 넣지 않은 번호의 수단은 꺼진다.
3. 위저드가 「지금 · 새 값 · 더한 것 · 기록」 값 표를 보이고, `y` 를 받은 뒤 `config/<flavor>.json` 의 `enabledAuthProviders` 에 켠 수단을 더한다.
   - 이어서 단계 목록을 다시 짜고 켠 수단의 단계를 진행한다.
   - 콘솔에 앱 아이콘 칸이 있는 수단을 켰으면 먼저 「앱 아이콘」 단계가 원본 이미지를 묻는다([위저드 실행](#위저드-실행) 의 「앱 아이콘 단계」).
4. 수단마다 위저드가 `<수단> 콘솔에 넣을 값 — <flavor>` 값 표를 보인다.
   - 콘솔에 넣을 값(패키지명 · 번들 ID · 키 해시 · 리디렉션 주소 등)과 콘솔 주소(`콘솔:` 줄) · 할 일 줄이 든다.
5. 값 표를 보며 그 provider 콘솔에서 앱을 등록하고 값을 넣는다 — 수단별 콘솔 단계는 아래 하위 절에 있다.
   - 위저드가 `콘솔에서 키를 받았나요?` 를 물으면 키를 받았을 때 `네 — 키를 입력합니다` 를, 콘솔 작업이 남았으면 `아니요 — 끝내고 콘솔 작업 뒤 다시 실행` 을 고른다.
6. 콘솔에서 받은 키를 한 번 입력한다.
   - 비밀 값은 화면에 보이지 않게 받고, 위저드가 형식 · 서버 확인 뒤에 `config/<flavor>.json` · `ios/Flutter/<flavor>.xcconfig` · Secret Manager 에 기록하고, Apple · Facebook 은 Firebase 로그인 설정에도 기록한다.
   - Google 은 입력할 키가 없다 — 위저드가 Firebase 에서 Google 로그인을 켜고 Web client ID 를 읽어 기록한다.
7. 「Cloud Functions 배포」 단계가 공통 함수와 켠 수단의 함수를 배포하고, 앱에서 부를 수 있게 공개 호출이 설정돼 있는지 확인한다.
   - 공개 호출은 앱이 부르는 함수(`onCall` · `onRequest`)만 확인하고, Auth · Firestore · 스케줄 같은 백그라운드 함수는 배포됐는지만 본다.
8. Kakao · Naver · LINE 가운데 하나라도 켰으면 「Custom Token 서명 권한」 단계가 함수 서비스 계정의 토큰 서명 권한을 확인하고 없으면 붙인다([Kakao · Naver · LINE 서명 권한(Token Creator)](#kakao--naver--line-서명-권한token-creator)).
9. 「앱 실행 · 로그인 확인」 단계가 앱을 다시 빌드해 띄우고, 「소셜 로그인 확인」 단계가 켠 수단마다 로그인한 사용자 수를 센다.
   - 앱에서 켠 수단으로 한 번씩 로그인한다.

**수단별로 필요한 것**

아래 표의 config 키 · xcconfig 변수 · secret 은 위저드가 채우고, Cloud Functions 는 위저드가 배포한다. 사람이 할 일은 「콘솔 단계」 칸의 절이다.

| 수단 | `enabledAuthProviders` 토큰 | config 키 | xcconfig 변수 | Cloud Functions | secret | 콘솔 단계 |
|------|-----------------------------|-----------|---------------|-----------------|--------|-----------|
| Google | `google` | `googleServerClientId` | `REVERSED_CLIENT_ID` | 없음 | 없음 | [Google 로그인 켜기](#google-로그인-켜기) |
| Apple | `apple` | 없음 | 없음 | 없음 | 없음 | [Apple 로그인 켜기](#apple-로그인-켜기) |
| Facebook | `facebook` | `facebookAppId` · `facebookClientToken` | `FACEBOOK_APP_ID` · `FACEBOOK_CLIENT_TOKEN` | `disconnectFacebookProvider` | `FACEBOOK_APP_ID` · `FACEBOOK_APP_SECRET` | [Facebook 로그인 켜기](#facebook-로그인-켜기) |
| Kakao | `kakao` | `kakaoNativeAppKey` | `KAKAO_NATIVE_APP_KEY` | `kakaoCustomToken` · `linkKakaoProvider` · `disconnectKakaoProvider` | `KAKAO_NATIVE_APP_KEY` · `KAKAO_ADMIN_KEY` | [Kakao 로그인 켜기](#kakao-로그인-켜기) |
| Naver | `naver` | `naverClientId` · `naverClientSecret` · `naverUrlScheme` | `NAVER_CLIENT_ID` · `NAVER_CLIENT_SECRET` · `NAVER_URL_SCHEME` | `naverCustomToken` · `naverWebCustomToken` · `linkNaverProvider` · `disconnectNaverProvider` | `NAVER_CLIENT_ID` · `NAVER_CLIENT_SECRET` | [Naver 로그인 켜기](#naver-로그인-켜기) |
| LINE | `line` | `lineChannelId` | `LINE_CHANNEL_ID` | `lineCustomToken` · `linkLineProvider` · `disconnectLineProvider` | `LINE_CHANNEL_ID` · `LINE_CHANNEL_SECRET` | [LINE 로그인 켜기](#line-로그인-켜기) |

공통 함수(`ping` · `unlinkCustomTokenProvider` · `deleteUserAccount` · `lookupSignInMethods` · `mirrorAccountEmail` · `sendTestPush`)는 수단과 무관하게 늘 배포된다.
- 콘솔에 등록할 때 그 수단이 이메일을 주도록 함께 설정한다 — 수단별 설정은 [로그인 수단에서 이메일 받기](#로그인-수단에서-이메일-받기) 에 있다.

provider 를 킷에 더하거나 빼는 일은 유지보수자 작업이라 이 문서에 절차가 없다 — 그 절차와 설계 이유는 [유지보수자 문서](maintainer/custom-token-provider-add-remove.md) 에 있다.

#### 확인 방법

- 앱을 다시 빌드해 실행하면 로그인 화면에 켠 수단의 버튼이 보이고, 소셜 버튼 아래에 「또는」 구분선이 나타난다.
- 위저드의 「소셜 로그인 확인」 단계가 켠 수단마다 `Google 1명` 꼴로 1명 이상을 세고 끝난다.
- `./setup.sh` 를 다시 실행하면 점검표의 「로그인 수단」 줄이 켠 수단을 보인다(예: `이메일 + Google · 바꾸기: ./setup.sh --providers`).

#### 문제 해결

- **켠 수단의 버튼이 로그인 화면에 없다.**
  - `enabledAuthProviders` 는 빌드 때 앱에 들어가므로 앱을 다시 빌드한다.
  - Remote Config 의 `auth_provider_<토큰>_enabled` 가 `false` 로 게시돼 있지 않은지도 본다([Kill Switch 로 로그인 수단 막기](guide.md#kill-switch-로-로그인-수단-막기)).
- **버튼을 누르면 오류 배너가 뜬다.**
  - 그 수단의 secret 이 자리표시 값 `unset` 으로 남아 있는지 [secret 값 확인하기](#secret-값-확인하기) 로 확인한다.
  - 값 표의 값을 콘솔에 모두 넣었는지 수단별 콘솔 단계도 다시 본다.
- **Kakao · Naver · LINE 로그인이 오류 배너로 끝나거나, Naver · LINE 의 연결 해제 · 회원탈퇴가 오류로 끝난다.**
  - 함수 로그(Cloud Logging)에 `auth/insufficient-permission` 이 있으면 함수의 서비스 계정에 토큰 서명 권한이 없는 것이다 — [Kakao · Naver · LINE 서명 권한(Token Creator)](#kakao--naver--line-서명-권한token-creator) 으로 확인하고 붙인다.
- **「소셜 로그인 확인」 이 `아직 로그인 기록이 없습니다:` 뒤에 수단 이름을 보인다.**
  - 그 수단으로 로그인한 기록이 아직 없다.
  - `앱을 다시 실행` 을 고르면 앱이 다시 뜨고, 그 수단으로 로그인한 뒤 `q` 로 끝내면 위저드가 다시 센다.
  - Kakao · Naver · LINE 은 다른 수단으로 가입한 계정에 계정 연결로만 붙였으면 기록으로 세지 않는다 — 그 수단의 버튼으로 한 번 로그인해야 기록이 생긴다.
  - `나중에` 를 고르면 다음 실행의 점검표에 다시 보인다.

### Google 로그인 켜기

Google 로그인을 앱에 둘 때 이 절을 따른다. Google 을 켜지 않으면 이 절을 건너뛴다.

**전제:** [켜는 순서와 수단별로 필요한 것](#켜는-순서와-수단별로-필요한-것) 의 체크 목록에서 Google 을 골랐다.
- Google 은 따로 개발자 콘솔 앱을 만들지 않는다 — 위저드가 Firebase 에서 Google 로그인을 켜면서 OAuth 동의 화면의 앱 이름 · 지원 이메일을 값 표의 값으로 정하고, Web client ID 를 `googleServerClientId` 에 기록한다.

#### 콘솔 단계

1. 위저드가 `Google 로그인 — 동의 화면` 값 표를 보인다.
   - 행은 아래와 같다.
   - `앱 이름` — `config/<flavor>.json` 의 `appName` 값이다. 동의 화면에서 사용자가 보는 앱 이름이 된다.
   - `지원 이메일` — 동의 화면의 지원 이메일이다. 위저드가 gcloud 에 로그인한 계정을 제안하고, `지원 이메일 고치기` 로 바꿀 수 있다.
   - `동의 화면 로고 · 출시 전 선택` — 「앱 아이콘」 단계가 만든 `.setup/icons/google-120x120.png` 다.
2. 이미 동의 화면이 있는 프로젝트면 위저드 안내(`이미 동의 화면이 있으면 그 이름 · 이메일을 넣으세요`)대로 그 이메일을 넣는다.
   - 값이 맞으면 `이대로 진행` 을 고른다 — 위저드가 Google 로그인을 켜고 동의 화면을 만든다.
3. 값 표 아래에 `조직 밖 사용자가 Google 로그인을 하려면 「Google 인증 플랫폼」 → 「대상」 의 「사용자 유형」 을 「외부」 로 바꿔야 합니다` 가 보이면 프로젝트가 조직 아래에 있는 것이다.
   - Google Cloud 콘솔의 「Google 인증 플랫폼」(OAuth 동의 화면) → 「대상」 에서 「사용자 유형」 을 「외부」 로 바꾼다.
   - 조직이 없는 프로젝트는 「사용자 유형」 이 이미 「외부」 이고, 이 줄이 보이지 않아 이 단계를 건너뛴다.
4. 결과를 콘솔에서 본다 — Google Cloud 콘솔의 프로젝트 선택 창에서 그 프로젝트를 고른다(조직이 없는 프로젝트는 「조직 없음」 아래에 있다).
   - 이어서 `OAuth 동의 화면` → `브랜딩` 을 열면 앱 이름 · 지원 이메일이 값 표와 같다.
5. 동의 화면 로고는 출시 전 선택이고, 올리려면 「브랜딩」 화면의 「앱 로고」 → 「업로드할 로고 파일」 에 `.setup/icons/google-120x120.png` 를 올린다.
   - 위저드 노트대로 로고는 Google 의 브랜드 인증을 거쳐야 동의 화면에 보인다.
6. 출시 전에 「대상」 화면의 「게시 상태」 와 「브랜딩」 화면 맨 아래 「인증 상태」 의 「브랜딩 확인」 에서 동의 화면의 게시 상태와 브랜드 인증을 확인한다.
7. iOS · Android 쪽은 위저드가 한다.
   - 「Google — iOS 쪽」 단계가 설정 파일의 `REVERSED_CLIENT_ID` 를 `ios/Flutter/<flavor>.xcconfig` 에 쓰고, 「Google — Android 쪽」 단계가 디버그 서명 키의 SHA-1 을 Firebase 의 Android 앱에 등록한다.
   - release 서명 키의 SHA-1 은 위저드가 등록하지 않는다 — [릴리스 서명(keystore)](guide.md#릴리스-서명keystore) 에서 만든 키의 SHA-1 을 Firebase 콘솔 → 프로젝트 설정 → 「일반」 의 Android 앱에서 「SHA 인증서 지문」 표 아래 「디지털 지문 추가」 로 더한다.

#### 확인 방법

- 앱을 다시 빌드해 실행하면 로그인 화면에 Google 버튼이 보이고, 눌러 Google 계정을 고르면 로그인된다.
- 위저드의 「소셜 로그인 확인」 단계가 `Google 1명` 꼴로 1명 이상을 센다.
- Google Cloud 콘솔의 `OAuth 동의 화면` → `브랜딩` 에서 앱 이름 · 지원 이메일이 값 표와 같다.

#### 문제 해결

- **조직 밖 계정으로 로그인하면 거부된다.**
  - 프로젝트가 조직 아래에 있고 동의 화면 대상이 조직 안으로 묶여 있는 것이다 — 콘솔 단계 3 으로 외부로 바꾼다.
- **Android 에서 Google 계정을 고른 뒤 로그인이 끝나지 않는다.**
  - 그 빌드를 서명한 키의 SHA-1 이 Firebase 의 Android 앱에 없는 것이다.
  - debug 빌드면 `./setup.sh` 를 다시 실행해 「Google — Android 쪽」 단계가 등록하게 한다 — JDK 나 디버그 서명 키가 없어 지문을 계산하지 못했으면 [시작 전 준비](#시작-전-준비) 의 「Android 도구 · JDK」 를 먼저 갖춘다.
  - release 빌드면 콘솔 단계 7 의 release 키 SHA-1 을 더한다.
- **iOS 에서 Google 로그인 뒤 앱으로 돌아오지 않는다.**
  - `ios/Flutter/<flavor>.xcconfig` 의 `REVERSED_CLIENT_ID` 가 설정 파일과 다를 수 있다.
  - `./setup.sh` 를 다시 실행하면 「Google — iOS 쪽」 단계가 설정 파일의 값으로 맞춘다 — 그 뒤 앱을 다시 빌드한다.

#### 되돌리기

Google 을 끄는 법은 [로그인 수단 끄기](#로그인-수단-끄기) 에 있다.

### Apple 로그인 켜기

Apple 로그인을 앱에 둘 때 이 절을 따른다.
- Apple 을 켜지 않으면 이 절을 건너뛴다.
- iOS 앱은 기기의 Apple 로그인을 쓰고, Android 앱은 Apple 웹 로그인을 거치므로 Apple Developer 에 Services ID 와 키를 더 만든다.

**전제:** Apple Developer 계정이 있다([시작 전 준비](#시작-전-준비)).
- [켜는 순서와 수단별로 필요한 것](#켜는-순서와-수단별로-필요한-것) 의 체크 목록에서 Apple 을 골랐다.

#### 콘솔 단계

1. 「Apple 로그인 — iOS 쪽」 단계가 Firebase 에서 Apple 로그인을 켜고 앱의 번들 ID 를 등록한다 — iOS 쪽은 콘솔에서 할 일이 없다.
   - App ID 의 Sign in with Apple capability 는 자동 서명이면 Xcode 가 켠다.
   - 수동 서명이면 [iOS 서명 — Apple 을 꺼도 필요한 capability](#ios-서명--apple-을-꺼도-필요한-capability) 대로 켠다.
2. 「Apple 로그인 — Android 쪽」 단계가 `Apple 콘솔에 넣을 값 — <flavor>` 값 표를 보인다.
   - 행은 아래와 같다.
   - `Services ID (제안)` — 번들 ID 를 소문자로 쓰고 `.signin` 을 붙인 값이다. 만들 Services ID 의 identifier 로 쓴다.
   - `Return URL` — `https://<your-project-id>.firebaseapp.com/__/auth/handler`
   - `도메인` — `<your-project-id>.firebaseapp.com`
   - `primary App ID (번들 ID)` — iOS 앱의 번들 ID 다. Services ID 를 이 App ID 에 묶는다.
3. Apple Developer(<https://developer.apple.com/account>)의 Certificates, Identifiers & Profiles 에서 Services ID 를 만든다 — Identifiers 의 (+) 를 눌러 「Register a new identifier」 에서 「Services IDs」 를 고른 뒤 identifier 칸에 `Services ID (제안)` 값을 넣는다.
4. 만든 Services ID 에서 Sign in with Apple 을 켜고 그 줄의 「Configure」 를 누른다.
   - 열린 창 「Web Authentication Configuration」 의 「Primary App ID」 에서 `primary App ID (번들 ID)` 의 App ID 를 고르고, 「Website URLs」 의 (+) 를 눌러 「Domains and Subdomains」 칸에 `도메인` 값을, 「Return URLs」 칸에 `Return URL` 값을 넣는다.
   - 「Next」 → 목록을 확인하고 「Done」 → 「Continue」 → 「Save」 순서로 저장한다.
   - App ID 쪽의 「Sign In with Apple: App ID Configuration」 창은 이 창과 다른 창이다.
5. 키를 만든다 — Certificates, Identifiers & Profiles → Keys 의 (+) 에서 새 키를 만들고 「Apple Push Notifications service (APNs)」 · 「DeviceCheck」 · 「Sign in with Apple」 체크 상자를 켠 뒤 Sign in with Apple 줄의 「Configure」 를 누른다.
   - 화면 안내대로 이 줄은 설정해야 켜진다.
   - 위저드 할 일 줄 `APNs · DeviceCheck · Sign in with Apple 을 함께 켠 키 하나를 만들고 .p8 을 내려받기` 대로 만들면 같은 키를 APNs · App Check 에도 쓴다.
   - `.p8` 파일은 한 번만 내려받을 수 있으므로 안전한 곳에 둔다.
   - Key ID 는 키 화면에 보이고, 내려받은 파일 이름(`AuthKey_<Key ID>.p8`)에도 들어 있다.
6. 위저드의 `콘솔에서 키를 받았나요?` 에 `네 — 키를 입력합니다` 를 고르고 값 세 개를 입력한다.
   - 순서는 Services ID → `.p8` 파일 경로 → Key ID 다.
   - 파일 경로는 Finder 에서 `.p8` 파일을 터미널 창으로 끌어다 놓으면 들어간다.
   - Team ID 는 `ios/Flutter/<flavor>.xcconfig` 의 `DEVELOPMENT_TEAM` 이 형식에 맞으면 묻지 않고, 비었으면 `Apple Team ID` 를 물어 그 자리에 쓴다 — Team ID 는 Apple Developer 계정의 「멤버십 세부 사항」 의 「팀 ID」 에 있다.
   - 위저드가 Firebase 의 Apple 로그인 설정에 기록한다.
7. Android 쪽 콘솔 작업을 미루려면 `지금 안 함` 을 고른다.
   - Android 에서 Apple 로그인만 막히고, 미룬 일은 위저드 끝의 「release 빌드 전에 끝내야 할 일」 목록에 보인다.

#### 확인 방법

- iOS 앱의 로그인 화면에서 Apple 버튼을 누르면 Apple 로그인 시트가 뜨고, 로그인하면 앱에 로그인된다.
- Android 앱에서 Apple 버튼을 누르면 Apple 웹 로그인 화면이 브라우저로 열리고, 로그인하면 앱으로 돌아와 로그인된다.
- 위저드의 「소셜 로그인 확인」 단계가 `Apple 1명` 꼴로 1명 이상을 센다.

#### 문제 해결

- **Android 에서 Apple 로그인 뒤 브라우저가 닫히지 않는다.**
  - 기기 · 브라우저에 따라 로그인 뒤 브라우저가 자동으로 닫히지 않는다 — 앱으로 직접 돌아오면 로그인이 끝나 있다.
  - 브라우저를 로그인 전에 닫은 뒤 Apple 버튼이 반응하지 않으면 앱을 다시 실행한다.
- **Android 에서 Apple 웹 로그인이 오류 화면으로 끝난다.**
  - Services ID 의 도메인 · Return URL 이 값 표와 글자 그대로 같은지, 위저드에 넣은 Services ID 가 만든 것과 같은지 본다.
  - 위저드의 Apple 키 입력을 미뤘다면 `./setup.sh` 를 다시 실행해 「Apple 로그인 — Android 쪽」 단계를 마친다.
- **`.p8` 파일을 잃어버렸다.**
  - 같은 키는 다시 내려받을 수 없다 — Keys 에서 새 키를 만들고 `./setup.sh --providers` 를 다시 실행해 새 키를 넣는다.
- **iOS 실기기 빌드가 서명 오류로 끝난다.**
  - App ID 에 Sign in with Apple capability 가 없는 것이다 — [iOS 서명 — Apple 을 꺼도 필요한 capability](#ios-서명--apple-을-꺼도-필요한-capability) 대로 켠다.

#### 되돌리기

Apple 을 끄는 법은 [로그인 수단 끄기](#로그인-수단-끄기) 에 있다. Apple 을 꺼도 iOS 실기기 서명에는 capability 가 그대로 필요하다.

### Facebook 로그인 켜기

Facebook 로그인을 앱에 둘 때 이 절을 따른다. Facebook 을 켜지 않으면 이 절을 건너뛴다.

**전제:** Meta for Developers 계정이 있다.
- [켜는 순서와 수단별로 필요한 것](#켜는-순서와-수단별로-필요한-것) 의 체크 목록에서 Facebook 을 골랐다.
- Android 키 해시는 JDK 와 디버그 서명 키가 있어야 계산된다([시작 전 준비](#시작-전-준비)).

#### 콘솔 단계

1. 위저드가 `Facebook 콘솔에 넣을 값 — <flavor>` 값 표를 보인다.
   - 콘솔 주소는 `콘솔: https://developers.facebook.com/apps` 줄에 있고, 행은 아래와 같다.
   - `iOS 번들 ID` · `Android 패키지명` · `Android 기본 액티비티 클래스 이름` · `Android 키 해시` — Facebook 앱의 iOS · Android 플랫폼에 넣는 값이다. 키 해시를 계산하지 못했으면 행 값이 `(이 Mac 에서는 계산할 수 없음 — 비워 두세요 · …)` 이고 그 칸은 비워 둔다.
   - `OAuth redirect URI` — `https://<your-project-id>.firebaseapp.com/__/auth/handler`
   - `앱 아이콘(1024 x 1024) · 앱 게시 때 필수` — 「앱 아이콘」 단계가 만든 `.setup/icons/facebook-1024x1024.png` 다.
2. 앱을 만들고 Facebook 로그인 사용 사례를 더한다(할 일 줄 `앱 만들기 · Facebook 로그인 사용 사례 추가`) — 사용 사례 목록에서 「Facebook 로그인을 통한 인증 및 사용자의 데이터 요청」 을 고른다.
3. 리디렉션 주소를 넣는다 — `Facebook 로그인 → 설정 → 클라이언트 OAuth 설정 → 유효한 OAuth 리디렉션 URI` 칸에 `OAuth redirect URI` 값을 넣고 저장한다.
4. Android 플랫폼을 더한다 — 빠른 시작 Android 의 「3. Android 프로젝트에 대해 Facebook에 알리기」 에서 「패키지 이름」 · 「기본 액티비티 클래스 이름」 칸에 `Android 패키지명` · `Android 기본 액티비티 클래스 이름` 값을 넣는다.
   - `키 해시` 칸에 `Android 키 해시` 값을 넣고 `Save` 를 누른 뒤 `계속` 을 누른다 — 키 해시를 넣기 전에는 `계속` 이 눌리지 않는다.
5. iOS 플랫폼을 더한다 — 빠른 시작 iOS 의 「2. 번들 식별자 추가」 에서 「번들 ID」 칸에 `iOS 번들 ID` 값을 넣는다.
6. 키 세 개를 모은다.
   - App ID · App Secret 은 「앱 설정 → 기본 설정」 의 「앱 ID」 · 「앱 시크릿 코드」(「보기」 로 연다)에, Client Token 은 「앱 설정 → 고급 설정」 의 「클라이언트 토큰」 에 있다.
7. 위저드의 `콘솔에서 키를 받았나요?` 에 `네 — 키를 입력합니다` 를 고르고 키 세 개를 입력한다.
   - 순서는 `Facebook App ID` → `Facebook Client Token` → `Facebook App Secret` 다.
   - 위저드가 App ID 와 App Secret 의 짝을 Facebook 서버로 확인한 뒤 config · xcconfig · Secret Manager 와 Firebase 의 Facebook 로그인 설정에 기록한다.
8. 이메일은 Facebook 에서 필수로 받을 수 없다 — 할 일 줄의 이메일 권한은 [로그인 수단에서 이메일 받기](#로그인-수단에서-이메일-받기) 에 있다.
9. 개발 모드 앱은 앱 역할이 있는 계정만 로그인할 수 있다.
   - 테스트할 Facebook 계정을 「앱 역할」 화면의 「테스터」 · 「개발자」 탭에서 「사람 추가」 로 더한다.
   - 같은 메뉴의 「테스트 사용자 계정」 은 시뮬레이션 계정을 만드는 다른 기능이다.
10. 출시 전에 앱을 게시한다.
    - 게시 화면에 `Currently ineligible for submission` 이 보이면 그 아래 항목 — 앱 아이콘(1024 x 1024) · 개인정보처리방침 URL · 사용자 데이터 삭제 · 카테고리 — 을 채운다.
    - 앱 아이콘은 `.setup/icons/facebook-1024x1024.png` 를 「앱 설정 → 기본 설정」 의 「앱 아이콘」 칸에 올린다(끌어다 놓거나 파일 선택 창에서 ⌘⇧G 로 `<저장소 경로>/.setup/icons` 를 붙여 넣는다).
    - 앱 아이콘은 게시 때 필수이고 개발 모드 로그인에는 필요 없다.

#### 확인 방법

- 앱 역할이 있는 Facebook 계정으로 앱에서 Facebook 로그인이 된다.
- 위저드의 「소셜 로그인 확인」 단계가 `Facebook 1명` 꼴로 1명 이상을 센다.

#### 문제 해결

- **역할이 없는 계정으로 로그인하면 거부된다.**
  - 앱이 개발 모드다 — 그 계정에 앱 역할을 주거나, 콘솔 단계 10 대로 앱을 게시한다.
- **Facebook 이 리디렉션 주소를 거부한다.**
  - `유효한 OAuth 리디렉션 URI` 칸에 값 표의 `OAuth redirect URI` 가 글자 그대로 들어 있는지 본다.
- **Android 에서 키 해시가 맞지 않는다는 오류가 뜬다.**
  - 그 빌드를 서명한 키의 키 해시가 Facebook 앱에 없는 것이다.
  - debug 빌드는 값 표의 `Android 키 해시` 를, release 빌드는 [릴리스 서명(keystore)](guide.md#릴리스-서명keystore) 에서 만든 키의 키 해시를 `키 해시` 칸에 더한다.
- **위저드가 `App Secret 이 App ID 와 맞지 않습니다` 를 보인다.**
  - 두 값을 같은 Facebook 앱에서 다시 복사해 넣는다.
- **계정 정보의 「이메일」 행이 「-」 다.**
  - 사용자가 이메일 권한을 거부했거나 Facebook 계정에 유효한 이메일이 없다 — [로그인 수단에서 이메일 받기](#로그인-수단에서-이메일-받기).

#### 되돌리기

Facebook 을 끄는 법은 [로그인 수단 끄기](#로그인-수단-끄기) 에 있다.

### Kakao 로그인 켜기

Kakao 로그인을 앱에 둘 때 이 절을 따른다. Kakao 를 켜지 않으면 이 절을 건너뛴다.

**전제:** Kakao Developers 계정이 있다([시작 전 준비](#시작-전-준비)).
- [켜는 순서와 수단별로 필요한 것](#켜는-순서와-수단별로-필요한-것) 의 체크 목록에서 Kakao 를 골랐다.
- Android 키 해시는 JDK 와 디버그 서명 키가 있어야 계산된다([시작 전 준비](#시작-전-준비)).
- stg · prod 는 그 flavor 용 Kakao 앱을 새로 만든다 — [Kakao · Naver 는 flavor 마다 새 앱](#kakao--naver-는-flavor-마다-새-앱).

#### 콘솔 단계

1. 위저드가 `Kakao 콘솔에 넣을 값 — <flavor>` 값 표를 보인다.
   - 콘솔 주소는 `콘솔: https://developers.kakao.com/console/app` 줄에 있고, 행은 아래와 같다.
   - `Android 패키지명` · `iOS 번들 ID` — 네이티브 앱 키에 등록하는 앱의 패키지명 · 번들 ID 다.
   - `Android 키 해시` — 디버그 서명 키의 키 해시다. 키 해시를 계산하지 못했으면 행 값이 `(이 Mac 에서는 계산할 수 없음 — 비워 두세요 · …)` 이고 그 칸은 비워 둔다.
   - `앱 아이콘 올리기 · 선택` — 「앱 아이콘」 단계가 만든 `.setup/icons/kakao-128x128.png` 다.

   값 표 아래의 `이번에 만들 콘솔 앱: <flavor> 용 하나 — …` 줄은 이번 실행에서 만들 Kakao 앱이 그 flavor 용 하나라는 뜻이다.
2. 새 앱을 만든다(할 일 줄 `「앱 생성」 창에서 새 앱 만들기`) — 그 창에서 「앱 이름 (필수)」 · 「회사명 (필수)」 · 「카테고리 (필수)」 를 채운다.
3. 플랫폼 값을 넣는다(할 일 줄 `네이티브 앱 키에 Android 패키지명 · 키 해시 · iOS 번들 ID 등록`) — `[앱] > [플랫폼 키] > [네이티브 앱 키]` 를 열고 패키지명 칸에 `Android 패키지명` 값을, 키 해시 칸에 `Android 키 해시` 값을, 번들 ID 칸에 `iOS 번들 ID` 값을 넣고 저장한다.
4. 카카오 로그인과 OpenID Connect 를 켠다(할 일 줄 `카카오 로그인 · OpenID Connect 켜기`) — `카카오 로그인 → 일반` 에서 `사용 설정` 과 `OpenID Connect` 를 켠다.
   - OpenID Connect 가 꺼져 있으면 Kakao 로그인이 끝나지 않는다(아래 문제 해결).
5. 이메일을 받도록 동의 항목을 설정한다(할 일 줄 `동의 항목에서 이메일을 받도록 설정`) — 설정은 [로그인 수단에서 이메일 받기](#로그인-수단에서-이메일-받기) 의 Kakao 행에 있다.
   - 이 동의 항목은 비즈 앱(또는 테스트 앱)에서만 설정할 수 있다 — 일반 앱이면 먼저 [로그인 수단 검수 · 인증](guide.md#로그인-수단-검수--인증) 대로 비즈 앱으로 전환한다.
6. 키 두 개를 모은다.
   - 네이티브 앱 키는 `[앱] > [플랫폼 키] > [네이티브 앱 키]` 의 키 값이고, 어드민 키는 `[앱] > [어드민 키]` 에 있다.
7. 위저드의 `콘솔에서 키를 받았나요?` 에 `네 — 키를 입력합니다` 를 고르고 키 두 개를 입력한다.
   - 순서는 `Kakao 네이티브 앱 키` → `Kakao 어드민 키` 다. 어드민 키는 화면에 보이지 않게 받는다.
   - 위저드가 어드민 키를 Kakao 서버로 확인한 뒤 기록한다 — 네이티브 앱 키는 config · xcconfig · Secret Manager 에, 어드민 키는 Secret Manager 에만.
   - 그 프로젝트의 Secret Manager 에 어드민 키가 이미 있으면(같은 프로젝트에서 다시 켜거나 다시 실행할 때) 어드민 키는 아래 질문에서 새로 입력을 고를 때만 묻고, 그 밖에는 Secret Manager 의 값으로 확인한다.
   - 이때 Secret Manager 의 네이티브 앱 키가 입력한 키와 다르면 위저드가 `입력한 네이티브 앱 키가 Secret Manager 의 네이티브 앱 키와 다릅니다 — Secret Manager 의 어드민 키가 입력한 키와 같은 Kakao 앱의 키인가요?` 를 묻는다 — 같은 Kakao 앱이면 `네 — 같은 Kakao 앱입니다 · 어드민 키를 그대로 둡니다` 를 고르고, 새 Kakao 앱이면 `아니요 — 새 Kakao 앱입니다 · 어드민 키를 새로 입력합니다` 를 고른 뒤 그 앱의 어드민 키를 넣는다.
   - 두 키는 같은 Kakao 앱의 것이어야 한다 — 다르면 이미 가입한 사용자가 로그인 · 회원탈퇴를 하지 못한다.
   - 콘솔 작업이 남았으면 `아니요 — 끝내고 콘솔 작업 뒤 다시 실행` 을 고른다.
8. 앱 아이콘은 선택이고, 올리려면 `[앱] > [일반]` 의 「앱 기본 정보」 → 「수정」 에서 「앱 아이콘」 에 `.setup/icons/kakao-128x128.png` 를 올린다.
   - 단계 2 의 「앱 생성」 창에서 앱을 만들 때 올려도 된다.
   - 파일은 끌어다 놓거나, 파일 선택 창에서 ⌘⇧G 로 `<저장소 경로>/.setup/icons` 를 붙여 넣어 고른다.
   - 콘솔은 JPG · GIF · PNG 를 받고, 128 px 를 권장하며 250 KB 까지 받는다.

#### 확인 방법

- 앱을 다시 빌드해 실행하면 로그인 화면에 Kakao 버튼이 보이고, 눌러 로그인하면 앱에 로그인된다.
  - 카카오톡이 설치된 기기는 카카오톡으로, 설치되지 않은 기기는 카카오계정 웹 화면으로 로그인한다.
- 위저드의 「소셜 로그인 확인」 단계가 `Kakao 1명` 꼴로 1명 이상을 센다.

#### 문제 해결

- **Kakao 로그인 뒤 로그인 화면에 `서비스를 일시적으로 사용할 수 없습니다.` 배너가 뜬다.**
  - OpenID Connect 가 꺼져 있으면 Kakao 가 ID 토큰을 주지 않아 로그인이 끝나지 않는다 — 콘솔 단계 4 대로 `OpenID Connect` 를 켠 뒤 앱을 다시 실행한다.
- **로그인 화면에 `요청을 확인하지 못했습니다. …` 배너가 뜬다.**
  - App Check 가 Kakao 함수 호출을 막은 것이다.
  - debug 빌드면 App Check 디버그 토큰이 그 앱에 등록돼 있는지 [App Check 등록 확인](#app-check-등록-확인) 으로 본다 — 빠졌으면 `./setup.sh` 를 다시 실행해 「App Check 디버그 토큰」 단계가 다시 등록하게 하고 앱을 다시 빌드한다.
- **위저드가 `어드민 키가 맞지 않습니다` 를 보인다.**
  - 위저드가 어드민 키만 다시 묻는다 — 네이티브 앱 키와 같은 Kakao 앱의 어드민 키를 다시 복사해 넣는다.
- **위저드가 `어드민 키를 서버에서 확인하지 못했습니다` 를 보인다.**
  - Kakao 서버에 닿지 못한 것이다 — 네트워크 연결을 확인하고 `./setup.sh --providers` 를 다시 실행한다.
- **Android 에서 Kakao 로그인이 키 해시가 맞지 않는다는 오류로 끝난다.**
  - 그 빌드를 서명한 키의 키 해시가 Kakao 앱에 없는 것이다.
  - debug 빌드는 값 표의 `Android 키 해시` 를, release 빌드는 [릴리스 서명(keystore)](guide.md#릴리스-서명keystore) 에서 만든 키의 키 해시를 콘솔 단계 3 의 키 해시 칸에 더한다.

#### 되돌리기

Kakao 를 끄는 법은 [로그인 수단 끄기](#로그인-수단-끄기) 에 있다.

### Naver 로그인 켜기

Naver 로그인을 앱에 둘 때 이 절을 따른다. Naver 를 켜지 않으면 이 절을 건너뛴다. NAVER 앱이 설치된 기기는 NAVER 앱으로 로그인하고, 설치되지 않은 기기는 Naver 웹 로그인 화면을 거친다.

**전제:** Naver Developers 계정이 있다([시작 전 준비](#시작-전-준비)).
- [켜는 순서와 수단별로 필요한 것](#켜는-순서와-수단별로-필요한-것) 의 체크 목록에서 Naver 를 골랐다.
- stg · prod 는 그 flavor 용 Naver 애플리케이션을 새로 만든다 — [Kakao · Naver 는 flavor 마다 새 앱](#kakao--naver-는-flavor-마다-새-앱).

#### 콘솔 단계

1. 위저드가 `Naver 콘솔에 넣을 값 — <flavor>` 값 표를 보인다.
   - 콘솔 주소는 `콘솔: https://developers.naver.com` 줄에 있고, 행은 아래와 같다.
   - `iOS URL Scheme` — `config/<flavor>.json` 의 `naverUrlScheme` 값이다. 그 값이 비었거나 형식(소문자 영문으로 시작하는 소문자 영문 · 숫자)에 맞지 않으면 행 이름이 `iOS URL Scheme (제안)` 이고, 앱 이름으로 만든 제안값을 보인다.
   - `Android 패키지명` — 안드로이드 환경에 넣는 패키지 이름이다.
   - `로고 이미지 · 필수` — 「앱 아이콘」 단계가 만든 `.setup/icons/naver-140x140.png` 다.

   NAVER 앱이 없는 기기의 웹 로그인은 값 표의 `iOS URL Scheme` 값으로 돌아온다(`<URL Scheme>://authorize`) — 콘솔에서 따로 할 일은 없다.
2. 애플리케이션을 등록한다(할 일 줄 `애플리케이션 등록 · 네이버 로그인 API 사용 · 로고 이미지 올리기(필수 — 없으면 저장되지 않습니다)`) — 「애플리케이션 등록 (API 이용신청)」 화면의 「애플리케이션 이름」 을 채우고 「사용 API」 에서 네이버 로그인을 고른다.
   - 같은 화면의 `로고 이미지` 칸에서 `파일선택` 을 눌러 `.setup/icons/naver-140x140.png` 를 올린다(파일 선택 창에서 ⌘⇧G 로 `<저장소 경로>/.setup/icons` 를 붙여 넣는다).
   - 로고 이미지는 필수다 — 없으면 애플리케이션이 저장되지 않는다.
   - 콘솔은 jpg · png · gif 를 받고, 140x140 을 권장하며 500KB 까지 받는다.
   - 로고는 사용자가 보는 로그인 동의 화면에 나온다.
3. 서비스 환경을 넣는다(할 일 줄 `iOS 환경에 다운로드 URL · URL Scheme · Android 환경에 다운로드 URL · 패키지명 등록`) — 「사용 API」 에 네이버 로그인을 고르면 펼쳐지는 「로그인 오픈 API 서비스 환경」 의 「환경 추가」 에서 「안드로이드」 · 「iOS」 두 환경을 더한다.
   - iOS 환경: `다운로드 URL` 과 `URL Scheme` 을 넣는다. `URL Scheme` 칸에는 값 표의 `iOS URL Scheme` 값을 글자 그대로 넣는다.
   - 안드로이드 환경: `다운로드 URL` 과 `안드로이드 앱 패키지 이름` 만 넣는다. `안드로이드 앱 패키지 이름` 칸에는 값 표의 `Android 패키지명` 값을 넣는다.
   - `다운로드 URL` 은 스토어에 올리기 전이면 임의 주소(예: 개발사 홈페이지)를 넣고 출시 뒤 스토어 주소로 바꾼다.
4. 이메일을 받도록 제공 정보를 설정한다(할 일 줄 `제공 정보에서 이메일 주소 받기`) — 설정은 [로그인 수단에서 이메일 받기](#로그인-수단에서-이메일-받기) 의 Naver 행에 있다.
5. 개발 중 로그인할 아이디를 등록한다.
   - 위저드 할 일 줄 `개발 중인 애플리케이션은 멤버관리에 등록한 관리자 · 테스터 ID 만 로그인할 수 있습니다` 대로 `멤버관리` 에서 `관리자 ID 등록`(최대 3개) 또는 `테스터 ID 등록`(최대 20개)에 시험할 네이버 아이디를 넣는다.
6. Client ID · Client Secret 을 모은다 — 내 애플리케이션에서 그 앱을 열면 「개요」 탭의 「애플리케이션 정보」 에 「Client ID」 · 「Client Secret」(「보기」 로 연다)이 있다.
7. 위저드의 `콘솔에서 키를 받았나요?` 에 `네 — 키를 입력합니다` 를 고르고 값 세 개를 입력한다.
   - 순서는 `Naver Client ID` → `Naver Client Secret` → `Naver URL Scheme` 다. Client Secret 은 화면에 보이지 않게 받는다.
   - `Naver URL Scheme` 은 Enter 만 누르면 제안값이 들어간다 — 콘솔 단계 3 의 `URL Scheme` 칸과 같은 값을 넣는다.
   - 위저드가 Client ID · Client Secret 의 짝을 Naver 서버로 확인한 뒤 config · xcconfig · Secret Manager 에 기록한다(URL Scheme 은 config · xcconfig 에만).
   - 콘솔 작업이 남았으면 `아니요 — 끝내고 콘솔 작업 뒤 다시 실행` 을 고른다.

#### 확인 방법

- 앱을 다시 빌드해 실행하면 로그인 화면에 Naver 버튼이 보이고, 눌러 로그인하면 앱에 로그인된다.
  - NAVER 앱이 있는 기기는 NAVER 앱의 동의 화면을, 없는 기기는 Naver 웹 로그인 화면을 거친다.
- 위저드의 「소셜 로그인 확인」 단계가 `Naver 1명` 꼴로 1명 이상을 센다.
- Android 에서 두 경로를 모두 보려면 NAVER 앱을 끈 채(`adb shell pm disable-user --user 0 com.nhn.android.search`) 한 번, 되돌린 뒤(`adb shell pm enable com.nhn.android.search`) 한 번 로그인한다.
  - debug 빌드의 로그 `Naver 경로 선택: mode=web installed=false` · `mode=app installed=true` 가 어느 경로를 탔는지 보인다.
- iOS 에서 NAVER 앱으로 처음 로그인하면 iOS 가 `"<앱 이름>" wants to open "NAVER"` 확인 알림을 띄운다.
  - `Open` 을 눌러야 NAVER 앱으로 넘어간다 — `Cancel` 을 누르면 오류 배너 없이 로그인 화면으로 돌아온다.

#### 문제 해결

- **NAVER 앱이 「입력하신 아이디로 로그인할 수 없습니다 … 개발 중 상태에서는 등록된 아이디만 로그인할 수 있습니다」 화면을 띄운다.**
  - 애플리케이션이 개발 중 상태이고 그 아이디가 등록돼 있지 않은 것이다 — 콘솔 단계 5 대로 `멤버관리` 에 그 아이디를 등록한다.
- **위저드가 `Client ID · Client Secret 짝이 맞지 않습니다` 를 보인다.**
  - 위저드가 두 값을 함께 다시 묻는다 — 같은 애플리케이션의 Client ID 와 Client Secret 을 다시 복사해 넣는다.
- **위저드가 `Client ID · Client Secret 을 서버에서 확인하지 못했습니다` 를 보인다.**
  - Naver 서버에 닿지 못한 것이다 — 네트워크 연결을 확인하고 `./setup.sh --providers` 를 다시 실행한다.
- **iOS 에서 Naver 로그인 뒤 앱으로 돌아오지 않는다.**
  - 콘솔 iOS 환경의 `URL Scheme` 과 위저드에 넣은 `Naver URL Scheme` 이 다르다 — 두 값을 값 표의 `iOS URL Scheme` 값으로 맞춘다.
  - 위저드 값을 고치려면 `config/<flavor>.json` 의 `naverUrlScheme` 을 고친 뒤 `./setup.sh --providers` 를 다시 실행하고 앱을 다시 빌드한다.
- **Android 에서 Naver 버튼을 눌렀는데 오류 배너 없이 로그인 화면으로 돌아온다.**
  - Android 의 Naver 로그인 플러그인은 사용자가 취소한 경우뿐 아니라 오류 설명에 `cancel` 이 든 오류(네트워크 오류 등)도 취소로 앱에 넘긴다.
  - 앱은 취소를 배너 없이 처리하므로 이런 실패는 화면에 드러나지 않는다.
  - debug 빌드의 로그에 `Naver logIn cancel: status=loggedOut` 줄이 있으면 취소로 끝난 것이다 — 네트워크 연결을 확인한 뒤 다시 로그인한다.
- **NAVER 앱이 없는 기기의 웹 로그인이 로그인 화면 대신 Naver 오류 페이지로 끝난다.**
  - 웹 로그인이 돌아올 주소(`<URL Scheme>://authorize`)를 Naver 가 받아들이는지 PC 브라우저로 확인한다.
  - 아래 주소의 `<clientId>` 에 Client ID 를, `<naverUrlScheme>` 에 값 표의 `iOS URL Scheme` 값을 넣어 연다 — `client_secret` 은 넣지 않는다.

  ```text
  https://nid.naver.com/oauth2.0/authorize?response_type=code&client_id=<clientId>&redirect_uri=<naverUrlScheme>%3A%2F%2Fauthorize&state=probe1
  ```

  Naver 로그인 폼이 뜨고, 로그인 뒤 브라우저 주소창이 `<naverUrlScheme>://authorize?code=…&state=probe1` 로 바뀌면 Naver 쪽 설정은 맞다(PC 에는 그 주소를 받을 앱이 없어 이동은 실패한다).
  - 주소의 `code` 값은 한 번만 쓰는 값이므로 기록 · 공유하지 않는다.
  - 로그인 폼 대신 오류 페이지가 뜨면 콘솔 iOS 환경의 `URL Scheme` 이 값 표의 `iOS URL Scheme` 값과 같은지 본다.

#### 되돌리기

Naver 를 끄는 법은 [로그인 수단 끄기](#로그인-수단-끄기) 에 있다.

### LINE 로그인 켜기

LINE 로그인을 앱에 둘 때 이 절을 따른다. LINE 을 켜지 않으면 이 절을 건너뛴다. LINE 콘솔은 영어 화면이라 칸 이름을 영어 원문 그대로 쓴다.

**전제:** LINE Developers 계정이 있다([시작 전 준비](#시작-전-준비)).
- [켜는 순서와 수단별로 필요한 것](#켜는-순서와-수단별로-필요한-것) 의 체크 목록에서 LINE 을 골랐다.
- Android 서명 SHA-1 은 JDK 와 디버그 서명 키가 있어야 계산된다([시작 전 준비](#시작-전-준비)).

#### 콘솔 단계

1. 위저드가 `LINE 콘솔에 넣을 값 — <flavor>` 값 표를 보인다.
   - 콘솔 주소는 `콘솔: https://developers.line.biz/console/` 줄에 있고, 행은 아래와 같다.
   - `iOS 번들 ID` — `LINE Login` 탭의 `iOS bundle ID` 칸에 넣는다.
   - `Android 패키지명` — `LINE Login` 탭의 `Package names` 칸에 넣는다.
   - `Android 서명 SHA-1` — 디버그 서명 키의 SHA-1 을 LINE 이 받는 대문자 · 콜론 꼴로 보인다. `LINE Login` 탭의 `Package signatures` 칸에 넣는다.
     - SHA-1 을 계산하지 못했으면 행 값이 `(이 Mac 에서는 계산할 수 없음 — 비워 두세요 · …)` 이고 그 칸은 비워 둔다.
   - `Channel icon · 선택` — 「앱 아이콘」 단계가 만든 `.setup/icons/line-512x512.png` 다.
2. 채널을 만든다(할 일 줄 `LINE Login 채널 만들기`) — `Create a new channel` 에서 `Channel type` 으로 `LINE Login` 을 고르고, `Provider` · `Region to provide the service` · `Company or owner's country or region` 을 채운다.
   - 앱 종류는 「App types」 에서 「Mobile app」 을 고른다.
3. 앱 값을 넣는다(할 일 줄 `iOS 번들 ID · Android 패키지명 · 서명 SHA-1 등록`) — 채널의 `LINE Login` 탭에서 `iOS bundle ID` · `Package names` · `Package signatures` 칸에 값 표의 세 행을 넣고 저장한다.
   - `Package signatures` 는 값 표의 대문자 · 콜론 꼴 그대로 넣는다.
   - 킷의 iOS 앱은 `line3rdp.<번들 ID>` URL scheme 으로 돌아오고 universal link 를 쓰지 않으므로 `iOS universal link` 칸은 비워 둔다.
   - `Android URL scheme` 칸은 비워 둔다 — 선택 칸이고, 킷의 Android 앱은 LINE 로그인에 URL scheme 을 쓰지 않는다.
4. 이메일 주소 권한을 신청한다(할 일 줄 `OpenID Connect 의 이메일 주소 권한 신청 — 신청하지 않으면 로그인 때 이메일을 받지 못합니다`) — `Basic settings` → `OpenID Connect` 의 `Email address permission` 이 `Unapplied` 면 `Apply` 로 신청한다.
   - 신청 절차는 [로그인 수단 검수 · 인증](guide.md#로그인-수단-검수--인증) 에 있다.
5. 개발 중 로그인할 계정에 역할을 준다.
   - 위저드 할 일 줄 `개발 중인 채널은 Admin 이나 Tester 역할을 준 계정으로 로그인합니다` 대로 시험할 LINE 계정에 채널의 「Roles」 탭 → 「Invite by email」 에서 Admin 이나 Tester 역할을 준다 — 프로바이더 화면에도 같은 이름의 「Roles」 탭이 있지만 그쪽 역할은 Admin · Member 뿐이고 Tester 가 없다.
6. Channel ID · Channel Secret 을 모은다 — 채널의 `Basic settings` 탭에 있다.
7. 위저드의 `콘솔에서 키를 받았나요?` 에 `네 — 키를 입력합니다` 를 고르고 값 두 개를 입력한다.
   - 순서는 `LINE Channel ID` → `LINE Channel Secret` 다. Channel Secret 은 화면에 보이지 않게 받는다.
   - 위저드가 두 값의 짝을 LINE 서버로 확인한 뒤 Channel ID 는 config · xcconfig · Secret Manager 에, Channel Secret 은 Secret Manager 에만 기록한다.
   - 콘솔 작업이 남았으면 `아니요 — 끝내고 콘솔 작업 뒤 다시 실행` 을 고른다.
8. 채널 아이콘은 선택이고, 올리려면 단계 2 의 `Create a new channel` 화면에서 「Channel icon」 칸의 「Register」 로 `.setup/icons/line-512x512.png` 를 올린다(끌어다 놓거나 파일 선택 창에서 ⌘⇧G 로 `<저장소 경로>/.setup/icons` 를 붙여 넣는다).
   - `Channel icon` 은 PNG · JPG · JPEG · GIF · BMP 를 3MB 까지 받고 크기 규정은 없다.

#### 확인 방법

- 앱을 다시 빌드해 실행하면 로그인 화면에 LINE 버튼이 보이고, 역할을 준 계정으로 로그인하면 앱에 로그인된다.
  - LINE 앱이 설치된 기기는 LINE 앱으로, 없는 기기는 LINE 웹 로그인 화면으로 로그인한다.
- 위저드의 「소셜 로그인 확인」 단계가 `LINE 1명` 꼴로 1명 이상을 센다.

#### 문제 해결

- **로그인이 `This channel is now developing status. User need to have developer role` 로 끝난다.**
  - 채널이 개발 중 상태이고 그 계정에 역할이 없는 것이다 — 콘솔 단계 5 대로 Admin 이나 Tester 역할을 준다.
- **Android 에서 LINE 앱으로 넘어갔다가 빈 화면으로 돌아오고 로그인되지 않는다.**
  - `Package signatures` 의 SHA-1 이 그 빌드를 서명한 키와 다르거나 대문자 · 콜론 꼴이 아니다.
  - debug 빌드는 값 표의 `Android 서명 SHA-1` 을 그대로, release 빌드는 [릴리스 서명(keystore)](guide.md#릴리스-서명keystore) 에서 만든 키의 SHA-1 을 같은 꼴로 더한다.
- **위저드가 `Channel ID 가 맞지 않습니다` 나 `Channel Secret 이 Channel ID 와 맞지 않습니다` 를 보인다.**
  - 위저드가 틀린 쪽 값을 다시 묻는다 — 같은 채널의 `Basic settings` 탭에서 값을 다시 복사해 넣는다.
- **계정 정보의 「이메일」 행이 「-」 다.**
  - `Email address permission` 을 신청하지 않았거나 사용자가 이메일 제공에 동의하지 않은 것이다 — [로그인 수단에서 이메일 받기](#로그인-수단에서-이메일-받기).

#### 되돌리기

LINE 을 끄는 법은 [로그인 수단 끄기](#로그인-수단-끄기) 에 있다.

### Kakao · Naver · LINE 서명 권한(Token Creator)

Kakao · Naver · LINE 의 함수는 로그인 때(Naver · LINE 은 연결 해제 · 회원탈퇴 때도) Firebase Custom Token 을 만들어 서명한다.
- 그래서 함수가 실행되는 서비스 계정(따로 정하지 않으면 프로젝트의 기본 Compute 서비스 계정)에 그 계정 자신을 구성원으로 한 Service Account Token Creator(`roles/iam.serviceAccountTokenCreator`)가 있어야 한다.
- 기본 Compute 서비스 계정이 기본으로 받는 역할에는 이 권한이 없어, 빠뜨리면 그 수단의 로그인이 앱에서 오류 배너로 끝나고 Naver · LINE 의 연결 해제 · 회원탈퇴도 오류로 끝난다.
- 셋 가운데 하나도 켜지 않으면 이 절을 건너뛴다.

**위저드가 하는 일:** 「Cloud Functions 배포」 뒤 「Custom Token 서명 권한」 단계가 켠 수단 함수의 런타임 서비스 계정을 읽고, 권한이 없으면 그 계정에 조건 없이 붙인다 — 프로젝트 수준 역할은 바꾸지 않는다.
- 권한이 있으면 `함수 런타임 서비스 계정 <n>개 · Token Creator 있음` 으로 지나가고, 막 붙였으면 `Token Creator 를 붙였습니다 — 반영에 몇 분 걸릴 수 있어 …` 를 보인다.
- 프로젝트마다 한 번 하면 되고, 위저드를 다시 실행할 때마다 다시 확인한다.

#### 직접 확인하고 붙이기

위저드 밖에서 확인하거나, 위저드가 붙이지 못했을 때 아래 명령을 쓴다.
- 먼저 함수의 서비스 계정을 읽는다.
- 서비스 이름은 함수 이름을 소문자로 쓴 것이다(Kakao `kakaocustomtoken` · Naver `navercustomtoken` · LINE `linecustomtoken`).
- `--region` 은 `config/<flavor>.json` 의 `functionsRegion` 값이고(아래 `asia-northeast3` 은 example 값), `<your-project-id>` 는 `firebaseProjectId` 값이다.
- 출력된 이메일이 아래 명령의 `<service-account-email>` 자리에 들어간다.

```bash
gcloud run services describe kakaocustomtoken --region asia-northeast3 --project <your-project-id> --format='value(spec.template.spec.serviceAccountName)'
```

그 계정의 IAM 정책에 `roles/iam.serviceAccountTokenCreator` 역할과 `serviceAccount:<service-account-email>` 구성원이 함께 든, 조건(`condition`)이 없는 바인딩이 있는지 본다.

```bash
gcloud iam service-accounts get-iam-policy <service-account-email> --project <your-project-id> --format=json
```

없으면 붙인다.
- 그 서비스 계정에만 붙고 프로젝트 수준 역할은 바뀌지 않는다.

```bash
gcloud iam service-accounts add-iam-policy-binding <service-account-email> --member=serviceAccount:<service-account-email> --role=roles/iam.serviceAccountTokenCreator --condition=None --project <your-project-id>
```

성공하면 `Updated IAM policy for serviceAccount` 로 시작하는 줄이 나온다.
- 권한이 반영되기까지 몇 분 걸릴 수 있다.
- 켠 수단의 함수가 서로 다른 서비스 계정을 쓰면 계정마다 한다.

#### 문제 해결

- **위저드가 `함수 런타임 서비스 계정에 Token Creator 를 붙이지 못했습니다` 를 보인다.**
  - 서비스 계정의 IAM 정책을 바꿀 수 있는 계정(예: 프로젝트 소유자)으로 gcloud 에 로그인했는지 확인한다.
  - 조직 정책이 막으면 조직 관리자에게 그 프로젝트의 예외를 요청한다.
  - 권한이 생긴 뒤 `./setup.sh` 를 다시 실행하면 이어진다.
- **Kakao · Naver · LINE 로그인이 오류 배너로 끝나거나, Naver · LINE 의 연결 해제 · 회원탈퇴가 오류로 끝난다.**
  - 함수 로그(Cloud Logging)에 `auth/insufficient-permission` 이 있으면 이 권한이 없는 것이다 — 위 명령으로 확인하고 붙인다.
  - 막 붙였다면 몇 분 기다린 뒤 로그인 · 해제 · 탈퇴를 다시 시도한다.
  - 해제 · 탈퇴는 그 수단 쪽 연결이 이미 끊긴 상태에서 실패한 것이므로 다시 시도할 때 그 수단의 로그인을 다시 거친다.

### 로그인 수단에서 이메일 받기

켠 로그인 수단이 가입할 때 이메일을 주도록 provider 콘솔을 설정하는 절차다.
- 킷은 로그인 수단이 준 이메일을 계정의 이메일로 쓰고, 사용자가 나중에 이메일을 등록하는 화면은 두지 않는다.
- 이메일이 오지 않은 계정은 설정 → 내 계정(계정 정보 화면)의 「이메일」 행이 「-」 로 보이고, 같은 사람이 다른 로그인 수단으로 이미 가입해 있어도 기존 계정 안내 없이 새 계정이 하나 더 생긴다.
- 그래서 켠 provider 마다 이메일을 필수로 받도록 설정한다.
- 소셜 로그인을 하나도 켜지 않았으면 이 절을 건너뛴다.

**전제:** [로그인 수단 켜기](#로그인-수단-켜기) 의 수단별 절로 그 provider 의 콘솔에 앱을 등록한다.
- 이 절의 설정은 모두 그 콘솔에서 하고, 앱 코드는 고치지 않는다.

#### provider 별 설정

| provider | 이메일을 필수로 받는 설정 | 할 일 |
|----------|---------------------------|-------|
| Google | 없음 | 설정할 것이 없다 |
| Apple | 없음 | 설정할 것이 없다 |
| Facebook | 없음 | 설정할 것이 없다 — 사용자가 이메일 권한을 거부할 수 있다 |
| Kakao | 있음 | 비즈 앱(또는 테스트 앱)에서 「카카오계정(이메일)」 동의항목을 [필수 동의] 로 설정한다 · 프로필 사진을 받으려면 「프로필 사진」 동의항목을 [선택 동의] 로 켠다 |
| Naver | 있음 | 「연락처 이메일 주소」 를 필수 제공 항목으로 설정한다 |
| LINE | 없음 | email 권한을 신청한다 — 권한을 받아도 사용자가 이메일 제공에 동의하지 않을 수 있다 |

**Kakao.**
- 「카카오계정(이메일)」 동의항목의 동의 단계는 비즈 앱 또는 테스트 앱에서만 설정할 수 있다.
- 일반 앱이면 먼저 비즈 앱으로 전환한다 — 전환 절차는 [로그인 수단 검수 · 인증](guide.md#로그인-수단-검수--인증) 에 있다.
- 그다음 Kakao Developers 앱 관리 페이지의 [카카오 로그인] > [동의항목] > [개인정보] 에서 「카카오계정(이메일)」 행의 [설정] 을 누르고, 동의 단계를 [필수 동의] 로 고른 뒤 동의 목적을 입력한다.
- 설정창에 「카카오계정으로 수집 후 제공」 이 있으면 함께 켠다 — 카카오계정에 등록되지 않은 정보를 사용자에게 동의와 입력을 요청해 받아 주는 기능이다.
- [필수 동의] 로 두어도 Kakao 가 갖고 있지 않은 정보는 오지 않을 수 있다.
- 프로필 사진도 받으려면 같은 [카카오 로그인] > [동의항목] > [개인정보] 에서 「프로필 사진」 행의 [설정] 을 누르고 [선택 동의] 로 켠다 — 사용자가 동의하면 ID 토큰에 사진 주소가 담긴다.
- 앱 등록 순서에서 이 설정의 자리는 [Kakao 로그인 켜기](#kakao-로그인-켜기) 의 콘솔 단계 5 다.
- 공식 문서: <https://developers.kakao.com/docs/ko/kakaologin/utilize> · <https://developers.kakao.com/docs/ko/kakaologin/prerequisite>

**Naver.**
- Naver Developers 의 애플리케이션 API 설정 메뉴에서 「연락처 이메일 주소」 를 필수 제공 항목으로 둔다.
- 추가 제공 항목으로 두면 사용자가 제공 여부를 고르므로 이메일이 오지 않을 수 있다.
- Naver 는 필수 제공 항목을 서비스 이용에 반드시 필요한 정보로만 설정하라고 안내한다.
- 앱 등록 순서에서 이 설정의 자리는 [Naver 로그인 켜기](#naver-로그인-켜기) 의 콘솔 단계 4 다.
- 공식 문서: <https://developers.naver.com/docs/login/devguide/devguide.md>

**LINE.**
- LINE Developers Console 에서 채널의 Basic settings 탭 → OpenID Connect → Apply 로 email 권한을 신청한다 — 신청 절차는 [로그인 수단 검수 · 인증](guide.md#로그인-수단-검수--인증) 에 있다.
- 권한이 없는 채널은 동의 화면에 이메일 항목이 없고 이메일 없이 가입된다.
- 권한을 받은 뒤에도 동의 화면에서 이메일은 필수 항목이 아니다 — 사용자가 이메일 제공에 동의하지 않고 로그인할 수 있다.
- 공식 문서: <https://developers.line.biz/en/docs/line-login/integrate-line-login/>

**Facebook.**
- 이메일을 필수로 받을 수 없다.
- 앱은 `email` 권한을 요청하지만, 사용자는 로그인할 때 공개 프로필을 뺀 권한을 모두 거부할 수 있고 Facebook 계정에 유효한 이메일이 없으면 값이 오지 않는다.
- 공식 문서: <https://developers.facebook.com/documentation/facebook-login/guides/permissions/handle-declined> · <https://developers.facebook.com/docs/graph-api/reference/user/>

**Google · Apple.**
- 설정할 것이 없다.
- Apple 은 사용자가 가입할 때 이메일 가리기(Hide My Email)를 고르면 `privaterelay.appleid.com` 도메인의 주소가 온다.
- 공식 문서: <https://firebase.google.com/docs/auth/ios/apple>

Facebook · LINE 처럼 이메일을 필수로 받을 수 없는 로그인 수단을 켜면 이메일 없는 계정이 생길 수 있다.
- 그 계정은 「이메일」 행이 「-」 로 보이고, 같은 사람이 다른 로그인 수단으로 만든 계정이 있어도 기존 계정 안내가 뜨지 않는다.
- 이메일이 꼭 필요한 앱은 가입 흐름에 이메일을 받는 화면을 직접 더한다.

#### 확인 방법

- 그 provider 로 새로 가입한 뒤 설정 → 내 계정(계정 정보 화면)을 연다.
  - 「이메일」 행에 「-」 가 아니라 그 provider 계정의 이메일이 보인다.
- LINE 은 신청이 받아들여지면 채널 Basic settings 탭의 OpenID Connect 에서 Email address permission 아래에 「Applied」 가 보인다.

#### 문제 해결

- **「이메일」 행이 「-」 다.**
  - 그 계정이 가입할 때 provider 가 이메일을 주지 않았다.
  - 원인은 provider 마다 다르다 — 설정을 고친 뒤 새로 가입하는 계정으로 다시 확인한다.
  - Kakao — 앱이 비즈 앱(또는 테스트 앱)이 아니다.
    - 또는 「카카오계정(이메일)」 동의항목이 [필수 동의] 가 아니다.
    - 또는 Kakao 가 그 사용자의 이메일을 갖고 있지 않다.
  - Naver — 「연락처 이메일 주소」 가 추가 제공 항목이고 사용자가 제공을 고르지 않았다.
  - LINE — 채널에 email 권한이 없다.
    - 또는 사용자가 동의 화면에서 이메일 제공에 동의하지 않았다.
    - 또는 LINE 계정에 이메일이 등록돼 있지 않다.
  - Facebook — 사용자가 이메일 권한을 거부했다.
    - 또는 Facebook 계정에 유효한 이메일이 없다.
    - 앱 설정으로는 고칠 수 없다.
- **같은 사람인데 계정이 두 개 생겼다.**
  - 나중에 쓴 로그인 수단이 이메일을 주지 않았거나 먼저 만든 계정과 다른 이메일을 줬다.
  - 그 로그인 수단을 먼저 만든 계정에 연결하려면 새로 생긴 계정으로 로그인해 회원탈퇴한 뒤, 먼저 만든 계정의 설정 → 내 계정(계정 정보 화면) → 「계정 연결」 에서 연결한다.

#### 되돌리기

Kakao 의 동의 단계와 Naver 의 제공 항목 구분을 바꾸기 전 값으로 되돌린다.
- 필수로 받지 않으면 그 뒤에 가입하는 계정은 이메일 없이 만들어질 수 있다.

## 알림(APNs) · App Check

iOS 실기기의 푸시 알림은 Firebase 에 APNs 인증 키가 있어야 도착하고, 킷의 보호된 기능(회원탈퇴 등)은 App Check 등록이 있어야 동작한다. 둘 다 위저드의 출시용 단계가 안내하거나 등록한다 — 이 절은 콘솔에서 할 일과 확인하는 화면을 적는다.

### APNs 인증 키 올리기

iOS 앱에서 푸시 알림을 받을 때 이 절을 따른다. iOS 알림을 쓰지 않으면 이 절을 건너뛴다 — Android 알림에는 필요 없다.

**전제:** Apple Developer 에서 APNs 를 켠 `.p8` 키가 있다.
- [Apple 로그인 켜기](#apple-로그인-켜기) 콘솔 단계 5 의 키(APNs · DeviceCheck · Sign in with Apple 을 함께 켠 키 하나)를 그대로 쓴다.

#### 콘솔 단계

1. 위저드의 「App Check — DeviceCheck」 단계에서 Apple 키를 넣으면, 이어지는 「APNs 키」 단계가 `Firebase 콘솔에 올릴 APNs 인증 키` 값 표를 보인다.
   - 행은 아래와 같다.
   - `iOS 앱 (번들 ID)` — 키를 올릴 iOS 앱이다. 위저드 노트대로 Firebase 프로젝트에 iOS 앱이 여럿이면 이 번들 ID 의 앱에 올린다.
   - `.p8` — `Key ID <Key ID> 의 .p8` 꼴로, 올릴 키 파일을 가리킨다.
   - `Key ID` · `Team ID` — 키를 올릴 때 함께 넣는 값이다.
2. Firebase 콘솔에서 그 프로젝트를 열고 `프로젝트 설정` → `클라우드 메시징` → `Apple 앱 구성` 에서 값 표의 번들 ID 앱을 찾는다.
3. `APN 인증 키` 아래 `개발 APNs 인증 키` · `프로덕션 APNs 인증 키` 두 칸에 같은 `.p8` 을 올린다(할 일 줄 `Firebase 콘솔에 APNs 인증 키 올리기 — iOS 앱마다 · 개발 · 운영 같은 키`).
   - 올리는 창의 「키 ID(필수 항목)」 · 「팀 ID(필수 항목)」 칸에 값 표의 `Key ID` · `Team ID` 를 넣는다 — 「팀 ID(필수 항목)」 은 이미 채워져 있을 수 있으니 값 표의 `Team ID` 와 같은지 본다.
4. stg · prod 는 그 flavor 의 Firebase 프로젝트에서 같은 일을 한다.
   - 키 파일은 저장소에 두지 않는다.

#### 확인 방법

- 위저드는 업로드 여부를 읽을 수 없어 「APNs 키」 줄을 `콘솔 업로드(확인은 실기기 알림)` 로 남긴다 — 확인은 iOS 실기기에서 알림이 도착하는지로 한다.
- 알림을 켜고 보내 보는 법은 [FCM 알림](guide.md#fcm-알림) 에 있다.

#### 문제 해결

- **iOS 실기기에 알림이 오지 않는다.**
  - 값 표의 번들 ID 앱에 키를 올렸는지, `개발 APNs 인증 키` · `프로덕션 APNs 인증 키` 두 칸 모두 올렸는지 본다.
  - 앱 쪽 설정(Push Notifications capability · `aps-environment`)은 [FCM 알림](guide.md#fcm-알림) 에서 확인한다.
- **`.p8` 파일을 잃어버렸다.**
  - 같은 키는 다시 내려받을 수 없다 — Apple Developer 의 Keys 에서 새 키를 만들고 `./setup.sh` 를 다시 실행해 DeviceCheck 에 새 키를 넣은 뒤, 같은 키를 이 절대로 올린다.

#### 되돌리기

올린 키는 같은 `APN 인증 키` 칸에서 지우거나 새 키로 바꾼다.
- 지우면 iOS 실기기에 알림이 오지 않는다.

### App Check 등록 확인

킷의 보호된 기능(회원탈퇴 · 테스트 알림 등)을 부르는 함수는 App Check 토큰이 있는 호출만 받는다. 위저드가 아래를 등록하고, 이 절은 그 등록을 콘솔에서 확인하는 화면을 적는다.

| 위저드 단계 | 등록하는 것 | 언제 |
|---|---|---|
| App Check 디버그 토큰 | `config/<flavor>.json` 의 `appCheckDebugToken` 을 iOS · Android 앱의 디버그 토큰으로 등록한다 — 표시 이름은 `setup-wizard-<flavor>` 다 | 항상 — debug 빌드용 |
| App Check — Play Integrity | Play Integrity API 를 켜고 Android 앱에 Play Integrity 를 등록한다. dev · stg 는 디버그 SHA-256 을 등록하고 Play 밖 설치를 허용한다. prod 는 Play 에 올린 뒤 Play 앱 서명 키(업로드 키와 다르다)의 SHA-256 을 받는다 | 출시용 단계 — `지금 안 함` 으로 미룰 수 있다 |
| App Check — DeviceCheck | Apple 키(`.p8` 경로 · Key ID)와 Team ID 를 받아 iOS 앱에 DeviceCheck 를 등록한다 | 출시용 단계 — `지금 안 함` 으로 미룰 수 있다 |

미룬 단계는 위저드 끝의 「release 빌드 전에 끝내야 할 일」 목록에 보인다.

#### 확인 방법

- Firebase 콘솔에서 그 프로젝트를 열고 App Check 의 「앱」 탭에서 Android 앱에 Play Integrity, iOS 앱에 DeviceCheck 가 등록돼 있는지(「상태」 가 「등록됨」) 본다.
- App Check 「앱」 탭의 앱 행 「⋮」 메뉴 → 「디버그 토큰 관리」 에 표시 이름 `setup-wizard-<flavor>` 인 디버그 토큰이 iOS · Android 앱마다 있는지 본다.
- debug 빌드에서 회원탈퇴 같은 보호된 기능이 동작한다.
  - dev · stg 의 Play Integrity 는 설정 뒤 1~2분 지나 release 빌드로 확인한다.

#### 문제 해결

- **debug 빌드에서 보호된 기능이 실패한다.**
  - 디버그 토큰 등록을 본다 — [그 밖의 문제](#그-밖의-문제) 의 App Check 디버그 토큰 항목.
- **release 빌드에서 보호된 기능이 실패한다.**
  - 출시용 단계를 미뤘으면 `./setup.sh` 를 다시 실행해 「App Check — Play Integrity」 · 「App Check — DeviceCheck」 를 마친다.
  - prod 의 Android 는 Play 에 앱을 올린 뒤 Play 앱 서명 키의 SHA-256 을 넣는다.

## stg · prod 설정

dev 와 따로 쓰는 stg · prod 환경이 필요하면 이 절을 따른다. flavor 마다 Firebase 프로젝트를 따로 쓰고, 위저드가 그 flavor 에 dev 와 같은 흐름을 적용한다.

**전제**

- dev 의 처음 설정이 끝나 있다([위저드 실행](#위저드-실행)).
  - Functions 리전은 dev 실행이 정한다(아래 「Functions 리전」).

**단계**

```bash
./setup.sh --flavor stg
./setup.sh --flavor prod
```

- 위저드가 그 flavor 의 Firebase 프로젝트를 만들거나 고르는 것부터 dev 와 같은 흐름을 적용한다.
  - 그 flavor 의 사용자 설정 파일(`config/<flavor>.json` · `ios/Flutter/<flavor>.xcconfig`)을 example 파일에서 만들어 채운다.
- 앱 이름 · Bundle ID 접미사는 flavor 마다 다르다 — example 값은 dev `StarterKit Dev` · `.dev`, stg `StarterKit Stg` · `.stg`, prod `StarterKit` · 빈 접미사다.
  - 그래서 세 flavor 의 앱을 한 기기에 같이 설치할 수 있다.
- 로그인 수단은 flavor 마다 따로 켠다 — `./setup.sh --flavor prod --providers` 처럼 `--providers` 를 함께 준다.
  - 켤 수단의 콘솔 앱도 flavor 마다 따로 만든다([Kakao · Naver 는 flavor 마다 새 앱](#kakao--naver-는-flavor-마다-새-앱)).
- 같은 명령을 다시 실행하면 그 flavor 에서 끝난 단계는 검사만 하고 건너뛴다.

**Functions 리전**

Cloud Functions 리전은 dev 처음 설정의 「위치 · Firestore」 단계에서 Firestore 위치와 함께 한 번 고른다(기본 `asia-northeast3` · 서울).
- 위저드는 고른 값을 세 곳에 같이 쓴다.

| 위치 | 값 |
|---|---|
| `config/<flavor>.json` 의 `functionsRegion` | 앱이 부를 리전 |
| `functions/src/shared/region.ts` 의 `REGION` | 함수를 배포할 리전 |
| `lib/core/config/app_config.dart` | `functionsRegion` 이 없을 때 앱이 쓰는 기본값 |

리전은 모든 flavor 가 함께 쓴다.
- stg · prod 는 리전을 묻지 않고 `dev 와 같은 위치 — Functions 리전은 모든 flavor 가 함께 씁니다.` 를 보인 뒤 `region.ts` 의 값으로 Firestore 를 만들고 그 flavor config 의 `functionsRegion` 을 맞춘다.
- 앱의 `functionsRegion` 과 함수의 `REGION` 이 어긋나면 빌드 · analyze 는 통과하지만 앱이 함수를 부를 때 `not-found` 로 실패한다 — Kakao · Naver · LINE 로그인과 회원탈퇴가 막힌다.
- 그래서 리전은 위저드로 바꾼다.

리전을 바꾸려면 이렇게 한다.
- Firestore 위치는 바뀌지 않는다.

1. `functions/src/shared/region.ts` · `lib/core/config/app_config.dart` 에 커밋하지 않은 변경이 없게 한다 — 있으면 위저드가 멈춘다.
2. `config/dev.json` 의 `functionsRegion` 을 새 리전으로 고친 뒤 `./setup.sh` 를 다시 실행한다.
   - 「위치 · Firestore」 단계가 세 곳의 값이 다르다고 알리고 `Functions 리전을 바꾸면 config/dev.json · functions/src/shared/region.ts · lib/core/config/app_config.dart 세 곳이 함께 바뀝니다.` 를 보인 뒤 리전을 고르게 한다.
   - 고른 값이 세 곳에 쓰인다.
3. 「Cloud Functions 배포」 단계가 새 리전에 함수를 배포한다.
   - 옛 리전의 함수는 위저드가 지우지 않는다 — Firebase 콘솔 Functions 의 「대시보드」 탭 함수 표에서 옛 리전의 함수(함수 이름 아래에 리전이 보인다)를 찾아 행 끝 「⋮」 의 「함수 삭제」 로 지운다.
4. 위저드 끝에 보이는 바뀐 추적 파일(`region.ts` · `app_config.dart`)을 확인하고 커밋한다.
5. stg · prod 는 다음 `./setup.sh --flavor stg` · `./setup.sh --flavor prod` 실행에서 그 flavor config 의 `functionsRegion` 이 새 값으로 맞춰지고, 함수가 새 리전에 배포된다.

### Kakao · Naver 는 flavor 마다 새 앱

Kakao · Naver 는 flavor 마다 콘솔 앱을 새로 만든다 — dev · stg · prod 의 키가 모두 달라야 하고, 검수도 앱마다 따로 받는다.
- dev 앱이 검수를 통과해도 prod 앱의 검수가 끝난 것은 아니다.
- 검수는 [로그인 수단 검수 · 인증](guide.md#로그인-수단-검수--인증) 에 있다.

1. 그 flavor 로 체크 목록을 열고 수단을 켠다 — 예: `./setup.sh --flavor prod --providers`.
2. 위저드가 값 표에 그 flavor 의 패키지명 · 번들 ID 같은 콘솔에 넣을 값과 `이번에 만들 콘솔 앱: prod 용 하나 — dev · stg 앱은 그 flavor 로 위저드를 실행할 때 따로 만듭니다` 를 보인다.
   - 그 값으로 콘솔에 새 앱을 만든다.
3. 새 앱의 키를 그 flavor 의 위저드에 넣는다.
   - 위저드는 그 flavor 의 설정과 그 Firebase 프로젝트에 키를 기록한다.
   - 다른 flavor 와 같은 키를 넣으면 `flavor 마다 새 콘솔 앱의 키를 넣으세요` 를 보이고 다시 묻는다.

- release 빌드는 release 키로 서명하므로, Kakao 앱의 Android 키 해시에는 release 키의 해시도 등록한다 — release 키는 [릴리스 서명(keystore)](guide.md#릴리스-서명keystore) 에서 만든다.
- 흔한 실수: dev 의 키를 prod 에 그대로 쓴다.
  - 검수를 받지 않은 dev 앱의 키로는 출시한 앱의 사용자가 로그인하지 못한다.

## 로그인 수단 끄기

켠 소셜 로그인 수단을 로그인 화면에서 빼려면 이 절을 따른다.
- 끄는 일도 위저드가 한다 — `config/<flavor>.json` 을 손으로 고치거나 배포된 함수를 손으로 지우지 않는다.
- 출시 뒤 이미 가입자가 있는 수단은 목록에서 빼지 않고 [Kill Switch 로 로그인 수단 막기](guide.md#kill-switch-로-로그인-수단-막기) 로 버튼만 숨긴다 — 목록에서 빼면 그 수단으로 가입한 사용자가 로그인 · 재인증 · 회원탈퇴를 할 수 없다.

**전제**

- [위저드 실행](#위저드-실행) 으로 그 flavor 의 처음 설정이 끝나 있다.
- 끌 수단이 [로그인 수단 켜기](#로그인-수단-켜기) 로 켜져 있다.

**단계**

1. 저장소 루트에서 체크 목록을 연다.
   - stg · prod 는 `--flavor stg` · `--flavor prod` 를 함께 준다.

   ```bash
   ./setup.sh --providers
   ```

2. 위저드가 `로그인 수단 — 이메일 로그인은 늘 켜져 있습니다` 아래에 번호 목록을 보인다 — 켜진 수단은 `1) [x] Google` 처럼 `[x]` 가 붙는다.
   - 번호를 묻는 질문에 **남길 수단의 번호만** 띄어 써서 입력한다.
   - 끌 수단의 번호를 빼면 그 수단이 꺼진다.
   - 소셜 로그인을 모두 끄려면 `0`(이메일만)을 입력한다.
3. 위저드가 뺀 수단의 가입자 수를 센다 — 화면에는 수단 이름과 개수만 보인다.
   - 여기서 아래 두 갈래로 나뉜다.

**가입자가 있으면** — 위저드는 로그인 수단 목록을 바꾸지 않고 아래 안내를 보인 뒤 끝난다. `<n>` · `<수단>` · `<토큰>` 에는 실제 값이 들어간다.

```text
<n>명이 <수단> 로그인으로 가입했습니다 — 빼면 이 사용자들이 로그인 · 재인증 · 회원탈퇴를 못 합니다
그래서 로그인 수단 목록(enabledAuthProviders)을 바꾸지 않았습니다.
앱에서 버튼만 숨기려면 Remote Config 에서 auth_provider_<토큰>_enabled 를 false 로 게시하세요 — … (위저드는 Remote Config 를 바꾸지 않습니다)
테스트 계정만 있는 개발 프로젝트라면 그 계정을 먼저 지운 뒤 다시 실행하세요
끝나면 ./setup.sh 를 다시 실행하세요 — 끝난 단계는 건너뜁니다.
```

`…` 자리에는 버튼을 숨기는 절차의 위치가 나온다.
- 그 절차는 [Kill Switch 로 로그인 수단 막기](guide.md#kill-switch-로-로그인-수단-막기) 에 있다 — 위저드는 Remote Config 를 바꾸지 않으므로 키 게시는 그 절차대로 직접 한다.

**켠 직후 끄는 개발 프로젝트** — 수단을 켜면 위저드의 「소셜 로그인 확인」 단계에서 그 수단으로 한 번 로그인하므로 테스트 계정이 생긴다.
- 그래서 켠 직후 끄면 위저드는 가입자가 있는 갈래로 가고, 안내 끝에 `테스트 계정만 있는 개발 프로젝트라면 그 계정을 먼저 지운 뒤 다시 실행하세요` 를 보인다.
- 가입자가 그 테스트 계정뿐이면 아래처럼 한다.

1. 테스트 계정을 지운다.
   - Google · Apple · Facebook — Firebase 콘솔에서 그 프로젝트를 열고 Authentication 의 「사용자」 탭에서 그 계정 행 끝 「⋮」 의 「계정 삭제」 로 지운다.
   - Kakao · Naver · LINE — 위저드는 이 셋의 가입자를 Firestore 의 가입 기록으로 센다.
     - 콘솔의 Authentication 사용자 목록에서만 지우면 그 기록이 남아 다시 가입자로 세어진다.
     - 앱에서 그 테스트 계정으로 로그인한 뒤 설정 → 「내 계정」 아래의 「회원탈퇴」 로 지운다 — 확인 칸(「계속하려면 "탈퇴"를 입력하세요.」)에 `탈퇴` 를 입력하고 「탈퇴」 를 누른다.
     - 연결된 서비스의 앱 연결을 해제하는 화면이 나오면 서비스마다 해제하거나 「건너뛰기」 를 누른 뒤(「모든 서비스를 해제하거나 건너뛰면 탈퇴할 수 있습니다.」) 「탈퇴」 를 누른다.
     - 그러면 계정과 가입 기록이 함께 지워진다.
     - 앱이 떠 있지 않으면 이 절의 「확인 방법」 의 명령으로 띄운다.
2. 체크 목록을 다시 연다.

   ```bash
   ./setup.sh --providers
   ```

3. 같은 번호를 다시 입력한다.
   - 이번에는 가입자가 0명이라 아래 「가입자가 없으면」 갈래로 간다.

**가입자가 없으면** — 위저드는 「지금 · 새 값 · 뺀 것 · 기록」 값 표를 보이고, `y` 를 받은 뒤 `config/<flavor>.json` 의 `enabledAuthProviders` 에서 그 수단을 뺀다. 그 수단의 키 · secret 값은 남긴다. 이어서 그 수단의 함수가 배포돼 있으면 이름을 보이고 지울지 따로 묻는다.

```text
뺀 로그인 수단의 함수 <n>개가 배포돼 있습니다 (<리전>): <함수 이름> · …
지우면 다시 켤 때 다시 배포합니다 — 키 · secret 값은 남깁니다.
지울까요? [y/N]
```

- 기본은 아니요다.
  - 아니요면 위저드가 `함수를 남겼습니다.` 를 보이고 함수는 그대로 남는다.
  - 남은 함수는 「Cloud Functions 배포」 단계가 끝남 줄에 `꺼진 로그인 수단의 함수 <n>개가 남아 있습니다` 로 개수와 지우는 명령을 알린다.
- `y` 면 위저드가 그 함수를 지우고 `함수 <n>개를 지웠습니다.` 를 보인다.
  - 이미 지워져 있으면 `지울 함수가 이미 지워져 있습니다 — 그대로 진행합니다.` 를 보이고 이어 간다.

그 뒤 위저드는 바뀐 목록으로 단계 목록을 다시 짜고 남은 단계를 이어 간다.

### 확인 방법

- `./setup.sh` 를 다시 실행하면 점검표의 「로그인 수단」 줄이 남은 수단만 보인다(예: `이메일 + Google · 바꾸기: ./setup.sh --providers`).
- 앱을 다시 빌드해 실행하면 로그인 화면에서 뺀 수단의 버튼이 사라진다.
  - `enabledAuthProviders` 는 빌드 때 앱에 들어가므로 실행 중인 앱에는 다시 빌드해야 반영된다.
  - 새로 받은 저장소에서 처음 빌드하면 코드 생성 파일이 없으므로 먼저 코드를 생성한다.

  ```bash
  fvm dart run build_runner build --delete-conflicting-outputs
  fvm flutter run --flavor dev --dart-define-from-file=config/dev.json
  ```

- 소셜 로그인을 모두 끄면 로그인 화면에는 「이메일로 계속」 만 남는다.

### 되돌리기

`./setup.sh --providers` 를 다시 실행해 끈 수단의 번호를 다시 넣는다.
- 키 · secret 값은 남아 있으므로 다시 입력하지 않아도 되고, 지운 함수는 「Cloud Functions 배포」 단계가 다시 배포한다.
- Kill Switch 로 숨긴 버튼을 되살리는 법은 [Kill Switch 로 로그인 수단 막기](guide.md#kill-switch-로-로그인-수단-막기) 에 있다.

### iOS 서명 — Apple 을 꺼도 필요한 capability

Apple 을 꺼도 iOS 실기기 서명에는 App ID 의 Sign in with Apple capability 가 필요하다.
- 자동 서명이면 Xcode 가 켠다.
- 수동 서명이면 Apple Developer → Certificates, Identifiers & Profiles → Identifiers 에서 앱의 App ID 를 열고 Sign in with Apple 을 켠다.

Apple 을 끈 앱도 이 capability 를 그대로 두는 이유는 다음과 같다.

- capability 는 추가 비용 없이 체크 한 번으로 켜진다.
- `ios/Runner/Runner.entitlements` 의 `com.apple.developer.applesignin` 은 provider 마다 나누지 않는다.
  - 빌드 설정 9곳이 같은 파일을 쓰고, 그 파일에 푸시 알림용 `aps-environment` 도 들어 있다.
- 파일을 나누면 `enabledAuthProviders` 와 xcconfig 두 곳을 서로 맞춰야 한다.
- 시뮬레이터 빌드에는 영향이 없다.

### App Store 심사 4.8 (Login Services) 주의

Apple 을 끄고 다른 소셜 로그인만 켜면 App Store Review Guidelines 4.8 의 「동등한 다른 로그인 수단」 요건을 검토해야 한다.
- 이메일/비밀번호 로그인이 그 요건을 채우는지는 Apple 이 심사에서 판단한다.
- 제출 전에 심사 시점의 원문을 확인한다 — <https://developer.apple.com/app-store/review/guidelines/#login-services>.
- 아래 인용은 4.8 원문 첫 문단과 세 조건이다.

> Apps that use a third-party or social login service (such as Facebook Login, Google Sign-In, Log in with X, Sign In with LinkedIn, Login with Amazon, or WeChat Login) to set up or authenticate the user’s primary account with the app must also offer as an equivalent option another login service with the following features:
>
> - the login service limits data collection to the user’s name and email address;
> - the login service allows users to keep their email address private as part of setting up their account; and
> - the login service does not collect interactions with your app for advertising purposes without consent.

## 위저드를 끝낸 뒤

위저드를 끝냈으면 아래 목록에서 할 일을 고른다.
- 절차는 각 링크의 절에 있다.

### 꼭 할 일

- 위저드 끝의 `release 빌드 전에 끝내야 할 일:` 목록을 처리한다 — 출시용 단계는 [알림(APNs) · App Check](#알림apns--app-check) 에서, release 빌드 준비는 [빌드 · 출시](guide.md#빌드--출시) 에서 한다.
- 위저드 끝에 보인 바뀐 추적 파일 목록을 확인하고 직접 커밋한다([위저드 실행](#위저드-실행) 의 「중단 · 다시 실행 · 실행 기록」).
- 출시 전에 검수 · 브랜드 자산 · 서명을 점검한다 — [출시 전 점검](guide.md#출시-전-점검).

### 필요할 때 할 일

- 홈 화면을 내 화면으로 바꿀 때 — [홈 화면 바꾸기](guide.md#홈-화면-바꾸기)
- 새 화면 · 기능을 더할 때 — [내 기능 추가하기](guide.md#내-기능-추가하기)
- 색 · 글꼴 같은 디자인을 바꿀 때 — [디자인 토큰 바꾸기](guide.md#디자인-토큰-바꾸기)
- 앱 아이콘을 바꿀 때 — [앱 아이콘 바꾸기](guide.md#앱-아이콘-바꾸기)
- 스플래시 화면을 바꿀 때 — [스플래시 바꾸기](guide.md#스플래시-바꾸기)
- 인증 · 재설정 메일을 킷이 보내게 할 때 — [인증 메일 발송 모드 켜고 끄기](guide.md#인증-메일-발송-모드-켜고-끄기)
- 메일 링크를 연 뒤 보이는 결과 페이지를 바꿀 때 — [인증 결과 페이지 바꾸기](guide.md#인증-결과-페이지-바꾸기)
- 알림 · Remote Config · Storage · Firestore 를 쓸 때 — [Firebase 서비스 쓰기](guide.md#firebase-서비스-쓰기)
- Crashlytics 대시보드에서 오류 보고를 볼 때 — [Crashlytics · Analytics](guide.md#crashlytics--analytics)
- release 서명 키를 만들 때 — [릴리스 서명(keystore)](guide.md#릴리스-서명keystore)
- 출시 뒤 로그인 수단을 막거나 알림을 보낼 때 — [앱 운영하기](guide.md#앱-운영하기)
- 킷의 새 판을 받을 때 — [킷 업데이트 반영](guide.md#킷-업데이트-반영)

## 문제가 생기면

위저드가 멈추거나 단계가 실패하면 `.setup/logs/` 의 가장 최근 실행 기록부터 본다 — 실행한 명령 · 종료 코드 · 명령 출력 · 단계 검사 판정이 들어 있고, 비밀 값은 가려져 있다.
- 원인을 고친 뒤 같은 명령을 다시 실행하면 끝난 단계는 검사만 하고 건너뛰고, 멈춘 단계부터 이어 간다.

### 위저드를 끝내기 전에 앱을 실행하면

**위저드를 끝까지 실행하면 해결된다.**
- 「앱 등록 · 설정 파일」 단계가 그 flavor 의 Firebase 설정 파일을 실제 값으로 만들고, 「앱 실행 · 로그인 확인」 단계가 앱을 다시 빌드해 띄운다.

위저드를 끝내기 전의 앱은 이렇게 동작한다.

- Firebase 설정 파일(`lib/core/firebase/firebase_options_<flavor>.dart` · `ios/config/<flavor>/GoogleService-Info.plist` · stg · prod 의 `android/app/src/<flavor>/google-services.json`)은 자리표시 값으로 저장소에 들어 있다.
  - 그래서 빌드와 analyze 는 통과하지만, 앱은 Firebase 를 초기화하지 못한 채 뜬다 — 인증 · Firestore · Crashlytics · Remote Config 같은 Firebase 기능이 모두 꺼진다.
  - 빌드가 된다고 Firebase 가 연결되지는 않는다.
- dev 의 Android 설정 파일 `android/app/src/dev/google-services.json` 은 저장소에 없고 「앱 등록 · 설정 파일」 단계가 만든다.
  - 그 전에는 `--flavor dev` Android 빌드가 실패한다.
- iOS 는 세 flavor 모두 자리표시 `GoogleService-Info.plist` 가 있어 빌드 단계를 통과한다.
- 위저드가 만든 실제 설정 파일은 이 컴퓨터에만 있다 — 저장소에 든 자리표시 파일은 skip-worktree 로, 나머지는 `.gitignore` 로 커밋 대상에서 빠진다.
  - 실제 값이 든 설정 파일을 `git add -f` 로 강제로 올리지 않는다.

### secret 값 확인하기

켠 로그인 수단으로 로그인할 때 오류 배너가 뜨면 그 수단의 secret 이 자리표시 값 `unset` 으로 남아 있는지 확인한다.
- secret 을 쓰는 수단과 secret 이름은 아래와 같다.

| 수단 | secret |
|---|---|
| Facebook | `FACEBOOK_APP_ID` · `FACEBOOK_APP_SECRET` |
| Kakao | `KAKAO_NATIVE_APP_KEY` · `KAKAO_ADMIN_KEY` |
| Naver | `NAVER_CLIENT_ID` · `NAVER_CLIENT_SECRET` |
| LINE | `LINE_CHANNEL_ID` · `LINE_CHANNEL_SECRET` |

- secret 이름마다 아래 명령을 실행한다.
  - `<your-project-id>` 는 `config/<flavor>.json` 의 `firebaseProjectId` 값이다.
  - 명령은 값을 화면에 출력하지 않고 `unset` 인지만 알려 준다 — `functions:secrets:access` 를 그대로 실행하면 값이 출력되므로 그 출력은 공유하지 않는다.

  ```bash
  if v="$(firebase functions:secrets:access <secret 이름> --project <your-project-id> 2>&1)"; then
    if [ "$v" = unset ]; then echo 'unset — 실제 값을 등록한다'; else echo 'unset 이 아니다'; fi
  else
    printf '%s\n' "$v"
  fi
  unset v
  ```

- `unset` 이면 `./setup.sh --providers` 를 다시 실행하고, 체크 목록에서 Enter 로 지금 그대로 둔다.
  - 켠 수단의 단계가 다시 검사되어 `config/<flavor>.json` 의 값으로 secret 을 맞추고, 서버에만 두는 secret 이면 콘솔에서 받은 값을 다시 묻는다.
  - 옛 secret 버전을 쓰는 함수는 「Cloud Functions 배포」 단계가 다시 배포한다.

### 조직 계정 프로젝트에서 함수 배포가 막히면

조직(Google Workspace)에 속한 계정으로 만든 프로젝트는 조직 정책 두 가지 때문에 「Cloud Functions 배포」 단계가 막힐 수 있다.
- 위저드는 실패 사유 아래에 프로젝트 ID 를 채운 명령을 보이고, 프로젝트 역할과 조직 정책은 직접 바꾸지 않는다.

- **위저드가 `함수 빌드 계정에 역할이 없어 빌드가 실패했습니다` 를 보인다(배포 출력에 `Could not build the function due to a missing permission on the build service account` 가 있다).**
  - 2세대 함수는 기본 Compute 서비스 계정(`<프로젝트 번호>-compute@developer.gserviceaccount.com`)으로 빌드 · 실행하는데, 조직 정책 `iam.automaticIamGrantsForDefaultServiceAccounts` 가 걸린 프로젝트는 이 계정에 역할이 자동으로 붙지 않는다.
  - 프로젝트 IAM 을 바꿀 수 있는 계정(예: 프로젝트 소유자)으로 gcloud 에 로그인하고 아래 명령으로 이 계정에 역할 7개를 붙인다.

  ```bash
  N="$(gcloud projects describe <your-project-id> --format='value(projectNumber)')"
  for R in roles/cloudbuild.builds.builder roles/artifactregistry.writer roles/logging.logWriter roles/datastore.user roles/firebaseauth.admin roles/firebasecloudmessaging.admin roles/eventarc.eventReceiver; do
    gcloud projects add-iam-policy-binding <your-project-id> --member="serviceAccount:${N}-compute@developer.gserviceaccount.com" --role="$R" --condition=None --quiet --format=none
  done
  ```

  - 역할이 반영되기까지 몇 분 걸릴 수 있다 — 그 뒤 `./setup.sh` 를 다시 실행하면 빌드가 실패한 함수를 다시 배포한다.
- **위저드가 `조직 정책이 함수를 공개 호출(allUsers)할 수 없게 막고 있습니다` 를 보인다(배포 출력에 `Unable to set the invoker for the IAM policy` 가 있거나, 공개 호출을 붙이는 명령이 `FAILED_PRECONDITION` · `permitted customer` 로 실패한다).**
  - 조직 정책 `iam.allowedPolicyMemberDomains` 가 조직 밖 계정(`allUsers` 포함)에 역할을 주지 못하게 막는 것이다.
  - 조직 정책 관리자(`roles/orgpolicy.policyAdmin`)가 아니면 조직 관리자에게 이 프로젝트의 예외를 요청하거나, 조직에 속하지 않은 개인 Google 계정으로 만든 프로젝트를 쓴다.
  - 조직 정책 관리자이면 아래 명령으로 이 프로젝트에만 예외를 둔다 — 이 프로젝트는 조직 밖 계정에도 역할을 줄 수 있게 되고, 반영까지 최대 15분 걸린다.

  ```bash
  gcloud services enable orgpolicy.googleapis.com --project <your-project-id>
  printf 'name: projects/<your-project-id>/policies/iam.allowedPolicyMemberDomains\nspec:\n  rules:\n  - allowAll: true\n' > allowed-policy-member-domains.yaml
  gcloud org-policies set-policy allowed-policy-member-domains.yaml
  ```

  - 예외가 생긴 뒤 `./setup.sh` 를 다시 실행하면 이어진다.

### 그 밖의 문제

- **회원탈퇴 같은 보호된 기능이 debug 빌드에서 실패한다.**
  - App Check 디버그 토큰이 등록돼 있지 않은 것이다 — Android 로그에 `Error getting App Check token; using placeholder token instead` 가 보이면 이 경우다.
  - debug 빌드는 위저드가 만든 토큰(`config/<flavor>.json` 의 `appCheckDebugToken`)을 쓴다.
  - `./setup.sh` 를 다시 실행하면 「App Check 디버그 토큰」 단계가 그 토큰이 iOS · Android 앱에 등록돼 있는지 보고 빠진 앱에 다시 등록한다 — config 에 토큰이 없으면 새로 만들어 등록한다.
  - 그 뒤 앱을 다시 빌드해야 새 토큰이 들어간다.
  - `appCheckDebugToken` 을 비워 두면 앱이 설치마다 토큰을 만들어 로그에 출력하고, 앱 데이터를 지우거나(`adb shell pm clear <applicationId>`) 다시 설치하면 그 토큰이 바뀐다 — 비우지 말고 위저드가 만든 값을 쓴다.
- **로그인 수단의 키를 채우기 전에도 빌드 · 기동은 된다.**
  - 로그인 수단 키가 비어 있어도 Android · iOS 빌드와 앱 기동은 성공한다.
  - `enabledAuthProviders` 의 example 값이 빈 문자열이라 소셜 로그인 버튼은 보이지 않는다.
  - 끈 수단은 다른 앱과 겹칠 수 있는 URL scheme 을 등록하지 않고, `unset` 이 들어간 자리표시 scheme(Android 예: `unset.kakao.oauth`)이 그 자리에 들어간다.
  - `bash scripts/verify_placeholder_builds.sh <android|ios> <dev|stg|prod> [off|google|all]` 로 확인하고, 성공하면 마지막 줄이 `PLACEHOLDER-BUILD-OK <platform> <flavor> <case>` 다.
  - 이 스크립트는 `config/<flavor>.json` · `ios/Flutter/<flavor>.xcconfig` 를 읽지도 바꾸지도 않는다.
- **`config/<flavor>.json` 을 커밋하려 한다.**
  - 이 파일에는 본인 키가 들어 있어 `.gitignore` 가 막는다.
  - `git add -f` 로 강제로 올리지 않는다 — `git status --ignored config/` 로 ignored 상태인지 확인한다.
- **example 파일에 본인 키를 넣었다.**
  - `config/*.example.json` · `ios/Flutter/*.example.xcconfig` 는 자리표시 값 그대로 둔다.
  - 본인 값은 위저드가 만든 `config/<flavor>.json` · `ios/Flutter/<flavor>.xcconfig` 에만 들어간다.
- **빌드 명령에 다른 config 를 줬다.**
  - 앱은 `--dart-define-from-file=config/<flavor>.json` 으로 빌드한다(예: `fvm flutter run --flavor dev --dart-define-from-file=config/dev.json`).
  - example 파일로 빌드하면 Kakao · Facebook SDK 초기화가 실패하거나 Firebase 프로젝트가 맞지 않는다.
