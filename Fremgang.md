# Fremgang / Logg

## Runde 1 – Gjennomgang og plan

- Gikk gjennom hele workspacet og skrev [Plan.md](Plan.md).
- Fant blant annet disse feilene:
  - To regelmotorer (Python og GDScript) som oppførte seg ulikt.
  - Falsk seier på 5×5×5.
  - Regler som kunne låse spillet.
  - Uavgjort manglet.
  - Bare musestyring.
  - En renderer som ikke virker på web.

## Runde 2 – Prototype (fase 0–5)

**Avklart:**
- Tid ute = tap.
- 5×5×5 spilles med fire på rad.
- Kallenavn holder foreløpig (passord senere).
- Python-koden er slettet.
- Godot-prosjektet ligger nå i roten av repoet.
- Hosting: én VPS med Docker.

### Ferdig

| Fase | Hva | Status |
|---|---|---|
| 0 | Opprydding: Godot i roten, `.tmp`-filer, Python og gammel `frontend/` fjernet. Compatibility-renderer, eksportprofiler (Web, Server, Windows) og CI. | ✅ |
| 1 | Regelmotor `core/`: linjetellere, 76/302 vinnerlinjer, regelprioritet, uavgjort, sjakkur | ✅ |
| 2 | Brett generert i kode (4×4×4 og 5×5×5), spøkelsesbrikke, fall-animasjon, mus og touch (to trykk for å legge), knip-zoom, lokalt spill | ✅ |
| 3 | AI portet fra `SimpleBot`: Lett, Middels, Vanskelig | ✅ |
| 4 | Meny med demo-parti i bakgrunnen, spilloppsett, innstillinger, 8 skins, lyd laget i kode. Seierseffekt: rist, gnister, glød, sakte film, blink og vibrasjon. | ✅ |
| 5 | Server (lobby, rom med kode, offentlige og private rom, klar-knapp, chat, klokke, rematch, gjenkobling i 60 s) og online-skjermer | ✅ |
| 6 | Docker, Caddy og CI er skrevet, men ikke satt i drift (trenger VPS og domene) | ⏳ |

### Tester

50 automatiske tester, alle grønne (`godot --headless --path . res://tests/run_tests.tscn`, ca. 20 s):

| Fil | Tester | Dekker |
|---|---|---|
| `test_rules.gd` | 23 | Alle 13 retninger, 5×5×5-hullet, uavgjort, begge regler, «aldri låst» (80 tilfeldige partier med begge regler på), angre, klokke |
| `test_bot.gd` | 7 | Vinner og blokkerer, finner tvungen seier fra den gamle notebooken, gjør aldri ulovlige trekk. Vanskelig vant 6–0 mot både Lett og Middels. |
| `test_lobby.gd` | 15 | Rom, koder, trekkvalidering, tid ute, gi opp, rematch, chat-begrensning, gjenkobling, søppel-input |
| `test_online.gd` | 1 | Ekte WebSocket-server og et helt parti med chat, mellom en testklient og spillets egen klient |
| `test_client.gd` | 4 | Går gjennom alle skjermer: AI-parti til slutt, touch-trykk på 5×5×5, og online fra lobby via venterom til parti |

### Målinger og funn

- **AI-hastighet:**
  - Første port brukte opptil 4,7 s på et trekk.
  - Med en hurtigsjekk («kan dette trekket i det hele tatt lage en trussel?») og hurtigbuffer i søket etter tvungen seier er tregeste trekk nå ca. 225 ms på PC.
  - Botens styrke ble ikke påvirket.
- **Valg som ble endret fra planen:**
  - **Tester:** en liten egen testløper i stedet for GUT. Den har ingen avhengighet, fungerer med Godot 4.7, og regner skriptfeil som feilet test.
  - **UI-skalering:** stretch-modus «disabled» med egen skalering. 3D tegnes da i full oppløsning, og UI-et tilpasses mobil og PC.
  - **Skins:** en enkel liste i `client/skins.gd` i stedet for egne Resource-filer.

### Kjente begrensninger og neste steg

