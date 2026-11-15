class_name GameState
extends RefCounted
## Port de js/core/state.js. Etat = Dictionary serialisable en JSON.
## Tuile : 1 = epi mur, 0 = recolte. regrow[i] = secondes avant repousse de la tuile i.


static func _fresh_field(def: Dictionary) -> Dictionary:
	var n := int(def["width"]) * int(def["height"])
	var tiles: Array = []
	tiles.resize(n)
	tiles.fill(1)
	var regrow: Array = []
	regrow.resize(n)
	regrow.fill(0.0)
	return {"unlocked": int(def["unlockCost"]) == 0, "tiles": tiles, "regrow": regrow}


static func create(data: Dictionary) -> Dictionary:
	var fields := {}
	for def in data["fields"]:
		fields[def["id"]] = _fresh_field(def)
	return {
		"version": int(data["balance"]["saveVersion"]),
		"money": float(data["balance"]["startMoney"]),
		"sack": {},
		"upgrades": {},
		"equipment": data["equipment"][0]["id"],   # palier possede (le premier au depart)
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
	var equip: Variant = saved.get("equipment")
	for e in data["equipment"]:
		if e["id"] == equip:
			state["equipment"] = equip
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
			var regrow: Variant = s.get("regrow")
			var has_regrow: bool = regrow is Array and regrow.size() == tiles.size()
			var full := float(data["crops"][def["crop"]]["growTime"])
			for i in tiles.size():
				f["tiles"][i] = 1 if int(tiles[i]) == 1 else 0
				if has_regrow:
					f["regrow"][i] = float(regrow[i])
				else:
					# ancienne sauvegarde (repousse par champ) : les tuiles coupees repoussent normalement
					f["regrow"][i] = 0.0 if f["tiles"][i] == 1 else full
	return state
