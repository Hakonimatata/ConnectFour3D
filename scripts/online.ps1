# Starter spillet slik at venner kan bli med over internett, via en gratis Cloudflare-tunnel.
#   scripts\online.cmd             eksporter + start server + tunnel
#   scripts\online.cmd -NoExport   hopp over eksporten (raskere hvis du ikke har endret noe)
#   scripts\online.cmd -WebPort 9000 -GamePort 9080   andre porter (hvis 8000/8080 er opptatt)
# Stopp med Ctrl+C. Adressen kopieres til utklippstavlen.
# Godot hentes fra miljøvariabelen GODOT, ellers fra Nedlastinger-mappen.
param([switch]$NoExport, [int]$WebPort = 8000, [int]$GamePort = 8080)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

function Find-Cloudflared {
    $cmd = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @("$env:ProgramFiles\cloudflared\cloudflared.exe",
                     "${env:ProgramFiles(x86)}\cloudflared\cloudflared.exe",
                     "$env:LOCALAPPDATA\Microsoft\WinGet\Links\cloudflared.exe")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

$godot = if ($env:GODOT) { $env:GODOT } else { "$env:USERPROFILE\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe" }
if (-not (Test-Path $godot)) {
    Write-Host "Fant ikke Godot: $godot" -ForegroundColor Red
    Write-Host "Sett miljøvariabelen GODOT til stien til Godot_v4.7-stable_win64_console.exe"
    exit 1
}

$cf = Find-Cloudflared
if (-not $cf) {
    Write-Host "cloudflared mangler. Installerer (bare første gang) ..." -ForegroundColor Yellow
    $winget = (Get-Command winget -ErrorAction SilentlyContinue).Source
    if (-not $winget) { $winget = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe" }
    & $winget install --id Cloudflare.cloudflared -e --accept-source-agreements --accept-package-agreements
    $cf = Find-Cloudflared
    if (-not $cf) {
        Write-Host "Fant ikke cloudflared etter installasjonen. Lukk og åpne terminalen, og prøv igjen." -ForegroundColor Red
        exit 1
    }
}

foreach ($port in @($WebPort, $GamePort)) {
    if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
        Write-Host "Port $port er allerede i bruk. Kjører serveren i et annet vindu? Stopp den først." -ForegroundColor Red
        exit 1
    }
}

if (-not $NoExport) {
    & cmd /c "$PSScriptRoot\web.cmd" export
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

New-Item -ItemType Directory -Force build | Out-Null
$server = Start-Process $godot -ArgumentList '--headless', '--path', '.', '--', '--server', '--port', "$GamePort", '--web', 'build/web', '--web-port', "$WebPort" `
    -NoNewWindow -PassThru -RedirectStandardOutput build\server.log -RedirectStandardError build\server.err.log
$tunnel = Start-Process $cf -ArgumentList 'tunnel', '--no-autoupdate', '--url', "http://localhost:$WebPort" `
    -NoNewWindow -PassThru -RedirectStandardOutput build\tunnel.out.log -RedirectStandardError build\tunnel.log

try {
    Write-Host "Starter tunnel ..."
    $url = $null
    for ($i = 0; $i -lt 60 -and -not $url; $i++) {
        Start-Sleep -Milliseconds 500
        if ($tunnel.HasExited) { break }
        $m = Select-String -Path build\tunnel.log -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($m) { $url = $m.Matches[0].Value }
    }
    if (-not $url) {
        Write-Host "Fikk ikke laget tunnel. Se build\tunnel.log" -ForegroundColor Red
        return
    }
    Set-Clipboard $url
    Write-Host ""
    Write-Host "  Spillet er på nett:  $url" -ForegroundColor Green
    Write-Host "  Adressen er kopiert. Send den til de som skal spille."
    Write-Host "  Velg «Spill online», opprett et rom og del romkoden."
    Write-Host "  Stopp med Ctrl+C."
    Write-Host ""
    while (-not $server.HasExited -and -not $tunnel.HasExited) { Start-Sleep -Seconds 1 }
    if ($server.HasExited) { Write-Host "Serveren stoppet. Se build\server.err.log" -ForegroundColor Red }
    if ($tunnel.HasExited) { Write-Host "Tunnelen stoppet. Se build\tunnel.log" -ForegroundColor Red }
}
finally {
    foreach ($p in @($server, $tunnel)) {
        if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    }
    Write-Host "Server og tunnel er stoppet."
}