- [ ] **Teste web-bygget på ekte telefon** (iPhone Safari og Android Chrome).
  - Krever eksportmalene (*Editor → Manage Export Templates*).
  - Følg med på AI-hastigheten på mobil. Hvis den hakker, del søket over flere frames.
- [ ] **Sette i drift:** skaff en VPS og et domene, og kjør `deploy/docker-compose.yml` (se README).
- [ ] **Passord og kontoer** (fase 8 i planen).
- [ ] **Ekspert-AI** (alfa-beta), angre-knapp mot AI, P2P (valgfritt).
- [ ] Brettet roterer med én finger og zoomer med knip. Tofinger-panorering finnes ikke.
- [ ] Mappen `frontend/` inneholder bare en gammel `.godot`-cache som Git ignorerer. Den kan slettes.

## Runde 3 – Brett, plassering, utseende og wifi-spill

### Gjort

| Ønske | Løsning |
|---|---|
| Ingen pinner, enkelt brett | Flat, firkantet plate med avrundede hjørner (`client/board/board_mesh.gd`). Rutenettet og svake «sokler» tegnes i en shader med lav kontrast (`assets/shaders/board_top.gdshader`). |
| Velge rett på flaten | Hver kolonne har en flat klikkflate der neste brikke lander, altså på ruten eller på toppen av den øverste brikken. Brikkene har i tillegg egne kollisjonsformer, så et trykk på siden av en brikke velger kolonnen den står i. Sjekket med skjermbilder: alle fire testpunkter traff riktig kolonne. |
| Diskré hover-indikator | En tynn, pulserende ring i spillerens farge der brikken vil lande. På touch viser første trykk ring og gjennomsiktig brikke, og andre trykk legger brikken. |
| Tydeligere knapper og farger | Nytt tema: knappene er lysere enn panelene og har kant og svak skygge. Primærknappen er dempet blå, og valgt alternativ er tydelig fylt. Tynnere scrollefelt. |
| Mindre mettet | Aksentfarger, lys, glød og blink er dempet. Den blå neonkanten på brettet er fjernet. Brikkene har fortsatt sterke farger. |
| Gradient-bakgrunn | Rolig vertikal gradient med en svak lysflekk og dithering mot striper (`assets/shaders/background.gdshader`, tegnet bak 3D med `BG_CANVAS`). |
| «Gi opp» etter seier | «Meny» viser resultatet (spill igjen / hovedmeny) når partiet er ferdig, og pausemenyen bare under partiet. Har egen test. |
| Spill over wifi | Serveren kan servere web-klienten selv (`--web build/web`) og skriver ut adressen man åpner på telefonen. Klienten finner spillserveren automatisk. Se README. |
| PC-en ble treg | Serveren begrenses nå til 60 bilder/s (gikk før så fort den kunne). Jeg kjører tester og vinduer med lav prioritet. |

### Svar: kan jeg hoste lokalt så vi kan spille over wifi?

Ja. Lag web-bygget én gang, og kjør så `godot --headless --path . -- --server --web build/web`. Åpne adressen den skriver ut (f.eks. `http://192.168.1.23:8000`) på telefonen. Første gang må du tillate Godot i Windows-brannmuren for private nettverk. Detaljer står i README under «Spille over wifi».

### Tester

54 tester, alle grønne. Nytt i denne runden:
- `test_web_server.gd`: filserveren serverer riktig, store filer kommer frem i sin helhet, og man kan ikke lese filer utenfor mappen.
- En test for at menyen etter partiet ikke viser «Gi opp».

### Neste steg

- [ ] Prøve wifi-spill på ekte telefon (krever eksportmalene).
- [ ] Gjenstående fra runde 2: drift på VPS, passord, Ekspert-AI.
- [ ] Til senere: turneringsmodus (se Plan.md, fase 9).

## Runde 4 – Rutenett, lys, profilbilde og feilretting

### Gjort

