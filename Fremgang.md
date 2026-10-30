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

**Feilretting (chat i menyen):** chatten i hovedmenyen var tom etter at du hadde vært i en annen meny (f.eks. innstillinger) og gått tilbake. Serveren sender historikken og «online» bare rett etter tilkobling, men menyen lages på nytt hver gang. Nå husker nettverksdelen de siste meldingene og antall online, så chatten er fylt med en gang menyen vises. Ny test dekker dette (116 tester, alle grønne).

**Feilretting (chat minimeres når man skriver):** på mobil krymper skjermtastaturet skjermen, og menyen la seg da om. Noen ganger gikk den over til PC-oppsettet med en liten chat i hjørnet, eller så la menyen seg over chatten. Nå beholdes mobil-oppsettet mens man skriver, og chatten fyller hele plassen over tastaturet (menyen skjules så lenge). Når man er ferdig å skrive, er alt som før. Ny test (117 tester, alle grønne).

**Tilskuere på alle partier, farger i oppgaver og i chatten:**
- «Spill online» har en ny liste, **«Spilles nå»**, med alle partier som pågår: spillerne (med Elo-merke og farge), antall trekk, hvor mange som ser på og eventuelt turneringen. «Se på» åpner partiet live som tilskuer. Alle partier kan nå ses på, ikke bare turneringskamper. «Slutt å se på» tar deg tilbake til lobbyen.
- **Oppgaver:** under målet står nå «Dine brikker» og «Motstanderen» med fargen til hver, så det er tydelig hvem som er hvem.
- **Global chat:** hvert navn har sin egen faste farge (12 tydelig ulike farger, valgt ut fra navnet), så det er lettere å se hvem som skriver.
- Testet: 118 tester, alle grønne (nye: listen over pågående partier og tilskuer på et vanlig parti, fargeforklaringen i oppgaver, og navnefargene).

**Endre innstillinger mellom partier og egen klokke:**
- Resultatskjermen har fått **«Endre innstillinger»**. Mot AI og lokalt åpnes oppsettet med innstillingene fra partiet (tid, regler, brett, nivå), og «Start» begynner et nytt parti.
- Online har verten **«Endre regler»**. Etter «Lagre» står verten i venterommet, og motstanderen får beskjed («Ada endret reglene: 4×4×4 · 7+4»). Det neste partiet starter når verten trykker «Klar!» og motstanderen trykker «Spill igjen» (eller «Klar!»). Endres reglene, må begge bekrefte på nytt. Turneringskamper har fortsatt låste regler.
- **Egen klokke:** ved siden av de faste valgene (Av, 1+0, 3+2, 5+0, 10+5) finnes «Egen». Der velger du minutter (1–60) og sekunder ekstra per trekk (0–60) selv. Dette gjelder også turneringsskjemaet.
- Testet: 120 tester, alle grønne (nye: regler endret mellom partier online, og «Endre innstillinger» med egen klokke mot et lokalt parti).

**Siste parti i hovedmenyen:** i stedet for to boter spiller hovedmenyen nå av det siste partiet som ble spilt på serveren. Partiet vises trekk for trekk med spillernes egne skins. Over brettet står «Siste parti: Ada – Bob», og når partiet er ferdig, hvordan det endte («Ada vant med fire på rad», «… på tid», «… motstanderen ga opp», «Uavgjort – fullt brett»).
- Serveren husker bare det siste partiet og sender det til alle når et parti er ferdig, og til nye når de kobler til (ny melding `last_game`, uten analysen, så den er liten).
- Med mange partier vises alltid det siste. Kommer det et nytt mens et annet spilles av, byttes det først når avspillingen er ferdig og sluttstillingen har stått litt.
- Uten nett, eller før noen har spilt, spiller botene som før.
- Testet: 122 tester, alle grønne (nye: serveren sender siste parti til alle og etter hello, og menyen spiller det av med riktig tekst).

**På nett med eget domene (fourinspace.com) og småfikser:**
- Spillet kjører fra PC-en på `https://fourinspace.com` (og `www.`) via en navngitt Cloudflare-tunnel: `scripts\online.cmd -Hostname fourinspace.com` (`-NoExport` hopper over eksporten).
- Skriptene finner Godot 4.7 selv (`scripts\find_godot.ps1`): Nedlastinger, skrivebordet (også «Skrivebord» og OneDrive), Program Files eller `godot` i PATH. `GODOT` kan fortsatt settes.
- Lastesiden på web har logo, «Fire på rad / i 3D» og en fremdriftslinje i spillets farger (`html/head_include` i `export_presets.cfg`).
- Hovedmenyen: «Spill online» (uthevet) og «Spill offline» side om side. «Spill offline» er en fane som folder ut «Mot AI» og «To spillere». «Dagens oppgave» og «Innstillinger» deler en rad.
- Den globale chatten viser hvem som er online (med Elo-merke, og «i parti» for dem som spiller).
- Tastaturet på mobil: feltet man skriver i (f.eks. i innstillinger) havner over tastaturet. Målingen bruker den synlige delen av spillflaten, og innstillingskortet får hele høyden mens man skriver.
- Kameraet kunne havne under brettet på mobil (bildet skyves opp, og det senker kameraet). Nå holdes det alltid over brettet.
- Ryddet bort gamle `__pycache__`-filer fra før Godot-omleggingen.

## Runde 13 – Admin, pokaler og siste vinner

