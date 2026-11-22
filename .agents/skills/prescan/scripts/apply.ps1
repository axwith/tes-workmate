# memory/work-map.json 하나로 사전 온보딩 결과를 파일에 반영한다(AI가 빠뜨리지 않게 스크립트가 쓴다).
# AGENTS.md 4장, 업무 폴더 README, references, 위키, 확인 목록, 대시보드 HTML. 끝에 빠진 것을 점검해 알려 준다.
# 사용: apply.ps1 [-Open]
param([switch]$Open)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ws = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$utf = New-Object Text.UTF8Encoding $false
function W($rel, $text) { $p = Join-Path $ws $rel; New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null; [IO.File]::WriteAllText($p, ($text -replace "`r?`n", "`r`n"), $utf) }
function Slug($s) { ($s -replace '[\\/:*?"<>|\s]+', '-').Trim('-') }
$D = Get-Content (Join-Path $ws 'memory\work-map.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$problems = @()

# 1) AGENTS.md 4장 (표식 사이를 바꾼다)
$p = $D.profile
if ($p) {
  function V($label, $v) { $v = "$v".Trim(); if ($v.StartsWith($label)) { $v = $v.Substring($label.Length).TrimStart(' ', ':', '·') }; if (-not $v) { $v = '(미확인)' }; "- ${label}: $v" }
  $rows = @((V '이름·소속·직무' $(if ($p.person) { "(이름·소속은 첫 작업 때 확인) " + $p.person } else { '' })), (V '보고 대상·주기' $p.report), (V '주요 반복 업무와 저장 위치' $p.works),
    (V '판단 기준·금지 사항' $p.criteria), (V '팀 용어' $p.terms))
  $agents = Get-Content (Join-Path $ws 'AGENTS.md') -Raw -Encoding UTF8
  $block = "<!-- profile:start -->`n" + ($rows -join "`n") + "`n<!-- profile:end -->"
  $agents = [regex]::Replace($agents, '(?s)<!-- profile:start -->.*?<!-- profile:end -->', [Text.RegularExpressions.MatchEvaluator] { param($m) $block })
  W 'AGENTS.md' $agents
} else { $problems += 'profile 없음(AGENTS.md 4장 미작성)' }

# 2) 업무 폴더와 README
$scanCsv = Join-Path $ws 'memory\scan\recent-files.csv'
$scanRows = if (Test-Path $scanCsv) { Import-Csv $scanCsv -Encoding UTF8 } else { @() }
foreach ($f in @($D.folders)) {
  if (-not $f.path) { continue }
  W (Join-Path $f.path 'README.md') $f.readme
  # 이 업무의 단서 파일 사본을 업무 폴더\자료 로 복사 — 이후 작업이 워크스페이스 안에서 원본을 찾게
  foreach ($src in @($f.files)) {
    $row = $scanRows | Where-Object { $_.path -eq $src -or $_.copy -eq $src -or $_.name -eq (Split-Path $src -Leaf) } | Select-Object -First 1
    if ($row -and $row.copy) {
      $from = Join-Path $ws $row.copy; $toDir = Join-Path $ws (Join-Path $f.path '자료')
      New-Item -ItemType Directory -Force -Path $toDir | Out-Null
      Copy-Item -LiteralPath $from -Destination (Join-Path $toDir $row.name) -Force -ErrorAction SilentlyContinue
    }
  }
}
if (-not $D.folders) { $problems += 'folders 없음(업무 폴더 미생성)' }

# 3) references
$refNames = @{ 'report-formats' = '보고 양식'; 'criteria' = '기준값·계산식'; 'glossary' = '용어' }
foreach ($k in $refNames.Keys) {
  $v = $D.references.$k
  if ($v) { W "references\$k.md" ("# " + $refNames[$k] + "`n`n" + $v) } else { $problems += "references.$k 없음" }
}

# 4) 위키 + 목록
$idx = @("# 위키 목록", "", "> ``wrap``·``onboard``가 고친다. 실제 파일과 다르면 실제 파일이 우선.", "", "| 분류 | 페이지 | 요약 | 갱신 |", "|---|---|---|---|")
foreach ($k in @($D.wiki)) {
  if (-not $k.title) { continue }
  $rel = "memory\wiki\$($k.category)\$(Slug $k.title).md"
  W $rel ("---`ntitle: $($k.title)`ncategory: $($k.category)`nstatus: 추정`nupdated: $($D.date)`n---`n`n# $($k.title)`n`n$($k.body)")
  $idx += "| $($k.category) | [$($k.title)](wiki/$($k.category)/$(Slug $k.title).md) | $((($k.body -split "`n")[0]) -replace '\|','/') | $($D.date) |"
}
if (-not $D.wiki) { $problems += 'wiki 없음' }
# 이미 있던 위키(미리 넣어 둔 회사 위키 등)도 목록에 남긴다
$listed = @($D.wiki | ForEach-Object { "$($_.category)/$(Slug $_.title).md" })
Get-ChildItem (Join-Path $ws 'memory\wiki') -Recurse -Filter *.md -ErrorAction SilentlyContinue | ForEach-Object {
  $r = ($_.FullName.Substring((Join-Path $ws 'memory\wiki').Length + 1)) -replace '\\', '/'
  if ($listed -notcontains $r) {
    $t = (Get-Content $_.FullName -Encoding UTF8 | Where-Object { $_ -match '^# ' } | Select-Object -First 1) -replace '^# ', ''
    if (-not $t) { $t = $_.BaseName }
    $idx += "| $(Split-Path (Split-Path $r) -Leaf) | [$t](wiki/$r) | 미리 넣어 둔 자료 | $($_.LastWriteTime.ToString('yyyy-MM-dd')) |"
  }
}
W 'memory\index.md' ($idx -join "`n")

# 5) 확인 목록
W 'memory\onboard-checklist.md' ("# 온보딩 확인 목록`n`n" + ((@($D.checklist) | ForEach-Object { "- $_" }) -join "`n"))

# 5-1) 2교시 첫 응답을 미리 만들어 둔다(첫 턴은 이 파일만 읽고 그대로 답한다 → 진행 문구·스킬 언급이 생기지 않게)
$wsUrl = ($ws -replace '\\', '/')
$dash = "reports/{0}_내-업무-한눈에.html" -f (Get-Date -Format 'yyyy-MM-dd')
$lines = @()
$who = "안녕하세요. "   # 이름은 파일에서 추정하지 않는다(다른 사람 이름일 수 있다). 첫 작업 때 물어 채운다
$up = @($D.upcoming) | Select-Object -First 1
$dr = @($D.drafts) | Select-Object -First 1
$lead = if ($up) { "$($up.when) $(("$($up.what)".Trim()) -replace '\s*준비$', '') 준비해 둘게요." } else { "이번 주 업무 정리해 뒀어요." }
$lines += "$who$lead"
if ($dr) { $lines += "$($dr.title)도 만들어 뒀습니다$(if ($dr.note) { " ($($dr.note))" })." }   # note는 짧은 꾸밈말(예: 지난달 형식 그대로)
$links = @("[업무 한눈에]($wsUrl/$dash)"); if ($dr) { $links += "[$($dr.title)]($wsUrl/reports/$($dr.href))" }
$lines += ($links -join ' · '); $lines += ''
$n = 1
foreach ($w in (@($D.works) | Select-Object -First 3)) { $lines += "$n. $($w.name) $(if ($n -eq 1) { '마저 하기' } else { '' })".TrimEnd(); $n++ }
$lines += "$n. 다른 일 시키기"
W 'memory\first-reply.md' ($lines -join "`n")

# 6) 대시보드
& (Join-Path $PSScriptRoot 'render.ps1') -Open:$Open | Out-Null

# 7) 점검
$agentsNow = Get-Content (Join-Path $ws 'AGENTS.md') -Raw -Encoding UTF8
if ($agentsNow -match '\(미설정\)') { $problems += 'AGENTS.md 4장에 (미설정) 남음' }
foreach ($draft in @($D.drafts)) { if (-not (Test-Path (Join-Path $ws "reports\$($draft.href)"))) { $problems += "초안 파일 없음: reports\$($draft.href)" } }   # $d는 $D와 같은 변수(대소문자 무시)
if (-not $D.drafts) { $problems += '초안(drafts) 없음' }
foreach ($f in @($D.folders)) { if ($f.path -and -not $f.files) { $problems += "folders[$($f.path)].files 없음(단서 파일 경로를 넣어야 자료가 업무 폴더로 복사됨)" } }
if ($problems) { "점검 실패 — 고친 뒤 다시 실행:"; $problems | ForEach-Object { " - $_" }; exit 1 }
"반영 완료: AGENTS.md 4장, 폴더 $(@($D.folders).Count)개, references 3개, 위키 $(@($D.wiki).Count)개, 대시보드"