| Ønske | Løsning |
|---|---|
| Rutenett uten ytterkant, uten sirkler, tykkere med avrundede ender | Shaderen tegner bare de indre linjene (3 + 3 på 4×4, 4 + 4 på 5×5). Linjene er tykkere og har runde ender. Sirklene er fjernet. |
| Mindre kontrast i skyggene | Svakere sollys, mer omgivelseslys, og skyggene er halvveis gjennomsiktige (`shadow_opacity`). |
| Profilbilde | «Innstillinger → Profilbilde → Velg bilde…». Bildet beskjæres til et lite, rundt JPEG (112 px, ca. 5–8 KB) og vises i menyen, venterommet og på spillerkortene. Uten bilde vises forbokstaven. Serveren sjekker at det er et gyldig, lite bilde før det deles. |
| Lysere bakgrunn | Gradienten er løftet merkbart. |
| Av/på-bryteren er vanskelig å se | Nye bryterikoner: av = grå med lys knott til venstre, på = blå med hvit knott til høyre. |
| Feil ved «Opprett rom» | **Årsak:** lobbyskjermen ga oppsettet en funksjon som hørte til seg selv. Lobbyen ble slettet da oppsettet ble vist, så funksjonen pekte på et objekt som ikke fantes. «Endre regler» i venterommet hadde samme feil. **Løsning:** handlingene ligger nå i `ClientRoot`, som lever hele tiden. En ny test går hele veien gjennom skjermene. |
| Skrive `godot` | Kortnavn i PowerShell-profilen. Se README, «Skrive godot i stedet for hele stien». |
| Teste på telefon i Chrome | Se README, «Spille over wifi» → «Teste på telefon». |

### Annet

- `build/.gdignore` gjør at Godot ikke importerer filene i web-bygget som ressurser. Eksportprofilene utelater også `build/`, så bygget ikke havner i neste bygg.
- Testene skriver aldri til de ekte innstillingene dine (`Settings.persist = false` under testing).
- 58 tester, alle grønne.

### Etter runde 4: «Secure Context»-feil på telefon

- **Årsak:** Godot-spill i nettleseren krever en sikker adresse, altså `https` eller `localhost`. `http://192.168.x.x:8000` er ikke sikker, så spillet nekter å starte. Det er en regel i nettleseren og kan ikke skrus av i spillet.
- **Endring:** serverens web-del sender nå WebSocket på `/ws` videre til spillserveren, så web-siden og spillet deler port 8000. Klienten kobler alltid til samme adresse som siden + `/ws`. Det er testet med en ekte WebSocket-tilkobling.
- **Slik spiller du nå:** `localhost` via Chromes port-videresending over USB (egen telefon), eller en gratis HTTPS-tunnel med `cloudflared` (venner, også over mobilnett). Se README.
- **Oppfølging:** HTTPS lokalt, uten kabel. `--https` gjør at serveren selv kjører HTTPS med sertifikatet fra local-ip.sh, som hentes automatisk. Alle på samme wifi, også iPhone, åpner `https://<PC-ens IP med bindestreker>.local-ip.sh:8000`. Testet med curl: sertifikatet godtas, og hele web-bygget lastes. HTTPS i filserveren har også en egen test.

### Spill med venner over internett: `scripts\online.cmd`

- Ett skript eksporterer spillet, starter serveren og en gratis Cloudflare-tunnel, og kopierer adressen (`https://….trycloudflare.com`) til utklippstavlen.
- **Testet over den ekte tunnelen:** nettsiden svarte 200, spillfilen ble lastet komprimert (10,1 MB i stedet for 39,5 MB, 4,5 s), og WebSocket koblet opp (`101 Switching Protocols`).
- Serverens filserver komprimerer nå `wasm`, `js` og `pck` med gzip (beregnes én gang og holdes i minnet). Det har egen test.
- Hjelpeskript: `scripts\web.cmd` (eksport + server med HTTPS på wifi) og `scripts\online.cmd` (eksport + server + tunnel).

## Runde 5 – Språk, mobil, hurtigmeldinger og skins

