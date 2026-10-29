extends Node
## Autoload "Online": Supabase client (server/README.md, docs/ROADMAP.md P6a). STUB: the interface for P6b, nothing is
## sent yet. Every request answers "offline" on the next frame.
## One account operation at a time: register / rename / set_avatar / delete_me all answer on `done`.

signal done(ok: bool, error: String) ## register / rename / set_avatar / delete_me finished; error is a server code (ERRORS) or "offline"
signal board(rows: Array, own_row: Dictionary) ## rows: [{rank, player_id, name, avatar, value, (best_run: day, victory, modifiers)}]; own_row {} if unranked
signal board_failed(error: String)
signal player(stats: Dictionary) ## {player_id, name, avatar, points, points_rank, days, rescued, kills, best: {value, day, victory, modifiers}, runs, wins} (runs/wins -1 for other players)
signal player_failed(error: String)
signal online_changed(online: bool)

const ERRORS := {
	"offline": "No connection to the server.",
	"name_taken": "That name is already taken.",
	"name_invalid": "Names have 3-16 letters, digits, space, _ or -.",
	"name_banned": "That name is not allowed.",
	"avatar_invalid": "Pick one of the portraits.",
	"already_registered": "This profile is already registered online.",
	"no_player": "This profile is not registered online yet.",
	"rate_limit": "Too many requests, try again in a minute.",
}

var enabled := false ## false in headless tests (SMOKE): nothing is sent
var ranked := false ## the running run counts for the leaderboard (false: offline at run start, never sent)


## Server reachable (the last request got an answer).
func is_online() -> bool:
	return false


## This profile has a player row on the server (auth.json).
func is_registered() -> bool:
	return false


func register(_name: String, _avatar: int) -> void:
	_fail_done.call_deferred()


func rename(_name: String) -> void:
	_fail_done.call_deferred()


func set_avatar(_avatar: int) -> void:
	_fail_done.call_deferred()


## Deletes player, runs and auth user on the server and the local tokens/outbox.
func delete_me() -> void:
	_fail_done.call_deferred()


## stats: {day, rescued, kills, ended, victory, modifiers}. Queued in the outbox; values only grow on the server.
func submit_run(_run_id: String, _stats: Dictionary) -> void:
	pass


## kind: "points" | "days" | "rescued" | "kills" | "best_run". Answers on `board` or `board_failed`.
func fetch_board(_kind: String, _limit := 50) -> void:
	board_failed.emit.call_deferred("offline")


## Answers on `player` or `player_failed`.
func fetch_player(_id: String) -> void:
	player_failed.emit.call_deferred("offline")


## Run start (main.gd, new run only): first upsert; if it fails the run is unranked.
func begin_run(_modifiers := []) -> void:
	pass


## Run over or abandoned (Game.record_run).
func end_run(_day: int, _rescued: int, _kills: int, _victory := false) -> void:
	pass


## Title text: "Offline - this run is not ranked" for an unranked saved run or while offline, else "".
func title_notice() -> String:
	return ""


func error_text(code: String) -> String:
	return ERRORS.get(code, "Server error (%s)." % code)


func _fail_done() -> void:
	done.emit(false, "offline")
