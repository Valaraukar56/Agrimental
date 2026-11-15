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
			return true
	return false
