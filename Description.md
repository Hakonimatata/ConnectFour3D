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

## Runde 5

- Engelsk og norsk språk

- i mobil så er det ett par forbedringer: Chat bør komme over tastatur når tastaturet kommer opp. Markere hele navnet feks i innstillinger funker ikke helt.

- Egne presets for chat knyttet til brukeren.

- Brikkene bør være en hjemme og borte, så vi ser de unike. Gjerne få inn litt metalic, eller noen heftige shadere som er unike for en spiller. Skins skal drive litt av moroa, i tillegg til vinneranimasjoner. Lag noen. Farger kan ha en liten gradient feks også (men da må de være nære i fargen). Kan ha noen decals på brikkene, eller teksturer som man kan velge imellom.

## Runde 6

- På pc: scrolling i instillinger hopper ganske mye av gangen. Fiks dette.

- Holografisk skin ser helt likt ut på hjemme og borte, så har den en litt rar wrap around. Gjør dem mer distinkt.

- Konto med brukernavn og passord

- Stats

- Elo system

- Turneringer

- Sjekk etter punkter i plan.md for gjennomførelse

- Brukerdata må lagres ett sted, og jeg vil gjerne lett endre på det. Kanskje en json fil. Her kan jeg fkes sette en bruker som admin.


## Runde 7

- Scroll i innstillinger er fortsatt veldig store hopp.

- Bør ha innstillinger til siden og brettet til andre siden så man ser skins og animasjoner som preview.

- Ikke lov å gi bort seier og må blokke bør være på som standard (litt som sjakk)

- Enda flere skins og customization. Overraks meg! Hold det relativt stilrent, men kult.

- Muligheten til å se skinet til motstander før man starter (om kontrasten er for dårlig kan man bytte)


## Runde 8

- Aktive turneringer må være på forsiden!

- Lag flere skins! Gjør dem rå og kreative.

- Elo merker. Skal vises ved spillernavn.


## Runde 9

- repriser. Alle trekk og analysen lagres allerede i games.jsonl. En «Se partiet igjen»-knapp der tvungne trekk er markert, er lite arbeid.

- Tilskuere på turneringskamper. Det gjør turneringene sosiale, og serveren sender allerede det som trengs.

- Merker på brikken som låses opp av Elo (ditt «til senere»-punkt). Nivåene finnes nå, så det som gjenstår er å la serveren sjekke hvilke merker spilleren har låst opp.

- Dagens oppgave. Boten finner allerede tvungne seire, så den kan lage en daglig «finn seieren i 3 trekk eller flere» med egen toppliste.

- Antall spillere online og en global chat som vises hele tiden i startmeny. Her publiseres achievevments osv.

## Runde 10

- bedre ui for telefon. Meny og chat overlapper hverandre litt. 

- Flere oppgaver man kan løse om man vil. Noen kan være vanskelige.

- Det er en liten lag i starten på ca. 3 sekund når spillet har loada. Fiks dette.

- Navn i innstillinger trenger ikke være der. Kun navn for de som har brukernavn.

- Test at alt fungerer og er klart til hosting senere. Test at turneringen fungerer. Kan jeg bruke maskinen min og kjøpe et domene?

## Runde 11

- Fiks et kult ikon. Hold det enkelt. Kan dette komme opp i nettleser?

- lag en til og mye mer absurd win animasjon. Mye camera shake.

- scrollingen på telefon i innstillinger er ikke helt en til en. Den lar meg ikke scrolle når skin knappene er der. Brettet i startskjerm er fortsatt gjemt bak menyen. Kanskje flytte brettet litt opp og sentrere menyen og få den litt tettere ned på telefon.

- Man bør kunne bytte skin variasjon. Det er kun når to er like at man blir låst til en.

- Kan heller ikke scrolle i rom-meny. Gå over og fiks dette!

- Se partiet igjen: Play og neste er helt lik. Lag en liten distinksjon. På pc dekker replay baren litt av brettet. Fiks dette. På telefon er den ok.

## Rune 12

- Ved profilbilde i hovedmeny bør man ha en login knapp

- Fjern github workflow test. Jeg orker ikke mails fra github






## Runde 13 

- Admin kan banne enkelte spillere

- Admin kan gjøre annonseringer

- Turneringer får unike pokaler med navn på. Kan jeg som admin generere en pokal som havner på brukerens statistikk? Gjerne mulighet for å lage unike generte pokaler. Også valg for å randomize pokal i det admin oppretter turneringen.

- Vinner av siste turnering skal vises i hovedmenyen. Må hedres på en eller annen måte. En knapp i menyen for å se tournament summary. Se turnerings treet og pokalen.

## Runde 14 (ikke kjørt)

- Har ikke sjekket, men hvis spectatting ikke er med bør vi ha med det!

- Legge til venner, og se hvem av vennene som er online. Mulighet for invitasjon in game også.

- Offentlige grupperom bør ha flere channels. Kanskje en velkommen, en hvor man kan gi feedbacks osv. 

- Hvordan oppleves det under turneringen. Ser man en oversikt over hvem som spiller? Jeg vil se et knowckout tre hvor vi ser pokalen i midten.

- Sjekk etter potensielle muligheter for å gjøre at serveren jobber enda mindre. Hvis mulig fiks, men viktig at det gjøres riktig (ikke must). Jeg vil også at det er smooth og raskt for de som spiller.

- Stressteste en turnering. Sjekk om server takler 32 på en turnering. Gjerne sjekk at det funker for telefon og pc.


## Senere

- progression. Mange av skinsene må unlockes! Lag en realistisk xp system som låser opp dette. Pass på at det ikke abuses helt.