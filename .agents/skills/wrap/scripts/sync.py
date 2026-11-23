# 기억 동기화 (AI 없이 돈다. 설치기가 LaunchAgent로 1시간마다 등록) — sync.ps1의 Mac 판
# 1) 이 워크스페이스에서 한 Codex 대화를 memory/sessions/ 에 마크다운으로 옮긴다(새로 생긴 것만)
# 2) memory·references·AGENTS.md·업무 폴더의 .md 를 memory/index.db (SQLite FTS5) 로 색인한다
# 사용: python3 sync.py [--quiet]
import argparse
import datetime as dt
import json
import os
import re
import sqlite3
import subprocess
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..'))
HOME = os.path.expanduser('~')
RT = os.path.join(HOME, '.cache/codex-runtimes/codex-primary-runtime/dependencies')
RUNTIME_PY = os.path.join(RT, 'python/bin/python3')


def need_trigram():
    """이 Python의 SQLite가 trigram을 모르면 Codex 런타임 Python으로 다시 실행한다."""
    try:
        sqlite3.connect(':memory:').execute("CREATE VIRTUAL TABLE t USING fts5(a, tokenize='trigram')")
        return
    except Exception:
        pass
    if os.path.exists(RUNTIME_PY) and os.path.realpath(sys.executable) != os.path.realpath(RUNTIME_PY):
        os.execv(RUNTIME_PY, [RUNTIME_PY] + sys.argv)
    sys.exit('이 Python의 SQLite가 FTS5 trigram을 지원하지 않습니다. Codex 앱을 한 번 열어 런타임을 받은 뒤 다시 실행하세요.')


def find_git():
    """git 경로. /usr/bin/git은 개발자 도구가 없으면 설치 창을 띄우므로 그때는 쓰지 않는다."""
    cands = []
    for d in os.environ.get('PATH', '').split(':') + ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin']:
        if d:
            cands.append(os.path.join(d, 'git'))
    cands += [os.path.join(RT, 'native/git/bin/git')]
    for g in cands:
        if not (os.path.isfile(g) and os.access(g, os.X_OK)):
            continue
        if g == '/usr/bin/git' and subprocess.run(['xcode-select', '-p'], capture_output=True).returncode != 0:
            continue
        return g
    return None


def nfc(s):
    return unicodedata.normalize('NFC', s)


def norm(p):
    return nfc(os.path.realpath(p)).rstrip('/').casefold()


def txt(content):
    if not isinstance(content, list):
        return ''
    return '\n'.join(str(c['text']) for c in content if isinstance(c, dict) and c.get('text'))


def cut(s, n):
    return s[:n] + ' …(줄임)' if len(s) > n else s


def local_day(ts, fallback):
    try:
        x = re.sub(r'Z$', '+00:00', ts.strip())
        x = re.sub(r'(\.\d{6})\d+', r'\1', x)
        d = dt.datetime.fromisoformat(x)
        if d.tzinfo is None:
            d = d.replace(tzinfo=dt.timezone.utc)
        return d.astimezone().strftime('%Y-%m-%d')
    except Exception:
        return dt.datetime.fromtimestamp(fallback).strftime('%Y-%m-%d')


