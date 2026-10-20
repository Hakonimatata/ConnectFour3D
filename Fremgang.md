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
