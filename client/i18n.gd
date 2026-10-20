class_name I18n
extends RefCounted
## Språk. Norsk er kildespråket: teksten i koden er norsk og brukes som nøkkel.
## Engelsk ligger i EN under. Godot oversetter tekst i knapper og etiketter selv;
## tekster som settes sammen med navn/tall bruker tr("mønster %s") % verdi.
##
## Ny tekst i UI-et? Legg den inn i EN (testen tests/test_i18n.gd sjekker at ingen mangler).

const SUPPORTED := ["nb", "en"]

static var _loaded := false


## lang: "auto" (følg enheten), "nb" eller "en".
static func apply(lang: String) -> void:
	_load()
	TranslationServer.set_locale(resolve(lang))


static func resolve(lang: String) -> String:
	if lang in SUPPORTED:
		return lang
	return "nb" if OS.get_locale_language() in ["nb", "no", "nn"] else "en"


static func t(text: String) -> String:
	return str(TranslationServer.translate(text))


## Tekst fra serveren. Med nøkkel + argumenter kan den oversettes; ellers vises teksten.
static func server_text(msg: Dictionary) -> String:
	var key = msg.get("key")
	if key is String and key != "":
		var args = msg.get("args", [])
		var pattern := t(key)
		if args is Array and not args.is_empty():
			return pattern % args
		return pattern
	return t(str(msg.get("text", "")))


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var translation := Translation.new()
	translation.locale = "en"
	for k in EN:
		translation.add_message(k, EN[k])
	TranslationServer.add_translation(translation)


