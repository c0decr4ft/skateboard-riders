extends RefCounted
## Pad, light, and rideable pieces. Blocks are solid boxes. Ramps are solid slopes.

const MODEL := "res://assets/kenney-mini-skate/%s.glb"


func build_environment(parent: Node3D) -> void:
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
	env.fog_density = 0.0012
	var world := WorldEnvironment.new()
	world.environment = env
	parent.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 36, 0)
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.light_energy = 1.4
	sun.shadow_enabled = DisplayServer.get_name() != "headless"
	sun.directional_shadow_max_distance = 80.0
	parent.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -140, 0)
	fill.light_color = Color(0.75, 0.84, 1.0)
	fill.light_energy = 0.35
	parent.add_child(fill)
	_add_horizon(parent)


func _add_horizon(parent: Node3D) -> void:
	# Gray lot around the pad, then the supplied city layers. No mountain rocks.
	var deck := MeshInstance3D.new()
	deck.name = "HorizonGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(480, 480)
	deck.mesh = plane
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.58, 0.59, 0.61)
	dirt.roughness = 1.0
	deck.material_override = dirt
	deck.position = Vector3(-0.5, -0.03, 1.0)
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(deck)
	_add_city(parent)


func _add_city(parent: Node3D) -> void:
	# Layers from FREE Background City, far to near: sky, trees, then three skylines.
	var layers: Array[Dictionary] = [
		{"file": "background_00.png", "radius": 220.0, "width": 500.0, "height": 220.0, "y": 90.0},
		{"file": "background_01.png", "radius": 180.0, "width": 420.0, "height": 64.0, "y": 26.0},
		{"file": "background_02.png", "radius": 154.0, "width": 370.0, "height": 58.0, "y": 24.0},
		{"file": "background_03.png", "radius": 132.0, "width": 330.0, "height": 56.0, "y": 22.0},
		{"file": "background_04.png", "radius": 112.0, "width": 290.0, "height": 46.0, "y": 18.0},
	]
	var yaws: Array[float] = [0.0, -PI * 0.5, PI, PI * 0.5]
	for layer_i in range(layers.size()):
		var spec: Dictionary = layers[layer_i]
		var tex: Texture2D = load("res://assets/background/%s" % str(spec["file"])) as Texture2D
		if tex == null:
			push_error("Missing city layer %s" % str(spec["file"]))
			continue
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.15
		mat.albedo_texture = tex
		mat.albedo_color = Color.WHITE
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		var mesh := QuadMesh.new()
		mesh.size = Vector2(float(spec["width"]), float(spec["height"]))
		var radius: float = float(spec["radius"])
		var height: float = float(spec["y"])
		var spots: Array[Vector3] = [
			Vector3(-0.5, height, -radius),
			Vector3(radius, height, 1.0),
			Vector3(-0.5, height, radius),
			Vector3(-radius, height, 1.0),
		]
		for side in range(spots.size()):
			var plate := MeshInstance3D.new()
			plate.name = "CityBackdrop%d_%d" % [layer_i, side]
			plate.mesh = mesh
			plate.material_override = mat
			plate.position = spots[side]
			plate.rotation.y = yaws[side]
			plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			plate.extra_cull_margin = 200.0
			parent.add_child(plate)


func _add_play_line(parent: Node3D) -> void:
	# Concrete tiles run x -28..27 and z -23..25, each one metre across.
	var x_min := -28.5
	var x_max := 27.5
	var z_min := -23.5
	var z_max := 25.5
	var y := 0.03
	var thin := 0.045
	var span_x := x_max - x_min
	var span_z := z_max - z_min
	_red_strip(parent, Vector3((x_min + x_max) * 0.5, y, z_min), Vector3(span_x, 0.015, thin))
	_red_strip(parent, Vector3((x_min + x_max) * 0.5, y, z_max), Vector3(span_x, 0.015, thin))
	_red_strip(parent, Vector3(x_min, y, (z_min + z_max) * 0.5), Vector3(thin, 0.015, span_z))
	_red_strip(parent, Vector3(x_max, y, (z_min + z_max) * 0.5), Vector3(thin, 0.015, span_z))


func _red_strip(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "PlayLine"
	var box := BoxMesh.new()
	box.size = size
	mesh_node.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.86, 0.14, 0.12)
	mesh_node.material_override = mat
	mesh_node.position = at
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh_node)


func build_pad(parent: Node3D) -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var shape := BoxShape3D.new()
	shape.size = Vector3(56, 1, 49)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(-0.5, -0.5, 1)
	ground.add_child(col)
	parent.add_child(ground)

	var tile_scene: PackedScene = load(MODEL % "floor-concrete") as PackedScene
	if tile_scene == null:
		push_error("Missing model floor-concrete")
		return
	var sample: Node = tile_scene.instantiate()
	var tile_mesh: MeshInstance3D = _find_mesh(sample)
	if tile_mesh == null or tile_mesh.mesh == null:
		sample.free()
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = tile_mesh.mesh
	var x0 := -28
	var x1 := 28
	var z0 := -23
	var z1 := 26
	multi.instance_count = (x1 - x0) * (z1 - z0)
	var index := 0
	for x in range(x0, x1):
		for z in range(z0, z1):
			multi.set_instance_transform(index, Transform3D(Basis(), Vector3(x, 0, z)))
			index += 1
	var tiles := MultiMeshInstance3D.new()
	tiles.name = "Concrete"
	tiles.multimesh = multi
	tiles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(tiles)
	sample.free()
	_add_play_line(parent)


func place_item(parent: Node3D, item: Dictionary) -> Node3D:
	var id: String = str(item["id"])
	if id == "corner":
		return _place_corner(parent, item)
	return place(parent, id, int(item["x"]), int(item["z"]), int(item["rot"]), float(item.get("y", 0.0)))