| Ønske | Løsning |
|---|---|
| Admin kan utestenge spillere | Ny admin-side («Admin» ved profilbildet i menyen, bare for admin). En utestengt konto kan ikke logge inn, øktene slettes, spilleren kastes ut hvis den er online (og får grunnen), og fjernes fra turneringer med åpen påmelding. Utestengte vises ikke på topplistene. En admin kan ikke utestenges. «Opphev» i listen over utestengte. `"banned": true` i `users.json` virker også, og serveren kaster ut spilleren når filen lastes inn på nytt. |
| Admin kan gjøre kunngjøringer | Kunngjøringen vises som et banner hos alle som er online, og blir stående (uthevet) i den globale chatten. |
| Unike pokaler, også fra admin | Pokaler lages fra et frø (`net/trophy.gd`): 6 former (pokal, beger, stjerne, kule med ring, obelisk, krone), 11 metaller (gull, sølv, bronse, platina, rosé, krystall, rubin, smaragd, safir, obsidian og regnbue), hanker, merke foran (bl.a. fire på rad) og sokkel. De tegnes i kode (`TrophyView`) med metallglans og glitter. Hver turnering får sin pokal: tilfeldig, eller trykk «Ny pokal» i skjemaet til du liker den. Vinneren får den med turneringens navn og dato på profilen («Pokaler»). Admin kan gi en egen pokal til hvem som helst. Den kunngjøres i chatten. |
| Siste vinner hedres i menyen, med turneringsoversikt | Et gyllent kort i hovedmenyen: pokalen (som gløder), «Siste turneringsvinner», navnet i gull og turneringen. Det åpner turneringssiden: vinneren med pokalen øverst og hele turneringstreet (kvartfinale, semifinale, finale) med vinnerne uthevet og finalevinneren i gull. |

**Også i runde 13:**
- **Enklere å lage turneringer:** dag og klokkeslett med piler (15 min om gangen) eller 18:00–21:00 med ett trykk, og «Starter i morgen kl. 20:00 (om 22 t)». Et tidspunkt som har passert, kan ikke velges. Det sjeldne (beskrivelse, regler, klokke, pauser, møtefrist, publisering) ligger under «Flere valg».
- **Reklame i hovedmenyen:** den neste turneringen med åpen påmelding får et eget kort med pokalen, tid og antall påmeldte, og «Meld meg på» rett fra menyen (uten konto åpnes innloggingen). Er du påmeldt, står det «Påmeldt».
- **For deltakerne:** øverst på turneringssiden står din status («Din kamp: Mattias – Duck · starter 22:07», «… nå! Trykk «Gå til kamp»», «… spilles nå», «Du vant kampen!» eller «Du er ute»). I treet er navnet ditt blått og kampen din har blå kant. Kamper som spilles nå, har grønn kant (med «Se på» i listen). Runder som ikke er trukket ennå, vises som tomme bokser.
- **Scrolling i chatten zoomet brettet:** musehjul og fingre over et panel (chat, menykort, banner) slapp gjennom til brettet når de ikke traff selve meldingene. Paneler utenfor en rulleliste tar nå imot dem.
- **«Dagens oppgave» ble kuttet på mobil** når den var løst («Dagens oppgav…»). Nå er «løst» et lite grønt merke med hake i hjørnet av knappen.
- Klienttestene kobler seg ikke lenger til en server som kjører på maskinen (de brukte standardadressen og kunne få ekte data).

**Testet:** 133 automatiske tester, alle grønne. Nye: utestenging (utkastelse, innlogging og økt nektes, opphev, toppliste, åpen turnering, `users.json`), kunngjøringer, pokaler fra admin og til turneringsvinneren, pokalgeneratoren, admin-siden, turneringstreet og deltakerstatus, skjemaet med dato og klokkeslett, reklamekortet og vinnerkortet, pokalhylla, og at scrolling over chatten ikke zoomer brettet. Skjermbilder av alle 66 pokalkombinasjoner, menyen (PC og mobil), turneringssiden (ferdig, og pågående sett fra en deltaker på mobil), skjemaet, admin-siden, profilen og kunngjøringen.

**Feilretting (pokalen byttet seg):** turneringen «FourInSpace Open» ble laget mens serveren kjørte koden fra før runde 13. Pokalen som ble valgt i skjemaet, ble derfor ikke lagret. Etter omstarten fikk turneringen en fast reservepokal ut fra id-en, og den er nå lagret. Samme frø gir alltid samme pokal, på web og PC. Admin har fått «Ny pokal» på turneringssiden for å velge på nytt før start.

**Feilretting (menyen ble høyere med tomrom nederst):** turneringslisten i hovedmenyen hentes hvert 20. sekund. De gamle elementene ble fjernet med `queue_free()`, så de var fortsatt med da menyen regnet ut høyden (715 i stedet for 544 piksler i testen). Nå fjernes de med en gang, menyen legger seg om når innholdet endrer høyde, og listen bygges ikke på nytt når ingenting er endret. Det hadde ingenting med admin å gjøre.

## Runde 14 – Venner, chatkanaler, turneringstre med pokalen i midten

| Ønske | Løsning |
|---|---|
| Tilskuere | Fantes fra før: alle partier kan ses på («Spilles nå» i *Spill online*), også turneringskamper. Nå kan du også trykke på en kamp som spilles i turneringstreet, og trykke «Se på» ved en venn som spiller. |
| Venner, se hvem som er online, invitere | Ny venneside (*Venner* ved profilbildet i menyen, og i *Spill online*). Legg til med brukernavn. Den andre får et banner med «Se» og godtar eller avslår (spør dere begge, blir dere venner med en gang). Listen viser online først med en farget prikk («spiller nå» med «Se på», «online» med «Utfordre», eller «offline»), og oppdateres av seg selv når noen kommer eller går. «Utfordre» åpner oppsettet for et privat rom og inviterer vennen når rommet er laget. I venterommet viser «Inviter en venn» de ledige vennene. Vennen får et banner med «Bli med». Menyknappen viser hvor mange venner som er online, og en prikk ved nye forespørsler. |
| Kanaler i den globale chatten | Faner for «Generelt», «Velkommen» og «Innspill». En prikk på fanen betyr nye meldinger der. «Velkommen» og «Innspill» har en kort introtekst. Nye kontoer ønskes velkommen i «Velkommen», og hendelsene havner i «Generelt». Alt i «Innspill» lagres også i `data/feedback.jsonl`, så admin kan lese det. Kunngjøringer vises i alle kanalene. Hver kanal har sine siste 50 meldinger. |
| Oversikt under turneringen, tre med pokalen i midten | Turneringstreet er speilvendt: halvparten av første runde på hver side, og finalen i midten med pokalen (som gløder) over. På smale skjermer går treet fra venstre mot høyre, med pokalen over finalen. Kamper som spilles nå har grønn kant og kan trykkes på for å se på. Din kamp og ditt navn er blå. Turneringssiden er bredere på PC, så treet med 8 spillere får plass. |
| Mindre arbeid for serveren, raskt for spillerne | Turneringssiden spurte serveren hvert 3. sekund. Nå sender serveren endringer med en gang til dem som har siden oppe (samlet opp per tick), og siden spør bare hvert 15. sekund som reserve. Serveren leste hele `users.json` hvert sekund for å se etter endringer for hånd. Nå sjekkes bare endringstiden, og filen leses bare når den er endret. Hovedmenyen bygger ikke turneringslisten på nytt når ingenting er endret. Web-filene var allerede komprimert og lagret i minnet. |

