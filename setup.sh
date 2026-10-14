#!/bin/zsh
# 설정 위저드 진입점 — 저장소 루트에서 ./setup.sh 로 실행한다.
#
# 순서: macOS 확인 → Homebrew 확인(없으면 안내 후 종료) → FVM 확인(없으면 설치
# 명령을 보이고 입력이 터미널이고 y 를 받았을 때만 설치) → .fvmrc 가 고정한
# Flutter 판 설치 → FVM 의 Dart 로 위저드(bin/setup.dart) 실행.
# 받은 인자는 위저드에 그대로 넘긴다. 셸 설정 파일은 고치지 않는다 — PATH 설정은
# 안내만 한다.
emulate -L zsh
set -eu

cd "${0:A:h}"

if [[ "$(uname -s)" != Darwin ]]; then
  print -r -- '이 위저드는 macOS 에서만 동작합니다.'
  exit 1
fi

# Homebrew — 설치 · PATH 설정은 셸을 다시 열어야 하므로 안내 후 종료한다.
if ! command -v brew >/dev/null 2>&1; then
  brew_path=''
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$candidate" ]]; then
      brew_path="$candidate"
      break
    fi
  done
  if [[ -n "$brew_path" ]]; then
    print -r -- 'Homebrew 는 설치돼 있지만 이 셸의 PATH 에 없습니다.'
    print -r -- '아래 줄을 셸 설정 파일(예: ~/.zprofile)에 직접 넣고 새 터미널에서 다시 실행하세요:'
    print -r -- "  eval \"\$(${brew_path} shellenv)\""
  else
    print -r -- 'Homebrew 가 필요합니다. 아래 명령으로 설치하세요:'
    print -r -- '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    print -r -- '설치가 끝나면 설치기가 알려 주는 PATH 줄을 실행하고 새 터미널에서 다시 실행하세요.'
  fi
  exit 1
fi

# FVM — 입력이 터미널이고 y 를 받았을 때만 설치한다(Enter · 그 밖 · 입력 끝 = 아니요).
if ! command -v fvm >/dev/null 2>&1; then
  print -r -- 'FVM(Flutter 판 관리 도구)이 필요합니다. 실행할 명령:'
  print -r -- '  $ brew tap btwld/fvm'
  print -r -- '  $ brew install btwld/fvm/fvm'
  if [[ -t 0 ]] && read -q '?설치할까요? [y/N] '; then
    print
    brew tap btwld/fvm
    brew install btwld/fvm/fvm
    rehash
  else
    if [[ -t 0 ]]; then
      print
    fi
    print -r -- '설치하지 않았습니다 — 같은 명령을 다시 실행하면 이어집니다.'
    exit 1
  fi
fi

# Flutter — .fvmrc 의 판을 인자로 준다(인자 없이 설치하면 FVM 이 편집기 설정 파일을 고친다).
flutter_version=''
if [[ -r .fvmrc ]]; then
  flutter_version="$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .fvmrc | head -n 1)"
fi
if [[ -z "$flutter_version" ]]; then
  print -r -- '.fvmrc 에서 Flutter 판을 읽지 못했습니다 — 저장소 루트의 .fvmrc 에 flutter 판 값이 있어야 합니다.' >&2
  exit 1
fi
fvm install "$flutter_version"

exec fvm dart run bin/setup.dart "$@"