func quarter_pair(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("id", "")) != "quarter" or str(b.get("id", "")) != "quarter":
		return false
	var dx: int = absi(int(a["x"]) - int(b["x"]))
	var dz: int = absi(int(a["z"]) - int(b["z"]))
	if dx + dz != 1:
		return false
	if absf(float(a.get("y", 0.0)) - float(b.get("y", 0.0))) > 0.05:
		return false
	var diff: int = posmod(int(a["rot"]) - int(b["rot"]), 360)
	return diff == 90 or diff == 270


func corner_from(a: Dictionary, b: Dictionary) -> Dictionary:
	return {
		"id": "corner",
		"x": int(a["x"]),
		"z": int(a["z"]),
		"rot": int(a["rot"]),
		"x2": int(b["x"]),
		"z2": int(b["z"]),
		"rot2": int(b["rot"]),
		"y": float(a.get("y", 0.0)),
	}


func absorb_corners(items: Array) -> Array:
	# Do not join quarters. An old generated corner is restored as two quarters.
	var out: Array = []
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		if str(entry.get("id", "")) != "corner":
			out.append(entry)
			continue
		var height: float = float(entry.get("y", 0.0))
		var first: Dictionary = {
			"id": "quarter",
			"x": int(entry.get("x", 0)),
			"z": int(entry.get("z", 0)),
			"rot": int(entry.get("rot", 0)),
			"y": height,
		}
		var second: Dictionary = {
			"id": "quarter",
			"x": int(entry.get("x2", entry.get("x", 0))),
			"z": int(entry.get("z2", entry.get("z", 0))),
			"rot": int(entry.get("rot2", entry.get("rot", 0))),
			"y": height,
		}
		out.append(first)
		out.append(second)
	return out


func stack_block(ids: Array) -> String:
	if ids.is_empty():
		return ""
	if ids.size() >= 4:
		return "Stack limit is 4"
	if str(ids[ids.size() - 1]) != "floor-concrete":
		return "Only on concrete"
	return ""


func keep_floors(items: Array) -> Array:
	return keep_stacks(items)


func keep_stacks(items: Array) -> Array:
	# Keep every piece. Extra levels stay only on concrete, four high.
	var groups: Dictionary = {}
	var order: Array = []
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var key := Vector2i(int(entry.get("x", 0)), int(entry.get("z", 0)))
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		var column: Array = groups[key]
		column.append(entry)
		groups[key] = column
	var out: Array = []
	for key in order:
		var column: Array = groups[key]
		column.sort_custom(func(a, b) -> bool:
			var ay: float = 0.0
			var by: float = 0.0
			if typeof(a) == TYPE_DICTIONARY:
				ay = float((a as Dictionary).get("y", 0.0))
			if typeof(b) == TYPE_DICTIONARY:
				by = float((b as Dictionary).get("y", 0.0))
			return ay < by
		)
		var kept: Array = []
		for item in column:
			var entry: Dictionary = item
			if kept.size() >= 4:
				break
			if not kept.is_empty():
				var below: Dictionary = kept[kept.size() - 1]
				if str(below.get("id", "")) != "floor-concrete":
					break
			kept.append(entry)
		for item in kept:
			out.append(item)
	return out


func piece_height(id: String) -> float:
	match id:
		"quarter", "corner", "bank", "bowl-side", "bowl-corner-inner", "bowl-corner-outer":
			return 0.8
		"half-pipe-low", "bowl-side-low", "bowl-corner-inner-low", "bowl-corner-outer-low":
			return 0.4
		"ramp", "ramp-rail":
			return 0.32
		"ledge", "obstacle-middle-rail", "obstacle-box", "obstacle-box-grind", "obstacle-end", "obstacle-corner":
			return 0.3
		"steps", "steps-rail":
			return 0.35
		"low-rail", "low-rail-end", "rail-curve":
			return 0.28
		"high-rail", "rail-high-curve":
			return 0.48
		"rail-slope", "rail-slope-smooth":
			return 0.7
		"structure-platform", "structure-wood-platform", "bowl-platform":
			return 0.25
		"structure-wood":
			return 0.55
		"fence":
			return 0.7
		"bench", "benches":
			return 0.42
		"pallet":
			return 0.15
		"floor-concrete":
			return 0.2
		"plank", "start":
			return 0.05
		"scooter":
			return 0.5
		"vehicle":
			return 0.6
		_:
			return 0.4


func piece_name(id: String) -> String:
	if id == "corner":
		return "Corner"
	return _label_for_model(_model_name(id))


func catalog() -> Array:
	var files: Array[String] = []
	var dir := DirAccess.open("res://assets/kenney-mini-skate")
	if dir != null:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".glb"):
				var base: String = file_name.get_basename()
				if not _is_player_model(base):
					files.append(base)
			file_name = dir.get_next()
		dir.list_dir_end()
	files.sort()
	var lead: Array[String] = ["half-pipe", "slope-smooth", "ramp", "rail-low", "rail-high", "obstacle-middle", "floor-wood"]
	var ordered: Array[String] = []
	for base in lead:
		if files.has(base):
			ordered.append(base)
	for base in files:
		if not ordered.has(base):
			ordered.append(base)
	var rows: Array = []
	for base in ordered:
		rows.append({"id": _id_for_model(base), "name": _label_for_model(base)})
	return rows


func _is_player_model(base: String) -> bool:
	return base == "character-skate-boy" or base == "character-skate-girl" or base == "skateboard"


func _id_for_model(base: String) -> String:
	match base:
		"half-pipe":
			return "quarter"
		"slope-smooth":
			return "bank"
		"obstacle-middle":
			return "ledge"
		"floor-wood":
			return "start"
		"rail-low":
			return "low-rail"
		"rail-high":
			return "high-rail"
		"rail-low-end":
			return "low-rail-end"
		_:
			return base