SYS_RE = re.compile(r'^\s*(# AGENTS\.md instructions|<environment_context>|<user_instructions>|<subagent_notification>)', re.I)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--quiet', '-Quiet', action='store_true')
    o = ap.parse_args()
    need_trigram()
    mem = os.path.join(WS, 'memory')
    sess_dir = os.path.join(mem, 'sessions')
    os.makedirs(sess_dir, exist_ok=True)
    state_path = os.path.join(mem, 'sync-state.json')
    state = {}
    if os.path.exists(state_path):
        try:
            with open(state_path, encoding='utf-8-sig') as f:
                state = json.load(f) or {}
        except Exception:
            state = {}

    # ---- 1. Codex 대화 기록 옮기기 ----
    codex_home = os.environ.get('CODEX_HOME') or os.path.join(HOME, '.codex')
    ws_n = norm(WS)
    new_sess = 0
    files = []
    for dp, dns, fns in os.walk(os.path.join(codex_home, 'sessions')):
        dns.sort()
        for fn in sorted(fns):
            if fn.startswith('rollout-') and fn.endswith('.jsonl'):
                files.append(os.path.join(dp, fn))
    for path in files:
        key = os.path.basename(path)
        try:
            size = os.path.getsize(path)
        except Exception:
            continue
        if key in state and int(state[key]) == size:
            continue
        cwd = sid = started = None
        turns = []
        last_assist = None
        try:
            with open(path, encoding='utf-8', errors='replace') as f:
                lines = f.read().split('\n')
        except Exception:
            continue
        for line in lines:
            if len(line) > 400000:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if not isinstance(d, dict):
                continue
            pl = d.get('payload') or {}
            if d.get('type') == 'session_meta':
                cwd, sid, started = pl.get('cwd'), pl.get('id'), pl.get('timestamp')
                continue
            if d.get('type') != 'response_item' or pl.get('type') != 'message':
                continue
            t = txt(pl.get('content'))
            if not t:
                continue
            if pl.get('role') == 'user':
                if SYS_RE.match(t):
                    continue
                if last_assist:
                    turns.append('**답변**\n\n' + cut(last_assist, 3000))
                    last_assist = None
                turns.append('**사용자**\n\n' + cut(t, 2000))
            elif pl.get('role') == 'assistant':
                last_assist = t
        state[key] = size
        if not cwd:
            continue
        c = norm(cwd)
        if not (c == ws_n or c.startswith(ws_n + '/')):
            continue
        if last_assist:
            turns.append('**답변**\n\n' + cut(last_assist, 3000))
        if not turns:
            continue
        day = local_day(started or '', os.path.getmtime(path))
        sid = sid or key[:-6]
        first = re.sub(r'^\*\*사용자\*\*\s*', '', turns[0]).split('\n')[0]
        title = cut(first, 60)
        out = os.path.join(sess_dir, '%s_%s.md' % (day, sid[:8]))
        head = '---\ndate: %s\nsession: %s\ntitle: %s\ndigested: false\n---\n\n# %s\n\n' % (day, sid, title, title)
        with open(out, 'w', encoding='utf-8') as f:
            f.write(head + '\n\n'.join(turns) + '\n')
        new_sess += 1
    with open(state_path, 'w', encoding='utf-8') as f:
        json.dump(state, f, ensure_ascii=False, separators=(',', ':'))

    # ---- 2. 색인 ----
    db_path = os.path.join(mem, 'index.db')
    tmp = db_path + '.tmp'
    if os.path.exists(tmp):
        os.remove(tmp)
    db = sqlite3.connect(tmp)
    try:
        db.execute("CREATE VIRTUAL TABLE docs USING fts5(path UNINDEXED, kind UNINDEXED, date UNINDEXED, title, body, tokenize='trigram')")
        roots = ['memory', 'references', '10-projects', '20-operations', '30-knowledge', '40-personal', '50-resources']
        paths = [os.path.join(WS, 'AGENTS.md')]
        scan_dir = os.path.join(WS, 'memory', 'scan') + os.sep
        for r in roots:
            for dp, dns, fns in os.walk(os.path.join(WS, r)):
                dns[:] = sorted(x for x in dns if not x.startswith('.'))
                for fn in sorted(fns):
                    full = os.path.join(dp, fn)
                    if fn.startswith('.') or os.path.splitext(fn)[1].lower() not in ('.md', '.txt', '.csv'):
                        continue
                    if full.startswith(scan_dir) or os.path.getsize(full) >= 2 * 1024 * 1024:
                        continue
                    paths.append(full)
        for full in paths:
            if not os.path.isfile(full):
                continue
            rel = nfc(os.path.relpath(full, WS))
            seg = rel.split('/')
            kind = seg[0]
            if rel.startswith('memory/') and len(seg) > 1:
                kind = 'memory/' + seg[1]
            with open(full, encoding='utf-8-sig', errors='replace') as f:
                body = f.read()
            if not body:
                continue
            title = ''
            for ln in body.split('\n'):
                if re.match(r'^(# |title:)', ln):
                    title = re.sub(r'^(# |title:\s*)', '', ln)
                    break
            if not title:
                title = nfc(os.path.splitext(os.path.basename(full))[0])
            date = dt.datetime.fromtimestamp(os.path.getmtime(full)).strftime('%Y-%m-%d')
            db.execute('INSERT INTO docs VALUES (?,?,?,?,?)', (rel, kind, date, title.strip(), body))
        db.commit()
        count = db.execute('SELECT count(*) FROM docs').fetchone()[0]
    finally:
        db.close()
    os.replace(tmp, db_path)

    # ---- 3. 최근 파일 목록 새로 고침(하루 한 번) — 샌드박스 밖에서 돌아야 Mac 문서를 다 읽는다 ----
    csv_path = os.path.join(mem, 'scan', 'recent-files.csv')
    scan_py = os.path.join(WS, '.agents', 'skills', 'prescan', 'scripts', 'scan.py')
    if os.path.exists(scan_py) and (not os.path.exists(csv_path) or os.path.getmtime(csv_path) < (dt.datetime.now() - dt.timedelta(days=1)).timestamp()):
        subprocess.run([sys.executable, scan_py, '--force'], capture_output=True, stdin=subprocess.DEVNULL)

    # ---- 4. 변경 기록(git) — Codex 샌드박스는 .git을 쓸 수 없으므로 여기서 남긴다 ----
    committed = False
    git = find_git()
    if git and os.path.exists(os.path.join(WS, '.git')):
        try:
            st = subprocess.run([git, '-C', WS, 'status', '--porcelain'], capture_output=True, text=True, stdin=subprocess.DEVNULL)
            if st.stdout.strip():
                subprocess.run([git, '-C', WS, 'add', '-A'], capture_output=True, stdin=subprocess.DEVNULL)
                subprocess.run([git, '-C', WS, '-c', 'user.name=workmate', '-c', 'user.email=workmate@local', 'commit', '-q', '-m',
                                '자동 기록 ' + dt.datetime.now().strftime('%Y-%m-%d %H:%M')], capture_output=True, stdin=subprocess.DEVNULL)
                committed = True
        except Exception:
            pass
    if not o.quiet:
        print('새 대화 %d개 옮김, 색인 문서 %d개 → memory/index.db%s' % (new_sess, count, ', 변경 기록 남김' if committed else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main())
