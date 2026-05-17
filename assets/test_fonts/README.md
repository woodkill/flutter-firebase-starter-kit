# Test-only Fonts

본 디렉토리는 **테스트 환경 전용** 폰트 자산을 보관한다. **production
`pubspec.yaml` 의 `fonts:` 단락에 미bundle** — 앱 binary 동봉 0.

## 자상 목록

| 파일 | 용도 | 라이센스 |
|------|------|---------|
| `Roboto-Medium.ttf` | golden test 의 Roboto Medium fixture (Google Sign-in label fontFamily) | Apache License 2.0 — `Roboto_LICENSE.txt` |

## 사유

production code 의 `_renderGoogleButton` 은 fontFamily 'Roboto' (Google CSS
verbatim) 사용. Android system 의 Roboto 가 default 매핑되지만, test env
(macOS host) 에서는 system fallback 의 weight 분기가 macOS 시스템 폰트 (SF
Pro / Helvetica) 로 우회 → Skia synthetic bold 발생 위험.

`assets/fonts/roboto/Roboto-VariableFont_wdth_wght.ttf` 가 production bundle
의 Roboto 단일 진실원이지만, 일부 legacy test fixture 가 명시적 weight binary
(Roboto-Medium.ttf) 를 FontLoader 에 직접 등록하는 패턴 사용.

## 미bundle 확인

`pubspec.yaml` 의 `fonts:` 단락에 본 디렉토리 entry 부재 → Flutter asset
bundler 가 무시. `flutter build apk --analyze-size` 검증 시 본 디렉토리 자상
0 bytes contribution.

## 갱신

본 디렉토리 자상은 test fixture — production behavior 영향 0. Roboto Medium
공식 binary 갱신 시 `Roboto_LICENSE.txt` 의 source URL 재방문 + Apache 2.0
attribution 보존 의무.
