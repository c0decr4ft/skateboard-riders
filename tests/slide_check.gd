extends SceneTree
## Headless checks for edge slides, the thin start pad, and the city backdrop.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var kit = load("res://scripts/pieces.gd").new()
	var world := Node3D.new()
	root.add_child(world)
	kit.build_environment(world)
	kit.build_pad(world)
	var rocks := 0
	var city := 0
	var lines := 0
	var ground := Color(0, 0, 0)
	for child in world.get_children():
		var child_name := str(child.name)
		if child_name.begins_with("HorizonRock"):
			rocks += 1
		if child_name.begins_with("CityBackdrop"):
			city += 1
		if child_name == "PlayLine":
			lines += 1
		if child_name == "HorizonGround" and child is MeshInstance3D:
			var mat := (child as MeshInstance3D).material_override as StandardMaterial3D
			if mat != null:
				ground = mat.albedo_color
	if rocks == 0 and city >= 16 and lines == 4 and ground.g < ground.r + 0.08 and ground.b < ground.r + 0.12:
		print("PASS city backdrop, no rocks, gray lot, red line")
	else:
		print("FAIL world rocks=%d city=%d lines=%d ground=%s" % [rocks, city, lines, ground])
	var skyline: Texture2D = load("res://assets/background/background_02.png") as Texture2D
	if skyline != null:
		var img := skyline.get_image()
		var clear := 0
		var solid := 0
		for y in range(0, img.get_height(), 4):
			for x in range(0, img.get_width(), 4):
				if img.get_pixel(x, y).a < 0.2:
					clear += 1
				else:
					solid += 1
		if clear > 20 and solid > 20:
			print("PASS city layer keeps transparent sky (%d clear, %d solid)" % [clear, solid])
		else:
			print("FAIL city alpha clear=%d solid=%d" % [clear, solid])
	else:
		print("FAIL city texture missing")
	var pieces := Node3D.new()
	pieces.name = "Pieces"
	world.add_child(pieces)
	kit.place(pieces, "floor-concrete", 0, 0, 0, 0.0)
	kit.place(pieces, "quarter", 3, 0, 0, 0.0)
	var pad: Node3D = kit.place(pieces, "start", 6, 0, 0, 0.0)
	var pad_box: BoxShape3D = null
	for child in pad.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			pad_box = (child as CollisionShape3D).shape as BoxShape3D
	if pad_box != null and pad_box.size.y < 0.08 and pad_box.size.x > 0.8 and pad_box.size.z > 0.8:
		print("PASS start pad is the thin wood tile %s" % pad_box.size)
	else:
		print("FAIL start pad %s" % pad_box)
	var skater := CharacterBody3D.new()
	skater.set_script(load("res://scripts/skater.gd"))
	world.add_child(skater)
	await process_frame
	skater.state = skater.State.RIDE
	skater.spawn_grace = 0.0
	skater._collect_slide_lines()
	if skater.slide_lines.size() >= 5:
		print("PASS slide edges %d" % skater.slide_lines.size())
	else:
		print("FAIL slide edges %d" % skater.slide_lines.size())
	_hold(KEY_SHIFT)
	await process_frame
	skater.airborne = false
	skater.jump_air = false
	skater.global_position = Vector3(0, 0.45, -0.72)
	skater.velocity = Vector3(4, 0, 0)
	skater.speed = 4.0
	if skater._try_start_slide():
		print("FAIL walking started a slide")
	else:
		print("PASS walking does not slide")
	skater.airborne = true
	skater.jump_air = true
	skater.velocity = Vector3(0, 1, 4)
	skater.global_position = Vector3(0, 0.5, -0.7)
	if skater._try_start_slide():
		print("FAIL a sideways jump slid")
	else:
		print("PASS missing the edge does not slide")
	skater.sliding = false
	skater.jump_air = true
	skater.airborne = true
	skater.velocity = Vector3(4, 1, 0)
	skater.speed = 4.0
	skater.global_position = Vector3(0, 0.5, -0.72)
	if skater._try_start_slide() and skater.sliding:
		print("PASS lined-up ollie slides the box edge")
	else:
		print("FAIL box slide pos=%s" % skater.global_position)
	_release(KEY_SHIFT)
	await process_frame
	if skater.sliding:
		skater._edge_slide(0.05)
	if skater.sliding:
		print("FAIL releasing Shift kept the slide")
	else:
		print("PASS releasing Shift ends the slide")
	_hold(KEY_SHIFT)
	await process_frame
	skater.sliding = false
	skater.slide_lock = 0.0
	skater.jump_air = true
	skater.airborne = true
	skater.grinding = false
	skater.global_position = Vector3(3.0, 0.9, -0.72)
	skater.velocity = Vector3(4, 0.4, 0)
	skater.speed = 4.0
	if skater._try_start_slide() and skater.sliding:
		print("PASS ramp lip slide")
		skater.speed = 8.0
		for _i in range(12):
			if not skater.sliding:
				break
			skater._edge_slide(0.05)
		if skater.sliding:
			print("FAIL lip slide never ended")
		else:
			print("PASS sliding off the lip ends it")
	else:
		print("FAIL ramp lip")
	var home: Node = load("res://scenes/home.tscn").instantiate()
	root.add_child(home)
	await process_frame
	print("buttons controls=%s host=%s join=%s delete=%s" % [_has(home, "Controls"), _has(home, "Host"), _has(home, "Join"), _has(home, "Delete")])
	quit()


func _hold(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _release(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = false
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _has(node: Node, text: String) -> bool:
	if node is Button and (node as Button).text == text:
		return true
	for child in node.get_children():
		if _has(child, text):
			return true
	return false
