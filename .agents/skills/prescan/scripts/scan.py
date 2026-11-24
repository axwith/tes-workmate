# 최근에 쓴 파일 목록과 본문 일부를 이 워크스페이스 memory/scan/ 에 만든다. (scan.ps1의 Mac 판)
# 설치 없이 macOS 기본 python3(표준 라이브러리)로 돈다. pypdf가 있으면 PDF 본문도 뽑는다. 원본 파일은 읽기만 한다.
# 온라인 전용(File Provider에서 내려받지 않은) 파일은 목록에만 남기고 열거나 내려받지 않는다(copy 열이 비고 why에 online-only).
# 사용: python3 scan.py [--days 30] [--max-files 300] [--max-text 80] [--roots "~/업무"] [--only-roots] [--force]
#   --roots는 기본 검색(Spotlight·문서·데스크탑·다운로드·클라우드 폴더)에 더한다. --only-roots를 함께 주면 그 폴더만 본다.
# 범위 설정 정본: memory/scan/scan-config.json (scan.ps1과 같은 키: roots·onlyRoots·useDiscovered·include·exclude·maxDepth·extensions·skipOnlineOnly)
# 본 폴더 목록: memory/scan/scan-roots.csv (status: 기본·자동 발견·추가·지정·제외·없음). 사람이 보는 요약은 memory/env.md 끝에 적는다.
import argparse
import csv
import datetime as dt
import fnmatch
import html
import json
import os
import time
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..'))
HOME = os.path.expanduser('~')
RUNTIME_PY = os.path.join(HOME, '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3')

DOC_EXT = ['.docx', '.xlsx', '.pptx', '.hwp', '.hwpx', '.pdf', '.txt', '.md', '.csv', '.tsv', '.json', '.xml',
           '.html', '.htm', '.doc', '.xls', '.ppt', '.msg', '.eml', '.log']
SKIP_NAMES = {'node_modules', '.git', '.Trash'}
SKIP_SUFFIX = ('.app', '.photoslibrary', '.bundle', '.framework')
SF_DATALESS = 0x40000000  # macOS: 내용이 클라우드에만 있는 파일(열면 내려받는다)


def nfc(s):
    return unicodedata.normalize('NFC', s)


def real(p):
    return nfc(os.path.realpath(p))


def parse():
    a = argparse.ArgumentParser()
    a.add_argument('--days', '-Days', type=int, default=30)
    a.add_argument('--max-files', '-MaxFiles', type=int, default=300)
    a.add_argument('--max-text', '-MaxText', type=int, default=80)
    a.add_argument('--max-chars', '-MaxChars', type=int, default=4000)
    a.add_argument('--roots', '-Roots', nargs='*', default=[])
    a.add_argument('--only-roots', '-OnlyRoots', action='store_true')  # 지정한 폴더만 본다(최근 항목·문서·다운로드 제외). 시험·직무 프로필용
    a.add_argument('--force', '-Force', action='store_true')  # 이미 읽어 둔 목록이 있어도 다시 읽는다(설치기·sync만 쓴다)
    return a.parse_args()


