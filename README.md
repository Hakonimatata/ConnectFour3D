# Fire på rad i 3D

Fire på rad på et 3D-brett (4×4×4 eller 5×5×5), laget i Godot 4.7. Spillet kan spilles mot AI (tre vanskelighetsgrader), med to spillere på samme enhet eller online mot venner. Det fungerer på PC og mobil (nettleser).

Alt er skrevet i GDScript i ett Godot-prosjekt. Klienten, AI-en og serveren bruker **samme regelmotor** (`core/`).

## Kom i gang

1. Installer [Godot 4.7](https://godotengine.org/download) (standardversjonen, ikke .NET).
2. Åpne `project.godot` i Godot og trykk **F5**.

Kommandoene under kjøres fra roten av repoet. `godot` er Godot-programmet (på Windows f.eks. `Godot_v4.7-stable_win64_console.exe`).

| Hva | Kommando |
|---|---|
| Kjør spillet | `godot --path .` |
| Kjør alle tester | `godot --headless --path . res://tests/run_tests.tscn` |
| Kjør noen tester | `godot --headless --path . res://tests/run_tests.tscn -- rules` (filter på filnavn) |
| Start spillserveren | `godot --headless --path . -- --server` (port 8080, endre med `--port 9000` eller `PORT=9000`) |

### Spille online lokalt

1. Start serveren med kommandoen over.
2. Start spillet to ganger, for eksempel med *Debug → Customize Run Instances* i editoren.
3. Velg «Spill online» i begge. Klienten kobler til `ws://localhost:8080` som standard.
4. Opprett et rom i det ene vinduet, og bli med med koden i det andre.

Serveradressen kan endres under *Innstillinger → Server*. På web kan den også settes i adressefeltet, for eksempel `?server=ws://192.168.1.10:8080`.

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
