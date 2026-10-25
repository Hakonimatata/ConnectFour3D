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

Skriptene i `scripts\` finner Godot 4.7 selv i Nedlastinger, på skrivebordet eller i Program Files. Ligger det et annet sted, sett miljøvariabelen `GODOT` til stien til `Godot_v4.7-stable_win64_console.exe`.

### Spille online lokalt

1. Start serveren med kommandoen over.
2. Start spillet to ganger, for eksempel med *Debug → Customize Run Instances* i editoren.
3. Velg «Spill online» i begge. Klienten kobler til `ws://localhost:8080` som standard.
4. Opprett et rom i det ene vinduet, og bli med med koden i det andre.

Serveradressen kan endres under *Innstillinger → Server*. På web kan den også settes i adressefeltet, for eksempel `?server=ws://192.168.1.10:8080`.

### Spille med venner over internett (én kommando)

```
scripts\online.cmd
```

Skriptet gjør alt:
1. Eksporterer spillet.
2. Starter serveren.
3. Lager en gratis Cloudflare-tunnel (`cloudflared` installeres automatisk første gang).
4. Skriver ut en adresse som `https://noe-tilfeldig.trycloudflare.com` og kopierer den til utklippstavlen.

Send adressen til de som skal spille. Den virker på iPhone, Android og PC, også over mobilnett.

- **Spille:** velg «Spill online», opprett et rom og del romkoden.
- **Stoppe:** trykk Ctrl+C.
- **Raskere oppstart:** `scripts\online.cmd -NoExport` hopper over eksporten når du ikke har endret noe.
- **Andre porter:** er 8000 eller 8080 opptatt, bruk `-WebPort 9000 -GamePort 9080`.
- **Ny adresse hver gang:** tunnelen får en ny adresse hver gang du starter den. Åpner du den på din egen PC med én gang, kan det ta opptil et halvt minutt før den virker der (nettverket ditt husker at navnet ikke fantes).
- **Spillet kjører på PC-en din:** den må være på, og opplastingen din avgjør hvor fort andre laster spillet. Spillfilen komprimeres til ca. 10 MB.

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

## Kontoer, admin og brukerdata

Online kan man spille som gjest, eller logge inn for å få statistikk, Elo-rating og være med i turneringer. Det gjøres under *Spill online → Logg inn / ny konto*.

Innloggede spillere får et **Elo-merke** ved navnet: Bronse (under 1100), Sølv (1100), Gull (1250), Platina (1400), Diamant (1550), Mester (1700) og Stormester (1850). Nivåene låser også opp merker på brikken (krone, flamme, laurbær m.fl.). Serveren sjekker at du har låst dem opp.

På forsiden vises aktive turneringer, **Dagens oppgave** (en ny tvungen seier å finne hver dag, med toppliste) og en **global chat** med hvor mange som er online. I chatten publiserer serveren også hendelser: nye nivåer, seiersrekker, turneringsvinnere og hvem som løste dagens oppgave. Turneringskamper kan ses på som tilskuer («Se på» på turneringssiden), og alle partier kan ses igjen med tvungne trekk markert («Se partiet igjen» og «Siste partier» på profilen).

**Hvor ligger dataene?** Serveren lagrer alt som lesbare JSON-filer i én mappe:
- Kjører serveren fra prosjektet (`scripts\web.cmd`, `scripts\online.cmd` eller `godot … -- --server`), ligger de i `data/` i prosjektmappen. Mappen er i `.gitignore`.
- I Docker ligger de i volumet `game_data`.
- Annen mappe: `--data <mappe>`.

| Fil | Innhold |
|---|---|
| `users.json` | Brukere: brukernavn, `admin`, `banned`, Elo, statistikk, pokaler, profil og passord-hash (aldri passordet selv) |
| `avatars.json` | Profilbilder |
| `sessions.json` | Innloggede økter (bare en hash av nøkkelen) |
| `tournaments.json` | Turneringer |
| `games.jsonl` | Ett ferdig parti per linje, med trekk og analyse (brukes til repriser) |
| `puzzles.json` | Dagens oppgave og hvem som har løst den, de siste 14 dagene |
| `global_chat.json` | De siste 50 meldingene og hendelsene i den globale chatten |

**Gjøre noen til admin:** åpne `data/users.json`, finn brukeren og sett `"admin": true`. Lagre filen. Serveren oppdager endringen innen ett sekund, og du trenger ikke starte den på nytt. Du kan også starte serveren med `--admin <brukernavn>`.

