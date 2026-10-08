# 킷 공개본 발행 (유지보수자 문서)

> 킷 사용자 문서가 아니다 — 킷 사용자는 공개 저장소의 새 판을 받기만 한다(`docs/manual.md`
> 「킷 업데이트 반영」). 공개본을 만들고 내보내는 일은 킷 유지보수자 작업이다.

배경 · 결정 · 실측은 아래 원본에 있고, 이 문서는 절차만 적는다.

- 공개 모델 · 결정 D-01~D-40 · 범위:
  `.planning/phases/17.4-kit-release-mirror-model/17.4-CONTEXT.md`(비공개 작업 일지 — mirror 에 없음)
- filter-repo 결정성 실험 · gitleaks · GitHub 설정 근거 · 함정 원문:
  `.planning/phases/17.4-kit-release-mirror-model/17.4-RESEARCH.md`(비공개 작업 일지 — mirror 에 없음)

`<ver>` 는 발행할 판 번호(`v` 없음 — 예: `1.0.0-rc.1`), `<TAG>` 는 `v<ver>` 다.

---

## 모델

- 공개 저장소 `woodkill/flutter-firebase-starter-kit`(기본 브랜치 `main`)는 비공개 저장소
  `woodkill/flutter_starter_kit`(`master`)를 origin 에서 fresh clone 해 `git filter-repo` 로 만든
  **증분 mirror** 다. 공개본은 손으로 고치지 않는다 — 고칠 것은 비공개 저장소에서 커밋하고
  스크립트로 다시 만든다.
- 결정적이다 — 같은 입력이면 같은 해시가 나오고, 비공개 쪽에 커밋을 더해도 앞서 발행한
  해시는 그대로 남는다. 그래서 릴리스마다 공개 `main` 은 fast-forward 로만 움직인다.
- 이력에서 가리는 것은 민감한 값뿐이다(D-01 · D-09) — 경로 제외 · blob 치환 · 커밋 메시지
  치환 규칙이 `.planning/release/` 에 있다. 민감하지 않은 정리(폴더 삭제 · 문서 이동 · 검사
  수정)는 비공개 저장소의 일반 커밋으로 HEAD 부터 고친다.
- 복사기가 `master` 를 `main` 으로 개명한다 — 커밋 해시는 바뀌지 않는다(D-27).
- 공개 `main` 은 릴리스 때만 움직이고 항상 어느 `v*` 태그와 같은 커밋이다(D-24). 긴급 수정도
  새 태그로 낸다.
- 비공개 저장소의 태그 · 다른 브랜치는 발행하지 않는다 — 공개 저장소에는 `main` 과 `v*`
  태그만 있다(D-18).
- 공개 저장소에서 PR 은 받지 않는다 — 다음 발행이 공개 이력을 다시 만들므로 반영할 수 없다.
  PR 이 오면 「발행 mirror — 반영 불가 · 이슈로 제안」 을 안내하고 닫는다(D-33). 이슈는 받는다.

## 준비

- 도구:
  - `git-filter-repo` — `brew install git-filter-repo`
  - `gitleaks` — `brew install gitleaks`(Homebrew core 공식 formula). 설정은 공개 루트
    `.gitleaks.toml` 하나다 — 기본 규칙(`useDefault = true`) + 최소 허용 목록(옛
    `ios/Podfile.lock` 의 CocoaPods 체크섬 줄만). `scan` 은 `--config` 없이 mirror 루트의 이
    파일을 읽는다. `.gitleaksignore` · `gitleaks:allow` 주석은 쓰지 않는다.
  - `gh` — `gh auth login` 으로 로그인해 둔다(`push` 뒤 단계 · Release · 저장소 설정).
  - `fvm` · `pnpm` · `jq` — `verify` 가 fresh clone 에서 Flutter · functions 를 돌린다.
- 비공개 저장소의 커밋을 모두 마친 뒤 `git push origin master` 를 한다. `mirror` 는 origin
  `master` 와 로컬 `master` 가 다르면 clone 전에 멈춘다(복사기의 원본은 언제나 origin 이다 — D-30).
