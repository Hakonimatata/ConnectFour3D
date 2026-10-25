class_name Social
extends RefCounted
## Den globale chatten (vises i hovedmenyen hos alle som er online) og hendelser som
## publiseres der: nye Elo-nivåer, seiersrekker, tvungne seire, turneringer og dagens oppgave.
## Historikken ligger i global_chat.json, så den overlever en omstart.
##
## En melding er { kind, time, ... }:
##   chat          { from, elo (-1 = gjest), text }
##   event         { key, args, text }  (key er norsk tekst med %s/%d som klienten oversetter)
##   announcement  { from, text }  (kunngjøring fra admin; vises også som et banner hos alle)

const MAX_HISTORY := 50
const CHAT_INTERVAL_MS := 1200     ## minste tid mellom to meldinger fra samme spiller

var store: Store
var broadcast: Callable = func(_msg: Dictionary) -> void: pass


func _init(p_store: Store) -> void:
	store = p_store


func chat(from_name: String, elo: int, text: String, now_s: int) -> void:
	_add({ "kind": "chat", "from": from_name, "elo": elo, "text": text, "time": now_s })


func event(key: String, args: Array, now_s: int) -> void:
	_add({ "kind": "event", "key": key, "args": args, "text": key % args, "time": now_s })


func announce(from_name: String, text: String, now_s: int) -> void:
	_add({ "kind": "announcement", "from": from_name, "text": text.substr(0, Protocol.MAX_ANNOUNCEMENT), "time": now_s })


func history_message() -> Dictionary:
	return { "t": Protocol.GLOBAL_HISTORY, "messages": store.global_chat }


func _add(m: Dictionary) -> void:
	store.global_chat.append(m)
	while store.global_chat.size() > MAX_HISTORY:
		store.global_chat.pop_front()
	store.save_global_chat()
	var msg := m.duplicate()
	msg.t = Protocol.GLOBAL_MSG
	broadcast.call(msg)
