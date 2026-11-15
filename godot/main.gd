extends Node3D
## Scene greybox : construit le monde 3D par code a partir des donnees JSON.
## Aucune regle de jeu ici : tout passe par l'API de Game (godot/core/game.gd).
## Les constantes ci-dessous reglent la SENSATION (distances, vitesse),
## pas l'economie (qui reste dans data/*.json).

const FIELD_GAP := 4.0         # ecart entre le hangar et les champs (m) : regle la longueur des allers-retours
const TILE_STEP := 1.0         # pas de la grille de ble (m)
# Vitesse et rayon de recolte viennent de l'equipement (data/equipment.json) : game.stats
const HUB_HALF := 4.0          # demi-taille de la dalle du hangar (m)
const PC_POS := Vector3(2.6, 0, -2.6)
const PC_RANGE := 1.8          # distance pour utiliser le PC (m)
const CAMERA_OFFSET := Vector3(0, 14, 10)
const SAVE_INTERVAL := 10.0
const COLOR_RIPE := Color(0.89, 0.73, 0.23)
const COLOR_CUT := Color(0.45, 0.33, 0.2)
const COLOR_GROW := Color(0.55, 0.65, 0.25)

var game: Game
var player: Node3D
var camera: Camera3D
var field_nodes := {}          # id -> { root, mm, cache, label, w, h }
var field_origins := {}        # id -> Vector3, calcule a partir des tailles de champs
var world_half := 40.0         # limite de deplacement (m)
var visual_acc := 0.0
var hud := {}
var mats := {}
var tile_mesh: BoxMesh
var save_acc := 0.0
var message_left := 0.0
var saving_enabled := true
var use_save := true           # false dans les tests : partie neuve, sans lire la sauvegarde


func _ready() -> void:
	var data := DataLoader.load_data()
	if data.is_empty():
		return
	game = Game.new(data, Storage.load_save() if use_save else null)

	mats = {
		"soil": _mat(Color(0.54, 0.42, 0.27)),
		"locked": _mat(Color(0.35, 0.35, 0.35)),
		"hub": _mat(Color(0.6, 0.6, 0.62)),
		"pillar": _mat(Color(0.3, 0.3, 0.32)),
		"pc": _mat(Color(0.2, 0.45, 0.9)),
		"player": _mat(Color(0.9, 0.3, 0.25)),
		"vehicle": _mat(Color(0.2, 0.6, 0.25)),
		"reach": _mat(Color(1, 1, 1, 0.25)),
	}
	mats["reach"].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mats["reach"].shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tile_mesh = BoxMesh.new()
	tile_mesh.size = Vector3(0.85, 1.0, 0.85)
	var tile_mat := StandardMaterial3D.new()
	tile_mat.vertex_color_use_as_albedo = true   # couleur par instance du MultiMesh
	tile_mesh.material = tile_mat

	_compute_layout()
	_build_environment()
	_build_hub()
	for def in data["fields"]:
		_build_field(def)
	_build_player()
	_build_hud()

	game.field_completed.connect(_on_field_completed)
	game.field_unlocked.connect(_on_field_unlocked)
	game.sack_full.connect(func(): _show_message("Sac plein ! Retourne au hangar pour vendre."))
	game.equipment_bought.connect(_on_equipment_bought)
	game.sold.connect(func(v: float): _show_message("Vendu : +%s" % _fmt(v)))


func _process(delta: float) -> void:
	if game == null:
		return
	_move_player(delta)
	game.tick(delta)
	_harvest_around_player()

	var p := player.position
	if absf(p.x) <= HUB_HALF and absf(p.z) <= HUB_HALF:
		game.sell()   # entrer dans le hangar vend automatiquement
	hud["panel"].visible = p.distance_to(PC_POS) <= PC_RANGE

	_update_fields(delta)
	_update_hud(delta)

	save_acc += delta
	if save_acc >= SAVE_INTERVAL:
		save_acc = 0.0
		_save()


# ---------- Joueur ----------
func _move_player(delta: float) -> void:
	# Touches PHYSIQUES : W/A/S/D = Z/Q/S/D sur un clavier AZERTY
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.z -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.z += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1
	if dir != Vector3.ZERO:
		dir = dir.normalized()
		player.position += dir * float(game.stats["moveSpeed"]) * delta
		player.position.x = clampf(player.position.x, -world_half, world_half)
		player.position.z = clampf(player.position.z, -world_half, world_half)
		player.rotation.y = atan2(dir.x, dir.z)
	var target := player.position + _camera_offset()
	camera.position = camera.position.lerp(target, 1.0 - exp(-8.0 * delta))
	camera.look_at(player.position)


