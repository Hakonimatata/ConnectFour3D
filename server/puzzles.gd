class_name Puzzles
extends RefCounted
## Dagens oppgave på serveren: lager (og husker) oppgaven for dagen, sjekker løsninger
## og fører listen over hvem som har løst den. Selve oppgavene lages av ai/puzzle.gd.
## Data i puzzles.json: { days: { "2026-10-21": { puzzle, solvers: [{ user, username, attempts, time }] } } }

const KEEP_DAYS := 14
const TOP := 20

var store: Store
var accounts: Accounts


func _init(p_store: Store, p_accounts: Accounts) -> void:
	store = p_store
	accounts = p_accounts


## Datoen (lokal tid på serveren) for et unix-tidspunkt, f.eks. "2026-10-21".
static func day_of(now_s: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return Time.get_date_string_from_unix_time(now_s + bias * 60)


## Dagens oppgave (lages første gang noen spør).
func today(now_s: int) -> Dictionary:
	var day := day_of(now_s)
	var days: Dictionary = store.puzzles.get_or_add("days", {})
	if not days.has(day):
		days[day] = { "puzzle": Puzzle.generate(day), "solvers": [] }
		var keys := days.keys()
		keys.sort()
		while keys.size() > KEEP_DAYS:
			days.erase(keys.pop_front())
		store.save_puzzles()
	return days[day]


## Meldingen til klienten: oppgaven, om du har løst den, og hvem som har løst den i dag.
func info_message(user_id: int, now_s: int) -> Dictionary:
	var d := today(now_s)
	var solvers: Array = d.solvers
	var solved := false
	var top := []
	for x in solvers:
		solved = solved or (user_id != 0 and int(x.user) == user_id)
		if top.size() < TOP:
			top.append({ "username": x.username, "attempts": x.attempts,
				"elo": int(store.users.get(int(x.user), {}).get("elo", -1)) })
	return { "t": Protocol.PUZZLE, "puzzle": d.puzzle, "solved": solved, "count": solvers.size(), "solvers": top }


## Registrerer en løsning (angriperens trekk). Gir { ok, rank, first } eller { error }.
## Gjester får sjekket løsningen, men kommer ikke på listen.
func solve(user_id: int, day: String, moves: Array, attempts: int, now_s: int) -> Dictionary:
	var d := today(now_s)
	if day != str(d.puzzle.get("day", "")):
		return { "error": "Oppgaven er byttet ut. Prøv dagens oppgave." }
	if not Puzzle.verify(d.puzzle, moves):
		return { "error": "Det var ikke en løsning." }
	if user_id == 0 or not store.users.has(user_id):
		return { "ok": true, "rank": 0, "first": false }
	for i in d.solvers.size():
		if int(d.solvers[i].user) == user_id:
			return { "ok": true, "rank": i + 1, "first": false }
	var u: Dictionary = store.users[user_id]
	d.solvers.append({ "user": user_id, "username": u.username, "attempts": clampi(attempts, 1, 99), "time": now_s })
	store.save_puzzles()
	var st: Dictionary = u.stats
	st.puzzles_solved += 1
	st.puzzle_streak = st.puzzle_streak + 1 if u.last_puzzle == day_of(now_s - 86400) else 1
	st.best_puzzle_streak = maxi(st.best_puzzle_streak, st.puzzle_streak)
	u.last_puzzle = day
	store.save_users()
	return { "ok": true, "rank": d.solvers.size(), "first": true }
