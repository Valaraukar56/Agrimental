class_name Layout
extends RefCounted
## Disposition des champs autour du hangar (logique pure, lue dans balance.world).
## Grille 3x3 selon slot.col / slot.row, hangar au centre (0, 0).
## Chaque colonne et ligne est aussi large que son plus grand champ : aucun chevauchement.
## Utilisee par la logique (distance de vol des drones) ET par la scene (placement).


## Renvoie { "origins": { field_id: Vector3 }, "world_half": float, "tile_step": float, "hub_half": float }
static func compute(data: Dictionary) -> Dictionary:
	var world: Dictionary = data["balance"]["world"]
	var step := float(world["tileStep"])
	var hub_half := float(world["hubHalf"])
	var gap := float(world["fieldGap"])

	var col_w := {1: 0.0, 2: hub_half * 2, 3: 0.0}
	var row_h := {1: 0.0, 2: hub_half * 2, 3: 0.0}
	for def in data["fields"]:
		var c := int(def["slot"]["col"])
		var r := int(def["slot"]["row"])
		col_w[c] = maxf(col_w[c], int(def["width"]) * step)
		row_h[r] = maxf(row_h[r], int(def["height"]) * step)
	var col_x := {1: -(col_w[2] / 2 + gap + col_w[1] / 2), 2: 0.0, 3: col_w[2] / 2 + gap + col_w[3] / 2}
	var row_z := {1: -(row_h[2] / 2 + gap + row_h[1] / 2), 2: 0.0, 3: row_h[2] / 2 + gap + row_h[3] / 2}

	var origins := {}
	for def in data["fields"]:
		origins[def["id"]] = Vector3(col_x[int(def["slot"]["col"])], 0, row_z[int(def["slot"]["row"])])
	var world_half := maxf(col_w[2] / 2 + gap + maxf(col_w[1], col_w[3]),
		row_h[2] / 2 + gap + maxf(row_h[1], row_h[3])) + 6.0
	return {"origins": origins, "world_half": world_half, "tile_step": step, "hub_half": hub_half}


## Position locale (par rapport au centre du champ) de la tuile i
static func tile_local(i: int, w: int, h: int, step: float) -> Vector3:
	return Vector3((i % w - (w - 1) * 0.5) * step, 0, (floori(float(i) / w) - (h - 1) * 0.5) * step)