**Testet:** 139 automatiske tester, alle grønne. Nye: venner (forespørsel, godta, gjensidig forespørsel, fjerne, online-status som oppdateres, feil, invitasjon til rom, «spiller nå» med rom), kanaler (hver kanal for seg, ukjent kanal, velkomst, grense per kanal), turneringssiden som får endringer med en gang (og ikke etter at den er lukket), menyhøyden etter ny turneringsliste, vennesiden, kanalfanene, invitasjonslisten og treet (speilvendt når det er plass, trykk for å se på). Skjermbilder av treet på PC (pågående og ferdig) og mobil, chatkanalene, vennesiden og invitasjonen.

**Stresstest: turnering med 32 spillere** (`tools/stress_tournament.gd`, se README). En egen testserver på port 9080/9000 med egen datamappe, så serveren på nett ikke ble påvirket. 32 boter over ekte WebSocket registrerte seg, meldte seg på og spilte hele utslagsturneringen (5 runder).
- Med blandede boter: 31 partier, 1 367 trekk og 8 396 meldinger på 4 minutter. Serveren brukte 0,9 % CPU i snitt (maks 4 %) og 130 MB minne, uten feil.
- Med raske boter (`--level easy`, måler serveren og ikke botene): 33 partier (2 uavgjorte ble spilt om), 1 615 trekk. Svartid fra trekk sendt til trekk bekreftet: median 14 ms, 99 % under 34 ms, tregeste 44 ms.
- De første målingene hadde noen svar på 0,8–1,2 sekunder. Det var testen selv: alle botene kjører i én prosess, og en vanskelig bot kan tenke i opptil 0,23 sekunder mens de andre venter.
- Fant og rettet en feil: turneringssiden hoppet tilbake til turneringslisten når en liste kom fra serveren (f.eks. den hovedmenyen ba om rett før). Nå skjer det bare når admin har slettet turneringen. Ny test.
- Funn: endres `users.json` for hånd mens mange registrerer seg samtidig, kan serveren skrive over endringen før den rekker å lese den. Vent til det er rolig, eller bruk admin-siden.
- Skjermbilder: påmeldingen, treet med 32 spillere på PC (fra venstre mot høyre, pokalen over finalen), en kamp sett som tilskuer, det ferdige treet og mobil (treet scrolles sidelengs).

## Tilbakemeldinger fra chatten (27.10.2026)

Ønsker og feil fra den globale chatten, og et ønske om menyen:

| Tilbakemelding | Løsning |
|---|---|
| «Står bare Ukjent melding: friend» og «Fint om innspill ikke kommer i Generelt-chatten» | Serveren på nett kjørte koden fra før runde 14 (venner og kanaler). Begge er løst når serveren startes på nytt med den nye koden. |
| «Se andres profil ved å klikke på brukernavn, og hurtigknapp for å adde venner» | Navnene i chatten, «hvem er online», topplisten, søket og vennelisten kan trykkes på og åpner profilen. Gjester kan ikke trykkes på, de har ingen profil. På andres profil står profilbildet, og under navnet en venneknapp: «Legg til venn», «Godta», «Forespørsel sendt», eller «Utfordre» / «Se på» når dere er venner. |
| «Burde få opp treff på profilen man søker opp» | Søkefeltet på vennesiden viser treff mens du skriver. Treffene sorteres slik at navn som begynner med teksten, kommer først. Hvert treff viser Elo, om spilleren er online, og «Legg til», «Godta», «Sendt» eller «Venner». |
| «Blir profilbilde lastet opp? Det kommer opp på mobil, men ikke på PC med samme bruker» | Bildet ble bare sendt når appen startet. Logget man inn på en enhet uten bilde, ble bildet på kontoen slettet. Nå hører bildet til kontoen. Ved innlogging får enheten kontoens bilde. Har kontoen ikke bilde ennå, tar den bildet fra enheten. Nytt eller fjernet bilde lagres på kontoen med en gang. Fjerner du bildet, kommer det ikke tilbake fra en annen enhet som fortsatt har det. Andre ser bildet på profilen din. |
| «Lagre/Tilbake-knappen bør synes uten å scrolle helt ned» | Kortene (profil, venner, turneringer, oppsett, konto, admin, lobby) har en fast rad nederst med «Tilbake» (og «Opprett» / «Lagre»). Innholdet scrolles inne i kortet, og kortet er aldri høyere enn skjermen. Det samme gjelder «Lagre» i innstillingene og knappene i oppgavene. |
| «Fint å kunne åpne/lukke menyen på mobil når man er inne i et spill/oppgave» | Oppgavepanelet har «Skjul» øverst. Da står bare tittelen, statusen og knappene (Tilbake, Vis løsning, Prøv igjen) igjen nederst, og brettet får resten av skjermen. «Vis mer» åpner panelet igjen. I et parti lukkes pausemenyen også når man trykker utenfor kortet. |
| Mindre «Siste parti»-tekst, og rotere mellom de tre siste partiene | Teksten og boksen er mindre. Serveren sender de tre siste partiene. Menyen spiller av ett om gangen, tilfeldig valgt, men aldri det samme to ganger på rad. Det nyeste heter «Siste parti», de andre «Nylig parti». |

