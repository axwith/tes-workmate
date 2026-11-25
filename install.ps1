# workmate (Codex) 설치기 — Windows PowerShell 5.1 이상
#   irm https://raw.githubusercontent.com/axwith/tes-workmate/main/get.ps1 | iex   (get.ps1이 이 파일을 받아 -File로 실행한다. 이 파일을 iex로 직접 돌리면 BOM 때문에 깨진다)
#   또는 받은 폴더에서: powershell -ExecutionPolicy Bypass -File install.ps1
# 옵션(환경변수): WORKMATE_DIR=설치 위치(기본 문서\workmate), WORKMATE_FROM=로컬 원본 폴더, WORKMATE_SCAN_ROOTS=스캔할 폴더(;로 구분, 지정하면 그 폴더만)
# git이 없으면 묻지 않고 Git for Windows를 사용자 범위로 설치한다(관리자 권한 불필요. 일시 오류는 다시 시도, 그래도 안 되면 winget 사용자 범위).
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Repo = 'axwith/tes-workmate'
$Dir = if ($env:WORKMATE_DIR) { $env:WORKMATE_DIR } else { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'tes-workmate' }
function Say($m) { Write-Host "  $m" }

Write-Host "`nworkmate 설치를 시작합니다 → $Dir`n"

# 1. git 확인 — 1교시 @lab1이 이미 준비했으면 그 git을 쓰고, 없으면 묻지 않고 설치한다(변경 기록·되돌리기에 필요)
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
  $gpf = Join-Path $env:LOCALAPPDATA 'workmate\git-path.txt'
  $known = @("$env:LOCALAPPDATA\Programs\Git\cmd\git.exe", "$env:ProgramFiles\Git\cmd\git.exe")
  if (Test-Path $gpf) { $known = @((Get-Content $gpf -TotalCount 1)) + $known }
  foreach ($p in $known) { if ($p -and (Test-Path $p)) { $env:Path = "$(Split-Path $p -Parent);$env:Path"; break } }
  $git = Get-Command git -ErrorAction SilentlyContinue
}
if (-not $git) {
  Say 'git이 없어 설치합니다(관리자 권한 없이, 1분 안팎).'
  $gitHome = "$env:LOCALAPPDATA\Programs\Git"
  $ProgressPreference = 'SilentlyContinue'
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
  $gitOk = $false
  # Git for Windows 설치 파일을 사용자 범위(/CURRENTUSER, UAC 없음)로 무인 설치한다. 고정 버전 주소 → GitHub API 최신 순.
  # 409·429·5xx·연결 끊김·덜 받은 파일은 2·4·8초(+무작위) 기다렸다 다시 받는다(1회차에서 409로 한 번 멈춘 적이 있다)
  foreach ($src in 'fixed', 'api') {
    for ($n = 1; $n -le 4 -and -not $gitOk; $n++) {
      $gz = Join-Path $env:TEMP ('git-setup-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.exe')
      try {
        if ($src -eq 'fixed') { $u = 'https://github.com/git-for-windows/git/releases/download/v2.56.1.windows.1/Git-2.56.1-64-bit.exe' }
        else {
          $rel = Invoke-RestMethod -UseBasicParsing 'https://api.github.com/repos/git-for-windows/git/releases/latest' -TimeoutSec 20
          $u = ($rel.assets | Where-Object { $_.name -match '^Git-[\d\.]+-64-bit\.exe$' } | Select-Object -First 1).browser_download_url
        }
        Invoke-WebRequest -UseBasicParsing $u -OutFile $gz -TimeoutSec 180
        if ((Get-Item $gz).Length -lt 20MB) { throw (New-Object System.IO.InvalidDataException 'short') }
      } catch {
        Remove-Item $gz -Force -ErrorAction SilentlyContinue
        $code = 0; try { if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode } } catch {}
        if (-not ($code -eq 0 -or @(408, 409, 425, 429, 500, 502, 503, 504) -contains $code)) { break }
        if ($n -lt 4) { Start-Sleep -Milliseconds ([int]((2 * [Math]::Pow(2, $n - 1) + (Get-Random -Maximum 1.0)) * 1000)) }
        continue
      }
      try {
        $gp = Start-Process -FilePath $gz -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /SUPPRESSMSGBOXES /CURRENTUSER /NOICONS /DIR=`"$gitHome`"" -WindowStyle Hidden -PassThru
        if (-not $gp.WaitForExit(240000)) { try { $gp.Kill() } catch {} }
      } catch {}
      Remove-Item $gz -Force -ErrorAction SilentlyContinue
      $gitOk = Test-Path "$gitHome\cmd\git.exe"
      break
    }
    if ($gitOk) { break }
  }
  if ($gitOk) {
    # 작업 스케줄러(sync)와 Codex 앱도 git을 찾도록 사용자 PATH에 영구 등록
    $up = [Environment]::GetEnvironmentVariable('Path','User')
    if (-not (($up -split ';') -contains "$gitHome\cmd")) { [Environment]::SetEnvironmentVariable('Path', ((@($up, "$gitHome\cmd") | Where-Object { $_ }) -join ';'), 'User') }
  } elseif (Get-Command winget -ErrorAction SilentlyContinue) {
    try {
      $wp = Start-Process winget -ArgumentList 'install --id Git.Git -e --source winget --scope user --silent --accept-package-agreements --accept-source-agreements --disable-interactivity' -WindowStyle Hidden -PassThru
      if (-not $wp.WaitForExit(180000)) { try { $wp.Kill() } catch {} }
    } catch {}
  }
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
  foreach ($p in "$env:LOCALAPPDATA\Programs\Git\cmd", "$env:ProgramFiles\Git\cmd") { if (Test-Path (Join-Path $p 'git.exe')) { $env:Path = "$p;$env:Path" } }
  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($git) { Say 'git 설치 완료.' } else { Say 'git 설치에 실패했습니다. git 없이 계속합니다(나중에 다시 실행하면 다시 설치를 시도합니다).' }
}

