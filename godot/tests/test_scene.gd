extends SceneTree
## Test de fumee de la scene 3D : construit le monde, teleporte le joueur.
## Lancer : Godot_console.exe --headless --path . --script res://godot/tests/test_scene.gd

var main: Node3D
var step := 0
var frames := 0


func _initialize() -> void:
	main = load("res://godot/main.tscn").instantiate()
	main.saving_enabled = false
	main.use_save = false
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 5:
		return false
	if main.get("game") == null:
		print("FAIL la scene n'a pas demarre (erreur de script ?)")
		return true
	var g: Game = main.game
	match step:
		0:
			print("OK   scene construite, %d champs" % main.field_nodes.size())
			main.player.position = main.field_nodes["f1"]["root"].position   # centre du champ 1
			step = 1
			frames = 0
		1:
			print(("OK   " if g.sack_count() > 0 else "FAIL ") + "recolte en marchant : %d epis dans le sac" % g.sack_count())
			main.player.position = Vector3.ZERO   # dans le hangar
			step = 2
			frames = 0
		2:
			var ok: bool = g.sack_count() == 0 and g.state["money"] > 0
			print(("OK   " if ok else "FAIL ") + "vente au hangar : argent = %d" % g.state["money"])
			main.player.position = main.PC_POS
			step = 3
			frames = 0
		3:
			print(("OK   " if main.hud["panel"].visible else "FAIL ") + "panneau PC visible pres du PC")
			# Acheter tous les paliers jusqu'au vehicule, puis recolter ailleurs dans le champ 1
			g.state["money"] = 1e12
			while g.buy_next_equipment():
				pass
			g.state["upgrades"]["sack"] = 100
			g.recompute()
			main.player.position = main.field_nodes["f1"]["root"].position + Vector3(4, 0, 0)
			step = 4
			frames = 0
		4:
			var r := float(g.stats["harvestRadius"])
			var got := g.sack_count()
			print(("OK   " if g.current_equipment()["model"] == "vehicule" else "FAIL ") + "equipement final : %s" % g.current_equipment()["name"])
			# disque de rayon r : environ pi*r^2 epis (x rendement par epi)
			var expected := PI * r * r * 0.6 * float(g.stats["yieldPerTile"])
			print(("OK   " if got >= expected else "FAIL ") + "recolte en vehicule, rayon %s m : %d epis (attendu >= %d)" % [r, got, expected])
			g.buy_upgrade("drone")
			main.player.position = Vector3(0, 0, 30)   # loin du hangar pour ne rien vendre soi-meme
			step = 5
			frames = 0
		5:
			if frames < 90:
				return false
			var ok_node: bool = main.drone_nodes.size() == g.drone_count() and g.drone_count() >= 1
			print(("OK   " if ok_node else "FAIL ") + "drone affiche (%d)" % main.drone_nodes.size())
			var d: Dictionary = g.state["drones"][0]
			var moved: float = (main.drone_nodes[0].position - Vector3(-2, 4.5, 2)).length()
			print(("OK   " if d["phase"] != "idle" and moved > 1.0 else "FAIL ") + "le drone a decolle : phase %s, %.1f m du hangar" % [d["phase"], moved])
			return true
	return false
