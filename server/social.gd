class_name Social
extends RefCounted
## Den globale chatten (vises i hovedmenyen hos alle som er online) med kanaler, og hendelser som
## publiseres der: nye Elo-nivåer, seiersrekker, tvungne seire, turneringer og dagens oppgave.
## Historikken ligger i global_chat.json, så den overlever en omstart.
##
## Kanaler (CHANNELS): «generelt» (hendelsene havner her), «velkommen» (nye kontoer ønskes
## velkommen her) og «tilbakemelding» (ønsker og feil; lagres også i feedback.jsonl til admin).
## Kunngjøringer fra admin har kanal «*» og vises i alle kanalene.
##
## En melding er { kind, channel, time, ... }:
##   chat          { from, elo (-1 = gjest), text }
##   event         { key, args, text }  (key er norsk tekst med %s/%d som klienten oversetter)
##   announcement  { from, text }  (kunngjøring fra admin; vises også som et banner hos alle)

const CHANNELS := ["generelt", "velkommen", "tilbakemelding"]
const ALL := "*"
const MAX_HISTORY := 50            ## per kanal
const CHAT_INTERVAL_MS := 1200     ## minste tid mellom to meldinger fra samme spiller

var store: Store
var broadcast: Callable = func(_msg: Dictionary) -> void: pass


func _init(p_store: Store) -> void:
	store = p_store
	for m in store.global_chat:
		if m is Dictionary and not m.has("channel"):
			m.channel = CHANNELS[0]   # meldinger fra før kanalene fantes


static func clean_channel(c: Variant) -> String:
	return str(c) if str(c) in CHANNELS else CHANNELS[0]


func chat(from_name: String, elo: int, text: String, now_s: int, channel := "generelt") -> void:
	channel = clean_channel(channel)
	_add({ "kind": "chat", "channel": channel, "from": from_name, "elo": elo, "text": text, "time": now_s })
	if channel == "tilbakemelding":
		store.append_feedback({ "time": Time.get_datetime_string_from_unix_time(now_s, true), "from": from_name,
			"text": text })


func event(key: String, args: Array, now_s: int, channel := "generelt") -> void:
	_add({ "kind": "event", "channel": clean_channel(channel), "key": key, "args": args, "text": key % args,
		"time": now_s })


func announce(from_name: String, text: String, now_s: int) -> void:
	_add({ "kind": "announcement", "channel": ALL, "from": from_name, "text": text.substr(0, Protocol.MAX_ANNOUNCEMENT),
		"time": now_s })


func history_message() -> Dictionary:
	return { "t": Protocol.GLOBAL_HISTORY, "messages": store.global_chat, "channels": CHANNELS }


func _add(m: Dictionary) -> void:
	store.global_chat.append(m)
	# Hold hver kanal (og kunngjøringene) under MAX_HISTORY: fjern den eldste i samme kanal.
	var same := store.global_chat.filter(func(x: Dictionary) -> bool: return x.get("channel") == m.channel)
	if same.size() > MAX_HISTORY:
		store.global_chat.erase(same[0])
	store.save_global_chat()
	var msg := m.duplicate()
	msg.t = Protocol.GLOBAL_MSG
	broadcast.call(msg)