- 환경변수(기본값은 실제 주소 — 테스트 · 리허설 때만 바꾼다):

  | 변수 | 기본값 | 쓰임 |
  |---|---|---|
  | `KIT_PUBLISH_ORIGIN` | `git@github.com:woodkill/flutter_starter_kit.git` | 복사기 원본(비공개 origin) |
  | `KIT_PUBLISH_PUBLIC` | `git@github.com:woodkill/flutter-firebase-starter-kit.git` | `check` 가 읽고 `push` 가 보내는 공개 저장소 |
  | `KIT_PUBLISH_WORK` | `<저장소>/build/publish` | 작업 디렉터리 — `<저장소>/build/` 아래 절대경로만 · `..` 금지 |
  | `KIT_PUBLISH_REPO` | `woodkill/flutter-firebase-starter-kit` | `release` 가 GitHub Release 를 만드는 저장소 |

  공개 쪽 주소(`KIT_PUBLISH_PUBLIC` · `KIT_PUBLISH_REPO`)가 `KIT_PUBLISH_ORIGIN` 과 같거나, 저장소
  이름이 `KIT_PUBLISH_ORIGIN` 또는 이 저장소의 `origin` remote 와 같으면 `check` · `push` ·
  `release` 가 원격을 보기 전에 멈춘다. `check` 의 첫 발행 판정(`first-publish`)은 공개 저장소의
  ref 가 0개일 때만이다 — `main` 이 없어도 다른 ref 가 있으면 멈춘다.

## 발행 단계

스크립트 하나(`scripts/publish_kit.sh`)를 단계별로 부른다. 순서는
`mirror → scan → verify → check → push → release` 다.

```bash
bash scripts/publish_kit.sh mirror          # origin master fresh clone → 이력 필터 → main 개명
bash scripts/publish_kit.sh scan            # 킷 불변식 10개 + gitleaks
bash scripts/publish_kit.sh verify          # mirror fresh clone 에서 analyze · 전체 Flutter 테스트 · Jest
bash scripts/publish_kit.sh check           # 공개 main · v* 태그가 재생성 main 의 조상인지
bash scripts/publish_kit.sh push            # 실행할 명령만 출력(dry-run)
bash scripts/publish_kit.sh push --apply    # 태그 생성 · main + 태그 원자 push(--atomic)
bash scripts/publish_kit.sh release         # Release 명령과 notes 파일만 준비(dry-run)
bash scripts/publish_kit.sh release --apply # GitHub Release 생성
```

각 단계 마지막 줄(sentinel):

| 단계 | 마지막 줄 |
|---|---|
| `mirror` | `MIRROR OK main=<해시> commits=<N>`(앞 줄 `tools: git=… filter-repo=…`) |
| `scan` | `SCAN OK main=<해시> gitleaks=0 invariants=10` |
| `verify` | `VERIFY OK main=<해시> flutter=pass jest=pass ios-goldens=<N\|skipped>` |
| `check` | `CHECK OK first-publish main=<해시>` 또는 `CHECK OK main=<해시> public-main=<해시> tags=<N>` |
| `push` | `DRY-RUN OK push tag=<TAG> main=<해시>` / `--apply` 면 `PUSH OK tag=<TAG> main=<해시>` |
| `release` | `DRY-RUN OK release tag=<TAG>` / `--apply` 면 `RELEASE OK tag=<TAG>` |

- 실패는 `FAIL: <사유>`(exit 1), 잘못된 인자는 사용법(exit 2)이다.
- 단계를 통과하면 `build/publish/<단계>.ok` 에 그때의 mirror `main` 해시를 쓴다. `push` 는
  `mirror` · `scan` · `verify` · `check` 의 표시가 **전부 지금 mirror `main` 해시와 같을 때만**
  열린다. `mirror` 를 다시 돌리면 해시가 바뀔 수 있으니 뒤 단계를 다시 통과시킨다. `release` 는
  같은 해시의 `push` 표시를 요구하고, CHANGELOG 의 해당 판 절(맨 아래 비교 링크 정의 제외)을
  `build/publish/release-notes-<ver>.md` 로 잘라 Release 본문으로 쓴다. rc 판은 pre-release 다.
- `push` · `release` 는 `--apply` 없이는 원격을 바꾸지 않는다. `push` 에는 강제 옵션이 없다 —
  공개 `main` 이 새 `main` 의 조상이 아니면 git 자체가 거부한다. `main` 과 태그는
  `git push --atomic` 한 번으로 보내므로 하나라도 거부되면 둘 다 반영되지 않는다(공개 `main` 이
  태그 없는 커밋에 머무는 창이 없다). 공개 저장소에 같은 태그가 이미
  있으면 같은 커밋일 때만 통과하고 태그 push 를 건너뛴다.
