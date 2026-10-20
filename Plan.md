# Plan – 3D fire på rad i Godot

Dette dokumentet er arbeidsplanen for prosjektet. Det beskriver hva som fantes ved start, hvilke valg vi tar (og hvorfor), hvordan alt henger sammen, og i hvilken rekkefølge vi bygger det.

> **Status etter runde 2:** fase 0–5 er ferdige, og en spillbar prototype finnes (AI, lokalt og online). Fase 6 (drift) gjenstår. Se [Fremgang.md](Fremgang.md) for detaljer og [README.md](README.md) for hvordan man kjører spillet.

---

## 0. Kortversjon

- **Alt skrives i GDScript, i ett Godot 4.7-prosjekt.** Klient, AI og server deler **én** regelmotor. I dag finnes reglene to steder (Python og GDScript), og de oppfører seg allerede ulikt.
- **Serveren er det samme Godot-prosjektet kjørt uten grafikk** (`--headless`). Den snakker WebSocket med JSON-meldinger, bestemmer over alle trekk, og pakkes i et lite Docker-image.
- **Web-klienten er en Godot web-eksport** (Compatibility-renderer, uten tråder). Det blir rene statiske filer som kan legges på GitHub Pages eller itch.io, og de fungerer på både mobil og PC.
- **AI-en er en GDScript-versjon av `SimpleBot`** med flere vanskelighetsgrader. Den kjører lokalt i klienten, så man kan spille mot den uten nett.
- **P2P er mulig (WebRTC), men ikke verdt det som hovedløsning.** Det krever fortsatt en server for signalering, og i dette spillet sendes det nesten ingen data. Vi bygger sentral server først og lar døren stå åpen for P2P senere.
- **Python-koden fases ut** når reglene og boten er portet og testene er grønne. Den ligger fortsatt i Git.

---

## 1. Gjennomgang av koden ved start (runde 1)

Denne seksjonen beskriver utgangspunktet. Alt under er ryddet eller erstattet i runde 2.

### 1.1 Status per del

| Del | Filer | Status i dag | Videre |
|---|---|---|---|
| Regler (Python) | `environment/game.py` | Fungerer for 4×4×4, men feiler på 5×5×5 (se 1.3) | Portes til GDScript og slettes |
| Regler (GDScript) | `frontend/Scripts/game_logic.gd` | Fungerer i klienten, men avviker fra Python-versjonen | Erstattes av ny `core/` |
| Bot | `ai/bot/simple_bot.py` | God heuristikk med lookahead og søk etter tvungen seier | Portes, og blir grunnlaget for vanskelighetsgradene |
| Game manager | `environment/game_manager.py` | Kjører ikke (`Game()` kalles uten argumenter) | Erstattes av lobby/rom på serveren |
| Server | `server/server.py` | Tom | Lages på nytt |
| DQN | `ai/DQN/dqn.txt` | Tom | Droppes foreløpig |
| Signal-hjelper | `environment/signals.py` | Liten observer-klasse | Trengs ikke, Godot har signaler |
| Klient | `frontend/` | Brett, brikker, hover, orbit-kamera, toon-shader, highlight | Deler beholdes og bygges om |
| Tester | `tests/game_test.ipynb` | Manuell notebook med utskrifter | Gjøres om til automatiske tester |

### 1.2 Dette er bra og tas med videre

- **Datamodellen:** kolonne `(x, y)` + høyde `z`, gravitasjon og de 13 retningene. Det er riktig og ryddig.
- **Skillet mellom logikk og visning med signaler** (`piece_placed`, `game_won`, `forced_moves`). Det er nettopp det mønsteret resten av planen bygger på.
- **Bot-ideene:** umiddelbar seier/blokk, «hengende tre», stablede trusler og søk etter tvungne angrepssekvenser. Dette er gode, spillspesifikke tanker.
- **Det visuelle:** orbit-kamera med myk bevegelse, toon-shader med glød og hover-ringen på cellene.

### 1.3 Feil og svakheter funnet ved gjennomlesning

1. **To regelmotorer som er ulike.** Python og GDScript sjekker seier og regler på hver sin måte. Når serveren kommer, vil klient og server da være uenige om hva som er lov. *Dette er hovedgrunnen til at vi går over til én motor.*
2. **Seiersjekken i Python hopper over tomme felt** (`count_pieces_in_open_line` gjør `continue` på tomme felt). På 4×4×4 virker det tilfeldigvis, fordi hver linje er nøyaktig 4 lang. På 5×5×5 gir brikker på x = 0, 1, 3 pluss et trekk på x = 4 «seier», selv om det er et hull på x = 2. En motstanderbrikke utenfor selve 4-vinduet ødelegger også linjen.
3. **GDScript hopper over «ikke gi bort seier»-regelen** når motstanderen har en trussel og `must_block` er av. Det skjer fordi `_get_move_info` returnerer tidlig.
4. **«Ikke gi bort seier» kan låse spillet:**
   - I GDScript finnes det ikke noe unntak for «alle trekk gir bort seier», så man kan ende uten lovlige trekk.
   - Python har et slikt unntak, men regner trekk i øverste lag som utrygge, selv om de alltid er trygge (det finnes ikke noe felt over dem).
5. **Reglene kan krasje med hverandre.** Hva skjer hvis den eneste blokken gir bort seier på toppen? I dag er ingen prioritet definert.
6. **Uavgjort finnes ikke.** Et fullt brett gir ingen sluttilstand, og `GameState.DRAW` blir aldri satt.
7. **Brettstørrelse er lagret flere steder.** `board.gd` har sin egen `grid_size`, og `grid.obj` er en fast 4×4-modell. Det må endres for at 5×5×5 skal fungere.
8. **Bare mus.** Rotering krever høyre musknapp, zoom bruker scrollehjulet, og plassering er venstreklikk. Ingenting av dette virker på telefon.
9. **Renderer-valget fungerer ikke på web.** Prosjektet bruker Forward+ og SDFGI, men web-eksport krever Compatibility-rendereren.
10. **Rot i repoet.** Det ligger rundt 16 `*.tmp`-filer fra editoren og `Board.tscn.depren` i Git. `grid.stl` (600 KB) ligger to steder, og brikkemeshen er lagret både i `Piece.obj` og innebygd i `Piece.tscn` (98 KB).
11. **Testene sjekker ingenting automatisk.** Notebooken skriver ut tilstander, men sier aldri «feil».

