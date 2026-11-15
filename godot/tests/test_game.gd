extends SceneTree
## Test de la logique portee (sans scene). Les valeurs attendues sont calculees
## a partir des JSON : le test reste valable quand l'equilibrage change.
## Lancer : Godot_console.exe --headless --path . --script res://godot/tests/test_game.gd

var failures := 0


func check(cond: bool, label: String) -> void:
	print(("OK   " if cond else "FAIL ") + label)
	if not cond:
		failures += 1


func _init() -> void:
	var data := DataLoader.load_data()
	check(not data.is_empty(), "donnees JSON chargees")
	var g := Game.new(data)
	var f1: Dictionary = g.field_def("f1")
	var n := int(f1["width"]) * int(f1["height"])
	var price := float(data["crops"][f1["crop"]]["sellPrice"])
	var grow := float(data["crops"][f1["crop"]]["growTime"])
	check(g.state["fields"]["f1"]["unlocked"], "f1 debloque au depart")
	check(not g.state["fields"]["f2"]["unlocked"], "f2 verrouille au depart")

	# Repousse par epi
	check(g.harvest_tile("f1", 0), "recolte de la tuile 0")
	check(not g.harvest_tile("f1", 0), "tuile 0 coupee : pas de double recolte")
	check(is_equal_approx(float(g.state["fields"]["f1"]["regrow"][0]), grow), "minuteur de la tuile 0 = growTime (%s)" % grow)
	g.tick(grow * 0.5)
	check(g.harvest_tile("f1", 1), "tuile 1 recoltee a mi-chemin")
	g.tick(grow * 0.5 + 0.01)
	check(g.state["fields"]["f1"]["tiles"][0] == 1, "tuile 0 a repousse apres growTime")
	check(g.state["fields"]["f1"]["tiles"][1] == 0, "tuile 1 pas encore repoussee (minuteur independant)")
	g.tick(grow * 0.5)
	check(g.state["fields"]["f1"]["tiles"][1] == 1, "tuile 1 a repousse a son tour")

	# Prime champ propre : tout couper (avec un sac assez grand)
	g.state["upgrades"]["sack"] = 1000
	g.recompute()
	g.state["sack"] = {}
	var completed := [0]
	g.field_completed.connect(func(_id, _b): completed[0] += 1)
	var money_before: float = g.state["money"]
	for i in n:
		g.harvest_tile("f1", i)
	var bonus := Formulas.completion_bonus(data, g.stats, f1)
	check(completed[0] == 1, "signal field_completed emis")
	check(is_equal_approx(g.state["money"] - money_before, bonus), "prime de champ propre = %d" % bonus)
	var expected_sack := n * float(g.stats["yieldPerTile"])
	check(is_equal_approx(g.sack_count(), expected_sack), "%d epis dans le sac (%s)" % [expected_sack, g.sack_count()])

	var value := g.sell()
	check(is_equal_approx(value, expected_sack * price) and g.sack_count() == 0.0, "vente = %s, sac vide" % value)

	# Ameliorations
	g.state["upgrades"] = {}
	g.recompute()
	var sack_def := g.upgrade_def("sack")
	g.state["money"] = float(sack_def["baseCost"])
	check(g.buy_upgrade("sack"), "achat du sac au cout de base")
	check(is_equal_approx(g.stats["sackCapacity"], float(data["balance"]["baseStats"]["sackCapacity"]) + float(sack_def["value"])), "capacite du sac augmentee")
	check(g.get_upgrade_cost("sack") == int(ceil(float(sack_def["baseCost"]) * float(sack_def["costGrowth"]))), "cout niveau 1 = base x croissance")

	# Ouvrier
	g.tick(grow + 1.0)
	var ripe_before := g.ripe_count("f1")
	g.state["money"] = 1e9
	check(g.buy_upgrade("farmhand"), "achat ouvrier")
	var rate := float(g.stats["autoHarvestRate"])
	g.tick(4.0 / rate)
	check(ripe_before - g.ripe_count("f1") == 4, "ouvrier : 4 epis en %s s" % (4.0 / rate))

	# Aller-retour sauvegarde JSON (les nombres reviennent en float)
	var saved: Variant = JSON.parse_string(JSON.stringify(g.serialize()))
	var g2 := Game.new(data, saved)
	check(g2.ripe_count("f1") == g.ripe_count("f1"), "sauvegarde : tuiles conservees")
	check(g2.upgrade_level("farmhand") == 1, "sauvegarde : niveaux conserves")
	check(g2.state["fields"]["f1"]["tiles"].has(1), "sauvegarde : tuiles relues en int")
	var cut: int = g2.state["fields"]["f1"]["tiles"].find(0)
	check(cut >= 0 and g2.state["fields"]["f1"]["regrow"][cut] > 0.0, "sauvegarde : minuteurs conserves")

	# Ancienne sauvegarde (repousse par champ, sans tableau regrow)
	var old := {"fields": {"f1": {"unlocked": true, "tiles": g2.state["fields"]["f1"]["tiles"].duplicate(), "regrowLeft": 3}}}
	var g3 := Game.new(data, old)
	var c3: int = g3.state["fields"]["f1"]["tiles"].find(0)
	check(c3 < 0 or is_equal_approx(float(g3.state["fields"]["f1"]["regrow"][c3]), grow), "migration ancienne sauvegarde")

	# Equipements a paliers
	var ge := Game.new(data)
	var eq: Array = data["equipment"]
	check(ge.state["equipment"] == eq[0]["id"], "equipement de depart = %s" % eq[0]["name"])
	check(is_equal_approx(ge.stats["harvestRadius"], float(eq[0]["set"]["harvestRadius"])), "rayon de depart lu dans equipment.json")
	check(not ge.buy_next_equipment(), "pas d'achat d'equipement sans argent")
	var base_sack := float(ge.stats["sackCapacity"])
	for k in range(1, eq.size()):
		ge.state["money"] = float(eq[k]["cost"])
		check(ge.buy_next_equipment(), "achat du palier %d : %s" % [k, eq[k]["name"]])
		check(ge.state["money"] == 0.0, "  cout debite (%s)" % eq[k]["cost"])
		check(is_equal_approx(ge.stats["moveSpeed"], float(eq[k]["set"]["moveSpeed"])), "  vitesse remplacee")
		var add_sack := float(eq[k]["add"].get("sackCapacity", 0.0))
		check(is_equal_approx(ge.stats["sackCapacity"], base_sack + add_sack), "  bonus de sac du palier (%s)" % add_sack)
	ge.state["money"] = 1e12
	check(ge.next_equipment().is_empty() and not ge.buy_next_equipment(), "pas de palier au-dela du dernier")
	var ge2 := Game.new(data, JSON.parse_string(JSON.stringify(ge.serialize())))
	check(ge2.state["equipment"] == eq[-1]["id"] and is_equal_approx(ge2.stats["harvestRadius"], ge.stats["harvestRadius"]), "sauvegarde : equipement conserve")
	check(Game.new(data, {"equipment": "inconnu"}).state["equipment"] == eq[0]["id"], "equipement inconnu dans la sauvegarde -> palier 0")

	print("\n%s" % ("TOUS LES TESTS PASSENT" if failures == 0 else "%d ECHEC(S)" % failures))
	quit(1 if failures else 0)
