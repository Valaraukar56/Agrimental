class_name Game
extends RefCounted
## Port de js/core/game.js. AUCUNE dependance a la scene 3D :
## la scene appelle cette API et ecoute ses signaux.

signal tile_harvested(field_id: String, idx: int, source: String, amount: float)
signal field_completed(field_id: String, bonus: float)
signal tile_regrown(field_id: String, idx: int)
signal sack_full
signal sold(value: float)
signal upgrade_bought(id: String, level: int)
signal field_unlocked(id: String)
signal equipment_bought(id: String)
signal drone_delivered(index: int, value: float)

var data: Dictionary
var state: Dictionary
var stats: Dictionary
var layout: Dictionary         # Layout.compute(data) : positions des champs
var _field_distance := {}      # field_id -> distance hangar -> centre du champ (m)


func _init(p_data: Dictionary, saved: Variant = null) -> void:
	data = p_data
	layout = Layout.compute(data)
	for id in layout["origins"]:
		_field_distance[id] = (layout["origins"][id] as Vector3).length()
	state = GameState.migrate(saved, data) if saved is Dictionary else GameState.create(data)
	recompute()


# ---------- Lecture ----------
func recompute() -> void:
	stats = Formulas.compute_stats(data, state)
	_sync_drones()


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


## Index du palier d'equipement possede dans data.equipment
func equipment_index() -> int:
	for i in data["equipment"].size():
		if data["equipment"][i]["id"] == state["equipment"]:
			return i
	return 0


func current_equipment() -> Dictionary:
	return data["equipment"][equipment_index()]


## Palier suivant, ou {} si on a deja le dernier
func next_equipment() -> Dictionary:
	var i := equipment_index() + 1
	return data["equipment"][i] if i < data["equipment"].size() else {}


func can_buy_next_equipment() -> bool:
	var nxt := next_equipment()
	return not nxt.is_empty() and state["money"] >= float(nxt["cost"])


func can_unlock_field(id: String) -> bool:
	return not state["fields"][id]["unlocked"] and state["money"] >= float(field_def(id)["unlockCost"])


# ---------- Actions ----------
func add_money(n: float) -> void:
	state["money"] += n
	state["totals"]["earned"] += n


## source : "player" (va dans le sac), "drone" (va dans sa soute) ou "auto" (vendu directement)
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
	elif source == "auto":
		add_money(amount * float(data["crops"][crop]["sellPrice"]))
	# source "drone" : la cargaison est geree par le drone (_tick_drones)

	f["tiles"][idx] = 0
	f["regrow"][idx] = Formulas.grow_time(data, stats, crop)
	state["totals"]["tilesHarvested"] += 1
	tile_harvested.emit(field_id, idx, source, amount)
	if not f["tiles"].has(1):
		complete_field(field_id)
	return true


## Recolte le premier epi mur (equivalent du mode sans grille du web)
func harvest_next(field_id: String, source := "player") -> bool:
	return harvest_tile(field_id, state["fields"][field_id]["tiles"].find(1), source)


## Prime quand toutes les tuiles sont coupees en meme temps
func complete_field(field_id: String) -> void:
	var bonus := Formulas.completion_bonus(data, stats, field_def(field_id))
	add_money(bonus)
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


## Les paliers s'achetent dans l'ordre ; le nouveau remplace l'ancien
func buy_next_equipment() -> bool:
	if not can_buy_next_equipment():
		return false
	var nxt := next_equipment()
	state["money"] -= float(nxt["cost"])
	state["equipment"] = nxt["id"]
	recompute()
	equipment_bought.emit(nxt["id"])
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

	# Repousse tuile par tuile
	for def in data["fields"]:
		var f: Dictionary = state["fields"][def["id"]]
		if not f["unlocked"]:
			continue
		var regrow: Array = f["regrow"]
		var tiles: Array = f["tiles"]
		for i in regrow.size():
			if regrow[i] <= 0.0:
				continue
			regrow[i] -= delta
			if regrow[i] <= 0.0:
				regrow[i] = 0.0
				tiles[i] = 1
				tile_regrown.emit(def["id"], i)

	_tick_drones(delta)


# ---------- Drones ----------
# Cycle d'un drone : idle (au hangar) -> aller -> recolte -> retour -> vente -> idle.
# Tout est en minuteurs : la scene ne fait qu'afficher (voir drone_world_position cote scene).