- `push` 는 `KIT_VERSION`(한 줄 semver)과 CHANGELOG 의 `## [<ver>] - YYYY-MM-DD` 절이 mirror
  `main` 에 있어야 한다 — 없으면 「릴리스 컷」 부터 한다.
- `verify` 는 mirror 를 `build/publish/verify/` 로 새로 clone 해 `fvm use` → `fvm flutter pub get`
  → build_runner → `fvm dart analyze` → `fvm flutter test --no-pub` → functions
  `pnpm install --frozen-lockfile` · lint · build · Jest 를 돈다. 단계 로그는
  `build/publish/verify-*.log` 다. macOS 에서는 gitignore 된 iOS golden(`*_ios.png` — `.gitignore`
  에 적힌 수만큼)을 이 트리에서 clone 으로 복사해 회귀까지 판정한다 — 복사하는 것은 이 PNG
  뿐이고 실 키 파일은 넘기지 않는다. 이 트리의 golden 수가 모자라면 macOS 에서 생성 · sign-off
  한 뒤 다시 돌린다.
- 인자 없이 실행하면 사용법과 마지막 줄
  `status: mirror=<ok|-> scan=<ok|-> verify=<ok|-> check=<ok|-> push=<ok|-> main=<해시|none>`
  만 낸다(파일을 만들지 않는다).
- 공개 저장소에서는 `.planning/release/` 가 없으므로 이 스크립트가 사용법만 내고 서브커맨드는
  멈춘다 — 킷을 fork 해 자기 킷을 내려면 규칙 파일 3종을 자기 비공개 저장소에 만든다.

## 릴리스 컷

판을 내기 전에 비공개 저장소에서 커밋 하나로 판 번호를 확정한다.

1. `CHANGELOG.md` 의 `## [Unreleased]` 아래 내용을 새 절 `## [<ver>] - YYYY-MM-DD` 로 옮기고,
   빈 `## [Unreleased]` 를 그 위에 남긴다. 사용자가 손봐야 하는 판이면 그 절 맨 앞에
   `### 사용자 조치` 를 둔다.
2. 파일 맨 아래 비교 링크 2줄을 갱신한다:
   `[Unreleased]: https://github.com/woodkill/flutter-firebase-starter-kit/compare/v<ver>...HEAD` ·
   `[<ver>]: https://github.com/woodkill/flutter-firebase-starter-kit/releases/tag/v<ver>`.
3. 루트 `KIT_VERSION` 에 `<ver>` 한 줄을 쓴다(`v` 없음).
4. 판 번호 규칙(D-19 · D-20 — CHANGELOG 머리의 「판 번호 규칙」 과 같은 기준):
   - merge 뒤 사용자가 손봐야 하는 판은 MAJOR 다(`### 사용자 조치` 가 있는 판).
   - 새 기능 · 새 로그인 수단은 MINOR, 수정만이면 PATCH 다.
   - 정식 판 전에는 phase 종결마다 `1.0.0-rc.N` 의 rc 번호만 올리고, Phase 19 뒤 `1.0.0` 을 낸다.
5. 커밋 → `git push origin master` → 「발행 단계」 를 `mirror` 부터 돈다.
6. `v1.0.0` 을 컷할 때는 README 머리의 pre-release 문장(`**판:**` 줄)과 저장소 About 설명의
   「개발 중(pre-release)」 표기를 지운다. README 문장은 컷 커밋에서 지우고, About 은
   `gh repo edit --description` 으로 바꾼다.

컷 커밋은 공개 파일(`CHANGELOG.md` · `KIT_VERSION`)을 바꾸므로 mirror 에서 살아남는다. 태그
대상은 비공개 HEAD 가 아니라 **mirror `main` tip** 이다 — `push` 가 그 커밋에 annotated 태그를
만든다(비공개 HEAD 가 작업 일지만 고친 커밋이면 mirror 에 대응 커밋이 없다).

## 첫 공개 절차

D-28 순서다 — 새 저장소를 비공개로 만들고 검수를 마친 뒤 마지막에 공개로 바꾼다. 아래
`gh` 명령은 유지보수자가 직접 실행한다(한 단계씩 결과를 확인하고 다음으로).

1. 「릴리스 컷」(`1.0.0-rc.1`) → `git push origin master` → `mirror` · `scan` · `verify` 통과.
   첫 공개에만 키 없는 빌드 게이트 `scripts/verify_placeholder_builds.sh`(3케이스)와 매뉴얼
   「킷 업데이트 반영」 절차 시뮬레이션도 통과시킨다(D-31 · D-39).