**Testet:** 145 automatiske tester, alle grønne. De nye tester:
- søket (store og små bokstaver, eget navn utelatt) og «sendt»-listen;
- at profilbildet følger kontoen: PC-en får mobilens bilde, et fjernet bilde forblir fjernet, et nytt bilde følger med, og ugyldige bilder avvises;
- de tre siste partiene;
- rotasjonen i menyen;
- at «Tilbake» synes på mobil med mye innhold;
- at oppgavepanelet kan skjules;
- trykk på navn i chatten;
- venneknappen på profilen.

Skjermbilder på mobil: profil, innstillinger, vennesøk, oppgaven (åpen og skjult) og menyen.

**Oppfølging samme kveld:**
- **Profilbildet kunne ikke velges på iPhone (Chrome og Safari).** Begge bruker WebKit, og WebKit åpner bare filvelgeren midt i selve trykket. Godot behandler trykket først i neste bilde, så velgeren ble stille blokkert (Android var mer tolerant). Nå gjør spillet nettleseren klar når fingeren treffer «Velg bilde…», og velgeren åpnes i nettleserens egen «slipp»-hendelse. Flyttet fingeren seg (scrolling), åpnes den ikke. En ny test sender et bilde på størrelse med et foto gjennom web-porten, slik telefonen gjør, og sjekker at det lagres på kontoen.
- **Skins følger kontoen.** Brikke, merke, farge på merket, drakt og seiersanimasjon lagres på kontoen når du lagrer innstillingene, og en enhet får kontoens utseende når du logger inn. En ny konto tar utseendet enheten har valgt. Endrer du utseendet uten nett, vinner enhetens utseende ved neste innlogging.
- **Feilretting:** hovedmenyen, vennesiden og turneringssiden koblet lambdaer til nettverkssignaler. De ble hengende igjen etter at skjermen var lukket, og ga skriptfeil ved neste innlogging eller tilkobling. Nå er det metoder, og Godot kobler dem fra når skjermen lukkes.
- **Testet:** 148 automatiske tester, alle grønne. Nye: utseendet følger kontoen (ny konto, annen enhet, endring, endret uten nett, gjest), klienten tar i bruk kontoens utseende og bilde, og bildeopplasting gjennom web-porten. JavaScript-koden til bildevelgeren er syntakssjekket. Den er ikke prøvd på en ekte iPhone.

## Innspill etter første turnering (28.10.2026)

Innspillene fra kanalen «innspill» under og etter FourInSpace Open, pluss tre ønsker fra admin.

| Innspill | Løsning |
|---|---|
| «Fjerne del lenke etter/under turnering» | «Del lenke» (og den nye «Legg i kalender») vises bare før turneringen starter. |
| «Nedtelling før start i turnering» og «countdown på 3 sek per game uansett turnering eller ikke» | Turneringssiden viser en stor nedtelling til start («Starter om 12:34»), og deltakerne ser «Din kamp starter om 1:45» mellom rundene. Hvert parti (online, mot AI og lokalt) starter med 3, 2, 1 og «Spill!» midt på skjermen. Serveren holder klokken og avviser trekk til nedtellingen er ferdig, så ingen taper tid. |
| «Ikke mega laggy animasjon når spillet tar slutt» | Shaderne til effektene ble kompilert første gang de ble tegnet, altså akkurat når partiet var slutt. Nå tegnes de usynlig når partiet starter. Gnistnettene gjenbrukes i stedet for å lages på nytt for hvert smell. Telefoner og nettbrett bruker halvparten så mange partikler. Sakte film er mildere (0,4 i stedet for 0,25), så det ikke ser ut som hakking. |
| «Spillere blir kastet inn i gamet når det startet, ikke gå inn manuelt» | Når kampen starter, går spilleren rett inn i rommet, også fra menyen, fra en annen side, fra et parti mot boten eller når hen ser på et annet parti. Er hen midt i et annet parti online, kommer banneret med «Gå til kamp» som før. |
| «En egen turneringschat ved siden av chat som hører til kampen» | Turneringssiden har en turneringschat. I en turneringskamp har chatten to faner: «Kamp» og «Turnering». Alle som har siden oppe, spiller eller ser på en kamp i turneringen, får meldingene. |
| «Tydelig før start hva reglene er for timer osv» | Ny seksjon «Regler» på turneringssiden: formatet, hva som skjer ved uavgjort, brett og regler, tiden («3 min hver, pluss 2 s per trekk»), at startspilleren byttes, at man kastes inn, møtefrist og pause, rangert eller ikke, og pokalen. |
| «Tydeligere at man ikke har opponent … (walkover)» | Venterommet viser «Motstanderen har ikke kommet ennå. Kommer hen ikke innen 3:12, vinner du på walkover», med nedtelling. Turneringssiden viser hvem som mangler og når walkoveren kommer. Etter en walkover kommer spilleren tilbake til turneringssiden med beskjeden øverst. Statusen sier «Du har fri denne runden» ved fri runde og «Motstanderen møtte ikke. Du vant på walkover» ved walkover. |
| «Turneringstreet bør være på toppen inne i turneringsmenyen» | Treet står rett under navnet. |
| «De som spiller bør få begrenset chattilgang, … reaction emojis fra seere og antall seere diskret i et hjørne» | I turneringskamper ser ikke spillerne det tilskuerne skriver. Tilskuerne har fire reaksjonsknapper (hjerte, stjerne, flamme, lyn). Reaksjonene flyr opp over skjermen hos alle, også spillerne. Antall som ser på står nede i hjørnet som før. Spillets skrift har ikke emoji, så ikonene tegnes med kode. |
| «Mulighet for å legge i kalender med lenke når man melder seg på turnering» | «Legg i kalender» på turneringssiden. På nett hentes en kalenderfil fra serveren (`/kalender/<id>.ics`) med navn, tid, lenke til turneringen og en påminnelse 15 min før. Telefonen spør om du vil legge den inn. På PC åpnes Google Kalender med turneringen fylt ut. |
| «En hall of fame med de som har vunnet tidligere turneringer» | Turneringslisten har en hall of fame: vinnerne av rangerte turneringer, nyeste først, med pokalen. Navnet åpner profilen. |
| «Flere brett og bakgrunnsstiler, f.eks. nebula/verdensrom eller coffeeshop» | Ny innstilling «Bakgrunn»: Standard, Nebula, Stjernehimmel og Kaffebar. De tegnes i bakgrunns-shaderen, så nedlastingen ikke blir større (Hako9: «kan ikke øke loading tid alt for mye»). Bakgrunnen er bare for deg selv. |
| (admin) Uranket turnering, med eller uten pokal | To nye brytere i turneringsskjemaet: «Rangert» og «Pokal til vinneren». Uranket: partiene endrer ikke Elo, men seire og tap telles i statistikken. Turneringen vises ikke i hovedmenyen, kunngjøres ikke i chatten, kommer ikke i hall of fame og teller ikke som turneringsseier. Den står i turneringslisten med «Uranket». Uten pokal: vinneren får ingen pokal, og treet har ingen pokal i midten. |
| (admin) Chatfeltet mistet fokus etter hver melding på PC | Chatfeltene (global chat, kamp, venterom, turnering) beholder fokus etter Enter og etter «Send» på PC, så man kan skrive videre. På telefon lar vi være, ellers ville tastaturet sprette opp igjen. |