---

## 2. Spillregler (spesifikasjon)

Denne seksjonen er **fasiten**. Koden og testene skal følge den. Endrer vi en regel, endrer vi den her først.

### 2.1 Grunnregler

- Brettet er **N×N×N** (N = 4 eller 5, alltid fire på rad). Man velger en kolonne `(x, y)`, og brikken faller ned til laveste ledige `z`.
- En kolonne som er full kan ikke velges.
- Man **vinner** med `win_length` (4) brikker på rad langs én av de 13 retningene: 3 akser, 6 flatediagonaler og 4 romdiagonaler.
  - På 4×4×4 er det **76** mulige vinnerlinjer.
  - På 5×5×5 med fire på rad er det **302**.
- Spillet er **uavgjort** hvis brettet blir fullt uten at noen har vunnet.
- **Tid ute = tap.**
- Man kan **gi opp** når som helst.

### 2.2 Valgfrie regler (velges når rommet opprettes)

| Regel | Navn i kode | Betydning |
|---|---|---|
| Må blokkere | `must_block` | Kan motstanderen vinne på neste trekk, og du ikke kan vinne nå, må du legge på en av motstanderens vinnerplasser. |
| Ikke gi bort seier | `no_gift` | Du kan ikke legge slik at feltet rett over brikken din blir en vinnerplass for motstanderen. |

### 2.3 Hvordan lovlige trekk regnes ut (prioritet)

1. Start med alle kolonner som ikke er fulle.
2. **Vinnertrekk er alltid lovlige.** Filtrene under gjelder bare de andre trekkene.
3. `must_block`: hvis motstanderen har vinnerplasser, fjern trekk som ikke blokkerer en av dem.
4. `no_gift`: fjern trekk som gir motstanderen en vinnerplass rett over.
5. **Hvis et filter ville gitt null lovlige trekk, hoppes det filteret over.**

Dermed finnes det alltid minst ett lovlig trekk så lenge brettet ikke er fullt, og spillet kan aldri låse seg. Dette testes med tilfeldige partier. Klienten viser *hvorfor* et trekk er ulovlig (`MUST_BLOCK`, `GIVES_WIN`, `COLUMN_FULL`, `OUT_OF_BOUNDS`, `GAME_OVER`). Feil tur håndteres av kampkontrolleren og serveren. Implementert i `core/game_state.gd` (`legal_moves()`).

### 2.4 Spillinnstillinger (ett objekt, delt av alt)

```
GameOptions
  size            4 | 5
  win_length      4
  must_block      true | false
  no_gift         true | false
  time_base_s     0 = uten klokke, ellers f.eks. 60, 180, 300
  time_increment  sekunder lagt til etter hvert trekk (f.eks. 0, 2, 5)
  starter         "p1" | "p2" | "random" | "alternate"   (p1 = jeg / verten)
```

Klokken fungerer som i sjakk: hver spiller har sin egen tidsbank, og bare den som har tur bruker av sin. Etter hvert trekk legges `time_increment` til.

---

## 3. Teknologivalg

### 3.1 Språk og server

| Alternativ | Fordeler | Ulemper |
|---|---|---|
| Python-server (FastAPI/websockets) + GDScript-klient | Gjenbruker eksisterende Python | Reglene må finnes i to språk for alltid (klienten trenger dem for AI og offline). Det er dette som allerede har gått galt. |
| Node/TypeScript-server | Mye brukt for spillservere | Nytt språk å lære, og fortsatt to regelmotorer |
| **Godot headless-server (GDScript)** ✅ | Én regelmotor og ett språk. Klient og server bruker *nøyaktig* samme kode, og alt testes med ett verktøy. | Binærfilen er større enn et Python-skript. Godot er ikke laget først og fremst for servere, men for et turbasert spill med lite trafikk har det lite å si. |

**C#** er ikke et alternativ, fordi C#-prosjekter ikke har hatt offisiell web-eksport i Godot 4.

### 3.2 Øvrige valg

| Tema | Valg | Hvorfor |
|---|---|---|
| Renderer | **Compatibility** (WebGL 2) | Påkrevd for web og best for telefoner. Toon-shaderen og glød fungerer, SDFGI fjernes. |
| Web-eksport | **Uten tråder** (*Thread Support* av) | Krever ingen spesielle HTTP-headere (COOP/COEP), så den kan hostes hvor som helst, også på GitHub Pages og itch.io. |
| Nettverk | **WebSocket + JSON-meldinger** | Fungerer fra nettleser og er enkelt å lese, feilsøke og teste. Samme meldinger kan senere sendes over WebRTC (P2P). |
| Tester | **Egen liten testløper** (`tests/run_tests.tscn`) | Endret fra GUT i runde 2. Ingen avhengighet, virker garantert med Godot 4.7, kjører headless i CI og regner skriptfeil som feilet test. |
| UI-skalering | Stretch-modus «disabled» + egen skalering i `ClientRoot` | 3D tegnes i full oppløsning, og UI-et skaleres etter skjermen (DPI på mobil/web). |
| Lagring på klient | `ConfigFile` i `user://` | Navn, skin og lydvalg huskes. Fungerer også på web (lagres i IndexedDB). |
| Lagring på server | **Ingen database** (alt i minnet) | Lettvekt. En omstart av serveren avslutter pågående kamper, noe som er akseptabelt for denne skalaen. |
| Partikler | `CPUParticles3D` | Trygt og billig på mobil-web |
| CI | GitHub Actions | Kjører tester ved hver push. På `main` eksporteres web-bygget som artefakt. |
| Hosting | **Én VPS med Docker Compose** (Caddy + spillserver) | Valgt i runde 2. Ett domene for alt, automatisk HTTPS, klienten finner serveren selv på `/ws`. Ingen CORS- eller URL-oppsett. |

---

## 4. Arkitektur

### 4.1 Oversikt

