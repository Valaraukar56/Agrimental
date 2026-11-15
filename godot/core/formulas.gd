class_name Formulas
extends RefCounted
## Port de js/core/formulas.js. Fonctions pures : (donnees, etat) -> nombre.


## Cout exponentiel classique des jeux idle : base * croissance^niveau
static func upgrade_cost(def: Dictionary, level: int) -> int:
	return int(ceil(float(def["baseCost"]) * pow(float(def["costGrowth"]), level)))


## Stats effectives : base -> "set" de l'equipement -> "add" de l'equipement -> ameliorations
static func compute_stats(data: Dictionary, state: Dictionary) -> Dictionary:
	var stats: Dictionary = data["balance"]["baseStats"].duplicate()
	for equip in data["equipment"]:
		if equip["id"] != state["equipment"]:
			continue
		for stat in equip["set"]:
			stats[stat] = float(equip["set"][stat])
		for stat in equip["add"]:
			stats[stat] = float(stats.get(stat, 0.0)) + float(equip["add"][stat])
	for def in data["upgrades"]:
		var lvl := int(state["upgrades"].get(def["id"], 0))
		if lvl == 0:
			continue
		var stat: String = def["stat"]
		if def["op"] == "add":
			stats[stat] = float(stats[stat]) + float(def["value"]) * lvl
		elif def["op"] == "mul":
			stats[stat] = float(stats[stat]) * pow(float(def["value"]), lvl)
	return stats


static func grow_time(data: Dictionary, stats: Dictionary, crop_id: String) -> float:
	return float(data["crops"][crop_id]["growTime"]) * float(stats["growTimeMult"])


static func completion_bonus(data: Dictionary, stats: Dictionary, field_def: Dictionary) -> int:
	var tiles := int(field_def["width"]) * int(field_def["height"])
	var price := float(data["crops"][field_def["crop"]]["sellPrice"])
	return int(ceil(tiles * float(stats["yieldPerTile"]) * price * float(data["balance"]["completionBonusRatio"])))
