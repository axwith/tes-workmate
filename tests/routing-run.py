#!/usr/bin/env python3
"""자연어 → 스킬 라우팅을 실제 codex exec로 측정한다(개발용, 설치 대상 아님).

사용: python3 tests/routing-run.py --ws <첫 인사까지 끝낸 워크스페이스> --out <결과.json> [--workers 8] [--ids e1,m1] [--timeout 300]
- 문장마다 워크스페이스를 따로 복사해 새 세션으로 돌린다(서로 기록·규칙이 섞이지 않게).
- 실행 로그(--json)의 명령에서 `skills/<이름>/SKILL.md`를 연 기록을 모은다.
- 기대 스킬을 열면 그 자리에서 끊는다(적중). 기대가 없으면(null) 끝까지 돌려 아무 스킬도 안 열었는지 본다.
"""
import argparse, json, os, re, shutil, subprocess, sys, threading, time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
CODEX = os.environ.get('CODEX_BIN', '/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex')
SKILL_RE = re.compile(r'skills/([a-z0-9-]+)/SKILL\.md')


def run_case(case, ws, root, timeout):
    d = os.path.join(root, case['id'])
    if os.path.exists(d):
        shutil.rmtree(d)
    shutil.copytree(ws, d, symlinks=True)
    log = open(os.path.join(root, case['id'] + '.jsonl'), 'w', encoding='utf-8')
    cmd = [CODEX, 'exec', '--json', '--skip-git-repo-check', '-s', 'workspace-write', '-C', d, case['text']]
    t0 = time.time()
    p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
    timer = threading.Timer(timeout, p.kill); timer.start()
    opened, last_msg, stopped = [], '', 'done'
    for line in p.stdout:
        log.write(line)
        try:
            ev = json.loads(line)
        except Exception:
            continue
        item = ev.get('item') or {}
        if item.get('type') == 'command_execution' and ev.get('type') == 'item.started':
            for name in SKILL_RE.findall(item.get('command', '')):
                if name not in opened:
                    opened.append(name)
        elif item.get('type') == 'agent_message':
            last_msg = item.get('text', '')
        if case['expected'] and case['expected'] in opened:
            stopped = 'hit-early'
            p.kill(); break
    p.wait(); timer.cancel(); log.close()
    if stopped == 'done' and time.time() - t0 >= timeout - 1:
        stopped = 'timeout'
    hit = (case['expected'] in opened) if case['expected'] else (not opened)
    shutil.rmtree(d, ignore_errors=True)
    return {**case, 'opened': opened, 'hit': hit, 'stopped': stopped,
            'sec': round(time.time() - t0), 'reply': last_msg[:300]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ws', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--cases', default=os.path.join(HERE, 'routing-cases.json'))
    ap.add_argument('--workers', type=int, default=8)
    ap.add_argument('--ids', default='')
    ap.add_argument('--timeout', type=int, default=300)
    a = ap.parse_args()
    cases = json.load(open(a.cases, encoding='utf-8'))['cases']
    if a.ids:
        want = a.ids.split(',')
        cases = [c for c in cases if c['id'] in want]
    root = os.path.splitext(os.path.abspath(a.out))[0] + '-runs'
    os.makedirs(root, exist_ok=True)
    with ThreadPoolExecutor(a.workers) as ex:
        res = list(ex.map(lambda c: run_case(c, a.ws, root, a.timeout), cases))
    hits = sum(r['hit'] for r in res)
    json.dump({'hits': hits, 'total': len(res), 'results': res}, open(a.out, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    for r in res:
        print(('O' if r['hit'] else 'X'), r['id'], '기대', r['expected'], '열림', r['opened'], r['stopped'], f"{r['sec']}s")
    print(f'적중 {hits}/{len(res)}')


if __name__ == '__main__':
    main()
