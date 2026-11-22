extends SceneTree
## Headless grind checks: jump mount, early ollie, curve, and a 90-degree corner.

var lines: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var kit = load("res://scripts/pieces.gd").new()
	var park = load("res://scripts/park.gd").new()
	var skater := CharacterBody3D.new()
	skater.set_script(load("res://scripts/skater.gd"))
	world.add_child(skater)
	await process_frame
	skater.state = skater.State.RIDE
	skater.spawn_grace = 0.0
	skater.stick_lock = 0.0

	var straight: Node3D = kit.place(world, "low-rail", 0, 0, 0, 0.0)
	var turned: Node3D = kit.place(world, "low-rail", 0, 1, 90, 0.0)
	var curve: Node3D = kit.place(world, "rail-curve", 4, 0, 0, 0.0)
	await process_frame
	var stem: PackedVector3Array = kit.rail_points(straight)
	var cross: PackedVector3Array = kit.rail_points(turned)
	var arc: PackedVector3Array = kit.rail_points(curve)
	if stem.size() >= 2 and cross.size() >= 2:
		var gap := _end_gap(stem, cross)
		if gap <= 0.9 and gap > 0.4:
			_ok("90-degree ends meet across the cell gap (%.2f)" % gap)
		else:
			_bad("90-degree end gap %.2f" % gap)
	else:
		_bad("rail samples missing")
	var joined: PackedVector3Array = park._join_rails(stem, cross)
	if joined.size() >= 4:
		_ok("corner join keeps both rails (%d pts)" % joined.size())
	else:
		_bad("corner join failed (%d pts)" % joined.size())

	_mount_cases(skater, stem)
	_early_ollie(skater, stem)
	_follow_arc(skater, arc)
	_follow_corner(skater, joined)
	_follow_separate(skater, stem, cross)

	for line in lines:
		print(line)
	quit()


func _mount_cases(skater: CharacterBody3D, line: PackedVector3Array) -> void:
	skater.grind_lines = [line]
	skater.global_position = line[0] + Vector3(0.1, -0.24, 0.2)
	skater.velocity = Vector3(0, 0, 3)
	skater.airborne = false
	skater.jump_air = false
	skater.rail_lock = 0.0
	skater.grinding = false
	if skater._try_start_grind():
		_bad("ground contact mounted a rail")
	else:
		_ok("ground contact does not mount")
	skater.airborne = true
	skater.jump_air = false
	skater.global_position = _mid(line) + Vector3(0.05, 0.08, 0)
	skater.velocity = Vector3(0, -1, 2)
	if skater._try_start_grind():
		_bad("air without a jump mounted")
	else:
		_ok("air without a jump does not mount")
	skater.jump_air = true
	skater.airborne = true
	skater.global_position = line[0] + Vector3(0.05, -0.3, 0.1)
	skater.velocity = Vector3(0, -1, 2)
	if skater._try_start_grind():
		_bad("jump below the bar mounted")
	else:
		_ok("jump below the bar does not mount")
	skater.jump_air = true
	skater.airborne = true
	skater.global_position = _mid(line) + Vector3(0.05, 0.08, 0)
	skater.velocity = Vector3(0, -2, 3)
	skater.speed = 3.0
	if skater._try_start_grind() and skater.grinding:
		_ok("jump onto the rail mounts")
	else:
		_bad("jump onto the rail did not mount")
	skater.grinding = false
	skater.jump_air = false


func _early_ollie(skater: CharacterBody3D, line: PackedVector3Array) -> void:
	skater.grind_lines = [line]
	skater.grind_index = 0
	skater.grind_line = line
	skater.grinding = true
	skater.grind_sign = 1.0
	skater.grind_balance = 0.0
	skater.grind_along = skater._line_length(line) * 0.5
	skater.speed = 6.0
	skater.charge = 0.5
	skater._space_was = true
	skater.airborne = false
	skater.jump_air = false
	var before: Vector3 = skater._point_at(line, skater.grind_along)
	var end_z: float = maxf(line[0].z, line[line.size() - 1].z)
	skater._grind_slide(0.016)
	var flat := Vector2(skater.velocity.x, skater.velocity.z).length()
	var left_early: bool = (not skater.grinding) and skater.airborne and skater.velocity.y > 3.0 and flat > 5.0 and absf(skater.global_position.z - end_z) > 0.2 and absf(skater.global_position.z - before.z) < 0.45
	if left_early and skater.rail_lock > 0.2 and skater.jump_air:
		_ok("ollie leaves mid-rail with grind speed")
	else:
		_bad("early ollie grinding=%s air=%s vy=%.2f flat=%.2f z=%.2f end=%.2f before=%.2f" % [skater.grinding, skater.airborne, skater.velocity.y, flat, skater.global_position.z, end_z, before.z])
	skater.global_position = before
	skater.airborne = true
	if skater._try_start_grind():
		_bad("ollie snapped straight back onto the rail")
	else:
		_ok("ollie does not remount during the lock")
	_hold(KEY_Q)
	skater.grinding = true
	skater.grind_line = line
	skater.grind_index = 0
	skater.grind_along = skater._line_length(line) * 0.45
	skater.grind_sign = 1.0
	skater.speed = 5.0
	skater.charge = 0.0
	skater._space_was = false
	skater.rail_lock = 0.0
	skater.board_flip = 0.0
	skater.flip_v = 0.0
	skater._grind_slide(0.1)
	if skater.grinding and absf(skater.board_flip) < 0.05 and absf(skater.board_shove) < 0.05:
		_ok("board stays flat and locked on the rail")
	else:
		_bad("grind trick grinding=%s flip=%.2f shove=%.2f" % [skater.grinding, skater.board_flip, skater.board_shove])
	_release(KEY_Q)


