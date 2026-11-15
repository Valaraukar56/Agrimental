class_name GameState
extends RefCounted
## Port de js/core/state.js. Etat = Dictionary serialisable en JSON.
## Tuile : 1 = epi mur, 0 = recolte.


static func _fresh_field(def: Dictionary) -> Dictionary:
	var tiles: Array = []
	tiles.resize(int(def["width"]) * int(def["height"]))
	tiles.fill(1)
	return {"unlocked": int(def["unlockCost"]) == 0, "tiles": tiles, "regrowLeft": 0.0}


static func create(data: Dictionary) -> Dictionary:
	var fields := {}
	for def in data["fields"]:
		fields[def["id"]] = _fresh_field(def)
	return {
		"version": int(data["balance"]["saveVersion"]),
		"money": float(data["balance"]["startMoney"]),
		"sack": {},
		"upgrades": {},
		"fields": fields,
		"totals": {"earned": 0.0, "tilesHarvested": 0, "fieldsCompleted": 0},
		"playTime": 0.0,
	}


## Recharge une sauvegarde en tolerant les changements de donnees JSON.
## JSON renvoie des float : on reconvertit explicitement en int ou float.
static func migrate(saved: Variant, data: Dictionary) -> Dictionary:
	var state := create(data)
	if not (saved is Dictionary):
		return state
	state["money"] = float(saved.get("money", 0))
	var sack: Variant = saved.get("sack", {})
	if sack is Dictionary:
		for crop in sack:
			state["sack"][crop] = float(sack[crop])
	var ups: Variant = saved.get("upgrades", {})
	if ups is Dictionary:
		for id in ups:
			state["upgrades"][id] = int(ups[id])
	var totals: Variant = saved.get("totals", {})
	if totals is Dictionary:
		state["totals"]["earned"] = float(totals.get("earned", 0))
		state["totals"]["tilesHarvested"] = int(totals.get("tilesHarvested", 0))
		state["totals"]["fieldsCompleted"] = int(totals.get("fieldsCompleted", 0))
	state["playTime"] = float(saved.get("playTime", 0))

	var saved_fields: Variant = saved.get("fields", {})
	if not (saved_fields is Dictionary):
		return state
	for def in data["fields"]:
		var s: Variant = saved_fields.get(def["id"])
		if not (s is Dictionary):
			continue
		var f: Dictionary = state["fields"][def["id"]]
		f["unlocked"] = bool(s.get("unlocked", false)) or f["unlocked"]
		var tiles: Variant = s.get("tiles")
		if tiles is Array and tiles.size() == f["tiles"].size():
			for i in tiles.size():
				f["tiles"][i] = int(tiles[i])
			f["regrowLeft"] = float(s.get("regrowLeft", 0))
	return state
