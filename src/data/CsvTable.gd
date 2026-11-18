extends RefCounted
## Preserve original headers and strings. All failures are explicit; never skip bad rows.
static func read_table(path: String, required: PackedStringArray) -> Dictionary:
	var errors: Array[String] = []
	var rows: Dictionary = {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"rows": rows, "errors": ["Cannot open CSV: " + path]}
	var header := file.get_csv_line()
	for field in required:
		if not header.has(field):
			errors.append("%s: missing column %s" % [path, field])
	var columns: Dictionary = {}
	for field in header:
		if columns.has(field):
			errors.append("%s: duplicate column %s" % [path, field])
		columns[field] = true
	if not errors.is_empty():
		return {"rows": rows, "errors": errors}
	var line := 1
	while not file.eof_reached():
		var values := file.get_csv_line()
		line += 1
		if values.size() == 1 and values[0].is_empty():
			continue
		if values.size() != header.size():
			errors.append("%s:%d: column count mismatch" % [path, line])
			continue
		var row: Dictionary = {}
		for index in header.size():
			row[header[index]] = values[index]
		var id: String = row["id"]
		if id.is_empty() or rows.has(id):
			errors.append("%s:%d: empty or duplicate id %s" % [path, line, id])
			continue
		for field in ["生命", "攻击", "防御", "速度", "技能香耗", "变异花费"]:
			if row.has(field) and (not str(row[field]).is_valid_int() or int(row[field]) < 0):
				errors.append("%s:%d: invalid number in %s" % [path, line, field])
		row.make_read_only()
		rows[id] = row
	rows.make_read_only()
	return {"rows": rows, "errors": errors}
