extends Node3D
## Ride scene. Loads the saved park and runs the skater.

const SkaterScript := preload("res://scripts/skater.gd")
const LayoutScript := preload("res://scripts/layout.gd")
const PiecesScript := preload("res://scripts/pieces.gd")
const MODEL := "res://assets/kenney-mini-skate/%s.glb"

var skater: CharacterBody3D
var camera: Camera3D
var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO
var cam_fwd := Vector3(0, 0, -1)
var cam_ready := false
var started := false
var ride_spawn := Vector3(0, 0.35, 1)
var ride_heading := 0.0
var ride_grinds: Array = []
var leaving := false

var ui_font: SystemFont
var menu: Control
var pause_layer: Control
var end_layer: Control
var hud: Control
var score_label: Label
var speed_label: Label
var trick_label: Label
var line_label: Label
var charge_fill: ColorRect
var charge_bar: Control
var end_title: Label
var end_body: Label
var best_label: Label
var mute_button: Button


func _ready() -> void:
	get_tree().paused = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var kit = PiecesScript.new()
	kit.build_environment(self)
	_build_park()
	_build_camera()
	_build_hud()
	_build_skater()
	_start_run()
	_follow_camera(0.0)
	get_viewport().gui_release_focus()


func _process(delta: float) -> void:
	if skater == null:
		return
	_follow_camera(delta)
	_refresh_hud()


func _input(event: InputEvent) -> void:
	if started:
		return
	var start := false
	if event is InputEventKey:
		var key_event := event as InputEventKey
		start = key_event.pressed and not key_event.echo
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if mute_button != null and mute_button.get_global_rect().has_point(click.position):
			return
		start = click.pressed
	if start:
		_start_run()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: Key = (event as InputEventKey).keycode
	if key == KEY_ESCAPE:
		_back_to_builder()
		return
	if key == KEY_R and started:
		_restart()
		return
	if (key == KEY_ENTER or key == KEY_KP_ENTER) and started and skater.state != SkaterScript.State.RIDE:
		_restart()


func _start_run() -> void:
	if skater == null:
		return
	started = true
	menu.hide()
	end_layer.hide()
	hud.show()
	_set_paused(false)
	skater.begin()
	_aim_spawn()


func _restart() -> void:
	_set_paused(false)
	skater.reset_run()
	_aim_spawn()
	started = true
	menu.hide()
	end_layer.hide()
	hud.show()


func _set_paused(on: bool) -> void:
	get_tree().paused = on
	pause_layer.visible = on


func _back_to_builder() -> void:
	if leaving:
		return
	leaving = true
	_set_paused(false)
	get_tree().call_deferred("change_scene_to_file", "res://scenes/home.tscn")


func _follow_camera(delta: float) -> void:
	# Chase sits behind the skater. Flat heading only, so a steep bank
	# cannot swing the rig or flip look_at.
	var back := 6.0
	var up := 2.5
	var look_up := 1.0
	var airborne: bool = skater.airborne
	if started and airborne and not get_tree().paused:
		back = 7.6
		up = 3.2
		look_up = 1.2
	elif not started:
		back = 8.0
		up = 3.4
		look_up = 1.1
	var fwd: Vector3 = skater.cam_forward
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	var turn := 1.0 - exp(-8.0 * delta)
	if not cam_ready:
		cam_fwd = fwd
	else:
		cam_fwd = cam_fwd.lerp(fwd, turn).normalized()
		if cam_fwd.length_squared() < 0.0001:
			cam_fwd = fwd
	var right := cam_fwd.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3(1, 0, 0)
	right = right.normalized()
	var lean: float = skater.lean
	var origin: Vector3 = skater.global_position
	var focus := origin + Vector3.UP * look_up
	var want := origin - cam_fwd * back + Vector3.UP * up + right * lean * 0.45
	if want.y < 0.8:
		want.y = 0.8
	if not cam_ready:
		cam_pos = want
		cam_look = focus
		cam_ready = true
	var k := 1.0 - exp(-5.5 * delta)
	cam_pos = cam_pos.lerp(want, k)
	cam_look = cam_look.lerp(focus, 1.0 - exp(-8.0 * delta))
	var view := cam_look - cam_pos
	if view.length_squared() < 0.25:
		view = cam_fwd * 6.0 + Vector3.UP * 0.2
	view = view.normalized()
	if absf(view.dot(Vector3.UP)) > 0.96:
		cam_pos += cam_fwd * 0.75
		view = (cam_look - cam_pos).normalized()
	camera.global_position = cam_pos
	camera.look_at(cam_pos + view, Vector3.UP)
	var speed: float = skater.speed_mps
	var aim := 58.0 + clampf(speed / 11.0, 0.0, 1.0) * 6.0
	camera.fov = lerpf(camera.fov, aim, k)


