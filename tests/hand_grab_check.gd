extends SceneTree
## Temporary check: turn-hand size, near-miss freeze, and 90-degree grab rotation.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/home.tscn")
	var home: Node3D = packed.instantiate()
	root.add_child(home)
	for _i in 10:
		await process_frame
	var icon: TextureRect = home.get_node_or_null("SpinArrows/SpinRoot/SpinCW/HandIcon") as TextureRect
	var grab: Control = home.get_node_or_null("SpinArrows/SpinRoot/SpinCW") as Control
	if icon == null or grab == null or icon.texture == null:
		print("FAIL hand was not created")
		quit()
		return
	var img := icon.texture.get_image()
	var opaque := 0
	if img != null:
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				if img.get_pixel(x, y).a > 0.35:
					opaque += 1
	print("icon px %s x %s tex %s x %s opaque %d grab %s" % [icon.size.x, icon.size.y, icon.texture.get_width(), icon.texture.get_height(), opaque, grab.size])
	if opaque < 30:
		print("FAIL hand texture is empty")
	else:
		print("PASS hand texture has ink")
	var ratio := grab.size.x / maxf(icon.size.y, 1.0)
	print("grab side / icon height = %.2f" % ratio)
	if grab.size.x >= icon.size.y * 2.5 and grab.size.y >= icon.size.x * 2.5:
		print("PASS grab is much larger than the icon")
	else:
		print("FAIL grab is not much larger")
	var ids: Array[String] = ["quarter", "bank", "low-rail", "start", "ledge"]
	var all_shown := true
	for id in ids:
		home._select(id)
		home._update_ghost()
		home._place_spin_arrows()
		await process_frame
		var shown: bool = grab.visible and home.ghost != null
		print("piece %s hand=%s ghost=%s rot=%s" % [id, grab.visible, home.ghost != null, home.place_rot])
		if not shown:
			all_shown = false
	if all_shown:
		print("PASS hand shows on every tested piece")
	else:
		print("FAIL hand missing on a piece")
	home._select("quarter")
	home.place_rot = 0
	home._remember_rot("quarter", 0)
	home._remember_rot("bank", 0)
	home.ghost_key = ""
	home._update_ghost()
	home._place_spin_arrows()
	await process_frame
	var center: Vector2 = home._piece_screen_center()
	var hand: Vector2 = home._hand_center()
	var outward := hand - center
	if outward.length_squared() < 4.0:
		outward = Vector2(1, 1)
	outward = outward.normalized()
	var icon_r := icon.size.length() * 0.5
	var near := hand + outward * (icon_r + 20.0)
	var gap := hand.distance_to(center) - grab.size.x * 0.5
	print("center %s hand %s dist %.1f gap_past_grab %.1f near %s" % [center, hand, hand.distance_to(center), gap, near])
	print("hit center=%s near=%s icon_edge=%s" % [home._hand_hit(center), home._hand_hit(near), home._hand_hit(hand + outward * (icon_r * 0.5))])
	if not home._hand_hit(near):
		print("FAIL near miss is outside the grab")
	else:
		print("PASS near miss is inside the grab")
	if home._hand_hit(center):
		print("FAIL piece center is inside the grab, so a move would stick")
	else:
		print("PASS piece center is outside the grab")
	var cell := Vector2i(int(home.aim_x), int(home.aim_z))
	home._hover_at(near)
	var stuck := Vector2i(int(home.aim_x), int(home.aim_z)) == cell
	if stuck and not home._hand_hit(center):
		print("PASS hovering a near miss does not move the block")
	else:
		print("FAIL near miss moved the block to %s,%s from %s" % [home.aim_x, home.aim_z, cell])
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = near
	home._input(press)
	if not home.hand_grabbing:
		print("FAIL mouse down on the near miss did not grab")
	else:
		print("PASS mouse down on the near miss grabs")
	var far := home.camera.unproject_position(Vector3(cell.x + 4, 0.0, cell.y))
	home._hover_at(far)
	if Vector2i(int(home.aim_x), int(home.aim_z)) == cell:
		print("PASS while held, a far hover cannot slide the block")
	else:
		print("FAIL held hand slid to %s,%s" % [home.aim_x, home.aim_z])
	var base := (hand - center).angle()
	var radius := maxf(hand.distance_to(center), 48.0)
	var dragged := center + Vector2(cos(base + deg_to_rad(80.0)), sin(base + deg_to_rad(80.0))) * radius
	home._drag_hand(dragged)
	var turned: int = int(home.place_rot)
	print("rot after 80 deg drag %d cell %s,%s" % [turned, home.aim_x, home.aim_z])
	if turned == 90 or turned == 270:
		print("PASS drag snaps to a 90 degree step")
	else:
		print("FAIL rotation did not snap (%d)" % turned)
	if Vector2i(int(home.aim_x), int(home.aim_z)) == cell:
		print("PASS drag did not change the cell")
	else:
		print("FAIL drag changed the cell")
	var further := center + Vector2(cos(base + deg_to_rad(170.0)), sin(base + deg_to_rad(170.0))) * radius
	home._drag_hand(further)
	var turned2: int = int(home.place_rot)
	print("rot after 170 deg drag %d" % turned2)
	if turned2 == 180 or turned2 == 0:
		print("PASS second drag snapped again")
	else:
		print("FAIL second snap %d" % turned2)
	home._end_hand_grab()
	home.hand_hot = false
	home._hover_at(far)
	if Vector2i(int(home.aim_x), int(home.aim_z)) != cell:
		print("PASS release lets the block move again")
	else:
		print("FAIL block stayed locked after release")
	var quarter_rot: int = int(home._rot_for("quarter"))
	home._select("bank")
	var bank_rot: int = int(home.place_rot)
	home._select("quarter")
	var quarter_back: int = int(home.place_rot)
	print("memory quarter %d bank %d back %d" % [quarter_rot, bank_rot, quarter_back])
	if quarter_back == quarter_rot and bank_rot == 0 and (quarter_rot == 90 or quarter_rot == 180 or quarter_rot == 270):
		print("PASS rotation is remembered per piece")
	else:
		print("FAIL rotation memory")
	quit()