**Ikke gjort, bare notert:** app i App Store, reklame, betalte skins, season pass, loot boxes, bedre premie, musikk, flere spillmoduser, prestasjonsside («inventory»), og en egen arena («boksering») for turneringskamper.

**Testet:** 159 automatiske tester, alle grønne. Nye tester:
- uranket turnering uten pokal (ingen Elo, pokal, turneringsseier eller kunngjøring, men statistikk);
- rangert uten pokal;
- hvem som har kommet til kampen, og tiden til walkover;
- turneringschatten og historikken;
- kalenderfilen;
- nedtellingen på serveren (trekk avvises, klokken står) og i klienten (også mot AI);
- at tilskuerchat ikke når spillerne i en turneringskamp, og at reaksjonene gjør det;
- at chatfeltet beholder fokus;
- at menyen og hall of fame bare viser rangerte turneringer;
- nedtelling, regler og lenker på turneringssiden;
- bakgrunnene.

Skjermbilder på mobil: turneringssiden, nedtellingen og bakgrunnene. Kalenderfilen og at spillet går raskere på slutten er ikke prøvd på en ekte telefon.

## Runde 15 – AI-analyse av partiene, og flere innspill fra turneringskvelden (29.10.2026)

**AI-analyse (fra Description.md, runde 15):** etter hvert parti vurderer den vanskelige boten hvert trekk. Den regner ut verdien av alle lovlige trekk, med samme evaluering som når den spiller, og sammenligner med trekket som ble spilt (`ai/move_review.gd`).
- **Under resultatet:** «Treffsikkerhet (AI): Du 87 % · Bob 72 % (2 feil)». Begge spillerne får en vurdering. Mens analysen pågår, står «Analyserer partiet… 40 %».
- **I «Se partiet igjen»:** hvert trekk får en vurdering (beste trekk, bra, unøyaktig, feil eller tabbe) i sin egen farge, og et kort tips. Markøren på brettet viser hvor brikken heller burde lagt. Eksempler på tips: «Du kunne vunnet med en gang der markøren står», «Motstanderen hadde tre på rad. Du måtte blokkere der markøren står», «Herfra kunne du tvunget frem seier…» og «Trekket lar motstanderen tvinge frem seier». Partier fra profilen («Siste partier») analyseres på samme måte.
- **Hva som teller som tabbe:** å ikke vinne eller ikke blokkere når det står tre på rad. Å bomme på en tvungen seier, eller gi motstanderen en, er «feil». Det skjer ofte, og ellers ville nesten alt blitt rødt. Trekk der det bare fantes ett lovlig trekk, teller ikke.
- **Ytelse:** analysen regnes ut litt etter litt, høyst 8 ms per bilde, ett motsvar om gangen, så skjermen ikke fryser. Tvangssøket er grunnere enn når boten spiller (dybde 4 på 4×4×4, 2 på 5×5×5). Målt på flere partier gir det samme vurdering. Et helt parti tar 1–2 s på 4×4×4 og ca. 7 s på 5×5×5 på PC. På mobil tar det lenger tid, men det skjer mens resultatet vises.

**Innspill fra kanalen:**

| Innspill | Løsning |
|---|---|
| «Påmelding på turnering bør være synlig fra hjemskjerm uansett» og «Turneringer som er unranked burde få påmelding i hovedmeny» | Urankede turneringer vises nå i menyen med «Meld meg på» og merket «Uranket». Bare rangerte vinnere hedres (siste vinner i menyen og hall of fame). |
| «Tydeligere i hjem-menyen at man er påmeldt, gjerne med timer» | Er du påmeldt, kommer den turneringen øverst med «Du er påmeldt!» og en nedtelling i grønt («Starter om 25:00 · 5/8»). En pågående turnering du er med i, står med «Pågår nå · du er med». |
| «Gjør chatten lik i turnering og general, bare med egen tab for turnering» | Den globale chatten får fanen «Turnering» når du er påmeldt eller en turnering pågår. Turneringssiden og turneringsfanen i kamp bruker samme chat (med Elo-merker, navnefarger og navn som kan trykkes på). Påmeldte får meldingene uten å ha siden oppe, og alle får dem mens turneringen pågår. |
| «Automatisk bortefarger dersom de er ganske like» | Før ble bare nesten like farger oppdaget (RGB-avstand på én farge). Nå sammenlignes hele brikken (hoved-, detalj- og UI-farge) i Oklab, der avstand følger hvordan øyet ser forskjell. F.eks. Glør mot Kobber, Is mot Opal, Eik mot Kobber og Lime mot Giftig gir nå bortedrakt. Testen sjekker alle par av skins. |
| «Bør kunne trykke ready og skippe ventingen» | I pausen mellom rundene har turneringssiden «Klar – start uten å vente». Når begge i kampen har trykket, starter den med en gang. Den andre får et banner: «Bob er klar for neste kamp …» med «Se». |
| «Bedre reaction emojis, ut med stearinlyset» | Nye reaksjoner tegnet med kode: hjerte (med glans), flamme med tre tunger, lattermildt fjes med gledestårer, og overrasket fjes. |
| «Etter et game i turnering fikk jeg ikke valg om å gå tilbake til turneringsoversikt» | Spillere i en turneringskamp får «Tilbake til turneringen» (i resultatet og i menyen), og forbindelsen holdes åpen. |
| «Trenger ikke den meldingen som sier at man har blitt satt inn i et game» | Banneret er borte når du kastes inn i kampen. Det kommer bare hvis du er midt i et annet parti online, med «Gå til kamp». |
| «Få inn spillet på Steam» | Ikke gjort, bare notert. |

