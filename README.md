# Fire på rad i 3D

Fire på rad på et 3D-brett (4×4×4 eller 5×5×5), laget i Godot 4.7. Spillet kan spilles mot AI (fire vanskelighetsgrader: Lett, Middels, Vanskelig og Ekspert, og en treningsmodus som viser beste trekk, vurderer hvert trekk og lar deg angre), med to spillere på samme enhet eller online mot venner. Det fungerer på PC og mobil (nettleser).

Hvert parti starter med en nedtelling (3, 2, 1). Etter partiet vurderer AI-en trekkene: treffsikkerhet for begge spillerne under resultatet, og i «Se partiet igjen» får hvert trekk en vurdering og et tips, med markøren der brikken heller burde lagt. Under *Innstillinger* velger du brikke, drakt, effekt (tegneserie, cel-shading, skisse, CMYK, akvarell eller glitch, oppå hvilken som helst brikke), merke, seiersanimasjon, brett og bakgrunn (Standard, Nebula, Stjernehimmel eller Kaffebar).

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

**XP og nivåer** (runde 17): kontoer får XP for partier mot andre kontoer (mer for å slå sterkere spillere; minst 10 trekk, høyst 3 partier mot samme motstander per dag og 400 XP per dag fra partier), for dagens oppgave (mer for hver dag på rad), 25 XP for å møte opp til start i en turnering (fra urangerte, private turneringer bare én gang per dag, og ikke til gjester) og for plassering i rangerte turneringer. Partier mot boten gir ikke XP. Nivåene låser opp skins, effekter og seiersanimasjoner. Noen låses bare opp ved å vinne en rangert turnering eller løse dagens oppgave 7 dager på rad, og admin kan sette en premie på en turnering. Reglene står i `core/progression.gd`, og serveren sjekker at andre bare ser det du har låst opp.

På forsiden vises aktive turneringer, **Dagens oppgave** (med toppliste; typen bytter dag for dag mellom «Tving frem seier», «Vinn på N trekk» med stille trekk og «Finn beste trekk»; et feil trekk stopper deg ikke, men spilles ut mot motstanderen, og alle seire innen tre trekk mer enn den raskeste godtas) og en **global chat** med hvor mange som er online. Bak menyen spilles de tre siste partiene på serveren av, ett om gangen. I chatten publiserer serveren også hendelser: nye nivåer, seiersrekker, turneringsvinnere og hvem som løste dagens oppgave. Turneringskamper kan ses på som tilskuer («Se på» på turneringssiden), og alle partier kan ses igjen med tvungne trekk markert («Se partiet igjen» og «Siste partier» på profilen).

**Hvor ligger dataene?** Serveren lagrer alt som lesbare JSON-filer i én mappe:
- Kjører serveren fra prosjektet (`scripts\web.cmd`, `scripts\online.cmd` eller `godot … -- --server`), ligger de i `data/` i prosjektmappen. Mappen er i `.gitignore`.
- I Docker ligger de i volumet `game_data`.
- Annen mappe: `--data <mappe>`.

| Fil | Innhold |
|---|---|
| `users.json` | Brukere: brukernavn, `admin`, `banned`, Elo, statistikk, pokaler, profil og passord-hash (aldri passordet selv) |
| `avatars.json` | Profilbilder. Bildet hører til kontoen, så det er det samme på alle enheter du logger inn fra. Utseendet (brikke, merke, farge, drakt, seiersanimasjon) ligger under `"profile"` i `users.json` og følger også kontoen. |
| `sessions.json` | Innloggede økter (bare en hash av nøkkelen) |
| `tournaments.json` | Turneringer |
| `games.jsonl` | Ett ferdig parti per linje, med trekk og analyse (brukes til repriser) |
| `puzzles.json` | Dagens oppgave og hvem som har løst den, de siste 14 dagene |
| `global_chat.json` | De siste 50 meldingene og hendelsene per kanal i den globale chatten |
| `feedback.jsonl` | Alt som skrives i chatkanalen «Innspill», én melding per linje (til admin) |

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