func _new_drone() -> Dictionary:
	return {"phase": "idle", "field": "", "t": 0.0, "dur": 0.0, "cargo": 0.0, "tile": -1}


func _sync_drones() -> void:
	var drones: Array = state["drones"]
	var n := drone_count()
	while drones.size() < n:
		drones.append(_new_drone())
	if drones.size() > n:
		drones.resize(n)
	# Une sauvegarde peut assigner plus de drones qu'on n'en a : on tronque
	var excess := total_assigned() - n
	for def in data["fields"]:
		if excess <= 0:
			break
		var id: String = def["id"]
		var take := mini(excess, assigned_count(id))
		if take > 0:
			state["droneAssign"][id] = assigned_count(id) - take
			excess -= take


func drone_count() -> int:
	return int(stats.get("droneCount", 0))


func assigned_count(field_id: String) -> int:
	return int(state["droneAssign"].get(field_id, 0))


func total_assigned() -> int:
	var total := 0
	for id in state["droneAssign"]:
		total += int(state["droneAssign"][id])
	return total


## delta = +1 ou -1. Les drones non assignes vont au champ le plus mur.
func assign_drone(field_id: String, delta: int) -> bool:
	if delta > 0:
		if total_assigned() >= drone_count() or not state["fields"][field_id]["unlocked"]:
			return false
	elif assigned_count(field_id) <= 0:
		return false
	state["droneAssign"][field_id] = assigned_count(field_id) + delta
	return true


func field_distance(field_id: String) -> float:
	return float(_field_distance[field_id])


## Champ vise par le drone i au decollage : les assignations remplissent les premiers drones
## (dans l'ordre des champs), les suivants vont au champ debloque le plus mur.
func _drone_target(i: int) -> String:
	var k := 0
	for def in data["fields"]:
		var n := assigned_count(def["id"])
		if i < k + n:
			return def["id"] if ripe_count(def["id"]) > 0 else ""
		k += n
	var best := ""
	var best_ripe := 0
	for def in data["fields"]:
		if state["fields"][def["id"]]["unlocked"]:
			var r := ripe_count(def["id"])
			if r > best_ripe:
				best = def["id"]
				best_ripe = r
	return best


func _random_ripe(field_id: String) -> int:
	var tiles: Array = state["fields"][field_id]["tiles"]
	var ripe: Array = []
	for i in tiles.size():
		if tiles[i] == 1:
			ripe.append(i)
	return -1 if ripe.is_empty() else ripe.pick_random()


func _drone_fly(d: Dictionary, phase: String) -> void:
	d["phase"] = phase
	d["dur"] = field_distance(d["field"]) / maxf(0.1, float(stats["droneSpeed"]))
	d["t"] = d["dur"]


func _tick_drones(delta: float) -> void:
	var drones: Array = state["drones"]
	var cut_time := 1.0 / maxf(0.01, float(stats["droneHarvestRate"]))
	var cap := float(stats["droneCargo"])
	for i in drones.size():
		var d: Dictionary = drones[i]
		var left := delta
		var guard := 0
		while left > 0.0 and guard < 10000:
			guard += 1
			if d["phase"] == "idle":
				var target := _drone_target(i)
				if target == "":
					break   # rien a recolter : il attend au hangar
				d["field"] = target
				_drone_fly(d, "aller")
				continue
			var step := minf(left, d["t"])
			d["t"] -= step
			left -= step
			if d["t"] > 0.0:
				continue
			match d["phase"]:
				"aller":
					d["phase"] = "recolte"
					d["t"] = cut_time
				"recolte":
					var idx := _random_ripe(d["field"])
					if idx >= 0 and d["cargo"] < cap:
						harvest_tile(d["field"], idx, "drone")
						d["cargo"] = minf(cap, d["cargo"] + float(stats["yieldPerTile"]))
						d["tile"] = idx
						d["t"] = cut_time
					if idx < 0 or d["cargo"] >= cap:
						_drone_fly(d, "retour")
				"retour":
					var price := float(data["crops"][field_def(d["field"])["crop"]]["sellPrice"])
					var value: float = d["cargo"] * price
					add_money(value)
					d["cargo"] = 0.0
					d["tile"] = -1
					d["phase"] = "idle"
					if value > 0.0:
						drone_delivered.emit(i, value)


func serialize() -> Dictionary:
	return state.duplicate(true)