func _label_for_model(base: String) -> String:
	match base:
		"half-pipe":
			return "Quarter"
		"slope-smooth":
			return "Bank"
		"ramp":
			return "Funbox ramp"
		"rail-low":
			return "Low rail"
		"rail-high":
			return "High rail"
		"obstacle-middle":
			return "Ledge"
		"floor-wood":
			return "Start pad"
		"half-pipe-low":
			return "Low quarter"
		"rail-low-end":
			return "Low rail end"
		"rail-curve":
			return "Curved rail"
		"rail-high-curve":
			return "High curved rail"
		"rail-slope":
			return "Rail slope"
		"rail-slope-smooth":
			return "Smooth rail slope"
		"ramp-rail":
			return "Funbox rail"
		"bowl-side":
			return "Bowl side"
		"bowl-side-low":
			return "Low bowl side"
		"bowl-corner-inner":
			return "Bowl inner corner"
		"bowl-corner-outer":
			return "Bowl outer corner"
		"bowl-corner-inner-low":
			return "Low bowl inner"
		"bowl-corner-outer-low":
			return "Low bowl outer"
		"bowl-platform":
			return "Bowl platform"
		"obstacle-box":
			return "Box"
		"obstacle-box-grind":
			return "Grind box"
		"obstacle-end":
			return "Obstacle end"
		"obstacle-corner":
			return "Obstacle corner"
		"obstacle-middle-rail":
			return "Ledge rail"
		"steps":
			return "Steps"
		"steps-rail":
			return "Steps rail"
		"structure-wood":
			return "Wood frame"
		"structure-wood-platform":
			return "Wood platform"
		"structure-platform":
			return "Platform"
		"floor-concrete":
			return "Concrete tile"
		"fence":
			return "Fence"
		"bench":
			return "Bench"
		"benches":
			return "Benches"
		"pallet":
			return "Pallet"
		"plank":
			return "Plank"
		"scooter":
			return "Scooter"
		"vehicle":
			return "Vehicle"
		_:
			return base.replace("-", " ").capitalize()


func _collide_piece(body: StaticBody3D, id: String) -> void:
	body.collision_layer = 1
	body.collision_mask = 1
	# The solid is the mesh the player sees. A bounding box leaves an invisible wall
	# in the air above a slope, and a rail on the stairs turns the whole stair into a cube.
	if _collide_visual(body):
		return
	_prop_box(body, piece_height(id))


func _collide_visual(body: StaticBody3D) -> bool:
	var faces := PackedVector3Array()
	_append_trimesh(body, Transform3D.IDENTITY, faces, false)
	if faces.size() < 3:
		return false
	var min_v := Vector3(1000, 1000, 1000)
	var max_v := Vector3(-1000, -1000, -1000)
	for p in faces:
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	var span := max_v - min_v
	# A single flat tile has no thickness, so give it a few centimetres. Do not grow the footprint.
	if span.y < 0.04 and span.x > 0.25 and span.z > 0.25:
		var thick := 0.04
		var shape := BoxShape3D.new()
		shape.size = Vector3(span.x, thick, span.z)
		var col := CollisionShape3D.new()
		col.name = "Plane"
		col.shape = shape
		col.position = Vector3((min_v.x + max_v.x) * 0.5, max_v.y - thick * 0.5, (min_v.z + max_v.z) * 0.5)
		body.add_child(col)
		return true
	var count := faces.size()
	var rev := PackedVector3Array()
	rev.resize(count)
	for i in range(0, count, 3):
		rev[i] = faces[i]
		rev[i + 1] = faces[i + 2]
		rev[i + 2] = faces[i + 1]
	faces.append_array(rev)
	var mesh_shape := ConcavePolygonShape3D.new()
	mesh_shape.data = faces
	var mesh_col := CollisionShape3D.new()
	mesh_col.name = "MeshSolid"
	mesh_col.shape = mesh_shape
	body.add_child(mesh_col)
	return true


func _append_trimesh(node: Node, xform: Transform3D, faces: PackedVector3Array, apply_self: bool) -> void:
	var here: Transform3D = xform
	if apply_self and node is Node3D:
		here = xform * (node as Node3D).transform
	if node is MeshInstance3D and str(node.name) != "FacingArrow":
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			var built: Shape3D = mesh.create_trimesh_shape()
			if built is ConcavePolygonShape3D:
				var data: PackedVector3Array = (built as ConcavePolygonShape3D).data
				for p in data:
					faces.push_back(here * p)
	for child in node.get_children():
		_append_trimesh(child, here, faces, true)


func _simple_ramp(body: StaticBody3D, height: float) -> void:
	_wedge(body, Vector2(-0.5, height), Vector2(0.55, 0.0), 1.0)


func _start_pad_box(body: StaticBody3D) -> void:
	# The wood pad is a thin tile. Keep its real footprint and thickness.
	var pts := PackedVector3Array()
	_gather_mesh_points(body, Transform3D.IDENTITY, pts, false)
	var min_x := -0.5
	var max_x := 0.5
	var min_y := 0.0
	var max_y := 0.025
	var min_z := -0.5
	var max_z := 0.5
	if pts.size() >= 3:
		min_x = 1000.0
		max_x = -1000.0
		min_y = 1000.0
		max_y = -1000.0
		min_z = 1000.0
		max_z = -1000.0
		for p in pts:
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
			min_y = minf(min_y, p.y)
			max_y = maxf(max_y, p.y)
			min_z = minf(min_z, p.z)
			max_z = maxf(max_z, p.z)
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(max_x - min_x, 0.02), maxf(max_y - min_y, 0.02), maxf(max_z - min_z, 0.02))
	var col := CollisionShape3D.new()
	col.name = "Pad"
	col.shape = shape
	col.position = Vector3((min_x + max_x) * 0.5, (min_y + max_y) * 0.5, (min_z + max_z) * 0.5)
	body.add_child(col)


func _prop_box(body: StaticBody3D, height: float) -> void:
	var shape := BoxShape3D.new()
	var h: float = maxf(height, 0.4)
	shape.size = Vector3(0.92, h, 0.92)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, h * 0.5, 0)
	body.add_child(col)


