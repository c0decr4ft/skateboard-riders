extends Node3D
## Builds one downhill park and the ride HUD.
## Open this folder in Godot 4.3+ and press Play.

const SLOPE_PITCH := 14.0
const START_Z := -430.0
const FINISH_Z := 470.0
const SkierScript := preload("res://scripts/skier.gd")

var slope: StaticBody3D
var skier: CharacterBody3D
var camera: Camera3D
var cam_pos := Vector3.ZERO
var cam_ready := false

var ui_font: SystemFont
var menu: Control
var pause_layer: Control
var end_layer: Control
var score_label: Label
var speed_label: Label
var trick_label: Label
var line_label: Label
var hint_label: Label
var progress_fill: ColorRect
var charge_fill: ColorRect
var charge_bar: Control
var end_title: Label
var end_body: Label
var best_label: Label
var started := false
var hud: Control

var snow_mat: Material
var gate_mat: StandardMaterial3D
var gate_hot: StandardMaterial3D
var kicker_spots: Array[float] = []


func _ready() -> void:
	# Stay awake while the tree is paused so Esc can resume.
	# The skier itself is set back to pausable after it is created.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_environment()
	_build_slope()
	_build_kickers()
	_build_rails()
	_build_gates()
	_build_dressing()
	_build_markers()
	_build_skier()
	_build_camera()
	_build_snow()
	_build_hud()
	hud.hide()


func _process(delta: float) -> void:
	if skier == null:
		return
	_follow_camera(delta)
	_refresh_hud()
	if skier.state == SkierScript.State.RIDE and skier.progress >= 0.992:
		skier.finish()
		_show_end(false)


func _input(event: InputEvent) -> void:
	if started:
		return
	var start := false
	if event is InputEventKey:
		var key_event := event as InputEventKey
		start = key_event.pressed and not key_event.echo
	elif event is InputEventMouseButton:
		start = (event as InputEventMouseButton).pressed
	if start:
		_start_run()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: Key = (event as InputEventKey).keycode
	if key == KEY_ESCAPE:
		if started and skier.state == SkierScript.State.RIDE and end_layer.visible == false:
			_set_paused(not get_tree().paused)
		return
	if key == KEY_R and started:
		_restart()
		return
	if (key == KEY_ENTER or key == KEY_KP_ENTER) and skier.state != SkierScript.State.RIDE:
		_restart()


func _start_run() -> void:
	started = true
	menu.hide()
	end_layer.hide()
	hud.show()
	_set_paused(false)
	skier.begin()


func _restart() -> void:
	_set_paused(false)
	for area in get_tree().get_nodes_in_group("gate"):
		area.set_meta("taken", false)
		for child in area.get_children():
			if child is MeshInstance3D:
				child.material_override = gate_mat
	skier.reset_run()
	started = true
	menu.hide()
	end_layer.hide()
	hud.show()


func _set_paused(on: bool) -> void:
	get_tree().paused = on
	pause_layer.visible = on