```
                 ┌────────────────────────────────────────────┐
                 │                  core/                     │
                 │  GameOptions · GameState · Lines · Clock   │
                 │  (ren logikk, ingen noder, ingen grafikk)  │
                 └───────▲──────────────▲───────────────▲─────┘
                         │              │               │
               ┌─────────┴───┐   ┌──────┴──────┐   ┌────┴─────────┐
               │    ai/      │   │   client/   │   │   server/    │
               │ Bot + nivå  │◄──┤ meny, lobby │   │ lobby, rom,  │
               └─────────────┘   │ brett, HUD  │   │ klokke, chat │
                                 └──────┬──────┘   └────▲─────────┘
                                        │   net/        │
                                        └── WebSocket ──┘
                                          (JSON-protokoll)
```

- `core/` vet ingenting om grafikk, nettverk eller noder. Derfor kan de samme klassene brukes av klienten, AI-en, serveren og testene.
- Hvilken modus som startes bestemmes i `main.gd`:
  - `OS.has_feature("dedicated_server")` eller argumentet `--server` → server-scenen.
  - Ellers → klientmenyen.

### 4.2 MatchController: én spillskjerm for alle moduser

Spillskjermen (brett + HUD + chat) snakker bare med et felles grensesnitt. Den vet ikke om motstanderen er en venn på samme skjerm, en bot eller en server:

```
MatchController (signaler)            Implementasjoner
  started                               OfflineMatch – lokalt (to spillere) og mot bot
  move_applied(col, pos, player)        OnlineMatch  – via server
  move_rejected(text, hints)            (P2PMatch    – senere, valgfritt)
  turn_changed(player)
  finished(result, reason, line)
  chat_received(from, text) · info(text) · players_changed
  submit_move(col) · resign() · request_rematch() · send_chat(text) · leave()
```

Dette bygger videre på signalmønsteret som allerede ligger i `board.gd` og `game_logic.gd`.

### 4.3 Regelmotoren (`core/`)

```gdscript
class_name GameState extends RefCounted
func _init(options: GameOptions)
func legal_moves() -> Array[Vector2i]
func check_move(col: Vector2i) -> int      # OK eller grunn (MUST_BLOCK, GIVES_WIN, ...)
func play(col: Vector2i) -> MoveResult     # landingsposisjon, ev. vinnerlinje, uavgjort
func undo() -> void
var current_player: int                    # 1 eller 2
var result: int                            # PLAYING, P1_WON, P2_WON, DRAW
var history: Array[Vector2i]               # hele partiet = listen over trekk
```

Valg av datastruktur:

- **Celler:** `PackedByteArray` med indeks `x + N·y + N²·z`, og høyden på hver kolonne lagret for seg.
- **Vinnerlinjer:** alle linjer regnes ut én gang per brettstørrelse (`Lines`), sammen med en oversikt over hvilke linjer hver celle er med i.
- **Linjetellere:** antall brikker per spiller i hver linje, oppdatert ved `play`/`undo`.
  - Seiersjekken blir korrekt for alle størrelser: en linje vinner når en spiller har `win_length` brikker i den.
  - Den er også rask, fordi den bare ser på linjene gjennom cellen som ble spilt.
  - Botens begreper blir enkle tall: «åpen linje» = 0 motstanderbrikker, «tre på rad» = 3 egne og 0 motstanderbrikker.
- **Historikken er hele sannheten.** Trekklisten er nok til å gjenskape partiet, og brukes til gjenoppkobling, synk mellom klient og server, angre (mot AI) og replays.
- **Koordinater:** `x, y` = kolonne og `z` = høyde, som i dag. Bare brettvisningen oversetter dette til Godots Y-opp.

### 4.4 Mappestruktur

Godot-prosjektet ligger i roten av repoet (gjort i runde 2):

```
ConnectFour3D/
├─ project.godot · main.tscn · main.gd   # main.gd velger klient eller server
├─ core/              # regler: GameOptions, GameState, Lines, ChessClock
├─ ai/                # Bot, BotProfile (vanskelighetsgrader)
├─ net/               # Protocol (meldingstyper), net_client.gd (autoload «Net»)
├─ server/            # ServerMain (WebSocket), Lobby (spillere, rom, partier)
├─ client/
│  ├─ match/          # MatchController, OfflineMatch, OnlineMatch
│  ├─ board/          # BoardView (genereres i kode, input mus + touch), CameraRig
│  ├─ ui/             # tema, meny, oppsett, lobby, rom, spillskjerm, chat, innstillinger
│  ├─ fx/             # seierseffekt, lyd (lages i kode)
│  ├─ skins.gd · settings.gd
├─ assets/            # brikkemodell og toon-shader
├─ tests/             # testløper + test_*.gd
├─ deploy/            # Dockerfile, docker-compose.yml, Caddyfile
├─ .github/workflows/ # CI
└─ README.md          # hvordan kjøre, teste, bygge og hoste
```

---

## 5. Klienten

### 5.1 Skjermer

| Skjerm | Innhold |
|---|---|
| Hovedmeny | Spill mot AI · Lokal 2-spiller · Online · Innstillinger |
| Spilloppsett | Brettstørrelse, regler, klokke, hvem starter. **Samme komponent** brukes for AI, lokalt spill og online-rom. |
| Online-lobby | Kallenavn, liste over åpne rom, «Opprett rom», «Bli med med kode» |
| Venterom | Innstillingene vises (verten kan endre dem), klar-knapp og chat |
| Spill | 3D-brett og HUD: spillere med skin og klokke, turindikator, chat-skuff, «Gi opp» |
| Resultat | Vinner/uavgjort, «Spill igjen» (rematch), «Til menyen» |
| Innstillinger | Navn, skin/farge, lyd og vibrasjon |

### 5.2 Mobil og PC

- UI-et bygges i kode med containere, ankre og ett felles `Theme` (`client/ui/ui.gd`). UI-skalaen tilpasses skjermen, og layouten bytter mellom stående og liggende.
- I stående modus følger kameraets synsfelt bredden, så brettet ikke kuttes på sidene.
- **Touch:**
  - Trykk på en kolonne viser en spøkelsesbrikke der den vil lande, og trykk igjen bekrefter. Det hindrer feiltrykk.
  - Én finger roterer brettet, og knipebevegelse zoomer.
