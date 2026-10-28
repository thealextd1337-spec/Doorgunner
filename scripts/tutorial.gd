extends Node
## First-run tutorial (docs/BASE.md section 7). main.gd adds it after the title when meta "tutorial_done" is 0
## or on the TUTORIAL button. Each step is a radio line and waits on a condition; the compass marks the settlement.
## Ends with a small forced assault tonight. The ESC menu's "Skip tutorial" calls finish(false).

const STEPS := [
	"Take off (SPACE).",
	"Fly to the marked settlement.",
	"Land next to it (SPACE) and hold the LZ: people board one by one. Noise draws zombies, keep the gun busy.",
	"Return to base and land on the pad.",
	"Open BUILD, place a Barracks blueprint, then assign 1 Build worker in WORKERS.",
	"Place 6 sandbags on the east side.",
	"Assign 1 Militia. Tonight's assault will test your line.",
]
const SCRAP_GRANT := 80 # barracks 40 + 6 sandbags 30, with some spare

var step := -1
var settlement: Node2D


func _ready() -> void:
	var world: Node2D = Game.world
	var pos: Vector2 = world.BASE_POS + Vector2(700, 0)
	for off in [Vector2.ZERO, Vector2(0, 64), Vector2(0, -64), Vector2(-64, 0), Vector2(0, 128), Vector2(0, -128), Vector2(-128, 0)]:
		if world.is_landable(pos + off):
			pos += off
			break
	settlement = world.spawn_poi("survivors", pos, RandomNumberGenerator.new(), 3)
	settlement.discovered = true
	world.radio_target = settlement
	_next()


func _process(_delta: float) -> void:
	if not Game.running:
		return
	if step < 3 and not settlement.done:
		Game.world.radio_target = settlement # radio hints would point elsewhere
	var done := false
	match step:
		0: done = not Game.heli.landed
		1: done = Game.heli.position.distance_to(settlement.position) < 160.0
		2: done = Game.passengers >= 1
		3: done = Game.rescued >= 3 or (settlement.done and Game.passengers == 0 and Game.rescued > 0) # a raid may cost people
		4: done = Game.buildings.any(func(b): return b["kind"] == "barracks") and Game.workers["build"] >= 1
		5: done = Game.sandbags.size() >= 6
		6: done = Game.workers["militia"] >= 1
	if done:
		_next()


func _next() -> void:
	step += 1
	if step >= STEPS.size():
		finish(true)
		return
	Game.radio("TUTORIAL: " + STEPS[step])
	if step == 3:
		Game.world.radio_target = null # the BASE arrow shows the way home
	if step == 4 and Game.scrap < SCRAP_GRANT:
		Game.scrap = SCRAP_GRANT
		Game.radio("Command: %d scrap released for construction." % SCRAP_GRANT)


## Marks the tutorial done; attack = true forces a small assault (8 zombies) tonight.
func finish(attack: bool) -> void:
	Game.meta["tutorial_done"] = 1
	Game._save_meta()
	if attack:
		Game.attack_pending = true
		Game.time = 0.79
		Game.tutorial_wave = 8
		Game.radio("TUTORIAL: done. A small horde is coming tonight. Hold the base.")
	if Game.world.radio_target == settlement:
		Game.world.radio_target = null
	Game.world.tutorial = null
	queue_free()