**Feil funnet underveis:** reprisen sa «X blokkerte.» etter et tvunget trekk, også når X ikke blokkerte. Nå står det bare når trekket faktisk blokkerte.

**Testet:** 167 automatiske tester, alle grønne. Nye tester:
- analysen (bommet på blokkering og seier, beste trekk, trinnene, små steg);
- «Klar» i pausen;
- turneringschatten til påmeldte og til alle mens den pågår;
- turneringsfanen i den globale chatten;
- tilbake til turneringen etter en kamp;
- like skins.

Skjermbilder på mobil: menyen med påmelding og turneringsfanen, reaksjonene, og reprisen med tips. Analysen er ikke tidsmålt i nettleser på telefon.

## Runde 16 – Hvordan AI-en kan bli bedre (særlig på 5×5×5)

Dette er bare forslag; ingen kode er endret. Nytt verktøy: `tools/ai_arena.gd` lar boter spille mot hverandre og måler seiersprosent og tenketid. Det kan brukes til å sjekke at en ny AI faktisk er bedre.

**Målt (PC, med standardreglene):**

| Oppsett | Resultat | Trekk per parti | Tenketid snitt / maks |
|---|---|---|---|
| 4×4×4 Vanskelig mot Vanskelig (20 partier) | starter 9, den andre 11 | 56 | 17 ms / 177 ms |
| 4×4×4 Vanskelig mot Middels (40) | Vanskelig vant 40–0 | 30–33 | 15–24 ms / 568 ms |
| 5×5×5 Vanskelig mot Vanskelig (8) | starter 6, den andre 2 | 30 | 149 ms / **2,1 s** |
| 5×5×5 Vanskelig mot Middels (16) | Vanskelig vant 16–0 | 23–25 | 78–118 ms / 1,6 s |

**Hvorfor den er svak på 5×5×5:**
1. Boten søker ikke, den ser bare ett trekk og motstanderens svar. Bare tvangssøket (trusler på rad) går dypere. På 5×5×5 er det 25 kolonner og 3× så mange vinnerlinjer, og partiene avgjøres raskt (30 trekk mot 56 på 4×4×4).
2. Evalueringen er lokal og ujustert. Den teller linjer gjennom cellen brikken lander i (vekt 1 på nesten alt). Den ser ikke på hele brettet: hvor mange levende trusler hver har, trusler over hverandre, eller paritet (hvem som «eier» trusler på oddetalls- og partallshøyder når brikkene faller ned).
3. Motsvaret ignorerer reglene. Motstanderens svar velges fra alle åpne kolonner, ikke fra `legal_moves()`. Med «må blokkere» og «ikke gi bort seier» på (standard) feilvurderer den altså hva motstanderen faktisk kan gjøre.
4. Den tenker på hovedtråden. Mot boten frøs spillet i opptil 2,1 s på PC på 5×5×5, og sannsynligvis flere sekunder i nettleser på mobil.
5. Vanskelig er helt forutsigbar. Samme stilling gir alltid samme trekk, så en spiller kan lære en fast vinnervei.

**Forslag, i rekkefølge:**
1. **Tenk uten å fryse (lite, stor gevinst):** del søket opp over flere bilder med en tidsgrense (f.eks. 300 ms på mobil, 1 s på PC). Det samme ble gjort med analysen i runde 15. Tråder virker på PC, men ikke i web-eksporten uten trådstøtte.
2. **Ekte søk:** negamax med alfa-beta, iterativ fordypning (søk dypere til tiden er ute) og transposisjonstabell (Zobrist-hash som oppdateres i `place`/`unplace`). Trekkrekkefølge: vinn, blokker, trusler, forrige beste trekk, midten. Tvangssøket brukes som forlengelse når det står trusler. Søket bruker `legal_moves()`, så reglene blir med.
3. **Global evaluering med paritet:** `counts` har allerede antall brikker per linje. Gi poeng for linjer der bare én farge har brikker (f.eks. 1/5/30 for 1/2/3 brikker), mye for trusler som kan spilles nå, og ekstra for trusler over hverandre og trusler på «riktig» høyde (oddetall for den som starter). Dette er det viktigste for 5×5×5.
4. **Juster vektene med selvspill:** la `tools/ai_arena.gd` spille ny mot gammel bot (f.eks. 200 partier, begge som starter). Ta bare i bruk en endring som vinner minst 55 %. Vektene kan finjusteres automatisk (endre én vekt, spill, behold om det ble bedre).
5. **Åpningsbok:** de første 4–6 trekkene ferdig regnet ut for begge størrelser (som oppgavebanken). Det sparer tid og gir sterkere åpninger.
6. **Nivåer etter tid og dybde, ikke bare av/på:** Lett = dybde 1 med mye tilfeldighet, Middels = dybde 2–3, Vanskelig = full tid, og gjerne et nytt «Ekspert». Litt tilfeldighet blant like gode trekk gjør Vanskelig mindre forutsigbar.
7. **Raskere kode:** unngå `filter`/lambdaer og nye Array-er i det innerste søket, og bruk `PackedInt32Array` og hele tall. Senere kan søket flyttes til C++ (GDExtension) hvis det trengs. C# fungerer ikke i web-eksporten.

