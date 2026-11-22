#!/bin/bash
# workmate (Codex) 설치기 — macOS
#   curl -fsSL https://raw.githubusercontent.com/axwith/tes-workmate/main/install.sh | bash
#   또는 받은 폴더에서: bash install.sh
# 옵션(환경변수): WORKMATE_DIR=설치 위치(기본 ~/Documents/workmate), WORKMATE_FROM=로컬 원본 폴더,
#   WORKMATE_SCAN_ROOTS=스캔할 폴더(:로 구분, ;도 됨. 지정하면 그 폴더만), WORKMATE_SAMPLE=research|cs|mfg|qa|support(내 Mac 대신 예시 직무 자료로)
# git은 설치하지 않는다. 개발자 도구 git, Homebrew git, Codex 앱이 받아 둔 git 순으로 찾고 없으면 git 없이 계속한다.
# 파이프(curl | bash)로 받을 때 중간에 끊겨도 반쯤 실행되지 않도록 전체를 함수로 감싸 마지막 줄에서 부른다.

main() {
  REPO='axwith/tes-workmate'
  DIR="${WORKMATE_DIR:-$HOME/Documents/tes-workmate}"
  RT="$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies"
  say() { printf '  %s\n' "$1"; }
  has_clt() { xcode-select -p >/dev/null 2>&1; }   # 없으면 /usr/bin/git·python3이 설치 창을 띄운다

  printf '\nworkmate 설치를 시작합니다 → %s\n\n' "$DIR"

  # 1. git 확인 — 변경 기록·되돌리기에 쓴다. 없으면 git 없이 계속한다
  GIT=''
  for g in "$(command -v git 2>/dev/null)" /opt/homebrew/bin/git /usr/local/bin/git /usr/bin/git "$RT/native/git/bin/git"; do
    [ -n "$g" ] && [ -x "$g" ] || continue
    if [ "$g" = /usr/bin/git ] && ! has_clt; then continue; fi
    "$g" --version >/dev/null 2>&1 </dev/null || continue
    GIT="$g"; break
  done
  if [ -z "$GIT" ]; then
    say 'git을 찾지 못했습니다. git 없이 계속합니다(Codex 앱을 한 번 연 뒤 다시 실행하면 앱이 받아 둔 git을 씁니다).'
  fi

  # Python — Codex 앱이 받아 둔 Python(pypdf·SQLite 검색 포함)을 먼저 쓴다
  PY=''
  for p in "$RT/python/bin/python3" /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
    [ -x "$p" ] || continue
    if [ "$p" = /usr/bin/python3 ] && ! has_clt; then continue; fi
    PY="$p"; break
  done

  # 2. 원본 받기
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/workmate-src-XXXXXXXX")"
  if [ -n "$WORKMATE_FROM" ]; then
    SRC="$WORKMATE_FROM"
  elif [ -n "$GIT" ]; then
    "$GIT" clone -q --depth 1 "https://github.com/$REPO.git" "$TMP/src" </dev/null >/dev/null 2>&1
    if [ ! -f "$TMP/src/AGENTS.md" ]; then
      echo "원본을 받지 못했습니다(https://github.com/$REPO). 비공개 저장소면 GitHub 로그인이 필요합니다." >&2
      rm -rf "$TMP"; return 1
    fi
    SRC="$TMP/src"
  else
    curl -fsSL "https://github.com/$REPO/archive/refs/heads/main.zip" -o "$TMP/src.zip" </dev/null &&
      /usr/bin/unzip -q "$TMP/src.zip" -d "$TMP/x" </dev/null
    SRC="$(find "$TMP/x" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)"
    if [ -z "$SRC" ] || [ ! -f "$SRC/AGENTS.md" ]; then
      echo "원본을 받지 못했습니다(https://github.com/$REPO). 비공개 저장소면 GitHub 로그인이 필요합니다." >&2
      rm -rf "$TMP"; return 1
    fi
  fi

  # 3. 설치 또는 업데이트
  if [ -f "$DIR/AGENTS.md" ]; then
    say '이미 설치돼 있습니다. 기본 스킬만 새 버전으로 바꾸고, 기억·규칙·업무 폴더는 그대로 둡니다.'
    for s in prescan onboard collect inbox-sort wrap make-skill recall dashboard thickness-map; do
      to="$DIR/.agents/skills/$s"
      [ -e "$to" ] && rm -rf "$to"
      mkdir -p "$DIR/.agents/skills"
      cp -R "$SRC/.agents/skills/$s" "$to"
    done
    if ! cmp -s "$SRC/AGENTS.md" "$DIR/AGENTS.md"; then
      cp -f "$SRC/AGENTS.md" "$DIR/AGENTS.md.new"
      say '새 기본 AGENTS.md는 AGENTS.md.new로 두었습니다. Codex에 "AGENTS.md.new에서 바뀐 기본 규칙만 합쳐 줘"라고 하면 됩니다.'
    fi
  else
    mkdir -p "$DIR"
    for item in "$SRC"/* "$SRC"/.[!.]* "$SRC"/..?*; do
      [ -e "$item" ] || continue
      name="${item##*/}"
      case "$name" in
        ._*|.git|.gitattributes|install.ps1|install.sh|README.md|LICENSE|tests) continue ;;
      esac
      cp -R "$item" "$DIR/"
    done
    if [ -n "$GIT" ]; then
      "$GIT" -C "$DIR" init -q </dev/null
      "$GIT" -C "$DIR" config core.autocrlf false
      "$GIT" -C "$DIR" config core.quotepath false
      "$GIT" -C "$DIR" add -A >/dev/null 2>&1
      "$GIT" -C "$DIR" -c user.name=workmate -c user.email=workmate@local commit -q -m "workmate 설치" >/dev/null 2>&1 </dev/null
    fi
  fi
  [ -d "$TMP" ] && rm -rf "$TMP"
  DIR="$(cd "$DIR" && pwd -P)"   # Codex는 실제 경로로 폴더를 연다(/tmp → /private/tmp 등)

  # 3-1. Codex가 이 폴더의 설정(.codex/config.toml)을 쓰도록 신뢰 프로젝트로 등록
  CFG="$HOME/.codex/config.toml"
  mkdir -p "$HOME/.codex"
  KEY="[projects.'$DIR']"
  if ! { [ -f "$CFG" ] && grep -qF "$KEY" "$CFG"; }; then
    printf '\n%s\ntrust_level = "trusted"\n' "$KEY" >> "$CFG"
  fi

  # 4. 기억 자동 정리 등록: 1시간마다 대화 기록을 옮기고 검색 색인을 만든다(AI 없이, 창 없이)
  SYNC="$DIR/.agents/skills/recall/scripts/sync.py"
  HASH="$(printf '%s' "$DIR" | tr '[:upper:]' '[:lower:]' | md5 | cut -c1-8)"
  LABEL="com.workmate.sync.$HASH"
  PLIST_DIR="${WORKMATE_PLIST_DIR:-$HOME/Library/LaunchAgents}"
  PLIST="$PLIST_DIR/$LABEL.plist"
  xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
  # 실행할 Python을 그때그때 고른다(Codex 런타임 → Homebrew → 개발자 도구). 없으면 조용히 끝난다
  PICK="for p in \"\$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3\" /opt/homebrew/bin/python3 /usr/local/bin/python3; do [ -x \"\$p\" ] && exec \"\$p\" \"\$0\" --quiet; done; xcode-select -p >/dev/null 2>&1 && exec /usr/bin/python3 \"\$0\" --quiet"
  mkdir -p "$PLIST_DIR"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>-c</string>
    <string>$(xml "$PICK")</string>
    <string>$(xml "$SYNC")</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$(xml "$RT/native/git/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")</string></dict>
  <key>WorkingDirectory</key><string>$(xml "$DIR")</string>
  <key>StartInterval</key><integer>3600</integer>
  <key>RunAtLoad</key><false/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>/dev/null</string>
  <key>StandardErrorPath</key><string>/dev/null</string>
