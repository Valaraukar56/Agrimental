extends SceneTree
## Test de fumee de la scene 3D : construit le monde, teleporte le joueur.
## Lancer : Godot_console.exe --headless --path . --script res://godot/tests/test_scene.gd

var main: Node3D
var step := 0
var frames := 0


func _initialize() -> void:
	main = load("res://godot/main.tscn").instantiate()
	main.saving_enabled = false
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
			return true
	return false