# 2. 원본 받기
$tmp = Join-Path $env:TEMP ("workmate-src-" + [guid]::NewGuid().ToString('N').Substring(0,8))
if ($env:WORKMATE_FROM) {
  $src = $env:WORKMATE_FROM
} elseif ($git) {
  $ErrorActionPreference = 'Continue'   # git은 진행 안내를 stderr로 쓴다. PS 5.1은 이를 오류로 바꿔 Stop에서 멈춘다
  git clone --depth 1 "https://github.com/$Repo.git" $tmp 2>&1 | Out-Null
  $ErrorActionPreference = 'Stop'
  if (-not (Test-Path (Join-Path $tmp 'AGENTS.md'))) { throw "원본을 받지 못했습니다(https://github.com/$Repo). 비공개 저장소면 GitHub 로그인이 필요합니다." }
  $src = $tmp
} else {
  $zip = "$tmp.zip"
  Invoke-WebRequest -UseBasicParsing "https://github.com/$Repo/archive/refs/heads/main.zip" -OutFile $zip
  Expand-Archive $zip $tmp -Force; $src = (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName
}

# 3. 설치 또는 업데이트
$skills = 'prescan','onboard','inbox-sort','wrap','dashboard','thickness-map','ppt-draft','excel-to-report','meeting-brief','foreign-matter-car','cross-check','teams'
if (Test-Path (Join-Path $Dir 'AGENTS.md')) {
  Say '이미 설치돼 있습니다. 기본 스킬만 새 버전으로 바꾸고, 기억·규칙·업무 폴더는 그대로 둡니다.'
  foreach ($s in $skills) {
    $to = Join-Path $Dir ".agents\skills\$s"
    if (Test-Path $to) { try { Remove-Item $to -Recurse -Force } catch { Start-Sleep 2; Remove-Item $to -Recurse -Force -ErrorAction SilentlyContinue } }
    if (Test-Path $to) { Copy-Item (Join-Path $src ".agents\skills\$s\*") $to -Recurse -Force } else { Copy-Item (Join-Path $src ".agents\skills\$s") $to -Recurse -Force }
  }
  if ((Get-FileHash (Join-Path $src 'AGENTS.md')).Hash -ne (Get-FileHash (Join-Path $Dir 'AGENTS.md')).Hash) {
    Copy-Item (Join-Path $src 'AGENTS.md') (Join-Path $Dir 'AGENTS.md.new') -Force
    Say '새 기본 AGENTS.md는 AGENTS.md.new로 두었습니다. Codex에 "AGENTS.md.new에서 바뀐 기본 규칙만 합쳐 줘"라고 하면 됩니다.'
  }
} else {
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  Get-ChildItem -LiteralPath $src -Force | Where-Object { -not $_.Name.StartsWith('._') -and $_.Name -notin '.git','.gitattributes','install.ps1','install.sh','get.ps1','README.md','LICENSE','tests' } |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Dir $_.Name) -Recurse -Force }
  if ($git) {
    Push-Location $Dir
    $ErrorActionPreference = 'Continue'
    git init -q; git config core.autocrlf false; git config core.quotepath false; git add -A 2>$null; git -c user.name=workmate -c user.email=workmate@local commit -q -m "workmate 설치" 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    Pop-Location
  }
}
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }

