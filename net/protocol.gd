class_name Protocol
extends RefCounted
## Meldingene mellom klient og server. Alt er JSON med feltet "t" (type).
## Se Plan.md, seksjon 7.2. Øk VERSION når meldingene endres på en måte
## som gjør at gamle klienter ikke lenger fungerer.

const VERSION := 1
const MAX_BYTES := 64 * 1024   ## Meldinger med profilbilder kan bli noen titalls KB
const MAX_NAME := 16
const MAX_CHAT := 200

# Klient -> server
const HELLO := "hello"               ## { name, skin, avatar?, version, token? }
const LIST_ROOMS := "list_rooms"
const CREATE_ROOM := "create_room"   ## { options, private }
const JOIN_ROOM := "join_room"       ## { code }
const LEAVE_ROOM := "leave_room"
const SET_OPTIONS := "set_options"   ## { options }  (kun verten)
const READY := "ready"               ## { ready }
const MOVE := "move"                 ## { x, y, ply }
const CHAT := "chat"                 ## { text }
const RESIGN := "resign"
const REMATCH := "rematch"
const PING := "ping"

# Server -> klient
const WELCOME := "welcome"           ## { player_id, token, resumed }
const ROOM_LIST := "room_list"       ## { rooms: [{ code, host, options }] }
const ROOM_STATE := "room_state"     ## { code, private, options, you, in_game, players: [...] }
const GAME_START := "game_start"     ## { options, first, you, players, clocks, number }
const GAME_SYNC := "game_sync"       ## som game_start + { moves, running, over, result, reason, line }
const MOVE_MADE := "move_made"       ## { x, y, player, ply, clocks, running }
const MOVE_REJECTED := "move_rejected" ## { text, hints }
const GAME_OVER := "game_over"       ## { result, reason, winner, line }
const CHAT_MSG := "chat"             ## { from, seat, text }
const NOTICE := "notice"             ## { text }  (statusmeldinger)
const ERROR := "error"               ## { code, text }
const PONG := "pong"


static func encode(msg: Dictionary) -> String:
	return JSON.stringify(msg)


## Gir {} hvis teksten ikke er et gyldig meldingsobjekt.
static func decode(text: String) -> Dictionary:
	if text.length() > MAX_BYTES:
		return {}
	var json := JSON.new()   # JSON.new().parse logger ikke feil ved søppel-input
	if json.parse(text) != OK:
		return {}
	var parsed = json.data
	if parsed is Dictionary and parsed.get("t") is String:
		return parsed
	return {}


static func positions_to_json(positions: Array) -> Array:
	var out := []
	for p in positions:
		out.append([p.x, p.y, p.z])
	return out


static func positions_from_json(arr: Variant) -> Array:
	var out := []
	if arr is Array:
		for p in arr:
			if p is Array and p.size() == 3:
				out.append(Vector3i(int(p[0]), int(p[1]), int(p[2])))
	return out


static func clean_name(n: Variant) -> String:
	var s := str(n).strip_edges().replace("\n", " ")
	if s == "":
		s = "Spiller"
	return s.substr(0, MAX_NAME)
