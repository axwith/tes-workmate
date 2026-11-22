# workmate bootstrap (ASCII only, safe for: irm .../get.ps1 | iex)
# Downloads install.ps1 as raw bytes (keeps its UTF-8 BOM for Korean text) and runs it with -File.
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$Repo = 'axwith/tes-workmate'
$f = Join-Path $env:TEMP ('workmate-install-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.ps1')
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/$Repo/main/install.ps1" -OutFile $f
powershell -NoProfile -ExecutionPolicy Bypass -File $f
Remove-Item $f -Force -ErrorAction SilentlyContinue
