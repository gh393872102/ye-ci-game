extends RefCounted
## Versioned, atomic local persistence. Seed/RNG/offers and live battle snapshot travel together.
const VERSION := 1
static func save(path: String, state: Dictionary) -> Dictionary:
	if path.is_empty() or state.is_empty():
		return {"ok":false,"reason":"P5_SAVE_INVALID"}
	var payload := JSON.stringify(state,"",true,true)
	var envelope := {"version":VERSION,"checksum":payload.sha256_text(),"payload":payload}
	var temp := path + ".tmp"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file == null:
		return {"ok":false,"reason":"P5_SAVE_FAILED"}
	file.store_string(JSON.stringify(envelope))
	file.flush()
	file.close()
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path)) != OK:
		return {"ok":false,"reason":"P5_SAVE_FAILED"}
	return {"ok":true,"reason":"P5_SAVED"}

static func load_save(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		return {"ok":false,"reason":"P5_SAVE_MISSING"}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or parsed.get("version") != VERSION or not parsed.get("payload") is String or not parsed.get("checksum") is String:
		return {"ok":false,"reason":"P5_SAVE_INVALID"}
	if parsed.payload.sha256_text() != parsed.checksum:
		return {"ok":false,"reason":"P5_SAVE_INVALID"}
	var state = JSON.parse_string(parsed.payload)
	if not state is Dictionary:
		return {"ok":false,"reason":"P5_SAVE_INVALID"}
	return {"ok":true,"reason":"P5_LOADED","state":state}