const EN := {
	# --- Meny og felles
	"Fire på rad": "Four in a Row",
	"i 3D · mot AI, lokalt eller online": "in 3D · vs AI, local or online",
	"Spill mot AI": "Play vs AI",
	"To spillere på samme enhet": "Two players, one device",
	"To spillere": "Two players",
	"Spill online": "Play online",
	"Innstillinger": "Settings",
	"Tilbake": "Back",
	"Start": "Start",
	"Lagre": "Save",
	"Feil": "Error",

	# --- Spilloppsett
	"Nytt rom": "New room",
	"Vanskelighetsgrad": "Difficulty",
	"Lett": "Easy",
	"Middels": "Medium",
	"Vanskelig": "Hard",
	"Brett": "Board",
	"Regler": "Rules",
	"Må blokkere": "Must block",
	"Kan motstanderen vinne på neste trekk, må du stoppe det.": "If your opponent can win next move, you must stop it.",
	"Ikke gi bort seier": "No gifted wins",
	"Du kan ikke legge slik at motstanderen kan vinne rett over.": "You can't play where your opponent could win right on top.",
	"Klokke (minutter + sekunder per trekk)": "Clock (minutes + seconds per move)",
	"Av": "Off",
	"Uten klokke": "No clock",
	"Hvem starter": "Who starts",
	"Jeg": "Me",
	"Motstander": "Opponent",
	"Tilfeldig": "Random",
	"Annenhver": "Alternate",
	"Spiller 1": "Player 1",
	"Spiller 2": "Player 2",
	"Verten": "Host",
	"Gjesten": "Guest",
	"Synlighet": "Visibility",
	"Privat rom": "Private room",
	"Vises ikke i listen. Venner blir med med koden.": "Not shown in the list. Friends join with the code.",
	"Opprett rom": "Create room",

	# --- Spillet
	"Meny": "Menu",
	"Chat": "Chat",
	"Chat •": "Chat •",
	"Pause": "Paused",
	"Fortsett": "Continue",
	"Gi opp": "Resign",
	"Til hovedmenyen": "Main menu",
	"Spill igjen": "Play again",
	"Se på brettet": "View the board",
	"Din tur": "Your turn",
	"Boten tenker…": "The bot is thinking…",
	"%s sin tur": "%s's turn",
	"Venter på %s…": "Waiting for %s…",
	"%s (deg)": "%s (you)",
	"Du vant!": "You won!",
	"Du tapte": "You lost",
	"%s vant!": "%s won!",
	"Uavgjort": "Draw",
	"Brettet er fullt": "The board is full",
	"Tiden gikk ut": "Time ran out",
	"Ga opp": "Resigned",
	"Motstanderen forlot partiet": "Your opponent left the game",
	"Trykk igjen for å legge brikken": "Tap again to place the piece",
	"%s: %s": "%s: %s",
	"Bot": "Bot",
	"Partiet er ferdig.": "The game is over.",
	"Utenfor brettet.": "Outside the board.",
	"Kolonnen er full.": "That column is full.",
	"Du må blokkere!": "You must block!",
	"Det trekket gir bort seieren.": "That move gives away the win.",
	"Det er ikke din tur.": "It's not your turn.",

	# --- Online
	"Bli med med kode": "Join with code",
	"Bli med": "Join",
	"F.eks. KXRTA": "E.g. KXRTA",
	"Åpne rom": "Open rooms",
	"Ingen åpne rom akkurat nå. Opprett ett!": "No open rooms right now. Create one!",
	"%s sitt rom": "%s's room",
	"Tilkoblet som %s": "Connected as %s",
	"Kobler til %s…%s": "Connecting to %s…%s",
	"Frakoblet": "Disconnected",
	"frakoblet": "disconnected",
	"Ugyldig serveradresse: %s": "Invalid server address: %s",
	"Fikk ikke kontakt med %s": "Couldn't reach %s",
	"Rom": "Room",
	"Gi koden til en venn, så kan de bli med.": "Give the code to a friend so they can join.",
	"Spillere": "Players",
	"Klar!": "Ready!",
	"Ikke klar likevel": "Not ready after all",
	"Endre regler": "Change rules",
	"Forlat rommet": "Leave room",
	"Venter på motstander…": "Waiting for an opponent…",
	"Venter på motstanderen…": "Waiting for your opponent…",
	"klar": "ready",
	"ikke klar": "not ready",
	"Mistet forbindelsen. Kobler til igjen…": "Connection lost. Reconnecting…",
	"Partiet ble avbrutt (serveren startet på nytt).": "The game was interrupted (the server restarted).",
	"Skriv en melding…": "Write a message…",
	"Send": "Send",
	"Lykke til!": "Good luck!",
	"Bra trekk!": "Nice move!",
	"Oi!": "Whoa!",
	"GG": "GG",

	# --- Meldinger fra serveren
	"%s mistet forbindelsen…": "%s lost the connection…",
	"%s er tilbake.": "%s is back.",
	"%s ble med.": "%s joined.",
	"%s forlot rommet.": "%s left the room.",
	"%s vil spille igjen!": "%s wants a rematch!",
	"Send hello først.": "Send hello first.",
	"Ukjent melding: %s": "Unknown message: %s",
	"Klienten er utdatert. Last inn siden på nytt.": "The game is out of date. Reload the page.",
	"Fant ikke rommet %s.": "Couldn't find room %s.",
	"Rommet er fullt.": "The room is full.",
	"Ugyldig melding.": "Invalid message.",

	# --- Innstillinger
	"Kallenavn": "Nickname",
	"Navnet ditt": "Your name",
	"Profilbilde": "Profile picture",
	"Velg bilde…": "Choose picture…",
	"Fjern bilde": "Remove picture",
	"Kunne ikke lese bildet. Prøv et PNG- eller JPEG-bilde.": "Couldn't read the picture. Try a PNG or JPEG image.",
	"Velg profilbilde": "Choose profile picture",
	"Bilder": "Images",
	"Brikke": "Piece",
	"Venstre: hjemmedrakt. Høyre: bortedrakt (brukes når motstanderen har samme skin).":
		"Left: home kit. Right: away kit (used when your opponent has the same skin).",
	"Merke på toppen": "Top decal",
	"Seiersanimasjon": "Victory animation",
	"Hurtigmeldinger i chatten": "Quick chat messages",
	"Tom": "Empty",
	"Tilbakestill hurtigmeldinger": "Reset quick messages",
	"Språk / Language": "Språk / Language",
	"Automatisk": "Automatic",
	"Norsk": "Norsk",
	"English": "English",
	"Lyd og følelse": "Sound and feel",
	"Lyd": "Sound",
	"Vibrasjon": "Vibration",
	"På mobil, der nettleseren støtter det.": "On mobile, where the browser supports it.",
	"Server (avansert)": "Server (advanced)",

	# --- Skins, merker og seiersanimasjoner
	"Havblå": "Ocean",
	"Glør": "Ember",
	"Lime": "Lime",
	"Gull": "Gold",
	"Krom": "Chrome",
	"Galakse": "Galaxy",
	"Lava": "Lava",
	"Neon": "Neon",
	"Holografisk": "Holographic",
	"Marmor": "Marble",
	"Karbon": "Carbon",
	"Racing": "Racing",
	"Ingen": "None",
	"Stjerne": "Star",
	"Prikk": "Dot",
	"Ring": "Ring",
	"Kryss": "Cross",
	"Diamant": "Diamond",
	"Hjerte": "Heart",
	"Klassisk": "Classic",
	"Fyrverkeri": "Fireworks",
	"Konfetti": "Confetti",
	"Sjokkbølge": "Shockwave",
	"Lyn": "Lightning",
}
