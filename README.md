# Fire på rad i 3D

Fire på rad på et 3D-brett (4×4×4 eller 5×5×5), laget i Godot 4.7. Spillet kan spilles mot AI (tre vanskelighetsgrader), med to spillere på samme enhet eller online mot venner. Det fungerer på PC og mobil (nettleser).

Alt er skrevet i GDScript i ett Godot-prosjekt. Klienten, AI-en og serveren bruker **samme regelmotor** (`core/`).

## Kom i gang

1. Installer [Godot 4.7](https://godotengine.org/download) (standardversjonen, ikke .NET).
2. Åpne `project.godot` i Godot og trykk **F5**.

Kommandoene under kjøres fra roten av repoet. `godot` er Godot-programmet (på Windows f.eks. `Godot_v4.7-stable_win64_console.exe`).

### Skrive `godot` i stedet for hele stien (Windows PowerShell)

Kjør dette én gang. Det legger et kortnavn i PowerShell-profilen din:

```powershell
if (!(Test-Path $PROFILE)) { New-Item -Type File -Force $PROFILE }
Add-Content $PROFILE 'Set-Alias godot "$env:USERPROFILE\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe"'
```

Lukk og åpne PowerShell (eller terminalen i VS Code) igjen. Deretter virker `godot ...` overalt.

Får du feilen «running scripts is disabled», kjør én gang:
`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

Flytter du Godot til en annen mappe, retter du stien med `notepad $PROFILE`.

| Hva | Kommando |
|---|---|
| Kjør spillet | `godot --path .` |
| Kjør alle tester | `godot --headless --path . res://tests/run_tests.tscn` |
| Kjør noen tester | `godot --headless --path . res://tests/run_tests.tscn -- rules` (filter på filnavn) |
| Start spillserveren | `godot --headless --path . -- --server` (port 8080, endre med `--port 9000` eller `PORT=9000`) |
| Server + web-klient på wifi | `godot --headless --path . -- --server --web build/web` (web på port 8000, endre med `--web-port`) |
| **Eksporter + start alt (Windows)** | `scripts\web.cmd` (bare eksport: `scripts\web.cmd export`) |

### Spille online lokalt

1. Start serveren med kommandoen over.
2. Start spillet to ganger, for eksempel med *Debug → Customize Run Instances* i editoren.
3. Velg «Spill online» i begge. Klienten kobler til `ws://localhost:8080` som standard.
4. Opprett et rom i det ene vinduet, og bli med med koden i det andre.

Serveradressen kan endres under *Innstillinger → Server*. På web kan den også settes i adressefeltet, for eksempel `?server=ws://192.168.1.10:8080`.

### Spille i nettleseren fra din egen PC (telefon, venner)

**Viktig:** nettlesere starter bare Godot-spill fra en *sikker* adresse, altså `https://…` eller `http://localhost`. En adresse som `http://192.168.1.23:8000` gir feilen *«Secure Context – use HTTPS»*. Serveren kan derfor kjøre HTTPS selv (`--https`).

1. **Lag web-bygget** (på nytt etter hver endring i spillet): *Project → Export → Web → Export Project* til `build/web/index.html`, eller kjør
   ```
   godot --headless --path . --export-release "Web" build/web/index.html
   ```
2. **Start serveren med web-klienten og HTTPS.** Web-siden og spillet deler port 8000, og `/ws` sendes videre til spillserveren:
   ```
   godot --headless --path . -- --server --web build/web --https
   ```
   Den skriver ut adressen alle skal åpne, for eksempel:
   ```
   https://192-168-1-23.local-ip.sh:8000
   ```
3. **Velg hvordan du åpner spillet:**

| Hvem | Slik gjør du |
|---|---|
| **Alle på samme wifi** (iPhone, Android, PC, uten kabel) | Åpne `https://…local-ip.sh:8000`-adressen serveren skriver ut. Det er PC-ens IP med bindestreker. Windows-brannmuren spør første gang: tillat Godot på *private nettverk*. |
| Deg på PC-en (uten `--https`) | Åpne `http://localhost:8000` i nettleseren. |
| Din Android-telefon (med kabel) | 1. Slå på *USB-feilsøking* (Innstillinger → Om telefonen → trykk 7 ganger på «Build number» → Utvikleralternativer → USB-feilsøking). 2. Koble telefonen til PC-en. 3. Åpne `chrome://inspect/#devices` i Chrome på PC-en, trykk **Port forwarding…**, legg til port `8000` → `localhost:8000`, kryss av for *Enable port forwarding* og trykk **Done**. 4. Åpne `http://localhost:8000` i Chrome på telefonen. |
| Venner og telefoner uten kabel (wifi eller hvor som helst) | Lag en gratis HTTPS-tunnel med Cloudflare. Installer én gang: `winget install Cloudflare.cloudflared`. Kjør deretter `cloudflared tunnel --url http://localhost:8000` i et eget terminalvindu. Den skriver ut en adresse som `https://noe-tilfeldig.trycloudflare.com`. Del den, så kan alle spille, også over mobilnett. Adressen er ny hver gang du starter tunnelen. |

**Om `--https` og local-ip.sh:**
- [local-ip.sh](https://local-ip.sh) er en gratis tjeneste der `192-168-1-23.local-ip.sh` peker til `192.168.1.23`, og som deler ut et gyldig sertifikat for `*.local-ip.sh`. Serveren henter sertifikatet selv og fornyer det ukentlig. Spilltrafikken går direkte over wifi.
- PC-en og telefonene trenger internett for navneoppslaget, og PC-en for å hente sertifikatet.
- Noen rutere blokkerer navn som peker til lokale adresser («DNS rebinding protection»). Får telefonen ikke åpnet siden, bruk Cloudflare-tunnelen i tabellen over i stedet.
- Nøkkelen til sertifikatet er offentlig. Det er greit for et spill på hjemmenettet, men ikke bruk det til noe hemmelig.
- Med eget sertifikat: `--https --cert fil.pem --key fil.key`.

**Tips:**
- I `chrome://inspect` kan du trykke *inspect* under telefonens fane for å se feilmeldinger fra spillet.
- Desktop-versjonen av spillet har ikke HTTPS-kravet. Den kan koble direkte til `ws://<PC-ens IP>:8080` (sett adressen under *Innstillinger → Server*). Windows-brannmuren spør første gang. Tillat Godot på *private nettverk*.
- For noe permanent: bruk en server med eget domene og HTTPS (under).

## Bygge og hoste

**Web-klienten** krever at Godot har eksportmaler: *Editor → Manage Export Templates → Download*. Deretter:

```
godot --headless --path . --export-release "Web" build/web/index.html
```

**Alt på én server (anbefalt):** én liten VPS med Docker. Caddy serverer web-klienten, gir automatisk HTTPS og sender `/ws` videre til spillserveren.

```
DOMAIN=spill.example.no docker compose -f deploy/docker-compose.yml up -d --build
```

Pek domenet (A-record) til serverens IP først. Deretter er spillet på `https://spill.example.no`, og klienten finner serveren selv (`wss://spill.example.no/ws`). Det første bygget laster ned Godot og eksportmalene, så det tar noen minutter.

**CI** (GitHub Actions) kjører testene ved hver push. På `main` eksporterer den også web-bygget og legger det ved som nedlastbar artefakt.

## Mappestruktur

```
core/      Regelmotoren: GameOptions, GameState, Lines, ChessClock (ren logikk)
ai/        Bot og BotProfile (vanskelighetsgrader)
net/       Protokoll (meldingstyper) og nettverksklienten (autoload «Net»)
server/    ServerMain (WebSocket) og Lobby (spillere, rom, partier, chat)
client/    Alt det visuelle: brett, kamera, skjermer, effekter, innstillinger
  board/   3D-brettet (genereres i kode) og orbit-kameraet
  match/   MatchController: OfflineMatch (lokalt/AI) og OnlineMatch
  ui/      Meny, oppsett, lobby, venterom, spillskjerm, chat, tema
  fx/      Seierseffekter og lyd (lages i kode)
assets/    Brikkemodell og toon-shader
tests/     Tester og testløper
deploy/    Dockerfile, docker-compose og Caddyfile
```

## Regler

Reglene er beskrevet i [Plan.md, seksjon 2](Plan.md), og hver regel har egne tester i `tests/test_rules.gd`.

- Man velger en kolonne, og brikken faller ned.
- Fire på rad i én av de 13 retningene vinner.
- Fullt brett er uavgjort, og tid ute er tap.

Når et rom opprettes kan man i tillegg slå på «Må blokkere» og «Ikke gi bort seier».

Se også [Plan.md](Plan.md) (planen) og [Fremgang.md](Fremgang.md) (hva som er gjort).