2. 비공개로 저장소를 만든다:

   ```bash
   gh repo create woodkill/flutter-firebase-starter-kit --private --disable-wiki -d "Flutter + Firebase starter kit (mirror)"
   ```

3. `bash scripts/publish_kit.sh check` → `CHECK OK first-publish main=<해시>`.
4. `bash scripts/publish_kit.sh push` 로 명령을 확인한 뒤 `bash scripts/publish_kit.sh push --apply`.
5. 기본 브랜치 · 기능 · template 플래그를 맞춘다(`gh repo create` 에는 Projects 를 끄는 옵션이
   없어 여기서 끈다):

   ```bash
   gh repo edit woodkill/flutter-firebase-starter-kit --default-branch main --enable-issues --enable-wiki=false --enable-projects=false --template
   ```

6. 실제 「Use this template」 를 한 번 해 본다 — 임시 저장소를 만들고 매뉴얼 「킷 업데이트
   반영」 의 문구 그대로 기준점 merge 까지 따라간 뒤, 임시 저장소는 GitHub 웹 콘솔(Settings →
   Danger Zone)에서 지운다(로그인 토큰에 `delete_repo` 권한이 없다):

   ```bash
   gh repo create <임시 이름> --template woodkill/flutter-firebase-starter-kit --private
   ```

7. `bash scripts/publish_kit.sh release` 로 notes 를 확인한 뒤 `bash scripts/publish_kit.sh release --apply`
   (rc 판은 pre-release 로 만들어진다).
8. 공개로 바꾼다(되돌릴 수 없는 단계):

   ```bash
   gh repo edit woodkill/flutter-firebase-starter-kit --visibility public --accept-visibility-change-consequences
   ```

9. 보호 규칙을 건다 — GitHub Free 는 비공개 저장소에 ruleset 이 없어 공개 뒤에 만든다.
   payload 는 `scripts/github/ruleset-main.json`(`main` 삭제 · 강제 갱신 금지) ·
   `scripts/github/ruleset-tags.json`(`v*` 태그 삭제 · 강제 갱신 · 이동 금지 — 생성은 허용)이고
   우회 대상은 없다(유지보수자 본인도 묶인다):

   ```bash
   gh api -X POST repos/woodkill/flutter-firebase-starter-kit/rulesets --input scripts/github/ruleset-main.json
   gh api -X POST repos/woodkill/flutter-firebase-starter-kit/rulesets --input scripts/github/ruleset-tags.json
   ```

10. secret scanning 과 push protection 을 켠다(공개 저장소 무료 · scanning 을 먼저 켠다):

    ```bash
    gh repo edit woodkill/flutter-firebase-starter-kit --enable-secret-scanning --enable-secret-scanning-push-protection
    ```

11. 조회로 확인한다:

    ```bash
    gh repo view woodkill/flutter-firebase-starter-kit --json visibility,isTemplate,defaultBranchRef,hasIssuesEnabled,hasWikiEnabled,hasProjectsEnabled
    gh ruleset list --repo woodkill/flutter-firebase-starter-kit
    gh release view v1.0.0-rc.1 --repo woodkill/flutter-firebase-starter-kit
    ```

공개 전환을 마지막 무리에 두는 이유: 공개된 이력은 복사된 뒤 회수할 수 없다 — 검수 · template
확인 · Release 를 비공개 상태에서 끝내야 문제가 나와도 저장소를 지우고 다시 시작할 수 있다.

두 번째 판부터는 「릴리스 컷」 → 「발행 단계」(`mirror` → `scan` → `verify` → `check` →
`push --apply` → `release --apply`)만 반복한다.

## 규칙 파일 동결

- 동결 대상: `.planning/release/` 의 규칙 3종(`mirror-exclude-paths.txt` ·
  `mirror-replace-text.txt` · `mirror-replace-message.txt`)과 스크립트의 mirror 레시피 블록
  (`# MIRROR-RECIPE-BEGIN` ~ `# MIRROR-RECIPE-END`). 네 가지의 sha256 이
  `.planning/release/rules.sha256` 에 있고 `mirror` 가 시작할 때 바이트로 비교한다.
- rc.1 발행 뒤에는 바꾸지 않는다 — 규칙 · 레시피가 한 글자라도 바뀌면 공개 이력 전체의 해시가
  달라져 사용자의 merge 기준점이 깨진다(D-12).