func _is_ramp(id: String) -> bool:
	match id:
		"quarter", "bank", "ramp", "ramp-rail", "half-pipe-low", \
		"bowl-side", "bowl-side-low", \
		"bowl-corner-inner", "bowl-corner-inner-low", \
		"bowl-corner-outer", "bowl-corner-outer-low", \
		"steps", "steps-rail", "obstacle-end", "obstacle-corner":
			return true
		_:
			return false


func _solid_ramp(body: StaticBody3D) -> bool:
	var tris: Array = []
	_gather_up_tris(body, Transform3D.IDENTITY, tris, false)
	if tris.is_empty():
		return false
	var min_x := 1000.0
	var max_x := -1000.0
	var min_z := 1000.0
	var max_z := -1000.0
	var min_y := 1000.0
	var max_y := -1000.0
	for tri in tris:
		var face: PackedVector3Array = tri
		for p in face:
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
			min_z = minf(min_z, p.z)
			max_z = maxf(max_z, p.z)
			min_y = minf(min_y, p.y)
			max_y = maxf(max_y, p.y)
	var span_x: float = max_x - min_x
	var span_z: float = max_z - min_z
	if span_x < 0.05 or span_z < 0.05 or max_y - min_y < 0.08:
		return false
	var nx: int = clampi(int(ceil(span_x / 0.2)), 1, 8)
	var nz: int = clampi(int(ceil(span_z / 0.2)), 1, 12)
	var cols := nx + 1
	var rows := nz + 1
	var heights := PackedFloat32Array()
	heights.resize(cols * rows)
	for iz in rows:
		var z: float = lerpf(min_z, max_z, float(iz) / float(nz))
		for ix in cols:
			heights[iz * cols + ix] = _ramp_height(tris, lerpf(min_x, max_x, float(ix) / float(nx)), z)
	var made := 0
	var floor_y := -0.05
	for iz in nz:
		for ix in nx:
			var i00: int = iz * cols + ix
			var i10: int = i00 + 1
			var i01: int = i00 + cols
			var i11: int = i01 + 1
			if heights[i00] < -100.0 or heights[i10] < -100.0 or heights[i01] < -100.0 or heights[i11] < -100.0:
				continue
			var x0: float = lerpf(min_x, max_x, float(ix) / float(nx)) - 0.02
			var x1: float = lerpf(min_x, max_x, float(ix + 1) / float(nx)) + 0.02
			var z0: float = lerpf(min_z, max_z, float(iz) / float(nz)) - 0.02
			var z1: float = lerpf(min_z, max_z, float(iz + 1) / float(nz)) + 0.02
			_ramp_cell(body, x0, z0, x1, z1, heights[i00], heights[i10], heights[i01], heights[i11], floor_y)
			made += 1
	return made > 0


func _ramp_height(tris: Array, x: float, z: float) -> float:
	var best := 1000.0
	var hit := false
	for tri in tris:
		var face: PackedVector3Array = tri
		var a: Vector3 = face[0]
		var b: Vector3 = face[1]
		var c: Vector3 = face[2]
		var v0x: float = c.x - a.x
		var v0z: float = c.z - a.z
		var v1x: float = b.x - a.x
		var v1z: float = b.z - a.z
		var den: float = v0x * v1z - v1x * v0z
		if absf(den) < 0.0000001:
			continue
		var v2x: float = x - a.x
		var v2z: float = z - a.z
		var u: float = (v2x * v1z - v1x * v2z) / den
		var v: float = (v0x * v2z - v2x * v0z) / den
		if u < -0.04 or v < -0.04 or u + v > 1.04:
			continue
		var y: float = a.y * (1.0 - u - v) + b.y * v + c.y * u
		best = minf(best, y)
		hit = true
	if not hit:
		return -1000.0
	return best


func _ramp_cell(body: StaticBody3D, x0: float, z0: float, x1: float, z1: float, h00: float, h10: float, h01: float, h11: float, floor_y: float) -> void:
	var lift: float = floor_y + 0.04
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(x0, floor_y, z0),
		Vector3(x1, floor_y, z0),
		Vector3(x0, floor_y, z1),
		Vector3(x1, floor_y, z1),
		Vector3(x0, maxf(h00, lift), z0),
		Vector3(x1, maxf(h10, lift), z0),
		Vector3(x0, maxf(h01, lift), z1),
		Vector3(x1, maxf(h11, lift), z1),
	])
	var col := CollisionShape3D.new()
	col.name = "Ramp"
	col.shape = shape
	body.add_child(col)


func _gather_up_tris(node: Node, xform: Transform3D, tris: Array, apply_self: bool) -> void:
	var here: Transform3D = xform
	if apply_self and node is Node3D:
		here = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			for s in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(s)
				if arrays.size() <= Mesh.ARRAY_VERTEX:
					continue
				var raw = arrays[Mesh.ARRAY_VERTEX]
				if not (raw is PackedVector3Array):
					continue
				var verts: PackedVector3Array = raw
				var indices := PackedInt32Array()
				var raw_idx = arrays[Mesh.ARRAY_INDEX]
				if raw_idx is PackedInt32Array and (raw_idx as PackedInt32Array).size() >= 3:
					indices = raw_idx
				else:
					indices.resize(verts.size())
					for i in verts.size():
						indices[i] = i
				var count: int = indices.size() - (indices.size() % 3)
				for i in range(0, count, 3):
					var a: Vector3 = here * verts[indices[i]]
					var b: Vector3 = here * verts[indices[i + 1]]
					var c: Vector3 = here * verts[indices[i + 2]]
					var n: Vector3 = (b - a).cross(c - a)
					if n.length_squared() < 0.0000001 or n.y <= 0.15 * n.length():
						continue
					var face := PackedVector3Array()
					face.push_back(a)
					face.push_back(b)
					face.push_back(c)
					tris.append(face)
	for child in node.get_children():
		_gather_up_tris(child, here, tris, true)


