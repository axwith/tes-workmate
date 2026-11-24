# 팀즈(회사 Microsoft 365)에 공유된 파일과 채팅을 읽기 전용으로 본다. (teams.ps1의 Mac 판, 표준 라이브러리만)
# 사용: python3 teams.py status | login [--with-channel-messages] | login-wait [--wait 90] | logout
#       python3 teams.py teams | channels <팀> | files <팀> [채널] [--depth 2] | shared | recent
#       python3 teams.py get <driveId> <itemId>          # 사본을 00-inbox/teams/ 로(50MB까지)
#       python3 teams.py chats | chat-messages <채팅id 또는 이름> [--top 20]
#       python3 teams.py channel-messages <팀> <채널> --with-channel-messages   # 회사 관리자 승인이 있어야 된다
#       python3 teams.py setup-m365                     # 팀즈 도구(CLI for Microsoft 365)를 사용자 폴더에 설치(관리자 권한 없음)
# 경로 순서: m365(설치·로그인돼 있으면) → 기본 방식(Graph 직접 호출) → 둘 다 안 되면 한 줄.
# 보내기·수정·삭제는 하지 않는다. 연결이 안 되면(로그인 전·관리자 승인 필요·회사망 차단·403) 한 줄만 쓰고 종료 코드 0으로 끝난다.
# 로그인 정보는 ~/.workmate/teams-token.json(기본 방식)과 m365 자체 저장소(키체인·홈 폴더)에만 둔다(워크스페이스·로그에 쓰지 않는다).
import argparse
import csv
import datetime as dt
import hashlib
import html
import json
import os
import platform
import random
import re
import shutil
import signal
import ssl
import subprocess
import sys
import tarfile
import time
import urllib.error
import urllib.parse
import urllib.request

CLIENT_ID = '14d82eec-204b-4c2f-b7e8-296a70dab67e'  # Microsoft Graph Command Line Tools(Microsoft 공용 앱)
LOGIN_HOST = os.environ.get('WORKMATE_TEAMS_LOGIN_HOST') or 'https://login.microsoftonline.com'  # 시험용 바꾸기
GRAPH = os.environ.get('WORKMATE_TEAMS_GRAPH') or 'https://graph.microsoft.com/v1.0'
SCOPES = 'User.Read Team.ReadBasic.All Channel.ReadBasic.All Files.Read.All Sites.Read.All Chat.Read offline_access'
CHAN_SCOPE = 'ChannelMessage.Read.All'  # 위임이어도 관리자 동의가 필요하다 — 옵션으로만
MAX_BYTES = 50 * 1024 * 1024
CACHE_DIR = os.environ.get('WORKMATE_TEAMS_CACHE') or os.path.expanduser('~/.workmate')
TOKEN_FILE = os.path.join(CACHE_DIR, 'teams-token.json')
PENDING_FILE = os.path.join(CACHE_DIR, 'teams-login.json')
HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..'))
OUT_DIR = os.path.join(WS, 'memory', 'teams')
INBOX_DIR = os.path.join(WS, '00-inbox', 'teams')
FAIL_LINE = '팀즈 연결이 안 됩니다. PC에 있는 파일로 진행합니다.'
NET_ERR = 'network'
# CLI for Microsoft 365(m365) — setup-m365가 사용자 폴더에만 설치한다
M365_PKG = '@pnp/cli-microsoft365'
M365_VER = '12.0.0'
NODE_PIN = 'v24.22.3'          # Node LTS 고정. 받을 수 없으면 index.json에서 아래 주 버전의 최신 LTS로
NODE_MAJORS = (24, 22)         # Node 26은 2026-11 맥 시험에서 keytar(로그인 저장) 문제가 있었다
NODE_DIST = os.environ.get('WORKMATE_NODE_DIST') or 'https://nodejs.org/dist'   # 시험용 바꾸기
NPM_REGISTRY = os.environ.get('WORKMATE_NPM_REGISTRY') or ''                    # 시험용 바꾸기
SETUP_SECONDS = 300
NODE_DIR = os.path.join(CACHE_DIR, 'node')
M365_DIR = os.path.join(CACHE_DIR, 'm365')
M365_REC = os.path.join(CACHE_DIR, 'm365.json')
SETUP_LOG = os.path.join(CACHE_DIR, 'teams-setup.log')
M365_PENDING = os.path.join(CACHE_DIR, 'teams-m365-login.json')
M365_LOGIN_LOG = os.path.join(CACHE_DIR, 'teams-m365-login.log')
SETUP_FAIL = '팀즈 도구를 설치하지 못했습니다. 기본 방식으로 진행합니다.'


class Stop(Exception):
    pass


def say(m):
    print(m, flush=True)


def done(m=None):
    if m:
        say(m)
    raise Stop()


QUIET = [False]   # login의 '이미 연결됐나' 확인 중에는 실패 줄을 쓰지 않는다


def fail(tag):
    if QUIET[0]:
        raise Stop()
    done(f'{FAIL_LINE} [{tag}]')


def now():
    return int(time.time())


def pick(*vals):
    for v in vals:
        if v not in (None, ''):
            return v
    return ''


def g(d, *keys):
    for k in keys:
        if not isinstance(d, dict):
            return None
        d = d.get(k)
    return d


def ssl_ctx():
    ctx = ssl.create_default_context()
    try:
        if not ctx.cert_store_stats().get('x509_ca') and os.path.exists('/etc/ssl/cert.pem'):
            ctx.load_verify_locations('/etc/ssl/cert.pem')  # 독립 실행형 Python은 인증서 목록이 비어 있을 수 있다
    except Exception:
        pass
    return ctx


CTX = ssl_ctx()


def read_json(p):
    try:
        with open(p, encoding='utf-8') as f:
            d = json.load(f)
        return d if isinstance(d, dict) else None
    except Exception:
        return None


def save_json(p, obj):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        json.dump(obj, f)
    try:
        os.chmod(p, 0o600)
    except Exception:
        pass


