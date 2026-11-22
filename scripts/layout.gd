extends RefCounted
## Saved park. A missing file means the starter park.
## A file with count 0 is a cleared pad and stays empty.

const SAVE_PATH := "user://park_layout.cfg"


func load_or_default() -> Array:
	if not FileAccess.file_exists(SAVE_PATH):
		return default_items()
	var cfg := ConfigFile.new()
	var err: int = cfg.load(SAVE_PATH)
	if err != OK:
		return default_items()
	if not cfg.has_section_key("layout", "count"):
		return default_items()
	var count: int = int(cfg.get_value("layout", "count", 0))
	if count < 0:
		count = 0
	if count > 500:
		count = 500
	var items: Array = []
	for i in range(count):
		var section := "piece%d" % i
		var id: String = str(cfg.get_value(section, "id", ""))
		if id == "":
			continue
		var entry: Dictionary = {
			"id": id,
			"x": int(cfg.get_value(section, "x", 0)),
			"z": int(cfg.get_value(section, "z", 0)),
			"rot": int(cfg.get_value(section, "rot", 0)),
		}
		entry["y"] = float(cfg.get_value(section, "y", 0.0))
		if id == "corner":
			entry["x2"] = int(cfg.get_value(section, "x2", entry["x"]))
			entry["z2"] = int(cfg.get_value(section, "z2", entry["z"]))
			entry["rot2"] = int(cfg.get_value(section, "rot2", entry["rot"]))
		items.append(entry)
	return items


func save_items(items: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("layout", "version", 1)
	var index := 0
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var section := "piece%d" % index
		cfg.set_value(section, "id", str(item["id"]))
		cfg.set_value(section, "x", int(item["x"]))
		cfg.set_value(section, "z", int(item["z"]))
		cfg.set_value(section, "rot", int(item["rot"]))
		cfg.set_value(section, "y", float(item.get("y", 0.0)))
		if str(item["id"]) == "corner":
			cfg.set_value(section, "x2", int(item.get("x2", item["x"])))
			cfg.set_value(section, "z2", int(item.get("z2", item["z"])))
			cfg.set_value(section, "rot2", int(item.get("rot2", item["rot"])))
		index += 1
	cfg.set_value("layout", "count", index)
	var err: int = cfg.save(SAVE_PATH)
	if err != OK:
		push_error("Could not save the park layout")


func default_items() -> Array:
	# The rebuilt starter park: wood start, spine, funbox, rails, ledges, far quarters.
	var items: Array = []
	for x in range(-4, 5):
		_push(items, "quarter", x, -7, 0)
	_push(items, "bank", -8, -5, 0)
	_push(items, "bank", 8, -5, 0)
	for x in range(-1, 2):
		_push(items, "quarter", x, -2, 0)
		_push(items, "quarter", x, -3, 180)
	_push(items, "ramp", 6, 4, 0)
	_push(items, "ledge", 6, 3, 0)
	_push(items, "ramp", 6, 2, 180)
	for z in range(4, 7):
		_push(items, "low-rail", -4, z, 0)
	_push(items, "low-rail-end", -4, 3, 0)
	_push(items, "high-rail", 4, 0, 0)
	_push(items, "high-rail", 4, -1, 0)
	_push(items, "ledge", -8, 2, 0)
	_push(items, "ledge", -7, 2, 0)
	for x in range(-1, 2):
		for z in range(7, 10):
			_push(items, "start", x, z, 0)
	return items


func _push(items: Array, id: String, x: int, z: int, rot: int) -> void:
	items.append({"id": id, "x": x, "z": z, "rot": rot})