func _refresh_hud() -> void:
	if not started:
		return
	var kmh := int(round(skater.speed_mps * 3.6))
	speed_label.text = "%d km/h" % kmh
	score_label.text = _comma(skater.points)
	if skater.combo > 1 and skater.state == SkaterScript.State.RIDE:
		line_label.text = "COMBO  x%.2f" % skater.line_mult
	else:
		line_label.text = ""
	var trick := ""
	if skater.live_trick != "" and (skater.airborne or skater.grinding or skater.sliding):
		trick = skater.live_trick
	elif skater.banner_ttl > 0.0:
		trick = skater.banner
	trick_label.text = trick
	var show_charge: bool = skater.charge > 0.02 and skater.state == SkaterScript.State.RIDE
	charge_bar.visible = show_charge
	charge_fill.anchor_right = skater.charge
	if skater.state == SkaterScript.State.CRASH and not end_layer.visible:
		_show_end()


func _show_end() -> void:
	end_layer.show()
	end_title.text = "BAILED"
	end_body.text = "%s\n%s\n\nR  —  ride again    Esc  —  builder" % [skater.crash_reason, _comma(skater.points)]


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.58, 0.86)
	sky_mat.sky_horizon_color = Color(0.78, 0.84, 0.9)
	sky_mat.ground_bottom_color = Color(0.45, 0.48, 0.52)
	sky_mat.ground_horizon_color = Color(0.62, 0.66, 0.7)
	sky_mat.sun_angle_max = 28.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.78, 0.84, 0.9)
	env.fog_density = 0.0025
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 36, 0)
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.light_energy = 1.4
	sun.shadow_enabled = DisplayServer.get_name() != "headless"
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -140, 0)
	fill.light_color = Color(0.75, 0.84, 1.0)
	fill.light_energy = 0.35
	add_child(fill)


func _build_park() -> void:
	var kit = PiecesScript.new()
	kit.build_pad(self)
	var layout = LayoutScript.new()
	var items: Array = layout.load_or_default()
	items = kit.absorb_corners(items)
	items = kit.keep_stacks(items)
	ride_spawn = _spawn_from(items)
	ride_heading = _heading_from_start(items)
	var holder := Node3D.new()
	holder.name = "Pieces"
	add_child(holder)
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		if str(entry.get("id", "")) == "":
			continue
		kit.place_item(holder, entry)
	kit.weld_ramps(holder)
	ride_grinds = _chain_rails(holder, kit)


func _spawn_from(items: Array) -> Vector3:
	var sx := 0.0
	var sy := 0.0
	var sz := 0.0
	var n := 0
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if str(item["id"]) != "start":
			continue
		sx += float(item["x"])
		sy += float(item.get("y", 0.0))
		sz += float(item["z"])
		n += 1
	if n == 0:
		return Vector3(0.0, 0.35, 1.0)
	return Vector3(sx / float(n), sy / float(n) + 0.35, sz / float(n))


func _heading_from_start(items: Array) -> float:
	# Start-pad rotation 0 faces -Z, into the starter park from the south pad.
	var sum_s := 0.0
	var sum_c := 0.0
	var n := 0
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if str(item["id"]) != "start":
			continue
		var yaw: float = deg_to_rad(float(int(item["rot"])))
		sum_s += sin(yaw)
		sum_c += cos(yaw)
		n += 1
	if n == 0:
		return 0.0
	return atan2(sum_s, sum_c)


func _aim_spawn() -> void:
	skater.heading = ride_heading
	skater.cam_forward = Vector3(-sin(ride_heading), 0.0, -cos(ride_heading))