func _follow_camera(delta: float) -> void:
	var scenic := (not started) or get_tree().paused
	var back := 5.4
	var up := 1.85
	var side: float = skier.lean * 1.6
	if scenic:
		back = 8.5
		up = 2.8
		side = 2.6
	var ahead := 6.5 if not scenic else 10.0
	var focus: Vector3 = skier.global_position + skier.cam_forward * ahead + Vector3.UP * 1.3
	var want: Vector3 = skier.global_position - skier.cam_forward * back + Vector3.UP * up + skier.cam_right * side
	var from := skier.global_position + Vector3.UP * 1.4
	var query := PhysicsRayQueryParameters3D.create(from, want, 1)
	query.exclude = [skier.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		want = hit.position + hit.normal * 0.45
	if not cam_ready:
		cam_pos = want
		cam_ready = true
	var k := 1.0 - exp(-4.2 * delta)
	cam_pos = cam_pos.lerp(want, k)
	camera.global_position = cam_pos
	camera.look_at(focus, Vector3.UP)
	var aim := 66.0 + clampf(skier.speed_mps / 36.0, 0.0, 1.0) * 12.0
	if scenic:
		aim = 60.0
	camera.fov = lerpf(camera.fov, aim, k)


func _refresh_hud() -> void:
	if not started:
		return
	var kmh := int(round(skier.speed_mps * 3.6))
	speed_label.text = "%d km/h" % kmh
	score_label.text = _comma(skier.points)
	if skier.combo > 1 and skier.state == SkierScript.State.RIDE:
		line_label.text = "LINE  x%.2f" % skier.line_mult
	else:
		line_label.text = ""
	var trick := ""
	if skier.airborne and skier.live_trick != "":
		trick = skier.live_trick
	elif skier.banner_ttl > 0.0:
		trick = skier.banner
	trick_label.text = trick
	progress_fill.anchor_right = clampf(skier.progress, 0.0, 1.0)
	var show_charge: bool = skier.charge > 0.02 and skier.state == SkierScript.State.RIDE
	charge_bar.visible = show_charge
	charge_fill.anchor_right = skier.charge
	if skier.state == SkierScript.State.CRASH and not end_layer.visible:
		_show_end(true)
	elif skier.state == SkierScript.State.DONE and not end_layer.visible:
		_show_end(false)


func _show_end(crashed: bool) -> void:
	end_layer.show()
	if crashed:
		end_title.text = "YARD SALE"
		end_body.text = "%s\n%s\n\nR  —  ride again" % [skier.crash_reason, _comma(skier.points)]
	else:
		var best_note := ""
		if skier.points > 0 and skier.points >= skier.saved_best:
			best_note = "\nNew best"
		end_title.text = "RUN COMPLETE"
		end_body.text = "%s%s\n\nR  —  ride again" % [_comma(skier.points), best_note]


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.33, 0.52, 0.82)
	sky_mat.sky_horizon_color = Color(0.78, 0.84, 0.9)
	sky_mat.ground_bottom_color = Color(0.62, 0.68, 0.72)
	sky_mat.ground_horizon_color = Color(0.8, 0.84, 0.86)
	sky_mat.sun_angle_max = 28.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.78, 0.84, 0.9)
	env.fog_density = 0.0016
	env.fog_aerial_perspective = 0.35
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-36, 48, 0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.35
	sun.shadow_enabled = DisplayServer.get_name() != "headless"
	sun.directional_shadow_max_distance = 220.0
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -140, 0)
	fill.light_color = Color(0.75, 0.84, 1.0)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	add_child(fill)


func _build_slope() -> void:
	snow_mat = _snow_material()
	slope = StaticBody3D.new()
	slope.name = "Slope"
	slope.rotation_degrees.x = SLOPE_PITCH
	add_child(slope)

	var ground := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(78, 6, 1200)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, -3.0, 20)
	ground.add_child(col)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(78, 6, 1200)
	mesh.mesh = box
	mesh.position = Vector3(0, -3.0, 20)
	mesh.material_override = snow_mat
	ground.add_child(mesh)
	slope.add_child(ground)

	for side in [-1.0, 1.0]:
		var berm := StaticBody3D.new()
		var bshape := BoxShape3D.new()
		bshape.size = Vector3(4.5, 1.6, 1100)
		var bcol := CollisionShape3D.new()
		bcol.shape = bshape
		bcol.position = Vector3(side * 27.5, 0.55, 20)
		berm.add_child(bcol)
		var bmesh := MeshInstance3D.new()
		var bbox := BoxMesh.new()
		bbox.size = Vector3(4.5, 1.6, 1100)
		bmesh.mesh = bbox
		bmesh.position = bcol.position
		bmesh.material_override = _flat(Color(0.8, 0.86, 0.92), 0.9)
		berm.add_child(bmesh)
		slope.add_child(berm)


