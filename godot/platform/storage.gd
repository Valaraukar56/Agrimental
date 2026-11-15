class_name Storage
extends RefCounted
## Port de js/platform/storage.js : sauvegarde dans user://save.json

const SAVE_PATH := "user://save.json"


static func load_save() -> Variant:
	if not FileAccess.file_exists(SAVE_PATH):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))


static func write_save(obj: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(obj))


static func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
