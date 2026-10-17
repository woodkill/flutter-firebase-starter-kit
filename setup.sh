#!/bin/zsh
# 설정 위저드 진입점 — 저장소 루트에서 ./setup.sh 로 실행한다.
#
# 순서: macOS 확인 → Homebrew 확인(없으면 안내 후 종료) → FVM 확인(없으면 설치
# 명령을 보이고 입력이 터미널이고 y 를 받았을 때만 설치) → .fvmrc 가 고정한
# Flutter 판 설치 → 패키지 받기(fvm flutter pub get) → 터미널 상태 저장 →
# FVM 의 Dart 로 위저드(bin/setup.dart)를 자식으로 실행 → 끝나면(Ctrl-C 포함)
# 터미널 상태를 되돌리고 위저드의 종료 코드로 끝낸다.
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

# 패키지 — 갓 설치한 SDK 캐시와 clone 직후 저장소에는 위저드가 쓸 패키지가 없다.
# 출력은 그대로 화면에 흐른다. 실패하면 안내 한 줄을 더하고 같은 종료 코드로
# 끝낸다 — 위저드는 부르지 않는다.
fvm flutter pub get || {
  pub_get_status=$?
  print -r -- '패키지를 받지 못했습니다 — 위 출력을 확인한 뒤 같은 명령을 다시 실행하세요.' >&2
  exit $pub_get_status
}

# 위저드 — Ctrl-C 를 받으면 바로 끝나므로 숨김 입력 중이었다면 터미널 에코가
# 꺼진 채 남을 수 있고, bash 같은 셸은 스스로 되돌리지 않는다. 그래서 위저드를
# 자식으로 실행하고 끝나면(정상 · 오류 · INT · TERM) 저장해 둔 상태로 되돌린다.
# 입력이 터미널이 아니면(상태를 읽지 못하면) 저장도 복원도 하지 않는다.
saved_stty=''
saved_stty="$(stty -g 2>/dev/null)" || saved_stty=''

# 저장한 터미널 상태로 되돌린다 — 실패해도 stty 의 오류 줄만 보이고 종료 코드는
# 바꾸지 않는다. 두 번 불려도 같은 상태를 다시 쓸 뿐이다.
restore_terminal() {
  if [[ -n "$saved_stty" ]]; then
    stty "$saved_stty" || true
  fi
}

trap 'restore_terminal; exit 130' INT
trap 'restore_terminal; exit 143' TERM

wizard_status=0
fvm dart run bin/setup.dart "$@" || wizard_status=$?
restore_terminal
exit $wizard_status