def fmt_d(v):
    if not v:
        return ''
    s = str(v)
    try:
        return dt.datetime.fromisoformat(re.sub(r'\.\d+', '', s.replace('Z', '+00:00'))).astimezone().strftime('%Y-%m-%d %H:%M')
    except Exception:
        return s[:16].replace('T', ' ')


def size(b):
    if b in (None, ''):
        return ''
    b = float(b)
    return f'{b / 1048576:.1f}MB' if b >= 1048576 else f'{-(-b // 1024):,.0f}KB'


def text(h):
    t = re.sub(r'<br\s*/?>|</p>', ' ', str(h or ''))
    t = re.sub(r'<[^>]+>', '', t)
    t = re.sub(r'\s+', ' ', html.unescape(t)).strip()
    return t[:500] + '…' if len(t) > 500 else t


def safe(s):
    return re.sub(r'[\\/:*?"<>|\s]+', '_', s or '').strip('_.')


def http(method, url, data=None, headers=None, timeout=60):
    """(상태 코드, 본문 bytes, 헤더). 네트워크 오류는 코드 0."""
    body = urllib.parse.urlencode(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    if body is not None:
        req.add_header('Content-Type', 'application/x-www-form-urlencoded')
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
            return r.status, r.read(), r.headers
    except urllib.error.HTTPError as e:
        try:
            b = e.read()
        except Exception:
            b = b''
        return e.code, b, e.headers
    except Exception:
        return 0, b'', {}


def tag_of(code, body):
    err = desc = ''
    try:
        j = json.loads(body.decode('utf-8', 'replace'))
        err = j.get('error') if isinstance(j.get('error'), str) else g(j, 'error', 'code') or ''
        desc = j.get('error_description') or ''
    except Exception:
        pass
    m = re.search(r'AADSTS\d+', desc)
    aad = ' ' + m.group(0) if m else ''
    if re.search(r'AADSTS(65001|65004|90094|90008)', desc) or err == 'consent_required':
        return 'admin-consent' + aad
    if re.search(r'AADSTS(53000|53001|53003|50105|7000112|700016|50020|500011)', desc):
        return 'policy' + aad
    if err == 'expired_token':
        return 'expired'
    if err in ('authorization_declined', 'access_denied'):
        return 'declined'
    if err == 'invalid_grant':
        return 'login-needed' + aad
    if code == 0:
        return NET_ERR
    if code == 401:
        return 'login-needed'
    if code == 403:
        return 'forbidden'
    return f'error {code}{aad}'


def post_token(form):
    code, body, _ = http('POST', f'{LOGIN_HOST}/organizations/oauth2/v2.0/token', data=form, timeout=30)
    try:
        j = json.loads(body.decode('utf-8', 'replace'))
    except Exception:
        j = {}
    if code == 200 and j.get('access_token'):
        return {'ok': True, 'data': j}
    return {'ok': False, 'error': j.get('error', '') if isinstance(j, dict) else '', 'tag': tag_of(code, body)}


def save_tokens(d, scope, chan, old=None):
    save_json(TOKEN_FILE, {'access_token': d.get('access_token', ''), 'refresh_token': pick(d.get('refresh_token'), (old or {}).get('refresh_token')),
                           'expires_at': now() + int(d.get('expires_in') or 3600), 'scope': scope, 'channel_messages': bool(chan)})


FORCE_REFRESH = [False]


def get_token(chan=False):
    c = read_json(TOKEN_FILE)
    if not c or not c.get('refresh_token'):
        fail('login-needed')
    has = bool(c.get('channel_messages'))
    try:
        exp = int(c.get('expires_at') or 0)
    except Exception:
        exp = 0
    if not FORCE_REFRESH[0] and c.get('access_token') and exp > now() + 120 and (not chan or has):
        return c['access_token']
    scope = f'{SCOPES} {CHAN_SCOPE}' if (chan or has) else SCOPES
    r = post_token({'grant_type': 'refresh_token', 'client_id': CLIENT_ID, 'refresh_token': c['refresh_token'], 'scope': scope})
    if not r['ok']:
        if chan and not has and r['tag'].startswith('admin-consent'):
            done(f"채널 메시지는 회사 관리자 승인이 있어야 읽을 수 있습니다. 파일·채팅은 그대로 쓸 수 있습니다. [{r['tag']}]")
        if re.match(r'(admin-consent|policy|network)', r['tag']):
            fail(r['tag'])
        fail('login-needed')
    save_tokens(r['data'], scope, chan or has, c)
    FORCE_REFRESH[0] = False
    return r['data']['access_token']


# ---------- m365 경로 ----------
def m365_cmd():
    """설치된 m365 실행 명령(list) 또는 None. setup-m365 기록이 먼저, 없으면 PATH의 m365."""
    r = read_json(M365_REC)
    if r and isinstance(r.get('cmd'), list) and r['cmd'] and all(os.path.isfile(x) for x in r['cmd']):
        return r['cmd']
    p = shutil.which('m365')
    return [p] if p else None


def m365_run(args, timeout=120):
    """(종료 코드, 표준 출력, 표준 오류). 실행 자체가 안 되면 코드 -1."""
    cmd = m365_cmd()
    if not cmd:
        return -1, '', 'no m365'
    env = dict(os.environ, CLIMICROSOFT365_NOUPDATE='1')
    try:
        p = subprocess.run(cmd + args, capture_output=True, timeout=timeout, env=env, stdin=subprocess.DEVNULL)
        return p.returncode, p.stdout.decode('utf-8', 'replace'), p.stderr.decode('utf-8', 'replace')
    except Exception as e:
        return -1, '', str(e)


def m365_who():
    """m365에 로그인돼 있으면 계정 이름, 아니면 None."""
    rc, out, _ = m365_run(['status', '-o', 'json'], 60)
    if rc != 0:
        return None
    try:
        j = json.loads(out)
    except Exception:
        return None
    return j.get('connectedAs') if isinstance(j, dict) and j.get('connectedAs') else None


def m365_tag(e):
    """m365 오류문 → 한 줄 사유. m365는 상태 코드를 주지 않아 문구로 가른다."""
    m = re.search(r'AADSTS\d+', e or '')
    aad = ' ' + m.group(0) if m else ''
    if re.search(r'AADSTS(65001|65004|90094|90008)', e) or re.search(r'consent', e, re.I):
        return 'admin-consent' + aad
    if re.search(r'AADSTS(53000|53001|53003|50105|7000112|700016|50020|500011)', e):
        return 'policy' + aad
    if re.search(r'Log in to Microsoft 365 first|login has expired|Sign in again|invalid_grant|AADSTS(50173|700082|70043|50076|50078)', e, re.I):
        return 'login-needed m365' + aad
    if re.search(r'ENOTFOUND|EAI_AGAIN|ECONNREFUSED|ECONNRESET|ETIMEDOUT|ENETUNREACH|socket hang up|getaddrinfo', e, re.I):
        return NET_ERR
    if re.search(r'Forbidden|Access ?denied|Insufficient privileges|Authorization_RequestDenied|\b403\b', e, re.I):
        return 'forbidden'
    return 'error m365'


def m365_get(url):
    """(True, JSON) 또는 (False, 오류문). m365 request가 토큰·재시도(429)를 맡는다."""
    rc, out, err = m365_run(['request', '--url', url, '-o', 'json'])
    if rc == 0:
        try:
            j = json.loads(out) if out.strip() else {}
            return True, (j if isinstance(j, dict) else {'value': j})
        except Exception:
            return False, 'bad json'
    return False, (err or out).strip()


def m365_pending_alive(p):
    try:
        os.kill(int(p.get('pid') or 0), 0)
        return True
    except Exception:
        return False


def m365_login_start(chan):
    """m365 디바이스 코드 로그인을 뒤에서 띄우고 주소·코드를 돌려준다. 안 되면 None(기본 방식으로)."""
    cmd = m365_cmd()
    if not cmd:
        return None
    os.makedirs(CACHE_DIR, exist_ok=True)
    env = dict(os.environ, CLIMICROSOFT365_NOUPDATE='1')
    try:
        with open(M365_LOGIN_LOG, 'w', encoding='utf-8') as f:
            pr = subprocess.Popen(cmd + ['login', '--authType', 'deviceCode', '--appId', CLIENT_ID, '--tenant', 'organizations'],
                                  stdout=f, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, env=env, start_new_session=True)
    except Exception:
        return None
    end = time.time() + 25
    while time.time() < end:
        time.sleep(1)
        try:
            s = open(M365_LOGIN_LOG, encoding='utf-8', errors='replace').read()
        except Exception:
            s = ''
        url = re.search(r'https://\S*(devicelogin|/device)\S*', s)
        code = re.search(r'code\s+([A-Z0-9]{6,12})\b', s) or re.search(r'\b([A-Z0-9]{8,10})\b', s)
        if url and code:
            save_json(M365_PENDING, {'pid': pr.pid, 'expires_at': now() + 900, 'channel_messages': bool(chan)})
            return url.group(0).rstrip('.,'), code.group(1)
        if pr.poll() is not None:
            break
    try:
        os.killpg(pr.pid, signal.SIGTERM)
    except Exception:
        pass
    return None


MODE = [None]   # None: 아직 모름, 'm365', 'rest'
SOFT_MISS = [False]


def graph(path, chan=False, soft=False):
    """Graph GET. m365가 있으면 m365 request로, 안 되면 기본 방식(REST)으로.
    REST: 429·503·504는 Retry-After만큼 기다렸다 다시, 401은 토큰을 한 번 새로 받아 다시. soft면 막힌 API는 None."""
    url = path if re.match(r'https?://', path) else GRAPH + path
    if MODE[0] != 'rest' and m365_cmd():
        ok, val = m365_get(url)
        if ok:
            MODE[0] = 'm365'
            return val
        tag = m365_tag(val)
        if not (read_json(TOKEN_FILE) or {}).get('refresh_token'):   # 기본 방식 로그인도 없으면 m365 사유로 끝낸다
            if soft and not re.match(r'(login-needed|network|admin-consent|policy)', tag):
                return None
            if chan and (tag == 'forbidden' or tag.startswith('admin-consent')):
                done(f'채널 메시지는 회사 관리자 승인이 있어야 읽을 수 있습니다. 파일·채팅은 그대로 쓸 수 있습니다. [{tag}]')
            fail(tag)
        if MODE[0] is None:   # 처음부터 m365가 안 되면 이번 실행은 기본 방식으로
            MODE[0] = 'rest'
    tok = get_token(chan)
    again = False
    for n in range(1, 5):
        code, body, hdr = http('GET', url, headers={'Authorization': f'Bearer {tok}', 'Accept': 'application/json'})
        if code == 200:
            try:
                return json.loads(body.decode('utf-8'))
            except Exception:
                fail('error')
        if code in (429, 503, 504) and n < 4:
            try:
                w = min(int(hdr.get('Retry-After') or 0), 30)
            except Exception:
                w = 0
            time.sleep(w if w > 0 else 2 ** n)
            continue
        if code == 401 and not again:
            FORCE_REFRESH[0] = True
            tok = get_token(chan)
            again = True
            continue
        if soft and code in (400, 403, 404, 405, 410, 501):
            return None
        fail(tag_of(code, body))
    if soft:
        return None
    fail('busy')


def get_all(path, mx=500, chan=False, soft=False):
    items, nxt, pages = [], path, 0
    SOFT_MISS[0] = False
    while nxt and len(items) < mx and pages < 50:
        r = graph(nxt, chan, soft)
        if r is None:
            SOFT_MISS[0] = True
            break
        for v in r.get('value') or []:
            if len(items) >= mx:
                break
            items.append(v)
        nxt = r.get('@odata.nextLink')
        pages += 1
    return items


def write_result(rows, name, cols, show):
    """memory/teams/ 에 CSV로 남기고 화면에는 앞 40줄만 표로 보여 준다."""
    rows = [r for r in rows if r]
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, f"{name}-{dt.datetime.now():%Y%m%d-%H%M%S}.csv")
    with open(path, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction='ignore', quoting=csv.QUOTE_ALL)
        w.writeheader()
        w.writerows(rows)
    say(f'{len(rows)}건 → {os.path.relpath(path, WS)}')
    if rows:
        say('  ' + ' | '.join(show))
    for r in rows[:40]:
        say('  ' + ' | '.join(str(r.get(k) or '') for k in show))
    if len(rows) > 40:
        say(f'  … 나머지 {len(rows) - 40}건은 CSV에 있습니다')