func _solid_from_mesh(body: StaticBody3D) -> bool:
	var pts := PackedVector3Array()
	_gather_mesh_points(body, Transform3D.IDENTITY, pts, false)
	if pts.size() < 3:
		return false
	var min_x := 1000.0
	var max_x := -1000.0
	var min_y := 1000.0
	var max_y := -1000.0
	var min_z := 1000.0
	var max_z := -1000.0
	for p in pts:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	var span_x: float = max_x - min_x
	var span_y: float = max_y - min_y
	var span_z: float = max_z - min_z
	# Anything thinner than 0.4 m can be skipped in one physics frame.
	# Extra thickness grows up from the mesh so a flat tile becomes a block.
	var size_x: float = maxf(span_x, 0.4)
	var size_y: float = maxf(span_y, 0.4)
	var size_z: float = maxf(span_z, 0.4)
	var center_x: float = (min_x + max_x) * 0.5
	var center_z: float = (min_z + max_z) * 0.5
	var center_y: float = (min_y + max_y) * 0.5
	if span_y < 0.4:
		center_y = min_y + size_y * 0.5
	var shape := BoxShape3D.new()
	shape.size = Vector3(size_x, size_y, size_z)
	var col := CollisionShape3D.new()
	col.name = "Solid"
	col.shape = shape
	col.position = Vector3(center_x, center_y, center_z)
	body.add_child(col)
	return true


func _gather_mesh_points(node: Node, xform: Transform3D, pts: PackedVector3Array, apply_self: bool) -> void:
	var here: Transform3D = xform
	if apply_self and node is Node3D:
		here = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var mesh: Mesh = mesh_node.mesh
		if mesh != null:
			for s in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(s)
				if arrays.size() <= Mesh.ARRAY_VERTEX:
					continue
				var raw = arrays[Mesh.ARRAY_VERTEX]
				if raw is PackedVector3Array:
					var verts: PackedVector3Array = raw
					for v in verts:
						pts.append(here * v)
	for child in node.get_children():
		_gather_mesh_points(child, here, pts, true)


func place(parent: Node3D, id: String, x: int, z: int, rot: int, stack_y: float = 0.0) -> Node3D:
	var deg := posmod(rot, 360)
	if id == "start":
		var pad := StaticBody3D.new()
		_stamp(pad, id, x, z, deg, stack_y + 0.01)
		pad.set_meta("stack_y", stack_y)
		parent.add_child(pad)
		_add_model(pad, "floor-wood")
		_collide_piece(pad, id)
		_add_facing_arrow(pad)
		return pad
	var body := StaticBody3D.new()
	_stamp(body, id, x, z, deg, stack_y)
	body.set_meta("stack_y", stack_y)
	parent.add_child(body)
	_add_model(body, _model_name(id))
	_collide_piece(body, id)
	return body


func make_icon(parent: Node3D, id: String) -> Node3D:
	var node := Node3D.new()
	var model_name := _model_name(id)
	if model_name != "":
		_add_model(node, model_name)
	if id == "start":
		_add_facing_arrow(node)
	parent.add_child(node)
	return node


func weld_ramps(root: Node) -> void:
	var bodies: Array = []
	for child in root.get_children():
		if not (child is StaticBody3D):
			continue
		var body: StaticBody3D = child as StaticBody3D
		if not body.has_meta("piece_id"):
			continue
		var pid: String = str(body.get_meta("piece_id"))
		if pid == "quarter" or pid == "ramp":
			bodies.append(body)
	for i in range(bodies.size()):
		for j in range(i + 1, bodies.size()):
			var first: StaticBody3D = bodies[i] as StaticBody3D
			var second: StaticBody3D = bodies[j] as StaticBody3D
			_try_hip(first, second)


func _try_hip(a: StaticBody3D, b: StaticBody3D) -> void:
	var ax: int = int(a.get_meta("cell_x"))
	var az: int = int(a.get_meta("cell_z"))
	var bx: int = int(b.get_meta("cell_x"))
	var bz: int = int(b.get_meta("cell_z"))
	if absi(ax - bx) + absi(az - bz) != 1:
		return
	if absf(float(a.get_meta("stack_y", 0.0)) - float(b.get_meta("stack_y", 0.0))) > 0.05:
		return
	var ar: int = posmod(int(a.get_meta("rot")), 360)
	var br: int = posmod(int(b.get_meta("rot")), 360)
	var diff: int = posmod(ar - br, 360)
	if diff != 90 and diff != 270:
		return
	_fill_hip(a, b)


func _local_point(body: StaticBody3D, lx: float, lz: float) -> Vector3:
	var yaw: float = deg_to_rad(float(int(body.get_meta("rot"))))
	var x: float = lx * cos(yaw) + lz * sin(yaw)
	var z: float = -lx * sin(yaw) + lz * cos(yaw)
	return body.position + Vector3(x, 0.0, z)


func _lip_height(body: StaticBody3D) -> float:
	if str(body.get_meta("piece_id")) == "quarter":
		return 0.78
	return 0.32


func _fill_hip(a: StaticBody3D, b: StaticBody3D) -> void:
	var a_lip: Vector3 = _local_point(a, 0.0, -0.5)
	var b_lip: Vector3 = _local_point(b, 0.0, -0.5)
	var a_down: Vector3 = _local_point(a, 0.0, 0.5) - a_lip
	var b_down: Vector3 = _local_point(b, 0.0, 0.5) - b_lip
	a_down.y = 0.0
	b_down.y = 0.0
	if a_down.length_squared() < 0.01 or b_down.length_squared() < 0.01:
		return
	a_down = a_down.normalized()
	b_down = b_down.normalized()
	var down: Vector3 = a_down + b_down
	if down.length_squared() < 0.04:
		return
	down = down.normalized()
	var side: Vector3 = Vector3(-down.z, 0.0, down.x)
	var peak: Vector3 = (a_lip + b_lip) * 0.5
	var high: float = minf(_lip_height(a), _lip_height(b))
	var hip := StaticBody3D.new()
	hip.name = "Hip"
	a.get_parent().add_child(hip)
	_hip_wedge(hip, peak, down, side, 0.0, 0.48, high, high * 0.48)
	_hip_wedge(hip, peak, down, side, 0.48, 1.02, high * 0.48, 0.02)


