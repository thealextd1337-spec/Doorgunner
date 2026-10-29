extends Node
## Name filter test: SMOKE=filter godot --headless --path . --quit-after 30000
## Each case is [name, expected_ok]; failures are collected so one run lists all of them.

const CASES := [
	# valid
	["Maverick", true], ["Doorgunner", true], ["Ace_77", true], ["Red-Baron", true], ["Eva Lynn", true], ["abc", true],
	["SixteenCharsName1", false], # 17 chars
	# name rules
	["ab", false], ["", false], ["Bad  Spacing", false], ["Ümlaut", false], ["no!bang", false], ["tab\tname", false],
	# direct hits, case, German
	["Nigger", false], ["ARSCHLOCH", false], ["Hurensohn", false], ["Scheiße", false], ["xXFuckXx", false],
	# leetspeak and separators
	["f4gg0t", false], ["5h1t", false], ["fu_ck", false], ["n1gg3r", false], ["c u n t", false], ["$lut", false],
	# Nazi terms and number codes
	["Hitler", false], ["Sieg Heil", false], ["h1tl3r", false], ["User88", true], ["User 88", false], ["Bob_88", false], ["Max 14 88", false], ["x1488", false],
	# false positives that must pass
	["Scunthorpe", true], ["Cockpit", true], ["Raccoon", true], ["Grape Soda", true], ["Montenegro", true], ["Penistone", true],
	["Warschau", true], ["Fickle", true], ["Benazir", true], ["Spicy", true], ["Hancock", true], ["Tycoon", true],
	["Player188", true], ["Agent87", true], ["R88", true], ["Retardant", true],
]


func _ready() -> void:
	var bad: PackedStringArray = []
	for c in CASES:
		var reason := NameFilter.check(c[0])
		if (reason == "") != c[1]:
			bad.append("%s -> expected %s, got '%s'" % [var_to_str(c[0]), "ok" if c[1] else "reject", reason])
	assert(NameFilter.normalize("Scheiße 4$$") == "scheisseass", "normalize: sharp s, leetspeak")
	assert(not NameFilter.read_words(NameFilter.BANNED_PATH).is_empty() and not NameFilter.read_words(NameFilter.ALLOWED_PATH).is_empty(), "lists load")
	if not bad.is_empty():
		push_error("FILTER FAIL\n" + "\n".join(bad))
		get_tree().quit(1)
		return
	print("FILTER OK  %d cases" % CASES.size())
	get_tree().quit(0)
