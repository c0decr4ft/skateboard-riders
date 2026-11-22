extends SceneTree
## Headless checks for layout roundtrip, stacking, rotation, and collision.

var lines: Array = []


func _initialize() -> void:
	_logic()
	call_deferred("_physics")


func _logic() -> void:
	var kit = load("res://scripts/pieces.gd").new()
	var pair: Array = [
		{"id": "quarter", "x": 0, "z": 0, "rot": 0, "y": 0.0},
		{"id": "quarter", "x": 1, "z": 0, "rot": 90, "y": 0.0},
		{"id": "floor-concrete", "x": 3, "z": 1, "rot": 0, "y": 0.0},
		{"id": "low-rail", "x": 4, "z": 2, "rot": 0, "y": 0.0},
		{"id": "bowl-corner-inner", "x": 5, "z": 2, "rot": 90, "y": 0.0},
	]
	var kept: Array = kit.keep_stacks(kit.absorb_corners(pair))
	if kept.size() == pair.size():
		_ok("quarters stay two and neighbors stay")
	else:
		_bad("layout shrunk from %d to %d" % [pair.size(), kept.size()])
	var stacked: Array = []
	for level in range(5):
		stacked.append({"id": "floor-concrete", "x": 2, "z": 2, "rot": 0, "y": float(level) * 0.2})
	stacked.append({"id": "quarter", "x": 2, "z": 2, "rot": 0, "y": 2.0})
	var column: Array = kit.keep_stacks(stacked)
	if column.size() == 4 and str(column[3]["id"]) == "floor-concrete":
		_ok("concrete stack stops at 4")
	else:
		_bad("stack cap kept %d" % column.size())
	var on_quarter: Array = kit.keep_stacks([
		{"id": "quarter", "x": 8, "z": 0, "rot": 0, "y": 0.0},
		{"id": "ledge", "x": 8, "z": 0, "rot": 0, "y": 0.8},
	])
	if on_quarter.size() == 1:
		_ok("refuses a piece stacked on a quarter")
	else:
		_bad("stacked on quarter kept %d" % on_quarter.size())
	if str(kit.stack_block(["floor-concrete", "floor-concrete", "floor-concrete", "floor-concrete"])) == "Stack limit is 4":
		_ok("fifth level is refused")
	else:
		_bad("fifth level was allowed")
	if str(kit.stack_block(["quarter"])) == "Only on concrete":
		_ok("stack on quarter is refused")
	else:
		_bad("stack on quarter was allowed")
	var ride: Array = kit.keep_stacks(kit.absorb_corners(pair.duplicate(true)))
	var back: Array = kit.keep_stacks(kit.absorb_corners(pair.duplicate(true)))
	var same := true
	if ride.size() != back.size():
		same = false
	else:
		for i in range(ride.size()):
			var a: Dictionary = ride[i]
			var b: Dictionary = back[i]
			if str(a["id"]) != str(b["id"]) or int(a["x"]) != int(b["x"]) or int(a["z"]) != int(b["z"]) or int(a["rot"]) != int(b["rot"]):
				same = false
	if same:
		_ok("play and back keep the same pieces")
	else:
		_bad("play and back layouts differ")
	var home_script = load("res://scripts/home.gd")
	if home_script != null:
		_ok("builder script parses")
	else:
		_bad("builder script failed to parse")
	var song = load("res://audio/blesksound-skate.mp3")
	if song != null:
		_ok("music file loads")
	else:
		_bad("music file failed to load")