**Turneringer:** admin lager dem i spillet under *Spill online → Turneringer → Ny turnering*. Velg navn, dag og klokkeslett med pilene (eller 18:00–21:00 med ett trykk), format, antall deltakere og pokalen vinneren får («Ny pokal» trekker en ny). Beskrivelse, regler, klokke, pauser og møtefrist ligger under «Flere valg». Den neste turneringen med åpen påmelding reklameres i hovedmenyen med «Meld meg på». Når en kamp starter, får begge varselet «Gå til kamp». Den som ikke møter innen fristen, taper på walkover. Deltakerne ser sin egen kamp øverst på turneringssiden og er markert i turneringstreet. Treet har pokalen i midten (på smale skjermer går det fra venstre mot høyre med pokalen over finalen), og kamper som spilles nå kan trykkes på for å se på. Siden oppdateres med en gang noe skjer. Vinneren får pokalen på profilen sin, og den siste vinneren vises i hovedmenyen. Admin kan bytte pokal på turneringssiden («Ny pokal») før turneringen starter. En turnering kan være uranket («Rangert» av): da endres ikke Elo, og den vises ikke i hovedmenyen, kunngjøres ikke og kommer ikke i hall of fame. «Pokal til vinneren» kan også slås av. Turneringssiden har det som skjer nå øverst (nedtellingen eller innsjekken, påmeldingen, din kamp og treet eller tabellen), så turneringschatten, og under den kampene, deltakerne, reglene (bak «Regler») og «Legg i kalender» (kalenderfil fra `/kalender/<id>.ics`). Når kampen starter, kastes spillerne rett inn i rommet, og venterommet teller ned til walkover. I turneringskamper ser ikke spillerne det tilskuerne skriver, bare reaksjonene deres. Turneringslisten har en hall of fame med vinnerne av rangerte turneringer. Urankede turneringer vises også i hovedmenyen med påmelding, og den du er påmeldt står øverst med nedtelling. I pausen mellom rundene kan begge trykke «Klar» for å starte neste kamp med en gang. Den globale chatten får en «Turnering»-fane når du er påmeldt eller en turnering pågår.

**Innsjekk før start:** de siste 2 minuttene før start åpnes turneringssiden hos alle påmeldte (et banner med «Se» hvis de er midt i et parti), med stor nedtelling og turneringschatten. Den som har siden oppe, er sjekket inn. Bare de er med når oppsettet trekkes. De andre er ute før start og får beskjed, så ingen vinner på walkover mot folk som aldri kom. Faller man ut underveis, kan man komme tilbake: kobler man til igjen eller logger inn, kastes man rett inn i kampen som venter. Begynner innsjekken for sent (serveren var nede over starttiden), flyttes starten så alle får hele tiden. Man kan ikke se på sitt eget parti som tilskuer (samme konto i en annen fane ville gitt stillingsmåleren og «vinner om 3 trekk»).

**Formatene:**
- **Utslag:** seedet etter Elo. Uavgjort spilles om, og blir også tredje parti uavgjort, går den som ikke startet det, videre.
- **Alle mot alle:** avgjøres aldri av Elo. Første runde trekkes tilfeldig, og hvem som starter, fordeles jevnt.
  - Med færre runder enn alle møter alle er det sveitsisk system: hver runde settes opp etter tabellen, så like mange poeng møtes, og ingen møtes to ganger.
  - Seier gir 1 poeng, uavgjort ½ og fri runde 1.
  - Likt antall poeng avgjøres av innbyrdes oppgjør, Buchholz, Sonneborn-Berger og flest seire. Er det fortsatt helt likt om førsteplassen, spilles omkamp.
  - Står to uten motstander fordi motstanderne ikke møtte, spiller de mot hverandre i stedet for å vinne på walkover.

**Private turneringer (en kveld med venner, på jobben, i klubben):**
- **Arrangør:** alle med konto (ikke gjester) kan lage private turneringer under *Turneringer → Ny turnering*. Den som lager turneringen, er arrangøren og styrer den. Høyst to om gangen kan være uferdige. Admin lager også offentlige turneringer og styrer alle.
- **Privat:** turneringen er skjult for andre og alltid urangert. «Start nå» begynner innsjekken (2 minutter). Er alle der allerede, starter den med en gang, og ellers så snart alle har kommet. Arrangøren kan også trykke «Start med dem som er her».
- **Bli med:** deltakerne kommer inn med lenken `/?t=KODE`, QR-koden på storskjermen eller «Har du en kode?» i turneringslisten. Uten konto skriver man bare et kallenavn og trykker «Bli med». Serveren lager da en gjestekonto, og nettleseren husker den.
- **Gjestekontoer:** ingen passord, bilde, venner eller XP. De kan bare skrive i turneringschatten og bare spille i turneringen. Er navnet tatt, får det et tall bak. De slettes etter 14 dager uten bruk, men navnet blir stående i turneringen.
- **Grenser og IP:** det er ingen grenser per IP, så alle på samme nett kan være med. Det kan lages høyst 200 nye gjestekontoer i timen totalt.
- **Arrangøren kan:**
  - kopiere lenken;
  - rette kallenavnet til en gjest;
  - fjerne en deltaker før start;
  - slå av chatten for deltakerne.