```json
{
  "id": 1,
  "username": "Hakon",
  "admin": true,
  "elo": 1216,
  ...
}
```

**Glemt passord:** legg til `"reset_password": "nytt-passord"` på brukeren og lagre. Serveren lager en hash av det nye passordet og fjerner klarteksten fra filen med en gang.

**Ugyldig JSON:** lagrer du `users.json` med en skrivefeil, beholder serveren brukerne den har i minnet og skriver en advarsel. Rett feilen og lagre på nytt.

**Turneringer:** admin lager dem i spillet under *Spill online → Turneringer → Ny turnering*. Velg navn, dag og klokkeslett med pilene (eller 18:00–21:00 med ett trykk), format, antall deltakere og pokalen vinneren får («Ny pokal» trekker en ny). Beskrivelse, regler, klokke, pauser og møtefrist ligger under «Flere valg». Den neste turneringen med åpen påmelding reklameres i hovedmenyen med «Meld meg på». Når en kamp starter, får begge varselet «Gå til kamp». Den som ikke møter innen fristen, taper på walkover. Deltakerne ser sin egen kamp øverst på turneringssiden og er markert i turneringstreet. Vinneren får pokalen på profilen sin, og den siste vinneren vises i hovedmenyen.

**Admin-siden** (knappen «Admin» ved profilbildet i hovedmenyen, bare for admin):
- **Kunngjøring:** vises som et banner hos alle som er online, og blir stående i den globale chatten.
- **Utesteng / opphev:** en utestengt konto kan ikke logge inn, kastes ut hvis den er online og fjernes fra turneringer med åpen påmelding. Grunnen vises for spilleren. Det samme skjer hvis du skriver `"banned": true` (og eventuelt `"ban_reason": "…"`) på brukeren i `users.json`. Utestengelsen gjelder kontoen: spilleren kan fortsatt spille som gjest.
- **Gi en pokal:** velg navn og en pokal (trykk «Ny pokal» til du liker den). Den havner på profilen til spilleren og kunngjøres i chatten. Pokalene ligger under `"trophies"` i `users.json` og kan også endres der.

**Invitasjon:** «Del invitasjon» i venterommet gir en lenke som `https://…/?rom=KXRTA`. Turneringer kan deles med `?turnering=3`.

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

### Hosting fra din egen PC med eget domene

Det går fint, og er en god mellomløsning før en fast server. Anbefalt oppsett: et domene i
**Cloudflare** og en **navngitt Cloudflare-tunnel**. Da trenger du ikke åpne porter i ruteren, du får
HTTPS automatisk, og IP-adressen hjemme vises ikke.

1. Kjøp et domene, f.eks. hos Cloudflare Registrar (ca. 100–150 kr i året for `.com`), eller flytt et
   domene du har til Cloudflare (gratis plan). `.no`-domener kjøpes hos en norsk forhandler, og så settes
   navnetjenerne til Cloudflare.
2. Start spillet med en fast adresse:
   ```
   scripts\online.cmd -Hostname spill.mittdomene.no
   ```
   Første gang åpnes nettleseren, så du kan logge inn hos Cloudflare og velge domenet. Skriptet lager
   tunnelen og DNS-oppføringen selv. Senere starter det bare.
3. Del `https://spill.mittdomene.no`. Adressen er den samme hver gang.

**Ting å tenke på:**
- PC-en må være på og ikke gå i dvale (*Innstillinger → System → Strøm*). Windows-oppdateringer kan starte den på nytt.
- Brukerdataene ligger i `data/` i prosjektmappen. Ta en kopi av mappen av og til.
- Opplastingen hjemme holder i massevis: et parti er noen få kB, og web-klienten (ca. 10 MB komprimert) lastes én gang per besøkende.
- Når du vil ha den alltid på, flytter du til en VPS med Docker (under). Domenet kan du ta med deg.

**Sjekket i runde 10:** web-eksporten bygger, serveren serverer web-klienten med gzip og `/ws`, og en
hel turnering er testet over ekte WebSocket-tilkoblinger (`tests/test_tournament_online.gd`).

**Tester** kjøres lokalt (se «Kom i gang»). Det er ingen automatisk CI på GitHub (fjernet etter runde 12, så det ikke kommer e-post ved hver push).

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

I tillegg er «Må blokkere» og «Ikke gi bort seier» på som standard (litt som i sjakk). De kan slås av når rommet opprettes.

Se også [Plan.md](Plan.md) (planen) og [Fremgang.md](Fremgang.md) (hva som er gjort).
