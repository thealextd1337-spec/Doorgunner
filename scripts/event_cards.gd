extends RefCounted
## The Q13 radio event cards (docs/ROADMAP2.md Q13), ONE table; the rules that run it are in events.gd. All card text is here.
## Card: {title, from (who calls), text ({name} = a base survivor, other {keys} come from the ctx of Events.offer),
##   when {..}, cd (days before it may come again, default 6), w (weight, default 1), chain_only (only as a follow-up), default (option index), opts []}
## when:  day, day_max, people, people_max (survivors at the base), morale_min, morale_max, mood_min, mood_max (bandit attitude -3..3),
##        res {key: n} (at least n), low {key: n} (below n), built [kinds], workers {job: n}, camps (an uncleared bandit camp exists),
##        place "base" (heli at the base) or "air" (flying elsewhere), night, seat (a free seat aboard), hull_below (share of max hull)
## Option: {t label, h hint, fx {}, risk [chance, fx {}, radio line], need {key: n}, chain [card id, days], out radio line}
## Keys of fx and need (events.gd RES): scrap food water fuel ammo medicine rifles (base stocks), parts (salvage), xp, hull, heli_fuel, heli_ammo.
## fx only: morale, mood (bandit attitude), join (new survivors) + join_skill, aboard + aboard_hurt (people aboard), hurt, die, leave,
##        mission (missions.offer type), zombies, raid (a bandit raid on the base).