- **Storskjerm:** åpnes med «Vis på storskjerm», eller med lenken `/?vis=KODE` på en TV eller prosjektor (uten innlogging).
  - **Før start:** QR-kode og lenke, og deltakerne etter hvert som de kommer.
  - **Innsjekken:** nedtellingen og hvem som er her (de som ikke er kommet, er dempet).
  - **Underveis:** bare turneringstreet (eller tabellen og rundens kamper) over hele skjermen.
  - **Finalen:** det eneste partiet som vises. Brettet står midt på skjermen med navnene og stillingsmåleren over.
  - **Til slutt:** vinneren med pokalen over brettet, som spiller av finalen, og pallen under.
  - QR-koden lages i spillet (`core/qr_code.gd`, uten eksterne biblioteker).

**Venner:** *Venner* (i hovedmenyen ved profilbildet, eller i *Spill online*) krever konto. Søk etter spillere (treff mens du skriver) og trykk «Legg til». Den andre får en forespørsel og godtar. Nye forespørsler gir en rød prikk med antallet på «Venner». Trykk på et navn (i chatten, «hvem er online», topplisten, søket eller vennelisten) for å se profilen, med «Legg til venn» rett der. En venn fjernes fra profilen hens («Fjern venn», trykk to ganger), ikke fra listen, så ingen kommer bort i det. Listen viser hvem som er online og hvem som spiller (med «Se på»). «Utfordre» lager et privat rom og inviterer vennen, og i venterommet kan du invitere venner med «Inviter en venn». Vennen får et banner med «Bli med». Vennene ligger under `"friends"` og `"friend_requests"` i `users.json`.

**Chatkanaler:** den globale chatten har kanalene «Generelt», «Velkommen» (nye kontoer ønskes velkommen her) og «Innspill» (lagres også i `feedback.jsonl`). Kunngjøringer vises i alle kanalene.

**Chat på mobil:** i nettleseren på telefon er chatfeltet et ekte HTML-felt som ligger over spillets felt (`client/ui/web_text_field.gd`). Da virker tastaturet, markering, autokorrektur, lim inn og emojier som på vanlige nettsider, og tastaturet blir stående når du sender. På iPhone flyttes feltet ut av skjermen idet du trykker, og settes tilbake når spillet har lagt seg over tastaturet, så Safari ikke ruller siden opp (samme grep som Flutter bruker). Emojiene vises i farger med fonten Twemoji (`assets/fonts/`, Twemoji-grafikken er CC BY 4.0, se `assets/fonts/LICENSE-Twemoji.txt`).

**Admin-siden** (knappen «Admin» ved profilbildet i hovedmenyen, bare for admin):
- **Kunngjøring:** vises som et banner hos alle som er online, og blir stående i den globale chatten.
- **Utesteng / opphev:** en utestengt konto kan ikke logge inn, kastes ut hvis den er online og fjernes fra turneringer med åpen påmelding. Grunnen vises for spilleren. Det samme skjer hvis du skriver `"banned": true` (og eventuelt `"ban_reason": "…"`) på brukeren i `users.json`. Utestengelsen gjelder kontoen: spilleren kan fortsatt spille som gjest.
- **Gi en pokal:** velg navn og en pokal (trykk «Ny pokal» til du liker den). Den havner på profilen til spilleren og kunngjøres i chatten. Pokalene ligger under `"trophies"` i `users.json` og kan også endres der.

**Invitasjon:** «Del invitasjon» i venterommet gir en lenke som `https://…/?rom=KXRTA`. Turneringer kan deles med `?turnering=3`.

## Bygge og hoste

**Web-klienten** krever at Godot har eksportmaler: *Editor → Manage Export Templates → Download*. Deretter:

```
scripts\web.cmd export
```

Det eksporterer til `build/web` og kjører `scripts/pack_web.ps1` etterpå (runde 19). Skriptet legger emojiskriften ved siden av spillet (`emoji.ttf`, den er ikke med i spillpakken), og komprimerer `index.wasm` med brotli hvis `brotli` finnes (det følger med Git for Windows). Eksporterer du med `godot --export-release "Web"` direkte, mangler `emoji.ttf`, og emojier i chatten blir firkanter.