func _harvest_around_player() -> void:
	var p := player.position
	for def in game.data["fields"]:
		var id: String = def["id"]
		var f: Dictionary = game.state["fields"][id]
		if not f["unlocked"]:
			continue
		var fn: Dictionary = field_nodes[id]
		var w: int = fn["w"]
		var h: int = fn["h"]
		var tiles: Array = f["tiles"]
		# Position du joueur en coordonnees de grille, puis seulement les tuiles proches
		var local: Vector3 = p - fn["root"].position
		var cx := local.x / TILE_STEP + (w - 1) * 0.5
		var cz := local.z / TILE_STEP + (h - 1) * 0.5
		var r := float(game.stats["harvestRadius"]) / TILE_STEP
		for z in range(maxi(0, ceili(cz - r)), mini(h - 1, floori(cz + r)) + 1):
			for x in range(maxi(0, ceili(cx - r)), mini(w - 1, floori(cx + r)) + 1):
				var i: int = z * w + x
				if tiles[i] != 1:
					continue
				if Vector2(x - cx, z - cz).length() <= r:
					if not game.harvest_tile(id, i):
						return   # sac plein


# ---------- Construction du monde ----------
func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _label3d(text: String, pos: Vector3, parent: Node, size := 64) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(l)
	return l


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.78, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(world_half * 2 + 4, world_half * 2 + 4)
	ground.mesh = pm
	ground.material_override = _mat(Color(0.42, 0.58, 0.3))
	add_child(ground)


func _build_hub() -> void:
	_box(Vector3(HUB_HALF * 2, 0.1, HUB_HALF * 2), Vector3(0, 0.05, 0), mats["hub"], self)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(Vector3(0.3, 3.5, 0.3), Vector3(sx * (HUB_HALF - 0.2), 1.75, sz * (HUB_HALF - 0.2)), mats["pillar"], self)
	_box(Vector3(0.8, 1.2, 0.6), PC_POS + Vector3(0, 0.6, 0), mats["pc"], self)
	_label3d("PC", PC_POS + Vector3(0, 1.8, 0), self, 48)
	_label3d("HANGAR (vente)", Vector3(0, 4.2, 0), self, 72)


## Place les champs autour du hangar selon slot.col / slot.row (grille 3x3, hangar au centre).
## Chaque colonne et ligne est aussi large que son plus grand champ : aucun chevauchement.
func _compute_layout() -> void:
	var col_w := {1: 0.0, 2: HUB_HALF * 2, 3: 0.0}
	var row_h := {1: 0.0, 2: HUB_HALF * 2, 3: 0.0}
	for def in game.data["fields"]:
		var c := int(def["slot"]["col"])
		var r := int(def["slot"]["row"])
		col_w[c] = maxf(col_w[c], int(def["width"]) * TILE_STEP)
		row_h[r] = maxf(row_h[r], int(def["height"]) * TILE_STEP)
	var col_x := {1: -(col_w[2] / 2 + FIELD_GAP + col_w[1] / 2), 2: 0.0, 3: col_w[2] / 2 + FIELD_GAP + col_w[3] / 2}
	var row_z := {1: -(row_h[2] / 2 + FIELD_GAP + row_h[1] / 2), 2: 0.0, 3: row_h[2] / 2 + FIELD_GAP + row_h[3] / 2}
	for def in game.data["fields"]:
		field_origins[def["id"]] = Vector3(col_x[int(def["slot"]["col"])], 0, row_z[int(def["slot"]["row"])])
	world_half = maxf(col_w[2] / 2 + FIELD_GAP + maxf(col_w[1], col_w[3]),
		row_h[2] / 2 + FIELD_GAP + maxf(row_h[1], row_h[3])) + 6.0


func _tile_local(i: int, w: int, h: int) -> Vector3:
	return Vector3((i % w - (w - 1) * 0.5) * TILE_STEP, 0, (floori(float(i) / w) - (h - 1) * 0.5) * TILE_STEP)


func _build_field(def: Dictionary) -> void:
	var id: String = def["id"]
	var w := int(def["width"])
	var h := int(def["height"])
	var unlocked: bool = game.state["fields"][id]["unlocked"]

	var root := Node3D.new()
	root.position = field_origins[id]
	add_child(root)
	_box(Vector3(w * TILE_STEP + 0.4, 0.05, h * TILE_STEP + 0.4), Vector3(0, 0.025, 0), mats["soil"] if unlocked else mats["locked"], root)

	# Un seul MultiMesh par champ : des milliers d'epis en un appel de dessin
	var mm: MultiMesh = null
	if unlocked:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = tile_mesh
		mm.instance_count = w * h
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		root.add_child(mmi)
	var label := _label3d("", Vector3(0, 2.2, -h * 0.5 * TILE_STEP), root)
	field_nodes[id] = {"root": root, "mm": mm, "cache": [], "label": label, "w": w, "h": h}