func _build_kickers() -> void:
	var specs := [
		[Vector3(0, 0, -340), 10.0, 13.0, 2.3],
		[Vector3(-8, 0, -250), 8.5, 15.0, 3.3],
		[Vector3(8, 0, -165), 8.0, 13.0, 2.7],
		[Vector3(0, 0, -55), 12.0, 17.0, 4.4],
		[Vector3(7, 0, 45), 8.0, 12.0, 2.5],
		[Vector3(-8, 0, 140), 9.0, 15.0, 3.5],
		[Vector3(0, 0, 245), 13.0, 19.0, 5.2],
		[Vector3(-4, 0, 355), 9.0, 14.0, 3.1],
	]
	for spec in specs:
		var at: Vector3 = spec[0]
		kicker_spots.append(at.z)
		_add_kicker(at, spec[1], spec[2], spec[3])


func _add_kicker(at: Vector3, width: float, length: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(at.x, 0.5, at.z)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _wedge_mesh(width, length, height)
	mesh.material_override = _flat(Color(0.86, 0.9, 0.95), 0.78)
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	col.shape = _wedge_shape(width, length, height)
	body.add_child(col)
	var lip := MeshInstance3D.new()
	var lip_box := BoxMesh.new()
	lip_box.size = Vector3(width * 0.94, 0.14, 0.42)
	lip.mesh = lip_box
	lip.position = Vector3(0, height * 0.92, length * 0.5 - 0.15)
	lip.material_override = _flat(Color(0.9, 0.28, 0.18), 0.45)
	body.add_child(lip)
	slope.add_child(body)


func _wedge_mesh(width: float, length: float, height: float) -> ArrayMesh:
	var hw := width * 0.5
	var hl := length * 0.5
	var p := [
		Vector3(-hw, -0.5, -hl),
		Vector3(hw, -0.5, -hl),
		Vector3(hw, -0.5, hl),
		Vector3(-hw, -0.5, hl),
		Vector3(-hw, height, hl),
		Vector3(hw, height, hl),
	]
	var faces := [
		[0, 4, 5], [0, 5, 1],
		[3, 5, 4], [3, 2, 5],
		[0, 1, 2], [0, 2, 3],
		[0, 3, 4],
		[1, 5, 2],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		for i in face:
			st.add_vertex(p[i])
	st.generate_normals()
	return st.commit()


func _wedge_shape(width: float, length: float, height: float) -> ConvexPolygonShape3D:
	var hw := width * 0.5
	var hl := length * 0.5
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(-hw, -0.5, -hl),
		Vector3(hw, -0.5, -hl),
		Vector3(hw, -0.5, hl),
		Vector3(-hw, -0.5, hl),
		Vector3(-hw, height, hl),
		Vector3(hw, height, hl),
	])
	return shape


func _build_rails() -> void:
	_add_rail(Vector3(-9, 0, -115), 16.0)
	_add_rail(Vector3(9, 0, 95), 14.0)
	_add_rail(Vector3(-8, 0, 310), 16.0)


func _add_rail(at: Vector3, length: float) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(at.x, 0.0, at.z)
	var steel := _flat(Color(0.55, 0.6, 0.66), 0.25)
	steel.metallic = 0.85
	var bar := MeshInstance3D.new()
	var bar_box := BoxMesh.new()
	bar_box.size = Vector3(0.22, 0.16, length)
	bar.mesh = bar_box
	bar.position = Vector3(0, 1.05, 0)
	bar.material_override = steel
	body.add_child(bar)
	var bar_col := CollisionShape3D.new()
	var bar_shape := BoxShape3D.new()
	bar_shape.size = bar_box.size
	bar_col.shape = bar_shape
	bar_col.position = bar.position
	body.add_child(bar_col)
	for end_z in [-length * 0.5, length * 0.5]:
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.08
		cyl.bottom_radius = 0.08
		cyl.height = 1.05
		post.mesh = cyl
		post.position = Vector3(0, 0.52, end_z)
		post.material_override = steel
		body.add_child(post)
	slope.add_child(body)
	var area := Area3D.new()
	area.position = body.position
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	var ashape := BoxShape3D.new()
	ashape.size = Vector3(1.4, 1.6, length)
	var acol := CollisionShape3D.new()
	acol.shape = ashape
	acol.position = Vector3(0, 1.15, 0)
	area.add_child(acol)
	slope.add_child(area)
	var world_a := area.to_global(Vector3(0, 1.2, -length * 0.5))
	var world_b := area.to_global(Vector3(0, 1.2, length * 0.5))
	area.body_entered.connect(_on_rail.bind(world_a, world_b))