- **PC:** hover viser spøkelsesbrikken, klikk plasserer, høyre museknapp roterer og scrollehjulet zoomer.
- Brettet genereres **i kode** ut fra `size` i stedet for den faste `grid.obj`-modellen. Da kommer 5×5×5 nesten gratis, og kameraavstanden tilpasses automatisk.
  - *Runde 3:* ingen pinner. Brettet er en flat plate med avrundede hjørner og et rutenett med lav kontrast.
  - *Runde 4:* bare de indre linjene, med runde ender og uten sirkler.
- **Plassering (runde 3):** man trykker på flaten man vil legge brikken oppå, altså ruten eller toppen av stabelen. Trykk på siden av en brikke velger også kolonnen.
  - På PC viser en diskré ring hvor man peker.
  - På touch viser første trykk ring og gjennomsiktig brikke, og andre trykk legger brikken.

### 5.3 Utseende

- **Minimalistisk stil:** mørk bakgrunn, Godots standardfont (kan byttes til f.eks. Inter senere), få farger, myke animasjoner og ett `Theme` for hele UI-et.
- **Skins (runde 5):** 12 skins i `client/skins.gd`, tegnet av én shader (`assets/shaders/piece.gdshader`):
  - stiler: glatt, metall, lava, galakse, holografisk, neon, marmor, karbon og racing,
  - en gradient mellom to nære farger,
  - hver skin har **hjemme- og bortedrakt**. Ved lik skin bruker spiller 2 (gjesten) bortedrakt, og begge klientene regner likt,
  - 7 **merker** på toppen (stjerne, prikk, ring, kryss, diamant, hjerte),
  - 5 **seiersanimasjoner** (klassisk, fyrverkeri, konfetti, sjokkbølge, lyn). Vinnerens valg vises, også online.
  - Alt er laget i kode, uten teksturer, så det er lett og virker på web og mobil.
- **Språk (runde 5):** norsk og engelsk (`client/i18n.gd`). Norsk tekst i koden er nøkkelen, og engelsk ligger i en ordliste. En test sjekker at ingen UI-tekst mangler oversettelse. Serveren sender meldinger med nøkkel + argumenter, så de også oversettes.
  - Valgt skin lagres lokalt og sendes til serveren, slik at motstanderen ser den.
  - Velger begge samme farge, bytter klienten automatisk motstanderen til en kontrastfarge.
- **Små detaljer som gir god følelse:** brikken faller med en liten sprett (tween), lyd ved plassering, og markering av tvungne trekk når `must_block` er på (finnes allerede, se `_on_forced_move`).

### 5.4 Effekter ved fire på rad

- **Kamerarist (trauma-modell):** en `trauma`-verdi settes til 1 og synker over tid. Utslaget blir `støy × trauma²`, slik at risten er voldsom i starten og klinger pent ut.
- **Partikler:** et smell av gnister i vinnerens farge langs linjen (`CPUParticles3D`).
- **Ekstra:**
  - De fire brikkene pulserer med glød (bygger på `set_highlight`).
  - Kort sakte film (`Engine.time_scale`).
  - Hvitt skjermblink.
  - Vibrasjon på mobil der nettleseren støtter det.

---

## 6. AI

Vi porterer `SimpleBot` til GDScript på toppen av den nye regelmotoren. Vanskelighetsgradene er **parametere** i en `BotProfile`-Resource, ikke egne klasser:

| Nivå | Oppførsel |
|---|---|
| Lett | Tar ofte (ikke alltid) en direkte seier og blokkerer bare noen ganger. Ellers spiller den et tilfeldig lovlig trekk. |
| Middels | `SimpleBot`-evaluering uten søk etter tvungen seier, med litt tilfeldighet blant de beste trekkene |
| Vanskelig | Hele `SimpleBot`, som i dag: lookahead, hengende tre, stablede trusler og tvungen seier |
| Ekspert *(senere)* | Alfa-beta-søk med `SimpleBot`-evalueringen, iterativ fordypning og tidsbudsjett |

Ting å passe på:

- **Ytelse på mobil-web.** Uten tråder kjører AI-en på samme tråd som UI-et.
  - *Runde 2:* med en hurtigsjekk («kan trekket lage en trussel?») og en hurtigbuffer i søket etter tvungen seier tar tregeste trekk ca. 225 ms på PC (før: 4,7 s). Det er en kunstig «tenketid» på 0,6 s.
  - *Hvis det hakker på telefon:* del søket over flere frames, eller gi trekket et tidsbudsjett.
- **Verifisering.** Bot-mot-bot-tester (`tests/test_bot.gd`) viser at Vanskelig vinner 6–0 mot både Lett og Middels.
- **DQN** settes på vent. Alfa-beta med en god evaluering er sannsynligvis sterk nok, og mye lettere å vedlikeholde.

---

## 7. Server og online

### 7.1 Ansvar

- **Tilkoblinger:** `TCPServer` + `WebSocketPeer.accept_stream()`.
- **Spillere:** id, navn, skin og en reconnect-token.
- **Lobby:** liste over offentlige rom, og private rom med kode på 5 bokstaver.
- **Rom:** innstillinger, spillere, chat, rematch og opprydding av tomme rom.
- **Kamp:** `GameState` + `Clock` fra `core/`.
  - Serveren validerer **alle** trekk og eier klokken.
  - Klienten teller bare ned lokalt mellom meldingene.
- **Frakobling:** spilleren får 60 sekunder på å koble til igjen. Etter det taper vedkommende på walkover. Ved gjenkobling sendes hele trekklisten.
- **Beskyttelse:**
  - Maks lengde på meldinger og chat.
  - Enkel rate-limit.
  - Ukjente eller ugyldige meldinger avvises uten at serveren krasjer.
  - Klientversjonen sjekkes i `hello`.
- **Konfigurasjon** via miljøvariabler, f.eks. `PORT`.

### 7.2 Protokoll (implementert i `net/protocol.gd`, versjon 1)

Alle meldinger er JSON med et typefelt, f.eks. `{"t": "move", "x": 1, "y": 2, "ply": 7}`.