| Ønske | Løsning |
|---|---|
| Engelsk og norsk | *Innstillinger → Språk*: Automatisk (følger enheten), Norsk eller English. All tekst i UI-et er oversatt (`client/i18n.gd`), også meldinger fra serveren. En test sjekker at ingen tekst mangler engelsk. |
| Chatten over tastaturet (mobil) | Når et tekstfelt har fokus og skjermtastaturet er oppe, krymper UI-et nedenfra, så chatten og tekstfeltet havner over tastaturet. I lister rulles feltet frem. |
| Markere hele navnet | Tekstfeltene markerer all tekst når du trykker i dem, og har en x-knapp som tømmer feltet. |
| Egne hurtigmeldinger | *Innstillinger → Hurtigmeldinger i chatten*: opptil 6 egne meldinger. «Tilbakestill» gir standardmeldingene på valgt språk. |
| Hjemme- og bortedrakt | Hver skin har to drakter. Har begge samme skin, bruker spiller 2 (gjesten online) bortedrakten. Begge klientene regner likt, og en test sjekker at alle kombinasjoner av skins er lette å skille. |
| Metall og «heftige» shadere | 12 skins: Havblå, Glør, Lime (glatt med gradient), Gull og Krom (metall), Galakse (blinkende stjerner), Lava (glødende sprekker som beveger seg), Neon (lysende kanter), Holografisk (perlemor-regnbue), Marmor, Karbon og Racing (striper). |
| Merker | Stjerne, prikk, ring, kryss, diamant og hjerte på toppen av brikken. |
| Seiersanimasjoner | Klassisk, fyrverkeri, konfetti, sjokkbølge (de andre brikkene hopper) og lyn. Vinnerens valg vises, også for motstanderen online. |
| Forhåndsvisning | Innstillingene viser en roterende 3D-forhåndsvisning av hjemme- og bortedrakten. Skin-knappene har gradient-ikoner. |

**Testet:**
- 70 automatiske tester, alle grønne.
- Skjermbilder av alle skins, de nye seiersanimasjonene og innstillingene på norsk og engelsk.
- Etter skjermbildene ble neon, holografisk og den myke toon-skyggen justert.

**Ikke testet:** tastaturhåndteringen på ekte telefon. Den bruker nettleserens `visualViewport` og kan trenge justering på iPhone.

## Runde 6 – Kontoer, statistikk, Elo og turneringer

| Ønske | Løsning |
|---|---|
| Scrolling i innstillinger hopper (PC) | Hvert hakk på musehjulet scroller nå 48 px (før en åttendedel av skjermen). |
| Holografisk: hjemme og borte like, og en «søm» | Drakten styrer fargene: hjemme er rosa/gull, borte er cyan/fiolett. Sømmen var et hopp i vinkelen rundt brikken (fra +180° til −180°). Shaderen bruker nå sin/cos av vinkelen, så den er borte. |
| Konto med brukernavn og passord | Registrering og innlogging under *Spill online*. Passord lagres bare som PBKDF2-hash (60 000 runder, testet mot standard testvektorer). Innloggingen huskes. Passord sendes bare over sikker forbindelse (https/wss) eller til localhost. Etter 5 feilforsøk må man vente 10 minutter. |
| Stats | Partier, seire, tap og uavgjort, vinnerprosent, rekker, raskeste seier, **tvungne trekk**, **doble trusler**, **lengste tvungne seier**, seire på tid/ga opp/walkover og turneringer vunnet. Profilskjerm og toppliste. Hvert parti lagres i `games.jsonl` med trekk og analyse. |
| Elo | Start 1200, K = 32, bare når begge spillerne er innlogget. Vises i lobbyen, på spillerkortene, i venterommet og som endring på resultatskjermen («Elo 1200 → 1216 (+16)»). |
| Turneringer | Admin lager dem i spillet (format, regler, klokke, maks deltakere, starttid eller klokkeslett, pause og møtefrist). Påmelding og oppsett etter Elo. Hver kamp får et låst privat rom og varselet «Gå til kamp». Walkover for den som ikke møter, omspill ved uavgjort i utslag, tabell i alle-mot-alle. Overlever omstart av serveren. |
| Brukerdata i JSON som er lett å endre | `data/users.json` (og `avatars.json`, `sessions.json`, `tournaments.json`, `games.jsonl`). Sett `"admin": true` på en bruker og lagre, så laster serveren filen inn på nytt innen ett sekund. Glemt passord: `"reset_password": "nytt-passord"`. Ugyldig JSON ødelegger ingenting. |
| Punkter fra planen | Invitasjonslenke (`?rom=…`, `?turnering=…`, del-meny på mobil), lagring (13.1), kontoer (13.3), statistikk (13.4) og turneringer (13.5). Status og hva som gjenstår står i Plan.md under fase 8–11. |

