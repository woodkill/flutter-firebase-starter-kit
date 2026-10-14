#!/bin/zsh
# 설정 위저드 진입점 — 저장소 루트에서 ./setup.sh 로 실행한다.
#
# macOS 인지 확인한 뒤 FVM 이 고정한 Dart 로 위저드(bin/setup.dart)를 실행한다.
# 받은 인자는 위저드에 그대로 넘긴다.
emulate -L zsh
set -eu

cd "${0:A:h}"

if [[ "$(uname -s)" != Darwin ]]; then
  print -r -- '이 위저드는 macOS 에서만 동작합니다.'
  exit 1
fi

exec fvm dart run bin/setup.dart "$@"
