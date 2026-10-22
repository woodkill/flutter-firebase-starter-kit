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

위저드를 처음 실행하기 전에 아래를 갖춘다. 개발 도구 대부분은 위저드가 확인하고 없으면 설치하므로, 사람이 미리 할 일은 계정 · 결제 수단 · Homebrew · Xcode 다.

**사람이 미리 갖출 것**

- **macOS 와 터미널 앱** — 위저드는 macOS 에서만 돈다. 개발자 도구가 한 번도 설치되지 않은 Mac 에서는 처음 `git clone` 을 실행할 때 macOS 가 Command Line Tools 설치 창을 띄운다 — 「설치」 를 누르고 끝나면 같은 `git clone` 명령을 다시 실행한다.
- **Homebrew** — 없으면 `./setup.sh` 가 설치 명령을 보이고 끝난다. 설치한 뒤 같은 명령을 다시 실행한다.
- **Xcode** — App Store 에서 설치한다. 없으면 위저드의 「Xcode 준비」 단계가 App Store 주소를 보이고 끝난다. 설치한 뒤 Xcode 를 한 번 열어 추가 구성 요소 설치를 마치고 `./setup.sh` 를 다시 실행한다. Xcode 선택 · 라이선스 · 첫 실행 준비 · iOS 시뮬레이터 런타임은 위저드가 진행한다 — sudo 비밀번호는 그 명령이 직접 묻는다.
- **Google 계정** — Firebase · Google Cloud 에 로그인할 계정이다. 처음 쓰는 계정이면 위저드 안내대로 약관에 동의한다([위저드 실행](#위저드-실행) 의 「사용자가 하는 일」).
- **결제 수단과 Blaze 요금제** — 위저드의 「결제 계정 (Blaze 요금제)」 단계가 열린 결제 계정을 골라 Firebase 프로젝트에 연결한다. 연결하면 프로젝트가 Blaze(종량제) 요금제로 바뀌고, 무료 사용량을 넘는 사용분이 그 결제 계정으로 청구된다 — 쓴 만큼 낸다. Cloud Functions 배포에 Blaze 가 필요하다. 요금은 [Firebase 가격 안내](https://firebase.google.com/pricing) 에서 확인한다. 열린 결제 계정이 없으면 위저드가 브라우저에서 결제 계정을 만든 뒤 Enter 를 누르라고 안내한다.
- **Apple Developer 계정** — Apple 로그인 · APNs(푸시 알림) · DeviceCheck · iOS 실기기 서명에 쓴다. Apple 로그인과 DeviceCheck 에는 Apple Developer 에서 만든 `.p8` 키가 필요하다.
- **켤 로그인 수단의 개발자 콘솔 계정** — Facebook · Kakao · Naver · LINE 은 그 회사의 개발자 콘솔에 앱을 등록한다. Google 은 Google 계정, Apple 은 Apple Developer 계정을 그대로 쓴다. 수단마다 필요한 것은 [켜는 순서와 수단별로 필요한 것](#켜는-순서와-수단별로-필요한-것) 에 있다.

**위저드가 확인하고 없으면 설치하는 것**

- **FVM 과 Flutter** — `setup.sh` 가 위저드를 띄우기 전에 FVM · `.fvmrc` 가 고정한 Flutter 판 · 패키지를 확인한다. FVM 이 없으면 설치 명령을 보이고 `y` 를 받았을 때만 설치한다.
- **개발 도구** — 「개발 도구」 단계가 Node(22 이상) · pnpm(10 이상) · Firebase CLI(15 이상) · gcloud · jq · ruby 의 xcodeproj · FlutterFire CLI 를 확인한다. 있으면 어디서 설치했든 그대로 쓰고, 없거나 판이 낮은 것만 설치 명령을 보인 뒤 확인을 받고 하나씩 설치한다 — Homebrew 로 설치하고, FlutterFire CLI 는 `fvm dart pub global activate` 로 설치한다. Functions 의존성(`pnpm -C functions install --frozen-lockfile`)은 「Cloud Functions 배포」 단계가 설치한다.

**Android 도구 · JDK**

- 위저드의 「앱 실행 · 로그인 확인」 단계는 iOS 시뮬레이터를 기본으로 앱을 띄운다. Android 기기나 에뮬레이터에서 돌리려면 Android 도구(Android SDK · 에뮬레이터)를 직접 설치한다 — 위저드는 Android 도구를 설치하지 않는다.
- JDK 는 Android 디버그 서명 키의 지문(SHA-1 · 키 해시)을 계산하는 데 쓰인다 — Google · Facebook · Kakao · LINE 콘솔에 넣는 Android 쪽 값이다. JDK 나 디버그 서명 키가 없으면 위저드는 지문 줄만 미루고 뒤 단계는 그대로 진행한다. 이때 `Android 도구(JDK)와 디버그 서명 키가 없어 지문을 계산하지 못했습니다 — Android 도구를 설치하고 Android 빌드를 한 번 한 뒤 ./setup.sh 를 다시 실행하면 지문을 보여 줍니다` 가 보인다.
- Firestore · Storage rules 시험(`functions/` 에서 `pnpm test:rules`)이 쓰는 Firebase 에뮬레이터도 JDK 가 있어야 돈다.

## 위저드 실행

> **처음 설정은 저장소 루트에서 `./setup.sh` 하나로 한다 — 설정 위저드가 단계를 차례로 진행하고, 사람만 할 수 있는 일은 그 자리에서 안내한다.**

위저드는 macOS 에서만 돈다. 먼저 [시작 전 준비](#시작-전-준비) 의 계정 · 도구를 갖춘다.

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

`setup.sh` 는 위저드를 띄우기 전에 Homebrew · FVM · `.fvmrc` 가 고정한 Flutter 판 · 패키지를 확인한다. Homebrew 가 없으면 설치 명령을 보이고 끝난다 — 설치한 뒤 같은 명령을 다시 실행한다. FVM 이 없으면 설치 명령을 보이고 `y` 를 받았을 때만 설치한다.

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

위저드는 개발 도구를 확인하고, 없는 도구는 확인을 받은 뒤 설치한다. 이어서 Xcode 를 준비하고, 앱 정체성을 정하고, CLI 에 로그인하고, Firebase 프로젝트를 만들거나 고르고, 결제 계정을 연결한다. Firestore · 기본 Storage bucket · 이메일 로그인 · 익명 로그인을 켜고, 앱을 등록해 설정 파일을 만들고, rules 를 배포하고, App Check 디버그 토큰을 등록하고, Cloud Functions 를 배포한다. 이어서 코드를 생성하고 dev flavor 앱을 실행해 로그인을 확인한다. 끝으로 출시용 단계 — App Check 의 Play Integrity · DeviceCheck 등록과 APNs 키 업로드 안내 — 를 진행한다. 출시용 단계는 「지금 안 함」 으로 미룰 수 있다.

`./setup.sh --providers` 로 수단을 켜면, 켠 수단마다 provider 콘솔에 넣을 값을 보여 주고, 콘솔에서 받은 키를 한 번 입력받아 설정에 기록한 뒤 함수를 배포하고, 앱에서 그 수단으로 로그인했는지 확인한다. 위저드가 채우는 설정 키는 [위저드가 채우는 설정 키](#위저드가-채우는-설정-키) 에 있다. 뺀 수단은 가입자 수를 세어, 가입자가 있으면 목록을 바꾸지 않고 Remote Config 로 버튼만 숨기는 방법을 안내한다([로그인 수단 끄기](#로그인-수단-끄기)).

- 위저드가 실행하는 명령은 화면에 그대로 보인다.
- 비용이 들거나 되돌릴 수 없는 선택은 값 표를 보여 주고 `y` 를 받은 뒤에만 진행한다.

**사용자가 하는 일**

- 처음 `git clone` 때 macOS 가 띄우는 Command Line Tools 설치 창을 확인한다.
- 브라우저에서 로그인한다. 처음 쓰는 Google 계정이면 위저드 안내대로 Google Cloud 콘솔에서 Google Cloud 약관에, Firebase 콘솔에서 프로젝트에 Firebase 를 추가하며 Firebase 약관에 동의한다. 애널리틱스를 켜 두면 같은 흐름에서 Google 애널리틱스 약관에도 동의한다.
- 결제 수단을 등록하고, Homebrew 와 Xcode 를 설치한다. sudo 비밀번호는 Xcode 준비 명령이 직접 묻는다 — 위저드는 비밀번호를 받지 않는다.
- 그 밖에는 위저드 질문에 답하고, 실행된 앱에서 가입한 뒤 인증 메일의 링크를 연다.
- 로그인 수단을 켜면 그 provider 의 개발자 콘솔에 앱을 등록하고 위저드가 보여 주는 값을 넣은 뒤 키를 받아 온다.
- Apple 로그인과 DeviceCheck 에는 Apple Developer 에서 만든 `.p8` 키를, Apple 로그인에는 Services ID 도 준비한다. APNs 키는 Firebase 콘솔에 직접 올린다([알림(APNs) · App Check](#알림apns--app-check)).
- prod 의 Play Integrity 에는 Play 에 앱을 올린 뒤 Play 앱 서명 키의 SHA-256 을 입력한다.

**앱 아이콘 단계**

켠 수단 가운데 콘솔에 앱 아이콘 칸이 있는 수단(Naver · Kakao · LINE · Facebook · Google)이 있으면 위저드가 원본 이미지 경로를 묻는다.

1. 정사각 · 1024x1024 이상 이미지 하나를 준비한다(PNG · JPEG · HEIC 등 — PDF · SVG 같은 벡터는 받지 않는다).
2. 위저드가 경로를 물으면 Finder 에서 그 파일을 터미널 창으로 끌어다 놓는다 — 경로가 입력된다. 빈 값으로 답하면 「지금 안 함」 으로 미룬다. 정사각이 아니거나 작은 이미지는 까닭을 보이고 경로를 다시 묻는다.
3. 위저드가 provider 마다 콘솔 규격의 PNG 를 `.setup/icons/` 에 만들고 그 폴더를 Finder 로 연 뒤, provider 의 값 표에 파일 경로를 보인다.
4. provider 콘솔의 파일 선택 창에서 ⌘⇧G 로 `.setup/icons` 경로를 붙여 넣거나, 열린 Finder 창에서 파일을 끌어다 놓아 올린다. Naver 는 로고가 없으면 콘솔에서 앱이 저장되지 않는다.

아이콘을 바꾸려면 `.setup/icons` 를 지우고 위저드를 다시 실행한다.

**중단 · 다시 실행 · 실행 기록**

- 언제든 Ctrl-C 로 끝낼 수 있다. 터미널 상태는 `setup.sh` 가 되돌린다.
- 단계가 실패하면 「다시 시도」 와 「멈춤」 가운데 고른다. 멈추거나 끝낸 뒤에는 같은 명령을 다시 실행하면 이어진다.
- 위저드 밖에서 할 일(콘솔 작업 · 도구 설치 등)을 안내하고 끝났으면, 그 일을 마친 뒤 `./setup.sh` 를 다시 실행한다.
- 다시 실행하면 끝난 단계는 검사만 하고 건너뛰고, 킷 새 판에서 생긴 config 키를 채운다.
- 실행 기록은 실행마다 `.setup/logs/` 에 파일 하나로 남는다 — 화면 출력 · 입력한 답 · 실행한 명령 · 종료 코드 · 명령 출력 · REST 요청과 응답 · 단계 검사 판정이 들고, 비밀 값은 가린 채 남는다. 폴더와 파일은 소유자만 열 수 있고, `.setup/` 은 `.gitignore` 에 들어 있어 저장소에 커밋되지 않는다.
- 할 수 있는 단계를 모두 지나면, 미룬 일과 위저드가 확인할 수 없는 일이 「release 빌드 전에 끝내야 할 일」 목록으로 보인다.
- 끝에 위저드가 바꾼 추적 파일 목록과 커밋 명령을 보인다. 위저드는 스테이징 · 커밋 · push 를 하지 않는다 — 목록을 확인한 뒤 직접 커밋한다. 다음에 할 일은 [위저드를 끝낸 뒤](#위저드를-끝낸-뒤) 에 있다.

### 위저드가 채우는 설정 키

위저드는 `config/<flavor>.json`(dev 면 `config/dev.json`)을 example 파일에서 만들고 아래 키를 채운다. 손으로 고칠 일은 드물고, 킷 새 판에서 키가 늘면 위저드를 다시 실행해 채운다.

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

### 켜는 순서와 수단별로 필요한 것

### Google 로그인 켜기

### Apple 로그인 켜기

### Facebook 로그인 켜기

### Kakao 로그인 켜기

### Naver 로그인 켜기

### LINE 로그인 켜기

### Kakao · Naver · LINE 서명 권한(Token Creator)

### 로그인 수단에서 이메일 받기

## 알림(APNs) · App Check

### APNs 인증 키 올리기

### App Check 등록 확인

## stg · prod 설정

dev 와 따로 쓰는 stg · prod 환경이 필요하면 이 절을 따른다. flavor 마다 Firebase 프로젝트를 따로 쓰고, 위저드가 그 flavor 에 dev 와 같은 흐름을 적용한다.

**전제**

- dev 의 처음 설정이 끝나 있다([위저드 실행](#위저드-실행)). Functions 리전은 dev 실행이 정한다(아래 「Functions 리전」).

**단계**

```bash
./setup.sh --flavor stg
./setup.sh --flavor prod
```

- 위저드가 그 flavor 의 Firebase 프로젝트를 만들거나 고르는 것부터 dev 와 같은 흐름을 적용한다. 그 flavor 의 사용자 설정 파일(`config/<flavor>.json` · `ios/Flutter/<flavor>.xcconfig`)을 example 파일에서 만들어 채운다.
- 앱 이름 · Bundle ID 접미사는 flavor 마다 다르다 — example 값은 dev `StarterKit Dev` · `.dev`, stg `StarterKit Stg` · `.stg`, prod `StarterKit` · 빈 접미사다. 그래서 세 flavor 의 앱을 한 기기에 같이 설치할 수 있다.
- 로그인 수단은 flavor 마다 따로 켠다 — `./setup.sh --flavor prod --providers` 처럼 `--providers` 를 함께 준다. 켤 수단의 콘솔 앱도 flavor 마다 따로 만든다([Kakao · Naver 는 flavor 마다 새 앱](#kakao--naver-는-flavor-마다-새-앱)).
- 같은 명령을 다시 실행하면 그 flavor 에서 끝난 단계는 검사만 하고 건너뛴다.

**Functions 리전**

Cloud Functions 리전은 dev 처음 설정의 「위치 · Firestore」 단계에서 Firestore 위치와 함께 한 번 고른다(기본 `asia-northeast3` · 서울). 위저드는 고른 값을 세 곳에 같이 쓴다.

| 위치 | 값 |
|---|---|
| `config/<flavor>.json` 의 `functionsRegion` | 앱이 부를 리전 |
| `functions/src/shared/region.ts` 의 `REGION` | 함수를 배포할 리전 |
| `lib/core/config/app_config.dart` | `functionsRegion` 이 없을 때 앱이 쓰는 기본값 |

리전은 모든 flavor 가 함께 쓴다. stg · prod 는 리전을 묻지 않고 `dev 와 같은 위치 — Functions 리전은 모든 flavor 가 함께 씁니다.` 를 보인 뒤 `region.ts` 의 값으로 Firestore 를 만들고 그 flavor config 의 `functionsRegion` 을 맞춘다. 앱의 `functionsRegion` 과 함수의 `REGION` 이 어긋나면 빌드 · analyze 는 통과하지만 앱이 함수를 부를 때 `not-found` 로 실패한다 — Kakao · Naver · LINE 로그인과 회원탈퇴가 막힌다. 그래서 리전은 위저드로 바꾼다.

리전을 바꾸려면 이렇게 한다. Firestore 위치는 바뀌지 않는다.

1. `functions/src/shared/region.ts` · `lib/core/config/app_config.dart` 에 커밋하지 않은 변경이 없게 한다 — 있으면 위저드가 멈춘다.
2. `config/dev.json` 의 `functionsRegion` 을 새 리전으로 고친 뒤 `./setup.sh` 를 다시 실행한다. 「위치 · Firestore」 단계가 세 곳의 값이 다르다고 알리고 `Functions 리전을 바꾸면 config/dev.json · functions/src/shared/region.ts · lib/core/config/app_config.dart 세 곳이 함께 바뀝니다.` 를 보인 뒤 리전을 고르게 한다. 고른 값이 세 곳에 쓰인다.
3. 「Cloud Functions 배포」 단계가 새 리전에 함수를 배포한다. 옛 리전의 함수는 위저드가 지우지 않는다 — Firebase 콘솔 [[LABEL: Firebase — Functions 함수 목록]] 에서 옛 리전의 함수를 지운다.
4. 위저드 끝에 보이는 바뀐 추적 파일(`region.ts` · `app_config.dart`)을 확인하고 커밋한다.
5. stg · prod 는 다음 `./setup.sh --flavor stg` · `./setup.sh --flavor prod` 실행에서 그 flavor config 의 `functionsRegion` 이 새 값으로 맞춰지고, 함수가 새 리전에 배포된다.

### Kakao · Naver 는 flavor 마다 새 앱

Kakao · Naver 는 flavor 마다 콘솔 앱을 새로 만든다 — dev · stg · prod 의 키가 모두 달라야 하고, 검수도 앱마다 따로 받는다. dev 앱이 검수를 통과해도 prod 앱의 검수가 끝난 것은 아니다. 검수는 [로그인 수단 검수 · 인증](guide.md#로그인-수단-검수--인증) 에 있다.

1. 그 flavor 로 체크 목록을 열고 수단을 켠다 — 예: `./setup.sh --flavor prod --providers`.
2. 위저드가 값 표에 그 flavor 의 패키지명 · 번들 ID 같은 콘솔에 넣을 값과 `이번에 만들 콘솔 앱: prod 용 하나 — dev · stg 앱은 그 flavor 로 위저드를 실행할 때 따로 만듭니다` 를 보인다. 그 값으로 콘솔에 새 앱을 만든다.
3. 새 앱의 키를 그 flavor 의 위저드에 넣는다. 위저드는 그 flavor 의 설정과 그 Firebase 프로젝트에 키를 기록한다. 다른 flavor 와 같은 키를 넣으면 `flavor 마다 새 콘솔 앱의 키를 넣으세요` 를 보이고 다시 묻는다.

- release 빌드는 release 키로 서명하므로, Kakao 앱의 Android 키 해시에는 release 키의 해시도 등록한다 — release 키는 [릴리스 서명(keystore)](guide.md#릴리스-서명keystore) 에서 만든다.
- 흔한 실수: dev 의 키를 prod 에 그대로 쓴다. 검수를 받지 않은 dev 앱의 키로는 출시한 앱의 사용자가 로그인하지 못한다.

## 로그인 수단 끄기

켠 소셜 로그인 수단을 로그인 화면에서 빼려면 이 절을 따른다. 끄는 일도 위저드가 한다 — `config/<flavor>.json` 을 손으로 고치거나 배포된 함수를 손으로 지우지 않는다. 출시 뒤 이미 가입자가 있는 수단은 목록에서 빼지 않고 [Kill Switch 로 로그인 수단 막기](guide.md#kill-switch-로-로그인-수단-막기) 로 버튼만 숨긴다 — 목록에서 빼면 그 수단으로 가입한 사용자가 로그인 · 재인증 · 회원탈퇴를 할 수 없다.

**전제**

- [위저드 실행](#위저드-실행) 으로 그 flavor 의 처음 설정이 끝나 있다.
- 끌 수단이 [로그인 수단 켜기](#로그인-수단-켜기) 로 켜져 있다.

**단계**

1. 저장소 루트에서 체크 목록을 연다. stg · prod 는 `--flavor stg` · `--flavor prod` 를 함께 준다.

   ```bash
   ./setup.sh --providers
   ```

2. 위저드가 `로그인 수단 — 이메일 로그인은 늘 켜져 있습니다` 아래에 번호 목록을 보인다 — 켜진 수단은 `1) [x] Google` 처럼 `[x]` 가 붙는다. 번호를 묻는 질문에 **남길 수단의 번호만** 띄어 써서 입력한다. 끌 수단의 번호를 빼면 그 수단이 꺼진다. 소셜 로그인을 모두 끄려면 `0`(이메일만)을 입력한다.
3. 위저드가 뺀 수단의 가입자 수를 센다 — 화면에는 수단 이름과 개수만 보인다. 여기서 아래 두 갈래로 나뉜다.

**가입자가 있으면** — 위저드는 로그인 수단 목록을 바꾸지 않고 아래 안내를 보인 뒤 끝난다. `<n>` · `<수단>` · `<토큰>` 에는 실제 값이 들어간다.

```text
<n>명이 <수단> 로그인으로 가입했습니다 — 빼면 이 사용자들이 로그인 · 재인증 · 회원탈퇴를 못 합니다
그래서 로그인 수단 목록(enabledAuthProviders)을 바꾸지 않았습니다.
앱에서 버튼만 숨기려면 Remote Config 에서 auth_provider_<토큰>_enabled 를 false 로 게시하세요 — … (위저드는 Remote Config 를 바꾸지 않습니다)
테스트 계정만 있는 개발 프로젝트라면 그 계정을 먼저 지운 뒤 다시 실행하세요
끝나면 ./setup.sh 를 다시 실행하세요 — 끝난 단계는 건너뜁니다.
```

`…` 자리에는 버튼을 숨기는 절차의 위치가 나온다. 그 절차는 [Kill Switch 로 로그인 수단 막기](guide.md#kill-switch-로-로그인-수단-막기) 에 있다 — 위저드는 Remote Config 를 바꾸지 않으므로 키 게시는 그 절차대로 직접 한다.

**켠 직후 끄는 개발 프로젝트** — 수단을 켜면 위저드의 「소셜 로그인 확인」 단계에서 그 수단으로 한 번 로그인하므로 테스트 계정이 생긴다. 그래서 켠 직후 끄면 위저드는 가입자가 있는 갈래로 가고, 안내 끝에 `테스트 계정만 있는 개발 프로젝트라면 그 계정을 먼저 지운 뒤 다시 실행하세요` 를 보인다. 가입자가 그 테스트 계정뿐이면 아래처럼 한다.

1. 테스트 계정을 지운다.
   - Google · Apple · Facebook — Firebase 콘솔에서 그 프로젝트를 열고 [[LABEL: Firebase — Authentication 사용자 목록 메뉴]] 에서 그 계정을 지운다.
   - Kakao · Naver · LINE — 위저드는 이 셋의 가입자를 Firestore 의 가입 기록으로 센다. 콘솔의 Authentication 사용자 목록에서만 지우면 그 기록이 남아 다시 가입자로 세어진다. 앱에서 그 테스트 계정으로 로그인한 뒤 「설정」 의 「회원탈퇴」 로 지운다 — 확인 칸에 `탈퇴` 를 입력하면 계정과 가입 기록이 함께 지워진다.
2. 체크 목록을 다시 연다.

   ```bash
   ./setup.sh --providers
   ```

3. 같은 번호를 다시 입력한다. 이번에는 가입자가 0명이라 아래 「가입자가 없으면」 갈래로 간다.

**가입자가 없으면** — 위저드는 「지금 · 새 값 · 뺀 것 · 기록」 값 표를 보이고, `y` 를 받은 뒤 `config/<flavor>.json` 의 `enabledAuthProviders` 에서 그 수단을 뺀다. 그 수단의 키 · secret 값은 남긴다. 이어서 그 수단의 함수가 배포돼 있으면 이름을 보이고 지울지 따로 묻는다.

```text
뺀 로그인 수단의 함수 <n>개가 배포돼 있습니다 (<리전>): <함수 이름> · …
지우면 다시 켤 때 다시 배포합니다 — 키 · secret 값은 남깁니다.
지울까요? [y/N]
```

- 기본은 아니요다. 아니요면 위저드가 `함수를 남겼습니다.` 를 보이고 함수는 그대로 남는다. 남은 함수는 「Cloud Functions 배포」 단계가 끝남 줄에 `꺼진 로그인 수단의 함수 <n>개가 남아 있습니다` 로 개수와 지우는 명령을 알린다.
- `y` 면 위저드가 그 함수를 지우고 `함수 <n>개를 지웠습니다.` 를 보인다. 이미 지워져 있으면 `지울 함수가 이미 지워져 있습니다 — 그대로 진행합니다.` 를 보이고 이어 간다.

그 뒤 위저드는 바뀐 목록으로 단계 목록을 다시 짜고 남은 단계를 이어 간다.

### 확인 방법

- `./setup.sh` 를 다시 실행하면 점검표의 「로그인 수단」 줄이 남은 수단만 보인다(예: `이메일 + Google · 바꾸기: ./setup.sh --providers`).
- 앱을 다시 빌드해 실행하면 로그인 화면에서 뺀 수단의 버튼이 사라진다. `enabledAuthProviders` 는 빌드 때 앱에 들어가므로 실행 중인 앱에는 다시 빌드해야 반영된다.

  ```bash
  fvm flutter run --flavor dev --dart-define-from-file=config/dev.json
  ```

- 소셜 로그인을 모두 끄면 로그인 화면에는 「이메일로 계속」 만 남는다.

### 되돌리기

`./setup.sh --providers` 를 다시 실행해 끈 수단의 번호를 다시 넣는다. 키 · secret 값은 남아 있으므로 다시 입력하지 않아도 되고, 지운 함수는 「Cloud Functions 배포」 단계가 다시 배포한다. Kill Switch 로 숨긴 버튼을 되살리는 법은 [Kill Switch 로 로그인 수단 막기](guide.md#kill-switch-로-로그인-수단-막기) 에 있다.

### iOS 서명 — Apple 을 꺼도 필요한 capability

Apple 을 꺼도 iOS 실기기 서명에는 App ID 의 Sign in with Apple capability 가 필요하다. 자동 서명이면 Xcode 가 켠다. 수동 서명이면 Apple Developer → Certificates, Identifiers & Profiles → Identifiers 에서 앱의 App ID 를 열고 Sign in with Apple 을 켠다.

Apple 을 끈 앱도 이 capability 를 그대로 두는 이유는 다음과 같다.

- capability 는 추가 비용 없이 체크 한 번으로 켜진다.
- `ios/Runner/Runner.entitlements` 의 `com.apple.developer.applesignin` 은 provider 마다 나누지 않는다. 빌드 설정 9곳이 같은 파일을 쓰고, 그 파일에 푸시 알림용 `aps-environment` 도 들어 있다.
- 파일을 나누면 `enabledAuthProviders` 와 xcconfig 두 곳을 서로 맞춰야 한다.
- 시뮬레이터 빌드에는 영향이 없다.

### App Store 심사 4.8 (Login Services) 주의

Apple 을 끄고 다른 소셜 로그인만 켜면 App Store Review Guidelines 4.8 의 「동등한 다른 로그인 수단」 요건을 검토해야 한다. 이메일/비밀번호 로그인이 그 요건을 채우는지는 Apple 이 심사에서 판단한다. 제출 전에 심사 시점의 원문을 확인한다 — <https://developer.apple.com/app-store/review/guidelines/#login-services>. 아래 인용은 4.8 원문 첫 문단과 세 조건이다.

> Apps that use a third-party or social login service (such as Facebook Login, Google Sign-In, Log in with X, Sign In with LinkedIn, Login with Amazon, or WeChat Login) to set up or authenticate the user’s primary account with the app must also offer as an equivalent option another login service with the following features:
>
> - the login service limits data collection to the user’s name and email address;
> - the login service allows users to keep their email address private as part of setting up their account; and
> - the login service does not collect interactions with your app for advertising purposes without consent.

## 위저드를 끝낸 뒤

## 문제가 생기면

### 위저드를 끝내기 전에 앱을 실행하면

### secret 값 확인하기
