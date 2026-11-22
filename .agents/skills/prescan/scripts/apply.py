# memory/work-map.json 하나로 사전 온보딩 결과를 파일에 반영한다(AI가 빠뜨리지 않게 스크립트가 쓴다). (apply.ps1의 Mac 판)
# AGENTS.md 4장, 업무 폴더 README, references, 위키, 확인 목록, 대시보드 HTML. 끝에 빠진 것을 점검해 알려 준다.
# 사용: python3 apply.py [--open]
import argparse
import csv
import datetime as dt
import json
import os
import re
import shutil
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..'))
sys.dont_write_bytecode = True  # 워크스페이스에 __pycache__를 남기지 않는다
sys.path.insert(0, HERE)
import render  # noqa: E402


def nfc(s):
    return unicodedata.normalize('NFC', s)


def s(v):
    return '' if v is None else str(v)


def as_list(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]


def W(rel, text):
    p = os.path.join(WS, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w', encoding='utf-8', newline='') as f:
        f.write(re.sub(r'\r?\n', '\n', s(text)))


def slug(x):
    return re.sub(r'[\\/:*?"<>|\s]+', '-', s(x)).strip('-')


def same(a, b):
    return nfc(s(a)).casefold() == nfc(s(b)).casefold()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--open', '-Open', action='store_true')
    o = ap.parse_args()
    with open(os.path.join(WS, 'memory', 'work-map.json'), encoding='utf-8-sig') as f:
        D = json.load(f)
    problems = []

    # 1) AGENTS.md 4장 (표식 사이를 바꾼다)
    p = D.get('profile')
    if p:
        def V(label, v):
            v = s(v).strip()
            if v.startswith(label):
                v = v[len(label):].lstrip(' :·')
            if not v:
                v = '(미확인)'
            return '- %s: %s' % (label, v)
        rows = [V('이름·소속·직무', ('(이름·소속은 첫 작업 때 확인) ' + s(p.get('person'))) if p.get('person') else ''),
                V('보고 대상·주기', p.get('report')), V('주요 반복 업무와 저장 위치', p.get('works')),
                V('판단 기준·금지 사항', p.get('criteria')), V('팀 용어', p.get('terms'))]
        with open(os.path.join(WS, 'AGENTS.md'), encoding='utf-8-sig') as f:
            agents = f.read()
        block = '<!-- profile:start -->\n' + '\n'.join(rows) + '\n<!-- profile:end -->'
        agents = re.sub(r'(?s)<!-- profile:start -->.*?<!-- profile:end -->', lambda m: block, agents)
        W('AGENTS.md', agents)
    else:
        problems.append('profile 없음(AGENTS.md 4장 미작성)')

    # 2) 업무 폴더와 README
    scan_csv = os.path.join(WS, 'memory', 'scan', 'recent-files.csv')
    scan_rows = []
    if os.path.exists(scan_csv):
        with open(scan_csv, encoding='utf-8-sig', newline='') as f:
            scan_rows = list(csv.DictReader(f))
    for fo in as_list(D.get('folders')):
        if not fo.get('path'):
            continue
        W(os.path.join(fo['path'], 'README.md'), fo.get('readme'))
        # 이 업무의 단서 파일 사본을 업무 폴더/자료 로 복사 — 이후 작업이 워크스페이스 안에서 원본을 찾게
        for src in as_list(fo.get('files')):
            leaf = re.split(r'[\\/]', s(src))[-1]
            row = next((r for r in scan_rows if same(r.get('path'), src) or same(r.get('copy'), src) or same(r.get('name'), leaf)), None)
            if row and row.get('copy'):
                frm = os.path.join(WS, row['copy'].replace('\\', '/'))
                to_dir = os.path.join(WS, fo['path'], '자료')
                os.makedirs(to_dir, exist_ok=True)
                try:
                    shutil.copy2(frm, os.path.join(to_dir, row['name']))
                except Exception:
                    pass
    if not D.get('folders'):
        problems.append('folders 없음(업무 폴더 미생성)')

    # 3) references
    ref_names = {'report-formats': '보고 양식', 'criteria': '기준값·계산식', 'glossary': '용어'}
    refs = D.get('references') or {}
    for k, name in ref_names.items():
        v = refs.get(k) if isinstance(refs, dict) else None
        if v:
            W('references/%s.md' % k, '# ' + name + '\n\n' + s(v))
        else:
            problems.append('references.%s 없음' % k)

    # 4) 위키 + 목록
    idx = ['# 위키 목록', '', '> `wrap`·`onboard`가 고친다. 실제 파일과 다르면 실제 파일이 우선.', '',
           '| 분류 | 페이지 | 요약 | 갱신 |', '|---|---|---|---|']
    date = s(D.get('date'))
    for k in as_list(D.get('wiki')):
        if not k.get('title'):
            continue
        cat, title = s(k.get('category')), s(k.get('title'))
        W('memory/wiki/%s/%s.md' % (cat, slug(title)),
          '---\ntitle: %s\ncategory: %s\nstatus: 추정\nupdated: %s\n---\n\n# %s\n\n%s' % (title, cat, date, title, s(k.get('body'))))
        first = s(k.get('body')).split('\n')[0].replace('|', '/')
        idx.append('| %s | [%s](wiki/%s/%s.md) | %s | %s |' % (cat, title, cat, slug(title), first, date))
    if not D.get('wiki'):
        problems.append('wiki 없음')
    # 이미 있던 위키(미리 넣어 둔 회사 위키 등)도 목록에 남긴다
    listed = [('%s/%s.md' % (s(k.get('category')), slug(k.get('title')))).casefold() for k in as_list(D.get('wiki'))]
    wiki_root = os.path.join(WS, 'memory', 'wiki')
    for dp, dns, fns in os.walk(wiki_root):
        dns.sort()
        for fn in sorted(fns):
            if not fn.endswith('.md') or fn.startswith('._'):
                continue
            full = os.path.join(dp, fn)
            r = nfc(os.path.relpath(full, wiki_root))
            if r.casefold() in listed:
                continue
            t = ''
            with open(full, encoding='utf-8-sig', errors='replace') as f:
                for line in f.read().splitlines():
                    if line.startswith('# '):
                        t = line[2:]
                        break
            if not t:
                t = nfc(os.path.splitext(fn)[0])
            parent = os.path.basename(os.path.dirname(r))
            mod = dt.datetime.fromtimestamp(os.path.getmtime(full)).strftime('%Y-%m-%d')
            idx.append('| %s | [%s](wiki/%s) | 미리 넣어 둔 자료 | %s |' % (parent, t, r, mod))
    W('memory/index.md', '\n'.join(idx))

    # 5) 확인 목록
    W('memory/onboard-checklist.md', '# 온보딩 확인 목록\n\n' + '\n'.join('- ' + s(x) for x in as_list(D.get('checklist'))))

    # 5-1) 2교시 첫 응답을 미리 만들어 둔다(첫 턴은 이 파일만 읽고 그대로 답한다 → 진행 문구·스킬 언급이 생기지 않게)
    ws_url = WS
    dash = 'reports/%s_내-업무-한눈에.html' % dt.date.today().strftime('%Y-%m-%d')
    lines = []
    who = '안녕하세요. '  # 이름은 파일에서 추정하지 않는다(다른 사람 이름일 수 있다). 첫 작업 때 물어 채운다
    ups = as_list(D.get('upcoming'))
    drs = as_list(D.get('drafts'))
    up = ups[0] if ups else None
    dr = drs[0] if drs else None
    if up:
        lead = '%s %s 준비해 둘게요.' % (s(up.get('when')), re.sub(r'\s*준비$', '', s(up.get('what')).strip()))
    else:
        lead = '이번 주 업무 정리해 뒀어요.'
    lines.append(who + lead)
    if dr:  # note는 짧은 꾸밈말(예: 지난달 형식 그대로)
        lines.append('%s도 만들어 뒀습니다%s.' % (s(dr.get('title')), (' (%s)' % s(dr.get('note'))) if dr.get('note') else ''))
    links = ['[업무 한눈에](%s/%s)' % (ws_url, dash)]
    if dr:
        links.append('[%s](%s/reports/%s)' % (s(dr.get('title')), ws_url, s(dr.get('href'))))
    lines.append(' · '.join(links))
    lines.append('')
    n = 1
    for w in as_list(D.get('works'))[:3]:
        lines.append(('%d. %s %s' % (n, s(w.get('name')), '마저 하기' if n == 1 else '')).rstrip())
        n += 1
    lines.append('%d. 다른 일 시키기' % n)
    W('memory/first-reply.md', '\n'.join(lines))

    # 6) 대시보드
    render.render(o.open, quiet=True)

    # 7) 점검
    with open(os.path.join(WS, 'AGENTS.md'), encoding='utf-8-sig') as f:
        if '(미설정)' in f.read():
            problems.append('AGENTS.md 4장에 (미설정) 남음')
    for d in drs:
        if not os.path.exists(os.path.join(WS, 'reports', s(d.get('href')))):
            problems.append('초안 파일 없음: reports/%s' % s(d.get('href')))
    if not D.get('drafts'):
        problems.append('초안(drafts) 없음')
    for fo in as_list(D.get('folders')):
        if fo.get('path') and not fo.get('files'):
            problems.append('folders[%s].files 없음(단서 파일 경로를 넣어야 자료가 업무 폴더로 복사됨)' % fo['path'])
    if problems:
        print('점검 실패 — 고친 뒤 다시 실행:')
        for x in problems:
            print(' - ' + x)
        return 1
    print('반영 완료: AGENTS.md 4장, 폴더 %d개, references 3개, 위키 %d개, 대시보드' % (len(as_list(D.get('folders'))), len(as_list(D.get('wiki')))))
    return 0


if __name__ == '__main__':
    sys.exit(main())