| Klient → server | Server → klient |
|---|---|
| `hello` {name, skin, avatar?, version, token?} | `welcome` {player_id, token, resumed} |
| `list_rooms` | `room_list` {rooms} |
| `create_room` {options, private} | `room_state` {code, private, options, description, you, in_game, players} |
| `join_room` {code} · `leave_room` | `game_start` {options, first, you, players, clocks, number} |
| `set_options` {options} · `ready` {ready} | `game_sync` (som game_start + moves, running, over, result, reason, line) |
| `move` {x, y, ply} | `move_made` {x, y, player, ply, clocks, running} · `move_rejected` {text, hints} |
| `chat` {text} | `chat` {from, seat, text} (også til avsender) |
| `resign` · `rematch` | `game_over` {result, reason, winner, line, clocks} |
| `ping` | `pong` · `notice` {text} · `error` {code, text} |

`ply` (trekknummeret) sørger for at et gammelt eller duplisert trekk ikke blir spilt to ganger.

### 7.3 Kjøring og hosting

- **Lokalt:** `godot --headless --path . -- --server` starter serveren på port 8080. Start deretter to klienter, f.eks. med *Debug → Customize Run Instances*.
- **Lokal testing og spill med venner:** `godot --headless --path . -- --server --web build/web`.
  - Serveren serverer da web-klienten på port 8000 og sender `/ws` videre til spillserveren, så alt går gjennom én port.
  - Nettlesere krever en sikker adresse (`https` eller `localhost`) for Godot-spill, så en LAN-adresse over `http` virker ikke.
  - Hovedløsning: `--https` gjør at serveren kjører HTTPS med local-ip.sh-sertifikatet, og alle på wifi åpner `https://<ip-med-bindestreker>.local-ip.sh:8000`. Testet: sertifikatet godtas, og hele spillet lastes.
  - Alternativer: `localhost` via Chromes port-videresending over USB, eller en HTTPS-tunnel (`cloudflared tunnel --url http://localhost:8000`) for venner over internett. Se README.
- **Valgt hosting (runde 2):** én liten VPS med `deploy/docker-compose.yml`.
  - `server`: samme prosjekt kjørt headless.
  - `web`: Caddy serverer web-bygget og sender `/ws` videre til serveren.
  - Caddy gir automatisk HTTPS, og det trengs fordi en side over HTTPS må bruke `wss://`.
  - Hele bygget (også web-eksporten) skjer i Docker: `DOMAIN=… docker compose -f deploy/docker-compose.yml up -d --build`.
- **Serveradresse i klienten:** på web brukes samme domene + `/ws` automatisk.
  - Kan overstyres med `?server=ws://…` i adressen eller under *Innstillinger → Server*.
  - Utenfor web er standarden `ws://localhost:8080`.
- **Alternativ:** web-bygget på GitHub Pages eller itch.io, og serveren alene på en PaaS (Fly.io, Render). Da må serveradressen settes eksplisitt.

---

## 8. Undersøkelse: peer-to-peer (klient til klient)

**Kort svar: ja, det går, men det gir lite gevinst for dette spillet.**

- **Teknisk:** Godot har `WebRTCPeerConnection` og `WebRTCMultiplayerPeer`.
  - I web-eksporten bruker Godot nettleserens innebygde WebRTC.
  - Desktop- og Android-bygg trenger i tillegg utvidelsen `webrtc-native` (GDExtension).
- **En server trengs uansett.** For å koble to nettlesere sammen må de først utveksle tilkoblingsinfo (SDP/ICE) via en *signalserver*. Det kan være vår egen WebSocket-server, men den må finnes.
- **NAT:**
  - Gratis offentlige STUN-servere holder for de fleste nettverk.
  - En del mobil- og bedriftsnettverk krever en TURN-server, som videresender trafikken. Den koster båndbredde og drift, enten man hoster selv (coturn) eller betaler for en tjeneste.
- **Juks:** uten en nøytral server er det ingen dommer. Men fordi begge klienter kjører samme deterministiske regelmotor, kan hver klient sjekke motstanderens trekk, så ulovlige trekk blir avvist. Det som fortsatt kan manipuleres er klokken og frakoblinger.
- **Gevinst:** et trekk er noen få byte. En sentral server for et turbasert spill er derfor svært billig, så P2P sparer nesten ingenting.
- **Bonus i vår arkitektur:** fordi serverkoden ligger i samme prosjekt, kan et **desktop-bygg** starte serveren i egen prosess («Host spill på LAN»). Nettleserklienter kan imidlertid ikke åpne en lytte-port selv.

**Anbefaling:** bygg sentral server først. Protokollen og `MatchController` utformes slik at en `P2PMatch` (samme JSON-meldinger over en WebRTC-datakanal) kan legges til senere uten å endre spillskjermen.

---

## 9. Testing og bygg

### 9.1 Automatiske tester (egen testløper, kjører headless). Alt under er implementert (50 tester).

- **Regler:**
  - Seier i alle 13 retninger og antall linjer (76 for 4×4×4, 302 for 5×5×5).
  - Gravitasjon, full kolonne og uavgjort.
  - Hver regel, samt prioritet mellom reglene.
  - **«Aldri låst»:** tusenvis av tilfeldige partier der `legal_moves()` aldri er tom før brettet er fullt.
  - `undo` gjenoppretter alt.
  - 5×5×5-hullet fra 1.3 punkt 2 gir *ikke* seier.
- **AI:**
  - Tar seier i ett trekk og blokkerer seier i ett trekk.
  - Finner tvungen seier i kjente stillinger (casene fra notebooken blir tester).
  - Gjør aldri ulovlige trekk og holder tidsbudsjettet.
- **Protokoll:** koding og dekoding, og at ugyldige meldinger avvises.
- **Server (integrasjon):** start serveren i testprosessen, koble til to testklienter og spill en hel kamp med chat, timeout og gjenkobling.

### 9.2 Kommandoer (dokumenteres i README)

```
godot --headless --path . res://tests/run_tests.tscn                    # tester
godot --headless --path . -- --server                                   # server
godot --headless --path . --export-release "Web" build/web/index.html   # web-klient (krever eksportmaler)
DOMAIN=… docker compose -f deploy/docker-compose.yml up -d --build      # alt i drift
```

### 9.3 CI (GitHub Actions, `.github/workflows/ci.yml`)