func _body(piece: String, at: Vector3, yaw_deg: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = piece
	body.position = at
	body.rotation.y = deg_to_rad(yaw_deg)
	add_child(body)
	var packed := load(MODEL % piece) as PackedScene
	if packed == null:
		push_error("Missing model %s" % piece)
	else:
		body.add_child(packed.instantiate())
	return body


func _quarter(at: Vector3, yaw_deg: float) -> void:
	var body := _body("half-pipe", at, yaw_deg)
	var pts: Array[Vector2] = [
		Vector2(-0.46, 0.78),
		Vector2(-0.28, 0.66),
		Vector2(-0.12, 0.38),
		Vector2(0.08, 0.14),
		Vector2(0.30, 0.04),
		Vector2(0.50, 0.0),
	]
	for i in range(pts.size() - 1):
		_wedge(body, pts[i], pts[i + 1], 0.98)


func _bank(at: Vector3, yaw_deg: float) -> void:
	var body := _body("slope-smooth", at, yaw_deg)
	var pts: Array[Vector2] = [
		Vector2(1.0, 0.0),
		Vector2(0.65, 0.04),
		Vector2(0.30, 0.18),
		Vector2(0.0, 0.42),
		Vector2(-0.35, 0.66),
		Vector2(-0.70, 0.78),
		Vector2(-1.0, 0.80),
	]
	for i in range(pts.size() - 1):
		_wedge(body, pts[i], pts[i + 1], 0.96)


func _ramp(at: Vector3, yaw_deg: float) -> void:
	var body := _body("ramp", at, yaw_deg)
	var deck := BoxShape3D.new()
	deck.size = Vector3(0.96, 0.30, 0.48)
	var dcol := CollisionShape3D.new()
	dcol.shape = deck
	dcol.position = Vector3(0, 0.15, -0.24)
	body.add_child(dcol)
	_wedge(body, Vector2(-0.02, 0.30), Vector2(0.50, 0.0), 0.96)


func _ledge(at: Vector3) -> void:
	var body := _body("obstacle-middle", at, 0)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.98, 0.30, 0.98)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 0.15, 0)
	body.add_child(col)


func _rail(piece: String, at: Vector3, bar_y: float) -> void:
	var body := _body(piece, at, 0)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.16, 0.10, 0.92)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, bar_y, 0)
	body.add_child(col)


func _wedge(body: StaticBody3D, a: Vector2, b: Vector2, width: float) -> void:
	var hx := width * 0.5
	var z0 := a.x
	var z1 := b.x
	if z1 >= z0:
		z0 -= 0.015
		z1 += 0.015
	else:
		z0 += 0.015
		z1 -= 0.015
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(-hx, -0.08, z0),
		Vector3(hx, -0.08, z0),
		Vector3(-hx, -0.08, z1),
		Vector3(hx, -0.08, z1),
		Vector3(-hx, a.y, z0),
		Vector3(hx, a.y, z0),
		Vector3(-hx, b.y, z1),
		Vector3(hx, b.y, z1),
	])
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)


func _build_skater() -> void:
	skater = CharacterBody3D.new()
	skater.name = "Skater"
	skater.set_script(SkaterScript)
	var cfg := ConfigFile.new()
	cfg.load("user://mini_park.cfg")
	skater.saved_best = int(cfg.get_value("run", "best", 0))
	skater.spawn_pos = ride_spawn
	skater.heading = ride_heading
	skater.cam_forward = Vector3(-sin(ride_heading), 0.0, -cos(ride_heading))
	skater.grind_lines = ride_grinds
	add_child(skater)
	skater.process_mode = Node.PROCESS_MODE_PAUSABLE
	skater.global_position = skater.spawn_pos


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 58.0
	camera.near = 0.05
	camera.far = 300.0
	add_child(camera)


func _chain_rails(holder: Node, kit) -> Array:
	var parts: Array = []
	for child in holder.get_children():
		if not (child is Node3D):
			continue
		var body: Node3D = child
		if not body.has_meta("piece_id"):
			continue
		var pts: PackedVector3Array = kit.rail_points(body)
		if pts.size() >= 2:
			parts.append(pts)
	var used: Dictionary = {}
	var chains: Array = []
	for i in range(parts.size()):
		if used.has(i):
			continue
		used[i] = true
		var line: PackedVector3Array = parts[i]
		var grew := true
		while grew:
			grew = false
			for j in range(parts.size()):
				if used.has(j):
					continue
				var other: PackedVector3Array = parts[j]
				var joined := _join_rails(line, other)
				if joined.size() < 2:
					continue
				used[j] = true
				line = joined
				grew = true
		chains.append(line)
	return chains