**Testet:**
- 88 automatiske tester, alle grønne. Nye tester dekker:
  - PBKDF2-testvektorer,
  - redigering av `users.json` mens serveren kjører,
  - nytt passord via `users.json`,
  - begrensning på innloggingsforsøk,
  - Elo og statistikk etter et parti,
  - analyse av tvungne trekk og doble trusler,
  - et helt utslag med walkover og finale,
  - omspill ved uavgjort, alle-mot-alle med tabell, og lagring over omstart,
  - en røyktest av konto-, profil- og turneringsskjermene mot en ekte server.
- Skjermbilder av holografisk skin, lobbyen, profilen og turneringssiden.

**Merk:** brukerdataene havner i `data/` i prosjektmappen når serveren kjøres derfra. Mappen er i `.gitignore`, så passord-hasher og statistikk aldri kommer i git.

## Runde 7 – Mer customization, forhåndsvisning og regler på som standard

| Ønske | Løsning |
|---|---|
| Scroll i innstillinger hopper fortsatt | Grunnen var at Godot scroller en åttendedel av det synlige området per hakk, uansett innstilling. Nå tar UI-et selv imot musehjulet: hvert hakk scroller 70 px med en kort, myk overgang (`UI.smooth_scroll`). Det gjelder alle skjermer med scroll. |
| Innstillinger på siden, brettet som forhåndsvisning | Kortet står til venstre på PC og nederst på mobil. Brettet ved siden av viser dine brikker i hjemmedrakt mot bortedrakt, og endres med en gang du velger skin, merke eller merkefarge. «Vis seiersanimasjonen» spiller av valgt animasjon på brettet (også når du bytter animasjon). |
| «Må blokkere» og «Ikke gi bort seier» på som standard | Begge er på i nye partier, rom og turneringer. Lagrede innstillinger fra før blir slått på én gang. De kan fortsatt slås av i oppsettet. |
| Flere skins, «overrask meg» | 8 nye skins: **Nordlys** (bølgende lysbånd), **Is** (frostede fasetter med glimt), **Eik** (årringer), **Keramikk** (matt glasur med prikker), **Glass**, **Kobber** (med grønn patina), **Solnedgang** og **Midnatt** (marine med gullstriper). 5 nye merker: sekskant, måne, krone, lyn og pil. Ny **merkefarge**: automatisk, hvit, svart, gull eller draktfarge. 2 nye seiersanimasjoner: **Supernova** (lyskule som vokser og eksploderer) og **Glitter** (gull- og sølvdryss). 5 **brett-temaer**: skifer, eik, lys stein, midnatt og filt. |
| Se motstanderens skin før start | Venterommet viser begge brikkene slik de blir i partiet. Har dere lik farge, ser du at gjesten får bortedrakt. Med «Bytt skin» velger du ny skin der og da, og motstanderen ser byttet med en gang (ny melding `set_look`). |
| Decal styrt av Elo (til senere) | Lagt i Plan.md under fase 7 som idé. |

**Også fikset:** merkene sto opp ned sett fra spillerens side (hjertet så ut som en spar). Nå står alle rett vei.

**Testet:**
- 92 automatiske tester, alle grønne. Nye eller endrede tester:
  - reglene er på som standard,
  - `set_look` når motstanderen i venterommet,
  - brett-temaer og merkefarger,
  - innstillingsskjermen: demo-stilling, bortedrakt, brett-tema og forhåndsvisning av supernova og glitter,
  - venterommet viser motstanderen, og skin-bytte går via serveren.
- Testene som spiller en rask vinnersekvens, slår nå reglene av eksplisitt.
- Skjermbilder av alle skins og merker, innstillinger liggende og stående, brett-temaer, supernova, glitter og venterommet.

## Runde 8 – Turneringer på forsiden, flere skins og Elo-merker