func _on_rail(body: Node, a: Vector3, b: Vector3) -> void:
	if body == skier:
		skier.try_rail(a, b)


func _build_gates() -> void:
	gate_mat = _flat(Color(0.2, 0.45, 0.95), 0.4)
	gate_hot = _flat(Color(0.95, 0.78, 0.25), 0.35)
	var spots := [
		[Vector3(0, 0, -300), 8.0],
		[Vector3(2, 0, -10), 7.0],
		[Vector3(-2, 0, 190), 8.0],
		[Vector3(0, 0, 410), 9.0],
	]
	for spot in spots:
		_add_gate(spot[0], spot[1])


func _add_gate(at: Vector3, gap: float) -> void:
	var area := Area3D.new()
	area.position = Vector3(at.x, 0.0, at.z)
	area.collision_layer = 0
	area.collision_mask = 1
	area.set_meta("taken", false)
	area.add_to_group("gate")
	var shape := BoxShape3D.new()
	shape.size = Vector3(gap, 2.4, 1.2)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 1.2, 0)
	area.add_child(col)
	for side in [-1.0, 1.0]:
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.12
		cyl.bottom_radius = 0.12
		cyl.height = 2.3
		pole.mesh = cyl
		pole.position = Vector3(side * gap * 0.5, 1.15, 0)
		pole.material_override = gate_mat if side < 0.0 else _flat(Color(0.9, 0.25, 0.2), 0.4)
		area.add_child(pole)
	slope.add_child(area)
	area.body_entered.connect(_on_gate.bind(area))


func _on_gate(body: Node, area: Area3D) -> void:
	if body != skier or bool(area.get_meta("taken")):
		return
	if skier.state != SkierScript.State.RIDE:
		return
	area.set_meta("taken", true)
	skier.score_gate()
	for child in area.get_children():
		if child is MeshInstance3D:
			child.material_override = gate_hot


func _build_dressing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 14021
	var pine := _flat(Color(0.16, 0.34, 0.24), 0.85)
	var trunk := _flat(Color(0.32, 0.22, 0.14), 0.9)
	var rock_mat := _flat(Color(0.45, 0.48, 0.52), 0.92)
	for i in 80:
		var z := rng.randf_range(-400.0, 500.0)
		var x := rng.randf_range(12.5, 23.0) * (1.0 if rng.randf() > 0.5 else -1.0)
		if _near_feature(z):
			continue
		_add_tree(Vector3(x, 0, z), rng.randf_range(0.75, 1.35), pine, trunk)
	for i in 14:
		var z := rng.randf_range(-380.0, 460.0)
		var x := rng.randf_range(12.0, 20.0) * (1.0 if i % 2 == 0 else -1.0)
		if _near_feature(z):
			continue
		_add_rock(Vector3(x, 0, z), rng.randf_range(0.7, 1.5), rock_mat)
	# Distant ridges, tilted with the slope so they read as mountains.
	var ridge := _flat(Color(0.55, 0.62, 0.7), 1.0)
	for i in 8:
		var cone := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.4
		mesh.bottom_radius = rng.randf_range(18.0, 34.0)
		mesh.height = rng.randf_range(28.0, 55.0)
		cone.mesh = mesh
		var side := 1.0 if i % 2 == 0 else -1.0
		cone.position = Vector3(side * rng.randf_range(70.0, 130.0), mesh.height * 0.35, rng.randf_range(-500.0, 500.0))
		cone.material_override = ridge
		slope.add_child(cone)


func _near_feature(z: float) -> bool:
	for spot in kicker_spots:
		if absf(z - spot) < 18.0:
			return true
	return false


