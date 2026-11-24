# 자료를 00-inbox\날짜\ 로 복사한다(원본은 그대로). 설치 없이 Windows PowerShell 5.1에서 돈다.
# 사용: collect.ps1 -Days 30            # prescan 기준(열어 봄·수정함·새로 받음)으로 최근 파일 복사
#       collect.ps1 -From "D:\업무\품질"  # 특정 폴더의 문서 파일 복사
param([int]$Days = 30, [string]$From = '', [int]$MaxFiles = 300)
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ws = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$dest = Join-Path $ws ("00-inbox\" + (Get-Date -Format 'yyyy-MM-dd'))
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$docExt = '.docx','.xlsx','.pptx','.hwp','.hwpx','.pdf','.txt','.md','.csv','.tsv','.json','.doc','.xls','.ppt','.msg','.eml'

if ($From) {
  $items = Get-ChildItem -LiteralPath $From -Recurse -File -Depth 6 | Where-Object { $docExt -contains $_.Extension.ToLower() -and $_.Length -lt 50MB } |
    Select-Object -First $MaxFiles | ForEach-Object { [pscustomobject]@{ path=$_.FullName; modified=$_.LastWriteTime.ToString('yyyy-MM-dd'); why='folder' } }
} else {
  & (Join-Path $ws '.agents\skills\prescan\scripts\scan.ps1') -Days $Days -MaxFiles $MaxFiles -MaxText 0 | Out-Null
  $items = Import-Csv -LiteralPath (Join-Path $ws 'memory\scan\recent-files.csv') -Encoding UTF8 | Where-Object { $_.why -notlike '*online-only*' }   # 온라인 전용은 내려받지 않는다
}

$rows = @(); $n = 0
foreach ($it in $items) {
  $name = Split-Path $it.path -Leaf
  $target = Join-Path $dest $name
  $i = 1; while (Test-Path -LiteralPath $target) { $target = Join-Path $dest ("{0}_{1}{2}" -f [IO.Path]::GetFileNameWithoutExtension($name), $i, [IO.Path]::GetExtension($name)); $i++ }
  Copy-Item -LiteralPath $it.path -Destination $target
  if ($?) { $n++; $rows += [pscustomobject]@{ file=(Split-Path $target -Leaf); from=$it.path; modified=$it.modified; why=$it.why } }
}
$rows | Export-Csv -LiteralPath (Join-Path $dest '_목록.csv') -NoTypeInformation -Encoding UTF8
"복사 ${n}개 → $dest"
Start-Process explorer.exe $dest
