#!/bin/bash
# Phase 12.1 R8.2 — 양방향 lint:
#   1. 코드의 모든 `Phase \d+` 참조가 ROADMAP.md 의 phase 와 매핑되는지 검증.
#   2. 코드의 모든 raw `TODO` 주석이 진실원 참조 (.planning/todos/pending/<file>.md
#      또는 ROADMAP.md) 를 포함하는지 검증.
# mismatch 시 exit 1 + 차이 요약 출력.
#
# starter-kit 정책: 외부 lint framework / GitHub Actions 미도입 (D-39 단순성).
# git pre-commit hook 으로만 강제 — 활성화는 사용자 선택 (docs/manual.md 참조).

set -euo pipefail

ROADMAP=".planning/ROADMAP.md"
SCAN_PATHS=("lib" "functions/src")
SCAN_FILES=("firestore.rules")
EXIT_CODE=0

if [ ! -f "$ROADMAP" ]; then
  echo "[FAIL] ROADMAP.md 미존재: $ROADMAP"
  exit 1
fi

# Step 1 — ROADMAP.md 의 phase 번호 set 추출 ("### Phase 12.1: ..." 형식, INSERTED suffix 무관).
roadmap_phases=$(grep -oE '^### Phase [0-9]+(\.[0-9]+)?' "$ROADMAP" | sed 's/^### Phase //' | sort -u)

if [ -z "$roadmap_phases" ]; then
  echo "[FAIL] ROADMAP.md 에서 phase 헤딩 미발견"
  exit 1
fi

# Step 2 — 코드의 "Phase NN" / "Phase NN.M" 참조 검증.
# scan target: lib/, functions/src/ (재귀), firestore.rules (단일 파일).
GREP_TARGETS=("${SCAN_PATHS[@]}" "${SCAN_FILES[@]}")

while IFS=: read -r file line text; do
  # 빈 라인 skip
  [ -z "${file:-}" ] && continue
  for ref in $(echo "$text" | grep -oE 'Phase [0-9]+(\.[0-9]+)?' | sed 's/Phase //' | sort -u); do
    if ! echo "$roadmap_phases" | grep -qx "$ref"; then
      echo "[FAIL] $file:$line — Phase $ref 가 ROADMAP.md 에 없음"
      EXIT_CODE=1
    fi
  done
done < <(grep -rn -E 'Phase [0-9]+(\.[0-9]+)?' "${GREP_TARGETS[@]}" --include='*.dart' --include='*.ts' --include='*.rules' 2>/dev/null || true)

# Step 3 — 코드의 TODO 주석 검증.
# 형식 통과: 같은 라인에 `ROADMAP.md` 또는 `.planning/todos/pending/` 포함.
# 형식 거부: TODO 만 있고 진실원 참조 없음 (raw TODO).
while IFS=: read -r file line text; do
  [ -z "${file:-}" ] && continue
  if echo "$text" | grep -qE 'TODO'; then
    if ! echo "$text" | grep -qE 'ROADMAP\.md|\.planning/todos/pending/'; then
      echo "[FAIL] $file:$line — raw TODO (진실원 참조 없음): $text"
      EXIT_CODE=1
    fi
  fi
done < <(grep -rn 'TODO' "${GREP_TARGETS[@]}" --include='*.dart' --include='*.ts' --include='*.rules' 2>/dev/null || true)

if [ $EXIT_CODE -eq 0 ]; then
  echo "[PASS] check_phase_refs.sh — Phase 참조 + TODO 진실원 양방향 일치"
else
  echo ""
  echo "fix 절차: ROADMAP.md 의 active phase 또는 .planning/todos/pending/ 의 todo 파일을 참조하도록 주석 갱신"
fi
exit $EXIT_CODE