| Ønske | Løsning |
|---|---|
| Aktive turneringer på forsiden | Menyen tar en kort «titt» på serveren og viser turneringer som pågår eller er åpne for påmelding, med pågående først (de pulserer svakt). Trykk åpner turneringen, og «Tilbake» går til menyen igjen. Svarer ikke serveren, gir menyen opp med en gang i stedet for å prøve igjen og igjen. Er du innlogget, får du også «Gå til kamp»-varselet mens du står i menyen. |
| Flere skins, rå og kreative | 10 nye, alle laget i shaderen: **Plasma** (elektriske buer), **Kintsugi** (svart eller hvit keramikk med gull i sprekkene), **Damaskus** (smidd stål med bølgende lag), **Kretskort** (baner med lyspulser), **Disco** (speilfliser som blinker), **Opal** (fargespill som flytter seg med blikket), **Piksel** (8-bit-klosser), **Kode** (fallende tegn), **Giftig** (selvlysende slim med bobler) og **Sort hull** (virvlende lysring på toppen). 30 skins totalt, og rutenettet i innstillingene er gjort mer kompakt (5 per rad). |
| Elo-merker ved spillernavn | 7 nivåer: Bronse, Sølv, Gull, Platina, Diamant, Mester og Stormester. Merkene tegnes i kode og vises i menyen, lobbyen, venterommet, på spillerkortene i partiet, på profilen (stort, med hvor mye som mangler til neste nivå), i topplisten og på turneringssiden. Resultatskjermen sier «Nytt nivå: Gull!» når du rykker opp. |

**Testet:**
- 95 automatiske tester, alle grønne. Nye tester:
  - Elo-nivåer og -merker (grensene, at bildene tegnes og caches, og at gjester ikke får merke),
  - romlisten har Elo bare for kontoer,
  - forsiden viser aktive turneringer i riktig rekkefølge og skjuler ferdige,
  - menyen gir opp når serveren ikke svarer.
- Skjermbilder av menyen med turneringer, alle de nye skinsene (hjemme og borte), merkene, profilen, venterommet og innstillingene. Damaskus ble justert etter første bilde (mønsteret var for grovt).

**Forslag til videre utvikling:** se Plan.md, seksjon 14.

## Runde 9 – Repriser, tilskuere, Elo-merker på brikken, dagens oppgave og global chat

| Ønske | Løsning |
|---|---|
| Repriser med tvungne trekk markert | «Se partiet igjen» på resultatskjermen (alle moduser, også mot AI). Avspilleren har hopp, fram/tilbake, spill av og en tidslinje i spillernes farger. Prikker viser tvungne trekk (oransje), doble trusler (rød) og vinnertrekket (gull). På brettet vises plassen motstanderen må blokkere, og en tekst forklarer trekket. Profilen har «Siste partier» fra serveren, som kan ses igjen på samme måte. |
| Tilskuere på turneringskamper | «Se på» ved kamper som spilles på turneringssiden. Tilskuere ser trekk, chat og resultat i sanntid, men kan ikke spille. Spillerne ser hvor mange som ser på. «Tilbake til turneringen» tar deg tilbake. |
| Merker på brikken låst av Elo | Nivåene er flyttet til `core/elo_tiers.gd`, og serveren sjekker merket (låste merker vises som «ingen» for motstanderen). Innstillingene viser låste merker grået ut med nivå-merket som trengs. To nye merker: **Flamme** (Mester) og **Laurbær** (Stormester). Klienten husker siste Elo, så merkene virker også uten nett. |
| Dagens oppgave (finn seieren i 3+ trekk) | Serveren lager én stilling per dag ut fra datoen (`ai/puzzle.gd`). Spilleren som har tur kan tvinge frem seier med 3 eller 4 trekk, men ikke raskere. Motstanderen forsvarer seg så godt den kan, og glipper seieren, kommer «Prøv igjen». «Vis løsning» spiller den av. Serveren sjekker løsningen ved å spille den på nytt, fører listen over dagens løsere og topplisten (løste oppgaver og rekke). Uten nett lages samme oppgave lokalt. |
| Antall online og global chat i menyen | Chatten står alltid i menyen (nede til høyre på PC, øverst på mobil), med «12 online · 4 spiller nå». Serveren publiserer hendelser der: velkommen til nye kontoer, nytt Elo-nivå, seiersrekker (5, 10, …), seire med 3+ tvungne trekk på rad, turnering startet og vunnet, og hvem som løste dagens oppgave. De siste 50 meldingene lagres. |