func _join_rails(line: PackedVector3Array, other: PackedVector3Array) -> PackedVector3Array:
	var empty := PackedVector3Array()
	if line.size() < 2 or other.size() < 2:
		return empty
	var a0: Vector3 = line[0]
	var a1: Vector3 = line[line.size() - 1]
	var b0: Vector3 = other[0]
	var b1: Vector3 = other[other.size() - 1]
	# Ends of a 90-degree grid corner sit about 0.7 apart. A straight run is closer.
	if _ends_meet(a1, b0) and _rail_turn_ok(line, true, other, false):
		return _link_rails(line, other, false)
	if _ends_meet(a1, b1) and _rail_turn_ok(line, true, other, true):
		return _link_rails(line, other, true)
	if _ends_meet(a0, b1) and _rail_turn_ok(line, false, other, true):
		return _link_rails(other, line, false)
	if _ends_meet(a0, b0) and _rail_turn_ok(line, false, other, false):
		return _link_rails(_reversed_rail(other), line, false)
	return empty


func _ends_meet(a: Vector3, b: Vector3) -> bool:
	if absf(a.y - b.y) > 0.45:
		return false
	return Vector2(a.x - b.x, a.z - b.z).length() <= 0.9


func _rail_turn_ok(line: PackedVector3Array, line_at_end: bool, other: PackedVector3Array, other_at_end: bool) -> bool:
	var arrive := _rail_in_dir(line, line_at_end)
	var depart := _rail_out_dir(other, other_at_end)
	if arrive.length_squared() < 0.01 or depart.length_squared() < 0.01:
		return true
	# Straight through a right angle stays. A reversal does not.
	return arrive.dot(depart) >= -0.25


func _rail_in_dir(line: PackedVector3Array, at_end: bool) -> Vector3:
	if line.size() < 2:
		return Vector3.ZERO
	if at_end:
		return _flat_dir(line[line.size() - 2], line[line.size() - 1])
	return _flat_dir(line[1], line[0])


func _rail_out_dir(line: PackedVector3Array, at_end: bool) -> Vector3:
	if line.size() < 2:
		return Vector3.ZERO
	if at_end:
		return _flat_dir(line[line.size() - 1], line[line.size() - 2])
	return _flat_dir(line[0], line[1])


func _flat_dir(a: Vector3, b: Vector3) -> Vector3:
	var delta := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if delta.length_squared() < 0.0001:
		return Vector3.ZERO
	return delta.normalized()