- `replace` 규칙 파일 2종에는 주석 · 빈 줄을 쓸 수 없다 — filter-repo 가 `#` 줄도 치환
  리터럴로 읽는다. 설명은 `mirror-exclude-paths.txt`(주석 지원)와 스크립트 머리에 둔다.
- rc.1 전에 의도해서 바꿨다면 동결본을 다시 만든다:

  ```bash
  bash scripts/publish_kit.sh rules-hash > .planning/release/rules.sha256
  ```

- 결정성 입력(전부 같아야 같은 해시가 나온다): 규칙 3종 · filter-repo 옵션 · 입력 ref
  (`--single-branch --no-tags` 로 `master` 하나) · filter-repo 버전 · git 버전. 두 버전은
  `mirror` 출력의 `tools:` 줄로 기록한다.
- `check` 가 불일치(`공개 main 이 재생성 이력에 없다` · `공개 태그 … 불일치`)를 내면 강제
  갱신하지 않는다 — 입력 중 무엇이 바뀌었는지 조사한다.

## 공개 뒤 민감 값을 찾았을 때

- 값을 폐기 · 회전한다. 공개 이력은 다시 쓰지 않는다 — 이미 복사된 이력은 지워도 남는다(D-13).
- 재발행 절차는 없다. 그래서 첫 공개 전 `scan` 을 전체 이력으로 돌린다.
- `scan` 이 `FAIL: gitleaks 가 <N>건을 찾았다` 로 끝나면 허용 목록을 넓히지 않는다 —
  `build/publish/gitleaks.json`(값은 가려져 있다)에서 규칙 · 파일 · 건수만 보고 판정한다.
  실 값으로 보이면 허용 목록에 넣지 않고 값을 폐기한다. 실 값이 아님이 확인된 묶음만 경로 +
  줄 모양으로 좁게 `.gitleaks.toml` 에 허용한다.

## 함정

- `flutter create .` 재실행 시 데스크톱 디렉터리 · `.metadata` 항목이 되살아난다 — 다시 지운다.
  `macos/` · `windows/` · `linux/` · `web/` 와 `.metadata` 의 해당 플랫폼 항목이다(모바일 전용 — D-02).
- GSD 의 `generate-claude-md` 를 다시 돌리면 `## Project` 블록이 `CLAUDE.md` 끝에 다시 붙는다 —
  지워도 된다. 내용은 항상 로드되는 `.claude/rules/project.md` 에 있다(D-04).
- origin 이 뒤처진 채 `mirror` — 로컬 커밋을 push 하지 않으면 옛 상태가 공개된다. `mirror` 가
  멈추면 `git push origin master` 뒤 다시 돌린다.
- filter-repo 는 fresh clone 이 아니면 아무것도 하지 않고 끝난다 — 스크립트가 commit-map 존재로
  잡는다. mirror 디렉터리에서 손으로 filter-repo 를 돌리지 않는다.
- 비공개 HEAD 가 작업 일지만 고친 커밋이면 mirror 에 대응 커밋이 없다 — 태그 대상은 언제나
  mirror `main` tip 이다.
- 이메일 치환 규칙은 커밋 메시지 전용이다 — blob 에 적용하면 테스트 픽스처의 주소가 바뀌어
  공개본 테스트가 깨진다.
- skip-worktree 2파일(`lib/core/firebase/firebase_options_dev.dart` ·
  `ios/config/dev/GoogleService-Info.plist`)에는 이 트리의 실 값이 있다. 작업 트리를 grep 해서
  공개 위생을 판정하지 않는다(검사 대상은 mirror 이력뿐). 킷이 이 파일을 고치면 사용자 merge 가
  멈춘다 — 매뉴얼 「킷 업데이트 반영」 의 충돌 풀기 절차가 필요한 MAJOR 변경이다.
- ruleset · push protection 을 비공개 상태에서 시도하면 실패한다(GitHub Free) — 공개 전환 뒤에 건다.
- 태그 ruleset 에 `creation` 을 넣거나 `main` ruleset 에 `update` 를 넣으면 우회 대상이 없는
  유지보수자도 발행할 수 없다 — payload 파일의 규칙 종류를 바꾸지 않는다.
- iOS golden 은 gitignore 라 fresh clone 에 없다 — `verify` 가 이 트리에서 복사한다. macOS 가
  아니면 `ios-goldens=skipped` 로 판정에서 빠진다.
