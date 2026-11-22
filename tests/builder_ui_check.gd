extends SceneTree
## Temporary check for builder arrows, rotation memory, and the start facing arrow.


func _initialize() -> void:
	_pieces()
	call_deferred("_home")


func _pieces() -> void:
	var kit = load("res://scripts/pieces.gd").new()
	var world := Node3D.new()
	root.add_child(world)
	var pad: Node3D = kit.place(world, "start", 3, 4, 90, 0.0)
	var arrow := pad.get_node_or_null("FacingArrow") as MeshInstance3D
	if arrow == null or arrow.mesh == null:
		print("FAIL start pad has no facing arrow")
		return
	print("PASS start pad draws a facing arrow")
	var shapes := 0
	for child in pad.get_children():
		if child is CollisionShape3D:
			shapes += 1
	if shapes > 0:
		print("PASS start pad kept collision (%d)" % shapes)
	else:
		print("FAIL start pad lost collision")
	var arrays: Array = (arrow.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tip := Vector3(0, 0, 99)
	for v in verts:
		if v.z < tip.z:
			tip = v
	var world_tip: Vector3 = pad.global_transform * tip
	var dir := world_tip - pad.global_position
	dir.y = 0.0
	dir = dir.normalized()
	if dir.dot(Vector3(-1, 0, 0)) > 0.85:
		print("PASS rot 90 arrow faces -X")
	else:
		print("FAIL rot 90 arrow faces %s" % dir)
	var zero: Node3D = kit.place(world, "start", 8, 4, 0, 0.0)
	var zero_arrow := zero.get_node_or_null("FacingArrow") as MeshInstance3D
	var z_arrays: Array = (zero_arrow.mesh as ArrayMesh).surface_get_arrays(0)
	var z_verts: PackedVector3Array = z_arrays[Mesh.ARRAY_VERTEX]
	var z_tip := Vector3(0, 0, 99)
	for v in z_verts:
		if v.z < z_tip.z:
			z_tip = v
	var z_world: Vector3 = zero.global_transform * z_tip
	var z_dir := z_world - zero.global_position
	z_dir.y = 0.0
	z_dir = z_dir.normalized()
	if z_dir.dot(Vector3(0, 0, -1)) > 0.85:
		print("PASS rot 0 arrow faces -Z")
	else:
		print("FAIL rot 0 arrow faces %s" % z_dir)


func _home() -> void:
	var packed: PackedScene = load("res://scenes/home.tscn")
	var home: Node3D = packed.instantiate()
	root.add_child(home)
	for _i in 8:
		await process_frame
	var ccw := home.get_node_or_null("SpinArrows/SpinRoot/SpinCCW") as Control
	var cw := home.get_node_or_null("SpinArrows/SpinRoot/SpinCW") as Control
	if ccw == null or cw == null:
		print("FAIL spin arrows were not created")
	else:
		var layer := home.get_node_or_null("SpinArrows") as CanvasLayer
		print("PASS spin arrows exist layer %d" % layer.layer)
		print("ccw vis=%s size=%s pos=%s" % [ccw.visible, ccw.size, ccw.position])
		print("cw vis=%s size=%s pos=%s" % [cw.visible, cw.size, cw.position])
		if ccw.visible and cw.visible and ccw.size.x >= 40.0 and cw.size.y >= 40.0:
			print("PASS arrows are visible and at least 40px")
		else:
			print("FAIL arrows hidden or tiny")
		var tex := (ccw as TextureRect).texture
		var img := tex.get_image()
		var opaque := 0
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				if img.get_pixel(x, y).a > 0.4:
					opaque += 1
		if opaque > 40:
			print("PASS arrow texture has pixels (%d)" % opaque)
		else:
			print("FAIL arrow texture empty (%d)" % opaque)
		var ghost: Node = home.get("ghost")
		print("ghost %s aim %s,%s" % [ghost, home.get("aim_x"), home.get("aim_z")])
	print("buttons delete=%s clear=%s play=%s host=%s join=%s rotate=%s" % [
		_has_text(home, "Delete"),
		_has_text(home, "Clear"),
		_has_text(home, "Play"),
		_has_text(home, "Host"),
		_has_text(home, "Join"),
		_has_text(home, "Rotate"),
	])
	home._select("quarter")
	var before: int = int(home.place_rot)
	home._snap_turn(1)
	var quarter_rot: int = int(home.place_rot)
	home._select("bank")
	var bank_start: int = int(home.place_rot)
	home._snap_turn(-1)
	home._snap_turn(-1)
	home._snap_turn(-1)
	var bank_rot: int = int(home.place_rot)
	home._select("quarter")
	var quarter_back: int = int(home.place_rot)
	print("rots quarter %d -> %d, bank %d -> %d, quarter back %d" % [before, quarter_rot, bank_start, bank_rot, quarter_back])
	if quarter_rot == 90 and bank_rot == 270 and quarter_back == 90 and bank_start == 0:
		print("PASS per-piece rotation memory")
	else:
		print("FAIL rotation memory")
	var quarter: Control = home.palette_buttons["quarter"]
	var bank: Control = home.palette_buttons["bank"]
	print("palette quarter h=%s bank h=%s" % [quarter.custom_minimum_size.y, bank.custom_minimum_size.y])
	if quarter.custom_minimum_size.y > bank.custom_minimum_size.y + 10.0:
		print("PASS selected inventory row is larger")
	else:
		print("FAIL selected row did not grow")
	home._select("bank")
	if bank.custom_minimum_size.y > quarter.custom_minimum_size.y + 10.0:
		print("PASS selection size follows the new piece")
	else:
		print("FAIL selection size stuck")
	home.orbit_dist = 14.0
	home._zoom_by(-30.0, Vector2(640, 360))
	print("zoom dist %s" % home.orbit_dist)
	if absf(home.orbit_dist - 3.5) < 0.01:
		print("PASS zoom in reaches ZOOM_NEAR")
	else:
		print("FAIL zoom dist %s" % home.orbit_dist)
	var heading := atan2(sin(deg_to_rad(90.0)), cos(deg_to_rad(90.0)))
	var fwd := Vector3(-sin(heading), 0.0, -cos(heading))
	if fwd.dot(Vector3(-1, 0, 0)) > 0.9:
		print("PASS play heading for rot 90 matches the arrow")
	else:
		print("FAIL heading %s" % fwd)
	quit()


func _has_text(node: Node, text: String) -> bool:
	if node is Button and (node as Button).text == text:
		return true
	for child in node.get_children():
		if _has_text(child, text):
			return true
	return false
