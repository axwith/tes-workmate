# 팀즈(회사 Microsoft 365)에 공유된 파일과 채팅을 읽기 전용으로 본다. 설치 없이 Windows PowerShell 5.1 기본 기능만 쓴다.
# 사용: teams.ps1 status | login [-WithChannelMessages] | login-wait [-Wait 90] | logout
#       teams.ps1 teams | channels <팀> | files <팀> [채널] [-Depth 2] | shared | recent
#       teams.ps1 get <driveId> <itemId>          # 사본을 00-inbox\teams\ 로(50MB까지)
#       teams.ps1 chats | chat-messages <채팅id 또는 이름> [-Top 20]
#       teams.ps1 channel-messages <팀> <채널> -WithChannelMessages   # 회사 관리자 승인이 있어야 된다
#       teams.ps1 setup-m365                     # 팀즈 도구(CLI for Microsoft 365)를 사용자 폴더에 설치(관리자 권한 없음)
# 경로 순서: m365(설치·로그인돼 있으면) → 기본 방식(Graph 직접 호출) → 둘 다 안 되면 한 줄.
# 보내기·수정·삭제는 하지 않는다. 연결이 안 되면(로그인 전·관리자 승인 필요·회사망 차단·403) 한 줄만 쓰고 종료 코드 0으로 끝난다.
# 로그인 정보는 %LOCALAPPDATA%\workmate\teams-token.json(기본 방식)과 m365 자체 저장소(사용자 프로필)에만 둔다(워크스페이스·로그에 쓰지 않는다).
param(
  [Parameter(Position = 0)][string]$Command = 'status',
  [Parameter(Position = 1)][string]$Arg1 = '',
  [Parameter(Position = 2)][string]$Arg2 = '',
  [int]$Top = 20,
  [int]$Depth = 2,
  [int]$Wait = 90,
  [switch]$WithChannelMessages,
  [switch]$Force
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
try { [Net.WebRequest]::DefaultWebProxy.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials } catch {}   # 회사 프록시

$ClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'   # Microsoft Graph Command Line Tools(Microsoft 공용 앱 — 회사가 앱을 따로 등록하지 않아도 된다)
$LoginHost = 'https://login.microsoftonline.com'; if ($env:WORKMATE_TEAMS_LOGIN_HOST) { $LoginHost = $env:WORKMATE_TEAMS_LOGIN_HOST }   # 시험용 바꾸기
$Graph = 'https://graph.microsoft.com/v1.0'; if ($env:WORKMATE_TEAMS_GRAPH) { $Graph = $env:WORKMATE_TEAMS_GRAPH }
$Scopes = 'User.Read Team.ReadBasic.All Channel.ReadBasic.All Files.Read.All Sites.Read.All Chat.Read offline_access'
$ChanScope = 'ChannelMessage.Read.All'   # 위임이어도 관리자 동의가 필요하다 — 옵션으로만
$MaxBytes = 50MB
$CacheDir = $env:WORKMATE_TEAMS_CACHE
if (-not $CacheDir) { if ($env:LOCALAPPDATA) { $CacheDir = Join-Path $env:LOCALAPPDATA 'workmate' } else { $CacheDir = Join-Path $HOME '.workmate' } }
$TokenFile = Join-Path $CacheDir 'teams-token.json'
$PendingFile = Join-Path $CacheDir 'teams-login.json'
$Ws = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$OutDir = Join-Path $Ws 'memory\teams'
$InboxDir = Join-Path $Ws '00-inbox\teams'
$FailLine = '팀즈 연결이 안 됩니다. PC에 있는 파일로 진행합니다.'
$script:ForceRefresh = $false
# CLI for Microsoft 365(m365) — setup-m365가 사용자 폴더에만 설치한다
$M365Pkg = '@pnp/cli-microsoft365'
$M365Ver = '12.0.0'
$NodePin = 'v24.22.3'            # Node LTS 고정. 받을 수 없으면 index.json에서 아래 주 버전의 최신 LTS로
$NodeMajors = @(24, 22)          # Node 26은 2026-11 맥 시험에서 keytar(로그인 저장) 문제가 있었다
$NodeDist = 'https://nodejs.org/dist'; if ($env:WORKMATE_NODE_DIST) { $NodeDist = $env:WORKMATE_NODE_DIST }   # 시험용 바꾸기
$NpmRegistry = [string]$env:WORKMATE_NPM_REGISTRY                                                              # 시험용 바꾸기
$SetupSeconds = 300
$NodeDir = Join-Path $CacheDir 'node'
$M365Dir = Join-Path $CacheDir 'm365'
$M365Rec = Join-Path $CacheDir 'm365.json'
$SetupLog = Join-Path $CacheDir 'teams-setup.log'
$M365Pending = Join-Path $CacheDir 'teams-m365-login.json'
$M365LoginLog = Join-Path $CacheDir 'teams-m365-login.log'
$M365LoginErr = Join-Path $CacheDir 'teams-m365-login.err.log'
$SetupFailLine = '팀즈 도구를 설치하지 못했습니다. 기본 방식으로 진행합니다.'
$OnWindows = ($env:OS -eq 'Windows_NT')
$script:Mode = ''        # '': 아직 모름, 'm365', 'rest'
$script:Quiet = $false   # login의 '이미 연결됐나' 확인 중에는 실패 줄을 쓰지 않는다

function Say([string]$m) { [Console]::Out.WriteLine($m) }   # 함수 반환값에 섞이지 않게 화면으로 바로 쓴다
function Fail([string]$tag) { if ($script:Quiet) { throw 'quiet-fail' }; Say "$FailLine [$tag]"; exit 0 }
function Now { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
function Pick { foreach ($a in $args) { if ($null -ne $a -and "$a" -ne '') { return $a } }; return '' }
function Read-Json([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  try { return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}
function Save-Json([string]$p, $obj) {
  New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null
  [IO.File]::WriteAllText($p, ($obj | ConvertTo-Json -Depth 5 -Compress), (New-Object Text.UTF8Encoding $false))
}
function D($v) {   # 현지 시각으로(PS 7은 날짜를 UTC DateTime으로, PS 5.1은 문자열로 준다)
  if (-not $v) { return '' }
  try { if ($v -is [datetime]) { return $v.ToLocalTime().ToString('yyyy-MM-dd HH:mm') }; return [DateTimeOffset]::Parse([string]$v).LocalDateTime.ToString('yyyy-MM-dd HH:mm') } catch { return [string]$v }
}
function Size($b) { if ($null -eq $b -or "$b" -eq '') { return '' }; $b = [double]$b; if ($b -ge 1MB) { return ('{0:N1}MB' -f ($b / 1MB)) }; return ('{0:N0}KB' -f [Math]::Ceiling($b / 1KB)) }
function Text($html) {
  $t = [string]$html -replace '<br\s*/?>', ' ' -replace '</p>', ' ' -replace '<[^>]+>', ''
  $t = ([Net.WebUtility]::HtmlDecode($t) -replace '\s+', ' ').Trim()
  if ($t.Length -gt 500) { $t = $t.Substring(0, 500) + '…' }
  return $t
}
function Safe([string]$s) { return (($s -replace '[\\/:*?"<>|\s]+', '_').Trim('_', '.')) }

# PS 5.1(WebException)과 PS 7(HttpResponseException) 모두에서 상태 코드·본문·Retry-After를 꺼낸다
function Get-HttpInfo($e) {
  $h = @{ code = 0; body = ''; retry = 0; net = $false }
  $r = $null; try { $r = $e.Exception.Response } catch {}
  if ($r) { try { $h.code = [int]$r.StatusCode } catch {} }
  try { $h.body = [string]$e.ErrorDetails.Message } catch {}
  if ($r) {
    $v = $null
    try { $v = $r.Headers['Retry-After'] } catch {}
    if (-not $v) { try { $v = [int]$r.Headers.RetryAfter.Delta.TotalSeconds } catch {} }
    try { if ($v) { $h.retry = [int]$v } } catch {}
  }
  if ($h.code -eq 0) { $h.net = ($e.Exception.GetType().FullName -match 'WebException|HttpRequestException|HttpResponseException|TaskCanceled|IOException|Socket|Timeout') }
  return $h
}
function Get-Tag($h) {
  $err = ''; $desc = ''
  try { $j = $h.body | ConvertFrom-Json; $err = [string]$j.error; $desc = [string]$j.error_description; if ($j.error.code) { $err = [string]$j.error.code } } catch {}
  $aad = ''; if ($desc -match 'AADSTS\d+') { $aad = ' ' + $Matches[0] }
  if ($desc -match 'AADSTS(65001|65004|90094|90008)' -or $err -eq 'consent_required') { return "admin-consent$aad" }
  if ($desc -match 'AADSTS(53000|53001|53003|50105|7000112|700016|50020|500011)') { return "policy$aad" }
  if ($err -eq 'expired_token') { return 'expired' }
  if ($err -eq 'authorization_declined' -or $err -eq 'access_denied') { return 'declined' }
  if ($err -eq 'invalid_grant') { return "login-needed$aad" }
  if ($h.code -eq 0) { if ($h.net) { return 'network' } else { return 'error' } }
  if ($h.code -eq 401) { return 'login-needed' }
  if ($h.code -eq 403) { return 'forbidden' }
  return ("error {0}{1}" -f $h.code, $aad)
}

function Post-Token($form) {
  try {
    $d = Invoke-RestMethod -Method Post -Uri "$LoginHost/organizations/oauth2/v2.0/token" -Body $form -ContentType 'application/x-www-form-urlencoded' -TimeoutSec 30 -UseBasicParsing
    return @{ ok = $true; data = $d }
  } catch {
    $h = Get-HttpInfo $_; $err = ''
    try { $err = [string]($h.body | ConvertFrom-Json).error } catch {}
    return @{ ok = $false; error = $err; tag = (Get-Tag $h) }
  }
}
function Save-Tokens($d, [string]$scope, [bool]$chan, $old) {
  $rt = Pick $d.refresh_token $old.refresh_token
  Save-Json $TokenFile ([ordered]@{ access_token = [string]$d.access_token; refresh_token = [string]$rt; expires_at = (Now) + [int]$d.expires_in; scope = $scope; channel_messages = $chan })
}
# 토큰을 꺼낸다. 실패하면 한 줄 남기고 끝낸다. $chan이면 채널 메시지 권한까지 받는다(관리자 동의 없으면 그 기능만 빠진다).
function Get-Token([bool]$chan = $false) {
  $c = Read-Json $TokenFile
  if (-not $c -or -not $c.refresh_token) { Fail 'login-needed' }
  $has = [bool]$c.channel_messages
  $exp = 0; try { $exp = [long]$c.expires_at } catch {}
  if (-not $script:ForceRefresh -and $c.access_token -and $exp -gt ((Now) + 120) -and (-not $chan -or $has)) { return [string]$c.access_token }
  $scope = $Scopes; if ($chan -or $has) { $scope = "$Scopes $ChanScope" }
  $r = Post-Token @{ grant_type = 'refresh_token'; client_id = $ClientId; refresh_token = [string]$c.refresh_token; scope = $scope }
  if (-not $r.ok) {
    if ($chan -and -not $has -and $r.tag -like 'admin-consent*') { Say "채널 메시지는 회사 관리자 승인이 있어야 읽을 수 있습니다. 파일·채팅은 그대로 쓸 수 있습니다. [$($r.tag)]"; exit 0 }
    if ($r.tag -match '^(admin-consent|policy|network)') { Fail $r.tag }
    Fail 'login-needed'
  }
  Save-Tokens $r.data $scope ($chan -or $has) $c
  $script:ForceRefresh = $false
  return [string]$r.data.access_token
}
# ---------- 외부 프로그램 실행(m365·node·npm) ----------
function Quote-Arg([string]$a) {   # Windows 명령줄 규칙대로 감싼다(cmd.exe를 거치지 않으므로 & | 는 그대로 넘어간다)
  if ($a -ne '' -and $a -notmatch '[\s"]') { return $a }
  return '"' + (($a -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}
# @{ code; out; err }. 시간을 넘기면 프로세스 묶음째 끝내고 code -2, 실행 자체가 안 되면 -1.
function Run-Proc([string]$file, [string[]]$argv, [int]$timeoutSec, [hashtable]$envs) {
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $file
  $psi.Arguments = ((@($argv) | ForEach-Object { Quote-Arg $_ }) -join ' ')
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
  $psi.StandardOutputEncoding = [Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
  $psi.EnvironmentVariables['CLIMICROSOFT365_NOUPDATE'] = '1'
  if ($envs) { foreach ($k in $envs.Keys) { $psi.EnvironmentVariables[$k] = [string]$envs[$k] } }
  $p = $null
  try { $p = [Diagnostics.Process]::Start($psi) } catch { return @{ code = -1; out = ''; err = [string]$_ } }
  try { $p.StandardInput.Close() } catch {}
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit([Math]::Max(1, $timeoutSec) * 1000)) {
    if ($OnWindows) { try { Start-Process -FilePath 'taskkill.exe' -ArgumentList "/T /F /PID $($p.Id)" -NoNewWindow -Wait } catch {} }
    try { $p.Kill() } catch {}
    return @{ code = -2; out = ''; err = 'timeout' }
  }
  $p.WaitForExit()
  return @{ code = $p.ExitCode; out = [string]$o.Result; err = [string]$e.Result }
}

# ---------- m365 경로 ----------
# 설치된 m365 실행 명령(배열) 또는 $null. setup-m365 기록이 먼저, 없으면 PATH의 m365.
function Get-M365Cmd {
  $r = Read-Json $M365Rec
  if ($r -and $r.cmd) {
    $c = @($r.cmd | ForEach-Object { [string]$_ }); $ok = ($c.Count -gt 0)
    foreach ($x in $c) { if (-not (Test-Path -LiteralPath $x -PathType Leaf)) { $ok = $false } }
    if ($ok) { return , $c }
  }
  $g = Get-Command m365 -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($g) {   # npm이 만든 m365.cmd는 cmd.exe가 URL의 & 를 해석하므로 node + index.js로 바로 부른다
    $dir = Split-Path $g.Source
    $entry = Join-Path $dir 'node_modules\@pnp\cli-microsoft365\dist\index.js'
    if (-not $OnWindows) { $entry = Join-Path (Split-Path $dir) 'lib/node_modules/@pnp/cli-microsoft365/dist/index.js' }
    $node = Join-Path $dir 'node.exe'
    if (-not (Test-Path -LiteralPath $node)) { $n = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1; $node = ''; if ($n) { $node = $n.Source } }
    if ($node -and (Test-Path -LiteralPath $entry)) { return , @($node, $entry) }
  }
  return $null
}
function Run-M365([string[]]$argv, [int]$timeoutSec = 120) {
  $c = Get-M365Cmd
  if (-not $c) { return @{ code = -1; out = ''; err = 'no m365' } }
  $c = @($c); $rest = @(); if ($c.Count -gt 1) { $rest = @($c[1..($c.Count - 1)]) }
  return (Run-Proc $c[0] (@($rest) + @($argv)) $timeoutSec $null)
}
function Get-M365Who {   # m365에 로그인돼 있으면 계정 이름, 아니면 $null
  $r = Run-M365 @('status', '-o', 'json') 60
  if ($r.code -ne 0) { return $null }
  $j = $null; try { $j = $r.out | ConvertFrom-Json } catch { return $null }
  if ($j -and $j.connectedAs) { return [string]$j.connectedAs }
  return $null
}
function Get-M365Tag([string]$e) {   # m365는 상태 코드를 주지 않아 오류문으로 가른다
  $aad = ''; if ($e -match 'AADSTS\d+') { $aad = ' ' + $Matches[0] }
  if ($e -match 'AADSTS(65001|65004|90094|90008)' -or $e -match 'consent') { return "admin-consent$aad" }
  if ($e -match 'AADSTS(53000|53001|53003|50105|7000112|700016|50020|500011)') { return "policy$aad" }
  if ($e -match 'Log in to Microsoft 365 first|login has expired|Sign in again|invalid_grant|AADSTS(50173|700082|70043|50076|50078)') { return "login-needed m365$aad" }
  if ($e -match 'ENOTFOUND|EAI_AGAIN|ECONNREFUSED|ECONNRESET|ETIMEDOUT|ENETUNREACH|socket hang up|getaddrinfo') { return 'network' }
  if ($e -match 'Forbidden|Access ?denied|Insufficient privileges|Authorization_RequestDenied|\b403\b') { return 'forbidden' }
  return 'error m365'
}
function M365-Get([string]$uri) {   # m365 request가 토큰·재시도(429)를 맡는다
  $r = Run-M365 @('request', '--url', $uri, '-o', 'json')
  if ($r.code -eq 0) {
    if (-not ([string]$r.out).Trim()) { return @{ ok = $true; data = (New-Object psobject) } }
    try { return @{ ok = $true; data = ($r.out | ConvertFrom-Json) } } catch { return @{ ok = $false; err = 'bad json' } }
  }
  return @{ ok = $false; err = ([string](Pick $r.err $r.out)).Trim() }
}
function Read-Shared([string]$f) {   # 다른 프로세스가 쓰는 중인 파일도 읽는다
  try {
    $fs = New-Object IO.FileStream($f, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
    $t = $sr.ReadToEnd(); $sr.Close(); return $t
  } catch { return '' }
}
# m365 디바이스 코드 로그인을 뒤에서 띄우고 @(주소, 코드)를 돌려준다. 안 되면 $null(기본 방식으로).
function Start-M365Login([bool]$chan) {
  $c = Get-M365Cmd; if (-not $c) { return $null }
  $c = @($c); $argv = @(); if ($c.Count -gt 1) { $argv = @($c[1..($c.Count - 1)]) }
  $argv += @('login', '--authType', 'deviceCode', '--appId', $ClientId, '--tenant', 'organizations')
  New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
  Remove-Item -LiteralPath $M365LoginLog, $M365LoginErr -Force -ErrorAction SilentlyContinue
  $env:CLIMICROSOFT365_NOUPDATE = '1'
  $p = $null
  try {
    $p = Start-Process -FilePath $c[0] -ArgumentList ((@($argv) | ForEach-Object { Quote-Arg $_ }) -join ' ') -RedirectStandardOutput $M365LoginLog -RedirectStandardError $M365LoginErr -NoNewWindow -PassThru
  } catch { return $null }
  $end = (Now) + 25
  while ((Now) -lt $end) {
    Start-Sleep -Seconds 1
    $s = (Read-Shared $M365LoginLog) + "`n" + (Read-Shared $M365LoginErr)
    $url = ''; $code = ''
    if ($s -match 'https://\S*(devicelogin|/device)\S*') { $url = $Matches[0].TrimEnd('.', ',') }
    if ($s -cmatch 'code\s+([A-Z0-9]{6,12})\b') { $code = $Matches[1] } elseif ($s -cmatch '\b([A-Z0-9]{8,10})\b') { $code = $Matches[1] }
    if ($url -and $code) {
      Save-Json $M365Pending ([ordered]@{ pid = $p.Id; expires_at = (Now) + 900; channel_messages = $chan })
      return , @($url, $code)
    }
    if ($p.HasExited) { break }
  }
  try { $p.Kill() } catch {}
  return $null
}
function Test-PidAlive($id) { try { return [bool](Get-Process -Id ([int]$id) -ErrorAction Stop) } catch { return $false } }

# Graph GET. m365가 있으면 m365 request로, 안 되면 기본 방식(REST)으로.
# REST: 429·503·504는 Retry-After만큼 기다렸다 다시, 401은 토큰을 한 번 새로 받아 다시. -Soft면 막힌 API(400·403·404 등)는 $null.
function Invoke-Graph([string]$path, [bool]$chan = $false, [switch]$Soft) {
  $uri = $path; if ($path -notmatch '^https?://') { $uri = "$Graph$path" }
  if ($script:Mode -ne 'rest' -and (Get-M365Cmd)) {
    $m = M365-Get $uri
    if ($m.ok) { $script:Mode = 'm365'; return $m.data }
    $tag = Get-M365Tag $m.err
    $c = Read-Json $TokenFile
    if (-not ($c -and $c.refresh_token)) {   # 기본 방식 로그인도 없으면 m365 사유로 끝낸다
      if ($Soft -and $tag -notmatch '^(login-needed|network|admin-consent|policy)') { return $null }
      if ($chan -and ($tag -eq 'forbidden' -or $tag -like 'admin-consent*')) { Say "채널 메시지는 회사 관리자 승인이 있어야 읽을 수 있습니다. 파일·채팅은 그대로 쓸 수 있습니다. [$tag]"; exit 0 }
      Fail $tag
    }
    if (-not $script:Mode) { $script:Mode = 'rest' }   # 처음부터 m365가 안 되면 이번 실행은 기본 방식으로
  }
  $tok = Get-Token $chan; $again = $false
  for ($n = 1; $n -le 4; $n++) {
    try { return (Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $tok" } -TimeoutSec 60 -UseBasicParsing) }
    catch {
      $h = Get-HttpInfo $_
      if (@(429, 503, 504) -contains $h.code -and $n -lt 4) {
        $w = [Math]::Pow(2, $n); if ($h.retry -gt 0) { $w = [Math]::Min($h.retry, 30) }
        Start-Sleep -Seconds $w; continue
      }
      if ($h.code -eq 401 -and -not $again) { $script:ForceRefresh = $true; $tok = Get-Token $chan; $again = $true; continue }
      if ($Soft -and @(400, 403, 404, 405, 410, 501) -contains $h.code) { return $null }
      Fail (Get-Tag $h)
    }
  }
  if ($Soft) { return $null }
  Fail 'busy'
}
function Get-All([string]$path, [int]$max = 500, [bool]$chan = $false, [switch]$Soft) {
  $items = New-Object System.Collections.ArrayList
  $next = $path; $pages = 0; $script:LastSoftMiss = $false
  while ($next -and $items.Count -lt $max -and $pages -lt 50) {
    $r = Invoke-Graph $next $chan -Soft:$Soft
    if ($null -eq $r) { $script:LastSoftMiss = $true; break }
    if ($r.value) { foreach ($v in $r.value) { if ($items.Count -ge $max) { break }; [void]$items.Add($v) } }
    $next = $r.'@odata.nextLink'; $pages++
  }
  return $items.ToArray()
}
# 결과를 memory\teams\ 에 CSV로 남기고 화면에는 앞 40줄만 표로 보여 준다
function Write-Result($rows, [string]$name, [string[]]$cols, [string[]]$show) {
  $rows = @($rows | Where-Object { $null -ne $_ })
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $file = Join-Path $OutDir ('{0}-{1}.csv' -f $name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
  if ($rows.Count -gt 0) { $rows | Select-Object $cols | Export-Csv -LiteralPath $file -NoTypeInformation -Encoding UTF8 }
  else { [IO.File]::WriteAllText($file, ('"' + ($cols -join '","') + '"' + "`r`n"), (New-Object Text.UTF8Encoding $true)) }
  Say ('{0}건 → {1}' -f $rows.Count, $file.Substring($Ws.Length).TrimStart('\', '/'))
  if ($rows.Count -gt 0) { Say ('  ' + ($show -join ' | ')) }
  foreach ($r in ($rows | Select-Object -First 40)) { Say ('  ' + (($show | ForEach-Object { [string]$r.$_ }) -join ' | ')) }
  if ($rows.Count -gt 40) { Say ('  … 나머지 {0}건은 CSV에 있습니다' -f ($rows.Count - 40)) }
}
function Find-One($list, [string]$q, [string]$what, [string]$listCmd) {
  $list = @($list)
  $hit = @($list | Where-Object { $_.id -eq $q })
  if ($hit.Count -eq 0) { $hit = @($list | Where-Object { $_.displayName -eq $q }) }
  if ($hit.Count -eq 0) { $hit = @($list | Where-Object { $_.displayName -and $_.displayName.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0 }) }
  if ($hit.Count -eq 1) { return $hit[0] }
  if ($hit.Count -gt 1) { Say ("'{0}'에 맞는 {1}이 여러 개입니다: {2}" -f $q, $what, ((@($hit | Select-Object -First 10) | ForEach-Object { $_.displayName }) -join ', ')); exit 0 }
  Say ("'{0}' {1}을 찾지 못했습니다. {2}로 목록을 봅니다." -f $q, $what, $listCmd); exit 0
}
function Resolve-Team([string]$q) {
  if (-not $q) { Say '팀 이름이 필요합니다. 예: files "품질팀" "일반"'; exit 0 }
  return (Find-One (Get-All '/me/joinedTeams' 500) $q '팀' 'teams')
}
function Resolve-Channel([string]$tid, [string]$q) { return (Find-One (Get-All "/teams/$tid/channels" 500) $q '채널' 'channels') }
function Msg-Row($m) {
  [pscustomobject]@{
    time = (D $m.createdDateTime)
    from = (Pick $m.from.user.displayName $m.from.application.displayName)
    text = (Text $m.body.content)
    files = ((@($m.attachments) | Where-Object { $_ -and $_.name } | ForEach-Object { $_.name }) -join '; ')
    messageId = $m.id
  }
}

# ---------- setup-m365: 관리자 권한 없이 사용자 폴더에 Node LTS + m365 설치 ----------
function Setup-M365 {
  $t0 = Get-Date; $deadline = $t0.AddSeconds($SetupSeconds)
  New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
  $enc = New-Object Text.UTF8Encoding $false
  function L([string]$m) { [IO.File]::AppendAllText($SetupLog, ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) + "`r`n", $enc) }
  function Left { return ($deadline - (Get-Date)).TotalSeconds }
  function Run-Logged([string]$file, [string[]]$argv, [hashtable]$envs, [int]$max = 0) {   # 진행 출력은 로그에만
    $t = [int](Left); if ($max -gt 0) { $t = [Math]::Min($t, $max) }
    L ('$ ' + $file + ' ' + ($argv -join ' '))
    $r = Run-Proc $file $argv ([Math]::Max(1, $t)) $envs
    if ($r.out) { L $r.out.TrimEnd() }; if ($r.err) { L $r.err.TrimEnd() }
    L "종료 코드 $($r.code)"
    return $r.code
  }
  # 내려받기. 409·429·5xx는 2·4·8초(+지터) 뒤 다시. $dest가 없으면 내용(문자열)을 돌려준다.
  function Fetch([string]$url, [string]$dest) {
    for ($n = 0; $n -lt 4; $n++) {
      if ((Left) -lt 5) { throw 'setup: 시간 초과' }
      L "GET $url"
      $code = 0
      try {
        $t = [int][Math]::Max(5, [Math]::Min(240, (Left)))
        if ($dest) { Invoke-WebRequest -Uri $url -OutFile $dest -TimeoutSec $t -UseBasicParsing -UserAgent 'workmate-setup' | Out-Null; return $dest }
        return [string](Invoke-WebRequest -Uri $url -TimeoutSec $t -UseBasicParsing -UserAgent 'workmate-setup').Content
      } catch {
        $h = Get-HttpInfo $_; $code = $h.code
        L ("HTTP {0} {1}" -f $code, $_.Exception.Message)
      }
      if (($code -eq 409 -or $code -eq 429 -or $code -ge 500) -and $n -lt 3) { Start-Sleep -Milliseconds ([int]([Math]::Pow(2, $n + 1) * 1000) + (Get-Random -Maximum 1000)); continue }
      throw "setup: HTTP $code"
    }
    throw 'setup: busy'
  }
  function Node-Major([string]$node) { $r = Run-Proc $node @('-v') 20 $null; if ($r.code -eq 0 -and $r.out -match 'v(\d+)\.') { return [int]$Matches[1] }; return 0 }
  function Ok-Line([string]$head) {
    $v = Run-M365 @('version', '-o', 'json') 60; $ver = ''
    if ($v.code -eq 0) { $ver = $v.out.Trim().Trim('"') }
    $c = @(Get-M365Cmd); $place = $c[-1]; if ($place.StartsWith($M365Dir)) { $place = $M365Dir }
    L ("완료: {0} {1} {2} ({3:N0}초)" -f $head, $place, $ver, ((Get-Date) - $t0).TotalSeconds)
    if ($ver) { Say ("{0}: {1} (m365 {2})" -f $head, $place, $ver) } else { Say ("{0}: {1}" -f $head, $place) }
  }

  $tmp = "$NodeDir.tmp"
  try {
    L '=== setup-m365 시작 ==='
    # 0) 이미 있으면 끝
    if (Get-M365Cmd) {
      $v = Run-M365 @('version', '-o', 'json') 60
      if ($v.code -eq 0) {
        if (-not (Read-Json $M365Rec)) { Save-Json $M365Rec ([ordered]@{ cmd = @(Get-M365Cmd); version = $v.out.Trim().Trim('"') }) }
        Ok-Line '팀즈 도구가 이미 있습니다'; return
      }
      L '있는 m365가 실행되지 않음'
    }
    $entry = Join-Path $M365Dir 'node_modules\@pnp\cli-microsoft365\dist\index.js'
    # 1) Node: 이미 받아 둔 것 → 시스템 Node(LTS 22·24) → nodejs.org 포터블 zip
    $node = Join-Path $NodeDir 'node.exe'; $npmCli = Join-Path $NodeDir 'node_modules\npm\bin\npm-cli.js'
    if (-not ((Test-Path -LiteralPath $node) -and (Test-Path -LiteralPath $npmCli) -and ($NodeMajors -contains (Node-Major $node)))) {
      $node = ''; $npmCli = ''
      $sys = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($sys) {
        $mj = Node-Major $sys.Source
        $cand = Join-Path (Split-Path $sys.Source) 'node_modules\npm\bin\npm-cli.js'
        if (($NodeMajors -contains $mj) -and (Test-Path -LiteralPath $cand)) { $node = $sys.Source; $npmCli = $cand; L "시스템 Node 사용: $node v$mj" }
        else { L "시스템 Node v$mj 는 쓰지 않음(LTS $($NodeMajors -join '·')만)" }
      }
    }
    if (-not $node) {
      $arch = 'x64'; if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { $arch = 'arm64' }
      Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
      New-Item -ItemType Directory -Force -Path $tmp | Out-Null
      $ver = $NodePin; $sums = ''
      try { $sums = Fetch "$NodeDist/$ver/SHASUMS256.txt" '' }
      catch {
        if ([string]$_ -notmatch 'HTTP 404') { throw }
        $idx = (Fetch "$NodeDist/index.json" '') | ConvertFrom-Json   # 고정 버전이 없어졌으면 최신 LTS(22·24)로
        $hit = @($idx | Where-Object { $_.lts -and (@($_.files) -contains "win-$arch-zip") -and ($NodeMajors -contains [int](($_.version -replace '^v', '') -split '\.')[0]) } | Select-Object -First 1)
        if ($hit.Count -eq 0) { throw 'setup: LTS 없음' }
        $ver = [string]$hit[0].version; L "고정 버전 대신 $ver"
        $sums = Fetch "$NodeDist/$ver/SHASUMS256.txt" ''
      }
      $name = "node-$ver-win-$arch.zip"
      $want = ''
      foreach ($ln in ($sums -split "`n")) { $ln = $ln.Trim(); if ($ln.EndsWith(" $name")) { $want = ($ln -split '\s+')[0] } }
      $zip = Join-Path $tmp $name
      Fetch "$NodeDist/$ver/$name" $zip | Out-Null
      $got = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
      if (-not $want -or $got -ne $want.ToLower()) { throw 'setup: SHA256 불일치' }
      L ("Node {0} 받음 {1:N1}MB, SHA256 확인" -f $ver, ((Get-Item -LiteralPath $zip).Length / 1MB))
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      [IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
      Remove-Item -LiteralPath $zip -Force
      Remove-Item -LiteralPath $NodeDir -Recurse -Force -ErrorAction SilentlyContinue
      Move-Item -LiteralPath (Join-Path $tmp ($name -replace '\.zip$', '')) -Destination $NodeDir
      Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
      $node = Join-Path $NodeDir 'node.exe'; $npmCli = Join-Path $NodeDir 'node_modules\npm\bin\npm-cli.js'
      if ($NodeMajors -notcontains (Node-Major $node)) { throw 'setup: Node 실행 안 됨' }
    }
    # 2) m365: npm 전역 설치를 사용자 폴더(prefix)로만. 재시도는 npm에 2·4·8초로 맡긴다
    $envs = @{
      PATH = (Split-Path $node) + [IO.Path]::PathSeparator + $env:PATH   # keytar 설치 스크립트가 같은 Node를 쓰게
      npm_config_update_notifier = 'false'; npm_config_fund = 'false'; npm_config_audit = 'false'
      npm_config_allow_scripts = '@azure/msal-node-extensions,keytar'   # 새 npm이 설치 스크립트를 막아도 keytar 바이너리는 받게
    }
    if ($NpmRegistry) { $envs['npm_config_registry'] = $NpmRegistry }
    if (-not $env:HTTPS_PROXY -and -not $env:npm_config_https_proxy) {   # 회사 프록시(시스템 설정)를 npm에도
      try {
        $px = [Net.WebRequest]::GetSystemWebProxy().GetProxy([Uri]'https://registry.npmjs.org/')
        if ($px -and $px.AbsoluteUri -ne 'https://registry.npmjs.org/') { $envs['npm_config_https_proxy'] = $px.AbsoluteUri; $envs['npm_config_proxy'] = $px.AbsoluteUri; L "프록시 사용: $($px.Host)" }
      } catch {}
    }
    if (-not (Test-Path -LiteralPath $entry)) {
      $rc = Run-Logged $node @($npmCli, 'install', '-g', '--prefix', $M365Dir, "$M365Pkg@$M365Ver", '--no-audit', '--no-fund', '--loglevel=warn',
        '--fetch-retries=3', '--fetch-retry-factor=2', '--fetch-retry-mintimeout=2000', '--fetch-retry-maxtimeout=8000') $envs
      if ($rc -ne 0 -or -not (Test-Path -LiteralPath $entry)) { throw "setup: npm 종료 코드 $rc" }
    }
    # 3) 로그인 저장(keytar) 확인 — m365 12는 Windows·맥에서 keytar 없이 로그인 정보를 저장하지 못한다
    $pkg = Split-Path (Split-Path $entry)
    $js = "const p=require('path'),u=require('url');const d=p.dirname(require.resolve('@azure/msal-node-extensions/package.json',{paths:[process.argv[1]]}));" +
      "import(u.pathToFileURL(p.join(d,'dist','index.mjs')).href).then(()=>console.log('keytar ok'),e=>{console.error(String(e&&e.message||e));process.exit(1)})"
    if ((Run-Logged $node @('-e', $js, $pkg) $envs 60) -ne 0) {
      Run-Logged $node @($npmCli, 'rebuild', 'keytar', '--prefix', $pkg) $envs | Out-Null   # 한 번만 다시 받거나 빌드
      if ((Run-Logged $node @('-e', $js, $pkg) $envs 60) -ne 0) { throw 'setup: keytar' }
    }
    Save-Json $M365Rec ([ordered]@{ cmd = @($node, $entry); version = $M365Ver })
    Run-M365 @('cli', 'config', 'set', '--key', 'prompt', '--value', 'false') 60 | Out-Null   # 빠진 값을 묻느라 멈추지 않게
    Ok-Line '팀즈 도구를 설치했습니다'
  } catch {
    try { L ("실패: {0} ({1:N0}초)" -f $_, ((Get-Date) - $t0).TotalSeconds) } catch {}
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Say $SetupFailLine
  }
}

function Start-RestLogin {
  try {
    $d = Invoke-RestMethod -Method Post -Uri "$LoginHost/organizations/oauth2/v2.0/devicecode" -Body @{ client_id = $ClientId; scope = $Scopes } -ContentType 'application/x-www-form-urlencoded' -TimeoutSec 30 -UseBasicParsing
  } catch { Fail (Get-Tag (Get-HttpInfo $_)) }
  if (-not $d.user_code) { Fail 'error' }
  Save-Json $PendingFile ([ordered]@{ device_code = [string]$d.device_code; interval = [int]$d.interval; expires_at = (Now) + [int]$d.expires_in; channel_messages = [bool]$WithChannelMessages })
  Say ("브라우저에서 {0} 에 들어가 코드 칸에 {1} 입력 후 회사 계정으로 로그인하세요. ({2}분 안에)" -f $d.verification_uri, $d.user_code, [int]([int]$d.expires_in / 60))
  Say '[다음: 로그인을 마치면 login-wait]'
}

try {
  switch ($Command.ToLower()) {
    'setup-m365' {
      try { Setup-M365 } catch { Say $SetupFailLine }
    }
    'status' {
      if (Get-M365Cmd) { $who = Get-M365Who; if ($who) { Say "팀즈 연결됨: $who (도구: m365)"; exit 0 } }
      if (-not (Read-Json $TokenFile)) { if (Get-M365Cmd) { Fail 'login-needed m365' }; Fail 'login-needed' }
      $script:Mode = 'rest'
      $me = Invoke-Graph '/me?$select=displayName'
      $ch = '쓰지 않음'; if ((Read-Json $TokenFile).channel_messages) { $ch = '가능' }
      Say ("팀즈 연결됨: {0} (채널 메시지: {1})" -f $me.displayName, $ch)
    }
    'login' {
      if (-not $Force) {
        if (Get-M365Cmd) { $who = Get-M365Who; if ($who) { Say "이미 팀즈에 연결돼 있습니다: $who"; exit 0 } }
        if (Read-Json $TokenFile) {
          $script:Mode = 'rest'; $script:Quiet = $true; $me = $null   # 저장된 로그인이 만료됐으면 조용히 새 로그인으로
          try { $me = Invoke-Graph '/me?$select=displayName' -Soft } catch { $me = $null }
          $script:Quiet = $false
          if ($me) { Say ("이미 팀즈에 연결돼 있습니다: {0}" -f $me.displayName); exit 0 }
        }
      }
      Remove-Item -LiteralPath $PendingFile, $M365Pending -Force -ErrorAction SilentlyContinue
      $got = $null; if (Get-M365Cmd) { $got = Start-M365Login ([bool]$WithChannelMessages) }   # m365가 있으면 m365로, 안 되면 기본 방식으로
      if ($got) {
        Say ("브라우저에서 {0} 에 들어가 코드 칸에 {1} 입력 후 회사 계정으로 로그인하세요. (15분 안에)" -f $got[0], $got[1])
        Say '[다음: 로그인을 마치면 login-wait]'; exit 0
      }
      Start-RestLogin
    }
    'login-wait' {
      $mp = Read-Json $M365Pending
      if ($mp) {
        $exp = [long]$mp.expires_at; $end = [Math]::Min($exp, (Now) + [Math]::Max(5, $Wait))
        while ($true) {
          $who = Get-M365Who
          if ($who) { Remove-Item -LiteralPath $M365Pending -Force -ErrorAction SilentlyContinue; Say "팀즈에 연결됐습니다: $who"; exit 0 }
          if (-not (Test-PidAlive $mp.pid) -or (Now) -ge $end) { break }
          Start-Sleep -Seconds 5
        }
        if (-not (Test-PidAlive $mp.pid)) {   # m365 로그인이 끝났는데 연결이 안 됐다
          Remove-Item -LiteralPath $M365Pending -Force -ErrorAction SilentlyContinue
          $tail = (Read-Shared $M365LoginLog) + "`n" + (Read-Shared $M365LoginErr)
          $tag = Get-M365Tag $tail
          if ($tag -match '^(admin-consent|policy|network)') { Fail $tag }
          Say '다른 방식으로 로그인 코드를 다시 받았습니다.'
          Start-RestLogin; exit 0
        }
        if ((Now) -ge $exp) { Remove-Item -LiteralPath $M365Pending -Force -ErrorAction SilentlyContinue; Fail 'expired' }
        Say '아직 로그인이 끝나지 않았습니다. 브라우저에서 로그인을 마치면 login-wait를 다시 실행합니다. [pending]'
        exit 0
      }
      $p = Read-Json $PendingFile
      if (-not $p -or -not $p.device_code) {
        if (Read-Json $TokenFile) { Say '이미 팀즈에 연결돼 있습니다.'; exit 0 }
        Fail 'login-needed'
      }
      $exp = [long]$p.expires_at; $end = [Math]::Min($exp, (Now) + [Math]::Max(5, $Wait)); $iv = [Math]::Max(5, [int]$p.interval)
      while ((Now) -lt $end) {
        $r = Post-Token @{ grant_type = 'urn:ietf:params:oauth:grant-type:device_code'; client_id = $ClientId; device_code = [string]$p.device_code }
        if ($r.ok) {
          Remove-Item -LiteralPath $PendingFile -Force -ErrorAction SilentlyContinue
          Save-Tokens $r.data $Scopes $false $null
          $me = Invoke-Graph '/me?$select=displayName' -Soft
          Say ("팀즈에 연결됐습니다: {0}" -f (Pick $me.displayName '로그인한 계정'))
          if ($p.channel_messages) {   # 채널 메시지 권한은 로그인과 따로 받아 본다 — 안 되면 그 기능만 빠진다
            $c = Read-Json $TokenFile
            $q = Post-Token @{ grant_type = 'refresh_token'; client_id = $ClientId; refresh_token = [string]$c.refresh_token; scope = "$Scopes $ChanScope" }
            if ($q.ok) { Save-Tokens $q.data "$Scopes $ChanScope" $true $c; Say '채널 메시지: 읽기 가능' }
            else { Say "채널 메시지: 회사 관리자 승인이 없어 빼고 연결했습니다. [$($q.tag)]" }
          }
          exit 0
        }
        if ($r.error -eq 'authorization_pending') { Start-Sleep -Seconds $iv; continue }
        if ($r.error -eq 'slow_down') { $iv += 5; Start-Sleep -Seconds $iv; continue }
        Remove-Item -LiteralPath $PendingFile -Force -ErrorAction SilentlyContinue
        Fail $r.tag
      }
      if ((Now) -ge $exp) { Remove-Item -LiteralPath $PendingFile -Force -ErrorAction SilentlyContinue; Fail 'expired' }
      Say '아직 로그인이 끝나지 않았습니다. 브라우저에서 로그인을 마치면 login-wait를 다시 실행합니다. [pending]'
    }
    'logout' {
      Remove-Item -LiteralPath $TokenFile, $PendingFile, $M365Pending, $M365LoginLog, $M365LoginErr -Force -ErrorAction SilentlyContinue
      if (Get-M365Cmd) { Run-M365 @('logout') 60 | Out-Null }
      Say '이 PC에서 팀즈 로그인 정보를 지웠습니다.'
    }
    'teams' {
      $rows = Get-All '/me/joinedTeams' 500 | ForEach-Object { [pscustomobject]@{ name = $_.displayName; description = (Text $_.description); teamId = $_.id } }
      Write-Result $rows 'teams' @('name', 'description', 'teamId') @('name', 'description')
    }
    'channels' {
      $t = Resolve-Team $Arg1
      $rows = Get-All "/teams/$($t.id)/channels" 500 | ForEach-Object { [pscustomobject]@{ name = $_.displayName; type = $_.membershipType; description = (Text $_.description); channelId = $_.id } }
      Write-Result $rows ('channels-' + (Safe $t.displayName)) @('name', 'type', 'description', 'channelId') @('name', 'type', 'description')
    }
    'files' {
      $t = Resolve-Team $Arg1
      $label = $t.displayName
      if ($Arg2) {   # 채널 '파일' 탭 = 채널 폴더(비공개·공유 채널은 따로 있는 사이트)
        $ch = Resolve-Channel $t.id $Arg2
        $f = Invoke-Graph "/teams/$($t.id)/channels/$($ch.id)/filesFolder"
        $drive = [string]$f.parentReference.driveId; $rootId = [string]$f.id; $label = "$label-$($ch.displayName)"
      } else {        # 팀 전체 문서 라이브러리(채널마다 폴더)
        $g = Invoke-Graph "/groups/$($t.id)/drive"
        $drive = [string]$g.id; $rootId = 'root'
      }
      $Depth = [Math]::Max(1, [Math]::Min($Depth, 5)); $max = 1000
      $rows = New-Object System.Collections.ArrayList
      $queue = New-Object System.Collections.Queue
      $queue.Enqueue(@($rootId, '', 1))
      while ($queue.Count -gt 0 -and $rows.Count -lt $max) {
        $q = $queue.Dequeue()
        $kids = Get-All ("/drives/$drive/items/$($q[0])/children" + '?$top=200&$select=id,name,size,lastModifiedDateTime,lastModifiedBy,folder,file,webUrl') $max
        foreach ($k in $kids) {
          $path = $k.name; if ($q[1]) { $path = "$($q[1])/$($k.name)" }
          $type = '파일'; if ($k.folder) { $type = '폴더' }
          [void]$rows.Add([pscustomobject]@{ path = $path; type = $type; size = (Size $k.size); modified = (D $k.lastModifiedDateTime); by = $k.lastModifiedBy.user.displayName; driveId = $drive; itemId = $k.id; webUrl = $k.webUrl })
          if ($k.folder -and $q[2] -lt $Depth) { $queue.Enqueue(@($k.id, $path, ($q[2] + 1))) }
          if ($rows.Count -ge $max) { break }
        }
      }
      Write-Result $rows.ToArray() ('files-' + (Safe $label)) @('path', 'type', 'size', 'modified', 'by', 'driveId', 'itemId', 'webUrl') @('path', 'type', 'size', 'modified', 'by')
    }
    { $_ -in 'shared', 'recent' } {
      $api = '/me/drive/sharedWithMe'; if ($_ -eq 'recent') { $api = '/me/drive/recent' }
      $items = Get-All $api 500 -Soft   # 회사가 막아 둔 API면 조용히 빈 결과
      $miss = $script:LastSoftMiss
      $rows = $items | ForEach-Object {
        $ri = $_.remoteItem
        [pscustomobject]@{
          name = (Pick $ri.name $_.name)
          size = (Size (Pick $ri.size $_.size))
          modified = (D (Pick $ri.lastModifiedDateTime $_.lastModifiedDateTime))
          by = (Pick $ri.shared.sharedBy.user.displayName $ri.shared.owner.user.displayName $ri.lastModifiedBy.user.displayName $_.lastModifiedBy.user.displayName)
          type = $(if ($ri.folder -or $_.folder) { '폴더' } else { '파일' })
          driveId = (Pick $ri.parentReference.driveId $_.parentReference.driveId)
          itemId = (Pick $ri.id $_.id)
          webUrl = (Pick $ri.webUrl $_.webUrl)
        }
      }
      Write-Result $rows $Command.ToLower() @('name', 'type', 'size', 'modified', 'by', 'driveId', 'itemId', 'webUrl') @('name', 'type', 'size', 'modified', 'by')
      if ($miss -and @($rows).Count -eq 0) { Say '  (이 목록은 회사 설정으로 비어 있을 수 있습니다. files로 팀 파일을 봅니다.)' }
    }
    'get' {
      if (-not $Arg1 -or -not $Arg2) { Say 'driveId와 itemId가 필요합니다(files·shared·recent 결과 CSV의 driveId·itemId 열).'; exit 0 }
      $it = Invoke-Graph "/drives/$Arg1/items/$Arg2"
      if (-not $it.file) { Say '폴더는 가져오지 않습니다. files로 안의 파일을 보고 파일을 고릅니다.'; exit 0 }
      if ([double]$it.size -gt $MaxBytes) { Say ("50MB가 넘어 가져오지 않았습니다: {0} ({1}). 팀즈에서 직접 내려받으세요." -f $it.name, (Size $it.size)); exit 0 }
      New-Item -ItemType Directory -Force -Path $InboxDir | Out-Null
      $name = [string]$it.name; foreach ($ch in [IO.Path]::GetInvalidFileNameChars()) { $name = $name.Replace([string]$ch, '_') }
      $target = Join-Path $InboxDir $name; $i = 1
      while (Test-Path -LiteralPath $target) { $target = Join-Path $InboxDir ('{0}_{1}{2}' -f [IO.Path]::GetFileNameWithoutExtension($name), $i, [IO.Path]::GetExtension($name)); $i++ }
      $url = [string]$it.'@microsoft.graph.downloadUrl'   # 짧게 유효한 내려받기 주소(토큰을 다른 서버로 보내지 않는다). 화면·파일에 쓰지 않는다
      $m365Ok = $false
      if (-not $url -and $script:Mode -eq 'm365') {   # 내려받기 주소가 없으면 m365가 토큰을 붙여 받는다
        $r = Run-M365 @('request', '--url', "$Graph/drives/$Arg1/items/$Arg2/content", '--filePath', $target) 300
        $m365Ok = ($r.code -eq 0 -and (Test-Path -LiteralPath $target))
        if (-not $m365Ok) { Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue }
      }
      if (-not $m365Ok) { try {
        if ($url) { Invoke-WebRequest -Uri $url -OutFile $target -TimeoutSec 300 -UseBasicParsing | Out-Null }
        else { Invoke-WebRequest -Uri "$Graph/drives/$Arg1/items/$Arg2/content" -Headers @{ Authorization = "Bearer $(Get-Token)" } -OutFile $target -TimeoutSec 300 -UseBasicParsing | Out-Null }
      } catch {
        Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        Fail (Get-Tag (Get-HttpInfo $_))
      } }
      [pscustomobject]@{ file = (Split-Path $target -Leaf); from = $it.webUrl; modified = (D $it.lastModifiedDateTime); fetched = (Get-Date -Format 'yyyy-MM-dd HH:mm'); driveId = $Arg1; itemId = $Arg2 } |
        Export-Csv -LiteralPath (Join-Path $InboxDir '_목록.csv') -NoTypeInformation -Encoding UTF8 -Append
      Say ("가져옴: {0} ({1}). 원본은 팀즈에 그대로 있습니다." -f $target.Substring($Ws.Length).TrimStart('\', '/'), (Size $it.size))
    }
    'chats' {
      $rows = Get-All '/me/chats?$expand=members&$top=50' 50 | ForEach-Object {
        $who = (@($_.members) | Where-Object { $_ -and $_.displayName } | Select-Object -First 6 | ForEach-Object { $_.displayName }) -join ', '
        [pscustomobject]@{ name = (Pick $_.topic $who '(이름 없음)'); type = $_.chatType; updated = (D $_.lastUpdatedDateTime); members = $who; chatId = $_.id }
      } | Sort-Object updated -Descending
      Write-Result $rows 'chats' @('name', 'type', 'updated', 'members', 'chatId') @('name', 'type', 'updated')
    }
    'chat-messages' {
      if (-not $Arg1) { Say '채팅 id나 이름이 필요합니다(chats 결과 CSV의 chatId 열).'; exit 0 }
      $cid = $Arg1
      if ($cid -notmatch '^19:') {
        $list = Get-All '/me/chats?$expand=members&$top=50' 50 | ForEach-Object { [pscustomobject]@{ id = $_.id; displayName = (Pick $_.topic ((@($_.members) | ForEach-Object { $_.displayName }) -join ', ')) } }
        $cid = (Find-One $list $Arg1 '채팅' 'chats').id
      }
      $n = [Math]::Max(1, [Math]::Min($Top, 50))
      $r = Invoke-Graph ("/chats/$cid/messages" + '?$top=' + $n)
      $rows = @($r.value) | Where-Object { $_ -and $_.messageType -eq 'message' } | ForEach-Object { Msg-Row $_ } | Sort-Object time
      Write-Result $rows 'chat-messages' @('time', 'from', 'text', 'files', 'messageId') @('time', 'from', 'text')
    }
    'channel-messages' {
      if (-not $WithChannelMessages) { Say '채널 메시지는 -WithChannelMessages를 붙일 때만 읽습니다(회사 관리자 승인이 필요할 수 있습니다).'; exit 0 }
      $t = Resolve-Team $Arg1
      if (-not $Arg2) { Say '채널 이름이 필요합니다. 예: channel-messages "품질팀" "일반" -WithChannelMessages'; exit 0 }
      $ch = Resolve-Channel $t.id $Arg2
      $n = [Math]::Max(1, [Math]::Min($Top, 50))
      $r = Invoke-Graph ("/teams/$($t.id)/channels/$($ch.id)/messages" + '?$top=' + $n) $true
      $rows = @($r.value) | Where-Object { $_ -and $_.messageType -eq 'message' } | ForEach-Object { Msg-Row $_ } | Sort-Object time
      Write-Result $rows ('channel-messages-' + (Safe "$($t.displayName)-$($ch.displayName)")) @('time', 'from', 'text', 'files', 'messageId') @('time', 'from', 'text')
    }
    default {
      Say '사용: setup-m365 | status | login | login-wait | logout | teams | channels <팀> | files <팀> [채널] | shared | recent | get <driveId> <itemId> | chats | chat-messages <채팅> | channel-messages <팀> <채널> -WithChannelMessages'
    }
  }
} catch {
  Fail 'error'
}
exit 0
