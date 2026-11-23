# 최근에 쓴 파일 목록과 본문 일부를 이 워크스페이스 memory/scan/ 에 만든다.
# 설치 없이 Windows PowerShell 5.1에서 돈다. 원본 파일은 읽기만 한다.
# 사용: powershell -NoProfile -ExecutionPolicy Bypass -File scan.ps1 [-Days 30] [-MaxFiles 300] [-MaxText 60] [-Roots "D:\업무"]
param(
  [int]$Days = 30,
  [int]$MaxFiles = 300,
  [int]$MaxText = 80,
  [int]$MaxChars = 4000,
  [string[]]$Roots = @(),
  [switch]$OnlyRoots,  # 지정한 폴더만 본다(최근 항목·문서·다운로드 제외). 시험·직무 프로필용
  [switch]$Force       # 이미 읽어 둔 목록이 있어도 다시 읽는다(설치기·sync만 쓴다)
)
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ws = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$out = Join-Path $ws 'memory\scan'
$textDir = Join-Path $out 'text'
# 이미 읽어 둔 목록이 있으면 다시 읽지 않는다 — Codex 샌드박스 안에서 다시 돌면 덜 읽히고 지정 폴더 설정도 사라진다
if ((Test-Path (Join-Path $out 'recent-files.csv')) -and -not $Force) {
  "이미 읽어 둔 최근 파일 목록이 있습니다(memory\scan\recent-files.csv). 다시 읽지 않습니다. 그 목록과 memory\scan\text를 쓰세요."; exit 0
}
# 처음 지정한 폴더 설정을 기억해 두고, 다음 새로 고침(sync)에도 같은 범위로 읽는다
$cfgPath = Join-Path $out 'scan-config.json'
if ($Roots.Count -gt 0) { New-Item -ItemType Directory -Force -Path $out | Out-Null; [IO.File]::WriteAllText($cfgPath, (@{ roots = $Roots; onlyRoots = [bool]$OnlyRoots } | ConvertTo-Json), (New-Object Text.UTF8Encoding $false)) }
elseif (Test-Path $cfgPath) { $c = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json; $Roots = @($c.roots); if ($c.onlyRoots) { $OnlyRoots = [switch]$true } }
if (Test-Path $textDir) { Remove-Item (Join-Path $textDir '*') -Force -ErrorAction SilentlyContinue }   # 이전 스캔 본문이 섞이지 않게
New-Item -ItemType Directory -Force -Path $textDir | Out-Null
$since = (Get-Date).AddDays(-$Days)

$docExt = '.docx','.xlsx','.pptx','.hwp','.hwpx','.pdf','.txt','.md','.csv','.tsv','.json','.xml','.html','.htm','.doc','.xls','.ppt','.msg','.eml','.log'
$skipDirs = '\AppData\','\node_modules\','\.git\','\$Recycle.Bin\','\Windows\','\Program Files'
$sampleDir = Join-Path $ws '.agents\skills\prescan\sample'
function Skip($p) { foreach ($d in $skipDirs) { if ($p -like "*$d*") { return $true } }; return ($p.StartsWith($ws) -and -not $p.StartsWith($sampleDir)) }   # 워크스페이스 자신은 빼되 예시 자료는 읽는다

$found = @{}
function Add($f, $why) {
  if (-not $f -or -not (Test-Path -LiteralPath $f.FullName -PathType Leaf)) { return }
  if ($docExt -notcontains $f.Extension.ToLower()) { return }
  if ($f.Name -match '^[~%]\$' -or $f.Length -lt 10) { return }   # Office 임시·빈 파일
  if ($f.Length -gt 50MB -or (Skip $f.FullName)) { return }
  $k = $f.FullName.ToLower()
  if ($found.ContainsKey($k)) { if ($found[$k].why -notlike "*$why*") { $found[$k].why += ",$why" }; return }
  $found[$k] = [pscustomobject]@{ path=$f.FullName; name=$f.Name; ext=$f.Extension.ToLower(); kb=[math]::Round($f.Length/1KB);
    modified=$f.LastWriteTime.ToString('yyyy-MM-dd'); created=$f.CreationTime.ToString('yyyy-MM-dd'); why=$why; last=$f.LastWriteTime }
}

# 1) 열어 본 파일: Windows 최근 항목 바로가기
$recent = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
$sh = New-Object -ComObject WScript.Shell
if (-not $OnlyRoots) { Get-ChildItem -LiteralPath $recent -Filter *.lnk | Where-Object { $_.LastWriteTime -ge $since } | ForEach-Object {
  $t = $sh.CreateShortcut($_.FullName).TargetPath
  if ($t) { Add (Get-Item -LiteralPath $t) 'opened' }
} }
# 2) 수정한 파일, 3) 새로 받은 파일
$homeDirs = @([Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('Desktop'), (Join-Path $env:USERPROFILE 'Downloads'))
$od = Get-ChildItem -LiteralPath $env:USERPROFILE -Directory -Filter 'OneDrive*'
foreach ($o in $od) { $homeDirs += $o.FullName }
$homeDirs += $Roots
if ($OnlyRoots) { $homeDirs = $Roots }
foreach ($r in ($homeDirs | Select-Object -Unique)) {
  if (-not (Test-Path -LiteralPath $r)) { continue }
  Get-ChildItem -LiteralPath $r -Recurse -File -Depth 6 | ForEach-Object {
    if ($_.LastWriteTime -ge $since) { Add $_ 'modified' }
    elseif ($_.CreationTime -ge $since -and $r -like '*Downloads*') { Add $_ 'downloaded' }
  }
}

$list = $found.Values | Sort-Object last -Descending | Select-Object -First $MaxFiles
# 원본 사본을 워크스페이스 안(memory\scan\files)에 둔다 — Codex 샌드박스 안에서도 읽을 수 있게
$filesDir = Join-Path $out 'files'
if (Test-Path $filesDir) { Remove-Item (Join-Path $filesDir '*') -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $filesDir | Out-Null
$i = 0
foreach ($f in $list) {
  $copyName = ('{0:D3}_{1}' -f $i, $f.name); $i++
  Copy-Item -LiteralPath $f.path -Destination (Join-Path $filesDir $copyName) -ErrorAction SilentlyContinue
  $f | Add-Member -NotePropertyName copy -NotePropertyValue ("memory\scan\files\" + $copyName) -Force
}
$list | Select-Object path,copy,name,ext,kb,modified,created,why | Export-Csv -LiteralPath (Join-Path $out 'recent-files.csv') -NoTypeInformation -Encoding UTF8

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
$byWhy = $list | Group-Object { ($_.why -split ',')[0] } | ForEach-Object { "$($_.Name) $($_.Count)" }
$pdfNote = if ($py) { "PDF 읽기 가능" } else { "PDF 읽기 도구 없음" }
"찾은 파일 $($list.Count)개 ($($byWhy -join ', ')), 본문 추출 ${n}개, 본문 미지원 형식 ${skipped}개, ${pdfNote} → memory\scan\"
