# memory/work-map.json 을 읽어 reports/YYYY-MM-DD_내-업무-한눈에.html 을 만든다(고정 디자인, 외부 파일 없음). (render.ps1의 Mac 판)
# 사용: python3 render.py [--open]
import argparse
import datetime as dt
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..'))


def render(open_it=False, quiet=False):
    with open(os.path.join(WS, 'memory', 'work-map.json'), encoding='utf-8-sig') as f:
        data = f.read()
    json.loads(data)  # 형식 오류면 여기서 멈춘다
    with open(os.path.join(HERE, 'dashboard.html'), encoding='utf-8-sig') as f:
        tpl = f.read()
    html = tpl.replace('/*DATA*/null', data.replace('</', '<\\/'))
    out = os.path.join(WS, 'reports', '%s_내-업무-한눈에.html' % dt.date.today().strftime('%Y-%m-%d'))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'w', encoding='utf-8', newline='') as f:
        f.write(html)
    if not quiet:
        print('만듦: ' + out)
    if open_it:
        subprocess.run(['open', out], stdin=subprocess.DEVNULL)
    return out


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--open', '-Open', action='store_true')
    render(ap.parse_args().open)
    sys.exit(0)