**Også fikset:** på Windows kunne et tilkoblingsforsøk til en server som ikke svarer henge i over 12 sekunder. Nå gir klienten opp etter 5 sekunder, så menyen viser «Frakoblet» i stedet for å stå på «Kobler til…». Protokollen er nå versjon 3, så gamle nettleserfaner blir bedt om å laste siden på nytt.

**Testet:**
- 110 automatiske tester, alle grønne. Nye tester:
  - oppgaven er lik hele dagen, har tvungen seier i minst 3 trekk og ingen raskere, og godtar bare riktige løsninger (også etter JSON),
  - forsvareren er forutsigbar,
  - tidslinjen i repriser stemmer med analysen,
  - tilskuere ser partiet uten å kunne spille, og bare turneringskamper kan ses på,
  - global chat med historikk, «online» og grense på hvor ofte man kan skrive,
  - hendelser for ny konto og nytt nivå,
  - merker sjekkes mot Elo,
  - partilisten og henting av et parti,
  - dagens oppgave hele veien, med rekke over to dager og toppliste.
- Røyktester av reprisen, oppgaveskjermen, chatten i menyen, låste merker og tilskuer-venterommet.
- Skjermbilder av menyen med chat (PC og mobil), oppgaven, reprisen, de nye merkene og de låste merkene.

## Runde 10 – Mobil, flere oppgaver, raskere oppstart og klar for hosting

| Ønske | Løsning |
|---|---|
| Meny og chat overlapper på telefon | På mobil er chatten nå en smal linje øverst med antall online og siste melding. «Chat» åpner den, og da fyller den bare plassen over menyen. På PC er den som før. |
| Flere oppgaver, noen vanskelige | Oppgaveskjermen har fem faner: Dagens, Lett (3 trekk), Middels (4), Vanskelig (5) og Ekspert (6). Banken har 60 ferdige oppgaver (`ai/puzzle_bank.gd`), laget av `tools/make_puzzle_bank.gd`. De lastes med en gang og virker uten nett. Fremgangen («Oppgave 4 av 15 · 3 løst») lagres på enheten, og «Neste oppgave» går videre. Et trekk som ikke truer noe, avsløres med en gang, så motstanderen aldri bruker lang tid. Tregeste svar målt til 87 ms. |
| Lag på ca. 3 sekunder etter oppstart | Målt: det første bildet med brikker hang i 1,8 s første gang. Det var brikke-shaderen, som hadde vokst til 25 stiler og 14 merker i ett program, og som ble kompilert første gang en brikke ble vist. I nettleseren skjer det hver gang. Nå lager spillet en liten shader per kombinasjon av stil og merke (preprosessoren i Godot), så bare koden som brukes kompileres. Alle 30 skins er sjekket i skjermbilde. |
| Navn i innstillinger trengs ikke | Feltet er fjernet. Med konto brukes brukernavnet (også uten nett, det huskes). Uten konto er du «Gjest» og et tall. Innstillingene sier hvordan du får eget navn. |
| Klar for hosting? Turnering? Egen maskin og domene? | Ny ende-til-ende-test: en hel utslagsturnering med fire spillere over ekte WebSocket-tilkoblinger. Admin lager turneringen, alle melder seg på, en gjest ser på, det blir finale og vinner, og vinneren publiseres i chatten. Web-eksporten er bygget og serveren er startet slik den kjører på nett (web-klient med gzip, egen datamappe). Svar på spørsmålet: ja. `scripts\online.cmd -Hostname spill.mittdomene.no` gir en fast adresse på ditt eget domene via en navngitt Cloudflare-tunnel. Se README, «Hosting fra din egen PC med eget domene». |

**Testet:**
- 112 automatiske tester, alle grønne. Nye: oppgavebanken (gyldige oppgaver på alle nivåer), oppgaveskjermen med banken, og hele turneringen over WebSockets.
- Web-eksporten bygger (37,7 MB wasm, 10 MB komprimert), og den ekte serveren serverer den.
- Skjermbilder av mobil-menyen (chat lukket og åpen), oppgavene på Ekspert, innstillinger uten navnefelt og alle 30 skins.