func _add_tree(at: Vector3, scale: float, pine: Material, trunk_mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.add_to_group("hazard")
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18 * scale
	trunk_mesh.bottom_radius = 0.28 * scale
	trunk_mesh.height = 1.4 * scale
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0, 0.7 * scale, 0)
	trunk.material_override = trunk_mat
	body.add_child(trunk)
	var top := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 1.35 * scale
	cone.height = 3.6 * scale
	top.mesh = cone
	top.position = Vector3(0, 2.5 * scale, 0)
	top.material_override = pine
	body.add_child(top)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.55 * scale
	shape.height = 3.2 * scale
	col.shape = shape
	col.position = Vector3(0, 1.6 * scale, 0)
	body.add_child(col)
	slope.add_child(body)


func _add_rock(at: Vector3, scale: float, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = at + Vector3(0, 0.3 * scale, 0)
	body.add_to_group("hazard")
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.8 * scale
	sphere.height = 1.1 * scale
	mesh.mesh = sphere
	mesh.material_override = mat
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.75 * scale
	col.shape = shape
	body.add_child(col)
	slope.add_child(body)


func _build_markers() -> void:
	_add_banner(START_Z + 16.0, "START", Color(0.12, 0.16, 0.22))
	_add_banner(FINISH_Z, "FINISH", Color(0.75, 0.18, 0.14))
	var finish := Area3D.new()
	finish.position = Vector3(0, 2.0, FINISH_Z)
	finish.collision_layer = 0
	finish.collision_mask = 1
	var shape := BoxShape3D.new()
	shape.size = Vector3(50, 8, 8)
	var col := CollisionShape3D.new()
	col.shape = shape
	finish.add_child(col)
	slope.add_child(finish)
	finish.body_entered.connect(_on_finish)
	var travelled := 0.0
	var z := START_Z
	while z < FINISH_Z - 40.0:
		z += 120.0
		travelled += 120.0
		if z > FINISH_Z - 30.0:
			break
		var label := Label3D.new()
		label.text = "%dm" % int(travelled)
		label.font_size = 72
		label.pixel_size = 0.01
		label.position = Vector3(-8.5, 2.2, z)
		label.modulate = Color(0.2, 0.26, 0.34)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.outline_size = 6
		label.outline_modulate = Color(1, 1, 1, 0.7)
		slope.add_child(label)


func _add_banner(z: float, text: String, color: Color) -> void:
	for side in [-1.0, 1.0]:
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.12
		cyl.bottom_radius = 0.12
		cyl.height = 3.2
		pole.mesh = cyl
		pole.position = Vector3(side * 7.0, 1.6, z)
		pole.material_override = _flat(color, 0.6)
		slope.add_child(pole)
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.01
	label.position = Vector3(0, 2.55, z)
	label.rotation.y = PI
	label.modulate = color
	label.outline_size = 8
	label.outline_modulate = Color(1, 1, 1, 0.85)
	slope.add_child(label)


func _on_finish(body: Node) -> void:
	if body != skier:
		return
	if skier.state == SkierScript.State.RIDE:
		skier.finish()


func _build_skier() -> void:
	skier = CharacterBody3D.new()
	skier.name = "Skier"
	skier.set_script(SkierScript)
	var spawn := slope.to_global(Vector3(0, 0.25, START_Z))
	var finish_at := slope.to_global(Vector3(0, 0.3, FINISH_Z))
	skier.spawn_pos = spawn
	skier.slope_hint = slope.global_transform.basis.y.normalized()
	skier.course_start = spawn
	skier.course_axis = finish_at - spawn
	skier.course_len = skier.course_axis.length()
	skier.course_axis = skier.course_axis.normalized()
	var cfg := ConfigFile.new()
	cfg.load("user://fall_line.cfg")
	skier.saved_best = int(cfg.get_value("run", "best", 0))
	add_child(skier)
	skier.process_mode = Node.PROCESS_MODE_PAUSABLE
	skier.global_position = spawn


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 66.0
	camera.near = 0.08
	camera.far = 800.0
	add_child(camera)


func _build_snow() -> void:
	var snow := GPUParticles3D.new()
	snow.amount = 500
	snow.lifetime = 4.0
	snow.preprocess = 2.0
	snow.visibility_aabb = AABB(Vector3(-30, -20, -30), Vector3(60, 40, 60))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(16, 8, 20)
	mat.direction = Vector3(0.15, -1, 0.05)
	mat.spread = 12.0
	mat.initial_velocity_min = 1.2
	mat.initial_velocity_max = 2.8
	mat.gravity = Vector3(0, -0.6, 0)
	mat.scale_min = 0.015
	mat.scale_max = 0.045
	mat.color = Color(1, 1, 1, 0.85)
	snow.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(1, 1, 1, 0.8)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = sm
	snow.draw_pass_1 = quad
	snow.process_mode = Node.PROCESS_MODE_PAUSABLE
	camera.add_child(snow)


func _build_hud() -> void:
	ui_font = SystemFont.new()
	ui_font.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Arial"])
	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)

	var track := ColorRect.new()
	track.color = Color(0.06, 0.09, 0.14, 0.45)
	track.set_anchors_preset(Control.PRESET_TOP_WIDE)
	track.offset_left = 28
	track.offset_top = 22
	track.offset_right = -28
	track.offset_bottom = 28
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(track)
	progress_fill = ColorRect.new()
	progress_fill.color = Color(0.9, 0.28, 0.18, 0.95)
	progress_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	progress_fill.anchor_right = 0.0
	progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(progress_fill)

	score_label = _label("", 42, Color(0.96, 0.97, 0.98))
	score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	score_label.offset_left = -360
	score_label.offset_top = 40
	score_label.offset_right = -28
	score_label.offset_bottom = 96
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(score_label)

	line_label = _label("", 18, Color(0.95, 0.82, 0.45))
	line_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	line_label.offset_left = -360
	line_label.offset_top = 96
	line_label.offset_right = -28
	line_label.offset_bottom = 126
	line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(line_label)

	speed_label = _label("0 km/h", 28, Color(0.96, 0.97, 0.98))
	speed_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	speed_label.offset_left = 28
	speed_label.offset_top = -72
	speed_label.offset_right = 280
	speed_label.offset_bottom = -28
	hud.add_child(speed_label)

	trick_label = _label("", 36, Color(1, 1, 1))
	trick_label.set_anchors_preset(Control.PRESET_CENTER)
	trick_label.offset_left = -360
	trick_label.offset_top = -40
	trick_label.offset_right = 360
	trick_label.offset_bottom = 20
	trick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(trick_label)

	charge_bar = Control.new()
	charge_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	charge_bar.offset_left = -90
	charge_bar.offset_top = -120
	charge_bar.offset_right = 90
	charge_bar.offset_bottom = -100
	charge_bar.visible = false
	charge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(charge_bar)
	var charge_bg := ColorRect.new()
	charge_bg.color = Color(0, 0, 0, 0.35)
	charge_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	charge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charge_bar.add_child(charge_bg)
	charge_fill = ColorRect.new()
	charge_fill.color = Color(0.95, 0.78, 0.3)
	charge_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	charge_fill.anchor_right = 0.0
	charge_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charge_bar.add_child(charge_fill)

	hint_label = _label("A D carve      W tuck      S brake      hold Space, release to pop\nAir   A D spin      arrows roll      Q E grab      Down slows a trick      B butter", 16, Color(1, 1, 1, 0.88))
	hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_top = -118
	hint_label.offset_bottom = -78
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(hint_label)

	menu = _overlay(Color(0.05, 0.08, 0.12, 0.28))
	layer.add_child(menu)
	var title := _label("FALL LINE", 72, Color(0.97, 0.98, 0.99))
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.offset_left = 48
	title.offset_top = 28
	title.offset_right = 720
	title.offset_bottom = 120
	menu.add_child(title)
	var sub := _label("Click anywhere or press any key.", 22, Color(0.94, 0.95, 0.96))
	sub.set_anchors_preset(Control.PRESET_TOP_LEFT)
	sub.offset_left = 52
	sub.offset_top = 124
	sub.offset_right = 820
	sub.offset_bottom = 164
	menu.add_child(sub)
	var ride_btn := Button.new()
	ride_btn.text = "RIDE"
	ride_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ride_btn.offset_left = 52
	ride_btn.offset_top = 180
	ride_btn.offset_right = 276
	ride_btn.offset_bottom = 236
	ride_btn.add_theme_font_override("font", ui_font)
	ride_btn.add_theme_font_size_override("font_size", 22)
	ride_btn.add_theme_color_override("font_color", Color(1, 1, 1))
	ride_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	var normal := _button_box(Color(0.86, 0.24, 0.16))
	var hover := _button_box(Color(0.94, 0.32, 0.22))
	ride_btn.add_theme_stylebox_override("normal", normal)
	ride_btn.add_theme_stylebox_override("hover", hover)
	ride_btn.add_theme_stylebox_override("pressed", hover)
	ride_btn.add_theme_stylebox_override("focus", normal)
	ride_btn.pressed.connect(_start_run)
	menu.add_child(ride_btn)
	var how := _label("A D carve    W tuck    S brake    hold Space, release to pop", 16, Color(1, 1, 1, 0.82))
	how.set_anchors_preset(Control.PRESET_TOP_LEFT)
	how.offset_left = 52
	how.offset_top = 248
	how.offset_right = 900
	how.offset_bottom = 280
	menu.add_child(how)
	best_label = _label("", 18, Color(0.97, 0.97, 0.98))
	best_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	best_label.offset_left = -320
	best_label.offset_top = 48
	best_label.offset_right = -36
	best_label.offset_bottom = 84
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	menu.add_child(best_label)
	if skier.saved_best > 0:
		best_label.text = "BEST  %s" % _comma(skier.saved_best)

	pause_layer = _overlay(Color(0.05, 0.08, 0.12, 0.45))
	pause_layer.hide()
	layer.add_child(pause_layer)
	var paused := _label("PAUSED", 54, Color.WHITE)
	paused.set_anchors_preset(Control.PRESET_CENTER)
	paused.offset_left = -200
	paused.offset_top = -70
	paused.offset_right = 200
	paused.offset_bottom = 0
	paused.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_layer.add_child(paused)
	var pause_hint := _label("Esc resume    R restart", 18, Color(1, 1, 1, 0.85))
	pause_hint.set_anchors_preset(Control.PRESET_CENTER)
	pause_hint.offset_left = -220
	pause_hint.offset_top = 8
	pause_hint.offset_right = 220
	pause_hint.offset_bottom = 40
	pause_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_layer.add_child(pause_hint)

	end_layer = _overlay(Color(0.05, 0.08, 0.12, 0.5))
	end_layer.hide()
	layer.add_child(end_layer)
	end_title = _label("", 52, Color.WHITE)
	end_title.set_anchors_preset(Control.PRESET_CENTER)
	end_title.offset_left = -360
	end_title.offset_top = -110
	end_title.offset_right = 360
	end_title.offset_bottom = -40
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_layer.add_child(end_title)
	end_body = _label("", 22, Color(0.95, 0.96, 0.97))
	end_body.set_anchors_preset(Control.PRESET_CENTER)
	end_body.offset_left = -360
	end_body.offset_top = -24
	end_body.offset_right = 360
	end_body.offset_bottom = 120
	end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_layer.add_child(end_body)


func _overlay(tint: Color) -> Control:
	var dim := ColorRect.new()
	dim.color = tint
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	return dim


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", ui_font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.07, 0.1, 0.8))
	return label


func _button_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 4
	box.corner_radius_bottom_left = 4
	box.corner_radius_bottom_right = 4
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


func _snow_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nvarying vec3 world_pos;\nuniform vec4 snow : source_color = vec4(0.94, 0.96, 0.98, 1.0);\nvoid vertex() {\n\tworld_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;\n}\nvoid fragment() {\n\tfloat cord = sin(world_pos.z * 1.15) * 0.5 + 0.5;\n\tfloat drift = sin(world_pos.x * 0.08 + world_pos.z * 0.02) * 0.5 + 0.5;\n\tALBEDO = mix(snow.rgb, vec3(0.72, 0.8, 0.88), cord * 0.28 + drift * 0.1);\n\tROUGHNESS = 0.9;\n}\n"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func _flat(color: Color, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	return mat


func _comma(value: int) -> String:
	var sign := "-" if value < 0 else ""
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = "," + out
		out = digits[i] + out
		count += 1
	return sign + out
