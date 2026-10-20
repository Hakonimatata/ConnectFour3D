# Description

## Runde 1

- Gå over hele workspacet. Målet er å lage et 3d 4-på-rad spill i Godot. Jeg trenger en server, klient i godot Web, og en AI som kjører lokalt hvis man vil spille ofline.

- Jeg er ikke så god på å kode, og har mest sannsynlig gjort mange dårlige valg som du kan endre. Det gjelder også valg av kodespråk. Du har friheten til å starte helt på nytt og slette tidligere kode. Jeg har det lagret i Git.

- Jeg vil fokusere på å holde ting litt lettvekt og strukturert.

- Reglene for spillet ser du og bør komme tydelig fram i koden jeg har skrevet. 

- Jeg vil ha enkel build, tester, og lett å kjøre og hoste.


### Klient siden

- I Godot, og skal fungere på telefon og pc. 

- Moderne pent og minimalistisk layout med meny, lobby, chat osv.

- Timer funksjon for runde litt ala sjakk. Det er i game settings.

- Start med 4x4x4 brett, men skal kunne utvides til 5x5x5 senere. 

- Skins / farge på brikken. 

- Heftig kamera shake og partikler når man får fire på rad.

- Regler kan setter i game options når man lager rom.

- Mot AI modus, med ulike vanskelighetsgrader. Ta utgangspunkt i det jeg har laget fra før.

### Server side

- Sjekker logikk og gyldige trekk

- Manager spillere og lager lobbyer. 

- Undersøk om det går an å hoste peer to peer, altså at klient og klient.

### Plan

- Lag en plan i "Plan.md" som beskriver en god fremgangsmåte for å lage alt dette.



## Runde 2 

- svar til uklarheter: tid ute fører til tap ja. 5x5x5 skal være 4 brikker som gir fire på rad. Hosting velger du det som er best egnet. Trenger kun kallenavn til å begynne med, men bør ha passord etter hvert. Gjerne slett og rydd python koden om nødvendig. Gjerne flytt godot til roten.

- Gjør en god chunk av planen. Gjerne så jeg kan se en god prototype ihverfal.


- Til slutt, opdater plan og fremgang om nødvendig


## Runde 3

- Jeg vil ikke ha de pinnene som stikker opp, de er i veien. Brikkene er ok, men brettet er stygt. Lag det enkelt firkantet med avrundede hjørner (flat topp). Vil også ha et grid i midten, ikke for høy kontrast. 

- Fiks noen gui elementer mtp farge og at knapper skilles fint ut. 

- Å legge ned brikker behøver litt rework. Jeg skal velge rett på flaten på den brikken jeg vil legge oppå. Nå er det forvirrende. Jeg vil også ha en indikator (ikke for forstyrrende) for der jeg hovrer over før jeg legger.

- Spørsmål: Kan jeg hoste lokalt på nett så jeg kan spille over wifi med telefon og noen andre? 

- Hold deg til en branch, trenger ikke styre for mye med git. Det fikser jeg.

- Får valget "gi opp" etter å ha vunnet.

- Lag en stilig men ikke for forstyrrende gradient bakgrunn.

- Gjør ting litt mindre saturert, bortsett fra brikkene.


## Runde 4

- Fjern endende på rutenettet slik at det liksom blir 6 streker for å lage 4x4 brettet. Ikke noen sirkelskygger der brikkene går. Litt tykkere grid med avrundede ender.

- Litt mindre kontrast på skygger (for mye directional light kanskje)

- Brukere kan legge til et bilde i profilen sin. 

- Lysere bakgrunn

- Slider knapp (on/off) er vanskelig å se er av siden det mørke går i ett med bakgrunnen.

- Å opprette rom gir attempt to call on null reference eller noe sånt. Fiks.

- Hvordan skrive godot i stedet for & "$env:USERPROFILE\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe"?

- Hvordan teste på telefon i chrome?


## Til senere

- Spør om hvordan bot fungerer sammenliknet med den første koden jeg ga i python.

- Turneringsmous. Admin brukere kan lage turneringer? Folk melder seg på innen en frist. Tid velges for å spille kampene. De som ikke møter opp taper umiddelbart. 