## Runde 11 – Ikon, «Kaos», scrolling på mobil, drakter og repriser

| Ønske | Løsning |
|---|---|
| Kult og enkelt ikon, også i nettleseren | `icon.svg`: fire blå brikker som trapp oppover på skrå over en glødende vinnerlinje (fire på rad i 3D). Den er satt som prosjektikon, så web-eksporten lager fanikon (`index.icon.png`) og ikon for hjemskjermen på iPhone. Det er sjekket i det eksporterte bygget. |
| En ny og mye mer absurd seiersanimasjon | **Kaos**: en kjempebrikke i vinnerens drakt faller fra himmelen og spretter tre ganger med smell og regnbuegnister. Alle brikkene på brettet kastes opp, snurrer og lander igjen, og 50 små brikker i alle farger regner ned. Kameraet rister nesten tre ganger så hardt som vanlig i fire sekunder. Resultatet vises først når showet er ferdig. |
| Scrolling på telefon i innstillinger og venterom | Knappene «slukte» fingeren, så scrollingen aldri startet. Nå slipper alle knapper og felt inne i en scrolleflate fingeren videre. Scrollingen er skrevet om: innholdet følger fingeren 1:1 og glir litt videre ved et raskt sveip. Knappen fingeren startet på blir ikke trykket. Dette gjelder alle skjermer (innstillinger, venterom, lobby, profil, oppgaver). Ny test sjekker at et drag over en skin-knapp scroller uten å velge skinnet. |
| Brettet gjemt bak menyen på mobil | Menyen er midtstilt nederst og litt tettere. Brettet zoomes litt ut og plasseres midt mellom chat-linjen og menyen. |
| Velge drakt selv | Ny innstilling «Drakt: Hjemme / Borte». Bare når begge har samme skin og drakt, eller fargene er for like, bytter gjesten til den andre drakten. I venterommet ligger «Bytt drakt» ved skin-valget. Drakten sendes til serveren og lagres i repriser. |
| Reprise: spill av og neste var like, og linjen dekket brettet på PC | Nye ikoner: stor ▶ (fremhevet) for spill av, ▶| og |◀ for ett trekk, ▶▶| og |◀◀ for slutt og start. På PC er linjen smalere og midtstilt, og brettet flyttes opp mens reprisen vises. |

**Også fikset:**
- Oppgaveskjermen kunne bytte ut en oppgave midt i et forsøk når dagens oppgave kom fra serveren, eller når reserven uten nett slo inn. Nå skjer det bare når ingen oppgave er i gang.
- Første hakk med musehjulet ga en feilmelding i loggen (`get_meta` med `null` som standardverdi). Rettet.

**Testet:** 114 automatiske tester, alle grønne (nye: drakt-valg, touch-scrolling over knapper, ulike ikoner i reprisen; «Kaos» kjøres av testen for alle seiersanimasjoner). Skjermbilder av ikonet, «Kaos», reprisen på PC, drakt-valget og mobil-menyen.

## Runde 12 – Logg inn fra hovedmenyen

| Ønske | Løsning |
|---|---|
| Login-knapp ved profilbildet i hovedmenyen | Ved profilbildet og navnet står nå **«Logg inn»** for gjester og **«Min profil»** for innloggede (knappen bytter med en gang du logger inn eller ut). Innloggingen kobler til serveren selv. Etter innlogging eller «Tilbake» kommer du tilbake til hovedmenyen, ikke til lobbyen. Det samme gjelder «Min profil». Slår en husket innlogging inn mens skjermen er åpen, går den tilbake til menyen med en gang. |

**Testet:** 115 automatiske tester, alle grønne (ny: knappen åpner innloggingen, og «Tilbake» går til menyen). Skjermbilder av menyen på PC og mobil.

**Etter runde 12:** GitHub-workflowen (`.github/workflows/ci.yml`) er fjernet, så GitHub ikke kjører tester og sender e-post ved hver push. Testene kjøres lokalt som før.
