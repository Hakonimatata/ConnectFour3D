# Private turneringer for elever – plan

> **Status (01.11.2026):** gjennomført i runde 18, for en sosial samling heller enn en skoletime (ordene
> i spillet er «arrangør» og «deltaker»). Storskjermen med QR-kode er også laget. Se «Runde 18 (forts.)»
> i Fremgang.md for hva som ble gjort. Disse er ikke laget:
> - QR-koden som bilde fra serveren til utskrift;
> - å gjøre en gjestekonto om til vanlig bruker;
> - å fjerne deltakere etter start.
>
> **Senere i runde 18:** rettigheten «Arrangør» (punkt 1 under) er fjernet igjen. Alle med konto kan nå
> lage private turneringer, og den som lager en, er arrangøren. «Start nå» begynner en innsjekk på
> 2 minutter. Se «Runde 18 – Punktene i Description.md» i Fremgang.md.
>
> Grensen for gjestekontoer er satt totalt (200 i timen), ikke per IP, så mange på samme nett kan bli med.

En lærer vil arrangere en turnering for klassen. Elevene skal være med via en lenke, uten å lage
bruker, og bare med et kallenavn (ikke bilde). Læreren lager et turneringsrom. Elevene blir med
til læreren trykker «Start».

Løsningen skal ikke være skreddersydd for skolen. Den bygges av tre generelle deler som også
passer for vennegjenger, klubber og jobben:

1. **Rettigheten «Arrangør»**: kan lage og styre egne private turneringer, men ikke noe annet.
2. **Private turneringer**: skjult for andre, og man blir med via kode eller lenke.
3. **Gjestekontoer**: en midlertidig konto med bare kallenavn, som lages når man blir med via lenken.

Det eneste som bare er til for elever, er at gjester ikke ser den globale chatten.

---

## Slik blir det å bruke

**Læreren** (har fått rettigheten «Arrangør» av admin):
1. Trykker «Ny turnering» i turneringslisten. Skjemaet er det vanlige, men turneringen blir alltid
   privat og uranket. Det startes manuelt, så læreren trenger ikke velge starttid.
2. Turneringssiden viser koden med stor tekst (`KX4P2`) og lenken `fourinspace.com/?t=KX4P2`, med
   «Kopier lenke». Den kan vises på projektoren.
3. Ser deltakerlisten fylles opp, og trykker «Start nå» når alle er med.
4. Kan endre et kallenavn eller fjerne en deltaker, og skru turneringschatten av og på.

**Eleven:**
1. Åpner lenken, eller skriver koden i «Har du en kode?» på forsiden.
2. Skriver et kallenavn og trykker «Bli med». Det trengs ingen bruker, e-post eller bilde.
3. Havner på turneringssiden og venter. Når kampen er klar, kommer varselet som i dag («Klar»).
4. Laster eleven siden på nytt eller mister nettet, kommer hen tilbake som samme spiller. Nettleseren
   husker gjestekontoen, slik den husker en innlogging i dag.

---

## Hvorfor gjestekontoer, og ikke gjester uten konto

Turneringene kjenner deltakerne som konto-id-er (`t.players`, kampene, `ready`, gjenkobling,
`placements`). Gjester uten konto (`user_id == 0`) er bare knyttet til tilkoblingen. Å la dem
delta direkte ville bety endringer i nesten hele `server/tournaments.gd` og i lobbyen, og det ville
bli skjørt ved gjenkobling.

En gjestekonto er en vanlig konto med `guest: true`, uten passord. Da virker turneringskoden,
gjenkoblingen (økt-nøkkelen i `hello`), reprisene og turneringschatten uendret. Det nye er å lage
kontoen og å stenge noen ting for den.

---

## 1. Rettigheten «Arrangør»

**Server:**
- `server/store.gd` `normalize_user`: nytt felt `"organizer": bool(d.get("organizer", false))`.
- `server/accounts.gd`:
  - `set_organizer(username, on)`, som `set_admin`;
  - `is_organizer(user_id)`;
  - `public_info` får `organizer`.