**Spilldesign:** 5×5×5 med fire på rad avgjøres fort, og den som starter vinner oftest (6–2 mellom to like boter). Fem på rad på 5×5×5 kan vurderes som et valg, og bør sjekkes med arenaen.

## Runde 16 (forts.) – Ny, mye sterkere bot, og flere ting fra admin (28.10.2026)

**Ny søkemotor** (`ai/search_bot.gd`) for Vanskelig og nytt nivå Ekspert. Lett og Middels er som før. Søket bruker:
- alfa-beta med iterativ fordypning, så det søker dypere til tiden er ute (Vanskelig 1 s, Ekspert 2,5 s);
- transposisjonstabell (Zobrist-hash), PVS, drapstrekk og historikk for trekkrekkefølgen, og grunnere søk av sene trekk (LMR);
- reglene («må blokkere» og «ikke gi bort seier») akkurat som `GameState.legal_moves()`;
- tvungne trekk som ikke teller som dybde, og et taktisk søk etter egne trusler nederst i søket;
- en vurdering av hele brettet: åpne linjer, trusler som ikke kan spilles ennå, laveste trussel i kolonnen, trusler over hverandre og høyden truslene står på;
- egne tabeller som oppdateres for hvert trekk, én fast tabell for trekklistene, og evaluering bare av kolonner med trusler.

**Tenker uten å fryse:** boten tenker 12 ms per bilde i spillet. Før kunne spillet fryse i over 2 s på 5×5×5.

**Viktigste funn:** bare partallsdybder (2, 4, 6 …) brukes til å velge trekket. Med oddetallsdybde har motstanderen tur nederst i søket, og da overses våre egne trusselrekker. Målt med fast dybde mot den gamle boten: dybde 2 vant 96 %, dybde 4 75 %, men dybde 3 bare 19–34 %. Å sjekke motstanderens trusselrekker overalt hjalp på fast dybde, men kostet så mye tid at boten ble svakere (25 %), så den sjekken er av.

**Målt mot den gamle Vanskelig** (`tools/ai_arena.gd`, begge som starter):

| Oppsett | Resultat |
|---|---|
| 4×4×4, ny Vanskelig (0,7 s) | 12–0 |
| 4×4×4, 250 ms | 15–1 (94 %) |
| 4×4×4, 100 ms (omtrent en treg mobil) | 78 % |
| 4×4×4 uten regler, 300 ms | 92 % |
| 5×5×5, 300 ms | 8–0, ofte på under 12 trekk |

**Om 5×5×5:** med fire på rad er tre på rad nederst med åpne ender allerede en dobbel trussel, akkurat som i gomoku. Boten ser det og vinner fort. Mennesker må blokkere åpne toere tidlig.

**Turneringslisten på mobil:** hver turnering var én knapp med lang tekst, så kortet ble bredere enn skjermen. Nå er det rader der navnet kortes av og infoen brytes over flere linjer.

**Antall runder i alle mot alle:** admin velger «Alle», 3, 5 eller 7 runder i skjemaet, og kan endre det på turneringssiden helt til start. Skjemaet viser hvor lenge turneringen tar, f.eks. «Varighet med 16 spillere: ca. 1 t 52 min (15 runder)». Reglene på turneringssiden sier antall runder og omtrentlig varighet.

**Testet:** 174 automatiske tester, alle grønne. Nye tester:
- søkets tabeller stemmer med regelmotoren på begge brettstørrelser;
- søket slår den gamle boten;
- tenkingen deles i små biter, og spillet fryser ikke mot Vanskelig;
- søket vinner på 5×5×5;
- alle nivåer spiller bare lovlige trekk;
- alle mot alle med begrenset antall runder;
- varighetsanslaget.

Stresstesten av turneringer bruker den gamle Vanskelig, så den måler serveren og ikke tenketiden. Boten er ikke tidsmålt i nettleser på mobil, men den tenker i små biter der også.

## Runde 17 – Bedre analyse, stillingsmåler, trening, XP og nye oppgaver (29.10.2026)

**AI-analysen bruker den sterke boten.** Før så analysen bare ett trekk fram (den gamle boten), og Ekspert-boten fikk rundt 78 % på sine egne partier. Nå vurderes hver stilling én gang av søket fra runde 16 (dybde 4, høyst 0,5 s per stilling), slik sjakkprogrammer gjør det:
- verdien gjøres om til vinnersjanse, og et trekk koster det vinnersjansen falt (samme kurve som Lichess bruker for treffsikkerhet);
- når en spiller ender i tvunget tap som søket først så senere, får spillerens siste frie trekk skylden (ellers slapp tabben unna fordi resten var tvungne blokkeringer);
- tipsene sier hva det bedre trekket gjør: to trusler, en trussel som må blokkeres, tre på rad som ikke kan blokkeres ennå, eller å stoppe motstanderens tre på rad.

Målt med `tools/review_check.gd` (botene spiller, analysen gir karakterer):

| Parti | Treffsikkerhet |
|---|---|
| Ekspert mot Lett | Ekspert 94–99 %, Lett 64–69 % |
| Vanskelig mot Middels | Vanskelig 95–98 %, Middels 76–89 % |
| Ekspert mot Ekspert | 85–92 % (lange partier der én må gjøre den avgjørende feilen) |

Analysen tar rundt 0,2 s per trekk på PC.

**Feilen med markøren «oppå» brikken:** markøren for det bedre trekket og plassene motstanderen måtte blokkere var begge hvite. Etter et trekk som lagde tre på rad, sto blokkeringsplassen ofte rett over brikken, og teksten sa «bedre der markøren står». Nå er det bedre trekket en grønn markør, og teksten sier «den grønne markøren». Det bedre trekket er alltid i en annen kolonne (testet).

**Stillingsmåler («sjakkpila»):** en stolpe i spillernes farger som viser hvem som leder, med vinnersjansen («62 %») eller «Seier om 3». Den vises
- i reprisen, for hvert trekk;
- for tilskuere, også i turneringskamper (søker litt hvert bilde);
- i treningen.

