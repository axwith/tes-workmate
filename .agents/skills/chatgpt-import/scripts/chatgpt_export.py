# ChatGPT 데이터 내보내기(ZIP 또는 conversations*.json)에서 대화 목록과 고른 대화의 내용을 화면에 보여 준다.
# 표준 라이브러리만 쓰고 파일을 쓰지 않는다.
# 사용: python chatgpt_export.py list <ZIP|json|폴더> [--limit 50] [--word 낱말]
#       python chatgpt_export.py show <ZIP|json|폴더> <번호> [<번호> ...] [--max-chars 2000]
# 번호는 list와 같은 순서(최근 수정순)다.
import argparse, datetime, glob, json, os, sys, zipfile

FAIL = '내보내기 파일에서 대화를 찾지 못했습니다.'


def load(path):
    convs = []
    def add(data):
        if isinstance(data, dict):
            data = data.get('conversations') or [data]
        if isinstance(data, list):
            convs.extend(c for c in data if isinstance(c, dict) and isinstance(c.get('mapping'), dict))
    if os.path.isdir(path):
        for p in sorted(glob.glob(os.path.join(path, '**', 'conversations*.json'), recursive=True)):
            with open(p, encoding='utf-8') as f:
                add(json.load(f))
    elif zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as z:
            for n in sorted(z.namelist()):
                if os.path.basename(n).startswith('conversations') and n.endswith('.json'):
                    add(json.loads(z.read(n).decode('utf-8')))
    elif os.path.isfile(path):
        with open(path, encoding='utf-8') as f:
            add(json.load(f))
    convs.sort(key=lambda c: c.get('update_time') or c.get('create_time') or 0, reverse=True)
    return convs


def day(t):
    try:
        return datetime.datetime.fromtimestamp(float(t)).strftime('%Y-%m-%d')
    except Exception:
        return '날짜 없음'


def messages(c):
    m = c['mapping']
    node = c.get('current_node')
    if node not in m:   # current_node가 없으면 가장 늦은 메시지에서 거슬러 올라간다
        node = max(m, key=lambda k: ((m[k].get('message') or {}).get('create_time') or 0), default=None)
    chain, seen = [], set()
    while node and node in m and node not in seen:
        seen.add(node)
        chain.append(m[node].get('message'))
        node = m[node].get('parent')
    out = []
    for msg in reversed(chain):
        if not msg:
            continue
        role = (msg.get('author') or {}).get('role')
        if role not in ('user', 'assistant'):
            continue
        if (msg.get('metadata') or {}).get('is_visually_hidden_from_conversation'):
            continue
        parts = (msg.get('content') or {}).get('parts') or []
        text = '\n'.join(p for p in parts if isinstance(p, str)).strip()
        if text:
            out.append((role, msg.get('create_time'), text))
    return out


def main():
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser()
    ap.add_argument('cmd', choices=['list', 'show'])
    ap.add_argument('path')
    ap.add_argument('nums', nargs='*', type=int)
    ap.add_argument('--limit', type=int, default=50)
    ap.add_argument('--word', default='')
    ap.add_argument('--max-chars', type=int, default=2000)
    o = ap.parse_args()
    try:
        convs = load(o.path)
    except Exception:
        convs = []
    if not convs:
        print(FAIL)
        return 1
    if o.cmd == 'list':
        print(f'대화 {len(convs)}개 (최근 수정순)')
        shown = 0
        for i, c in enumerate(convs, 1):
            title = c.get('title') or '(제목 없음)'
            if o.word and o.word.lower() not in title.lower():
                continue
            print(f'{i}. {day(c.get("update_time") or c.get("create_time"))} — {title}')
            shown += 1
            if shown >= o.limit:
                break
        return 0
    for n in o.nums:
        if not 1 <= n <= len(convs):
            print(f'[{n}] 없는 번호입니다.')
            continue
        c = convs[n - 1]
        print(f'===== [{n}] {day(c.get("create_time"))} — {c.get("title") or "(제목 없음)"}')
        for role, t, text in messages(c):
            if len(text) > o.max_chars:
                text = text[:o.max_chars] + ' …(줄임)'
            print(f'--- {"나" if role == "user" else "ChatGPT"} ({day(t)})')
            print(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
