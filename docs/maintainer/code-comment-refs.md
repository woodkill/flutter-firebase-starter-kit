# 코드 주석의 phase 참조 · TODO 규칙 (유지보수자 문서)

> 킷 사용자 문서가 아니다 — 사용자 저장소에서는 이 검사가 건너뛴다([Git Hooks 활성화 (선택)](../guide.md#git-hooks-활성화-선택)).

---

## 검사가 하는 일

`scripts/check_phase_refs.sh` 는 코드 주석의 phase 참조와 `TODO` 주석을 진실원과 양방향으로
대조한다. 진실원은 `.planning/ROADMAP.md` 의 phase 머리(`### Phase <번호>: …`)와
`.planning/todos/pending/<file>.md` 의 todo 파일이다.

- **대상:** `lib/` · `functions/src/`(재귀) · `firestore.rules` 의 `*.dart` · `*.ts` ·
  `*.rules` 파일.
- **phase 참조:** 주석의 phase 번호마다 ROADMAP 에 같은 번호의 phase 머리가 있어야 한다.
  번호는 비교 전에 양쪽 모두 성분별 선행 0 을 뗀다(`09` 와 `9` 가 같다).
- **`TODO` 주석:** 같은 줄에 `ROADMAP.md` 또는 `.planning/todos/pending/` 인용이 있어야
  한다. 인용이 없는 `TODO` 는 실패다.
- **결과:** 어긋나면 `[FAIL] <파일>:<줄> — …` 줄을 내고 exit 1, 모두 맞으면 `[PASS]` 를
  낸다. `.planning/ROADMAP.md` 가 없는 트리(킷 사용자 저장소 · 공개본)에서는 `[SKIP]` 을
  내고 exit 0 이라, 공개본에서 hook 을 켜도 커밋이 막히지 않는다.

CI 는 두지 않고 git pre-commit hook 의 가드 4 로만 돌린다(hook 은 선택이다). 켜는 법은
[Git Hooks 활성화 (선택)](../guide.md#git-hooks-활성화-선택) 에 있다.

## 손으로 돌리기

hook 을 켜지 않고 한 번 확인할 때:

```bash
bash scripts/check_phase_refs.sh
```

## 규칙 예시

| TODO / Phase 참조 | Pass / Fail |
|-------------------|-------------|
| `// TODO: Phase 8 후속 — Crashlytics.recordError (.planning/todos/pending/...md)` | PASS (todo 파일 인용) |
| `// Phase 17 — see ROADMAP.md` | PASS (ROADMAP 인용) |
| `// Phase 09 — see ROADMAP.md` | PASS (0 채움 표기 — 번호 성분별 선행 0 을 떼고 비교하므로 Phase 9 와 같다) |
| `// TODO(phase-08): ...` | FAIL (raw — 진실원 미명시) |
| `// TODO: dedicated NotFoundScreen` | FAIL (raw — 진실원 미명시) |
| `// Phase 99 — see ROADMAP.md` | FAIL (Phase 99 가 ROADMAP 미존재) |

검사는 format 을 보지 않는다 — 커밋 전 `fvm dart format --output=none --set-exit-if-changed lib test bin tool` 를 따로 돌린다.
