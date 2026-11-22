# 기억 검색: memory/index.db (SQLite FTS5 trigram) 에서 찾는다. 3글자 이상 단어가 잘 잡힌다. (search.ps1의 Mac 판)
# 사용: python3 search.py "품질 보고" [-n 10] [--kind memory/sessions]
import argparse
import os
import re
import sqlite3
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..'))
sys.dont_write_bytecode = True  # 워크스페이스에 __pycache__를 남기지 않는다
sys.path.insert(0, HERE)
from sync import need_trigram  # noqa: E402


def like(s):
    return '%' + re.sub(r'([\\%_])', r'\\\1', s) + '%'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('q')
    ap.add_argument('-n', '--n', type=int, default=10)
    ap.add_argument('--kind', '-kind', default='')
    o = ap.parse_args()
    need_trigram()
    db_path = os.path.join(WS, 'memory', 'index.db')
    if not os.path.exists(db_path):
        subprocess.run([sys.executable, os.path.join(HERE, 'sync.py'), '--quiet'], stdin=subprocess.DEVNULL)
    terms = [t for t in re.split(r'\s+', o.q) if t]
    long_ = [t for t in terms if len(t) >= 3]
    short = [t for t in terms if len(t) < 3]
    args = []
    if long_:
        match = ' AND '.join('"' + t.replace('"', '""') + '"' for t in long_)
        sql = "SELECT path, date, title, snippet(docs, 4, '[', ']', ' … ', 24) FROM docs WHERE docs MATCH ?"
        args.append(match)
    else:
        sql = 'SELECT path, date, title, substr(body, max(1, instr(body, ?) - 60), 160) FROM docs WHERE 1=1'
        args.append(short[0] if short else '')
    for s in short:
        sql += " AND body LIKE ? ESCAPE '\\'"
        args.append(like(s))
    if o.kind:
        sql += ' AND kind = ?'
        args.append(o.kind)
    sql += ' ORDER BY date DESC LIMIT %d' % o.n
    db = sqlite3.connect(db_path)
    try:
        rows = db.execute(sql, args).fetchall()
    finally:
        db.close()
    if not rows:
        print('검색 결과 없음: ' + o.q)
        return 0
    for r in rows:
        print('- %s  %s  「%s」\n    %s' % (r[1], r[0], r[2], re.sub(r'\s+', ' ', r[3] or '').strip()))
    return 0


if __name__ == '__main__':
    sys.exit(main())
