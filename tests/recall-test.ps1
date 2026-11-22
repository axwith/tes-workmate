# recall(대화 수집·색인·검색) 회귀 시험. 임시 워크스페이스와 가짜 Codex 기록으로 돌리고, 기대 결과와 대조한다.
# 사용: powershell -NoProfile -ExecutionPolicy Bypass -File tests\recall-test.ps1   (실패하면 종료 코드 1)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tmp = Join-Path $env:TEMP ('wm-recall-test-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$ws = Join-Path $tmp 'workmate'; $cx = Join-Path $tmp 'codex'
New-Item -ItemType Directory -Force "$ws\.agents\skills", "$ws\memory\wiki\decisions", "$ws\memory\sessions", "$ws\20-operations\월간품질보고", "$cx\sessions\2026\11\20" | Out-Null
Copy-Item "$repo\.agents\skills\recall" "$ws\.agents\skills\recall" -Recurse
$utf = New-Object Text.UTF8Encoding $false
function W($p, $t) { [IO.File]::WriteAllText((Join-Path $ws $p), $t, $utf) }
W 'AGENTS.md' "# workmate`n보고는 결과부터."
W 'memory\wiki\decisions\pct.md' "---`ntitle: 차이 표기`n---`n# 차이 표기`n불량률 차이는 %p로 쓴다. 품질팀장 지시."
W '20-operations\월간품질보고\README.md' "# 월간 품질 보고`n매월 첫째 주 월요일, 검사결과.xlsx 기준."
function J($o) { $o | ConvertTo-Json -Compress -Depth 8 }
$lines = @(
  (J @{type='session_meta';payload=@{id='aaaabbbb-0000-0000-0000-000000000001';cwd=$ws;timestamp='2026-11-20T06:00:00Z'}}),
  (J @{type='response_item';payload=@{type='message';role='user';content=@(@{type='input_text';text='# AGENTS.md instructions 무시돼야 함'})}}),
  (J @{type='response_item';payload=@{type='message';role='user';content=@(@{type='input_text';text='협력사 견적 비교표 만들어 줘'})}}),
  (J @{type='response_item';payload=@{type='message';role='assistant';content=@(@{type='output_text';text='reports/견적비교.md 에 저장했습니다.'})}})
)
[IO.File]::WriteAllLines("$cx\sessions\2026\11\20\rollout-a.jsonl", $lines, $utf)
$other = @((J @{type='session_meta';payload=@{id='ccccdddd-0000-0000-0000-000000000002';cwd='C:\다른폴더';timestamp='2026-11-20T06:00:00Z'}}),
  (J @{type='response_item';payload=@{type='message';role='user';content=@(@{type='input_text';text='다른 폴더 대화 비밀'})}}))
[IO.File]::WriteAllLines("$cx\sessions\2026\11\20\rollout-b.jsonl", $other, $utf)

$env:CODEX_HOME = $cx
$r = "$ws\.agents\skills\recall\scripts"
$fail = 0
function Check($name, $cond) { if ($cond) { "통과  $name" } else { "실패  $name"; $script:fail++ } }
$out1 = powershell -NoProfile -ExecutionPolicy Bypass -File "$r\sync.ps1"
Check '대화 1개만 수집(다른 폴더 대화 제외)' ($out1 -match '새 대화 1개')
$sess = Get-ChildItem "$ws\memory\sessions" -Filter *.md
Check '세션 파일 이름' ($sess.Count -eq 1 -and $sess[0].Name -eq '2026-11-20_aaaabbbb.md')
$body = Get-Content $sess[0].FullName -Raw -Encoding UTF8
Check '시스템 문구 제외' ($body -notmatch 'AGENTS\.md instructions')
Check 'digested: false 표시' ($body -match 'digested: false')
$out2 = powershell -NoProfile -ExecutionPolicy Bypass -File "$r\sync.ps1"
Check '다시 돌려도 중복 수집 없음' ($out2 -match '새 대화 0개')
$cases = @(
  @('견적 비교표', '2026-11-20_aaaabbbb'), @('불량률', 'pct.md'), @('%p', 'pct.md'), @('팀장', 'pct.md'),
  @('품질 보고', '월간품질보고'), @('첫째 주', '월간품질보고'), @('결과부터', 'AGENTS.md')
)
foreach ($c in $cases) {
  $res = (powershell -NoProfile -ExecutionPolicy Bypass -File "$r\search.ps1" $c[0] -n 5) -join "`n"
  Check "검색 '$($c[0])' → $($c[1])" ($res -like "*$($c[1])*")
}
$none = (powershell -NoProfile -ExecutionPolicy Bypass -File "$r\search.ps1" '비밀' -n 5) -join "`n"
Check "다른 폴더 대화는 검색 안 됨" ($none -match '검색 결과 없음')
$kindRes = (powershell -NoProfile -ExecutionPolicy Bypass -File "$r\search.ps1" '견적' -kind 'memory/sessions' -n 5) -join "`n"
Check "종류 필터(memory/sessions)" ($kindRes -like '*aaaabbbb*')
Remove-Item $tmp -Recurse -Force
if ($fail) { "실패 $fail건"; exit 1 } else { '전부 통과' }