- `server/lobby.gd` `_tournament_request`:
  - i dag: «ikke admin → admin_only»;
  - nytt: én sjekk `_can_manage(p, t)`. Den er sann for admin, eller for arrangøren som lagde
    turneringen (`t.created_by == p.user_id`). Arrangøren kan bare lage turneringer.
- `server/tournaments.gd` `create`: kommer forespørselen fra en arrangør som ikke er admin, tvinges
  `private = true` og `ranked = false`, og premie (`prize`) er ikke lov.

**Klient:**
- `client/ui/admin_screen.gd`: felt for brukernavn + «Gjør til arrangør» / «Fjern arrangør», ved
  siden av det som finnes for admin og utestenging.
- Turneringslisten og turneringssiden viser «Ny turnering», «Endre» og «Start nå» også for en
  arrangør, men bare for egne turneringer. Serveren sjekker det uansett.

## 2. Private turneringer

**Server (`server/tournaments.gd`):**
- Nye felt: `private` (bool), `code` (5 tegn uten tegn som kan forveksles, f.eks.
  `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, unik blant aktive turneringer) og `manual_start` (bool).
- `private` gir alltid `ranked = false`. Da gjelder det som allerede er laget for urangerte
  turneringer: ingen Elo, ingen kunngjøring, ikke i hall of fame og ikke «siste turneringsvinner».
- `manual_start`: `tick()` starter den ikke på starttid. Den starter bare med `action("start")`,
  som finnes allerede. Påmeldingen er åpen til den starter.
- Fordeling: alle gjester har samme Elo. Ved like Elo bør oppsettet trekkes tilfeldig (ikke etter
  påmeldingsrekkefølge), ellers møter de første som meldte seg på hverandre.
- Navn: lagre et øyeblikksbilde av kallenavnet ved påmelding (`t.names[uid]`). Da står navnene
  fortsatt i treet når gjestekontoene er slettet. I dag viser `_name_or_dash` «—» for slettede kontoer.

**Server (`server/lobby.gd`):**
- `_list_tournaments`: private turneringer tas bare med for admin, for arrangøren og for dem som er
  påmeldt.
- `_send_tournament`: en privat turnering vises bare for de samme, eller når man oppgir riktig kode.
- Ny melding (`net/protocol.gd`) `TOURNAMENT_CODE { code, name? }`: slår opp koden og sender
  turneringen. Er man ikke logget inn og `name` er med, lages en gjestekonto først (se 3), og
  personen meldes på.
- `code` sendes bare til admin og arrangøren (i `public(t)`). Deltakerne trenger den ikke.

**Klient:**
- `client/client_root.gd`: ved oppstart på web leses `?t=KODE`
  (`JavaScriptBridge.eval("location.search", true)`), og «Bli med i turnering» åpnes direkte.
  Appen (Android) bruker feltet «Har du en kode?».
- Ny liten skjerm: «Bli med i turnering». Den viser turneringens navn, feltet for kallenavn (fylt ut
  med `Settings.display_name()`) og «Bli med». Er man logget inn, trengs bare «Bli med».
- Turneringssiden for arrangøren: koden med stor tekst, lenken og «Kopier lenke»
  (`DisplayServer.clipboard_set`). QR-kode er valgfritt og kan komme senere, siden den krever en egen
  koder.

## 3. Gjestekontoer

**Server (`server/accounts.gd`):**
- `create_guest(nickname, now)`: en konto med `guest: true`, et internt brukernavn som ikke vises
  (`gjest-<tilfeldig>`), `display_name = Protocol.clean_name(nickname)` og ingen passord. Lag en økt
  med `create_session`, og send nøkkelen tilbake som ved innlogging.
- Det som stenges for gjestekontoer:
  - **bilde:** `set_avatar` og `avatar_on_sign_in` ignoreres (kravet «ikke bilde»);
  - **venner:** ingen forespørsler, og de finnes ikke i `search`;
  - **XP og topplister:** de får ingen XP og kommer ikke med i `leaderboard`;
  - **innlogging:** ingen innlogging med passord, siden de ikke har noe.
- Kallenavnet kan endres fritt av gjesten selv, og av arrangøren i egen turnering. To like navn i
  samme turnering får et tall bak («Ada 2»).
- **Opprydding:** en gang i døgnet (fra `tick`) slettes gjestekontoer som ikke har vært brukt på 14
  dager og ikke er med i en turnering som pågår. Øktene deres slettes også.
- **Grense mot misbruk:** høyst f.eks. 60 nye gjestekontoer i timen per IP. Ikke lavere: en hel klasse
  deler ofte samme IP bak skolens nett.

**Server (`server/lobby.gd`):**
- En gjestekonto får ikke skrive i den globale chatten, bare i turneringschatten.
- Arrangøren kan skru av turneringschatten for sin turnering (`t.chat = false`). Da avvises meldinger
  fra andre enn arrangøren.

**Klient:**
- Logget inn som gjestekonto: menyen viser chatten i `tournament_only`-modus (finnes allerede i
  `GlobalChat`) i stedet for den globale chatten. Profilbilde-valget er skjult.
- «Lag bruker»-knapp (valgfritt, senere): setter brukernavn og passord på gjestekontoen, så eleven
  beholder partiene.

---

## Format og tid

- **Anbefalt for en klasse:** alle mot alle med `max_rounds` 4–5 (finnes allerede). Alle får spille
  like mange partier, og ingen er ute etter første kamp. 5 runder à 6–8 minutter passer i en
  skoletime.
- **Utslag** er raskere med mange, men halvparten er ferdige etter første parti.
- **Møtefrist** (`show_up_s`) kort, f.eks. 60 sekunder, fordi alle sitter i rommet.
- **Klokke:** en fast og kort tid (f.eks. 3 min + 2 s), så ingen kamp blokkerer runden.

## Personvern

- Vi lagrer bare kallenavnet. Ingen e-post, ingen passord, ingen bilde.
- Gjestekontoene slettes automatisk (se over), og navnene i turneringstreet er bare kallenavn.
- Dette er greit å kunne si til skolen. Det bør stå kort på «Bli med»-skjermen («Vi lagrer bare
  kallenavnet ditt, og sletter det etter 14 dager»).

## Grenser

- **Deltakere:** høyst f.eks. 64 i en privat turnering (`max_players` finnes).
- **Aktive turneringer:** høyst 2 private som ikke er ferdige, per arrangør.
- **Gjestekontoer:** høyst 60 nye per IP i timen (se 3).

---

## Rekkefølge

Hvert steg kan testes alene, og alle stegene er nyttige hver for seg:

1. **Arrangør-rettigheten:** felt, `_can_manage`, admin-skjermen. Tester: en arrangør kan lage og
   starte sin egen, men ikke endre andres, og turneringen blir privat og uranket.
2. **Private turneringer:** `private`, `code`, `manual_start`, filtrering i lister, `TOURNAMENT_CODE`,
   navnebildet. Tester: skjult for andre, synlig med kode, starter ikke av seg selv, navnene står
   igjen.
3. **Gjestekontoer:** `create_guest`, begrensningene, oppryddingen, grensen per IP. Tester: gjesten blir
   med via kode, kobler seg på igjen med økt-nøkkelen, kan ikke sette bilde, ikke skrive i den globale
   chatten, og blir slettet etter 14 dager.
4. **Klienten:** `?t=` i lenken, «Bli med»-skjermen, koden og lenken for arrangøren, chatten for
   gjester. Tester i `tests/test_client.gd`: hele flyten fra lenke til første parti.
5. **Valgfritt senere:** QR-kode, «Lag bruker» fra gjestekonto, arrangøren endrer kallenavn.

Grovt omfang: 300–400 linjer kode og 150–200 linjer tester.

## Det som må bestemmes før vi starter

- Skal gjestekontoer kunne gjøres om til vanlige brukere senere? Anbefalt: ja, men som et eget steg.
- Hvor lenge skal gjestekontoer leve? Anbefalt: 14 dager etter siste bruk.
- Hvor mange deltakere i en privat turnering, og hvor mange aktive per arrangør?
  Anbefalt: 64 og 2.
- Skal chatten for gjester være av eller på som standard? Anbefalt: på, men bare
  turneringschatten, og arrangøren kan skru den av.
- Skal gjestekontoer kunne spille vanlige online-partier utenom turneringen, eller bare i den?
  Anbefalt: bare turneringen. Det er enklest å forklare og minst å passe på.