# 3-1. Codex가 이 폴더의 설정(.codex/config.toml)을 쓰도록 신뢰 프로젝트로 등록
$cfg = Join-Path $env:USERPROFILE '.codex\config.toml'
New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
$key = "[projects.'$Dir']"
if (-not ((Test-Path $cfg) -and (Get-Content $cfg -Raw -Encoding UTF8).Contains($key))) {   # -like는 [ ]를 패턴으로 읽어 오판한다
  [IO.File]::AppendAllText($cfg, "`r`n$key`r`ntrust_level = `"trusted`"`r`n", (New-Object Text.UTF8Encoding $false))
}

# 3-2. 문서 작업(PPT·엑셀·PDF)용 Python 준비 — 설치할 때 한 번에 끝낸다. 관리자 권한(UAC) 없이 사용자 범위에만 설치하고, 실패해도 계속한다
#   Codex 런타임 Python에 python-pptx가 있으면 그대로 → 이미 있는 Python에 pip --user → uv → winget 사용자 범위 → python.org 포터블(embeddable) 순. 결과는 memory\env.md
function Ensure-Python {
  $ErrorActionPreference = 'Continue'   # 이 함수 안에서만. 설치 실패로 설치기 전체가 멈추지 않게 한다
  $ProgressPreference = 'SilentlyContinue'
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
  $Pkgs = @('python-pptx', 'openpyxl', 'pypdf', 'Pillow')
  $Check = 'import pptx'
  $Base = Join-Path $env:LOCALAPPDATA 'workmate'
  $Venv = Join-Path $Base 'py'
  $VenvPy = Join-Path $Venv 'Scripts\python.exe'
  $Portable = Join-Path $Base 'python'
  $PortablePy = Join-Path $Portable 'python.exe'
  $Runtime = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
  $env:UV_NATIVE_TLS = '1'   # 회사 SSL 검사 장비가 있어도 Windows 인증서 저장소를 쓰게 한다
  $env:PIP_DISABLE_PIP_VERSION_CHECK = '1'
  $env:PIP_DEFAULT_TIMEOUT = '15'; $env:PIP_RETRIES = '1'   # 막힌 망에서 pip이 몇 분씩 붙잡지 않게

  function Test-Py($py) {   # python-pptx까지 되면 'ok', 실행만 되면 'bare', 실행이 안 되면 ''
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
      Invoke-WebRequest -UseBasicParsing -TimeoutSec 120 'https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip' -OutFile $zip -ErrorAction Stop
      New-Item -ItemType Directory -Force -Path $uvDir | Out-Null
      Expand-Archive $zip $uvDir -Force -ErrorAction Stop
    }
    if (-not (Test-Path $VenvPy)) { & $uv venv $Venv --python 3.12 --seed --quiet 2>&1 | Out-Null }
    & $uv pip install --python $VenvPy --quiet @Pkgs 2>&1 | Out-Null
    return $VenvPy
  }
  function Install-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget 없음' }
    # 사용자 범위만, py 런처(모든 사용자용)는 빼서 UAC 창이 뜨지 않게. 4분 넘게 멈추면 끊는다
    $wa = 'install --id Python.Python.3.12 -e --source winget --scope user --silent --accept-package-agreements --accept-source-agreements --disable-interactivity --override "/quiet InstallAllUsers=0 Include_launcher=0 InstallLauncherAllUsers=0 PrependPath=0 Include_test=0"'
    $wp = Start-Process winget -ArgumentList $wa -WindowStyle Hidden -PassThru
    if (-not $wp.WaitForExit(240000)) { try { $wp.Kill() } catch {}; throw 'winget 4분 초과' }
    $p = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'
    if (-not (Test-Path $p)) { throw 'winget 설치 후 python.exe 없음' }
    & $p -m pip install --user --quiet --no-warn-script-location @Pkgs 2>&1 | Out-Null
    return $p
  }
  function Install-Portable {
    $ver = '3.12.10'
    $zip = Join-Path $env:TEMP "python-$ver-embed-amd64.zip"
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 120 "https://www.python.org/ftp/python/$ver/python-$ver-embed-amd64.zip" -OutFile $zip -ErrorAction Stop
    New-Item -ItemType Directory -Force -Path $Portable | Out-Null
    Expand-Archive $zip $Portable -Force -ErrorAction Stop
    Get-ChildItem $Portable -Filter 'python*._pth' | ForEach-Object {   # embeddable은 site가 꺼져 있어 pip 패키지를 못 읽는다
      (Get-Content $_.FullName) -replace '^#\s*import site', 'import site' | Set-Content $_.FullName -Encoding ASCII
    }
    $gp = Join-Path $env:TEMP 'get-pip-workmate.py'
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 'https://bootstrap.pypa.io/get-pip.py' -OutFile $gp -ErrorAction Stop
    & $PortablePy $gp --quiet --no-warn-script-location 2>&1 | Out-Null
    & $PortablePy -m pip install --quiet --no-warn-script-location @Pkgs 2>&1 | Out-Null
    return $PortablePy
  }

  $result = ''; $how = ''; $tries = @()
  $cands = @(Get-Candidates)
  foreach ($p in $cands) { if ((Test-Py $p) -eq 'ok') { $result = $p; $how = '이미 있음'; break } }
  if (-not $result) {
    foreach ($p in $cands) {
      if ($p -eq $Runtime -or (Test-Py $p) -ne 'bare') { continue }   # Codex 런타임은 앱이 관리하므로 건드리지 않는다
      Say "Python($p)에 문서 작업용 패키지를 넣는 중..."
      & $p -m pip install --user --quiet --no-warn-script-location @Pkgs 2>&1 | Out-Null
      if ((Test-Py $p) -eq 'ok') { $result = $p; $how = 'pip --user'; break } else { $tries += "pip --user($p) 실패" }
    }
  }
  if (-not $result) {
    foreach ($step in @(@('uv', 'Install-Uv'), @('포터블 Python', 'Install-Portable'), @('winget 사용자 범위', 'Install-Winget'))) {
      Say "Python을 사용자 폴더에 설치하는 중($($step[0]), 1~3분)..."
      try {
        $p = & $step[1]
        if ((Test-Py $p) -eq 'ok') { $result = $p; $how = $step[0]; break }
        $tries += "$($step[0]) 실패(패키지 확인 안 됨)"
      } catch { $tries += "$($step[0]) 실패($((("$($_.Exception.Message)") -split "`r?`n")[0]))" }
    }
  }

  $mem = Join-Path $Dir 'memory'
  New-Item -ItemType Directory -Force -Path $mem | Out-Null
  $lines = @('# 실행 환경 (설치 스크립트가 자동 기록)', '', "- 확인 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
  if ($result) {
    $lines += @("- python: $result", "- 방법: $how", "- 패키지: $($Pkgs -join ', ')")
  } else {
    $lines += @('- python: 없음(자동 설치 실패)', "- 시도: $($tries -join ' / ')", '- 대응: PPT는 보고서(문서)로 대신 만든다. 다시 시도하려면 설치 한 줄을 다시 실행한다.')
  }
  [IO.File]::WriteAllText((Join-Path $mem 'env.md'), (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $false))
  if ($result) { Say "Python 준비 완료($how): $result" } else { Say "Python 자동 설치 실패: $($tries -join ' / ')" }
}
Say 'PPT·엑셀 작업용 Python을 확인합니다(없으면 사용자 폴더에 자동 설치, 1~3분)...'
try { Ensure-Python } catch { Say "Python 준비 중 오류: $($_.Exception.Message) (설치는 계속합니다)" }

# 4. 기억 자동 정리 등록: 1시간마다·로그인 때 대화 기록을 옮기고 검색 색인을 만든다(AI 없이, 창 없이)
$sync = Join-Path $Dir '.agents\skills\wrap\scripts\sync.ps1'
$vbs = Join-Path $Dir '.agents\skills\wrap\scripts\sync-hidden.vbs'
Set-Content -LiteralPath $vbs -Encoding Unicode -Value ('CreateObject("WScript.Shell").Run "powershell -NoProfile -ExecutionPolicy Bypass -File ""' + $sync + '"" -Quiet", 0, False')
$tn = 'workmate-sync-' + ([BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($Dir.ToLower()))) -replace '-','').Substring(0,8)
schtasks /Create /F /SC HOURLY /TN $tn /TR "wscript.exe `"$vbs`"" | Out-Null
if ($LASTEXITCODE -eq 0) { Say "기억 자동 정리를 1시간마다 돌도록 등록했습니다($tn)." } else { Say '기억 자동 정리 등록에 실패했습니다. 대화를 시작할 때마다 정리됩니다.' }

# 5. 최근 파일 미리 읽기 — Codex 샌드박스 밖(지금 이 PowerShell)에서 돌려야 문서·다운로드·PDF를 다 읽는다
$scanPs = Join-Path $Dir '.agents\skills\prescan\scripts\scan.ps1'
$rolesDir = Join-Path $Dir '.agents\skills\prescan\sample\pcs'
if (-not $env:WORKMATE_SAMPLE -and -not $env:WORKMATE_SCAN_ROOTS) {
  try { $env:WORKMATE_SCAN_ROOTS = Read-Host '  기본 검색에 더할 업무 폴더 경로(Enter는 기본 검색만)' } catch { $env:WORKMATE_SCAN_ROOTS = '' }
}
Say '최근 파일을 미리 읽는 중입니다(1분 안팎)...'
$scanArgs = @('-Force')
if ($env:WORKMATE_SAMPLE -and (Test-Path (Join-Path $rolesDir $env:WORKMATE_SAMPLE))) {
  $scanArgs += @('-OnlyRoots', '-Roots', (Join-Path $rolesDir $env:WORKMATE_SAMPLE)); Say "선택한 스캔 경로: 예시 자료($($env:WORKMATE_SAMPLE))"
} elseif ($env:WORKMATE_SCAN_ROOTS) {
  if ($env:WORKMATE_SCAN_ONLY -eq '1') { $scanArgs += '-OnlyRoots' }   # "이 폴더만"은 명시할 때만
  $scanArgs += @('-Roots') + ($env:WORKMATE_SCAN_ROOTS -split ';'); Say "선택한 스캔 경로: 기본 검색 + $($env:WORKMATE_SCAN_ROOTS)"
} else { Say '선택한 스캔 경로: 기본 검색(최근 항목·문서·다운로드·동기화 폴더)' }
# 사전 스캔은 4분을 넘기면 끊고 설치를 계속한다(못 읽은 내용은 Codex 온보딩 때 다시 읽는다)
$scanOut = Join-Path $env:TEMP ('workmate-scan-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
$scanArgLine = (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scanPs) + $scanArgs | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
try {
  $sp = Start-Process powershell -ArgumentList $scanArgLine -RedirectStandardOutput $scanOut -WindowStyle Hidden -PassThru
  if (-not $sp.WaitForExit(240000)) { try { $sp.Kill() } catch {}; Say '최근 파일 읽기가 오래 걸려 여기서 멈췄습니다. 나머지는 Codex에서 온보딩할 때 읽습니다.' }
  if (Test-Path $scanOut) { Get-Content $scanOut -Encoding UTF8 | ForEach-Object { Say $_ }; Remove-Item $scanOut -Force -ErrorAction SilentlyContinue }
} catch { Say '최근 파일 읽기를 건너뜁니다. Codex에서 온보딩할 때 읽습니다.' }
powershell -NoProfile -ExecutionPolicy Bypass -File $sync -Quiet
$csvPath = Join-Path $Dir 'memory\scan\recent-files.csv'
$found = if (Test-Path $csvPath) { @(Import-Csv $csvPath -Encoding UTF8).Count } else { 0 }
$textDir = Join-Path $Dir 'memory\scan\text'
$text = if (Test-Path $textDir) { @(Get-ChildItem $textDir -File).Count } else { 0 }
Say "발견 파일 수: ${found}개"
Say "본문 추출 수: ${text}개"

Write-Host "`n설치 완료: $Dir`n"
Say '다음:'
Say '1. Codex 앱에서 이 폴더를 프로젝트로 엽니다.'
Say '2. 대화창에 @onboard를 입력해 보내면 설치된 자료를 확인하고 세팅을 시작합니다.'
Start-Process explorer.exe $Dir
