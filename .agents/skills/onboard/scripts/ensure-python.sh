#!/bin/bash
# 문서 작업(PPT·엑셀·PDF)용 Python 준비 — macOS. 묻지 않고 사용자 범위에만 설치한다(관리자 권한 불필요)
#   bash .agents/skills/onboard/scripts/ensure-python.sh [--workspace <폴더>] [--quiet]
# 순서: 1) 이미 있는 Python(Codex 런타임 → 전에 만든 workmate Python → Homebrew → 개발자 도구)에 패키지가 다 있으면 그대로 쓴다
#       2) Python은 있는데 패키지만 없으면 pip --user로 넣는다(Codex 런타임은 앱이 관리하므로 건드리지 않는다)
#       3) 그래도 없으면 uv(사용자 폴더 실행 파일 하나)로 Python과 패키지를 ~/.workmate/py에 설치한다
# 결과는 <업무 공간>/memory/env.md에 적는다. 실패해도 멈추지 않는다(종료 코드 0, 마지막 줄에 결과 한 줄).
# 개발자 도구(Xcode CLT)가 없으면 /usr/bin/python3을 부르지 않는다(설치 창이 뜬다).

WS=''; QUIET=''
while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WS="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    *) shift ;;
  esac
done
[ -n "$WS" ] || WS="$(cd "$(dirname "$0")/../../../.." && pwd)"
say() { [ -n "$QUIET" ] || printf '  %s\n' "$1"; }
has_clt() { xcode-select -p >/dev/null 2>&1; }

PKGS='python-pptx openpyxl pypdf Pillow'
CHECK='import pptx, openpyxl, pypdf, PIL'
RUNTIME="$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
BASE="$HOME/.workmate"
VENV="$BASE/py"
VENVPY="$VENV/bin/python"
export UV_NATIVE_TLS=1 PIP_DISABLE_PIP_VERSION_CHECK=1

test_py() {   # 패키지까지 다 있으면 ok, 실행만 되면 bare, 안 되면 빈 값
  [ -n "$1" ] && [ -x "$1" ] || { echo ''; return; }
  if [ "$1" = /usr/bin/python3 ] && ! has_clt; then echo ''; return; fi
  "$1" -c 'import sys' </dev/null >/dev/null 2>&1 || { echo ''; return; }
  if "$1" -c "$CHECK" </dev/null >/dev/null 2>&1; then echo ok; else echo bare; fi
}

CANDS=("$RUNTIME" "$VENVPY" /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3)
RESULT=''; HOW=''; TRIES=''
for p in "${CANDS[@]}"; do
  [ "$(test_py "$p")" = ok ] && { RESULT="$p"; HOW='이미 있음'; break; }
done
if [ -z "$RESULT" ]; then
  for p in "${CANDS[@]}"; do
    [ "$p" = "$RUNTIME" ] && continue
    [ "$(test_py "$p")" = bare ] || continue
    say "Python($p)에 문서 작업용 패키지를 넣는 중..."
    "$p" -m pip install --user --quiet $PKGS </dev/null >/dev/null 2>&1
    if [ "$(test_py "$p")" = ok ]; then RESULT="$p"; HOW='pip --user'; break; fi
    TRIES="$TRIES pip --user($p) 실패 /"
  done
fi
if [ -z "$RESULT" ]; then
  say 'Python을 사용자 폴더에 설치하는 중(uv, 1~3분)...'
  UV="$BASE/uv/uv"
  if [ ! -x "$UV" ]; then
    mkdir -p "$BASE/uv"
    curl -LsSf https://astral.sh/uv/install.sh </dev/null 2>/dev/null |
      env UV_INSTALL_DIR="$BASE/uv" UV_NO_MODIFY_PATH=1 sh >/dev/null 2>&1
  fi
  if [ -x "$UV" ]; then
    [ -x "$VENVPY" ] || "$UV" venv "$VENV" --python 3.12 --seed --quiet </dev/null >/dev/null 2>&1
    "$UV" pip install --python "$VENVPY" --quiet $PKGS </dev/null >/dev/null 2>&1
    if [ "$(test_py "$VENVPY")" = ok ]; then RESULT="$VENVPY"; HOW='uv'; else TRIES="$TRIES uv 실패(패키지 확인 안 됨) /"; fi
  else
    TRIES="$TRIES uv 실패(내려받기 막힘) /"
  fi
fi

mkdir -p "$WS/memory"
{
  printf '# 실행 환경 (ensure-python이 자동 기록)\n\n- 확인 시각: %s\n' "$(date '+%Y-%m-%d %H:%M')"
  if [ -n "$RESULT" ]; then
    printf -- '- python: %s\n- 방법: %s\n- 패키지: %s\n' "$RESULT" "$HOW" "$(echo $PKGS | sed 's/ /, /g')"
  else
    printf -- '- python: 없음(자동 설치 실패)\n- 시도:%s\n- 대응: PPT는 보고서(문서)로 대신 만든다. 다시 시도하려면 이 스크립트를 다시 실행한다.\n' "${TRIES% /}"
  fi
} > "$WS/memory/env.md"
if [ -n "$RESULT" ]; then printf '  Python 준비 완료(%s): %s\n' "$HOW" "$RESULT"; else printf '  Python 자동 설치 실패:%s\n' "${TRIES% /}"; fi
exit 0