def find_one(lst, q, what, list_cmd):
    hit = [x for x in lst if x.get('id') == q] or [x for x in lst if x.get('displayName') == q] \
        or [x for x in lst if q.lower() in (x.get('displayName') or '').lower()]
    if len(hit) == 1:
        return hit[0]
    if hit:
        done(f"'{q}'에 맞는 {what}이 여러 개입니다: " + ', '.join(x.get('displayName') or '' for x in hit[:10]))
    done(f"'{q}' {what}을 찾지 못했습니다. {list_cmd}로 목록을 봅니다.")


def resolve_team(q):
    if not q:
        done('팀 이름이 필요합니다. 예: files "품질팀" "일반"')
    return find_one(get_all('/me/joinedTeams', 500), q, '팀', 'teams')


def resolve_channel(tid, q):
    return find_one(get_all(f'/teams/{tid}/channels', 500), q, '채널', 'channels')


def msg_row(m):
    return {'time': fmt_d(m.get('createdDateTime')),
            'from': pick(g(m, 'from', 'user', 'displayName'), g(m, 'from', 'application', 'displayName')),
            'text': text(g(m, 'body', 'content')),
            'files': '; '.join(a.get('name') for a in (m.get('attachments') or []) if a and a.get('name')),
            'messageId': m.get('id')}


