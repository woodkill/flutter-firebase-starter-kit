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

### Kakao · Naver 는 flavor 마다 새 앱

## 로그인 수단 끄기

### iOS 서명 — Apple 을 꺼도 필요한 capability

### App Store 심사 4.8 (Login Services) 주의

## 위저드를 끝낸 뒤

## 문제가 생기면

### 위저드를 끝내기 전에 앱을 실행하면

### secret 값 확인하기
