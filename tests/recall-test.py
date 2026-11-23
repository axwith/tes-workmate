# recall(대화 수집·색인·검색) 회귀 시험 — Mac 판(sync.py·search.py). recall-test.ps1과 같은 14개 항목을 확인한다.
# 사용: python3 tests/recall-test.py   (실패하면 종료 코드 1)
import json
import os
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
tmp = tempfile.mkdtemp(prefix='wm-recall-test-')
ws = os.path.join(tmp, 'workmate')
cx = os.path.join(tmp, 'codex')
for d in ['.agents/skills', 'memory/wiki/decisions', 'memory/sessions', '20-operations/월간품질보고']:
    os.makedirs(os.path.join(ws, d), exist_ok=True)
os.makedirs(os.path.join(cx, 'sessions/2026/11/20'))
shutil.copytree(os.path.join(REPO, '.agents/skills/wrap'), os.path.join(ws, '.agents/skills/wrap'),
                ignore=shutil.ignore_patterns('__pycache__'))


def W(p, t):
    with open(os.path.join(ws, p), 'w', encoding='utf-8') as f:
        f.write(t)


W('AGENTS.md', '# workmate\n보고는 결과부터.')
W('memory/wiki/decisions/pct.md', '---\ntitle: 차이 표기\n---\n# 차이 표기\n불량률 차이는 %p로 쓴다. 품질팀장 지시.')
W('20-operations/월간품질보고/README.md', '# 월간 품질 보고\n매월 첫째 주 월요일, 검사결과.xlsx 기준.')


def J(o):
    return json.dumps(o, ensure_ascii=False)


def msg(role, kind, text):
    return J({'type': 'response_item', 'payload': {'type': 'message', 'role': role, 'content': [{'type': kind, 'text': text}]}})


lines = [J({'type': 'session_meta', 'payload': {'id': 'aaaabbbb-0000-0000-0000-000000000001', 'cwd': ws, 'timestamp': '2026-11-20T06:00:00Z'}}),
         msg('user', 'input_text', '# AGENTS.md instructions 무시돼야 함'),
         msg('user', 'input_text', '협력사 견적 비교표 만들어 줘'),
         msg('assistant', 'output_text', 'reports/견적비교.md 에 저장했습니다.')]
with open(os.path.join(cx, 'sessions/2026/11/20/rollout-a.jsonl'), 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + '\n')
other = [J({'type': 'session_meta', 'payload': {'id': 'ccccdddd-0000-0000-0000-000000000002', 'cwd': '/Users/someone/다른폴더', 'timestamp': '2026-11-20T06:00:00Z'}}),
         msg('user', 'input_text', '다른 폴더 대화 비밀')]
with open(os.path.join(cx, 'sessions/2026/11/20/rollout-b.jsonl'), 'w', encoding='utf-8') as f:
    f.write('\n'.join(other) + '\n')

env = dict(os.environ, CODEX_HOME=cx)
r = os.path.join(ws, '.agents/skills/wrap/scripts')
py = sys.executable
fail = 0


def run(*a):
    return subprocess.run([py] + list(a), capture_output=True, text=True, env=env, stdin=subprocess.DEVNULL).stdout


def check(name, cond):
    global fail
    print(('통과  ' if cond else '실패  ') + name)
    if not cond:
        fail += 1


out1 = run(os.path.join(r, 'sync.py'))
check('대화 1개만 수집(다른 폴더 대화 제외)', '새 대화 1개' in out1)
sess = sorted(n for n in os.listdir(os.path.join(ws, 'memory/sessions')) if n.endswith('.md'))
check('세션 파일 이름', sess == ['2026-11-20_aaaabbbb.md'])
body = open(os.path.join(ws, 'memory/sessions', sess[0]), encoding='utf-8').read() if sess else ''
check('시스템 문구 제외', 'AGENTS.md instructions' not in body)
check('digested: false 표시', 'digested: false' in body)
out2 = run(os.path.join(r, 'sync.py'))
check('다시 돌려도 중복 수집 없음', '새 대화 0개' in out2)
cases = [('견적 비교표', '2026-11-20_aaaabbbb'), ('불량률', 'pct.md'), ('%p', 'pct.md'), ('팀장', 'pct.md'),
         ('품질 보고', '월간품질보고'), ('첫째 주', '월간품질보고'), ('결과부터', 'AGENTS.md')]
for q, want in cases:
    res = run(os.path.join(r, 'search.py'), q, '-n', '5')
    check("검색 '%s' → %s" % (q, want), want in res)
none = run(os.path.join(r, 'search.py'), '비밀', '-n', '5')
check('다른 폴더 대화는 검색 안 됨', '검색 결과 없음' in none)
kind_res = run(os.path.join(r, 'search.py'), '견적', '--kind', 'memory/sessions', '-n', '5')
check('종류 필터(memory/sessions)', 'aaaabbbb' in kind_res)
leftover = [d for d, _, _ in os.walk(ws) if d.endswith('__pycache__')]
shutil.rmtree(tmp)
if leftover:
    print('참고: __pycache__ 남음 ' + ', '.join(leftover))
if fail:
    print('실패 %d건' % fail)
    sys.exit(1)
print('전부 통과')