def main():
    o = parse()
    out = os.path.join(WS, 'memory', 'scan')
    text_dir = os.path.join(out, 'text')
    # 이미 읽어 둔 목록이 있으면 다시 읽지 않는다 — Codex 샌드박스 안에서 다시 돌면 덜 읽히고 지정 폴더 설정도 사라진다
    if os.path.exists(os.path.join(out, 'recent-files.csv')) and not o.force:
        print('이미 읽어 둔 최근 파일 목록이 있습니다(memory/scan/recent-files.csv). 다시 읽지 않습니다. 그 목록과 memory/scan/text를 쓰세요.')
        return 0
    # 범위 설정: 처음 지정한 폴더를 기억해 두고, 다음 새로 고침(sync)에도 같은 범위로 읽는다. 없는 키는 기본값으로 채워 다시 쓴다
    cfg_path = os.path.join(out, 'scan-config.json')
    cfg = {'roots': [], 'onlyRoots': False, 'useDiscovered': True, 'include': [], 'exclude': [], 'maxDepth': 6,
           'extensions': list(DOC_EXT), 'skipOnlineOnly': True}
    if os.path.exists(cfg_path):
        try:
            with open(cfg_path, encoding='utf-8-sig') as f:
                c = json.load(f)
            for k in cfg:
                if c.get(k) is not None:
                    cfg[k] = c[k]
        except Exception:
            pass
    roots = [os.path.abspath(os.path.expanduser(r)) for r in o.roots if r]
    if roots:
        cfg['roots'] = roots
        cfg['onlyRoots'] = bool(o.only_roots)
    as_list = lambda v: [v] if isinstance(v, str) else [x for x in (v or []) if x]
    cfg['roots'] = as_list(cfg['roots'])
    cfg['include'] = as_list(cfg['include'])
    cfg['exclude'] = as_list(cfg['exclude'])
    exts = ['.' + e.strip().lower().lstrip('.') for e in as_list(cfg['extensions']) if e.strip()]
    cfg['extensions'] = exts or list(DOC_EXT)
    try:
        cfg['maxDepth'] = int(cfg['maxDepth']) if int(cfg['maxDepth']) >= 0 else 6
    except Exception:
        cfg['maxDepth'] = 6
    for k in ('onlyRoots', 'useDiscovered', 'skipOnlineOnly'):
        cfg[k] = bool(cfg[k])
    only_roots = o.only_roots or cfg['onlyRoots']
    os.makedirs(out, exist_ok=True)
    with open(cfg_path, 'w', encoding='utf-8') as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    roots = cfg['roots']
    exts = cfg['extensions']
    max_depth = cfg['maxDepth']
    if os.path.isdir(text_dir):  # 이전 스캔 본문이 섞이지 않게
        for n in os.listdir(text_dir):
            try:
                os.remove(os.path.join(text_dir, n))
            except Exception:
                pass
    os.makedirs(text_dir, exist_ok=True)
    since = dt.datetime.now() - dt.timedelta(days=o.days)
    since_ts = since.timestamp()

    ws_real = real(WS)
    sample_real = real(os.path.join(WS, '.agents', 'skills', 'prescan', 'sample'))
    lib = real(os.path.join(HOME, 'Library'))
    cloud = real(os.path.join(HOME, 'Library', 'CloudStorage'))

    def under(p, d):
        return p == d or p.startswith(d.rstrip('/') + '/')

    def expand(p):
        p = p.strip().strip('"').replace('%USERPROFILE%', HOME).replace('\\', '/')
        return os.path.abspath(os.path.expandvars(os.path.expanduser(p))) if p else ''

    def key(p):
        return real(p).rstrip('/').lower()

    # exclude: 와일드카드(* ?)가 있으면 패턴, 없으면 그 폴더와 아래 전체. 단 더 깊은 기본·추가 폴더는 살린다
    excl = []
    for e in cfg['exclude']:
        x = e.strip().replace('\\', '/')
        if any(ch in x for ch in '*?'):
            excl.append((nfc(x).lower(), True))
        elif x:
            excl.append((key(expand(x)), False))

    def excluded(p, root_key=''):
        q = nfc(p).rstrip('/').lower()
        for pat, wild in excl:
            if wild:
                if fnmatch.fnmatchcase(q, pat) or fnmatch.fnmatchcase(q, pat + '/*'):
                    return True
            elif under(q, pat) and (not root_key or under(pat, root_key)):
                return True
        return False

    # ---- 볼 폴더 정하기 ----
    root_list = []

    def add_root(path, kind, status, source):
        if not path:
            return
        if not os.path.isdir(path):
            if status != '자동 발견':
                root_list.append({'path': path, 'key': key(path), 'kind': kind, 'status': '없음', 'source': source, 'files': 0, 'online': 0})
            return
        k = key(path)
        auto = status == '자동 발견'
        for r in root_list:
            if r['status'] == '없음':
                continue
            if r['key'] == k or (auto and r['status'] == '자동 발견' and under(k, r['key'])):
                return
        if auto:
            root_list[:] = [r for r in root_list if not (r['status'] == '자동 발견' and under(r['key'], k))]
        if excluded(real(path), '' if auto else k):
            status = '제외'
        root_list.append({'path': nfc(os.path.abspath(path)), 'key': k, 'kind': kind, 'status': status, 'source': source, 'files': 0, 'online': 0})

    if only_roots:
        for r in roots:
            add_root(expand(r), 'roots', '지정', 'roots')
    else:
        for n, kind in (('Documents', 'documents'), ('Desktop', 'desktop'), ('Downloads', 'downloads')):
            add_root(os.path.join(HOME, n), kind, '기본', 'home')
        if cfg['useDiscovered']:
            # 이미 이 Mac에 동기화된 클라우드 폴더(OneDrive-<회사>, OneDrive-SharedLibraries-<회사>, GoogleDrive-<계정>, Dropbox 등)
            cs = os.path.join(HOME, 'Library', 'CloudStorage')
            try:
                for n in sorted(os.listdir(cs)):
                    if os.path.isdir(os.path.join(cs, n)):
                        kind = ('sharepoint' if n.startswith('OneDrive-SharedLibraries') else 'onedrive' if n.startswith('OneDrive')
                                else 'googledrive' if n.startswith('GoogleDrive') else 'dropbox' if n.startswith('Dropbox') else 'cloud')
                        add_root(os.path.join(cs, n), kind, '자동 발견', 'Library/CloudStorage')
            except Exception:
                pass
            try:  # 예전 OneDrive 앱이 홈 바로 아래 만든 폴더
                for n in sorted(os.listdir(HOME)):
                    if n.startswith('OneDrive') and os.path.isdir(os.path.join(HOME, n)):
                        add_root(os.path.join(HOME, n), 'onedrive', '자동 발견', 'home:OneDrive*')
            except Exception:
                pass
        for r in roots:
            add_root(expand(r), 'roots', '추가', 'roots')
        for r in cfg['include']:
            add_root(expand(r), 'include', '추가', 'scan-config.include')
    active = [r for r in root_list if r['status'] not in ('없음', '제외')]
    root_keys = {r['key'] for r in active}

    def find_root(p):  # 이 경로를 품는 가장 깊은 폴더
        q = nfc(p).rstrip('/').lower()
        best = None
        for r in root_list:
            if r['status'] != '없음' and under(q, r['key']) and (best is None or len(r['key']) > len(best['key'])):
                best = r
        return best

    def skip(p):
        parts = p.split('/')
        if any(x in SKIP_NAMES for x in parts):
            return True
        if under(p, lib) and not under(p, cloud):
            return True
        return under(p, ws_real) and not under(p, sample_real)  # 워크스페이스 자신은 빼되 예시 자료는 읽는다

    found = {}

    def add(path, why, root=None):
        try:
            if not path or not os.path.isfile(path):
                return
            name = nfc(os.path.basename(path))
            ext = os.path.splitext(name)[1].lower()
            if ext not in exts:
                return
            st = os.stat(path)
            if re.match(r'^[~%]\$', name) or name.startswith('._') or st.st_size < 10:  # Office 임시·빈 파일
                return
            rp = real(path)
            if st.st_size > 50 * 1024 * 1024 or skip(rp):
                return
            root = root or find_root(rp)
            if root and root['status'] == '제외':
                return
            if excluded(rp, root['key'] if root and root['status'] != '자동 발견' else ''):
                return
            k = rp.lower()
            if k in found:
                if why not in found[k]['why']:
                    found[k]['why'] += ',' + why
                return
            created = getattr(st, 'st_birthtime', st.st_ctime)
            found[k] = {'path': nfc(os.path.abspath(path)), 'name': name, 'ext': ext, 'kb': round(st.st_size / 1024),
                        'modified': dt.datetime.fromtimestamp(st.st_mtime).strftime('%Y-%m-%d'),
                        'created': dt.datetime.fromtimestamp(created).strftime('%Y-%m-%d'), 'why': why, 'last': st.st_mtime,
                        'online': cfg['skipOnlineOnly'] and bool(getattr(st, 'st_flags', 0) & SF_DATALESS)}
        except Exception:
            pass

    # 1) 열어 본 파일: Spotlight의 마지막 사용일
    if not only_roots:
        try:
            r = subprocess.run(['mdfind', 'kMDItemLastUsedDate >= $time.today(-%d)' % o.days], capture_output=True,
                               text=True, timeout=120, stdin=subprocess.DEVNULL)
            for line in r.stdout.splitlines():
                if line.strip():
                    add(line.strip(), 'opened')
        except Exception:
            pass
    # 2) 수정한 파일, 3) 새로 받은 파일 — 폴더마다 깊이 maxDepth까지. 다른 볼 폴더·제외 폴더·워크스페이스는 들어가지 않는다
    scan_t0 = time.monotonic()  # 클라우드 폴더가 오래 걸리면 그 폴더만 멈춘다. 전체도 2분을 넘기지 않는다
    for ro in active:
        r = ro['path']
        if time.monotonic() - scan_t0 >= 120:
            ro['source'] += ' (시간 상한으로 건너뜀)'
            continue
        root_t0 = time.monotonic()
        root_limit = 30 if ro.get('kind') in ('googledrive', 'onedrive', 'sharepoint', 'cloud', 'dropbox') else 45
        rk = ro['key'] if ro['status'] != '자동 발견' else ''
        is_dl = 'downloads' in r.lower() or '다운로드' in nfc(r)
        base_depth = r.rstrip('/').count('/')
        for dp, dns, fns in os.walk(r, onerror=lambda e: None):
            if time.monotonic() - root_t0 >= root_limit or time.monotonic() - scan_t0 >= 120:
                ro['source'] += ' (시간 상한으로 일부만)'
                break
            depth = dp.rstrip('/').count('/') - base_depth
            keep = []
            for d in sorted(dns):
                if d.startswith('.') or d in SKIP_NAMES or d.endswith(SKIP_SUFFIX) or depth >= max_depth:
                    continue
                rd = real(os.path.join(dp, d))
                if skip(rd) or rd.rstrip('/').lower() in root_keys or excluded(rd, rk):
                    continue
                keep.append(d)
            dns[:] = keep
            for fn in sorted(fns):
                if fn.startswith('.'):
                    continue
                p = os.path.join(dp, fn)
                try:
                    st = os.stat(p)
                except Exception:
                    continue
                created = getattr(st, 'st_birthtime', st.st_ctime)
                if st.st_mtime >= since_ts:
                    add(p, 'modified', ro)
                elif created >= since_ts and is_dl:
                    add(p, 'downloaded', ro)

    lst = sorted(found.values(), key=lambda x: x['last'], reverse=True)[:o.max_files]
    # 원본 사본을 워크스페이스 안(memory/scan/files)에 둔다 — Codex 샌드박스 안에서도 읽을 수 있게. 온라인 전용은 내려받지 않고 목록만
    files_dir = os.path.join(out, 'files')
    if os.path.isdir(files_dir):
        for n in os.listdir(files_dir):
            try:
                os.remove(os.path.join(files_dir, n))
            except Exception:
                pass
    os.makedirs(files_dir, exist_ok=True)
    online_n = 0
    for i, f in enumerate(lst):
        copy_name = '%03d_%s' % (i, f['name'])
        if f['online']:
            online_n += 1
            f['why'] += ',online-only'
            f['copy'] = ''
            continue
        try:
            shutil.copy2(f['path'], os.path.join(files_dir, copy_name))
        except Exception:
            pass
        f['copy'] = 'memory/scan/files/' + copy_name
    cols = ['path', 'copy', 'name', 'ext', 'kb', 'modified', 'created', 'why']
    with open(os.path.join(out, 'recent-files.csv'), 'w', encoding='utf-8-sig', newline='') as fh:
        w = csv.writer(fh, quoting=csv.QUOTE_ALL, lineterminator='\n')
        w.writerow(cols)
        for f in lst:
            w.writerow([f[c] for c in cols])
    # 본 폴더 목록: 온보딩에서 '자동 발견' 폴더를 보여 주고 사용자가 뺄 수 있게(빼면 scan-config.json exclude에 경로를 넣는다)
    for f in lst:
        r = find_root(real(f['path']))
        if r:
            r['files'] += 1
            r['online'] += 1 if f['online'] else 0
    rcols = ['path', 'kind', 'status', 'source', 'files', 'online']
    with open(os.path.join(out, 'scan-roots.csv'), 'w', encoding='utf-8-sig', newline='') as fh:
        w = csv.writer(fh, quoting=csv.QUOTE_ALL, lineterminator='\n')
        w.writerow(rcols)
        for r in root_list:
            w.writerow([r[c] for c in rcols])

    # PDF 본문: 이 Python에 pypdf가 있으면 바로, 없으면 Codex 앱이 받아 둔 Python(pypdf 포함)으로
    pdf_mode = None
    try:
        import pypdf  # noqa: F401
        pdf_mode = 'self'
    except Exception:
        if os.path.exists(RUNTIME_PY):
            pdf_mode = 'runtime'
    pdf_py = os.path.join(HERE, 'pdftext.py')

    def pdf_text(p):
        if pdf_mode == 'self':
            from pypdf import PdfReader
            try:
                rd = PdfReader(p)
                if rd.is_encrypted:
                    rd.decrypt('')
                parts = []
                for pg in rd.pages[:3]:
                    parts.append(pg.extract_text() or '')
                    if sum(map(len, parts)) > o.max_chars:
                        break
                return '\n'.join(parts).strip()[:o.max_chars]
            except Exception:
                return ''
        fd, tmp = tempfile.mkstemp(prefix='workmate-pdftext-', suffix='.txt')
        os.close(fd)
        try:
            subprocess.run([RUNTIME_PY, pdf_py, p, tmp, str(o.max_chars)], capture_output=True, timeout=120,
                           stdin=subprocess.DEVNULL)
            with open(tmp, encoding='utf-8', errors='replace') as fh:
                return fh.read()
        except Exception:
            return ''
        finally:
            try:
                os.remove(tmp)
            except Exception:
                pass

    # 본문 일부 추출 (설치 없이 되는 형식만)
    def zip_text(p, pattern):
        parts = []
        total = 0
        with zipfile.ZipFile(p) as z:
            for e in sorted(n for n in z.namelist() if re.search(pattern, n)):
                x = z.read(e).decode('utf-8', errors='replace')
                x = re.sub(r'</w:p>|</a:p>|</row>', '\n', x)
                x = re.sub(r'<[^>]+>', ' ', x)
                x = re.sub(r'[ \t]+', ' ', html.unescape(x))
                parts.append(x + '\n')
                total += len(x) + 1
                if total > o.max_chars:
                    break
        return ''.join(parts)

    n = 0
    skipped = 0
    text_limit = None if only_roots else o.max_text
    for f in lst:
        if text_limit is not None and n >= text_limit:
            break
        if f['online']:  # 온라인 전용은 열지 않는다(열면 내려받는다)
            continue
        t = None
        e = f['ext']
        try:
            if e == '.docx':
                t = zip_text(f['path'], r'^word/document\.xml$')
            elif e == '.pptx':
                t = zip_text(f['path'], r'^ppt/slides/slide\d+\.xml$')
            elif e == '.xlsx':
                t = zip_text(f['path'], r'^xl/(sharedStrings|worksheets/sheet\d+)\.xml$')
            elif e == '.hwpx':
                t = zip_text(f['path'], r'^Contents/section\d+\.xml$')
            elif e == '.pdf':
                if pdf_mode:
                    t = pdf_text(f['path'])
                else:
                    skipped += 1
            elif e in ('.txt', '.md', '.csv', '.tsv', '.json', '.xml', '.html', '.htm', '.log'):
                with open(f['path'], encoding='utf-8-sig', errors='replace') as fh:
                    t = ''.join(line for _, line in zip(range(200), fh))
            else:
                skipped += 1
        except Exception:
            t = None
        if t:
            t = t.strip()
            if len(t) > o.max_chars:
                t = t[:o.max_chars]
            safe = re.sub(r'[^\w\.\-가-힣]', '_', f['name'])
            with open(os.path.join(text_dir, '%03d_%s.txt' % (n, safe)), 'w', encoding='utf-8') as fh:
                fh.write('# %s\n# 수정 %s / 근거 %s\n\n%s\n' % (f['path'], f['modified'], f['why'], t))
            n += 1
    # 사람이 보는 범위 요약: memory/env.md 끝의 '## 사전 스캔 범위' 절만 바꾼다(다른 내용은 그대로)
    env_path = os.path.join(WS, 'memory', 'env.md')
    yn = lambda b: '예' if b else '아니오'
    sec = ['## 사전 스캔 범위 (scan이 자동 기록 — 바꾸려면 memory/scan/scan-config.json, 폴더별 결과는 memory/scan/scan-roots.csv)', '',
           '- 확인 시각: %s / 최근 %d일, 깊이 %d, 지정 폴더만 보기: %s, 온라인 전용은 목록만: %s' % (
               dt.datetime.now().strftime('%Y-%m-%d %H:%M'), o.days, max_depth, yn(only_roots), yn(cfg['skipOnlineOnly']))]
    sec += ['- [%s] %s — %d개' % (r['status'], r['path'], r['files']) for r in root_list]
    try:
        with open(env_path, encoding='utf-8-sig') as fh:
            env_text = fh.read()
    except Exception:
        env_text = ''
    cut = env_text.find('## 사전 스캔 범위')
    if cut >= 0:
        env_text = env_text[:cut]
    env_text = env_text.rstrip()
    with open(env_path, 'w', encoding='utf-8') as fh:
        fh.write((env_text + '\n\n' if env_text else '') + '\n'.join(sec) + '\n')

    groups = {}
    for f in lst:
        g = f['why'].split(',')[0]
        groups[g] = groups.get(g, 0) + 1
    by_why = ', '.join('%s %d' % (k, v) for k, v in groups.items())
    pdf_note = 'PDF 읽기 가능' if pdf_mode else 'PDF 읽기 도구 없음'
    auto_n = sum(1 for r in root_list if r['status'] == '자동 발견')
    excl_n = sum(1 for r in root_list if r['status'] == '제외')
    if auto_n or excl_n or online_n:
        print('본 폴더 %d개(자동 발견 %d개, 제외 %d개), 온라인 전용 %d개는 내려받지 않고 목록만 → memory/scan/scan-roots.csv' % (
            len(active), auto_n, excl_n, online_n))
    print('찾은 파일 %d개 (%s), 본문 추출 %d개, 본문 미지원 형식 %d개, %s → memory/scan/' % (len(lst), by_why, n, skipped, pdf_note))
    return 0


if __name__ == '__main__':
    sys.exit(main())
