# memory/work-map.json 을 읽어 reports/YYYY-MM-DD_내-업무-한눈에.html 을 만든다(고정 디자인, 외부 파일 없음).
# 사용: render.ps1 [-Open]
param([switch]$Open)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ws = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$json = Get-Content (Join-Path $ws 'memory\work-map.json') -Raw -Encoding UTF8
$null = $json | ConvertFrom-Json   # 형식 오류면 여기서 멈춘다
$tpl = Get-Content (Join-Path $PSScriptRoot 'dashboard.html') -Raw -Encoding UTF8
$html = $tpl.Replace('/*DATA*/null', ($json -replace '</', '<\/'))
$out = Join-Path $ws ("reports\{0}_내-업무-한눈에.html" -f (Get-Date -Format 'yyyy-MM-dd'))
[IO.File]::WriteAllText($out, $html, (New-Object Text.UTF8Encoding $false))
"만듦: $out"
if ($Open) { Start-Process $out }
