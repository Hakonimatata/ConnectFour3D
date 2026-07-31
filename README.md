# Fire på rad i 3D

Et prosjekt som samler spillogikk, grafikk, kunstig intelligens og framtidig flerspillerstøtte for **fire på rad i 3D**.

Spillet foregår på et tredimensjonalt brett der spillerne plasserer brikker i vertikale kolonner. Målet er å få fire brikker på rad langs en vannrett, loddrett eller diagonal linje. Det finnes totalt 13 unike liner!

## Funksjoner

- [x] Komplett spillogikk
- [x] Validering av trekk og vinnende linjer
- [x] Grunnleggende frontend og 3D-grafikk
- [x] Regelbasert bot med taktisk evaluering og lookahead
- [ ] Server for nettverksspill
- [ ] Game manager for håndtering av spill og spillere
- [ ] Nevralt nettverk for en mer avansert AI-modell

## Bot

Den nåværende boten vurderer blant annet:

- Mulige linjer og oppbygging av angrep
- Umiddelbare seire og nødvendige blokkeringer
- Flere samtidige vinnertrusler
- Hengende og stablede trusler
- Tvungne angrepssekvenser gjennom simulering av framtidige trekk

Målet er å videreutvikle dette til en mer avansert AI som kan trenes gjennom selvspilling.

## Prosjektmål

Prosjektet skal etter hvert inneholde alt som trengs for å:

- Spille lokalt mot andre spillere eller en bot
- Kjøre spill gjennom en sentral server
- Administrere aktive spill og spillere
- Trene og evaluere forskjellige AI-modeller

## Status

Prosjektet er under aktiv utvikling. Spillmiljøet og den grunnleggende frontenden fungerer, mens serverarkitektur, game manager og nevralt nettverk fortsatt er planlagt.
