# 최근에 쓴 파일 목록과 본문 일부를 이 워크스페이스 memory/scan/ 에 만든다. (scan.ps1의 Mac 판)
# 설치 없이 macOS 기본 python3(표준 라이브러리)로 돈다. pypdf가 있으면 PDF 본문도 뽑는다. 원본 파일은 읽기만 한다.
# 사용: python3 scan.py [--days 30] [--max-files 300] [--max-text 80] [--roots "~/업무"] [--only-roots] [--force]
import argparse
import csv
import datetime as dt
import html
import json
import os
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
    # 처음 지정한 폴더 설정을 기억해 두고, 다음 새로 고침(sync)에도 같은 범위로 읽는다
    roots = [os.path.abspath(os.path.expanduser(r)) for r in o.roots if r]
    only_roots = o.only_roots
    cfg_path = os.path.join(out, 'scan-config.json')
    if roots:
        os.makedirs(out, exist_ok=True)
        with open(cfg_path, 'w', encoding='utf-8') as f:
            json.dump({'roots': roots, 'onlyRoots': bool(only_roots)}, f, ensure_ascii=False, indent=2)
    elif os.path.exists(cfg_path):
        try:
            with open(cfg_path, encoding='utf-8-sig') as f:
                c = json.load(f)
            r = c.get('roots') or []
            roots = [r] if isinstance(r, str) else list(r)
            if c.get('onlyRoots'):
                only_roots = True
        except Exception:
            pass
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

    def skip(p):
        parts = p.split('/')
        if any(x in SKIP_NAMES for x in parts):
            return True
        if under(p, lib) and not under(p, cloud):
            return True
        return under(p, ws_real) and not under(p, sample_real)  # 워크스페이스 자신은 빼되 예시 자료는 읽는다

    found = {}

    def add(path, why):
        try:
            if not path or not os.path.isfile(path):
                return
            name = nfc(os.path.basename(path))
            ext = os.path.splitext(name)[1].lower()
            if ext not in DOC_EXT:
                return
            st = os.stat(path)
            if re.match(r'^[~%]\$', name) or name.startswith('._') or st.st_size < 10:  # Office 임시·빈 파일
                return
            rp = real(path)
            if st.st_size > 50 * 1024 * 1024 or skip(rp):
                return
            k = rp.lower()
            if k in found:
                if why not in found[k]['why']:
                    found[k]['why'] += ',' + why
                return
            created = getattr(st, 'st_birthtime', st.st_ctime)
            found[k] = {'path': nfc(os.path.abspath(path)), 'name': name, 'ext': ext, 'kb': round(st.st_size / 1024),
                        'modified': dt.datetime.fromtimestamp(st.st_mtime).strftime('%Y-%m-%d'),
                        'created': dt.datetime.fromtimestamp(created).strftime('%Y-%m-%d'), 'why': why, 'last': st.st_mtime}
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
    # 2) 수정한 파일, 3) 새로 받은 파일
    home_dirs = [os.path.join(HOME, 'Documents'), os.path.join(HOME, 'Desktop'), os.path.join(HOME, 'Downloads')]
    try:
        cs = os.path.join(HOME, 'Library', 'CloudStorage')
        for n in sorted(os.listdir(cs)):
            if os.path.isdir(os.path.join(cs, n)):
                home_dirs.append(os.path.join(cs, n))
    except Exception:
        pass
    home_dirs += roots
    if only_roots:
        home_dirs = list(roots)
    seen = set()
    for r in home_dirs:
        if r in seen or not os.path.isdir(r):
            continue
        seen.add(r)
        is_dl = 'downloads' in r.lower() or '다운로드' in nfc(r)
        base_depth = r.rstrip('/').count('/')
        for dp, dns, fns in os.walk(r, onerror=lambda e: None):
            depth = dp.rstrip('/').count('/') - base_depth
            keep = []
            for d in sorted(dns):
                if d.startswith('.') or d in SKIP_NAMES or d.endswith(SKIP_SUFFIX) or depth >= 6:
                    continue
                if skip(real(os.path.join(dp, d))):
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
                    add(p, 'modified')
                elif created >= since_ts and is_dl:
                    add(p, 'downloaded')

    lst = sorted(found.values(), key=lambda x: x['last'], reverse=True)[:o.max_files]
    # 원본 사본을 워크스페이스 안(memory/scan/files)에 둔다 — Codex 샌드박스 안에서도 읽을 수 있게
    files_dir = os.path.join(out, 'files')
    if os.path.isdir(files_dir):
        for n in os.listdir(files_dir):
            try:
                os.remove(os.path.join(files_dir, n))
            except Exception:
                pass
    os.makedirs(files_dir, exist_ok=True)
    for i, f in enumerate(lst):
        copy_name = '%03d_%s' % (i, f['name'])
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
    groups = {}
    for f in lst:
        g = f['why'].split(',')[0]
        groups[g] = groups.get(g, 0) + 1
    by_why = ', '.join('%s %d' % (k, v) for k, v in groups.items())
    pdf_note = 'PDF 읽기 가능' if pdf_mode else 'PDF 읽기 도구 없음'
    print('찾은 파일 %d개 (%s), 본문 추출 %d개, 본문 미지원 형식 %d개, %s → memory/scan/' % (len(lst), by_why, n, skipped, pdf_note))
    return 0


if __name__ == '__main__':
    sys.exit(main())
