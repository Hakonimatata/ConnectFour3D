class_name Protocol
extends RefCounted
## Meldingene mellom klient og server. Alt er JSON med feltet "t" (type).
## Se Plan.md, seksjon 7.2. Øk VERSION når meldingene endres på en måte
## som gjør at gamle klienter ikke lenger fungerer.

const VERSION := 3
const MAX_BYTES := 64 * 1024   ## Meldinger med profilbilder kan bli noen titalls KB
const MAX_NAME := 16
const MAX_CHAT := 200
const MAX_ANNOUNCEMENT := 300
const COUNTDOWN_MS := 3000   ## nedtelling (3, 2, 1) før hvert parti: klokken og trekkene venter så lenge

# Klient -> server
const HELLO := "hello"               ## { name, skin, decal?, win_fx?, avatar?, look_pending?, version, token?, session? }
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
# Kontoer, statistikk og turneringer
const REGISTER := "register"         ## { username, password }
const LOGIN := "login"               ## { username, password }
const LOGOUT := "logout"             ## { session }
const GET_STATS := "get_stats"       ## { username? }  (tom = deg selv)
const GET_LEADERBOARD := "get_leaderboard"
const LIST_TOURNAMENTS := "list_tournaments"
const GET_TOURNAMENT := "get_tournament"       ## { id }  (følger også siden: endringer sendes med en gang)
const TOURNAMENT_JOIN := "tournament_join"     ## { id }
const TOURNAMENT_LEAVE := "tournament_leave"   ## { id }
const TOURNAMENT_CREATE := "tournament_create" ## { data }        (admin)
const TOURNAMENT_UPDATE := "tournament_update" ## { id, data }    (admin)
const TOURNAMENT_ACTION := "tournament_action" ## { id, action }  (admin: publish, start, cancel, delete)
const SET_LOOK := "set_look"         ## { skin, decal, win_fx, decal_color, away, avatar? }  (f.eks. byttet skin i venterommet; avatar bare når bildet er byttet)
# Runde 9: tilskuere, global chat, dagens oppgave og repriser
const WATCH := "watch"               ## { code }  (se på et parti som spilles, eller en turneringskamp)
const GLOBAL_CHAT := "global_chat"   ## { text, channel }  (generelt | velkommen | tilbakemelding)
const GET_PUZZLE := "get_puzzle"
const PUZZLE_SOLVE := "puzzle_solve" ## { day, moves: [[x, y], ...] (bare dine trekk), attempts }
const LIST_GAMES := "list_games"     ## { username? }  (tom = deg selv)
const GET_GAME := "get_game"         ## { id }
# Runde 13: admin
const ADMIN := "admin"               ## { action: ban | unban | announce | award | banned_list, username?, reason?, text?, name?, design? }
# Runde 14: venner og kanaler
const FRIEND := "friend"             ## { action: list | request | accept | decline | remove | invite, username? }
const VIEW_TOURNAMENT := "view_tournament" ## { id }  (0 = slutt å følge). Serveren sender endringer med en gang.
const USER_SEARCH := "user_search"   ## { query }  (finn spillere på navn)
# Runde 15: tilbakemeldinger etter første turnering
const REACT := "react"               ## { kind }  (tilskuer reagerer: en av REACTIONS)
const TOURNAMENT_CHAT := "tournament_chat" ## { id, text }  (tom tekst = send historikken)

# Server -> klient
const WELCOME := "welcome"           ## { player_id, token, resumed, user?, avatar?, look? }  (innlogget: kontoens profilbilde og utseende)
const ROOM_LIST := "room_list"       ## { rooms: [{ code, host, options }], live: [{ code, players, moves, spectators, tournament }] }
const ROOM_STATE := "room_state"     ## { code, private, options, you, in_game, players: [...], tournament?: { id, name, ranked, walkover_in } }
const GAME_START := "game_start"     ## { options, first, you, players, clocks, number }
const GAME_SYNC := "game_sync"       ## som game_start + { moves, running, over, result, reason, line }
const MOVE_MADE := "move_made"       ## { x, y, player, ply, clocks, running }
const MOVE_REJECTED := "move_rejected" ## { text, hints }
const GAME_OVER := "game_over"       ## { result, reason, winner, line, elo? { "1": {before, after}, ... } }
const CHAT_MSG := "chat"             ## { from, seat, text }
const NOTICE := "notice"             ## { text }  (statusmeldinger)
const ERROR := "error"               ## { code, text }
const PONG := "pong"
const SESSION := "session"           ## { token, user, avatar, look }  (innlogget. Kontoens profilbilde ("" = ingen) og utseende { skin, decal, win_fx, decal_color, away })
const AUTH_ERROR := "auth_error"     ## { key, text }
const LOGGED_OUT := "logged_out"
const STATS := "stats"               ## { user }  (user har også avatar)
const LEADERBOARD := "leaderboard"   ## { elo: [...], wins: [...], forced: [...] }
const TOURNAMENT_LIST := "tournament_list"     ## { tournaments: [...], admin }
const TOURNAMENT_STATE := "tournament_state"   ## { tournament }
const TOURNAMENT_NOTICE := "tournament_notice" ## { key, args, tournament, room }  («Gå til kamp»)
const ROOM_CLOSED := "room_closed"   ## { key, args, tournament? }  (turnering-id når det var en turneringskamp)
const PRESENCE := "presence"         ## { online, playing, users: [{ name, elo, playing }] }
const LAST_GAME := "last_game"       ## { game, games }  (siste ferdige parti og de tre siste, nyeste først. Vises i hovedmenyen. Etter hello og etter hvert parti)
const GLOBAL_MSG := "global_msg"     ## { kind: "chat" | "event" | "announcement", channel ("*" = alle), time, from?, elo?, text, key?, args? }
const GLOBAL_HISTORY := "global_history" ## { messages: [...], channels: [...] }  (sendes etter hello)
const SPECTATORS := "spectators"     ## { count }  (til alle i rommet)
const PUZZLE := "puzzle"             ## { puzzle, solved, count, solvers: [{ username, attempts, elo }] }
const PUZZLE_RESULT := "puzzle_result" ## { ok, rank, first } eller { ok: false, text }
const GAME_LIST := "game_list"       ## { username, games: [{ id, time, players, result, reason, moves, tournament }] }
const GAME_RECORD := "game_record"   ## { game }  (hele partiet, til reprise)
const ADMIN_RESULT := "admin_result" ## { action, ok, key, args, text, banned: [{ username, reason }] }
const FRIENDS := "friends"           ## { friends: [{ username, elo, online, playing, room }], requests: [{ username, elo }], sent: [username] }
const USERS := "users"               ## { query, users: [{ username, elo, online }] }  (svar på user_search)
const FRIEND_NOTICE := "friend_notice" ## { kind: request | accepted | invite, from, code?, key, args, text }
const REACTION := "reaction"         ## { kind, from }  (til alle i rommet)
const TOURNAMENT_CHAT_MSG := "tournament_chat_msg" ## { id, history, messages: [{ from, elo, text }] }  (history = hele loggen)

## Reaksjoner tilskuere kan sende (tegnes som ikoner, se ReactionView)
const REACTIONS := ["heart", "star", "fire", "bolt"]


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
