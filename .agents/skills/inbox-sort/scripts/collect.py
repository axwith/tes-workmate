# 자료를 00-inbox/날짜/ 로 복사한다(원본은 그대로). (collect.ps1의 Mac 판, 표준 라이브러리만)
# 사용: python3 collect.py --days 30            # prescan 기준(열어 봄·수정함·새로 받음)으로 최근 파일 복사
#       python3 collect.py --from "~/업무/품질"  # 특정 폴더의 문서 파일 복사
import argparse
import csv
import datetime as dt
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..'))
DOC_EXT = ['.docx', '.xlsx', '.pptx', '.hwp', '.hwpx', '.pdf', '.txt', '.md', '.csv', '.tsv', '.json', '.doc', '.xls', '.ppt', '.msg', '.eml']


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--days', '-Days', type=int, default=30)
    ap.add_argument('--from', '-From', dest='src', default='')
    ap.add_argument('--max-files', '-MaxFiles', type=int, default=300)
    o = ap.parse_args()
    dest = os.path.join(WS, '00-inbox', dt.date.today().strftime('%Y-%m-%d'))
    os.makedirs(dest, exist_ok=True)

    items = []
    if o.src:
        root = os.path.abspath(os.path.expanduser(o.src))
        base = root.rstrip('/').count('/')
        for dp, dns, fns in os.walk(root, onerror=lambda e: None):
            depth = dp.rstrip('/').count('/') - base
            dns[:] = sorted(d for d in dns if not d.startswith('.') and depth < 6)
            for fn in sorted(fns):
                p = os.path.join(dp, fn)
                if fn.startswith('.') or os.path.splitext(fn)[1].lower() not in DOC_EXT:
                    continue
                try:
                    st = os.stat(p)
                except Exception:
                    continue
                if st.st_size >= 50 * 1024 * 1024:
                    continue
                items.append({'path': p, 'modified': dt.datetime.fromtimestamp(st.st_mtime).strftime('%Y-%m-%d'), 'why': 'folder'})
                if len(items) >= o.max_files:
                    break
            if len(items) >= o.max_files:
                break
    else:
        scan = os.path.join(WS, '.agents', 'skills', 'prescan', 'scripts', 'scan.py')
        subprocess.run([sys.executable, scan, '--days', str(o.days), '--max-files', str(o.max_files), '--max-text', '0'],
                       capture_output=True, stdin=subprocess.DEVNULL)
        try:
            with open(os.path.join(WS, 'memory', 'scan', 'recent-files.csv'), encoding='utf-8-sig', newline='') as f:
                items = [r for r in csv.DictReader(f) if 'online-only' not in r.get('why', '')]  # 온라인 전용은 내려받지 않는다
        except Exception:
            items = []

    rows = []
    n = 0
    for it in items:
        name = os.path.basename(it['path'])
        target = os.path.join(dest, name)
        stem, ext = os.path.splitext(name)
        i = 1
        while os.path.exists(target):
            target = os.path.join(dest, '%s_%d%s' % (stem, i, ext))
            i += 1
        try:
            shutil.copy2(it['path'], target)
        except Exception:
            continue
        n += 1
        rows.append([os.path.basename(target), it['path'], it.get('modified', ''), it.get('why', '')])
    with open(os.path.join(dest, '_목록.csv'), 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f, quoting=csv.QUOTE_ALL, lineterminator='\n')
        w.writerow(['file', 'from', 'modified', 'why'])
        w.writerows(rows)
    print('복사 %d개 → %s' % (n, dest))
    if not os.environ.get('WORKMATE_NO_OPEN'):
        subprocess.run(['open', dest], stdin=subprocess.DEVNULL)
    return 0


if __name__ == '__main__':
    sys.exit(main())
