extends SceneTree
## Test de la logique portee (sans scene).
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
	check(g.state["fields"]["f1"]["unlocked"], "f1 debloque au depart")
	check(not g.state["fields"]["f2"]["unlocked"], "f2 verrouille au depart")

	var completed := [0]
	g.field_completed.connect(func(_id, _b): completed[0] += 1)
	for i in 20:
		g.harvest_tile("f1", i)
	check(g.sack_count() == 20.0, "20 epis dans le sac (%s)" % g.sack_count())
	check(completed[0] == 1, "signal field_completed emis")
	check(g.state["money"] == 10.0, "prime de champ propre = 10 (%s)" % g.state["money"])
	check(not g.harvest_tile("f1", 0), "pas de recolte pendant la repousse")

	g.sell()
	check(g.state["money"] == 30.0 and g.sack_count() == 0.0, "vente : 30 et sac vide")
	check(g.buy_upgrade("sack"), "achat du sac (25)")
	check(g.stats["sackCapacity"] == 60.0, "capacite 60 (%s)" % g.stats["sackCapacity"])
	check(g.get_upgrade_cost("sack") == 31, "cout sac niv.1 = ceil(25*1.22) = 31 (%s)" % g.get_upgrade_cost("sack"))

	g.tick(12.1)
	check(g.ripe_count("f1") == 20, "f1 a repousse apres 12 s")

	g.state["money"] = 2000.0
	check(g.buy_upgrade("farmhand"), "achat ouvrier")
	g.tick(10.0)
	check(g.ripe_count("f1") == 15, "ouvrier : 5 epis en 10 s (%d restants)" % g.ripe_count("f1"))

	# Aller-retour sauvegarde JSON (les nombres reviennent en float)
	var saved: Variant = JSON.parse_string(JSON.stringify(g.serialize()))
	var g2 := Game.new(data, saved)
	check(g2.ripe_count("f1") == 15, "sauvegarde : tuiles conservees")
	check(g2.upgrade_level("farmhand") == 1 and g2.upgrade_level("sack") == 1, "sauvegarde : niveaux conserves")
	check(g2.state["fields"]["f1"]["tiles"].has(1), "sauvegarde : tuiles relues en int")
	check(g2.harvest_tile("f1", g2.state["fields"]["f1"]["tiles"].find(1)), "recolte apres rechargement")

	print("\n%s" % ("TOUS LES TESTS PASSENT" if failures == 0 else "%d ECHEC(S)" % failures))
	quit(1 if failures else 0)