const CARDS := {
	"stranger": {"title": "STRANGER AT THE GATE", "from": "Gate guard", "when": {"day": 3, "people": 2, "place": "base"}, "cd": 8, "default": 2,
		"text": "One man at the fence, hands up, alone. Says he can work. He's coughing a bit.",
		"opts": [
			{"t": "Take him in", "h": "+1 survivor, he might be sick", "fx": {"join": 1}, "risk": [0.3, {"hurt": 2, "morale": -2}, "Gate guard: he was sick. Two of ours are down with it."], "out": "Gate guard: he's in. Says thanks."},
			{"t": "Quarantine him", "h": "5 food, answer tomorrow", "fx": {"food": -5}, "chain": ["stranger_clear", 1], "out": "Gate guard: he's in the shed. We'll know tomorrow."},
			{"t": "Turn him away", "h": "morale -1", "fx": {"morale": -1}, "out": "Gate guard: he walked off down the road."}]},
	"stranger_clear": {"title": "QUARANTINE OVER", "from": "Medic", "chain_only": true, "default": 1,
		"text": "The stranger is clean. Used to be a field medic, he says. Wants a bunk.",
		"opts": [
			{"t": "Welcome him", "h": "+1 medic, morale +2", "fx": {"join": 1, "join_skill": "medic", "morale": 2}, "out": "Medic: good. We could use the hands."},
			{"t": "Send him on", "h": "3 food for the road", "fx": {"food": -3, "morale": 1}, "out": "Gate guard: he took the food and went north."}]},
	"sickness": {"title": "FEVER IN THE BUNKS", "from": "Medic", "when": {"day": 4, "people": 4, "place": "base"}, "cd": 10, "default": 1,
		"text": "Three bunks are sweating through the night. It spreads fast in a shared room.",
		"opts": [
			{"t": "Treat them", "h": "1 medicine, nobody down", "need": {"medicine": 1}, "fx": {"medicine": -1, "morale": 1}, "out": "Medic: caught early. Nobody is down."},
			{"t": "Isolate the bunks", "h": "1 person down, morale -1", "fx": {"hurt": 1, "morale": -1}, "out": "Medic: three bunks isolated. We wear masks."},
			{"t": "Ignore it", "h": "3 down, someone may die", "fx": {"hurt": 3, "morale": -2}, "risk": [0.3, {"die": 1}, "Medic: the fever took one overnight."], "out": "Medic: your call."}]},
	"bandit_trade": {"title": "BANDITS WANT TO TRADE", "from": "Gate guard", "when": {"day": 5, "people": 2, "camps": true, "place": "base"}, "cd": 8, "default": 2,
		"text": "Two bandits at the fence, rifles slung, white rag on a stick. They want to talk business.",
		"opts": [
			{"t": "Buy ammo", "h": "40 scrap for 150 ammo", "need": {"scrap": 40}, "fx": {"scrap": -40, "ammo": 150, "mood": 1}, "out": "Gate guard: crate over the wire, scrap back. They nodded."},
			{"t": "Sell a rifle", "h": "1 rifle for 60 scrap", "need": {"rifles": 1}, "fx": {"rifles": -1, "scrap": 60, "mood": 1}, "out": "Gate guard: rifle gone, scrap in hand. Strange feeling."},
			{"t": "Send them off", "h": "they remember it", "fx": {"mood": -1}, "out": "Gate guard: they spat and left."}]},
	"deserters": {"title": "DESERTERS", "from": "Gate guard", "when": {"day": 6, "camps": true, "place": "base"}, "cd": 12, "default": 1,
		"text": "Three bandits walked out of their camp last night. Unarmed, scared. They ask for asylum.",
		"opts": [
			{"t": "Take them in", "h": "+2 soldiers, one may be a spy", "fx": {"join": 2, "join_skill": "soldier", "mood": -1}, "risk": [0.35, {"scrap": -30, "leave": 1, "morale": -2}, "Gate guard: one of them took scrap and ran for his camp."], "out": "Gate guard: they are in. Watch them."},
			{"t": "Send them on", "h": "they leave 2 rifles behind", "fx": {"rifles": 2, "mood": -1}, "out": "Gate guard: two rifles on the pile. They went east."},
			{"t": "Send them back", "h": "bandits respect it, morale -2", "fx": {"mood": 1, "morale": -2}, "out": "Gate guard: that was cold. The camp will hear of it."}]},
	"child_radio": {"title": "A CHILD ON THE RADIO", "from": "Unknown", "when": {"day": 3, "people": 2}, "cd": 10, "default": 1,
		"text": "A small voice: \"My mum is hurt. We are in the church. Please come.\" Then static.",
		"opts": [
			{"t": "Go find her", "h": "rooftop rescue mission", "fx": {"mission": "rooftop"}, "out": "Command: location marked. Go."},
			{"t": "Tell her to hide", "h": "morale -3", "fx": {"morale": -3}, "out": "Base: we told her to hide. Nobody slept."}]},
	"stolen_supplies": {"title": "FOOD IS MISSING", "from": "Quartermaster", "when": {"day": 5, "people": 3, "place": "base"}, "cd": 8, "default": 2,
		"text": "The store is short. Someone helped themselves, and it was not a zombie.",
		"opts": [
			{"t": "Search the bunks", "h": "+8 food back, morale -3", "fx": {"food": 8, "morale": -3}, "out": "Quartermaster: found half under a mattress. Nobody's talking to the guards."},
			{"t": "Guard the store", "h": "-6 food, morale +1", "fx": {"food": -6, "morale": 1}, "out": "Quartermaster: a guard on the door tonight."},
			{"t": "Let it go", "h": "-12 food, morale -1", "fx": {"food": -12, "morale": -1}, "out": "Quartermaster: noted. The shelf is empty."}]},
	"quarrel": {"title": "WORKERS AT EACH OTHER'S THROATS", "from": "Foreman", "when": {"day": 4, "people": 4, "place": "base"}, "cd": 8, "default": 0,
		"text": "{name} and another worker are shouting over the tools. Work has stopped.",
		"opts": [
			{"t": "Split them up", "h": "morale -1", "fx": {"morale": -1}, "out": "Foreman: separated. Sulking, but working."},
			{"t": "Pay a bonus", "h": "15 scrap, morale +3", "need": {"scrap": 15}, "fx": {"scrap": -15, "morale": 3}, "out": "Foreman: money talks. They shook hands."},
			{"t": "Let them settle it", "h": "1 down, morale +1", "fx": {"hurt": 1, "morale": 1}, "out": "Foreman: a split lip. Better now."}]},
	"supply_drop": {"title": "SUPPLY DROP DOWN", "from": "Command", "when": {"day": 3, "place": "air"}, "cd": 8, "default": 1,
		"text": "A cargo plane dumped its load and went down east of you. The crates may still be there.",
		"opts": [
			{"t": "Mark the crash", "h": "black box mission", "fx": {"mission": "blackbox"}, "out": "Command: crash site marked."},
			{"t": "Send a truck", "h": "+30 scrap, may draw a crowd", "fx": {"scrap": 30}, "risk": [0.3, {"zombies": 6}, "Gunner: the truck is drawing a crowd!"], "out": "Command: the truck is on the way."}]},
	"radio_ghost": {"title": "A SIGNAL IN THE NOISE", "from": "Radio Station", "when": {"day": 6, "built": ["radio"]}, "cd": 12, "default": 1,
		"text": "Something repeats a looped scream on a dead channel. It pulls the dead like a dinner bell.",
		"opts": [
			{"t": "Send the heli", "h": "silence the screamer mission", "fx": {"mission": "screamer"}, "out": "Command: source located. Silence it."},
			{"t": "Log it", "h": "+40 XP", "fx": {"xp": 40}, "out": "Radio Station: logged. Not our problem today."}]},
	"scrap_trader": {"title": "TRADER ON THE ROAD", "from": "Pilot", "when": {"day": 7, "place": "air"}, "cd": 8, "default": 2,
		"text": "A scrapper truck flags you down from the shoulder. A man with a rifle and a smile.",
		"opts": [
			{"t": "Buy fuel", "h": "30 scrap for 60 fuel", "need": {"scrap": 30}, "fx": {"scrap": -30, "fuel": 60}, "out": "Pilot: tank cans on the truck bed, delivered to base."},
			{"t": "Buy medicine", "h": "30 scrap for 3 medicine", "need": {"scrap": 30}, "fx": {"scrap": -30, "medicine": 3}, "out": "Pilot: three boxes, delivered to base."},
			{"t": "Wave him on", "h": "nothing", "out": "Pilot: he shrugged and drove off."}]},
	"wounded_soldier": {"title": "WOUNDED SOLDIER", "from": "Pilot", "when": {"day": 2, "place": "air", "seat": true}, "cd": 8, "default": 2,
		"text": "A soldier waves at a roadblock, leg bloody. He is holding his rifle like it is the last thing he has.",
		"opts": [
			{"t": "Pick him up", "h": "+1 passenger, injured", "fx": {"aboard": 1, "aboard_hurt": 1}, "out": "Pilot: he's aboard. Bleeding, but grinning."},
			{"t": "Drop a dressing", "h": "+30 XP", "fx": {"xp": 30}, "out": "Pilot: dressing dropped. He saluted."},
			{"t": "Fly on", "h": "morale -1", "fx": {"morale": -1}, "out": "Pilot: couldn't stop. He kept waving."}]},
	"stray_dog": {"title": "A DOG AT THE WIRE", "from": "Gate guard", "when": {"day": 2, "people": 3, "place": "base"}, "cd": 14, "default": 1,
		"text": "A thin dog sits at the fence and stares at the cook. Nobody has seen a dog in weeks.",
		"opts": [
			{"t": "Keep it", "h": "morale +3, might bring trouble", "fx": {"morale": 3}, "risk": [0.2, {"zombies": 4}, "Gate guard: it barked all night. Something answered."], "out": "Base: the dog is called Sarge now."},
			{"t": "Shoo it away", "h": "morale -1", "fx": {"morale": -1}, "out": "Gate guard: it ran off. {name} took it hard."}]},
	"generator_fault": {"title": "GENERATOR DOWN", "from": "Mechanic", "when": {"day": 5, "built": ["generator"], "place": "base"}, "cd": 10, "default": 2,
		"text": "The generator coughs, shakes, and dies. The lights are out in the whole camp.",
		"opts": [
			{"t": "Repair it properly", "h": "3 spare parts", "need": {"parts": 3}, "fx": {"parts": -3}, "out": "Mechanic: new gaskets. She hums."},
			{"t": "Pay for a bodge", "h": "15 scrap", "need": {"scrap": 15}, "fx": {"scrap": -15}, "out": "Mechanic: duct tape and prayers. It runs."},
			{"t": "Let it run rough", "h": "30 fuel wasted", "fx": {"fuel": -30}, "out": "Mechanic: it burns twice the fuel, but it runs."}]},
	"well_taint": {"title": "THE WELL TASTES OF DIESEL", "from": "Medic", "when": {"day": 8, "built": ["well"], "place": "base"}, "cd": 12, "default": 0,
		"text": "A film on the water and a sour smell. Two people already drank from it.",
		"opts": [
			{"t": "Boil it", "h": "20 base fuel", "fx": {"fuel": -20}, "out": "Medic: boiled and strained. Tastes of smoke, safe."},
			{"t": "Dig a new line", "h": "30 scrap, morale +1", "need": {"scrap": 30}, "fx": {"scrap": -30, "morale": 1}, "out": "Medic: a clean line. Good work."},
			{"t": "Drink anyway", "h": "2 down, someone may die", "fx": {"hurt": 2, "morale": -1}, "risk": [0.3, {"die": 1}, "Medic: one of them didn't wake up."], "out": "Medic: I want it written down that I objected."}]},
	"bumper_crop": {"title": "BUMPER CROP", "from": "Farmer", "when": {"day": 6, "workers": {"farm": 1}, "place": "base"}, "cd": 10, "default": 1,
		"text": "The beans came in all at once. More than the kitchen can use before it rots.",
		"opts": [
			{"t": "Feast tonight", "h": "10 food, morale +5", "fx": {"food": -10, "morale": 5}, "out": "Farmer: first full bellies in weeks."},
			{"t": "Store it", "h": "+25 food", "fx": {"food": 25}, "out": "Farmer: dried and jarred. We won't starve this week."}]},
	"grumbling": {"title": "GRUMBLING IN THE MESS", "from": "Foreman", "when": {"day": 6, "morale_max": 35, "people": 3, "place": "base"}, "cd": 8, "default": 0,
		"text": "Nobody is laughing anymore. People talk about leaving. {name} has already packed.",
		"opts": [
			{"t": "Hold a meeting", "h": "5 food, morale +4", "fx": {"food": -5, "morale": 4}, "out": "Foreman: they needed to be heard."},
			{"t": "Extra rations", "h": "15 food, morale +6", "need": {"food": 15}, "fx": {"food": -15, "morale": 6}, "out": "Foreman: full plates. It helps."},
			{"t": "Ignore it", "h": "someone may leave", "risk": [0.5, {"leave": 1}, "Foreman: {name} left in the night."], "out": "Foreman: your call."}]},
	"night_off": {"title": "THE CREW WANTS A NIGHT OFF", "from": "Foreman", "when": {"day": 6, "morale_min": 75, "people": 3, "place": "base"}, "cd": 10, "default": 0,
		"text": "Good spirits, good food. They want a fire, a song, and a night with no shifts.",
		"opts": [
			{"t": "Allow it", "h": "8 food, morale +3", "fx": {"food": -8, "morale": 3}, "out": "Foreman: you could hear them from the airstrip."},
			{"t": "Keep working", "h": "+25 scrap, morale -3", "fx": {"scrap": 25, "morale": -3}, "out": "Foreman: shifts continue. Nobody's thrilled."}]},
	"ultimatum": {"title": "WARLORD'S ULTIMATUM", "from": "Bandit radio", "when": {"day": 10, "camps": true, "mood_max": 0, "place": "base"}, "cd": 14, "default": 1,
		"text": "\"Tribute at dawn, or we come for the base. Sixty scrap. Don't make me ask twice.\"",
		"opts": [
			{"t": "Pay tribute", "h": "60 scrap, they back off", "need": {"scrap": 60}, "fx": {"scrap": -60, "mood": 2}, "out": "Bandit radio: smart. We'll leave you be for a while."},
			{"t": "Offer rifles", "h": "2 rifles", "need": {"rifles": 2}, "fx": {"rifles": -2, "mood": 1}, "out": "Bandit radio: they'll do. For now."},
			{"t": "Refuse", "h": "they come tomorrow", "fx": {"mood": -1}, "chain": ["tribute_raid", 1], "out": "Bandit radio: your funeral."}]},
	"tribute_raid": {"title": "THEIR SCOUTS ARE HERE", "from": "Watchtower", "chain_only": true, "default": 0,
		"text": "Technicals on the ridge. The warlord kept his word. There is still time to settle.",
		"opts": [
			{"t": "Hold the line", "h": "a bandit raid hits tonight", "fx": {"raid": true}, "out": "Watchtower: here they come."},
			{"t": "Pay now", "h": "90 scrap, they turn around", "need": {"scrap": 90}, "fx": {"scrap": -90, "mood": 1}, "out": "Watchtower: they took it and left."}]},
	"ambush": {"title": "TECHNICALS AHEAD", "from": "Pilot", "when": {"day": 8, "mood_max": -1, "place": "air"}, "cd": 8, "default": 1,
		"text": "Two technicals parked across the road below. Gun crews waiting. They know your helicopter.",
		"opts": [
			{"t": "Fly straight through", "h": "hull -15, +40 XP", "fx": {"hull": -15, "xp": 40}, "out": "Pilot: through! Holes in the tail."},
			{"t": "Take the long way", "h": "12 fuel", "fx": {"heli_fuel": -12}, "out": "Pilot: around the hills. Burned some fuel."},
			{"t": "Suppress them", "h": "40 ammo, +80 XP", "need": {"heli_ammo": 40}, "fx": {"heli_ammo": -40, "xp": 80}, "out": "Gunner: they dove for cover. Clear."}]},
	"nurse": {"title": "A NURSE AT THE GATE", "from": "Gate guard", "when": {"day": 5, "people": 3, "place": "base"}, "cd": 12, "default": 0,
		"text": "A woman in a stained scrub top, walked two days. Says she knows where to cut and where to stitch.",
		"opts": [
			{"t": "Take her in", "h": "+1 medic", "fx": {"join": 1, "join_skill": "medic"}, "out": "Gate guard: she asked for soap first."},
			{"t": "Ask for medicine", "h": "+2 medicine, she moves on", "fx": {"medicine": 2}, "out": "Gate guard: she traded two boxes for water."}]},
	"ammo_cache": {"title": "AMMO CRATE IN A DITCH", "from": "Gunner", "when": {"day": 4, "place": "air"}, "cd": 6, "default": 1,
		"text": "A military crate in a roadside ditch. The lid is open a crack. Too neat for a wreck.",
		"opts": [
			{"t": "Load it", "h": "+60 ammo, might be bait", "fx": {"heli_ammo": 60}, "risk": [0.3, {"zombies": 5}, "Gunner: bait! They're coming out of the woods!"], "out": "Gunner: sixty rounds in the box."},
			{"t": "Leave it", "h": "nothing", "out": "Gunner: too neat. I don't like it."}]},
	"fuel_leak": {"title": "FUEL LINE LEAKED", "from": "Mechanic", "when": {"day": 6, "res": {"fuel": 100}, "place": "base"}, "cd": 10, "default": 0,
		"text": "A wet stain under the tanks, spreading. The smell is making people dizzy.",
		"opts": [
			{"t": "Mop it up", "h": "30 fuel, morale -1, fire risk", "fx": {"fuel": -30, "morale": -1}, "risk": [0.15, {"hurt": 1, "fuel": -40}, "Mechanic: a spark! The shed went up."], "out": "Mechanic: mopped and sealed."},
			{"t": "Fix it with parts", "h": "4 spare parts", "need": {"parts": 4}, "fx": {"parts": -4, "fuel": -10}, "out": "Mechanic: new line. Only a little lost."}]},
	"refugees": {"title": "A FAMILY AT THE GATE", "from": "Gate guard", "when": {"day": 8, "people": 3, "people_max": 12, "place": "base"}, "cd": 14, "default": 1,
		"text": "Four people, one carrying a sick old woman. They have no weapons and no more road.",
		"opts": [
			{"t": "Take them all", "h": "+3 survivors, 10 food, 1 down", "fx": {"join": 3, "food": -10, "hurt": 1}, "out": "Gate guard: all in. The old woman sat down and cried."},
			{"t": "Take the healthy", "h": "+2 survivors, morale -3", "fx": {"join": 2, "morale": -3}, "out": "Gate guard: two stayed. The rest walked on."},
			{"t": "Turn them away", "h": "morale -4", "fx": {"morale": -4}, "out": "Gate guard: nobody talked at dinner."}]},
	"herd_at_wire": {"title": "A HERD LEANS ON THE WIRE", "from": "Watchtower", "when": {"day": 4, "place": "base"}, "cd": 6, "default": 1,
		"text": "A slow shuffle out of the trees, thirty bodies wide. They have not seen us yet.",
		"opts": [
			{"t": "Man the wall", "h": "fight, 40 ammo, +50 XP", "fx": {"zombies": 6, "ammo": -40, "xp": 50}, "out": "Watchtower: open fire when they come close."},
			{"t": "Lights out", "h": "quiet, they might not leave", "fx": {"morale": -1}, "risk": [0.4, {"zombies": 10}, "Watchtower: they found us anyway!"], "out": "Watchtower: lights out. Nobody breathe."}]},
	"escapee": {"title": "A PRISONER STUMBLES IN", "from": "Gate guard", "when": {"day": 6, "camps": true, "place": "base"}, "cd": 10, "default": 0,
		"text": "A man with rope burns on both wrists, ran out of a bandit camp. He does not know where he is.",
		"opts": [
			{"t": "Take him in", "h": "+1 survivor, bandits angry", "fx": {"join": 1, "mood": -1}, "out": "Gate guard: he hasn't stopped eating."},
			{"t": "Hand him back", "h": "+30 scrap, morale -2", "fx": {"scrap": 30, "mood": 2, "morale": -2}, "out": "Gate guard: they paid. Some of us didn't like it."}]},
	"mechanic_offer": {"title": "A MECHANIC OFFERS HIS TOOLS", "from": "Gate guard", "when": {"day": 5, "res": {"scrap": 40}, "hull_below": 0.8, "place": "base"}, "cd": 10, "default": 2,
		"text": "A wandering mechanic looked over the helicopter and clicked his tongue. He says he can fix the hull.",
		"opts": [
			{"t": "Pay him", "h": "50 scrap, hull +40", "need": {"scrap": 50}, "fx": {"scrap": -50, "hull": 40}, "out": "Mechanic: good as new. Almost."},
			{"t": "Barter food", "h": "15 food, hull +30", "need": {"food": 15}, "fx": {"food": -15, "hull": 30}, "out": "Mechanic: a meal for a patch. Fair."},
			{"t": "No thanks", "h": "nothing", "out": "Gate guard: he shrugged and left."}]},
	"shortwave": {"title": "SHORTWAVE VOICES", "from": "Radio Station", "when": {"day": 4, "built": ["radio"]}, "cd": 10, "default": 0,
		"text": "A faint voice from the north says the coast still holds. Others answer. Real people.",
		"opts": [
			{"t": "Ask for news", "h": "morale +2, +30 XP", "fx": {"morale": 2, "xp": 30}, "out": "Radio Station: they say hold on. We held our breath."},
			{"t": "Stay silent", "h": "nothing", "out": "Radio Station: no answer sent."}]},
	"wreck_rumor": {"title": "A DRIFTER SELLS A LOCATION", "from": "Gate guard", "when": {"day": 5, "place": "base"}, "cd": 10, "default": 1,
		"text": "A drifter swears he saw an airliner go down in a field to the east. For a price, he'll draw the spot.",
		"opts": [
			{"t": "Buy the map", "h": "25 scrap, black box mission", "need": {"scrap": 25}, "fx": {"scrap": -25, "mission": "blackbox"}, "out": "Command: coordinates logged."},
			{"t": "No thanks", "h": "nothing", "out": "Gate guard: he left grumbling."}]},
	"low_food": {"title": "THE PANTRY IS EMPTY", "from": "Quartermaster", "when": {"day": 3, "people": 3, "low": {"food": 15}, "place": "base"}, "cd": 6, "default": 0,
		"text": "A few cans and a bag of rice. People are eyeing each other's plates.",
		"opts": [
			{"t": "Cut rations", "h": "+8 food, morale -4", "fx": {"food": 8, "morale": -4}, "out": "Quartermaster: half portions. Nobody likes it."},
			{"t": "Send scavengers", "h": "+25 food, may get hurt", "fx": {"food": 25}, "risk": [0.35, {"hurt": 2}, "Quartermaster: two came back bleeding."], "out": "Quartermaster: back with cans and bags."}]},
	"low_water": {"title": "THE TANK IS DRY", "from": "Quartermaster", "when": {"day": 3, "people": 3, "low": {"water": 15}, "place": "base"}, "cd": 6, "default": 0,
		"text": "The barrels echo. Lips are cracking and tempers are short.",
		"opts": [
			{"t": "Boil rainwater", "h": "15 fuel for 20 water", "need": {"fuel": 15}, "fx": {"fuel": -15, "water": 20}, "out": "Quartermaster: a pot on the stove all night."},
			{"t": "Ration it", "h": "+8 water, morale -3", "fx": {"water": 8, "morale": -3}, "out": "Quartermaster: one cup each."}]},
	"wounded_bandit": {"title": "A WOUNDED BANDIT AT THE FENCE", "from": "Gate guard", "when": {"day": 7, "camps": true, "place": "base"}, "cd": 12, "default": 1,
		"text": "A bandit crawls up to the wire, leg torn open, no weapon. He begs for help.",
		"opts": [
			{"t": "Treat him", "h": "1 medicine, bandits respect it", "need": {"medicine": 1}, "fx": {"medicine": -1, "mood": 2, "morale": -1}, "chain": ["bandit_thanks", 3], "out": "Medic: stitched. He'll live. He did not look grateful."},
			{"t": "Turn him away", "h": "nothing", "out": "Gate guard: he crawled back into the grass."},
			{"t": "End it", "h": "bandits furious, morale -2", "fx": {"mood": -2, "morale": -2}, "out": "Gate guard: it's done. Nobody said a word after."}]},
	"bandit_thanks": {"title": "A DEBT PAID", "from": "Bandit radio", "chain_only": true, "default": 0,
		"text": "\"The man you patched up is my brother. I pay my debts. Choose.\"",
		"opts": [
			{"t": "Accept the gift", "h": "+60 scrap", "fx": {"scrap": 60}, "out": "Gate guard: a bag of scrap at the gate, no note."},
			{"t": "Ask for a truce", "h": "no raids for a while", "fx": {"mood": 2}, "out": "Bandit radio: for a while. Don't test it."}]},
}
