# 기억 검색: memory/index.db (SQLite FTS5 trigram) 에서 찾는다. 3글자 이상 단어가 잘 잡힌다.
# 사용: search.ps1 "품질 보고" [-n 10] [-kind memory/sessions]
param([Parameter(Mandatory = $true)][string]$q, [int]$n = 10, [string]$kind = '')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ws = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
. (Join-Path $PSScriptRoot 'sqlite.ps1')
$dbPath = Join-Path $ws 'memory\index.db'
if (-not (Test-Path $dbPath)) { & (Join-Path $PSScriptRoot 'sync.ps1') -Quiet }
$terms = $q -split '\s+' | Where-Object { $_ }
$long = $terms | Where-Object { $_.Length -ge 3 }
$short = $terms | Where-Object { $_.Length -lt 3 }
function Like($s) { '%' + ($s -replace '([\\%_])', '\$1') + '%' }
$db = [WmSql]::Open($dbPath)
try {
  $args2 = @()
  if ($long) {
    $match = ($long | ForEach-Object { '"' + ($_ -replace '"', '""') + '"' }) -join ' AND '
    $sql = "SELECT path, date, title, snippet(docs, 4, '[', ']', ' … ', 24) FROM docs WHERE docs MATCH ?"
    $args2 += $match
  } else {
    $sql = "SELECT path, date, title, substr(body, max(1, instr(body, ?) - 60), 160) FROM docs WHERE 1=1"
    $args2 += $short[0]
  }
  foreach ($s in $short) { $sql += " AND body LIKE ? ESCAPE '\'"; $args2 += (Like $s) }
  if ($kind) { $sql += " AND kind = ?"; $args2 += $kind }
  $sql += " ORDER BY date DESC LIMIT $n"
  $rows = [WmSql]::Run($db, $sql, [string[]]$args2)
} finally { [WmSql]::Close($db) }
if (-not $rows -or $rows.Count -eq 0) { "검색 결과 없음: $q"; return }
foreach ($r in $rows) { "- $($r[1])  $($r[0])  「$($r[2])」`n    $(($r[3] -replace '\s+', ' ').Trim())" }
