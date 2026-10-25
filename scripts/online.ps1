# Starter spillet slik at venner kan bli med over internett, via en gratis Cloudflare-tunnel.
#   scripts\online.cmd             eksporter + start server + tunnel
#   scripts\online.cmd -NoExport   hopp over eksporten (raskere hvis du ikke har endret noe)
#   scripts\online.cmd -WebPort 9000 -GamePort 9080   andre porter (hvis 8000/8080 er opptatt)
#   scripts\online.cmd -Hostname spill.mittdomene.no   fast adresse på ditt eget domene (se README, «Hosting»)
# Uten -Hostname får du en tilfeldig adresse (trycloudflare.com) som endres hver gang.
# Med -Hostname brukes en navngitt tunnel: første gang logger du inn hos Cloudflare i nettleseren,
# så lages tunnelen og DNS-oppføringen automatisk. Domenet må ligge i Cloudflare.
# Stopp med Ctrl+C. Adressen kopieres til utklippstavlen.
# Godot finnes automatisk (se scripts\find_godot.ps1), eller settes med miljøvariabelen GODOT.
param([switch]$NoExport, [int]$WebPort = 8000, [int]$GamePort = 8080, [string]$Hostname = "", [string]$TunnelName = "fire-paa-rad")

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

$godot = & "$PSScriptRoot\find_godot.ps1"
if (-not $godot) {
    Write-Host "Fant ikke Godot 4.7 i Nedlastinger, på skrivebordet eller i Program Files." -ForegroundColor Red
    Write-Host "Sett miljøvariabelen GODOT til stien til Godot_v4.7-stable_win64_console.exe"
    exit 1
}
$env:GODOT = $godot   # så web.cmd (eksporten) bruker samme Godot

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
$tunnelArgs = @('tunnel', '--no-autoupdate', '--url', "http://localhost:$WebPort")
if ($Hostname) {
    # Navngitt tunnel på eget domene: logg inn (første gang), lag tunnelen og pek domenet dit.
    if (-not (Test-Path "$env:USERPROFILE\.cloudflared\cert.pem")) {
        Write-Host "Første gang: logg inn hos Cloudflare i nettleseren som åpnes, og velg domenet ditt." -ForegroundColor Yellow
        & $cf tunnel login
        if (-not (Test-Path "$env:USERPROFILE\.cloudflared\cert.pem")) {
            Write-Host "Innloggingen ble ikke fullført." -ForegroundColor Red
            exit 1
        }
    }
    $existing = & $cf tunnel list --output json 2>$null | ConvertFrom-Json
    if (-not ($existing | Where-Object { $_.name -eq $TunnelName })) {
        & $cf tunnel create $TunnelName
        if ($LASTEXITCODE -ne 0) { Write-Host "Kunne ikke lage tunnelen." -ForegroundColor Red; exit 1 }
    }
    & $cf tunnel route dns --overwrite-dns $TunnelName $Hostname
    if ($LASTEXITCODE -ne 0) { Write-Host "Kunne ikke peke $Hostname til tunnelen. Ligger domenet i Cloudflare?" -ForegroundColor Red; exit 1 }
    $tunnelArgs = @('tunnel', '--no-autoupdate', 'run', '--url', "http://localhost:$WebPort", $TunnelName)
}
$tunnel = Start-Process $cf -ArgumentList $tunnelArgs `
    -NoNewWindow -PassThru -RedirectStandardOutput build\tunnel.out.log -RedirectStandardError build\tunnel.log

try {
    Write-Host "Starter tunnel ..."
    $url = $null
    for ($i = 0; $i -lt 60 -and -not $url; $i++) {
        Start-Sleep -Milliseconds 500
        if ($tunnel.HasExited) { break }
        if ($Hostname) {
            if (Select-String -Path build\tunnel.log -Pattern 'Registered tunnel connection' -Quiet -ErrorAction SilentlyContinue) {
                $url = "https://$Hostname"
            }
            continue
        }
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