func _physics() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var horizon_kit = load("res://scripts/pieces.gd").new()
	horizon_kit.build_environment(world)
	var rocks := 0
	var city := 0
	var ground := false
	for child in world.get_children():
		var child_name := str(child.name)
		if child_name.begins_with("HorizonRock"):
			rocks += 1
		if child_name.begins_with("CityBackdrop"):
			city += 1
		if child_name == "HorizonGround":
			ground = true
	if ground and rocks == 0 and city >= 8:
		_ok("city backdrop replaces the mountains (%d plates)" % city)
	else:
		_bad("backdrop ground=%s rocks=%d city=%d" % [ground, rocks, city])
	var missing := 0
	var named: Array = horizon_kit.catalog()
	for row in named:
		var entry: Dictionary = row
		var piece: Node = horizon_kit.place(world, str(entry["id"]), 40 + missing, 8, 0, 0.0)
		var count := 0
		if piece != null:
			for child in piece.get_children():
				if child is CollisionShape3D:
					count += 1
		if piece == null or count == 0:
			missing += 1
			_bad("unplaceable %s" % str(entry["id"]))
	if missing == 0:
		_ok("every catalog piece places with collision (%d)" % named.size())
	var kit = load("res://scripts/pieces.gd").new()
	var specs: Array = [
		["concrete", "floor-concrete", 0],
		["quarter", "quarter", 6],
		["bowl", "bowl-corner-inner", 12],
		["funbox", "ramp", 18],
		["ledge", "ledge", 24],
	]
	for spec in specs:
		var placed: Node = kit.place(world, str(spec[1]), int(spec[2]), 0, 0, 0.0)
		var shapes := 0
		for child in placed.get_children():
			if child is CollisionShape3D:
				shapes += 1
		if shapes == 0:
			_bad("no collision shapes on %s" % str(spec[0]))
	var first: Node = kit.place(world, "obstacle-box", 30, 0, 0, 0.0)
	var second: Node = kit.place(world, "obstacle-box", 32, 0, 90, 0.0)
	var first_id: int = first.get_instance_id()
	var second_rot: int = int(second.get_meta("rot"))
	var second_pos: Vector3 = (second as Node3D).position
	var turned: int = posmod(int(first.get_meta("rot")) + 90, 360)
	first.set_meta("rot", turned)
	(first as Node3D).rotation.y = deg_to_rad(float(turned))
	if first.get_instance_id() == first_id and int(second.get_meta("rot")) == second_rot and (second as Node3D).position == second_pos and int(first.get_meta("rot")) == 90:
		_ok("rotate changes only the selected piece")
	else:
		_bad("rotate changed a neighbor")
	for _frame in range(3):
		await physics_frame
	for spec in specs:
		var blocked: bool = await _ram(world, float(spec[2]))
		if blocked:
			_ok("collision %s" % str(spec[0]))
		else:
			_bad("phased through %s" % str(spec[0]))
	if _inside(world, Vector3(6.0, 0.2, -0.35)) and not _inside(world, Vector3(6.0, 0.5, 0.35)):
		_ok("quarter is a solid ramp")
	else:
		_bad("quarter hitbox is not a ramp")
	if _inside(world, Vector3(18.0, 0.12, -0.3)) and not _inside(world, Vector3(18.0, 0.22, 0.4)):
		_ok("funbox ramp leaves the air above the slope open")
	else:
		_bad("funbox ramp is still a block")
	var ledge: Node = kit.place(world, "ledge", 24, 0, 0, 0.0)
	var ledge_box := false
	for child in ledge.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			ledge_box = true
	if ledge_box:
		_ok("ledge stays a solid block")
	else:
		_bad("ledge lost its block hitbox")
	for line in lines:
		print(line)
	quit()


func _ram(world: Node3D, piece_x: float) -> bool:
	var body := CharacterBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	var shape := CapsuleShape3D.new()
	shape.radius = 0.13
	shape.height = 0.62
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 0.32, 0)
	body.add_child(col)
	body.position = Vector3(piece_x - 1.6, 0.0, 0.0)
	world.add_child(body)
	for _step in range(50):
		body.velocity = Vector3(5.0, 0.0, 0.0)
		body.move_and_slide()
		await physics_frame
	var inside: bool = absf(body.position.x - piece_x) < 0.35 and body.position.y < 0.08
	body.queue_free()
	return not inside


func _inside(world: Node3D, point: Vector3) -> bool:
	var space := world.get_world_3d().direct_space_state
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.collision_mask = 1
	return not space.intersect_point(query, 4).is_empty()


func _ok(text: String) -> void:
	lines.append("PASS " + text)


func _bad(text: String) -> void:
	lines.append("FAIL " + text)