func _build_player() -> void:
	player = Node3D.new()
	add_child(player)
	_build_player_model()

	camera = Camera3D.new()
	add_child(camera)
	camera.position = player.position + _camera_offset()
	camera.look_at(player.position)


## Reconstruit le modele selon l'equipement : a pied (capsule) ou vehicule (gros cube),
## plus un disque au sol qui montre le rayon de recolte.
func _build_player_model() -> void:
	for c in player.get_children():
		c.queue_free()
	if game.current_equipment()["model"] == "vehicule":
		_box(Vector3(2.4, 1.2, 3.4), Vector3(0, 0.8, 0), mats["vehicle"], player)
		_box(Vector3(1.4, 1.0, 1.2), Vector3(0, 1.9, -0.8), mats["player"], player)    # cabine
		_box(Vector3(float(game.stats["harvestRadius"]) * 2, 0.4, 0.6), Vector3(0, 0.4, 2.0), mats["pillar"], player)   # barre de coupe
	else:
		var body := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.4
		cm.height = 1.8
		body.mesh = cm
		body.material_override = mats["player"]
		body.position.y = 0.9
		player.add_child(body)
		_box(Vector3(0.25, 0.25, 0.4), Vector3(0, 1.4, 0.4), mats["pillar"], player)   # "nez" : direction

	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = float(game.stats["harvestRadius"])
	cyl.bottom_radius = cyl.top_radius
	cyl.height = 0.02
	disc.mesh = cyl
	disc.material_override = mats["reach"]
	disc.position.y = 0.04
	player.add_child(disc)


## Camera un peu plus haute quand le rayon de coupe grandit
func _camera_offset() -> Vector3:
	return CAMERA_OFFSET * (1.0 + float(game.stats["harvestRadius"]) * 0.12)


# ---------- Mise a jour visuelle ----------
func _update_fields(delta: float) -> void:
	# Les epis en train de repousser grandissent : rafraichis 10 fois par seconde
	visual_acc += delta
	var refresh_growth := visual_acc >= 0.1
	if refresh_growth:
		visual_acc = 0.0
	for def in game.data["fields"]:
		var id: String = def["id"]
		var f: Dictionary = game.state["fields"][id]
		var fn: Dictionary = field_nodes[id]
		if not f["unlocked"]:
			fn["label"].text = "%s\nVerrouillé : %s" % [def["name"], _fmt(float(def["unlockCost"]))]
			continue
		var tiles: Array = f["tiles"]
		var regrow: Array = f["regrow"]
		fn["label"].text = "%s\n%d / %d épis mûrs" % [def["name"], game.ripe_count(id), tiles.size()]
		var full := maxf(0.01, Formulas.grow_time(game.data, game.stats, def["crop"]))
		var cache: Array = fn["cache"]
		if cache.size() != tiles.size():
			cache.resize(tiles.size())
			cache.fill(-1)
		for i in tiles.size():
			if tiles[i] == 1:
				if cache[i] != 1:
					cache[i] = 1
					_set_tile(fn, i, true, 1.0)
			elif refresh_growth or cache[i] != 0:
				cache[i] = 0
				_set_tile(fn, i, false, 1.0 - clampf(regrow[i] / full, 0.0, 1.0))


## growth : 0 = vient d'etre coupe, 1 = presque mur
func _set_tile(fn: Dictionary, i: int, ripe: bool, growth: float) -> void:
	var height := 0.7 if ripe else lerpf(0.06, 0.45, growth)
	var pos := _tile_local(i, fn["w"], fn["h"]) + Vector3(0, height * 0.5, 0)
	var mm: MultiMesh = fn["mm"]
	mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1, height, 1)), pos))
	mm.set_instance_color(i, COLOR_RIPE if ripe else COLOR_CUT.lerp(COLOR_GROW, growth))


func _on_field_completed(id: String, bonus: float) -> void:
	var l := _label3d("Champ propre ! +%s" % _fmt(bonus), field_nodes[id]["root"].position + Vector3(0, 2, 0), self, 96)
	l.modulate = Color(1, 0.9, 0.3)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", 6.0, 1.5)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.chain().tween_callback(l.queue_free)


func _on_equipment_bought(_id: String) -> void:
	_build_player_model()
	_show_message("Nouvel équipement : %s !" % game.current_equipment()["name"])


func _on_field_unlocked(id: String) -> void:
	field_nodes[id]["root"].queue_free()
	_build_field(game.field_def(id))
	_show_message("%s débloqué !" % game.field_def(id)["name"])