</dict>
</plist>
EOF
  if [ -n "$WORKMATE_NO_SCHEDULE" ]; then
    say "기억 자동 정리 등록은 건너뜁니다(WORKMATE_NO_SCHEDULE). 설정 파일만 만들었습니다: $PLIST"
  else
    UIDN="$(id -u)"
    launchctl bootout "gui/$UIDN/$LABEL" >/dev/null 2>&1 </dev/null
    if launchctl bootstrap "gui/$UIDN" "$PLIST" >/dev/null 2>&1 </dev/null || launchctl load -w "$PLIST" >/dev/null 2>&1 </dev/null; then
      say "기억 자동 정리를 1시간마다 돌도록 등록했습니다($LABEL)."
    else
      say '기억 자동 정리 등록에 실패했습니다. 대화를 시작할 때마다 정리됩니다.'
    fi
  fi

  # 5. 최근 파일 미리 읽기 — Codex 샌드박스 밖(지금 이 터미널)에서 돌려야 문서·다운로드·PDF를 다 읽는다
  SCAN="$DIR/.agents/skills/prescan/scripts/scan.py"
  ROLES="$DIR/.agents/skills/prescan/sample/pcs"
  scan_sample() { say "예시 자료($1)로 세팅합니다."; "$PY" "$SCAN" --force --only-roots --roots "$ROLES/$1" </dev/null | while IFS= read -r l; do say "$l"; done; }
  if [ -z "$PY" ]; then
    say 'Python을 찾지 못해 최근 파일 미리 읽기를 건너뜁니다. Codex에서 처음 대화할 때 읽습니다.'
  else
    say '최근 파일을 미리 읽는 중입니다(1분 안팎)...'
    if [ -n "$WORKMATE_SAMPLE" ] && [ -d "$ROLES/$WORKMATE_SAMPLE" ]; then
      scan_sample "$WORKMATE_SAMPLE"   # 강사 시연·시험용: 내 Mac 파일 대신 예시 직무 자료로
    else
      set --
      if [ -n "$WORKMATE_SCAN_ROOTS" ]; then   # 시험·직무 프로필용: 지정 폴더만
        set -- --only-roots --roots
        OLDIFS="$IFS"; IFS=':;'
        for r in $WORKMATE_SCAN_ROOTS; do [ -n "$r" ] && set -- "$@" "$r"; done
        IFS="$OLDIFS"
      fi
      "$PY" "$SCAN" --force "$@" </dev/null | while IFS= read -r l; do say "$l"; done
      # 최근 업무 파일이 거의 없으면(새 Mac 등) 가까운 직무의 예시 자료로 세팅한다
      CSV="$DIR/memory/scan/recent-files.csv"
      CNT=0
      [ -f "$CSV" ] && CNT="$("$PY" -c 'import csv,sys; print(len(list(csv.DictReader(open(sys.argv[1], encoding="utf-8-sig")))))' "$CSV" 2>/dev/null || echo 0)"
      if [ "$CNT" -lt 5 ] && [ -d "$ROLES" ]; then
        say '최근 업무 파일이 거의 없어 예시 자료로 세팅합니다. 가장 가까운 직무 번호를 고르세요.'
        say '  1. 연구소'; say '  2. CS'; say '  3. 제조'; say '  4. 품질'; say '  5. 지원'
        a=''
        if { exec 3</dev/tty; } 2>/dev/null; then
          printf '  번호(1~5, 그냥 Enter는 4): ' >/dev/tty
          read -r a <&3 || a=''
          exec 3<&-
        fi
        case "$a" in 1) role=research ;; 2) role=cs ;; 3) role=mfg ;; 5) role=support ;; *) role=qa ;; esac
        scan_sample "$role"
      fi
    fi
    "$PY" "$SYNC" --quiet </dev/null   # 첫 색인 — 스캔 뒤에 돌려야 Mac 전체를 한 번 더 읽지 않는다
  fi

  # 6. 1차 세팅까지 설치기가 끝낸다 — 사용자가 처음 열 때 이미 자기 업무에 맞춰져 있게
  CODEX=''
  for c in /Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex "$HOME/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex" "$(command -v codex 2>/dev/null)"; do
    [ -n "$c" ] && [ -x "$c" ] && { CODEX="$c"; break; }
  done
  STATE="$DIR/memory/state.md"
  setup_done() { [ -f "$STATE" ] && grep -q 'prescan: 완료' "$STATE"; }
  if [ -n "$CODEX" ] && [ -f "$HOME/.codex/auth.json" ] && ! setup_done; then
    say '내 업무에 맞춰 세팅하는 중입니다(2~3분)...'
    (cd "$DIR" && "$CODEX" exec --skip-git-repo-check -s workspace-write -C "$DIR" \
      "처음 세팅해 줘. PRESCAN.md 절차만 끝까지 하고, 첫 응답(first-reply)은 보내지 말고 세팅 완료라고만 답해." \
      </dev/null >"$DIR/memory/setup.log" 2>"$DIR/memory/setup.err.log")
    [ -n "$PY" ] && "$PY" "$SYNC" --quiet </dev/null
    # 첫 응답(first-reply)은 사용자가 처음 말을 걸 때 나가야 하므로 상태를 '미실행'으로 되돌려 둔다
    [ -f "$STATE" ] && /usr/bin/perl -Mutf8 -CSD -0777 -i -pe 's/onboard:\s*\S+/onboard: 미실행/g' "$STATE"
    if setup_done; then say '세팅 완료.'; else say '세팅을 끝내지 못했습니다. Codex에서 폴더를 열고 아무 말이나 보내면 이어서 합니다.'; fi
  elif [ ! -f "$HOME/.codex/auth.json" ]; then
    say 'Codex 앱에 로그인돼 있지 않아 세팅은 처음 대화 때 진행합니다.'
  fi

  printf '\n설치 완료: %s\n\n' "$DIR"
  say '다음:'
  say '1. ChatGPT 앱의 Codex에서 이 폴더를 프로젝트로 엽니다.'
  say '2. "안녕하세요"라고 보내 보세요.'
  [ -z "$WORKMATE_NO_OPEN" ] && open "$DIR" </dev/null
  return 0
}

main "$@"