func _follow_arc(skater: CharacterBody3D, arc: PackedVector3Array) -> void:
	if arc.size() < 4:
		_bad("curve sample has %d points" % arc.size())
		return
	skater.grind_lines = [arc]
	skater.grind_index = 0
	skater.grind_line = arc
	skater.grinding = true
	skater.grind_sign = 1.0
	skater.grind_balance = 0.0
	skater.grind_along = 0.05
	skater.speed = 4.0
	skater.charge = 0.0
	skater._space_was = false
	skater.rail_lock = 0.0
	var center := Vector2(arc[0].x, arc[arc.size() - 1].z)
	# The arc is centered on the piece origin: start (x, z-r), end (x+r, z).
	center = Vector2(arc[arc.size() - 1].x - 0.46, arc[0].z + 0.46)
	var saw_bend := false
	var left_early := false
	for _i in range(30):
		if not skater.grinding:
			left_early = true
			break
		skater._grind_slide(0.05)
		var radius := Vector2(skater.global_position.x, skater.global_position.z).distance_to(center)
		if radius > 0.4 and skater.grind_along > skater._line_length(arc) * 0.35 and skater.grind_along < skater._line_length(arc) * 0.7:
			saw_bend = true
	if saw_bend and not left_early:
		_ok("grind follows the curved rail")
	else:
		_bad("curve follow bend=%s early=%s along=%.2f pos=%s" % [saw_bend, left_early, skater.grind_along, skater.global_position])


func _follow_corner(skater: CharacterBody3D, joined: PackedVector3Array) -> void:
	if joined.size() < 4:
		_bad("skipped joined corner")
		return
	skater.grind_lines = [joined]
	skater.grind_index = 0
	skater.grind_line = joined
	skater.grinding = true
	skater.grind_sign = 1.0
	skater.grind_balance = 0.0
	skater.grind_along = 0.05
	skater.speed = 5.0
	skater.charge = 0.0
	skater._space_was = false
	skater.rail_lock = 0.0
	var start_heading: float = skater.heading
	var turned := false
	var bailed := false
	for _i in range(40):
		if not skater.grinding:
			bailed = true
			break
		skater._grind_slide(0.05)
		if skater.grind_along > 1.3 and absf(wrapf(skater.heading - start_heading, -PI, PI)) > 0.6:
			turned = true
			break
	if turned and skater.grinding and not bailed:
		_ok("grind turns through a joined 90-degree corner")
	else:
		_bad("joined corner turned=%s grinding=%s along=%.2f heading=%.2f pos=%s" % [turned, skater.grinding, skater.grind_along, skater.heading, skater.global_position])


func _follow_separate(skater: CharacterBody3D, stem: PackedVector3Array, cross: PackedVector3Array) -> void:
	skater.grind_lines = [stem, cross]
	skater.grind_index = 0
	skater.grind_line = stem
	skater.grinding = true
	skater.grind_sign = 1.0
	skater.grind_balance = 0.0
	skater.grind_along = 0.05
	skater.speed = 5.0
	skater.charge = 0.0
	skater._space_was = false
	skater.rail_lock = 0.0
	var moved := false
	for _i in range(50):
		if not skater.grinding:
			break
		skater._grind_slide(0.05)
		if skater.grind_index == 1:
			moved = true
			break
	if moved and skater.grinding:
		_ok("grind crosses onto a separate 90-degree rail")
	else:
		_bad("separate corner index=%s grinding=%s pos=%s" % [skater.grind_index, skater.grinding, skater.global_position])


func _end_gap(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var best := 999.0
	for pa in [a[0], a[a.size() - 1]]:
		for pb in [b[0], b[b.size() - 1]]:
			best = minf(best, Vector2(pa.x - pb.x, pa.z - pb.z).length())
	return best


func _mid(line: PackedVector3Array) -> Vector3:
	return (line[0] + line[line.size() - 1]) * 0.5


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


func _ok(text: String) -> void:
	lines.append("PASS " + text)


func _bad(text: String) -> void:
	lines.append("FAIL " + text)
