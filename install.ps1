# workmate (Codex) 설치기 — Windows PowerShell 5.1 이상
#   irm https://raw.githubusercontent.com/axwith/tes-workmate/main/get.ps1 | iex   (get.ps1이 이 파일을 받아 -File로 실행한다. 이 파일을 iex로 직접 돌리면 BOM 때문에 깨진다)
#   또는 받은 폴더에서: powershell -ExecutionPolicy Bypass -File install.ps1
# 옵션(환경변수): WORKMATE_DIR=설치 위치(기본 문서\workmate), WORKMATE_FROM=로컬 원본 폴더, WORKMATE_SCAN_ROOTS=스캔할 폴더(;로 구분, 지정하면 그 폴더만)
# git이 없으면 묻지 않고 설치한다(MinGit을 사용자 폴더에, 관리자 권한 불필요. 실패하면 winget).
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Repo = 'axwith/tes-workmate'
$Dir = if ($env:WORKMATE_DIR) { $env:WORKMATE_DIR } else { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'tes-workmate' }
function Say($m) { Write-Host "  $m" }

Write-Host "`nworkmate 설치를 시작합니다 → $Dir`n"

# 1. git 확인 — 없으면 묻지 않고 설치한다(변경 기록·되돌리기에 필요)
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
  Say 'git이 없어 설치합니다(관리자 권한 없이, 1분 안팎).'
  $gitHome = "$env:LOCALAPPDATA\Programs\Git"
  try {
    # MinGit(압축 파일)을 사용자 폴더에 푼다 — 설치 프로그램과 달리 관리자 권한 창(UAC)이 뜨지 않는다
    $rel = Invoke-RestMethod -UseBasicParsing 'https://api.github.com/repos/git-for-windows/git/releases/latest'
    $asset = $rel.assets | Where-Object { $_.name -match '^MinGit-[\d\.]+-64-bit\.zip$' } | Select-Object -First 1
    $gz = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest -UseBasicParsing $asset.browser_download_url -OutFile $gz
    Expand-Archive $gz $gitHome -Force
    # 작업 스케줄러(sync)와 Codex 앱도 git을 찾도록 사용자 PATH에 영구 등록
    $up = [Environment]::GetEnvironmentVariable('Path','User')
    if (-not (($up -split ';') -contains "$gitHome\cmd")) { [Environment]::SetEnvironmentVariable('Path', ((@($up, "$gitHome\cmd") | Where-Object { $_ }) -join ';'), 'User') }
  } catch {
    Say "git 내려받기 실패: $($_.Exception.Message)"
    $wg = Get-Command winget -ErrorAction SilentlyContinue
    if ($wg) { try { winget install --id Git.Git -e --source winget --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null } catch {} }
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
$skills = 'prescan','onboard','collect','inbox-sort','wrap','make-skill','recall','dashboard','thickness-map'
if (Test-Path (Join-Path $Dir 'AGENTS.md')) {
  Say '이미 설치돼 있습니다. 기본 스킬만 새 버전으로 바꾸고, 기억·규칙·업무 폴더는 그대로 둡니다.'
  foreach ($s in $skills) {
    $to = Join-Path $Dir ".agents\skills\$s"
    if (Test-Path $to) { Remove-Item $to -Recurse -Force }
    Copy-Item (Join-Path $src ".agents\skills\$s") $to -Recurse -Force
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

# 4. 기억 자동 정리 등록: 1시간마다·로그인 때 대화 기록을 옮기고 검색 색인을 만든다(AI 없이, 창 없이)
$sync = Join-Path $Dir '.agents\skills\recall\scripts\sync.ps1'
$vbs = Join-Path $Dir '.agents\skills\recall\scripts\sync-hidden.vbs'
Set-Content -LiteralPath $vbs -Encoding Unicode -Value ('CreateObject("WScript.Shell").Run "powershell -NoProfile -ExecutionPolicy Bypass -File ""' + $sync + '"" -Quiet", 0, False')
$tn = 'workmate-sync-' + ([BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($Dir.ToLower()))) -replace '-','').Substring(0,8)
schtasks /Create /F /SC HOURLY /TN $tn /TR "wscript.exe `"$vbs`"" | Out-Null
if ($LASTEXITCODE -eq 0) { Say "기억 자동 정리를 1시간마다 돌도록 등록했습니다($tn)." } else { Say '기억 자동 정리 등록에 실패했습니다. 대화를 시작할 때마다 정리됩니다.' }

# 5. 최근 파일 미리 읽기 — Codex 샌드박스 밖(지금 이 PowerShell)에서 돌려야 문서·다운로드·PDF를 다 읽는다
Say '최근 파일을 미리 읽는 중입니다(1분 안팎)...'
$scanPs = Join-Path $Dir '.agents\skills\prescan\scripts\scan.ps1'
$rolesDir = Join-Path $Dir '.agents\skills\prescan\sample\pcs'
$roles = [ordered]@{ '1' = @('research', '연구소'); '2' = @('cs', 'CS'); '3' = @('mfg', '제조'); '4' = @('qa', '품질'); '5' = @('support', '지원') }
function ScanSample($r) { Say "예시 자료($r)로 세팅합니다."; powershell -NoProfile -ExecutionPolicy Bypass -File $scanPs -Force -OnlyRoots -Roots (Join-Path $rolesDir $r) | ForEach-Object { Say $_ } }
if ($env:WORKMATE_SAMPLE -and (Test-Path (Join-Path $rolesDir $env:WORKMATE_SAMPLE))) {
  ScanSample $env:WORKMATE_SAMPLE   # 강사 시연·시험용: 내 PC 파일 대신 예시 직무 자료로
} else {
  $scanArgs = @('-Force')
  if ($env:WORKMATE_SCAN_ROOTS) { $scanArgs += @('-OnlyRoots', '-Roots') + ($env:WORKMATE_SCAN_ROOTS -split ';') }   # 시험·직무 프로필용: 지정 폴더만
  powershell -NoProfile -ExecutionPolicy Bypass -File $scanPs @scanArgs | ForEach-Object { Say $_ }
  # 최근 업무 파일이 거의 없으면(새 PC 등) 가까운 직무의 예시 자료로 세팅한다
  $csvPath = Join-Path $Dir 'memory\scan\recent-files.csv'
  $cnt = if (Test-Path $csvPath) { @(Import-Csv $csvPath -Encoding UTF8).Count } else { 0 }
  if ($cnt -lt 5 -and (Test-Path $rolesDir)) {
    Say '최근 업무 파일이 거의 없어 예시 자료로 세팅합니다. 가장 가까운 직무 번호를 고르세요.'
    foreach ($k in $roles.Keys) { Say "  $k. $($roles[$k][1])" }
    $a = try { Read-Host '  번호(1~5, 그냥 Enter는 4)' } catch { '' }
    if (-not $roles.Contains("$a")) { $a = '4' }
    ScanSample $roles["$a"][0]
  }
}
powershell -NoProfile -ExecutionPolicy Bypass -File $sync -Quiet   # 첫 색인 — 스캔 뒤에 돌려야 PC 전체를 한 번 더 읽지 않는다

# 6. 1차 세팅까지 설치기가 끝낸다 — 사용자가 처음 열 때 이미 자기 업무에 맞춰져 있게
$codexExe = $null
$pkg = Get-AppxPackage 'OpenAI.Codex' -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
if ($pkg) { $c = Join-Path $pkg.InstallLocation 'app\resources\codex.exe'; if (Test-Path $c) { $codexExe = $c } }
if (-not $codexExe) { $c = Get-Command codex -ErrorAction SilentlyContinue; if ($c) { $codexExe = $c.Source } }
$authOk = Test-Path (Join-Path $env:USERPROFILE '.codex\auth.json')
$stateFile = Join-Path $Dir 'memory\state.md'
function SetupDone { (Test-Path $stateFile) -and ((Get-Content $stateFile -Raw -Encoding UTF8) -match 'prescan: 완료') }
if ($codexExe -and $authOk -and -not (SetupDone)) {
  Say '내 업무에 맞춰 세팅하는 중입니다(2~3분)...'
  Push-Location $Dir
  # PowerShell 5.1은 codex가 stderr에 쓰는 안내를 오류로 바꿔 멈추므로 Start-Process로 분리해 돌린다
  $empty = Join-Path $env:TEMP ('workmate-empty-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.txt'); Set-Content -LiteralPath $empty -Value '' -Encoding ASCII
  Start-Process -FilePath $codexExe -ArgumentList @('exec', '--skip-git-repo-check', '-s', 'workspace-write', '-C', "`"$Dir`"", '"처음 세팅해 줘. PRESCAN.md 절차만 끝까지 하고, 첫 응답(first-reply)은 보내지 말고 세팅 완료라고만 답해."') `
    -WorkingDirectory $Dir -RedirectStandardInput $empty -RedirectStandardOutput (Join-Path $Dir 'memory\setup.log') -RedirectStandardError (Join-Path $Dir 'memory\setup.err.log') -NoNewWindow -Wait
  Pop-Location
  powershell -NoProfile -ExecutionPolicy Bypass -File $sync -Quiet
  # 첫 응답(first-reply)은 사용자가 처음 말을 걸 때 나가야 하므로 상태를 '미실행'으로 되돌려 둔다
  if (Test-Path $stateFile) { $st = Get-Content $stateFile -Raw -Encoding UTF8; [IO.File]::WriteAllText($stateFile, ($st -replace 'onboard:\s*\S+', 'onboard: 미실행'), (New-Object Text.UTF8Encoding $false)) }
  if (SetupDone) { Say '세팅 완료.' } else { Say '세팅을 끝내지 못했습니다. Codex에서 폴더를 열고 아무 말이나 보내면 이어서 합니다.' }
} elseif (-not $authOk) { Say 'Codex 앱에 로그인돼 있지 않아 세팅은 처음 대화 때 진행합니다.' }

Write-Host "`n설치 완료: $Dir`n"
Say '다음:'
Say '1. Codex 앱에서 이 폴더를 프로젝트로 엽니다.'
Say '2. "안녕하세요"라고 보내 보세요.'
Start-Process explorer.exe $Dir
