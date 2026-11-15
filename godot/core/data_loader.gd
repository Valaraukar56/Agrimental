class_name DataLoader
extends RefCounted
## Port de js/data/loader.js. Lit les MEMES fichiers que la version web.

const FILES := ["crops", "fields", "upgrades", "balance", "equipment", "drones"]


static func load_data(base := "res://data/") -> Dictionary:
	var out := {}
	for name in FILES:
		var path: String = base + name + ".json"
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			push_error("Impossible de charger %s" % path)
			return {}
		out[name] = JSON.parse_string(text)
		if out[name] == null:
			push_error("JSON invalide : %s" % path)
			return {}
	# Ameliorations vues par Godot : sans celles reservees au web (ouvrier),
	# plus celles des drones (data/drones.json, que la version web ne lit pas).
	var ups: Array = []
	for u in out["upgrades"]:
		if not u.get("webOnly", false):
			ups.append(u)
	ups.append_array(out["drones"])
	out["upgrades"] = ups
	return out