func _hip_wedge(body: StaticBody3D, peak: Vector3, down: Vector3, side: Vector3, t0: float, t1: float, h0: float, h1: float) -> void:
	var c0: Vector3 = peak + down * t0
	var c1: Vector3 = peak + down * t1
	var w := 0.62
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		c0 + side * w + Vector3(0, -0.08, 0),
		c0 - side * w + Vector3(0, -0.08, 0),
		c1 + side * w + Vector3(0, -0.08, 0),
		c1 - side * w + Vector3(0, -0.08, 0),
		c0 + side * w + Vector3(0, h0, 0),
		c0 - side * w + Vector3(0, h0, 0),
		c1 + side * w + Vector3(0, h1, 0),
		c1 - side * w + Vector3(0, h1, 0),
	])
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)


func make_visual(parent: Node3D, id: String, x: int, z: int, rot: int, stack_y: float = 0.0) -> Node3D:
	var node := Node3D.new()
	var deg := posmod(rot, 360)
	node.position = Vector3(x, stack_y + 0.05, z)
	node.rotation.y = deg_to_rad(float(deg))
	var model_name := _model_name(id)
	if model_name != "":
		_add_model(node, model_name)
		_tint_ghost(node)
	if id == "start":
		_add_facing_arrow(node)
	parent.add_child(node)
	return node


func _add_facing_arrow(parent: Node3D) -> void:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "FacingArrow"
	mesh_node.mesh = _facing_arrow_mesh()
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.98, 0.42, 0.12, 1)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_node.material_override = mat
	parent.add_child(mesh_node)


func _facing_arrow_mesh() -> ArrayMesh:
	# Local -Z matches spawn heading: rotation 0 faces world -Z.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.12
	var tip := Vector3(0.0, y, -0.42)
	var head_l := Vector3(-0.24, y, -0.06)
	var head_r := Vector3(0.24, y, -0.06)
	var neck_l := Vector3(-0.09, y, -0.06)
	var neck_r := Vector3(0.09, y, -0.06)
	var tail_l := Vector3(-0.09, y, 0.38)
	var tail_r := Vector3(0.09, y, 0.38)
	_arrow_face(st, tip, head_r, head_l)
	_arrow_face(st, neck_l, neck_r, tail_r)
	_arrow_face(st, neck_l, tail_r, tail_l)
	st.generate_normals()
	return st.commit()


func _arrow_face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _model_name(id: String) -> String:
	match id:
		"quarter":
			return "half-pipe"
		"bank":
			return "slope-smooth"
		"ledge":
			return "obstacle-middle"
		"start":
			return "floor-wood"
		"low-rail":
			return "rail-low"
		"high-rail":
			return "rail-high"
		"low-rail-end":
			return "rail-low-end"
		"corner":
			return ""
		_:
			return id


func _stamp(node: Node3D, id: String, x: int, z: int, rot: int, y: float) -> void:
	node.name = id
	node.position = Vector3(x, y, z)
	node.rotation.y = deg_to_rad(float(rot))
	node.set_meta("piece_id", id)
	node.set_meta("cell_x", x)
	node.set_meta("cell_z", z)
	node.set_meta("rot", rot)


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found: MeshInstance3D = _find_mesh(child)
		if found != null:
			return found
	return null


func _add_model(body: Node3D, model_name: String) -> void:
	if model_name == "":
		return
	var packed: PackedScene = load(MODEL % model_name) as PackedScene
	if packed == null:
		push_error("Missing model %s" % model_name)
		return
	body.add_child(packed.instantiate())


func _tint_ghost(node: Node) -> void:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.58, 0.22, 0.4)
	_tint_rec(node, mat)


func _tint_rec(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		mesh_node.material_overlay = mat
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_tint_rec(child, mat)


func _quarter_ramps(body: StaticBody3D) -> void:
	var pts: Array[Vector2] = [
		Vector2(-0.58, 0.80),
		Vector2(-0.28, 0.66),
		Vector2(-0.12, 0.38),
		Vector2(0.08, 0.14),
		Vector2(0.30, 0.04),
		Vector2(0.58, 0.0),
	]
	for i in range(pts.size() - 1):
		_wedge(body, pts[i], pts[i + 1], 1.02)


func _bank_ramps(body: StaticBody3D) -> void:
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


func _ramp_box(body: StaticBody3D) -> void:
	var deck := BoxShape3D.new()
	deck.size = Vector3(1.02, 0.32, 0.52)
	var dcol := CollisionShape3D.new()
	dcol.shape = deck
	dcol.position = Vector3(0, 0.16, -0.28)
	body.add_child(dcol)
	_wedge(body, Vector2(-0.08, 0.32), Vector2(0.58, 0.0), 1.02)


func _ledge_box(body: StaticBody3D) -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.98, 0.30, 0.98)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 0.15, 0)
	body.add_child(col)


func _rail_box(body: StaticBody3D, bar_y: float) -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.16, 0.10, 0.92)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, bar_y, 0)
	body.add_child(col)