| Når | Hva skjer |
|---|---|
| Hver push | Testene kjøres |
| Push til `main` | Web-bygget eksporteres og legges ved som artefakt |

### 9.4 Manuell sjekkliste per release

- Chrome og Firefox på PC.
- Safari på iPhone og Chrome på Android, både stående og liggende.
- En online-kamp mellom to enheter på ulike nett.

---

## 10. Faser

Hver fase gir noe som virker, og bygger på den forrige. Offline-spillet blir ferdig før online. Størrelse: S = liten, M = middels, L = stor.

**Status etter runde 2:** fase 0–5 ✅ · fase 6 ⏳ (filene er klare, men ikke satt i drift) · fase 7–11 ikke startet (design for 8–11 i seksjon 13).

### Fase 0 – Opprydding og oppsett (S) ✅
- Ny gren. Flytt Godot-prosjektet til roten av repoet.
- Slett `*.tmp`, `*.depren` og duplisert `grid.stl`, og legg `*.tmp` i `.gitignore`.
- Bytt til Compatibility-renderer og fjern SDFGI.
- Sett opp testløper, eksportprofiler (Web, Server, Windows) og en CI-jobb som kjører testene.
- **Ferdig når:** testkommandoen kjører i CI, og dagens brett åpner i nettleseren via web-eksport. *(Web-eksporten er ikke testet i nettleser ennå, fordi eksportmalene mangler lokalt.)*

### Fase 1 – Regelmotor + tester (M) ✅
- Lag `core/` etter seksjon 2 og 4.3, og skriv testene fra 9.1.
- **Ferdig når:** alle regeltester er grønne for både 4×4×4 og 5×5×5, og «aldri låst»-testen passerer.

### Fase 2 – Lokalt spill på ny arkitektur (M) ✅
- `MatchController` + `LocalMatch`.
- Brettet bygges om til å bruke `core/` og genereres i kode ut fra `size`.
- Spøkelsesbrikke, fall-animasjon, touch-input og kamera for mobil, uavgjort og «spill igjen».
- **Ferdig når:** man kan spille en hel lokal kamp på både PC og mobil-nettleser.

### Fase 3 – AI (M) ✅ (Lett, Middels og Vanskelig. Ekspert og tidsbudsjett venter.)
- Port `SimpleBot`, legg til `BotProfile` med nivåer, AI-modus og ytelsesmåling.
- AI-tester og bot-turnering.
- **Ferdig når:** Vanskelig slår Lett i over 90 % av partiene, telefonen hakker ikke mens boten tenker, og Python-koden er slettet.

### Fase 4 – Meny, innstillinger, skins og effekter (M) ✅
- `Theme`, hovedmeny, spilloppsett, innstillinger med skins (lagres lokalt) og resultatskjerm.
- Effekter ved seier (rist, partikler, glød, sakte film) og lyd.
- **Ferdig når:** offline-delen føles som et ferdig spill.

### Fase 5 – Server og online (L) ✅
- `net/Protocol`, `NetClient`, `ServerMain`, lobby, rom med kode, chat, klokke, gjenkobling og `OnlineMatch`.
- Lobby-, venterom- og chat-UI, Dockerfile og integrasjonstester.
- **Ferdig når:** to enheter kan spille mot hverandre via en lokal server, med klokke og chat.

### Fase 6 – Hosting og publisering (S) ⏳
- *Ferdig:* Docker Compose, Caddy, versjonssjekk i `hello`, serveradresse som finnes automatisk, README.
- *Gjenstår:* skaffe VPS og domene, kjøre `docker compose up`, og teste på ekte mobil.
- **Ferdig når:** én lenke kan deles, og venner kan spille.

### Fase 7 – Utvidelser (valgfritt)
- Ekspert-AI (alfa-beta), og AI-søk fordelt over flere frames hvis mobilen hakker.
- Angre-knapp mot AI (motoren har allerede `undo()`).
- P2P via WebRTC.
- Tilskuere, replays, rangering, app-eksport (Android).

### Fase 8 – Invitasjonslenke (S)
- «Del invitasjon»-knapp i venterommet. Den gir en lenke som `https://<adresse>/?rom=KXRTA`.
- Åpner man lenken, kobler spillet seg til og blir med i rommet. Har man ikke kallenavn, blir man spurt om det først.
- Fungerer uten kontoer, og virker med tunnelen, `--https` på wifi og VPS. Detaljer i 13.2.

### Fase 9 – Lagring og kontoer med passord (M)
- Serveren får varig lagring (JSON-filer) i stedet for bare minnet.
- Registrering og innlogging med brukernavn og passord. Gjestespill med kallenavn virker fortsatt.
- Profil (navn, farge, bilde) lagres på serveren.
- *Allerede på plass:* kallenavn, farge og profilbilde sendes i `hello`.
- Detaljer i 13.1 og 13.3.

### Fase 10 – Statistikk og toppliste (M)
- Hvert online-parti lagres med trekkliste.
- **Per spiller:** seire, tap, uavgjort, vinnerprosent, rekker, raskeste seier, og «tvungne trekk»-tellere (tvungne trekk, lengste tvungne rekke, doble trusler).
- Profilskjerm, statistikk på spillerkortet og en toppliste.
- Detaljer i 13.4.

### Fase 11 – Turneringer med admin i spillet (L)
- Admin oppretter turneringer i spillet med:
  - format (utslag eller alle-mot-alle) og regler/klokke,
  - påmeldingsfrist og starttid,
  - tid mellom rundene.
- Spillerne melder seg på. Serveren setter opp kampene, åpner rommene til riktig tid og gir walkover til den som ikke møter.
- Krever fase 9 (kontoer, admin-rolle) og en server som alltid er på (fase 6).
- Detaljer i 13.5.

---

## 11. Risiko

