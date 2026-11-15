class_name Game
extends RefCounted
## Port de js/core/game.js. AUCUNE dependance a la scene 3D :
## la scene appelle cette API et ecoute ses signaux.

signal tile_harvested(field_id: String, idx: int, source: String, amount: float)
signal field_completed(field_id: String, bonus: float)
signal field_regrown(field_id: String)
signal sack_full
signal sold(value: float)
signal upgrade_bought(id: String, level: int)
signal field_unlocked(id: String)

var data: Dictionary
var state: Dictionary
var stats: Dictionary
var _auto_acc := 0.0


func _init(p_data: Dictionary, saved: Variant = null) -> void:
	data = p_data
	state = GameState.migrate(saved, data) if saved is Dictionary else GameState.create(data)
	recompute()


# ---------- Lecture ----------
func recompute() -> void:
	stats = Formulas.compute_stats(data, state)


func field_def(id: String) -> Dictionary:
	for f in data["fields"]:
		if f["id"] == id:
			return f
	return {}


func upgrade_def(id: String) -> Dictionary:
	for u in data["upgrades"]:
		if u["id"] == id:
			return u
	return {}


func upgrade_level(id: String) -> int:
	return int(state["upgrades"].get(id, 0))


func sack_count() -> float:
	var total := 0.0
	for crop in state["sack"]:
		total += float(state["sack"][crop])
	return total


func sack_value() -> float:
	var total := 0.0
	for crop in state["sack"]:
		total += float(state["sack"][crop]) * float(data["crops"][crop]["sellPrice"])
	return total


func sack_free() -> float:
	return maxf(0.0, float(stats["sackCapacity"]) - sack_count())


func ripe_count(field_id: String) -> int:
	return state["fields"][field_id]["tiles"].count(1)


func get_upgrade_cost(id: String) -> int:
	return Formulas.upgrade_cost(upgrade_def(id), upgrade_level(id))


func is_upgrade_maxed(id: String) -> bool:
	var max_level: Variant = upgrade_def(id).get("maxLevel")
	return max_level != null and upgrade_level(id) >= int(max_level)


func can_buy_upgrade(id: String) -> bool:
	return not is_upgrade_maxed(id) and state["money"] >= get_upgrade_cost(id)


func can_unlock_field(id: String) -> bool:
	return not state["fields"][id]["unlocked"] and state["money"] >= float(field_def(id)["unlockCost"])


# ---------- Actions ----------
func add_money(n: float) -> void:
	state["money"] += n
	state["totals"]["earned"] += n


## source : "player" (va dans le sac) ou "auto" (vendu directement)
func harvest_tile(field_id: String, idx: int, source := "player") -> bool:
	var f: Dictionary = state["fields"].get(field_id, {})
	if f.is_empty() or not f["unlocked"] or idx < 0 or idx >= f["tiles"].size() or f["tiles"][idx] != 1:
		return false
	var def := field_def(field_id)
	var crop: String = def["crop"]
	var amount := float(stats["yieldPerTile"])

	if source == "player":
		var free := sack_free()
		if free <= 0.0:
			sack_full.emit()
			return false
		state["sack"][crop] = float(state["sack"].get(crop, 0.0)) + minf(amount, free)
	else:
		add_money(amount * float(data["crops"][crop]["sellPrice"]))

	f["tiles"][idx] = 0
	state["totals"]["tilesHarvested"] += 1
	tile_harvested.emit(field_id, idx, source, amount)
	if not f["tiles"].has(1):
		complete_field(field_id)
	return true


## Recolte le premier epi mur (equivalent du mode sans grille du web)
func harvest_next(field_id: String, source := "player") -> bool:
	return harvest_tile(field_id, state["fields"][field_id]["tiles"].find(1), source)


func complete_field(field_id: String) -> void:
	var def := field_def(field_id)
	var bonus := Formulas.completion_bonus(data, stats, def)
	add_money(bonus)
	state["fields"][field_id]["regrowLeft"] = Formulas.grow_time(data, stats, def["crop"])
	state["totals"]["fieldsCompleted"] += 1
	field_completed.emit(field_id, bonus)


func sell() -> float:
	var value := sack_value()
	if value <= 0.0:
		return 0.0
	add_money(value)
	state["sack"] = {}
	sold.emit(value)
	return value


func buy_upgrade(id: String) -> bool:
	if not can_buy_upgrade(id):
		return false
	state["money"] -= get_upgrade_cost(id)
	state["upgrades"][id] = upgrade_level(id) + 1
	recompute()
	upgrade_bought.emit(id, state["upgrades"][id])
	return true


func unlock_field(id: String) -> bool:
	if not can_unlock_field(id):
		return false
	state["money"] -= float(field_def(id)["unlockCost"])
	state["fields"][id]["unlocked"] = true
	field_unlocked.emit(id)
	return true


# ---------- Boucle ----------
func tick(delta: float) -> void:
	state["playTime"] += delta

	# Repousse des champs termines
	for def in data["fields"]:
		var f: Dictionary = state["fields"][def["id"]]
		if not f["unlocked"] or f["regrowLeft"] <= 0.0:
			continue
		f["regrowLeft"] -= delta
		if f["regrowLeft"] <= 0.0:
			f["regrowLeft"] = 0.0
			f["tiles"].fill(1)
			field_regrown.emit(def["id"])

	# Automatisation : ouvriers
	_auto_acc += float(stats["autoHarvestRate"]) * delta
	while _auto_acc >= 1.0:
		var target := pick_auto_target()
		if target.is_empty():
			_auto_acc = 0.0
			break
		harvest_tile(target["fieldId"], target["idx"], "auto")
		_auto_acc -= 1.0


## Epi mur aleatoire dans un champ debloque
func pick_auto_target() -> Dictionary:
	var candidates: Array = []
	for def in data["fields"]:
		var f: Dictionary = state["fields"][def["id"]]
		if f["unlocked"] and f["regrowLeft"] <= 0.0 and f["tiles"].has(1):
			candidates.append(def["id"])
	if candidates.is_empty():
		return {}
	var id: String = candidates.pick_random()
	var ripe: Array = []
	var tiles: Array = state["fields"][id]["tiles"]
	for i in tiles.size():
		if tiles[i] == 1:
			ripe.append(i)
	return {"fieldId": id, "idx": ripe.pick_random()}


func serialize() -> Dictionary:
	return state.duplicate(true)