func _place_corner(parent: Node3D, item: Dictionary) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "Corner"
	body.position = Vector3.ZERO
	body.rotation = Vector3.ZERO
	var x: int = int(item["x"])
	var z: int = int(item["z"])
	var rot: int = posmod(int(item["rot"]), 360)
	var x2: int = int(item.get("x2", x))
	var z2: int = int(item.get("z2", z))
	var rot2: int = posmod(int(item.get("rot2", rot)), 360)
	body.set_meta("piece_id", "corner")
	body.set_meta("cell_x", x)
	body.set_meta("cell_z", z)
	body.set_meta("rot", rot)
	body.set_meta("cell_x2", x2)
	body.set_meta("cell_z2", z2)
	body.set_meta("rot2", rot2)
	var stack_y: float = float(item.get("y", 0.0))
	body.set_meta("stack_y", stack_y)
	body.position = Vector3(0.0, stack_y, 0.0)
	parent.add_child(body)
	_fill_corner(body, x, z, rot, x2, z2, rot2, true)
	return body


func make_corner_visual(parent: Node3D, item: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.position = Vector3(0.0, float(item.get("y", 0.0)), 0.0)
	parent.add_child(node)
	_fill_corner(node, int(item["x"]), int(item["z"]), int(item["rot"]), int(item["x2"]), int(item["z2"]), int(item["rot2"]), false)
	_tint_ghost(node)
	return node


func _lip_dir(rot: int) -> Vector2:
	var r: int = posmod(rot, 360)
	if r == 90:
		return Vector2(-1, 0)
	if r == 180:
		return Vector2(0, 1)
	if r == 270:
		return Vector2(1, 0)
	return Vector2(0, -1)


func _corner_profile(radius: float) -> float:
	# Same lip-to-toe curve as a quarter, measured from the outer corner.
	if radius <= 0.0:
		return 0.80
	if radius >= 1.16:
		return 0.0
	var samples: Array[Vector2] = [
		Vector2(0.00, 0.80),
		Vector2(0.30, 0.66),
		Vector2(0.46, 0.38),
		Vector2(0.66, 0.14),
		Vector2(0.88, 0.04),
		Vector2(1.16, 0.00),
	]
	for i in range(samples.size() - 1):
		var a: Vector2 = samples[i]
		var b: Vector2 = samples[i + 1]
		if radius <= b.x:
			var t: float = (radius - a.x) / maxf(b.x - a.x, 0.0001)
			return lerpf(a.y, b.y, t)
	return 0.0


func _fill_corner(node: Node3D, x: int, z: int, rot: int, x2: int, z2: int, rot2: int, solid: bool) -> void:
	if absi(x - x2) + absi(z - z2) != 1:
		return
	var turn: int = posmod(rot - rot2, 360)
	if turn != 90 and turn != 270:
		return
	var mid := Vector2(float(x + x2) * 0.5, float(z + z2) * 0.5)
	var hx: float = absf(float(x - x2)) * 0.5 + 0.5
	var hz: float = absf(float(z - z2)) * 0.5 + 0.5
	var uphill: Vector2 = _lip_dir(rot) + _lip_dir(rot2)
	if uphill.length_squared() < 0.25:
		return
	var best := mid
	var best_d := -1000.0
	var signs: Array[float] = [-1.0, 1.0]
	for sx in signs:
		for sz in signs:
			var corner := mid + Vector2(sx * hx, sz * hz)
			var score: float = (corner - mid).dot(uphill)
			if score > best_d:
				best_d = score
				best = corner
	var axis_u := Vector3(-1.0 if best.x > mid.x else 1.0, 0.0, 0.0)
	var axis_v := Vector3(0.0, 0.0, -1.0 if best.y > mid.y else 1.0)
	var origin := Vector3(best.x, 0.0, best.y)
	var span_u: float = hx * 2.0
	var span_v: float = hz * 2.0
	var steps_u: int = maxi(int(round(span_u / 0.25)), 1)
	var steps_v: int = maxi(int(round(span_v / 0.25)), 1)
	if solid and node is StaticBody3D:
		var body: StaticBody3D = node as StaticBody3D
		for iu in range(steps_u):
			for iv in range(steps_v):
				var u0: float = span_u * float(iu) / float(steps_u)
				var u1: float = span_u * float(iu + 1) / float(steps_u)
				var v0: float = span_v * float(iv) / float(steps_v)
				var v1: float = span_v * float(iv + 1) / float(steps_v)
				_bank_prism(body, origin, axis_u, axis_v, u0, v0, u1, v1)
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "CornerMesh"
	var built: Array = _corner_mesh(origin, axis_u, axis_v, span_u, span_v, steps_u, steps_v)
	var corner_mesh: Mesh = built[0] as Mesh
	var corner_mat: Material = built[1] as Material
	mesh_node.mesh = corner_mesh
	mesh_node.material_override = corner_mat
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mesh_node.extra_cull_margin = 4.0
	node.add_child(mesh_node)


func _bank_height(u: float, v: float) -> float:
	# High along both outer lips, falling to the floor toward each opening.
	return _corner_profile(minf(u, v))


func _bank_top(origin: Vector3, axis_u: Vector3, axis_v: Vector3, u: float, v: float) -> Vector3:
	return origin + axis_u * u + axis_v * v + Vector3(0.0, _bank_height(u, v) + 0.02, 0.0)


func _bank_prism(body: StaticBody3D, origin: Vector3, axis_u: Vector3, axis_v: Vector3, u0: float, v0: float, u1: float, v1: float) -> void:
	var a: Vector3 = _bank_top(origin, axis_u, axis_v, u0, v0)
	var b: Vector3 = _bank_top(origin, axis_u, axis_v, u1, v0)
	var c: Vector3 = _bank_top(origin, axis_u, axis_v, u1, v1)
	var d: Vector3 = _bank_top(origin, axis_u, axis_v, u0, v1)
	var floor_y := -0.06
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(a.x, floor_y, a.z),
		Vector3(b.x, floor_y, b.z),
		Vector3(c.x, floor_y, c.z),
		Vector3(d.x, floor_y, d.z),
		a, b, c, d,
	])
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)


func _fan_point(origin: Vector3, axis_u: Vector3, axis_v: Vector3, radius: float, ang: float, height: float) -> Vector3:
	return origin + axis_u * (radius * cos(ang)) + axis_v * (radius * sin(ang)) + Vector3(0, height, 0)