def q(s):
    return urllib.parse.quote(s, safe=":@!$'()*+,;=-._~")  # 팀즈 id(19:…@thread)는 그대로 둔다


# ---------- setup-m365: 관리자 권한 없이 사용자 폴더에 Node LTS + m365 설치 ----------
class SetupFail(Exception):
    pass


def setup_m365():
    t0 = time.time()
    deadline = t0 + SETUP_SECONDS
    os.makedirs(CACHE_DIR, exist_ok=True)
    log = open(SETUP_LOG, 'a', encoding='utf-8')

    def L(m):
        log.write(f'[{dt.datetime.now():%Y-%m-%d %H:%M:%S}] {m}\n')
        log.flush()

    def left():
        return deadline - time.time()

    def run(cmd, env=None, timeout=None):
        """진행 출력은 로그에만. 시간 넘기면 프로세스 묶음째 끝낸다."""
        tmo = max(1, min(timeout or left(), left()))
        L('$ ' + ' '.join(cmd))
        try:
            p = subprocess.Popen(cmd, stdout=log, stderr=log, stdin=subprocess.DEVNULL, env=env, start_new_session=True)
        except Exception as e:
            L(f'실행 실패: {e}')
            return -1
        try:
            rc = p.wait(timeout=tmo)
        except subprocess.TimeoutExpired:
            L(f'시간 초과({int(tmo)}초) — 중단')
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except Exception:
                p.kill()
            p.wait()
            return -2
        L(f'종료 코드 {rc}')
        return rc

    def fetch(url, dest=None):
        """내려받기. 409·429·5xx는 2·4·8초(+지터) 뒤 다시. dest 없으면 bytes를 돌려준다."""
        for n in range(4):
            if left() < 5:
                raise SetupFail('시간 초과')
            L(f'GET {url}')
            req = urllib.request.Request(url, headers={'User-Agent': 'workmate-setup'})
            try:
                with urllib.request.urlopen(req, timeout=min(60, left()), context=CTX) as r:
                    if dest is None:
                        return r.read()
                    with open(dest, 'wb') as f:
                        while True:
                            b = r.read(1 << 20)
                            if not b:
                                break
                            f.write(b)
                            if left() < 0:
                                raise SetupFail('시간 초과')
                    return dest
            except urllib.error.HTTPError as e:
                L(f'HTTP {e.code}')
                if (e.code in (409, 429) or e.code >= 500) and n < 3:
                    time.sleep(2 ** (n + 1) + random.random())
                    continue
                raise SetupFail(f'HTTP {e.code}')
            except SetupFail:
                raise
            except Exception as e:
                L(f'네트워크 오류: {e}')
                raise SetupFail('network')
        raise SetupFail('busy')

    def node_major(node):
        try:
            v = subprocess.run([node, '-v'], capture_output=True, timeout=20).stdout.decode().strip()
            return int(v.lstrip('v').split('.')[0]), v
        except Exception:
            return 0, ''

    def ok_line(head, cmd):
        rc, out, _ = m365_run(['version', '-o', 'json'], 60)
        ver = out.strip().strip('"') if rc == 0 else ''
        place = M365_DIR if cmd[-1].startswith(M365_DIR) else cmd[-1]
        L(f'완료: {head} {place} {ver} ({time.time() - t0:.0f}초)')
        say(f'{head}: {place}' + (f' (m365 {ver})' if ver else ''))

    try:
        L('=== setup-m365 시작 ===')
        # 0) 이미 있으면 끝
        cur = m365_cmd()
        if cur:
            rc, out, _ = m365_run(['version', '-o', 'json'], 60)
            if rc == 0:
                if not read_json(M365_REC):
                    save_json(M365_REC, {'cmd': cur, 'version': out.strip().strip('"')})
                return ok_line('팀즈 도구가 이미 있습니다', cur)
            L(f'있는 m365가 실행되지 않음: {cur}')
        entry = os.path.join(M365_DIR, 'lib', 'node_modules', '@pnp', 'cli-microsoft365', 'dist', 'index.js')
        # 1) Node: 이미 받아 둔 것 → 시스템 Node(LTS 22·24) → nodejs.org 포터블
        node = os.path.join(NODE_DIR, 'bin', 'node')
        npm_cli = os.path.join(NODE_DIR, 'lib', 'node_modules', 'npm', 'bin', 'npm-cli.js')
        if not (os.path.isfile(node) and node_major(node)[0] in NODE_MAJORS and os.path.isfile(npm_cli)):
            node = npm_cli = None
            sysn = shutil.which('node')
            if sysn and node_major(sysn)[0] in NODE_MAJORS:
                cand = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(sysn))), 'lib', 'node_modules', 'npm', 'bin', 'npm-cli.js')
                if os.path.isfile(cand):
                    node, npm_cli = sysn, cand
                    L(f'시스템 Node 사용: {sysn} {node_major(sysn)[1]}')
            elif sysn:
                L(f'시스템 Node {node_major(sysn)[1]}는 쓰지 않음(LTS {NODE_MAJORS}만)')
        if not node:
            arch = 'arm64' if platform.machine().lower() in ('arm64', 'aarch64') else 'x64'
            plat = 'darwin' if sys.platform == 'darwin' else 'linux'
            key = ('osx-' if plat == 'darwin' else 'linux-') + arch + '-tar'
            tmp = NODE_DIR + '.tmp'
            shutil.rmtree(tmp, ignore_errors=True)
            os.makedirs(tmp)
            ver = NODE_PIN
            for attempt in range(2):
                name = f'node-{ver}-{plat}-{arch}.tar.gz'
                try:
                    sums = fetch(f'{NODE_DIST}/{ver}/SHASUMS256.txt').decode('utf-8', 'replace')
                    break
                except SetupFail as e:
                    if attempt or not str(e).startswith('HTTP 404'):
                        raise
                    idx = json.loads(fetch(f'{NODE_DIST}/index.json').decode('utf-8'))   # 고정 버전이 없어졌으면 최신 LTS(22·24)로
                    cands = [v for v in idx if v.get('lts') and key in (v.get('files') or [])
                             and int(v['version'].lstrip('v').split('.')[0]) in NODE_MAJORS]
                    if not cands:
                        raise SetupFail('LTS 없음')
                    ver = cands[0]['version']
                    L(f'고정 버전 대신 {ver}')
            want = next((ln.split()[0] for ln in sums.splitlines() if ln.strip().endswith(' ' + name)), '')
            tgz = fetch(f'{NODE_DIST}/{ver}/{name}', os.path.join(tmp, name))
            h = hashlib.sha256()
            with open(tgz, 'rb') as f:
                for b in iter(lambda: f.read(1 << 20), b''):
                    h.update(b)
            if not want or h.hexdigest() != want:
                raise SetupFail('SHA256 불일치')
            L(f'Node {ver} 받음 {os.path.getsize(tgz) / 1048576:.1f}MB, SHA256 확인')
            with tarfile.open(tgz) as tf:
                try:
                    tf.extractall(tmp, filter='data')
                except TypeError:
                    tf.extractall(tmp)
            os.remove(tgz)
            inner = os.path.join(tmp, name[:-len('.tar.gz')])
            shutil.rmtree(NODE_DIR, ignore_errors=True)
            os.rename(inner, NODE_DIR)
            shutil.rmtree(tmp, ignore_errors=True)
            node = os.path.join(NODE_DIR, 'bin', 'node')
            npm_cli = os.path.join(NODE_DIR, 'lib', 'node_modules', 'npm', 'bin', 'npm-cli.js')
            if node_major(node)[0] not in NODE_MAJORS:
                raise SetupFail('Node 실행 안 됨')
        # 2) m365: npm 전역 설치를 사용자 폴더(prefix)로만. 재시도는 npm에 2·4·8초로 맡긴다
        env = dict(os.environ, CLIMICROSOFT365_NOUPDATE='1', npm_config_update_notifier='false', npm_config_fund='false', npm_config_audit='false',
                   npm_config_allow_scripts='@azure/msal-node-extensions,keytar')   # 새 npm이 설치 스크립트를 막아도 keytar 바이너리는 받게
        env['PATH'] = os.path.dirname(node) + os.pathsep + env.get('PATH', '')   # keytar 설치 스크립트가 같은 Node를 쓰게
        if NPM_REGISTRY:
            env['npm_config_registry'] = NPM_REGISTRY
        if not os.path.isfile(entry):
            rc = run([node, npm_cli, 'install', '-g', '--prefix', M365_DIR, f'{M365_PKG}@{M365_VER}', '--no-audit', '--no-fund', '--loglevel=warn',
                      '--fetch-retries=3', '--fetch-retry-factor=2', '--fetch-retry-mintimeout=2000', '--fetch-retry-maxtimeout=8000'], env)
            if rc != 0 or not os.path.isfile(entry):
                raise SetupFail(f'npm 종료 코드 {rc}')
        # 3) 로그인 저장(keytar) 확인 — m365 12는 맥·Windows에서 keytar 없이 로그인 정보를 저장하지 못한다
        pkg = os.path.dirname(os.path.dirname(entry))
        chk = [node, '-e', "const p=require('path'),u=require('url');const d=p.dirname(require.resolve('@azure/msal-node-extensions/package.json',{paths:[process.argv[1]]}));"
               "import(u.pathToFileURL(p.join(d,'dist','index.mjs')).href).then(()=>console.log('keytar ok'),e=>{console.error(String(e&&e.message||e));process.exit(1)})", pkg]
        if run(chk, env, 60) != 0:
            run([node, npm_cli, 'rebuild', 'keytar', '--prefix', pkg], env)   # 한 번만 다시 받거나 빌드
            if run(chk, env, 60) != 0:
                raise SetupFail('keytar')
        cmd = [node, entry]
        save_json(M365_REC, {'cmd': cmd, 'version': M365_VER})
        m365_run(['cli', 'config', 'set', '--key', 'prompt', '--value', 'false'], 60)   # 빠진 값을 묻느라 멈추지 않게
        return ok_line('팀즈 도구를 설치했습니다', cmd)
    except Exception as e:
        L(f'실패: {e!r} ({time.time() - t0:.0f}초)')
        shutil.rmtree(NODE_DIR + '.tmp', ignore_errors=True)
        say(SETUP_FAIL)
    finally:
        log.close()


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument('command', nargs='?', default='status')
    ap.add_argument('arg1', nargs='?', default='')
    ap.add_argument('arg2', nargs='?', default='')
    ap.add_argument('--top', '-Top', type=int, default=20)
    ap.add_argument('--depth', '-Depth', type=int, default=2)
    ap.add_argument('--wait', '-Wait', type=int, default=90)
    ap.add_argument('--with-channel-messages', '-WithChannelMessages', action='store_true')
    ap.add_argument('--force', '-Force', action='store_true')
    o, _ = ap.parse_known_args()  # 모르는 옵션은 무시(멈추지 않게)
    cmd = o.command.lower()

    def rest_login():
        code, body, _ = http('POST', f'{LOGIN_HOST}/organizations/oauth2/v2.0/devicecode', data={'client_id': CLIENT_ID, 'scope': SCOPES}, timeout=30)
        try:
            d = json.loads(body.decode('utf-8', 'replace'))
        except Exception:
            d = {}
        if code != 200 or not d.get('user_code'):
            fail(tag_of(code, body))
        save_json(PENDING_FILE, {'device_code': d['device_code'], 'interval': int(d.get('interval') or 5),
                                 'expires_at': now() + int(d.get('expires_in') or 900), 'channel_messages': bool(o.with_channel_messages)})
        say(f"브라우저에서 {d.get('verification_uri')} 에 들어가 코드 칸에 {d['user_code']} 입력 후 회사 계정으로 로그인하세요. ({int(d.get('expires_in') or 900) // 60}분 안에)")
        say('[다음: 로그인을 마치면 login-wait]')

    if cmd == 'setup-m365':
        try:
            setup_m365()
        except Exception:
            say(SETUP_FAIL)

    elif cmd == 'status':
        if m365_cmd():
            who = m365_who()
            if who:
                done(f'팀즈 연결됨: {who} (도구: m365)')
        c = read_json(TOKEN_FILE)
        if not c:
            fail('login-needed m365' if m365_cmd() else 'login-needed')
        MODE[0] = 'rest'
        me = graph('/me?$select=displayName')
        say(f"팀즈 연결됨: {me.get('displayName')} (채널 메시지: {'가능' if (read_json(TOKEN_FILE) or {}).get('channel_messages') else '쓰지 않음'})")

    elif cmd == 'login':
        if not o.force:
            who = m365_who() if m365_cmd() else None
            if who:
                done(f'이미 팀즈에 연결돼 있습니다: {who}')
            if read_json(TOKEN_FILE):
                MODE[0] = 'rest'
                QUIET[0] = True   # 저장된 로그인이 만료됐으면 조용히 새 로그인으로
                try:
                    me = graph('/me?$select=displayName', soft=True)
                except Stop:
                    me = None
                QUIET[0] = False
                if me:
                    done(f"이미 팀즈에 연결돼 있습니다: {me.get('displayName')}")
        for f in (PENDING_FILE, M365_PENDING):
            os.path.exists(f) and os.remove(f)
        got = m365_login_start(o.with_channel_messages) if m365_cmd() else None   # m365가 있으면 m365로, 안 되면 기본 방식으로
        if got:
            say(f'브라우저에서 {got[0]} 에 들어가 코드 칸에 {got[1]} 입력 후 회사 계정으로 로그인하세요. (15분 안에)')
            done('[다음: 로그인을 마치면 login-wait]')
        rest_login()

    elif cmd == 'login-wait' and read_json(M365_PENDING):
        p = read_json(M365_PENDING)
        exp = int(p.get('expires_at') or 0)
        end = min(exp, now() + max(5, o.wait))
        while True:
            who = m365_who()
            if who:
                os.remove(M365_PENDING)
                done(f'팀즈에 연결됐습니다: {who}')
            if not m365_pending_alive(p) or now() >= end:
                break
            time.sleep(5)
        if not m365_pending_alive(p):   # m365 로그인이 끝났는데 연결이 안 됐다
            os.remove(M365_PENDING)
            try:
                tail = open(M365_LOGIN_LOG, encoding='utf-8', errors='replace').read()[-2000:]
            except Exception:
                tail = ''
            tag = m365_tag(tail)
            if re.match(r'(admin-consent|policy|network)', tag):
                fail(tag)
            say('다른 방식으로 로그인 코드를 다시 받았습니다.')
            rest_login()
            done()
        if now() >= exp:
            os.remove(M365_PENDING)
            fail('expired')
        say('아직 로그인이 끝나지 않았습니다. 브라우저에서 로그인을 마치면 login-wait를 다시 실행합니다. [pending]')

    elif cmd == 'login-wait':
        p = read_json(PENDING_FILE)
        if not p or not p.get('device_code'):
            if read_json(TOKEN_FILE):
                done('이미 팀즈에 연결돼 있습니다.')
            fail('login-needed')
        exp = int(p.get('expires_at') or 0)
        end = min(exp, now() + max(5, o.wait))
        iv = max(5, int(p.get('interval') or 5))
        while now() < end:
            r = post_token({'grant_type': 'urn:ietf:params:oauth:grant-type:device_code', 'client_id': CLIENT_ID, 'device_code': p['device_code']})
            if r['ok']:
                os.path.exists(PENDING_FILE) and os.remove(PENDING_FILE)
                save_tokens(r['data'], SCOPES, False)
                me = graph('/me?$select=displayName', soft=True) or {}
                say(f"팀즈에 연결됐습니다: {pick(me.get('displayName'), '로그인한 계정')}")
                if p.get('channel_messages'):  # 채널 메시지 권한은 로그인과 따로 받아 본다 — 안 되면 그 기능만 빠진다
                    c = read_json(TOKEN_FILE) or {}
                    s = post_token({'grant_type': 'refresh_token', 'client_id': CLIENT_ID, 'refresh_token': c.get('refresh_token', ''), 'scope': f'{SCOPES} {CHAN_SCOPE}'})
                    if s['ok']:
                        save_tokens(s['data'], f'{SCOPES} {CHAN_SCOPE}', True, c)
                        say('채널 메시지: 읽기 가능')
                    else:
                        say(f"채널 메시지: 회사 관리자 승인이 없어 빼고 연결했습니다. [{s['tag']}]")
                done()
            if r['error'] == 'authorization_pending':
                time.sleep(iv)
                continue
            if r['error'] == 'slow_down':
                iv += 5
                time.sleep(iv)
                continue
            os.path.exists(PENDING_FILE) and os.remove(PENDING_FILE)
            fail(r['tag'])
        if now() >= exp:
            os.path.exists(PENDING_FILE) and os.remove(PENDING_FILE)
            fail('expired')
        say('아직 로그인이 끝나지 않았습니다. 브라우저에서 로그인을 마치면 login-wait를 다시 실행합니다. [pending]')

    elif cmd == 'logout':
        for f in (TOKEN_FILE, PENDING_FILE, M365_PENDING, M365_LOGIN_LOG):
            if os.path.exists(f):
                os.remove(f)
        if m365_cmd():
            m365_run(['logout'], 60)
        say('이 PC에서 팀즈 로그인 정보를 지웠습니다.')

    elif cmd == 'teams':
        rows = [{'name': t.get('displayName'), 'description': text(t.get('description')), 'teamId': t.get('id')} for t in get_all('/me/joinedTeams', 500)]
        write_result(rows, 'teams', ['name', 'description', 'teamId'], ['name', 'description'])

    elif cmd == 'channels':
        t = resolve_team(o.arg1)
        rows = [{'name': c.get('displayName'), 'type': c.get('membershipType'), 'description': text(c.get('description')), 'channelId': c.get('id')}
                for c in get_all(f"/teams/{q(t['id'])}/channels", 500)]
        write_result(rows, 'channels-' + safe(t.get('displayName')), ['name', 'type', 'description', 'channelId'], ['name', 'type', 'description'])

    elif cmd == 'files':
        t = resolve_team(o.arg1)
        label = t.get('displayName') or ''
        if o.arg2:  # 채널 '파일' 탭 = 채널 폴더(비공개·공유 채널은 따로 있는 사이트)
            ch = resolve_channel(q(t['id']), o.arg2)
            f = graph(f"/teams/{q(t['id'])}/channels/{q(ch['id'])}/filesFolder")
            drive, root_id, label = g(f, 'parentReference', 'driveId'), f.get('id'), f"{label}-{ch.get('displayName')}"
        else:  # 팀 전체 문서 라이브러리(채널마다 폴더)
            drive, root_id = graph(f"/groups/{q(t['id'])}/drive").get('id'), 'root'
        depth = max(1, min(o.depth, 5))
        mx = 1000
        rows, queue = [], [(root_id, '', 1)]
        while queue and len(rows) < mx:
            iid, base, lv = queue.pop(0)
            for k in get_all(f'/drives/{q(drive)}/items/{q(iid)}/children?$top=200&$select=id,name,size,lastModifiedDateTime,lastModifiedBy,folder,file,webUrl', mx):
                path = f"{base}/{k.get('name')}" if base else k.get('name')
                rows.append({'path': path, 'type': '폴더' if k.get('folder') is not None else '파일', 'size': size(k.get('size')), 'modified': fmt_d(k.get('lastModifiedDateTime')),
                             'by': g(k, 'lastModifiedBy', 'user', 'displayName'), 'driveId': drive, 'itemId': k.get('id'), 'webUrl': k.get('webUrl')})
                if k.get('folder') is not None and lv < depth:
                    queue.append((k.get('id'), path, lv + 1))
                if len(rows) >= mx:
                    break
        write_result(rows, 'files-' + safe(label), ['path', 'type', 'size', 'modified', 'by', 'driveId', 'itemId', 'webUrl'], ['path', 'type', 'size', 'modified', 'by'])

    elif cmd in ('shared', 'recent'):
        items = get_all('/me/drive/sharedWithMe' if cmd == 'shared' else '/me/drive/recent', 500, soft=True)  # 회사가 막아 둔 API면 조용히 빈 결과
        miss = SOFT_MISS[0]
        rows = []
        for it in items:
            ri = it.get('remoteItem') or {}
            rows.append({'name': pick(ri.get('name'), it.get('name')), 'type': '폴더' if (ri.get('folder') is not None or it.get('folder') is not None) else '파일',
                         'size': size(pick(ri.get('size'), it.get('size'))), 'modified': fmt_d(pick(ri.get('lastModifiedDateTime'), it.get('lastModifiedDateTime'))),
                         'by': pick(g(ri, 'shared', 'sharedBy', 'user', 'displayName'), g(ri, 'shared', 'owner', 'user', 'displayName'),
                                    g(ri, 'lastModifiedBy', 'user', 'displayName'), g(it, 'lastModifiedBy', 'user', 'displayName')),
                         'driveId': pick(g(ri, 'parentReference', 'driveId'), g(it, 'parentReference', 'driveId')),
                         'itemId': pick(ri.get('id'), it.get('id')), 'webUrl': pick(ri.get('webUrl'), it.get('webUrl'))})
        write_result(rows, cmd, ['name', 'type', 'size', 'modified', 'by', 'driveId', 'itemId', 'webUrl'], ['name', 'type', 'size', 'modified', 'by'])
        if miss and not rows:
            say('  (이 목록은 회사 설정으로 비어 있을 수 있습니다. files로 팀 파일을 봅니다.)')

    elif cmd == 'get':
        if not o.arg1 or not o.arg2:
            done('driveId와 itemId가 필요합니다(files·shared·recent 결과 CSV의 driveId·itemId 열).')
        it = graph(f'/drives/{q(o.arg1)}/items/{q(o.arg2)}')
        if it.get('file') is None:  # 빈 {}도 파일이다
            done('폴더는 가져오지 않습니다. files로 안의 파일을 보고 파일을 고릅니다.')
        if float(it.get('size') or 0) > MAX_BYTES:
            done(f"50MB가 넘어 가져오지 않았습니다: {it.get('name')} ({size(it.get('size'))}). 팀즈에서 직접 내려받으세요.")
        os.makedirs(INBOX_DIR, exist_ok=True)
        name = re.sub(r'[\\/:*?"<>|\x00-\x1f]', '_', it.get('name') or 'file')
        target, i = os.path.join(INBOX_DIR, name), 1
        while os.path.exists(target):
            stem, ext = os.path.splitext(name)
            target = os.path.join(INBOX_DIR, f'{stem}_{i}{ext}')
            i += 1
        url = it.get('@microsoft.graph.downloadUrl')  # 짧게 유효한 내려받기 주소(토큰을 다른 서버로 보내지 않는다). 화면·파일에 쓰지 않는다
        m365_ok = False
        if not url and MODE[0] == 'm365':   # 내려받기 주소가 없으면 m365가 토큰을 붙여 받는다
            rc, _, _ = m365_run(['request', '--url', f'{GRAPH}/drives/{q(o.arg1)}/items/{q(o.arg2)}/content', '--filePath', target], 300)
            m365_ok = rc == 0 and os.path.exists(target)
            if not m365_ok:
                os.path.exists(target) and os.remove(target)
        if not m365_ok:
            try:
                hdr = {} if url else {'Authorization': f'Bearer {get_token()}'}
                req = urllib.request.Request(url or f'{GRAPH}/drives/{q(o.arg1)}/items/{q(o.arg2)}/content', headers=hdr)
                with urllib.request.urlopen(req, timeout=300, context=CTX) as r, open(target, 'wb') as f:
                    n = 0
                    while True:
                        b = r.read(1 << 20)
                        if not b:
                            break
                        n += len(b)
                        if n > MAX_BYTES:
                            raise ValueError('too big')
                        f.write(b)
            except urllib.error.HTTPError as e:
                os.path.exists(target) and os.remove(target)
                fail(tag_of(e.code, b''))
            except Exception:
                os.path.exists(target) and os.remove(target)
                fail(NET_ERR)
        lst = os.path.join(INBOX_DIR, '_목록.csv')
        new = not os.path.exists(lst)
        with open(lst, 'a', encoding='utf-8-sig' if new else 'utf-8', newline='') as f:
            w = csv.writer(f, quoting=csv.QUOTE_ALL)
            if new:
                w.writerow(['file', 'from', 'modified', 'fetched', 'driveId', 'itemId'])
            w.writerow([os.path.basename(target), it.get('webUrl'), fmt_d(it.get('lastModifiedDateTime')), f'{dt.datetime.now():%Y-%m-%d %H:%M}', o.arg1, o.arg2])
        say(f"가져옴: {os.path.relpath(target, WS)} ({size(it.get('size'))}). 원본은 팀즈에 그대로 있습니다.")

    elif cmd in ('chats', 'chat-messages'):
        if cmd == 'chat-messages' and not o.arg1:
            done('채팅 id나 이름이 필요합니다(chats 결과 CSV의 chatId 열).')
        chats = []
        if cmd == 'chats' or not o.arg1.startswith('19:'):
            for c in get_all('/me/chats?$expand=members&$top=50', 50):
                who = ', '.join(m.get('displayName') for m in (c.get('members') or []) if m and m.get('displayName'))
                chats.append({'id': c.get('id'), 'displayName': pick(c.get('topic'), who, '(이름 없음)'), 'type': c.get('chatType'),
                              'updated': fmt_d(c.get('lastUpdatedDateTime')), 'members': ', '.join(who.split(', ')[:6])})
        if cmd == 'chats':
            rows = sorted(({'name': c['displayName'], 'type': c['type'], 'updated': c['updated'], 'members': c['members'], 'chatId': c['id']} for c in chats),
                          key=lambda r: r['updated'] or '', reverse=True)
            write_result(rows, 'chats', ['name', 'type', 'updated', 'members', 'chatId'], ['name', 'type', 'updated'])
        else:
            cid = o.arg1 if o.arg1.startswith('19:') else find_one(chats, o.arg1, '채팅', 'chats')['id']
            r = graph(f'/chats/{q(cid)}/messages?$top={max(1, min(o.top, 50))}')
            rows = sorted((msg_row(m) for m in (r.get('value') or []) if m and m.get('messageType') == 'message'), key=lambda x: x['time'])
            write_result(rows, 'chat-messages', ['time', 'from', 'text', 'files', 'messageId'], ['time', 'from', 'text'])

    elif cmd == 'channel-messages':
        if not o.with_channel_messages:
            done('채널 메시지는 --with-channel-messages를 붙일 때만 읽습니다(회사 관리자 승인이 필요할 수 있습니다).')
        t = resolve_team(o.arg1)
        if not o.arg2:
            done('채널 이름이 필요합니다. 예: channel-messages "품질팀" "일반" --with-channel-messages')
        ch = resolve_channel(q(t['id']), o.arg2)
        r = graph(f"/teams/{q(t['id'])}/channels/{q(ch['id'])}/messages?$top={max(1, min(o.top, 50))}", chan=True)
        rows = sorted((msg_row(m) for m in (r.get('value') or []) if m and m.get('messageType') == 'message'), key=lambda x: x['time'])
        write_result(rows, 'channel-messages-' + safe(f"{t.get('displayName')}-{ch.get('displayName')}"),
                     ['time', 'from', 'text', 'files', 'messageId'], ['time', 'from', 'text'])

    else:
        say('사용: setup-m365 | status | login | login-wait | logout | teams | channels <팀> | files <팀> [채널] | shared | recent | '
            'get <driveId> <itemId> | chats | chat-messages <채팅> | channel-messages <팀> <채널> --with-channel-messages')


if __name__ == '__main__':
    try:
        main()
    except Stop:
        pass
    except KeyboardInterrupt:
        pass
    except Exception:
        say(f'{FAIL_LINE} [error]')
    sys.exit(0)