# ---------- HUD ----------
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var top := VBoxContainer.new()
	top.position = Vector2(16, 16)
	layer.add_child(top)
	hud["money"] = _label(top, 32)
	hud["sack"] = _label(top, 20)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(240, 14)
	bar.show_percentage = false
	top.add_child(bar)
	hud["sack_bar"] = bar
	hud["stats"] = _label(top, 14)
	var help := _label(top, 14)
	help.text = "ZQSD / flèches : bouger\nMarche sur le blé pour récolter\nEntre dans le hangar pour vendre\nApproche du PC bleu pour améliorer\nF8 : +10 000 (Maj+F8 : +1 M, test)\nF9 : effacer la sauvegarde"

	var msg := _label(layer, 26)
	msg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	msg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.position.y = 24
	hud["message"] = msg

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -16
	panel.offset_top = 16
	panel.visible = false
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_label(box, 22).text = "PC d'amélioration"
	hud["equipment_label"] = _label(box, 16)
	var eb := Button.new()
	eb.pressed.connect(game.buy_next_equipment)
	box.add_child(eb)
	hud["equipment_button"] = eb
	_label(box, 18).text = "Améliorations"
	hud["upgrade_buttons"] = {}
	for def in game.data["upgrades"]:
		var b := Button.new()
		b.pressed.connect(game.buy_upgrade.bind(def["id"]))
		box.add_child(b)
		hud["upgrade_buttons"][def["id"]] = b
	_label(box, 18).text = "Champs"
	hud["field_buttons"] = {}
	for def in game.data["fields"]:
		var b := Button.new()
		b.pressed.connect(game.unlock_field.bind(def["id"]))
		box.add_child(b)
		hud["field_buttons"][def["id"]] = b
	hud["panel"] = panel


func _label(parent: Node, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l


func _update_hud(delta: float) -> void:
	var st := game.stats
	hud["money"].text = "Argent : %s" % _fmt(game.state["money"])
	hud["sack"].text = "Sac : %s / %s" % [_fmt(game.sack_count()), _fmt(st["sackCapacity"])]
	hud["sack_bar"].max_value = st["sackCapacity"]
	hud["sack_bar"].value = game.sack_count()
	hud["stats"].text = "Épis récoltés : %s   Champs finis : %d   Auto : %s épi/s" % [
		_fmt(game.state["totals"]["tilesHarvested"]), game.state["totals"]["fieldsCompleted"], str(st["autoHarvestRate"])]

	if hud["panel"].visible:
		var cur := game.current_equipment()
		hud["equipment_label"].text = "Équipement : %s (rayon %s m, vitesse %s m/s)" % [
			cur["name"], String.num(st["harvestRadius"], 1), String.num(st["moveSpeed"], 1)]
		var nxt := game.next_equipment()
		var eb: Button = hud["equipment_button"]
		if nxt.is_empty():
			eb.text = "Équipement au maximum"
			eb.disabled = true
		else:
			eb.text = "Acheter : %s, %s   [%s]" % [nxt["name"], nxt["desc"], _fmt(float(nxt["cost"]))]
			eb.disabled = not game.can_buy_next_equipment()
		for def in game.data["upgrades"]:
			var id: String = def["id"]
			var b: Button = hud["upgrade_buttons"][id]
			var cost := "MAX" if game.is_upgrade_maxed(id) else _fmt(game.get_upgrade_cost(id))
			b.text = "%s (niv. %d) : %s   [%s]" % [def["name"], game.upgrade_level(id), def["desc"], cost]
			b.disabled = not game.can_buy_upgrade(id)
		for def in game.data["fields"]:
			var id: String = def["id"]
			var b: Button = hud["field_buttons"][id]
			b.visible = not game.state["fields"][id]["unlocked"]
			b.text = "Débloquer %s   [%s]" % [def["name"], _fmt(float(def["unlockCost"]))]
			b.disabled = not game.can_unlock_field(id)

	message_left -= delta
	hud["message"].modulate.a = clampf(message_left, 0.0, 1.0)


func _show_message(text: String) -> void:
	hud["message"].text = text
	message_left = 2.0


func _fmt(n: float) -> String:
	n = floorf(n)
	if n < 10000:
		return str(int(n))
	var units := ["k", "M", "G", "T"]
	var u := -1
	while n >= 1000 and u < units.size() - 1:
		n /= 1000.0
		u += 1
	var decimals := 2 if n < 10 else (1 if n < 100 else 0)
	return String.num(n, decimals) + units[u]


# ---------- Sauvegarde ----------
func _save() -> void:
	if saving_enabled and game:
		Storage.write_save(game.serialize())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()


func _unhandled_input(event: InputEvent) -> void:
	# Triche de test (uniquement depuis l'editeur) : F8 = +10 000, Maj+F8 = +1 000 000
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_F8 and OS.is_debug_build():
		var amount := 1000000.0 if event.shift_pressed else 10000.0
		game.state["money"] += amount   # volontairement hors totals.earned : ne fausse pas les stats
		_show_message("Triche : +%s" % _fmt(amount))
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_F9:
		saving_enabled = false
		Storage.clear_save()
		get_tree().reload_current_scene()