func _fan_wedge(body: StaticBody3D, origin: Vector3, axis_u: Vector3, axis_v: Vector3, r0: float, r1: float, a0: float, a1: float) -> void:
	var h00: float = _corner_profile(r0)
	var h01: float = _corner_profile(r0)
	var h10: float = _corner_profile(r1)
	var h11: float = _corner_profile(r1)
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		_fan_point(origin, axis_u, axis_v, r0, a0, -0.08),
		_fan_point(origin, axis_u, axis_v, r0, a1, -0.08),
		_fan_point(origin, axis_u, axis_v, r1, a0, -0.08),
		_fan_point(origin, axis_u, axis_v, r1, a1, -0.08),
		_fan_point(origin, axis_u, axis_v, r0, a0, h00),
		_fan_point(origin, axis_u, axis_v, r0, a1, h01),
		_fan_point(origin, axis_u, axis_v, r1, a0, h10),
		_fan_point(origin, axis_u, axis_v, r1, a1, h11),
	])
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)


func _corner_mesh(origin: Vector3, axis_u: Vector3, axis_v: Vector3, span_u: float, span_v: float, steps_u: int, steps_v: int) -> Array:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.56, 0.36)
	mat.roughness = 0.72
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(mat)
	for iu in range(steps_u):
		for iv in range(steps_v):
			var u0: float = span_u * float(iu) / float(steps_u)
			var u1: float = span_u * float(iu + 1) / float(steps_u)
			var v0: float = span_v * float(iv) / float(steps_v)
			var v1: float = span_v * float(iv + 1) / float(steps_v)
			var p00: Vector3 = _bank_top(origin, axis_u, axis_v, u0, v0)
			var p10: Vector3 = _bank_top(origin, axis_u, axis_v, u1, v0)
			var p11: Vector3 = _bank_top(origin, axis_u, axis_v, u1, v1)
			var p01: Vector3 = _bank_top(origin, axis_u, axis_v, u0, v1)
			_corner_tri(tool, p00, p10, p11)
			_corner_tri(tool, p00, p11, p01)
	_bank_skirt(tool, origin, axis_u, axis_v, span_u, span_v, steps_u, steps_v)
	var mesh: Mesh = tool.commit()
	if mesh.get_surface_count() == 0:
		var box := BoxMesh.new()
		box.size = Vector3(span_u, 0.4, span_v)
		mesh = box
	else:
		mesh.surface_set_material(0, mat)
	return [mesh, mat]


func _bank_skirt(tool: SurfaceTool, origin: Vector3, axis_u: Vector3, axis_v: Vector3, span_u: float, span_v: float, steps_u: int, steps_v: int) -> void:
	for iu in range(steps_u):
		var u0: float = span_u * float(iu) / float(steps_u)
		var u1: float = span_u * float(iu + 1) / float(steps_u)
		_skirt_pair(tool, origin, axis_u, axis_v, u0, 0.0, u1, 0.0)
		_skirt_pair(tool, origin, axis_u, axis_v, u0, span_v, u1, span_v)
	for iv in range(steps_v):
		var v0: float = span_v * float(iv) / float(steps_v)
		var v1: float = span_v * float(iv + 1) / float(steps_v)
		_skirt_pair(tool, origin, axis_u, axis_v, 0.0, v0, 0.0, v1)
		_skirt_pair(tool, origin, axis_u, axis_v, span_u, v0, span_u, v1)


func _skirt_pair(tool: SurfaceTool, origin: Vector3, axis_u: Vector3, axis_v: Vector3, u0: float, v0: float, u1: float, v1: float) -> void:
	var top0: Vector3 = _bank_top(origin, axis_u, axis_v, u0, v0)
	var top1: Vector3 = _bank_top(origin, axis_u, axis_v, u1, v1)
	var bot0 := Vector3(top0.x, 0.0, top0.z)
	var bot1 := Vector3(top1.x, 0.0, top1.z)
	_corner_tri(tool, bot0, bot1, top1)
	_corner_tri(tool, bot0, top1, top0)


func _corner_tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var face: Vector3 = (b - a).cross(c - a)
	if face.length_squared() < 0.0000001:
		return
	# Godot treats clockwise faces as front. Flip so the top faces the camera,
	# and store an upward normal so the bank is lit instead of black.
	if face.y > 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
		face = -face
	var lit: Vector3 = (-face).normalized()
	tool.set_normal(lit)
	tool.add_vertex(a)
	tool.set_normal(lit)
	tool.add_vertex(b)
	tool.set_normal(lit)
	tool.add_vertex(c)


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


func rail_points(body: Node3D) -> PackedVector3Array:
	var id := str(body.get_meta("piece_id", ""))
	if not id.contains("rail"):
		return PackedVector3Array()
	var local := _rail_local(id)
	var out := PackedVector3Array()
	for point in local:
		out.append(body.global_transform * point)
	return out


func _rail_local(id: String) -> PackedVector3Array:
	if id.contains("curve"):
		var high := 0.24
		if id.contains("high"):
			high = 0.42
		var arc := PackedVector3Array()
		for i in range(5):
			var ang := lerpf(0.0, PI * 0.5, float(i) / 4.0)
			arc.append(Vector3(sin(ang) * 0.46, high, -cos(ang) * 0.46))
		return arc
	if id == "rail-slope":
		return PackedVector3Array([Vector3(0, 0.7, -0.46), Vector3(0, 0.08, 0.46)])
	if id == "rail-slope-smooth":
		return PackedVector3Array([Vector3(0, 0.8, -1.0), Vector3(0, 0.05, 1.0)])
	var bar := 0.24
	if id == "high-rail" or id.contains("high"):
		bar = 0.42
	elif id == "steps-rail" or id == "obstacle-middle-rail" or id == "ramp-rail":
		bar = 0.36
	return PackedVector3Array([Vector3(0, bar, -0.46), Vector3(0, bar, 0.46)])
