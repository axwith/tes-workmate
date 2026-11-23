# 기억 동기화 (AI 없이 돈다. 설치기가 작업 스케줄러에 1시간마다·로그인 때 등록)
# 1) 이 워크스페이스에서 한 Codex 대화를 memory/sessions/ 에 마크다운으로 옮긴다(새로 생긴 것만)
# 2) memory·references·AGENTS.md·업무 폴더의 .md 를 memory/index.db (SQLite FTS5) 로 색인한다
param([switch]$Quiet)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ws = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
. (Join-Path $PSScriptRoot 'sqlite.ps1')
$mem = Join-Path $ws 'memory'
$sessDir = Join-Path $mem 'sessions'; New-Item -ItemType Directory -Force -Path $sessDir | Out-Null
$statePath = Join-Path $mem 'sync-state.json'
$state = @{}; if (Test-Path $statePath) { (Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json).psobject.Properties | ForEach-Object { $state[$_.Name] = $_.Value } }

# ---- 1. Codex 대화 기록 옮기기 ----
function Txt($content) { ($content | Where-Object { $_.text } | ForEach-Object { $_.text }) -join "`n" }
function Cut($s, $n) { if ($s.Length -gt $n) { $s.Substring(0, $n) + ' …(줄임)' } else { $s } }
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$newSess = 0
foreach ($f in (Get-ChildItem (Join-Path $codexHome 'sessions') -Recurse -Filter 'rollout-*.jsonl' -ErrorAction SilentlyContinue)) {
  $key = $f.Name; $len = $f.Length
  if ($state.ContainsKey($key) -and [long]$state[$key] -eq $len) { continue }
  $cwd = $null; $id = $null; $started = $null; $turns = New-Object System.Collections.ArrayList; $lastAssist = $null
  # 지금 쓰고 있는 대화 파일도 읽을 수 있게 공유 모드로 연다(잠김 오류 방지)
  try { $fs = New-Object IO.FileStream($f.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete'); $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8); $lines = $sr.ReadToEnd() -split "`n"; $sr.Close() } catch { continue }
  foreach ($line in $lines) {
    if ($line.Length -gt 400000) { continue }
    try { $d = $line | ConvertFrom-Json } catch { continue }
    if ($d.type -eq 'session_meta') { $cwd = $d.payload.cwd; $id = $d.payload.id; $started = $d.payload.timestamp; continue }
    if ($d.type -ne 'response_item' -or $d.payload.type -ne 'message') { continue }
    $t = Txt $d.payload.content
    if (-not $t) { continue }
    if ($d.payload.role -eq 'user') {
      if ($t -match '^\s*(# AGENTS\.md instructions|<environment_context>|<user_instructions>|<subagent_notification>)') { continue }
      if ($lastAssist) { [void]$turns.Add("**답변**`n`n" + (Cut $lastAssist 3000)); $lastAssist = $null }
      [void]$turns.Add("**사용자**`n`n" + (Cut $t 2000))
    } elseif ($d.payload.role -eq 'assistant') { $lastAssist = $t }
  }
  $state[$key] = $len
  if (-not $cwd -or -not ($cwd.TrimEnd('\') -ieq $ws.TrimEnd('\') -or $cwd -like "$ws\*")) { continue }
  if ($lastAssist) { [void]$turns.Add("**답변**`n`n" + (Cut $lastAssist 3000)) }
  if ($turns.Count -eq 0) { continue }
  $day = ([datetime]$started).ToLocalTime().ToString('yyyy-MM-dd')
  $first = (($turns[0] -replace '^\*\*사용자\*\*\s*', '') -split "`n")[0]; $title = Cut $first 60
  $out = Join-Path $sessDir ("{0}_{1}.md" -f $day, $id.Substring(0, 8))
  $head = "---`ndate: $day`nsession: $id`ntitle: $title`ndigested: false`n---`n`n# $title`n`n"
  Set-Content -LiteralPath $out -Value ($head + ($turns -join "`n`n")) -Encoding UTF8
  $newSess++
}
($state | ConvertTo-Json -Compress) | Set-Content -LiteralPath $statePath -Encoding UTF8

# ---- 2. 색인 ----
$dbPath = Join-Path $mem 'index.db'
$tmp = "$dbPath.tmp"; if (Test-Path $tmp) { Remove-Item $tmp -Force }
$db = [WmSql]::Open($tmp)
try {
  [void][WmSql]::Run($db, "CREATE VIRTUAL TABLE docs USING fts5(path UNINDEXED, kind UNINDEXED, date UNINDEXED, title, body, tokenize='trigram')")
  [void][WmSql]::Run($db, "BEGIN")
  $roots = @('memory', 'references', '10-projects', '20-operations', '30-knowledge', '40-personal', '50-resources')
  $files = @(Get-Item (Join-Path $ws 'AGENTS.md'))
  foreach ($r in $roots) { $p = Join-Path $ws $r; if (Test-Path $p) { $files += Get-ChildItem $p -Recurse -File -Include *.md, *.txt, *.csv | Where-Object { $_.FullName -notlike '*\memory\scan\*' -and $_.Length -lt 2MB } } }
  foreach ($f in $files) {
    $rel = $f.FullName.Substring($ws.Length + 1)
    $kind = ($rel -split '\\')[0]; if ($rel -like 'memory\*') { $kind = 'memory/' + ($rel -split '\\')[1] }
    $body = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
    if (-not $body) { continue }
    $title = (($body -split "`n") | Where-Object { $_ -match '^(# |title:)' } | Select-Object -First 1) -replace '^(# |title:\s*)', ''
    if (-not $title) { $title = $f.BaseName }
    [void][WmSql]::Run($db, "INSERT INTO docs VALUES (?,?,?,?,?)", $rel, $kind, $f.LastWriteTime.ToString('yyyy-MM-dd'), $title.Trim(), $body)
  }
  [void][WmSql]::Run($db, "COMMIT")
  $count = ([WmSql]::Run($db, "SELECT count(*) FROM docs"))[0][0]
} finally { [WmSql]::Close($db) }
Move-Item -Force $tmp $dbPath
# ---- 3. 최근 파일 목록 새로 고침(하루 한 번) — 샌드박스 밖에서 돌아야 PC 문서를 다 읽는다 ----
$csv = Join-Path $mem 'scan\recent-files.csv'
$scanPs = Join-Path $ws '.agents\skills\prescan\scripts\scan.ps1'
if ((Test-Path $scanPs) -and (-not (Test-Path $csv) -or (Get-Item $csv).LastWriteTime -lt (Get-Date).AddDays(-1))) {
  powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws '.agents\skills\prescan\scripts\scan.ps1') -Force | Out-Null
}

# ---- 4. 변경 기록(git) — Codex 샌드박스는 .git을 쓸 수 없으므로 여기서 남긴다 ----
$committed = $false
if ((Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $ws '.git'))) {
  if (git -C $ws status --porcelain 2>$null) {
    $ErrorActionPreference = 'Continue'   # git stderr 안내가 Stop에서 오류로 바뀌지 않게
    git -C $ws add -A 2>$null
    git -C $ws -c user.name=workmate -c user.email=workmate@local commit -q -m ("자동 기록 " + (Get-Date -Format 'yyyy-MM-dd HH:mm')) 2>$null | Out-Null
    $ErrorActionPreference = 'Stop'
    $committed = $true
  }
}
if (-not $Quiet) { "새 대화 ${newSess}개 옮김, 색인 문서 ${count}개 → memory\index.db" + $(if ($committed) { ", 변경 기록 남김" } else { "" }) }