**Lastetid (runde 19):**
- Første besøk laster ca. 7,7 MB i stedet for 11,7 MB: `index.wasm` med brotli (6,9 MB, mot 10,1 MB med gzip) og spillpakken (0,7 MB, før 1,5 MB). Emojiskriften (0,7 MB) hentes når spillet har startet.
- Serveren gir hver fil ETag og dato. Neste besøk spør nettleseren bare om filene er endret og får «304», så ingenting lastes ned på nytt. Nettleseren kan da også bruke den ferdig kompilerte `index.wasm` fra forrige gang.
- `index.wasm` komprimeres bare på nytt når Godot er oppdatert (det tar 1–2 minutter). Ellers gjenbrukes `index.wasm.br`.

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
- Opplastingen hjemme holder i massevis: et parti er noen få kB, og web-klienten (ca. 8 MB komprimert) lastes én gang per besøkende.
- Når du vil ha den alltid på, flytter du til en VPS med Docker (under). Domenet kan du ta med deg.

**Sjekket i runde 10:** web-eksporten bygger, serveren serverer web-klienten med gzip og `/ws`, og en
hel turnering er testet over ekte WebSocket-tilkoblinger (`tests/test_tournament_online.gd`).

**Stresstest av en turnering** (påvirker ikke serveren på nett: egne porter og egen datamappe):
```
godot --headless --path . -- --server --port 9080 --web build/web --web-port 9000 --data build/stresstest
godot --headless --path . --script res://tools/stress_tournament.gd -- --url ws://127.0.0.1:9080 --data build/stresstest --players 32
```
32 boter registrerer seg, melder seg på og spiller en hel utslagsturnering. Følg med på `http://localhost:9000/?turnering=1`. Til slutt skrives svartider og antall partier. `--level easy` gir raske boter, så svartiden måler serveren og ikke botene. Se også `--signup`, `--delay` og `--report`.

**Boter mot boter** (måler AI-en: seiersprosent som starter og ikke, og tenketid per trekk):
```
godot --headless --path . -s res://tools/ai_arena.gd -- 4 20 vanskelig gammel
godot --headless --path . -s res://tools/ai_arena.gd -- 4 12 dybde:4,parity_w=0 dybde:4
godot --headless --path . -s res://tools/ai_arena.gd -- 5 8 ekspert vanskelig free
```
Argumentene: brettstørrelse, partier per farge, bot A og bot B (lett, middels, gammel = Vanskelig før runde 16, vanskelig, ekspert, `søk:<ms>` eller `dybde:<n>`, med vekter etter komma), og `free` for å slå av «må blokkere» og «ikke gi bort seier». Hver bot starter halvparten av partiene.

**AI-analysen** (treffsikkerheten etter partiet) måles med `tools/review_check.gd`: botene spiller, og analysen skal gi den sterke boten høy treffsikkerhet og den svake lav:
```
godot --headless --path . -s res://tools/review_check.gd -- 4 4 ekspert lett
```

**Oppgavebankene** lages på forhånd, fordi de krever tunge søk. Fra runde 19 må alle oppgavene gå i flere plan (ikke bare et vanlig firepårad i én høyde), og verktøyene beholder det som allerede ligger i banken og passer.

- Dagens oppgave (`ai/daily_bank.gd`): «Tving frem seier», «Vinn på N trekk» og «Finn beste trekk». Argumentene er antall av hver type, prosesser som leter samtidig, en tidsfrist i minutter (med tidsfrist letes det til halvparten av «Vinn på N trekk» er uten trikset med tre trekk i samme kolonne) og antall «Tving frem seier». Med 5 prosesser tok det rundt en time:
  ```
  godot --headless --path . -s res://tools/make_daily_bank.gd -- 30 5 75 120
  ```
- «Flere oppgaver» (`ai/puzzle_bank.gd`, 20 per nivå): noen minutter.
  ```
  godot --headless --path . -s res://tools/make_puzzle_bank.gd
  ```

**Tester** kjøres lokalt (se «Kom i gang»). Det er ingen automatisk CI på GitHub (fjernet etter runde 12, så det ikke kommer e-post ved hver push).

## Mappestruktur

```
core/      Regelmotoren: GameOptions, GameState, Lines, ChessClock (ren logikk), EloTiers og Progression (XP og opplåsing)
ai/        Bot og BotProfile (vanskelighetsgrader), SearchBot (søket til Vanskelig og Ekspert), MoveReview (AI-analysen),
           LiveEval (stillingsmåleren og treningen), Puzzle og oppgavebankene
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