func _reversed_rail(line: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in range(line.size() - 1, -1, -1):
		out.append(line[k])
	return out


func _link_rails(base: PackedVector3Array, extra: PackedVector3Array, flip_extra: bool) -> PackedVector3Array:
	var out := base.duplicate()
	var seq := extra
	if flip_extra:
		seq = _reversed_rail(extra)
	if seq.size() < 2:
		return out
	var gap := out[out.size() - 1].distance_to(seq[0])
	var start_k := 0 if gap > 0.04 else 1
	for k in range(start_k, seq.size()):
		out.append(seq[k])
	return out


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

	var back := Button.new()
	back.text = "Back"
	back.focus_mode = Control.FOCUS_NONE
	back.set_anchors_preset(Control.PRESET_TOP_LEFT)
	back.offset_left = 28
	back.offset_top = 24
	back.offset_right = 148
	back.offset_bottom = 68
	back.add_theme_font_override("font", ui_font)
	back.add_theme_font_size_override("font_size", 18)
	back.add_theme_color_override("font_color", Color(1, 1, 1))
	back.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	var back_normal := _button_box(Color(0.16, 0.18, 0.22))
	var back_hover := _button_box(Color(0.28, 0.31, 0.36))
	back.add_theme_stylebox_override("normal", back_normal)
	back.add_theme_stylebox_override("hover", back_hover)
	back.add_theme_stylebox_override("pressed", back_hover)
	back.add_theme_stylebox_override("focus", back_normal)
	back.pressed.connect(_back_to_builder)
	hud.add_child(back)

	score_label = _label("0", 42, Color(0.96, 0.97, 0.98))
	score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	score_label.offset_left = -360
	score_label.offset_top = 28
	score_label.offset_right = -28
	score_label.offset_bottom = 84
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(score_label)

	line_label = _label("", 18, Color(0.95, 0.82, 0.45))
	line_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	line_label.offset_left = -360
	line_label.offset_top = 84
	line_label.offset_right = -28
	line_label.offset_bottom = 114
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
	charge_fill.color = Color(0.95, 0.55, 0.2)
	charge_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	charge_fill.anchor_right = 0.0
	charge_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charge_bar.add_child(charge_fill)

	var hint := _label("A left   D right   W push   S brake   hold Space, release to ollie\nJump, then hold Shift to slide    Air A D 180   Q kickflip   E heelflip   S shove-it    R restart    Esc builder", 16, Color(1, 1, 1, 0.9))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -128
	hint.offset_bottom = -78
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(hint)

	menu = _overlay(Color(0.05, 0.07, 0.1, 0.35))
	layer.add_child(menu)
	var title := _label("SKATEBOARD RIDERS", 48, Color(0.97, 0.98, 0.99))
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.offset_left = 48
	title.offset_top = 28
	title.offset_right = 760
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
	var normal := _button_box(Color(0.9, 0.38, 0.16))
	var hover := _button_box(Color(0.98, 0.48, 0.22))
	ride_btn.add_theme_stylebox_override("normal", normal)
	ride_btn.add_theme_stylebox_override("hover", hover)
	ride_btn.add_theme_stylebox_override("pressed", hover)
	ride_btn.add_theme_stylebox_override("focus", normal)
	ride_btn.pressed.connect(_start_run)
	menu.add_child(ride_btn)
	var how := _label("A left   D right   W push   S brake   Space ollie\nAir: A D 180   Q / Left kickflip   E / Right heelflip   S / Down shove-it\nEsc builder   R restart", 16, Color(1, 1, 1, 0.88))
	how.set_anchors_preset(Control.PRESET_TOP_LEFT)
	how.offset_left = 52
	how.offset_top = 252
	how.offset_right = 920
	how.offset_bottom = 340
	menu.add_child(how)
	best_label = _label("", 18, Color(0.97, 0.97, 0.98))
	best_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	best_label.offset_left = -320
	best_label.offset_top = 48
	best_label.offset_right = -36
	best_label.offset_bottom = 84
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	menu.add_child(best_label)
	var best_score: int = 0
	if skater != null and is_instance_valid(skater):
		best_score = int(skater.saved_best)
	else:
		var cfg := ConfigFile.new()
		if cfg.load("user://mini_park.cfg") == OK:
			best_score = int(cfg.get_value("run", "best", 0))
	if best_score > 0:
		best_label.text = "BEST  %s" % _comma(best_score)

	pause_layer = _overlay(Color(0.05, 0.07, 0.1, 0.45))
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

	end_layer = _overlay(Color(0.05, 0.07, 0.1, 0.55))
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
	_build_mute_button(layer)


func _build_mute_button(layer: CanvasLayer) -> void:
	mute_button = Button.new()
	mute_button.name = "MuteButton"
	mute_button.focus_mode = Control.FOCUS_NONE
	mute_button.mouse_filter = Control.MOUSE_FILTER_STOP
	mute_button.process_mode = Node.PROCESS_MODE_ALWAYS
	mute_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mute_button.offset_left = 160
	mute_button.offset_top = 24
	mute_button.offset_right = 300
	mute_button.offset_bottom = 68
	mute_button.add_theme_font_override("font", ui_font)
	mute_button.add_theme_font_size_override("font_size", 18)
	mute_button.add_theme_color_override("font_color", Color(1, 1, 1))
	mute_button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	mute_button.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	mute_button.pressed.connect(_toggle_mute)
	layer.add_child(mute_button)
	_sync_mute_button()


func _toggle_mute() -> void:
	Music.toggle_mute()
	_sync_mute_button()


func _sync_mute_button() -> void:
	if mute_button == null:
		return
	var on: bool = Music.muted
	mute_button.text = Music.mute_label()
	var bg := Color(0.90, 0.38, 0.16) if on else Color(0.16, 0.18, 0.22)
	var hot := Color(0.98, 0.50, 0.24) if on else Color(0.28, 0.31, 0.36)
	var normal := _button_box(bg)
	var hover := _button_box(hot)
	mute_button.add_theme_stylebox_override("normal", normal)
	mute_button.add_theme_stylebox_override("hover", hover)
	mute_button.add_theme_stylebox_override("pressed", hover)
	mute_button.add_theme_stylebox_override("focus", normal)


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
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.08, 0.8))
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
