# Etter web-eksporten (kalles av web.cmd, runde 19), for kortere lastetid:
#   - emojiskriften legges ved siden av spillet (build\web\emoji.ttf). Den er ikke med i spillpakken,
#     men hentes når spillet har startet (se client/ui/ui.gd, emoji_font).
#   - index.wasm komprimeres med brotli (index.wasm.br, ~30 % mindre enn gzip) hvis brotli finnes
#     (følger med Git for Windows). Serveren sender den til nettlesere som støtter det.
#     index.wasm er den samme til Godot oppdateres, så den komprimeres bare når innholdet er endret
#     (tar 1–2 minutter). Ellers får den gamle .br-filen bare ny dato, så serveren vet at den passer.
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

Copy-Item assets\fonts\Twemoji.Mozilla.ttf build\web\emoji.ttf -Force

$brotli = (Get-Command brotli -ErrorAction SilentlyContinue).Source
foreach ($p in @("$env:ProgramFiles\Git\mingw64\bin\brotli.exe", "$env:ProgramFiles\Git\usr\bin\brotli.exe")) {
    if (-not $brotli -and (Test-Path $p)) { $brotli = $p }
}
$wasm = 'build\web\index.wasm'
if (-not $brotli) {
    Remove-Item "$wasm.br" -ErrorAction SilentlyContinue
    Write-Host "Fant ikke brotli: index.wasm sendes med gzip. Installer Git for Windows for ~30 % mindre nedlasting."
    exit 0
}
$hash = (Get-FileHash $wasm -Algorithm SHA256).Hash
$stamp = 'build\index.wasm.sha256'
if (-not ((Test-Path "$wasm.br") -and (Test-Path $stamp) -and ((Get-Content $stamp -Raw).Trim() -eq $hash))) {
    Write-Host "Komprimerer index.wasm med brotli (1-2 minutter, bare etter at Godot er oppdatert) ..."
    & $brotli -q 11 -f -o "$wasm.br" $wasm
    if ($LASTEXITCODE -ne 0) {
        Remove-Item "$wasm.br" -ErrorAction SilentlyContinue
        Write-Host "brotli feilet: index.wasm sendes med gzip."
        exit 0
    }
    Set-Content $stamp $hash
}
(Get-Item "$wasm.br").LastWriteTime = Get-Date   # serveren bruker bare en .br som er minst like ny som index.wasm