| Risiko | Tiltak |
|---|---|
| AI-en er for treg i GDScript på mobil-web | Linjetellere i `core/` og hurtigbuffer er på plass (maks ca. 225 ms på PC). Måles på telefon, og ved behov deles søket over flere frames. |
| Web på iPhone (minne, lyd, lastetid) | Compatibility-renderer, små teksturer, komprimert bygg. Lyd starter først etter første trykk, slik nettleseren krever. Testes tidlig på ekte telefon. |
| Godot 4.7 er nytt, og tillegg støtter det kanskje ikke | Løst: ingen tillegg brukes (egen testløper). |
| Prosjektet blir for stort | Fasene følges i rekkefølge. Online starter først når offline er ferdig. |
| Serveren krasjer, og kamper går tapt | Akseptabelt nå. Integrasjonstester og robust meldingshåndtering reduserer risikoen. |
| Passord på avveie | Lagres bare som salt + hash. Sendes bare over kryptert forbindelse. Begrenset antall innloggingsforsøk. |
| Data går tapt (brukere, statistikk, turneringer) | Trygg skriving (midlertidig fil + navnebytte) og datamappe på Docker-volum. Ta jevnlig kopi av mappen. |
| Turnering mens serveren er av | Turneringer kjøres bare på en server som alltid er på (VPS). Ved omstart fortsetter serveren fra lagret tilstand. |

---

## 12. Spørsmål

**Avklart i runde 2:**
- Tid ute = tap.
- 5×5×5 = fire på rad.
- Hosting: én VPS med Docker.
- Kallenavn nå, passord senere (fase 8).
- Python er slettet.
- Godot ligger i roten av repoet.

**Åpne (forslag i parentes):**
1. **Domene og VPS:** har du et domene, og hvilken leverandør? *(F.eks. Hetzner CX22, ca. 4 €/mnd.)*
2. **Neste fokus:** teste på mobil og sette i drift (fase 6), eller passord (fase 8)? *(Fase 6 først.)*
3. **Ekspert-AI:** ønskes et enda sterkere nivå? *(Ja, men etter drift.)*
4. **Turneringsformat:** utslag, alle-mot-alle, eller begge? *(Utslag først.)*
5. **Uavgjort i turnering:** ny kamp med byttet startspiller, eller den med mest tid igjen vinner? *(Ny kamp.)*
6. **Statistikk mot AI:** skal partier mot AI telle i statistikken, eller bare online-partier? *(Bare online på serveren. AI-partier kan telles lokalt.)*
7. **Toppliste:** skal alle kunne se den, også gjester? *(Ja, men bare innloggede kommer på listen.)*

---

## 13. Brukere, statistikk, invitasjoner og turneringer (design)

**Kort svar: ja, alt dette er mulig med dagens oppsett.** Det som mangler er at serveren *husker* ting mellom omstarter (i dag ligger alt i minnet). Passord bør dessuten bare sendes over HTTPS, og turneringer med tidsfrister trenger en server som alltid er på. Rekkefølgen under bygger på dette.

### 13.1 Lagring (grunnmuren)

- **Format:** JSON-filer i en datamappe (`--data <mappe>`, standard `user://data`, et Docker-volum på VPS). Det holder fint for noen hundre spillere og er lett å ta backup av (kopier mappen). Ingen database trengs.

  | Fil | Innhold |
  |---|---|
  | `users.json` | brukere: id, brukernavn, passord-hash, rolle, profil, statistikk |
  | `games.jsonl` | ett ferdig parti per linje: spillere, innstillinger, trekkliste, resultat, analyse |
  | `tournaments.json` | turneringer, påmeldte, runder og kamper |

- **Trygg lagring:** skriv til en midlertidig fil og bytt navn, så en krasj midt i en lagring ikke ødelegger filen. `games.jsonl` får bare nye linjer lagt til.
- **Ny serverdel:** `server/store.gd` med enkle funksjoner (`load_user`, `save_user`, `append_game` …). `Lobby` får lagringen inn utenfra, slik at testene kan bruke en lagring i minnet.

### 13.2 Invitasjonslenke

1. I venterommet: **«Del invitasjon»**.
   - På mobil åpnes telefonens del-meny (Web Share API), så du kan sende lenken på SMS, Messenger osv.
   - På PC kopieres lenken.
2. Lenken er `https://<adressen spillet ligger på>/?rom=KXRTA`.
3. Når spillet starter med `?rom=…`, hopper det rett til online, kobler til og blir med i rommet. Mangler kallenavn, spørres det først.
4. Er rommet borte, vises «Rommet finnes ikke lenger» og lobbyen.

**Merk:** tunnelen (`scripts\online.cmd`) får ny adresse hver gang den startes, så lenken virker bare mens den økten kjører. Faste lenker krever fast adresse (VPS med domene, fase 6).

### 13.3 Kontoer og passord

- **Brukere:** brukernavn (unikt, store og små bokstaver regnes som like) og passord (minst 8 tegn). Gjestespill fungerer som i dag.
- **Passord lagres aldri i klartekst:**
  - Serveren lagrer bare tilfeldig salt + PBKDF2-HMAC-SHA256 med mange runder (laget med Godots `Crypto`/`HMACContext`).
  - Ved innlogging sammenlignes hashen på en måte som ikke lekker tid.
- **Innlogget økt:** innlogging gir en tilfeldig økt-nøkkel som klienten husker. Neste gang logges man inn automatisk via `hello`. «Logg ut» sletter nøkkelen på serveren.
- **Beskyttelse:**
  - Begrenset antall feilforsøk per brukernavn og IP (f.eks. 5 per 10 min).
  - Passord sendes bare når forbindelsen er kryptert (`wss://`: tunnel, `--https` eller Caddy). Klienten nekter å sende passord over vanlig `ws://`.
- **Glemt passord:** det er ingen e-post foreløpig. En admin kan sette et midlertidig passord.
- **Admin-rolle:** du gjøres til admin med `--admin <brukernavn>` når serveren startes (lagres i `users.json`). Senere kan en admin gjøre andre til admin i spillet.
- **Protokoll (nytt):** `register`, `login`, `logout`, `hello` {…, session?}, `me` {bruker, rolle, profil, statistikk}, `set_profile`.
- **Klient:**
  - «Logg inn / Registrer» i innstillingene og i lobbyen.
  - Viser hvem du er innlogget som.
  - Profilbilde og farge synkroniseres med serveren.

### 13.4 Statistikk og «tvungne trekk»

**Lagres for hvert online-parti:** spillere, innstillinger, trekkliste, resultat og grunn (fire på rad, tid ute, gi opp, frakobling), antall trekk og varighet. Trekklisten gjør det også mulig med replays senere.

