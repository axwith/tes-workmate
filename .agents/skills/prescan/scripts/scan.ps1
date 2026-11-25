# 최근에 쓴 파일 목록과 본문 일부를 이 워크스페이스 memory/scan/ 에 만든다.
# 설치 없이 Windows PowerShell 5.1에서 돈다. 원본 파일은 읽기만 한다.
# 온라인 전용(Files On-Demand) 파일은 목록에만 남기고 열거나 내려받지 않는다(copy 열이 비고 why에 online-only).
# 사용: powershell -NoProfile -ExecutionPolicy Bypass -File scan.ps1 [-Days 30] [-MaxFiles 300] [-MaxText 60] [-Roots "D:\업무"] [-OnlyRoots] [-Force]
#   -Roots는 기본 검색(최근 항목·Office 최근 문서·문서·바탕 화면·다운로드·동기화 폴더)에 더한다. -OnlyRoots를 함께 주면 그 폴더만 본다.
# 범위 설정 정본: memory\scan\scan-config.json
#   roots·onlyRoots(설치기가 넘긴 폴더), useDiscovered(동기화 폴더 자동 탐색), include(더할 폴더), exclude(뺄 폴더·패턴),
#   maxDepth(하위 폴더 깊이), extensions(확장자), skipOnlineOnly(온라인 전용은 목록만)
# 본 폴더 목록: memory\scan\scan-roots.csv (status: 기본·자동 발견·추가·지정·제외·없음). 사람이 보는 요약은 memory\env.md 끝에 적는다.
param(
  [int]$Days = 30,
  [int]$MaxFiles = 300,
  [int]$MaxText = 80,
  [int]$MaxChars = 4000,
  [string[]]$Roots = @(),
  [switch]$OnlyRoots,  # 지정한 폴더만 본다(최근 항목·문서·다운로드·동기화 폴더 제외). 시험·직무 프로필용
  [switch]$Force,      # 이미 읽어 둔 목록이 있어도 다시 읽는다(설치기·sync만 쓴다)
  [string]$HomeDir = ''  # 시험용: 사용자 폴더(기본 %USERPROFILE%)
)
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$onWindows = ($env:OS -eq 'Windows_NT')
$ws = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$out = Join-Path $ws 'memory\scan'
$textDir = Join-Path $out 'text'
# 이미 읽어 둔 목록이 있으면 다시 읽지 않는다 — Codex 샌드박스 안에서 다시 돌면 덜 읽히고 지정 폴더 설정도 사라진다
if ((Test-Path (Join-Path $out 'recent-files.csv')) -and -not $Force) {
  "이미 읽어 둔 최근 파일 목록이 있습니다(memory\scan\recent-files.csv). 다시 읽지 않습니다. 그 목록과 memory\scan\text를 쓰세요."; exit 0
}
$docExt = '.docx','.xlsx','.pptx','.hwp','.hwpx','.pdf','.txt','.md','.csv','.tsv','.json','.xml','.html','.htm','.doc','.xls','.ppt','.msg','.eml','.log'