Spillerne i et vanlig parti ser den ikke, siden det ville vært juks.

**Trening mot AI** (bryter i oppsettet):
- uten klokke;
- «Vis beste trekk» med grønn markør og forklaring;
- hvert av trekkene dine blir vurdert («Ditt trekk: Unøyaktig. Bedre: den grønne markøren …»). Boten venter til vurderingen er ferdig, og litt til hvis trekket kunne vært bedre, så du rekker å se markøren;
- «Angre» tar bort ditt trekk og botens svar, også etter at partiet er slutt.

**Reprise av finalen:** partiene lagres nå på turneringskampene. Eldre turneringer finner dem i partiloggen ved oppstart. En ferdig utslagsturnering har knappen «Se finalen» hos vinneren. Ferdige kamper har ▶ i treet og «Reprise» i rundelisten.

**Admin kan endre turneringen** («Endre» på turneringssiden, samme skjema som «Ny turnering»):
- før start kan alt endres;
- mens den pågår: navn, beskrivelse, pause mellom rundene, møtefrist, pokal og premie;
- etter at den er ferdig: navn og beskrivelse.

**XP, nivåer og opplåsing** (`core/progression.gd`, sjekket på serveren):
- **Partier mot en annen konto:** seier 20–50 XP (mer mot sterkere motstander), uavgjort 15, tap 8.
  - Partiet må ha minst 10 trekk.
  - Høyst 3 partier mot samme motstander per dag gir XP, og høyst 400 XP per dag fra partier, så to kontoer ikke kan «farme» hverandre.
- **Dagens oppgave:** 25 XP, pluss 5 for hver dag på rad (høyst +50). 7 dager på rad låser opp skinnet «Morgengry».
- **Rangert turnering:** vinneren 150, finalisten 75, semifinalistene 40, alle andre som spilte 20. Første turneringsseier låser opp «Gullmester».
  - Admin kan sette en premie: en skin eller animasjon som ellers krever nivå. Vinneren får den.
- **Partier mot boten gir ikke XP.** De spilles uten server, så de kan ikke sjekkes, og å slå Lett-boten skal ikke gi noe uansett.
- **Nivåer:** 100 XP til nivå 2, og 50 mer for hvert nivå. Nivå 10 kommer ved 2 700 XP og nivå 20 ved 10 450.
- **Hva som er låst:**
  - 8 skins og 2 seiersanimasjoner er åpne for alle.
  - De andre låses opp fra nivå 2 til nivå 30 (Sort hull).
  - Nye nivåer på 5, 10, 15 … kunngjøres i chatten.
- **Eksisterende kontoer:** de får XP ut fra statistikken sin, og beholder skinnet og animasjonen de bruker.
- **Hvor det vises:** XP står i resultatet etter partiet, etter dagens oppgave og på profilen. Låste ting er dempet i innstillingene, med kravet («Nivå 10»).

**Dagens oppgave i tre typer, dag for dag:**
- «Tving frem seier», som før;
- «Vinn på N trekk»: stille trekk er lov, det finnes ingen seier med bare trusler, og løsningen er entydig. De med vinnerlinje på kryss og tvers gjennom flere høyder kommer først;
- «Finn beste trekk»: motstanderen truer med tvungen seier, og bare ett trekk redder deg. Bommer du, vises motstanderens første trekk i seieren.

De to nye typene krever eksakt søk med stille trekk og er for tunge for serveren. Derfor lages de på forhånd (`tools/make_daily_bank.gd`, `ai/daily_bank.gd`), og serveren sjekker bare løsningen. Søkeboten har fått en eksakt modus (ingen forlengelser eller reduksjoner) til dette.

Banken har 30 «Vinn på N trekk» (16 på 3 trekk, 14 på 4 trekk) og 30 «Finn beste trekk». Med tre typer på rundgang varer den i 90 dager før noe gjentas. Alle 60 er sjekket: løsningen godtas, «Vinn på N» har ingen seier med bare trusler, og svaret i «Finn beste trekk» holder. Å lage dem tok rundt 50 minutter.

**Testet:** 189 automatiske tester, alle grønne. Nye tester:
- analysen gir den sterke boten høy og den svake lav treffsikkerhet, og det bedre trekket er alltid i en annen kolonne;
- treningen: vurdering, beste trekk og angre;
- tilskuere ser stillingsmåleren, spillerne ikke;
- reprise av finalen, også for gamle turneringer;
- endring av en turnering før og under;
- XP: grenser, oppgaverekke, turneringsplassering og premie;
- låste skins vises ikke for andre;
- alle tre typer dagens oppgave i skjermen;
- oppgavene i banken.

**Utsatt, eller bør diskuteres:**
- **Partier mot boten gir ikke XP.** De spilles uten server og kan ikke sjekkes, så en endret klient kunne gitt seg selv XP. Skal sterke boter gi noe, bør det være en engangs prestasjon («slå Ekspert»), og vi må godta at den kan jukses til.
- **Gjester og spill uten konto** får bare de 8 åpne skinsene og 2 animasjonene. Før hadde alle alt. Det er poenget med opplåsing, men det merkes for dem som bare spiller mot boten.
- **Brett og bakgrunner er ikke låst**, bare skins og seiersanimasjoner, som innspillet nevnte.
- **Eksklusive premier:** to nye skins (turneringsseier og 7 dager på rad). Nye seiersanimasjoner som bare kan vinnes, krever egen effektkode og design.
- **Stillingsmåleren for spillerne selv i et parti** er ikke med, siden det ville vært juks. En spiller kan i teorien se på sitt eget parti som tilskuer fra en annen enhet.
- **Oppgavebanken er endelig.** Kjør `tools/make_daily_bank.gd` på nytt for flere. Å lage dem på serveren i bakgrunnen (litt hvert sekund) går, men er mer arbeid.
- **Treningen og analysen er ikke tidsmålt i nettleser på mobil.** Analysen har tak på 0,5 s per stilling, og i nettleseren blir den grunnere, ikke tregere.