**Per spiller** (oppdateres når partiet er ferdig):

| Tall | Forklaring |
|---|---|
| Partier, seire, tap, uavgjort | Totalt og per brettstørrelse |
| Vinnerprosent | Seire / partier (vises f.eks. som «12–5–1, 67 %») |
| Rekker | Nåværende og beste seiersrekke |
| Raskeste seier | Færrest trekk til fire på rad |
| Seiere på tid / ga opp / walkover | Hvordan partiene endte |
| **Tvungne trekk** | Antall ganger trekket ditt ga motstanderen en trussel de *måtte* blokkere |
| **Lengste tvungne rekke** | Flest tvungne trekk på rad, der motstanderen bare kunne svare, før du vant. Vises som «Seier med 5 tvungne trekk». |
| **Doble trusler** | Trekk som lager to vinnerplasser samtidig. Motstanderen kan bare blokkere én, så seieren er avgjort. |
| Elo-rating *(valgfritt)* | Brukes til toppliste og til seeding i turneringer |

**Slik regnes tvungne trekk ut:**
- Etter partiet spiller serveren trekklisten på nytt med regelmotoren (`core/`).
- For hvert trekk sjekkes `winning_columns()`: har spilleren nå en vinnerplass motstanderen kan nå, er trekket «tvungent». Har spilleren to eller flere, er det en «dobbel trussel».
- Dette blir en ren funksjon (`core/game_analysis.gd`) med egne tester. Det er de samme begrepene boten allerede bruker.

**Klient:**
- Ny skjerm «Profil og statistikk».
- Motstanderens kort viser seire–tap.
- «Toppliste»: flest seire, best vinnerprosent (minst 10 partier) og lengste tvungne rekke.
- Partier mot AI kan telles lokalt på enheten. Bare online-partier teller på serveren.

### 13.5 Turneringer (med deg som admin i spillet)

**Hvordan det ser ut for spillerne:**
1. Hovedmenyen får **«Turneringer»**, med kommende, pågående og ferdige turneringer.
2. En turneringsside viser:
   - navn, regler og klokke, påmeldingsfrist og starttid,
   - påmeldte spillere,
   - utslagstre eller tabell,
   - din neste kamp,
   - knappene «Meld på» og «Meld av» (krever innlogging).
3. **Fem minutter før en kamp** får begge spillerne et varsel i spillet med knappen **«Gå til kamp»**. Den åpner et ferdig rom med turneringens regler, låst slik at de ikke kan endres.
4. **Møter du ikke** innen fristen (f.eks. 5 min etter start), taper du på walkover.
   - Møter ingen av dem, taper begge. I utslag får da motstanderen i neste runde walkover.
5. Resultatet registreres automatisk når partiet er ferdig, og treet eller tabellen oppdateres for alle.

**Hvordan det ser ut for deg som admin:**
- I «Turneringer» finnes **«Ny turnering»**. Den bruker samme skjema som spilloppsettet, pluss:
  - navn og beskrivelse,
  - format: **utslag** (anbefalt først) eller **alle-mot-alle** (små grupper). Senere eventuelt sveitsisk.
  - maks antall deltakere,
  - påmeldingsfrist og starttid (dato og klokkeslett),
  - tid mellom rundene, f.eks. «neste runde 10 min etter at forrige er ferdig» eller faste klokkeslett,
  - beste av 1 eller 3,
  - uavgjort: ny kamp med byttet startspiller.
- Status: *Utkast → Åpen for påmelding → Pågår → Ferdig*.
- **Admin-verktøy:** publisere, utsette, avlyse, endre et resultat (ved uenighet), diskvalifisere, og legge til eller fjerne en deltaker før start.
- Invitasjonslenke til turneringen, som i 13.2: `?turnering=<id>`.

**Hvordan serveren gjør det:**
- **Ny del `server/tournaments.gd`:** ren logikk med tiden gitt utenfra, akkurat som `Lobby`. Den kan testes helt uten nettverk.
- Ved påmeldingsfristen trekkes oppsettet: tilfeldig, eller etter rating hvis Elo finnes. Ved oddetall får noen «bye» (fri runde).
- Ved kampstart oppretter den et privat rom per kamp via `Lobby`, med låste innstillinger, og venter på begge spillerne.
- Når partiet er ferdig, meldes resultatet fra `Lobby`, og turneringen går videre.
- Alt lagres i `tournaments.json`, så en omstart av serveren fortsetter der den slapp. Tidspunkter lagres i UTC og vises i lokal tid.
- **Protokoll (nytt):** `list_tournaments`, `tournament_state`, `tournament_join`/`leave`, admin: `tournament_create`/`update`/`action`. Fra serveren: `tournament_notice` («Kampen din starter om 5 min»).

**Fremgangsmåte (i små steg):**
1. Datamodell og `tournaments.gd` med tester: påmelding, frist, oppsett, walkover, uavgjort og videre til neste runde.
2. Koble til `Lobby`: turneringsrom, resultat tilbake og varsler.
3. Klient: turneringsliste, turneringsside (tre/tabell) og «Gå til kamp»-varselet.
4. Admin-skjema og admin-verktøy i spillet.
5. Prøvekjøring med noen venner (kort turnering, 4 spillere, 5 min mellom rundene).
6. **Drift:** turneringer med frister krever en server som alltid er på (VPS, fase 6). Tunnelen fra PC-en duger bare til testing.

**Senere:** varsel utenfor spillet (e-post, push eller Discord), tilskuere som ser kampene live, og premier eller merker på profilen.

### 13.6 Anbefalt rekkefølge

| # | Hva | Størrelse | Hvorfor i denne rekkefølgen |
|---|---|---|---|
| 1 | Invitasjonslenke (fase 8) | S | Liten, nyttig med en gang, trenger ingen kontoer |
| 2 | Fast server (fase 6) | S | Trengs for faste lenker, trygge passord og turneringer med tidsfrister |
| 3 | Lagring og kontoer (fase 9) | M | Grunnmuren for statistikk og admin |
| 4 | Statistikk og toppliste (fase 10) | M | Bygger på kontoer og lagrede partier |
| 5 | Turneringer (fase 11) | L | Bygger på alt over |
