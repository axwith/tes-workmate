# 문서 작업(PPT·엑셀·PDF)용 Python 준비 — 묻지 않고 사용자 범위에만 설치한다(관리자 권한·UAC 불필요). Windows PowerShell 5.1 이상
#   powershell -NoProfile -ExecutionPolicy Bypass -File .agents\skills\onboard\scripts\ensure-python.ps1 [-Workspace <폴더>] [-Quiet]
# 순서: 1) 이미 있는 Python(Codex 런타임 → 전에 만든 workmate Python → py → python)에 패키지가 다 있으면 그대로 쓴다
#       2) Python은 있는데 패키지만 없으면 pip --user로 넣는다(Codex 런타임은 앱이 관리하므로 건드리지 않는다)
#       3) 쓸 Python이 없으면 uv(사용자 폴더 exe 하나) → winget 사용자 범위 → python.org 포터블(embeddable) 순으로 설치한다
# 결과는 <업무 공간>\memory\env.md에 적는다. 실패해도 멈추지 않는다(종료 코드 0, 마지막 줄에 결과 한 줄).
param([string]$Workspace = '', [switch]$Quiet)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
if (-not $Workspace) { $Workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path }
function Say($m) { if (-not $Quiet) { Write-Host "  $m" } }

$Pkgs = @('python-pptx', 'openpyxl', 'pypdf', 'Pillow')
$Check = 'import pptx, openpyxl, pypdf, PIL'
$Base = Join-Path $env:LOCALAPPDATA 'workmate'
$Venv = Join-Path $Base 'py'
$VenvPy = Join-Path $Venv 'Scripts\python.exe'
$Portable = Join-Path $Base 'python'
$PortablePy = Join-Path $Portable 'python.exe'
$Runtime = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$env:UV_NATIVE_TLS = '1'   # 회사 SSL 검사 장비가 있어도 Windows 인증서 저장소를 쓰게 한다
$env:PIP_DISABLE_PIP_VERSION_CHECK = '1'

function Test-Py($py) {   # 패키지까지 다 있으면 'ok', 실행만 되면 'bare', 실행이 안 되면 ''
  if (-not $py -or -not (Test-Path $py)) { return '' }
  & $py -c 'import sys' 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { return '' }
  & $py -c $Check 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { return 'ok' } else { return 'bare' }
}

function Get-Candidates {
  $c = @($Runtime, $VenvPy, $PortablePy)
  if (Get-Command py -ErrorAction SilentlyContinue) {
    $e = & py -3 -c 'import sys; print(sys.executable)' 2>$null
    if ($LASTEXITCODE -eq 0 -and $e) { $c += "$e".Trim() }
  }
  foreach ($n in 'python', 'python3') {
    Get-Command $n -All -CommandType Application -ErrorAction SilentlyContinue |
      Where-Object { $_.Source -notlike '*\WindowsApps\*' } | ForEach-Object { $c += $_.Source }   # WindowsApps의 python은 Store 안내 창만 띄운다
  }
  $c += @(Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
  $c | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
}

function Install-Uv {
  $uvDir = Join-Path $Base 'uv'; $uv = Join-Path $uvDir 'uv.exe'
  if (-not (Test-Path $uv)) {
    $zip = Join-Path $env:TEMP 'uv-workmate.zip'
    Invoke-WebRequest -UseBasicParsing 'https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip' -OutFile $zip -ErrorAction Stop
    New-Item -ItemType Directory -Force -Path $uvDir | Out-Null
    Expand-Archive $zip $uvDir -Force -ErrorAction Stop
  }
  if (-not (Test-Path $VenvPy)) { & $uv venv $Venv --python 3.12 --seed --quiet 2>&1 | Out-Null }
  & $uv pip install --python $VenvPy --quiet @Pkgs 2>&1 | Out-Null
  return $VenvPy
}

function Install-Winget {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget 없음' }
  winget install --id Python.Python.3.12 -e --source winget --scope user --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
  $p = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'
  if (-not (Test-Path $p)) { throw 'winget 설치 후 python.exe 없음' }
  & $p -m pip install --user --quiet --no-warn-script-location @Pkgs 2>&1 | Out-Null
  return $p
}

function Install-Portable {
  $ver = '3.12.10'
  $zip = Join-Path $env:TEMP "python-$ver-embed-amd64.zip"
  Invoke-WebRequest -UseBasicParsing "https://www.python.org/ftp/python/$ver/python-$ver-embed-amd64.zip" -OutFile $zip -ErrorAction Stop
  New-Item -ItemType Directory -Force -Path $Portable | Out-Null
  Expand-Archive $zip $Portable -Force -ErrorAction Stop
  Get-ChildItem $Portable -Filter 'python*._pth' | ForEach-Object {   # embeddable은 site가 꺼져 있어 pip 패키지를 못 읽는다
    (Get-Content $_.FullName) -replace '^#\s*import site', 'import site' | Set-Content $_.FullName -Encoding ASCII
  }
  $gp = Join-Path $env:TEMP 'get-pip-workmate.py'
  Invoke-WebRequest -UseBasicParsing 'https://bootstrap.pypa.io/get-pip.py' -OutFile $gp -ErrorAction Stop
  & $PortablePy $gp --quiet --no-warn-script-location 2>&1 | Out-Null
  & $PortablePy -m pip install --quiet --no-warn-script-location @Pkgs 2>&1 | Out-Null
  return $PortablePy
}

$result = ''; $how = ''; $tries = @()
$cands = @(Get-Candidates)
foreach ($p in $cands) { if ((Test-Py $p) -eq 'ok') { $result = $p; $how = '이미 있음'; break } }
if (-not $result) {
  foreach ($p in $cands) {
    if ($p -eq $Runtime -or (Test-Py $p) -ne 'bare') { continue }
    Say "Python($p)에 문서 작업용 패키지를 넣는 중..."
    & $p -m pip install --user --quiet --no-warn-script-location @Pkgs 2>&1 | Out-Null
    if ((Test-Py $p) -eq 'ok') { $result = $p; $how = 'pip --user'; break } else { $tries += "pip --user($p) 실패" }
  }
}
if (-not $result) {
  foreach ($step in @(@('uv', 'Install-Uv'), @('winget 사용자 범위', 'Install-Winget'), @('포터블 Python', 'Install-Portable'))) {
    Say "Python을 사용자 폴더에 설치하는 중($($step[0]), 1~3분)..."
    try {
      $p = & $step[1]
      if ((Test-Py $p) -eq 'ok') { $result = $p; $how = $step[0]; break }
      $tries += "$($step[0]) 실패(패키지 확인 안 됨)"
    } catch { $tries += "$($step[0]) 실패($($_.Exception.Message))" }
  }
}

$mem = Join-Path $Workspace 'memory'
New-Item -ItemType Directory -Force -Path $mem | Out-Null
$lines = @('# 실행 환경 (ensure-python이 자동 기록)', '', "- 확인 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
if ($result) {
  $lines += @("- python: $result", "- 방법: $how", "- 패키지: $($Pkgs -join ', ')")
} else {
  $lines += @('- python: 없음(자동 설치 실패)', "- 시도: $($tries -join ' / ')", '- 대응: PPT는 보고서(문서)로 대신 만든다. 다시 시도하려면 이 스크립트를 다시 실행한다.')
}
[IO.File]::WriteAllText((Join-Path $mem 'env.md'), (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $false))
if ($result) { Write-Host "  Python 준비 완료($how): $result" } else { Write-Host "  Python 자동 설치 실패: $($tries -join ' / ')" }
exit 0