# 범위 설정: 처음 지정한 폴더를 기억해 두고, 다음 새로 고침(sync)에도 같은 범위로 읽는다. 없는 키는 기본값으로 채워 다시 쓴다
$cfgPath = Join-Path $out 'scan-config.json'
$cfg = [ordered]@{ roots = @(); onlyRoots = $false; useDiscovered = $true; include = @(); exclude = @(); maxDepth = 6; extensions = $docExt; skipOnlineOnly = $true }
if (Test-Path -LiteralPath $cfgPath) {
  $c = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($c) { foreach ($k in @($cfg.Keys)) { if (($c.PSObject.Properties.Name -contains $k) -and ($null -ne $c.$k)) { $cfg[$k] = $c.$k } } }
}
if ($Roots.Count -gt 0) { $cfg.roots = @($Roots); $cfg.onlyRoots = [bool]$OnlyRoots }
elseif ($cfg.onlyRoots) { $OnlyRoots = [switch]$true }
$cfg.roots = @(@($cfg.roots) | Where-Object { $_ })
$cfg.include = @(@($cfg.include) | Where-Object { $_ })
$cfg.exclude = @(@($cfg.exclude) | Where-Object { $_ })
$cfg.extensions = @(@($cfg.extensions) | Where-Object { $_ } | ForEach-Object { $e = ([string]$_).Trim().ToLower(); if (-not $e.StartsWith('.')) { $e = '.' + $e }; $e })
if ($cfg.extensions.Count -eq 0) { $cfg.extensions = $docExt }
$cfg.maxDepth = [int]$cfg.maxDepth; if ($cfg.maxDepth -lt 0) { $cfg.maxDepth = 6 }
$cfg.onlyRoots = [bool]$cfg.onlyRoots; $cfg.useDiscovered = [bool]$cfg.useDiscovered; $cfg.skipOnlineOnly = [bool]$cfg.skipOnlineOnly
New-Item -ItemType Directory -Force -Path $out | Out-Null
[IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
$Roots = @($cfg.roots); $exts = @($cfg.extensions); $maxDepth = $cfg.maxDepth

if (Test-Path $textDir) { Remove-Item (Join-Path $textDir '*') -Force -ErrorAction SilentlyContinue }   # 이전 스캔 본문이 섞이지 않게
New-Item -ItemType Directory -Force -Path $textDir | Out-Null
$since = (Get-Date).AddDays(-$Days)
if (-not $HomeDir) { $HomeDir = $env:USERPROFILE }

$skipDirs = '\AppData\','\node_modules\','\.git\','\$Recycle.Bin\','\Windows\','\Program Files'
$sampleDir = Join-Path $ws '.agents\skills\prescan\sample'
function Norm([string]$p) { return $p.Replace('/', '\').TrimEnd('\') }   # 비교용 경로(구분자 통일)
function Under([string]$a, [string]$b) { $a = $a.ToLower(); $b = $b.ToLower(); return ($a -eq $b -or $a.StartsWith($b + '\')) }
function Skip($p) { $q = Norm $p; foreach ($d in $skipDirs) { if (($q + '\') -like "*$d*") { return $true } }; return ($p.StartsWith($ws) -and -not $p.StartsWith($sampleDir)) }   # 워크스페이스 자신은 빼되 예시 자료는 읽는다
function Expand-Root([string]$p) {
  $p = $p.Trim().Trim('"')
  if (-not $p) { return '' }
  $p = [regex]::Replace($p, '(?i)%USERPROFILE%', [Text.RegularExpressions.MatchEvaluator]{ param($m) $HomeDir })
  if ($p -eq '~' -or $p.StartsWith('~\') -or $p.StartsWith('~/')) { $p = $HomeDir + $p.Substring(1) }
  $p = [Environment]::ExpandEnvironmentVariables($p)
  if (-not $onWindows) { $p = $p.Replace('\', '/') }   # 맥에서 Windows 구조 흉내(fixture) 시험용
  return $p
}
# exclude: 와일드카드(* ?)가 있으면 -like 패턴, 없으면 그 폴더와 아래 전체. 단 더 깊은 기본·추가 폴더(예: OneDrive 안 문서)는 살린다
$excl = @(foreach ($e in $cfg.exclude) { $x = Expand-Root ([string]$e); if ($x) { $n = Norm $x; [pscustomobject]@{ pat = $n; wild = ($n -match '[\*\?]') } } })
function Test-Excluded([string]$p, [string]$rootKey) {
  $q = Norm $p
  foreach ($e in $excl) {
    if ($e.wild) { if ($q -like $e.pat -or $q -like ($e.pat + '\*')) { return $true } }
    elseif ((Under $q $e.pat) -and (-not $rootKey -or (Under $e.pat $rootKey))) { return $true }
  }
  return $false
}

# ---- 볼 폴더 정하기 ----
$rootList = New-Object System.Collections.ArrayList
function Add-Root([string]$path, [string]$kind, [string]$status, [string]$source, [bool]$cloud = $false) {
  if (-not $path) { return }
  if (-not (Test-Path -LiteralPath $path -PathType Container)) {
    if ($status -ne '자동 발견') { [void]$rootList.Add([pscustomobject]@{ path = $path; key = (Norm $path).ToLower(); kind = $kind; status = '없음'; source = $source; cloud = $false; files = 0; online = 0 }) }
    return
  }
  $full = (Get-Item -LiteralPath $path -Force).FullName.TrimEnd('\', '/')
  $key = (Norm $full).ToLower()
  $auto = ($status -eq '자동 발견')
  foreach ($r in $rootList) {
    if ($r.status -eq '없음') { continue }
    if ($r.key -eq $key) { return }                                    # 이미 넣은 폴더
    if ($auto -and $r.status -eq '자동 발견' -and (Under $key $r.key)) { return }   # 이미 찾은 동기화 폴더 안
  }
  if ($auto) {   # 새로 찾은 동기화 폴더가 앞서 찾은 하위 폴더를 품으면 하위 폴더는 뺀다
    for ($i = $rootList.Count - 1; $i -ge 0; $i--) { $r = $rootList[$i]; if ($r.status -eq '자동 발견' -and (Under $r.key $key)) { $rootList.RemoveAt($i) } }
  }
  $rk = if ($auto) { '' } else { $key }
  if (Test-Excluded $full $rk) { $status = '제외' }
  [void]$rootList.Add([pscustomobject]@{ path = $full; key = $key; kind = $kind; status = $status; source = $source; cloud = $cloud; files = 0; online = 0 })
}

if ($OnlyRoots) {
  foreach ($r in $Roots) { Add-Root (Expand-Root $r) 'roots' '지정' 'roots' }
} else {
  # 1) 기본: 문서·바탕 화면·다운로드
  if ($PSBoundParameters.ContainsKey('HomeDir')) { $docs = Join-Path $HomeDir 'Documents'; $desk = Join-Path $HomeDir 'Desktop' }
  else { $docs = [Environment]::GetFolderPath('MyDocuments'); $desk = [Environment]::GetFolderPath('Desktop') }
  Add-Root $docs 'documents' '기본' 'known-folder'
  Add-Root $desk 'desktop' '기본' 'known-folder'
  Add-Root (Join-Path $HomeDir 'Downloads') 'downloads' '기본' 'known-folder'
  # 2) 자동 발견: 이미 이 PC에 동기화된 클라우드·회사 폴더(새로 연결하거나 내려받지 않는다)
  if ($cfg.useDiscovered) {
    # 2-1) %USERPROFILE%\OneDrive* (개인·회사 OneDrive, '바로 가기 추가' 포함)
    Get-ChildItem -LiteralPath $HomeDir -Directory -Filter 'OneDrive*' | ForEach-Object { Add-Root $_.FullName 'onedrive' '자동 발견' 'home:OneDrive*' }
    # 2-2) OneDrive 계정 레지스트리: UserFolder(OneDrive 폴더 위치)
    $acc = 'HKCU:\Software\Microsoft\OneDrive\Accounts'
    if ($onWindows -and (Test-Path $acc)) {
      Get-ChildItem $acc | ForEach-Object { $uf = (Get-ItemProperty $_.PSPath).UserFolder; if ($uf) { Add-Root $uf 'onedrive' '자동 발견' ('registry:Accounts\' + $_.PSChildName + '\UserFolder') } }
    }
    # 2-3) SharePoint '동기화' 버튼: %USERPROFILE%\<조직명>\<사이트> - <라이브러리>
    $std = @('Documents','Desktop','Downloads','Pictures','Music','Videos','Favorites','Links','Contacts','Searches','Saved Games','AppData','3D Objects','Public')
    Get-ChildItem -LiteralPath $HomeDir -Directory | Where-Object { $std -notcontains $_.Name -and $_.Name -notlike 'OneDrive*' -and $_.Name -notlike '.*' } | ForEach-Object {
      $libs = @(Get-ChildItem -LiteralPath $_.FullName -Directory | Where-Object { $_.Name -match '^.+ - .+$' })
      if ($libs.Count -gt 0) { Add-Root $_.FullName 'sharepoint' '자동 발견' ('home:<조직>\<사이트> - <라이브러리> x' + $libs.Count) }
      elseif ($_.Name -eq 'My Drive' -or $_.Name -eq '내 드라이브') { Add-Root $_.FullName 'googledrive' '자동 발견' 'home:My Drive(미러링)' }
    }
    if ($onWindows) {
      # 2-4) 레지스트리 Tenants\<조직> 값 이름 = 동기화 폴더 경로, SyncEngines MountPoint = 라이브러리별 동기화 위치
      if (Test-Path $acc) { Get-ChildItem $acc | ForEach-Object {
        $ten = Join-Path $_.PSPath 'Tenants'
        if (Test-Path $ten) { Get-ChildItem $ten | ForEach-Object {
          $tn = $_.PSChildName
          foreach ($pn in (Get-ItemProperty $_.PSPath).PSObject.Properties.Name) { if ($pn -match '^[A-Za-z]:\\') { Add-Root $pn 'sharepoint' '자동 발견' ('registry:Tenants\' + $tn) } }
        } }
      } }
      $se = 'HKCU:\Software\SyncEngines\Providers\OneDrive'
      if (Test-Path $se) { Get-ChildItem $se | ForEach-Object { $mp = (Get-ItemProperty $_.PSPath).MountPoint; if ($mp) { Add-Root $mp 'sharepoint' '자동 발견' 'registry:SyncEngines\MountPoint' } } }
      # 2-5) 구글 드라이브 데스크톱(가상 드라이브). 스트리밍이라 파일을 열면 내려받으므로 목록만 남긴다
      Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        foreach ($n in @('My Drive', '내 드라이브')) { $p = Join-Path $_.Root $n; if (Test-Path -LiteralPath $p) { Add-Root $p 'googledrive' '자동 발견' ('drive:' + $_.Name) $true } }
      }
    }
  }
  # 3) 추가: 설치 때 넣은 업무 폴더(roots)와 설정의 include — 기본 검색에 더한다
  foreach ($r in $Roots) { Add-Root (Expand-Root $r) 'roots' '추가' 'roots' }
  foreach ($r in $cfg.include) { Add-Root (Expand-Root $r) 'include' '추가' 'scan-config.include' }
}
$active = @($rootList | Where-Object { $_.status -ne '없음' -and $_.status -ne '제외' })
$rootKeys = @{}; foreach ($r in $active) { $rootKeys[$r.key] = $true }
function Find-Root([string]$p) {   # 이 경로를 품는 가장 깊은 폴더
  $q = (Norm $p).ToLower(); $best = $null
  foreach ($r in $rootList) { if ($r.status -ne '없음' -and (Under $q $r.key) -and (-not $best -or $r.key.Length -gt $best.key.Length)) { $best = $r } }
  return $best
}

$found = @{}
$ONLINE_BITS = 0x1000 -bor 0x40000 -bor 0x400000   # OFFLINE, RECALL_ON_OPEN, RECALL_ON_DATA_ACCESS
function Add($f, $why, $root) {
  if (-not $f -or -not (Test-Path -LiteralPath $f.FullName -PathType Leaf)) { return }
  if ($exts -notcontains $f.Extension.ToLower()) { return }
  if ($f.Name -match '^[~%]\$' -or $f.Length -lt 10) { return }   # Office 임시·빈 파일
  if ($f.Length -gt 50MB -or (Skip $f.FullName)) { return }
  if (-not $root) { $root = Find-Root $f.FullName }
  if ($root -and $root.status -eq '제외') { return }
  $rk = if ($root -and $root.status -ne '자동 발견') { $root.key } else { '' }
  if (Test-Excluded $f.FullName $rk) { return }
  $k = $f.FullName.ToLower()
  if ($found.ContainsKey($k)) { if ($found[$k].why -notlike "*$why*") { $found[$k].why += ",$why" }; return }
  $online = $cfg.skipOnlineOnly -and ((([int64]$f.Attributes) -band $ONLINE_BITS) -ne 0 -or ($root -and $root.cloud))
  $found[$k] = [pscustomobject]@{ path=$f.FullName; name=$f.Name; ext=$f.Extension.ToLower(); kb=[math]::Round($f.Length/1KB);
    modified=$f.LastWriteTime.ToString('yyyy-MM-dd'); created=$f.CreationTime.ToString('yyyy-MM-dd'); why=$why; last=$f.LastWriteTime; online=$online }
}

# 1) 열어 본 파일: Windows 최근 항목 바로가기, Office 최근 문서(로컬 경로만 — SharePoint URL은 쓰지 않는다)
if ($onWindows -and -not $OnlyRoots) {
  $recent = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
  $sh = New-Object -ComObject WScript.Shell
  Get-ChildItem -LiteralPath $recent -Filter *.lnk | Where-Object { $_.LastWriteTime -ge $since } | ForEach-Object {
    $t = $sh.CreateShortcut($_.FullName).TargetPath
    if ($t) { Add (Get-Item -LiteralPath $t) 'opened' $null }
  }
  Get-ChildItem 'HKCU:\Software\Microsoft\Office' | Where-Object { $_.PSChildName -match '^\d+\.\d+$' } | ForEach-Object {
    $ver = $_.PSPath
    foreach ($app in @('Word', 'Excel', 'PowerPoint')) {
      $keys = @(Join-Path $ver "$app\File MRU")
      $um = Join-Path $ver "$app\User MRU"
      if (Test-Path $um) { $keys += @(Get-ChildItem $um | ForEach-Object { Join-Path $_.PSPath 'File MRU' }) }
      foreach ($k in $keys) {
        $props = Get-ItemProperty -Path $k
        if (-not $props) { continue }
        foreach ($pp in $props.PSObject.Properties) {
          if ($pp.Name -notlike 'Item *' -or [string]$pp.Value -notmatch '\[T([0-9A-Fa-f]{16})\].*?\*([A-Za-z]:\\.+)$') { continue }
          $mp = $matches[2]
          try { $t = [DateTime]::FromFileTime([Convert]::ToInt64($matches[1], 16)) } catch { continue }
          if ($t -ge $since) { Add (Get-Item -LiteralPath $mp) 'opened' $null }
        }
      }
    }
  }
}
# 2) 수정한 파일, 3) 새로 받은 파일 — 폴더마다 깊이 maxDepth까지. 다른 볼 폴더·제외 폴더·워크스페이스는 들어가지 않는다
# 폴더 하나가 오래 걸리면(클라우드 가상 드라이브 등) 그 폴더만 멈추고 다음으로 간다. 전체도 2분을 넘기지 않는다
$scanAll = [Diagnostics.Stopwatch]::StartNew()
foreach ($r in $active) {
  if ($scanAll.Elapsed.TotalSeconds -ge 120) { $r.source += ' (시간 상한으로 건너뜀)'; continue }
  $rootLimit = if ($r.kind -in @('googledrive', 'onedrive', 'sharepoint')) { 30 } else { 45 }
  $rootSw = [Diagnostics.Stopwatch]::StartNew()
  $isDl = $r.path -like '*Downloads*'
  $rk = if ($r.status -ne '자동 발견') { $r.key } else { '' }
  $stack = New-Object System.Collections.Stack
  $stack.Push(@($r.path, 0))
  while ($stack.Count -gt 0) {
    if ($rootSw.Elapsed.TotalSeconds -ge $rootLimit -or $scanAll.Elapsed.TotalSeconds -ge 120) { $r.source += ' (시간 상한으로 일부만)'; break }
    $cur = $stack.Pop()
    foreach ($it in @(Get-ChildItem -LiteralPath $cur[0])) {
      if ($it.PSIsContainer) {
        if ($cur[1] -ge $maxDepth) { continue }
        if ($rootKeys.ContainsKey((Norm $it.FullName).ToLower())) { continue }
        if ((Skip ($it.FullName + '\')) -or (Test-Excluded $it.FullName $rk)) { continue }
        $stack.Push(@($it.FullName, ($cur[1] + 1)))
      }
      elseif ($it.LastWriteTime -ge $since) { Add $it 'modified' $r }
      elseif ($it.CreationTime -ge $since -and $isDl) { Add $it 'downloaded' $r }
    }
  }
}

$list = $found.Values | Sort-Object last -Descending | Select-Object -First $MaxFiles
# 원본 사본을 워크스페이스 안(memory\scan\files)에 둔다 — Codex 샌드박스 안에서도 읽을 수 있게. 온라인 전용은 내려받지 않고 목록만
$filesDir = Join-Path $out 'files'
if (Test-Path $filesDir) { Remove-Item (Join-Path $filesDir '*') -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $filesDir | Out-Null
$i = 0; $onlineN = 0
foreach ($f in $list) {
  $copyName = ('{0:D3}_{1}' -f $i, $f.name); $i++
  if ($f.online) { $onlineN++; $f.why += ',online-only'; $f | Add-Member -NotePropertyName copy -NotePropertyValue '' -Force; continue }
  Copy-Item -LiteralPath $f.path -Destination (Join-Path $filesDir $copyName) -ErrorAction SilentlyContinue
  $f | Add-Member -NotePropertyName copy -NotePropertyValue ("memory\scan\files\" + $copyName) -Force
}
$list | Select-Object path,copy,name,ext,kb,modified,created,why | Export-Csv -LiteralPath (Join-Path $out 'recent-files.csv') -NoTypeInformation -Encoding UTF8
# 본 폴더 목록: 온보딩에서 '자동 발견' 폴더를 보여 주고 사용자가 뺄 수 있게(빼면 scan-config.json exclude에 경로를 넣는다)
foreach ($f in $list) { $r = Find-Root $f.path; if ($r) { $r.files++; if ($f.online) { $r.online++ } } }
$rootList | Select-Object path,kind,status,source,files,online | Export-Csv -LiteralPath (Join-Path $out 'scan-roots.csv') -NoTypeInformation -Encoding UTF8

# Codex 앱에 함께 깔리는 Python(pypdf 포함)이 있으면 PDF 본문도 뽑는다
$rt = (Get-AppxPackage 'OpenAI.CodexPrimaryRuntime*' -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1).InstallLocation
$py = if ($rt) { Join-Path $rt 'dependencies\python\python.exe' }
if (-not ($py -and (Test-Path $py))) { $c = Get-Command python -ErrorAction SilentlyContinue; $py = if ($c) { $c.Source } }
$pdfPy = Join-Path $PSScriptRoot 'pdftext.py'
$tmpTxt = Join-Path $env:TEMP 'workmate-pdftext.txt'

# 본문 일부 추출 (설치 없이 되는 형식만)
Add-Type -AssemblyName System.IO.Compression.FileSystem
function ZipText($p, $pattern) {
  $z = [IO.Compression.ZipFile]::OpenRead($p); $sb = New-Object Text.StringBuilder
  try { foreach ($e in ($z.Entries | Where-Object { $_.FullName -match $pattern } | Sort-Object FullName)) {
      $rd = New-Object IO.StreamReader($e.Open()); $x = $rd.ReadToEnd(); $rd.Close()
      $x = $x -replace '</w:p>|</a:p>|</row>', "`n" -replace '<[^>]+>', ' ' -replace '[ \t]+', ' '; $x = [Net.WebUtility]::HtmlDecode($x)
      [void]$sb.AppendLine($x); if ($sb.Length -gt $MaxChars) { break } } } finally { $z.Dispose() }
  return $sb.ToString()
}
$n = 0; $skipped = 0
$textLimit = if ($OnlyRoots) { $null } else { $MaxText }
foreach ($f in $list) {
  if ($null -ne $textLimit -and $n -ge $textLimit) { break }
  if ($f.online) { continue }   # 온라인 전용은 열지 않는다(열면 내려받는다)
  $t = $null
  switch ($f.ext) {
    '.docx' { $t = ZipText $f.path '^word/document\.xml$' }
    '.pptx' { $t = ZipText $f.path '^ppt/slides/slide\d+\.xml$' }
    '.xlsx' { $t = ZipText $f.path '^xl/(sharedStrings|worksheets/sheet\d+)\.xml$' }
    '.hwpx' { $t = ZipText $f.path '^Contents/section\d+\.xml$' }
    '.pdf'  { if ($py) { & $py $pdfPy $f.path $tmpTxt $MaxChars 2>$null; $t = Get-Content -LiteralPath $tmpTxt -Raw -Encoding UTF8 } else { $skipped++ } }
    { $_ -in '.txt','.md','.csv','.tsv','.json','.xml','.html','.htm','.log' } { $t = Get-Content -LiteralPath $f.path -TotalCount 200 -Encoding UTF8 | Out-String }
    default { $skipped++ }
  }
  if ($t) {
    $t = $t.Trim(); if ($t.Length -gt $MaxChars) { $t = $t.Substring(0, $MaxChars) }
    $safe = ($f.name -replace '[^\w\.\-가-힣]', '_')
    "# $($f.path)`n# 수정 $($f.modified) / 근거 $($f.why)`n`n$t" | Set-Content -LiteralPath (Join-Path $out "text\$('{0:D3}' -f $n)_$safe.txt") -Encoding UTF8
    $n++
  }
}

# 사람이 보는 범위 요약: memory\env.md 끝의 '## 사전 스캔 범위' 절만 바꾼다(다른 내용은 그대로)
$envPath = Join-Path $ws 'memory\env.md'
$yn = @{ $true = '예'; $false = '아니오' }
$sec = @('## 사전 스캔 범위 (scan이 자동 기록 — 바꾸려면 memory/scan/scan-config.json, 폴더별 결과는 memory/scan/scan-roots.csv)', '',
  "- 확인 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm') / 최근 ${Days}일, 깊이 $maxDepth, 지정 폴더만 보기: $($yn[[bool]$OnlyRoots]), 온라인 전용은 목록만: $($yn[$cfg.skipOnlineOnly])")
foreach ($r in $rootList) { $sec += ('- [{0}] {1} — {2}개' -f $r.status, $r.path, $r.files) }
$envText = if (Test-Path -LiteralPath $envPath) { [IO.File]::ReadAllText($envPath) } else { '' }
$nl = if ($envText -match "`r`n") { "`r`n" } else { "`n" }
$cut = $envText.IndexOf('## 사전 스캔 범위')
if ($cut -ge 0) { $envText = $envText.Substring(0, $cut) }
$envText = $envText.TrimEnd() ; if ($envText) { $envText += $nl + $nl }
[IO.File]::WriteAllText($envPath, $envText + ($sec -join $nl) + $nl, (New-Object Text.UTF8Encoding $false))

$byWhy = $list | Group-Object { ($_.why -split ',')[0] } | ForEach-Object { "$($_.Name) $($_.Count)" }
$pdfNote = if ($py) { "PDF 읽기 가능" } else { "PDF 읽기 도구 없음" }
$autoN = @($rootList | Where-Object { $_.status -eq '자동 발견' }).Count
$exclN = @($rootList | Where-Object { $_.status -eq '제외' }).Count
if ($autoN -gt 0 -or $exclN -gt 0 -or $onlineN -gt 0) { "본 폴더 $($active.Count)개(자동 발견 ${autoN}개, 제외 ${exclN}개), 온라인 전용 ${onlineN}개는 내려받지 않고 목록만 → memory\scan\scan-roots.csv" }
"찾은 파일 $($list.Count)개 ($($byWhy -join ', ')), 본문 추출 ${n}개, 본문 미지원 형식 ${skipped}개, ${pdfNote} → memory\scan\"
