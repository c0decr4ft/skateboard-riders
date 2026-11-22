extends Node3D
## Home screen. Build a park on the concrete pad, then ride it.

const LayoutScript := preload("res://scripts/layout.gd")
const PiecesScript := preload("res://scripts/pieces.gd")

const GRID_MIN_X := -28
const GRID_MAX_X := 27
const GRID_MIN_Z := -23
const GRID_MAX_Z := 25
const ZOOM_NEAR := 3.5
const ZOOM_FAR := 72.0
const SPIN_SIZE := 48.0
const SPIN_STEP := 0.36
# Visible hand is HAND_ICON_H tall. The hit target stays larger than the icon.
const HAND_ICON_H := 28.0
const HAND_GRAB := 96.0
const HAND_OUTSET := 10.0
const HAND_CENTER_GAP := 18.0

var layout
var pieces
var camera: Camera3D
var piece_root: Node3D
var ghost_root: Node3D
var highlight: MeshInstance3D
var highlight_mesh: BoxMesh
var highlight_mat: StandardMaterial3D
var highlight_size := Vector3.ZERO
var occupied: Dictionary = {}
var selected_id := "quarter"
var place_rot := 0
var place_rot_by_id: Dictionary = {}
var aim_valid := false
var aim_x := 0
var aim_z := 0
var spin_ccw: Control
var spin_cw: Control
var spin_tex_ccw: Texture2D
var hand_icon: TextureRect
var hand_shadow: TextureRect
var hand_tex: Texture2D
var hand_hot := false
var hand_cursor := false
var hand_grabbing := false
var hand_frozen_x := 0
var hand_frozen_z := 0
var hand_pivot := Vector2.ZERO
var hand_grab_angle := 0.0
var hand_grab_rot := 0
var spin_dir := 0
var spin_wait := 0.0
var hover_valid := false
var hover_x := 0
var hover_z := 0
var ghost: Node3D
var ghost_key := ""
var orbit_yaw := 0.0
var orbit_pitch := 1.0
var orbit_dist := 14.0
var focus := Vector3(0, 0, 1)
var orbiting := false
var launching := false
var dragging := false
var drag_id := ""
var painting := false
var stroke_cells: Dictionary = {}
var ui_font: SystemFont
var palette_buttons: Dictionary = {}
var palette_thumbs: Dictionary = {}
var palette_labels: Dictionary = {}
var ui_blockers: Array = []
var status_label: Label
var count_label: Label
var help_root: Control
var mute_button: Button
var block_note := ""


func _ready() -> void:
	layout = LayoutScript.new()
	pieces = PiecesScript.new()
	pieces.build_environment(self)
	pieces.build_pad(self)
	piece_root = Node3D.new()
	piece_root.name = "Pieces"
	add_child(piece_root)
	ghost_root = Node3D.new()
	ghost_root.name = "Ghost"
	add_child(ghost_root)
	_build_highlight()
	_load_layout()
	_build_camera()
	_build_ui()
	_seed_aim()
	get_viewport().gui_release_focus()


func _process(delta: float) -> void:
	_spin_hold(delta)
	if hand_grabbing and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_end_hand_grab()
	hand_hot = _hand_hit(get_viewport().get_mouse_position())
	_apply_hand_cursor()
	if painting and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_end_stroke()
	if dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if not hand_grabbing:
			_hover_at(get_viewport().get_mouse_position())
		_finish_drag()
	_release_orbit()
	_pan_keyboard(delta)
	_apply_camera()
	_update_hover()
	if painting:
		_stamp_stroke()
	_update_highlight()
	_update_ghost()
	_place_spin_arrows()


func _input(event: InputEvent) -> void:
	if event.get_class() == "InputEventMagnify":
		var factor: float = float(event.get("factor"))
		var at: Vector2 = event.get("position")
		if not _pointer_over_ui(at):
			_zoom_by((1.0 - factor) * orbit_dist, at)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var wheel := event as InputEventMouseButton
		if wheel.pressed and (wheel.button_index == MOUSE_BUTTON_WHEEL_UP or wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if not _pointer_over_ui(wheel.position):
				var step: float = 2.4 * wheel.factor
				if step < 0.2:
					step = 0.2
				if wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					step = -step
				_zoom_by(-step, wheel.position)
				get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		var key: Key = key_event.keycode
		if key == KEY_R:
			_rotate_current()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_DELETE or key == KEY_BACKSPACE:
			_delete_hover()
			get_viewport().set_input_as_handled()
			return
	if _handle_hand_input(event):
		return
	if not dragging:
		return
	if event is InputEventMouseMotion:
		_hover_at(get_viewport().get_mouse_position())
		_update_highlight()
		_update_ghost()
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.pressed:
			_hover_at(get_viewport().get_mouse_position())
			_finish_drag()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed and not mouse.alt_pressed and not dragging and not painting:
			if _hand_hit(mouse.position):
				_begin_hand_grab(mouse.position)
				get_viewport().set_input_as_handled()
				return
			if not help_open() and not _pointer_over_ui(mouse.position):
				_hover_at(mouse.position)
				if hover_valid and selected_id != "":
					painting = true
					stroke_cells = {}
					orbiting = false
					_stamp_stroke()
					get_viewport().set_input_as_handled()
					return
		if not dragging and not painting and (mouse.button_index == MOUSE_BUTTON_MIDDLE or (mouse.button_index == MOUSE_BUTTON_LEFT and mouse.alt_pressed)):
			orbiting = mouse.pressed
			get_viewport().set_input_as_handled()
			return
		if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			_delete_hover()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and orbiting and not dragging and not painting:
		var motion := event as InputEventMouseMotion
		orbit_yaw -= motion.relative.x * 0.005
		orbit_pitch += motion.relative.y * 0.0035
		get_viewport().set_input_as_handled()
		return


func _release_orbit() -> void:
	if dragging or painting:
		orbiting = false
		return
	if not orbiting:
		return
	var mid := Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	var alt_drag := Input.is_key_pressed(KEY_ALT) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not mid and not alt_drag:
		orbiting = false


func _pan_keyboard(delta: float) -> void:
	if camera == null:
		return
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.z += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.z -= 1.0
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	var right: Vector3 = camera.global_basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var fwd: Vector3 = -camera.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	focus += (right * dir.x + fwd * dir.z) * 16.0 * delta
	focus.x = clampf(focus.x, float(GRID_MIN_X), float(GRID_MAX_X))
	focus.y = 0.0
	focus.z = clampf(focus.z, float(GRID_MIN_Z), float(GRID_MAX_Z))


func _zoom_by(delta: float, screen: Vector2) -> void:
	if camera == null:
		return
	var before: float = orbit_dist
	orbit_dist = clampf(orbit_dist + delta, ZOOM_NEAR, ZOOM_FAR)
	if absf(orbit_dist - before) < 0.0001:
		return
	if orbit_dist < before and before > 0.001:
		var ground: Vector3 = _ground_at_pointer(screen)
		var pull: float = clampf((before - orbit_dist) / before, 0.0, 0.55)
		focus = focus.lerp(ground, pull)
		focus.x = clampf(focus.x, float(GRID_MIN_X), float(GRID_MAX_X))
		focus.y = 0.0
		focus.z = clampf(focus.z, float(GRID_MIN_Z), float(GRID_MAX_Z))
	_apply_camera()


func _ground_at_pointer(screen: Vector2) -> Vector3:
	if camera == null:
		return focus
	var origin: Vector3 = camera.project_ray_origin(screen)
	var dir: Vector3 = camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return focus
	var t: float = -origin.y / dir.y
	if t < 0.0:
		return focus
	var hit: Vector3 = origin + dir * t
	hit.y = 0.0
	return hit


func _apply_camera() -> void:
	if camera == null:
		return
	var pitch: float = clampf(orbit_pitch, deg_to_rad(38.0), deg_to_rad(84.0))
	orbit_pitch = pitch
	var dist: float = clampf(orbit_dist, ZOOM_NEAR, ZOOM_FAR)
	orbit_dist = dist
	var horiz: float = dist * cos(pitch)
	var height: float = dist * sin(pitch)
	var pos := focus + Vector3(sin(orbit_yaw) * horiz, height, cos(orbit_yaw) * horiz)
	if pos.y < 2.0:
		pos.y = 2.0
	camera.global_position = pos
	var aim := focus + Vector3(0, 0.2, 0)
	if pos.distance_squared_to(aim) < 0.25:
		return
	camera.look_at(aim, Vector3.UP)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "BuilderCamera"
	camera.current = true
	camera.fov = 50.0
	camera.near = 0.08
	camera.far = 500.0
	add_child(camera)
	orbit_yaw = 0.0
	orbit_pitch = deg_to_rad(58.0)
	orbit_dist = 14.0
	focus = Vector3(0, 0, 1)
	_apply_camera()


func _build_highlight() -> void:
	highlight = MeshInstance3D.new()
	highlight.name = "Highlight"
	highlight_mesh = BoxMesh.new()
	highlight_mesh.size = Vector3(0.98, 0.05, 0.98)
	highlight_size = highlight_mesh.size
	highlight.mesh = highlight_mesh
	highlight_mat = StandardMaterial3D.new()
	highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight_mat.albedo_color = Color(0.95, 0.58, 0.22, 0.45)
	highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	highlight.material_override = highlight_mat
	highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	highlight.visible = false
	add_child(highlight)


func _update_hover() -> void:
	_hover_at(get_viewport().get_mouse_position())


func _hover_at(mouse: Vector2) -> void:
	if hand_grabbing:
		_lock_hand_cell()
		return
	if _hand_hit(mouse) and aim_valid:
		hover_valid = true
		hover_x = aim_x
		hover_z = aim_z
		return
	if camera == null:
		hover_valid = false
		return
	if dragging or painting:
		if _pointer_over_ui(mouse):
			hover_valid = false
			return
	else:
		var hovered: Control = get_viewport().gui_get_hovered_control()
		if hovered != null:
			return
	var origin: Vector3 = camera.project_ray_origin(mouse)
	var dir: Vector3 = camera.project_ray_normal(mouse)
	if absf(dir.y) < 0.00001:
		hover_valid = false
		return
	var t: float = -origin.y / dir.y
	if t < 0.0:
		hover_valid = false
		return
	var hit: Vector3 = origin + dir * t
	var x: int = roundi(hit.x)
	var z: int = roundi(hit.z)
	if x < GRID_MIN_X or x > GRID_MAX_X or z < GRID_MIN_Z or z > GRID_MAX_Z:
		hover_valid = false
		return
	hover_valid = true
	hover_x = x
	hover_z = z
	aim_valid = true
	aim_x = x
	aim_z = z


func _pointer_over_ui(mouse: Vector2) -> bool:
	for entry in ui_blockers:
		var control: Control = entry as Control
		if control == null or not is_instance_valid(control):
			continue
		if not control.is_visible_in_tree():
			continue
		if control.get_global_rect().has_point(mouse):
			return true
	return false


func _update_highlight() -> void:
	if highlight == null:
		return
	if not hover_valid:
		highlight.visible = false
		return
	highlight.visible = true
	var id := selected_id
	var rot := place_rot
	var placed := false
	var active := _stroke_id()
	if active != "":
		id = active
	else:
		var key := Vector2i(hover_x, hover_z)
		var node: Node = _occupied_node(key)
		if node != null:
			id = str(node.get_meta("piece_id"))
			rot = int(node.get_meta("rot"))
			placed = true
	if active != "" or not placed:
		highlight_mat.albedo_color = Color(0.95, 0.6, 0.22, 0.42)
	else:
		highlight_mat.albedo_color = Color(0.92, 0.32, 0.26, 0.55)
	_set_highlight_size(_footprint(id))
	highlight.position = Vector3(hover_x, 0.07, hover_z)
	highlight.rotation.y = deg_to_rad(float(rot))
	var span: Dictionary = {}
	if active == "quarter":
		span = _drag_corner_item()
	else:
		var held: Node = _occupied_node(Vector2i(hover_x, hover_z))
		if held != null and str(held.get_meta("piece_id")) == "corner":
			span = {
				"x": int(held.get_meta("cell_x")),
				"z": int(held.get_meta("cell_z")),
				"x2": int(held.get_meta("cell_x2")),
				"z2": int(held.get_meta("cell_z2")),
			}
	if not span.is_empty():
		var x1: int = int(span["x"])
		var z1: int = int(span["z"])
		var x2: int = int(span["x2"])
		var z2: int = int(span["z2"])
		highlight.position = Vector3(float(x1 + x2) * 0.5, 0.07, float(z1 + z2) * 0.5)
		highlight.rotation.y = 0.0
		_set_highlight_size(Vector3(float(absi(x1 - x2) + 1), 0.05, float(absi(z1 - z2) + 1)))
	highlight.position.y = _support_y(hover_x, hover_z) + 0.07


func _set_highlight_size(size: Vector3) -> void:
	if highlight_size.is_equal_approx(size):
		return
	highlight_size = size
	highlight_mesh = BoxMesh.new()
	highlight_mesh.size = size
	highlight.mesh = highlight_mesh


func _footprint(id: String) -> Vector3:
	if id == "bank":
		return Vector3(0.98, 0.05, 2.0)
	if id == "low-rail" or id == "low-rail-end" or id == "high-rail":
		return Vector3(0.28, 0.05, 0.98)
	return Vector3(0.98, 0.05, 0.98)


func _hide_ghost() -> void:
	ghost_key = ""
	if ghost != null and is_instance_valid(ghost):
		ghost.free()
	ghost = null


func _update_ghost() -> void:
	var key := ""
	var active := ""
	var show_preview := false
	var gx := aim_x
	var gz := aim_z
	if painting or dragging:
		active = _stroke_id()
		show_preview = active != "" and hover_valid
		gx = hover_x
		gz = hover_z
		if show_preview and painting and stroke_cells.has(Vector2i(gx, gz)):
			show_preview = false
	elif selected_id != "" and aim_valid:
		active = selected_id
		show_preview = true
	if show_preview and _stack_note(gx, gz) != "":
		show_preview = false
	var preview_y := 0.0
	if show_preview:
		preview_y = _stack_base(gx, gz)
		key = "%s|%d|%d|%d|%.2f" % [active, gx, gz, place_rot, preview_y]
	if key == ghost_key and (key != "" or ghost == null):
		return
	ghost_key = key
	if ghost != null and is_instance_valid(ghost):
		ghost.free()
		ghost = null
	if key == "":
		return
	ghost = pieces.make_visual(ghost_root, active, gx, gz, place_rot, preview_y) as Node3D


func _load_layout() -> void:
	var items: Array = layout.load_or_default()
	items = pieces.absorb_corners(items)
	items = pieces.keep_stacks(items)
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		if str(entry.get("id", "")) == "":
			continue
		_place_saved(entry)
	pieces.lift_rails(piece_root)


func _cell_taken(x: int, z: int) -> bool:
	return not _cell_list(Vector2i(x, z)).is_empty()


func _stack_note(x: int, z: int) -> String:
	var list: Array = _cell_list(Vector2i(x, z))
	var ranked: Array = []
	for item in list:
		var node: Node = item as Node
		if node != null:
			ranked.append(node)
	ranked.sort_custom(func(a: Node, b: Node) -> bool:
		return float(a.get_meta("stack_y", 0.0)) < float(b.get_meta("stack_y", 0.0))
	)
	var ids: Array = []
	for item in ranked:
		var node: Node = item as Node
		ids.append(str(node.get_meta("piece_id")))
	return str(pieces.stack_block(ids))


func _stack_base(x: int, z: int) -> float:
	var top: Node = _occupied_node(Vector2i(x, z))
	if top == null:
		return 0.0
	return float(top.get_meta("stack_y", 0.0)) + float(pieces.piece_height(str(top.get_meta("piece_id"))))


func _put_piece(id: String, x: int, z: int, rot: int) -> void:
	_remember_rot(id, rot)
	var note: String = _stack_note(x, z)
	if note != "":
		block_note = note
		_refresh_status()
		return
	block_note = ""
	var stack_y: float = _stack_base(x, z)
	var node: Node3D = pieces.place(piece_root, id, x, z, rot, stack_y) as Node3D
	if node == null:
		return
	_remember(node)


func _place_saved(item: Dictionary) -> void:
	var node: Node3D = pieces.place_item(piece_root, item) as Node3D
	if node == null:
		return
	_remember(node)


func _remember(node: Node) -> void:
	var cells: Array = _node_cells(node)
	for cell in cells:
		var spot: Vector2i = cell
		var list: Array = _cell_list(spot)
		list.append(node)
		occupied[spot] = list


func _merge_placed_quarters() -> void:
	var before: Array = _collect_items()
	var merged: Array = pieces.absorb_corners(before)
	if merged.size() == before.size():
		return
	_replace_all(merged)


func _replace_all(items: Array) -> void:
	_free_all_pieces()
	var ordered: Array = pieces.keep_stacks(items)
	for item in ordered:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		if str(entry.get("id", "")) == "":
			continue
		_place_saved(entry)


func _cell_list(cell: Vector2i) -> Array:
	if not occupied.has(cell):
		return []
	var raw = occupied[cell]
	var incoming: Array = []
	if raw is Array:
		incoming = raw
	elif typeof(raw) == TYPE_OBJECT and raw != null and is_instance_valid(raw):
		incoming = [raw]
	else:
		occupied.erase(cell)
		return []
	var clean: Array = []
	for item in incoming:
		if typeof(item) != TYPE_OBJECT or item == null or not is_instance_valid(item):
			continue
		var node: Node = item as Node
		if node != null:
			clean.append(node)
	if clean.is_empty():
		occupied.erase(cell)
	else:
		occupied[cell] = clean
	return clean


func _occupied_node(key: Vector2i) -> Node:
	var list: Array = _cell_list(key)
	var best: Node = null
	var best_y := -1.0
	for item in list:
		var node: Node = item as Node
		if node == null:
			continue
		var stack_y: float = float(node.get_meta("stack_y", 0.0))
		if best == null or stack_y >= best_y:
			best = node
			best_y = stack_y
	return best


func _node_cells(node: Node) -> Array:
	var cells: Array = [Vector2i(int(node.get_meta("cell_x")), int(node.get_meta("cell_z")))]
	if str(node.get_meta("piece_id")) == "corner":
		cells.append(Vector2i(int(node.get_meta("cell_x2")), int(node.get_meta("cell_z2"))))
	return cells


func _unique_nodes() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var keys: Array = occupied.keys()
	for key in keys:
		var cell: Vector2i = key
		var list: Array = _cell_list(cell)
		for item in list:
			var node: Node = item as Node
			if node == null:
				continue
			var iid: int = node.get_instance_id()
			if seen.has(iid):
				continue
			seen[iid] = true
			out.append(node)
	return out


func _support_y(x: int, z: int) -> float:
	return _top_of_cell(Vector2i(x, z), null)


func _top_of_cell(cell: Vector2i, ignore: Node) -> float:
	var best := 0.0
	var list: Array = _cell_list(cell)
	for item in list:
		var node: Node = item as Node
		if node == null or node == ignore:
			continue
		var top: float = float(node.get_meta("stack_y", 0.0))
		top += float(pieces.piece_height(str(node.get_meta("piece_id"))))
		if top > best:
			best = top
	return best


func _support_below(node: Node) -> float:
	var y: float = float(node.get_meta("stack_y", 0.0))
	var best := 0.0
	var cells: Array = _node_cells(node)
	for cell in cells:
		var spot: Vector2i = cell
		var list: Array = _cell_list(spot)
		for item in list:
			var other: Node = item as Node
			if other == null or other == node:
				continue
			var oy: float = float(other.get_meta("stack_y", 0.0))
			if oy >= y - 0.001:
				continue
			var top: float = oy + float(pieces.piece_height(str(other.get_meta("piece_id"))))
			if top > best:
				best = top
	return best


func _apply_height(node: Node, y: float) -> void:
	node.set_meta("stack_y", y)
	var id: String = str(node.get_meta("piece_id"))
	if id == "corner":
		node.position = Vector3(0.0, y, 0.0)
	elif id == "start":
		node.position.y = y - 0.025
	else:
		node.position.y = y


func _settle_stacks() -> void:
	var nodes: Array = _unique_nodes()
	nodes.sort_custom(func(a: Node, b: Node) -> bool:
		return float(a.get_meta("stack_y", 0.0)) < float(b.get_meta("stack_y", 0.0))
	)
	for item in nodes:
		var node: Node = item as Node
		if node == null or not is_instance_valid(node):
			continue
		var y: float = float(node.get_meta("stack_y", 0.0))
		var support: float = _support_below(node)
		if y > support + 0.02:
			_apply_height(node, support)


func _collect_items() -> Array:
	var items: Array = []
	var nodes: Array = _unique_nodes()
	for item in nodes:
		var node: Node = item as Node
		if node == null:
			continue
		var entry: Dictionary = {
			"id": str(node.get_meta("piece_id")),
			"x": int(node.get_meta("cell_x")),
			"z": int(node.get_meta("cell_z")),
			"rot": int(node.get_meta("rot")),
			"y": float(node.get_meta("stack_y", 0.0)),
		}
		if str(entry["id"]) == "corner":
			entry["x2"] = int(node.get_meta("cell_x2"))
			entry["z2"] = int(node.get_meta("cell_z2"))
			entry["rot2"] = int(node.get_meta("rot2"))
		items.append(entry)
	return items


func _erase_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		_drop_stale()
		return
	var iid: int = node.get_instance_id()
	var keys: Array = occupied.keys()
	for key in keys:
		var cell: Vector2i = key
		var list: Array = _cell_list(cell)
		var kept: Array = []
		for item in list:
			if typeof(item) != TYPE_OBJECT or item == null or not is_instance_valid(item):
				continue
			var other: Node = item as Node
			if other == null or other.get_instance_id() == iid:
				continue
			kept.append(other)
		if kept.is_empty():
			occupied.erase(cell)
		else:
			occupied[cell] = kept
	if is_instance_valid(node):
		node.free()


func _drop_stale() -> void:
	var keys: Array = occupied.keys()
	for key in keys:
		var cell: Vector2i = key
		_cell_list(cell)


func _free_all_pieces() -> void:
	var pending: Array = _unique_nodes()
	occupied.clear()
	for item in pending:
		var node: Node = item as Node
		if node != null and is_instance_valid(node):
			node.free()


func _piece_count() -> int:
	return _unique_nodes().size()


func _drag_corner_item() -> Dictionary:
	if _stroke_id() != "quarter" or not hover_valid:
		return {}
	var here: Dictionary = {
		"id": "quarter",
		"x": hover_x,
		"z": hover_z,
		"rot": place_rot,
		"y": 0.0,
	}
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for dir in dirs:
		var key := Vector2i(hover_x, hover_z) + dir
		var node: Node = _occupied_node(key)
		if node == null or str(node.get_meta("piece_id")) != "quarter":
			continue
		var other: Dictionary = {
			"id": "quarter",
			"x": int(node.get_meta("cell_x")),
			"z": int(node.get_meta("cell_z")),
			"rot": int(node.get_meta("rot")),
			"y": float(node.get_meta("stack_y", 0.0)),
		}
		if pieces.quarter_pair(here, other):
			return pieces.corner_from(here, other)
	return {}


func _remove_cell(x: int, z: int) -> void:
	var node: Node = _occupied_node(Vector2i(x, z))
	if node == null:
		return
	_erase_node(node)
	_settle_stacks()


func _stroke_id() -> String:
	if dragging and drag_id != "":
		return drag_id
	if painting and selected_id != "":
		return selected_id
	return ""


func _stamp_stroke() -> void:
	if not painting or not hover_valid or selected_id == "":
		return
	var key := Vector2i(hover_x, hover_z)
	if stroke_cells.has(key):
		return
	stroke_cells[key] = true
	var note: String = _stack_note(hover_x, hover_z)
	if note != "":
		block_note = note
		_refresh_status()
		return
	_put_piece(selected_id, hover_x, hover_z, place_rot)
	_save()
	_hide_ghost()
	_refresh_status()


func _end_stroke() -> void:
	painting = false
	stroke_cells = {}
	_hide_ghost()
	_refresh_status()


func _begin_drag(id: String) -> void:
	if help_open():
		return
	dragging = true
	drag_id = id
	ghost_key = ""
	_select(id)


func _finish_drag() -> void:
	var id: String = drag_id
	var drop_x: int = hover_x
	var drop_z: int = hover_z
	var drop: bool = hover_valid and id != ""
	dragging = false
	drag_id = ""
	_hide_ghost()
	if not drop:
		_refresh_status()
		return
	_put_piece(id, drop_x, drop_z, place_rot)
	_save()
	_hide_ghost()
	_refresh_status()


func _delete_hover() -> void:
	if not hover_valid:
		return
	if not occupied.has(Vector2i(hover_x, hover_z)):
		return
	_remove_cell(hover_x, hover_z)
	ghost_key = ""
	_save()
	_refresh_status()


func _rotate_current() -> void:
	var placed: Node = null
	if not dragging and not painting and hover_valid:
		placed = _occupied_node(Vector2i(hover_x, hover_z))
	if placed != null and is_instance_valid(placed):
		_turn_placed(placed)
		_save()
		ghost_key = ""
		_refresh_status()
		return
	_snap_turn(1)


func _turn_placed(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var rot: int = posmod(int(node.get_meta("rot")) + 90, 360)
	node.set_meta("rot", rot)
	if node is Node3D:
		(node as Node3D).rotation.y = deg_to_rad(float(rot))
	_remember_rot(str(node.get_meta("piece_id")), rot)


func _clear_pieces() -> void:
	_free_all_pieces()
	ghost_key = ""
	_save()
	_refresh_status()


func _save() -> void:
	var items: Array = _collect_items()
	layout.save_items(items)


func _play() -> void:
	if launching:
		return
	_save()
	_go_ride()


func _go_ride() -> void:
	if launching:
		return
	launching = true
	get_tree().call_deferred("change_scene_to_file", "res://scenes/park.tscn")


func help_open() -> bool:
	return help_root != null and help_root.visible


func _toggle_help() -> void:
	if help_root == null:
		return
	help_root.visible = not help_root.visible
	if help_root.visible:
		painting = false
		dragging = false
		orbiting = false
		_end_hand_grab()
		_end_stroke()


func _seed_aim() -> void:
	var cx := clampi(roundi(focus.x), GRID_MIN_X, GRID_MAX_X)
	var cz := clampi(roundi(focus.z), GRID_MIN_Z, GRID_MAX_Z)
	if _stack_note(cx, cz) == "":
		aim_x = cx
		aim_z = cz
		aim_valid = true
		return
	for radius in range(1, 10):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dz) != radius:
					continue
				var x: int = cx + dx
				var z: int = cz + dz
				if x < GRID_MIN_X or x > GRID_MAX_X or z < GRID_MIN_Z or z > GRID_MAX_Z:
					continue
				if _stack_note(x, z) == "":
					aim_x = x
					aim_z = z
					aim_valid = true
					return
	aim_x = cx
	aim_z = cz
	aim_valid = true


func _rot_for(id: String) -> int:
	if id == "":
		return 0
	return posmod(int(place_rot_by_id.get(id, 0)), 360)


func _remember_rot(id: String, rot: int) -> void:
	if id == "":
		return
	var snapped := posmod(rot, 360)
	place_rot_by_id[id] = snapped
	if id == selected_id or (dragging and id == drag_id):
		place_rot = snapped


func _active_piece_id() -> String:
	if dragging and drag_id != "":
		return drag_id
	return selected_id


func _snap_turn(dir: int) -> void:
	var id := _active_piece_id()
	if id == "":
		return
	var next := posmod(_rot_for(id) + dir * 90, 360)
	_remember_rot(id, next)
	ghost_key = ""
	_refresh_status()


func _spin_down(dir: int) -> void:
	spin_dir = dir
	spin_wait = SPIN_STEP
	_snap_turn(dir)


func _spin_up() -> void:
	spin_dir = 0


func _spin_hold(delta: float) -> void:
	if spin_dir == 0:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		spin_dir = 0
		return
	spin_wait -= delta
	if spin_wait > 0.0:
		return
	spin_wait = SPIN_STEP
	_snap_turn(spin_dir)


func _on_spin_gui(event: InputEvent, dir: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse.pressed:
		_spin_down(dir)
	else:
		_spin_up()
	get_viewport().set_input_as_handled()


func _build_spin_arrows() -> void:
	spin_tex_ccw = _spin_texture(false)
	hand_tex = ImageTexture.create_from_image(_load_hand_image())
	var layer := CanvasLayer.new()
	layer.name = "SpinArrows"
	layer.layer = 30
	add_child(layer)
	var holder := Control.new()
	holder.name = "SpinRoot"
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(holder)
	spin_cw = _make_turn_hand()
	holder.add_child(spin_cw)


func _make_spin_arrow(clockwise: bool, dir: int) -> TextureRect:
	var node := TextureRect.new()
	node.name = "SpinCW" if clockwise else "SpinCCW"
	node.texture = spin_tex_ccw
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	node.focus_mode = Control.FOCUS_NONE
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.custom_minimum_size = Vector2(SPIN_SIZE, SPIN_SIZE)
	node.size = Vector2(SPIN_SIZE, SPIN_SIZE)
	node.visible = false
	node.z_index = 20
	node.modulate = Color.WHITE
	node.gui_input.connect(_on_spin_gui.bind(dir))
	node.mouse_entered.connect(_spin_hover.bind(node, true))
	node.mouse_exited.connect(_spin_hover.bind(node, false))
	return node


func _spin_hover(node: CanvasItem, on: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.modulate = Color(1.15, 1.12, 1.05) if on else Color.WHITE


func _place_spin_arrows() -> void:
	if spin_cw == null:
		return
	var show := ghost != null and is_instance_valid(ghost) and camera != null
	if show and camera.is_position_behind(ghost.global_position):
		show = false
	if show and help_open():
		show = false
	spin_cw.visible = show
	if not show:
		return
	var rect := _ghost_screen_rect()
	if rect.size.x < 8.0 and rect.size.y < 8.0:
		var origin := camera.unproject_position(ghost.global_position + Vector3(0, 0.35, 0))
		rect = Rect2(origin - Vector2(36, 36), Vector2(72, 72))
	_move_hand(_hand_anchor(rect))
	_spin_hand_visual()
	_tint_hand()


func _move_spin(node: Control, center: Vector2) -> void:
	var s := SPIN_SIZE
	var vp := get_viewport().get_visible_rect().size
	var pos := center - Vector2(s, s) * 0.5
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vp.x - s - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, vp.y - s - 8.0))
	node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	node.offset_left = pos.x
	node.offset_top = pos.y
	node.offset_right = pos.x + s
	node.offset_bottom = pos.y + s


func _make_turn_hand() -> Control:
	var grab := Control.new()
	grab.name = "SpinCW"
	grab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grab.focus_mode = Control.FOCUS_NONE
	grab.visible = false
	grab.z_index = 21
	grab.custom_minimum_size = Vector2(HAND_GRAB, HAND_GRAB)
	grab.size = Vector2(HAND_GRAB, HAND_GRAB)
	hand_shadow = TextureRect.new()
	hand_shadow.name = "HandShadow"
	hand_shadow.texture = hand_tex
	hand_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hand_shadow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hand_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_shadow.modulate = Color(0.05, 0.04, 0.04, 0.45)
	grab.add_child(hand_shadow)
	hand_icon = TextureRect.new()
	hand_icon.name = "HandIcon"
	hand_icon.texture = hand_tex
	hand_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hand_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hand_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_icon.modulate = Color(1, 0.98, 0.93)
	grab.add_child(hand_icon)
	_layout_hand_icon()
	return grab


func _layout_hand_icon() -> void:
	if hand_icon == null:
		return
	var aspect := 0.68
	if hand_tex != null and hand_tex.get_height() > 0:
		aspect = hand_tex.get_width() / float(hand_tex.get_height())
	var icon_size := Vector2(HAND_ICON_H * aspect, HAND_ICON_H)
	hand_icon.position = (Vector2(HAND_GRAB, HAND_GRAB) - icon_size) * 0.5
	hand_icon.size = icon_size
	hand_icon.custom_minimum_size = icon_size
	if hand_shadow == null:
		return
	var shadow_size := icon_size + Vector2(6, 6)
	hand_shadow.position = (Vector2(HAND_GRAB, HAND_GRAB) - shadow_size) * 0.5 + Vector2(1.0, 1.5)
	hand_shadow.size = shadow_size
	hand_shadow.custom_minimum_size = shadow_size


func _hand_anchor(rect: Rect2) -> Vector2:
	var center := rect.get_center()
	var corner := rect.end + Vector2(HAND_OUTSET, HAND_OUTSET)
	var min_dist := HAND_GRAB * 0.5 + HAND_CENTER_GAP
	if center.distance_to(corner) < min_dist:
		var away := corner - center
		if away.length_squared() < 9.0:
			away = Vector2(1, 1)
		corner = center + away.normalized() * min_dist
	return corner


func _move_hand(center: Vector2) -> void:
	if spin_cw == null:
		return
	var s := HAND_GRAB
	var vp := get_viewport().get_visible_rect().size
	var pos := center - Vector2(s, s) * 0.5
	if vp.x > s + 16.0:
		pos.x = clampf(pos.x, 8.0, vp.x - s - 8.0)
	if vp.y > s + 16.0:
		pos.y = clampf(pos.y, 8.0, vp.y - s - 8.0)
	spin_cw.set_anchors_preset(Control.PRESET_TOP_LEFT)
	spin_cw.offset_left = pos.x
	spin_cw.offset_top = pos.y
	spin_cw.offset_right = pos.x + s
	spin_cw.offset_bottom = pos.y + s
	spin_cw.size = Vector2(s, s)


func _hand_center() -> Vector2:
	if spin_cw == null:
		return Vector2.ZERO
	return spin_cw.get_global_rect().get_center()


func _hand_hit(mouse: Vector2) -> bool:
	if help_open() or spin_cw == null or not spin_cw.visible:
		return false
	if _pointer_over_ui(mouse):
		return false
	var reach := HAND_GRAB * 0.5
	if hand_hot or hand_grabbing:
		reach += 16.0
	return mouse.distance_to(_hand_center()) <= reach


func _spin_hand_visual() -> void:
	if hand_icon == null:
		return
	var angle := 0.0
	if hand_grabbing:
		var rel := get_viewport().get_mouse_position() - hand_pivot
		if rel.length_squared() > 36.0:
			angle = angle_difference(hand_grab_angle, rel.angle())
	hand_icon.pivot_offset = hand_icon.size * 0.5
	hand_icon.rotation = angle
	if hand_shadow != null:
		hand_shadow.pivot_offset = hand_shadow.size * 0.5
		hand_shadow.rotation = angle


func _tint_hand() -> void:
	if hand_icon == null:
		return
	var hot := hand_grabbing or hand_hot
	hand_icon.modulate = Color(1.12, 1.08, 0.98) if hot else Color(1, 0.98, 0.93)


func _apply_hand_cursor() -> void:
	var want := hand_hot or hand_grabbing
	if want == hand_cursor:
		return
	hand_cursor = want
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if want else Input.CURSOR_ARROW)


func _handle_hand_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT or mouse.alt_pressed:
			return false
		if mouse.pressed and _hand_hit(mouse.position):
			_begin_hand_grab(mouse.position)
			get_viewport().set_input_as_handled()
			return true
		if not mouse.pressed and hand_grabbing:
			_end_hand_grab()
			get_viewport().set_input_as_handled()
			return true
		return false
	if event is InputEventMouseMotion and hand_grabbing:
		_drag_hand((event as InputEventMouseMotion).position)
		_update_highlight()
		_update_ghost()
		_place_spin_arrows()
		get_viewport().set_input_as_handled()
		return true
	return false


func _begin_hand_grab(mouse: Vector2) -> void:
	if hand_grabbing or help_open() or not aim_valid:
		return
	hand_grabbing = true
	hand_frozen_x = aim_x
	hand_frozen_z = aim_z
	painting = false
	stroke_cells = {}
	dragging = false
	drag_id = ""
	orbiting = false
	_lock_hand_cell()
	hand_pivot = _piece_screen_center()
	var rel := mouse - hand_pivot
	if rel.length_squared() < 36.0:
		rel = _hand_center() - hand_pivot
	if rel.length_squared() < 1.0:
		rel = Vector2(1, 1)
	hand_grab_angle = rel.angle()
	hand_grab_rot = posmod(place_rot, 360)


func _drag_hand(mouse: Vector2) -> void:
	_lock_hand_cell()
	var rel := mouse - hand_pivot
	if rel.length_squared() < 36.0:
		return
	var delta := rad_to_deg(angle_difference(hand_grab_angle, rel.angle()))
	# Screen +angle is clockwise. Piece yaw +90 is counter-clockwise from above.
	var steps := int(round((float(hand_grab_rot) - delta) / 90.0))
	var snapped_rot := posmod(steps * 90, 360)
	if snapped_rot == posmod(place_rot, 360):
		return
	_remember_rot(_active_piece_id(), snapped_rot)
	ghost_key = ""
	_refresh_status()


func _end_hand_grab() -> void:
	hand_grabbing = false


func _lock_hand_cell() -> void:
	hover_valid = true
	hover_x = hand_frozen_x
	hover_z = hand_frozen_z
	aim_valid = true
	aim_x = hand_frozen_x
	aim_z = hand_frozen_z


func _piece_screen_center() -> Vector2:
	if ghost != null and is_instance_valid(ghost) and camera != null and not camera.is_position_behind(ghost.global_position):
		return camera.unproject_position(ghost.global_position)
	return _hand_center()


func _load_hand_image() -> Image:
	var img := Image.new()
	var path := ProjectSettings.globalize_path("res://assets/ui/turn_hand_src.png")
	if img.load(path) != OK or img.is_empty():
		return _draw_hand_image()
	img.convert(Image.FORMAT_RGBA8)
	var bounds := _ink_bounds(img)
	if bounds.size.x < 4 or bounds.size.y < 4:
		return _draw_hand_image()
	var cropped := img.get_region(bounds)
	var side := maxi(cropped.get_width(), cropped.get_height())
	if side > 180:
		var scale := 180.0 / float(side)
		cropped.resize(maxi(1, int(round(cropped.get_width() * scale))), maxi(1, int(round(cropped.get_height() * scale))), Image.INTERPOLATE_LANCZOS)
	var keyed := Image.create(cropped.get_width(), cropped.get_height(), false, Image.FORMAT_RGBA8)
	for y in cropped.get_height():
		for x in cropped.get_width():
			var c := cropped.get_pixel(x, y)
			var lum := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			var ink := clampf((0.86 - lum) / 0.55, 0.0, 1.0) * c.a
			if ink < 0.05:
				keyed.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				keyed.set_pixel(x, y, Color(1, 1, 1, ink))
	return keyed


func _ink_bounds(img: Image) -> Rect2i:
	var min_x := img.get_width()
	var min_y := img.get_height()
	var max_x := -1
	var max_y := -1
	var y := 0
	while y < img.get_height():
		var x := 0
		while x < img.get_width():
			var c := img.get_pixel(x, y)
			var lum := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			if lum < 0.78 and c.a > 0.2:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
			x += 2
		y += 2
	if max_x < 0:
		return Rect2i()
	var pad := 3
	min_x = maxi(0, min_x - pad)
	min_y = maxi(0, min_y - pad)
	max_x = mini(img.get_width() - 1, max_x + pad)
	max_y = mini(img.get_height() - 1, max_y + pad)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _draw_hand_image() -> Image:
	var img := Image.create(96, 140, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_stroke_capsule(img, Vector2(48, 18), Vector2(48, 62), 9.0, Color(1, 1, 1, 1))
	_stroke_capsule(img, Vector2(34, 58), Vector2(70, 64), 8.0, Color(1, 1, 1, 1))
	_fill_disc(img, Vector2(30, 62), 11.0, Color(1, 1, 1, 1))
	_fill_disc(img, Vector2(46, 66), 11.0, Color(1, 1, 1, 1))
	_fill_disc(img, Vector2(62, 74), 11.0, Color(1, 1, 1, 1))
	_stroke_capsule(img, Vector2(40, 78), Vector2(52, 118), 22.0, Color(1, 1, 1, 1))
	_stroke_capsule(img, Vector2(22, 96), Vector2(18, 118), 9.0, Color(1, 1, 1, 1))
	return img


func _stroke_capsule(img: Image, a: Vector2, b: Vector2, radius: float, color: Color) -> void:
	var span := b - a
	var steps := maxi(int(span.length() / 2.0), 1)
	for i in steps + 1:
		var t := float(i) / float(steps)
		_fill_disc(img, a.lerp(b, t), radius, color)


func _ghost_screen_rect() -> Rect2:
	if ghost == null or camera == null:
		return Rect2()
	var local := _ghost_local_aabb()
	var xf := ghost.global_transform
	var min_p := Vector2(1.0e9, 1.0e9)
	var max_p := Vector2(-1.0e9, -1.0e9)
	var any := false
	var origin := local.position
	var size := local.size
	for i in 8:
		var corner := origin + Vector3(
			size.x if (i & 1) != 0 else 0.0,
			size.y if (i & 2) != 0 else 0.0,
			size.z if (i & 4) != 0 else 0.0
		)
		var world: Vector3 = xf * corner
		if camera.is_position_behind(world):
			continue
		var screen := camera.unproject_position(world)
		min_p.x = minf(min_p.x, screen.x)
		min_p.y = minf(min_p.y, screen.y)
		max_p.x = maxf(max_p.x, screen.x)
		max_p.y = maxf(max_p.y, screen.y)
		any = true
	if not any:
		return Rect2()
	return Rect2(min_p, max_p - min_p)


func _ghost_local_aabb() -> AABB:
	var acc: Array = []
	_collect_visual_aabb(ghost, Transform3D.IDENTITY, acc)
	if acc.is_empty():
		return AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 0.5, 1.0))
	return acc[0] as AABB


func _collect_visual_aabb(node: Node, parent_xf: Transform3D, acc: Array) -> void:
	var here := parent_xf
	if node != ghost and node is Node3D:
		here = parent_xf * (node as Node3D).transform
	if node is VisualInstance3D:
		var local_box: AABB = (node as VisualInstance3D).get_aabb()
		var world_box: AABB = here * local_box
		if acc.is_empty():
			acc.append(world_box)
		else:
			acc[0] = (acc[0] as AABB).merge(world_box)
	for child in node.get_children():
		_collect_visual_aabb(child, here, acc)


func _spin_texture(clockwise: bool) -> Texture2D:
	var n := 72
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(float(n - 1) * 0.5, float(n - 1) * 0.5)
	_fill_disc(img, c, 33.0, Color(0.07, 0.08, 0.11, 0.96))
	_stroke_ring(img, c, 31.0, 2.2, Color(1, 1, 1, 0.35))
	var start := 2.4
	var sweep := 3.6
	if not clockwise:
		start = 0.7
		sweep = -3.6
	var steps := 40
	var pts: Array[Vector2] = []
	for i in steps + 1:
		var a := start + sweep * float(i) / float(steps)
		pts.append(c + Vector2(cos(a), sin(a)) * 16.5)
	for i in range(pts.size() - 1):
		_fill_disc(img, pts[i], 2.7, Color(0.99, 0.97, 0.94, 1))
	var tip: Vector2 = pts[pts.size() - 1]
	var prev: Vector2 = pts[pts.size() - 3]
	var dir := tip - prev
	if dir.length_squared() < 0.01:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var side := Vector2(-dir.y, dir.x)
	_fill_tri(img, tip + dir * 9.0, tip - dir * 1.5 + side * 6.2, tip - dir * 1.5 - side * 6.2, Color(1.0, 0.48, 0.14, 1))
	return ImageTexture.create_from_image(img)


func _fill_disc(img: Image, center: Vector2, radius: float, color: Color) -> void:
	var r2 := radius * radius
	var min_x := maxi(0, int(floor(center.x - radius)))
	var max_x := mini(img.get_width() - 1, int(ceil(center.x + radius)))
	var min_y := maxi(0, int(floor(center.y - radius)))
	var max_y := mini(img.get_height() - 1, int(ceil(center.y + radius)))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var d := Vector2(float(x) + 0.5, float(y) + 0.5) - center
			if d.length_squared() <= r2:
				img.set_pixel(x, y, color)


func _stroke_ring(img: Image, center: Vector2, radius: float, width: float, color: Color) -> void:
	var outer := radius + width * 0.5
	var inner := maxf(radius - width * 0.5, 0.0)
	var outer2 := outer * outer
	var inner2 := inner * inner
	var min_x := maxi(0, int(floor(center.x - outer)))
	var max_x := mini(img.get_width() - 1, int(ceil(center.x + outer)))
	var min_y := maxi(0, int(floor(center.y - outer)))
	var max_y := mini(img.get_height() - 1, int(ceil(center.y + outer)))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var d2 := (Vector2(float(x) + 0.5, float(y) + 0.5) - center).length_squared()
			if d2 <= outer2 and d2 >= inner2:
				img.set_pixel(x, y, color)


func _fill_tri(img: Image, a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	var min_x := maxi(0, int(floor(minf(a.x, minf(b.x, c.x)))))
	var max_x := mini(img.get_width() - 1, int(ceil(maxf(a.x, maxf(b.x, c.x)))))
	var min_y := maxi(0, int(floor(minf(a.y, minf(b.y, c.y)))))
	var max_y := mini(img.get_height() - 1, int(ceil(maxf(a.y, maxf(b.y, c.y)))))
	var area := _cross2(b - a, c - a)
	if absf(area) < 0.001:
		return
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var w0 := _cross2(b - a, p - a)
			var w1 := _cross2(c - b, p - b)
			var w2 := _cross2(a - c, p - c)
			if w0 * area >= 0.0 and w1 * area >= 0.0 and w2 * area >= 0.0:
				img.set_pixel(x, y, color)


func _cross2(u: Vector2, v: Vector2) -> float:
	return u.x * v.y - u.y * v.x


func _tool_button(label: String, action: Callable, play: bool) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(action)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 46 if play else 40)
	if play:
		_paint(button, Color(0.90, 0.40, 0.16), Color(0.98, 0.52, 0.26), 18)
	else:
		_style_choice(button, false)
	ui_blockers.append(button)
	return button


func _select(id: String) -> void:
	selected_id = id
	place_rot = _rot_for(id)
	ghost_key = ""
	for key in palette_buttons.keys():
		var row: Panel = palette_buttons[key] as Panel
		if row == null:
			continue
		_style_row(row, str(key) == id)
	_refresh_status()


func _refresh_status() -> void:
	if status_label == null:
		return
	var line := "%s    %d°" % [_piece_label(selected_id), place_rot]
	if block_note != "":
		line += "    " + block_note
	status_label.text = line
	if count_label != null:
		count_label.text = "%d pieces" % _piece_count()


func _piece_label(id: String) -> String:
	return str(pieces.piece_name(id))


func _build_ui() -> void:
	ui_font = SystemFont.new()
	ui_font.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Arial"])
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var side := ColorRect.new()
	side.color = Color(0.07, 0.08, 0.11, 0.94)
	side.mouse_filter = Control.MOUSE_FILTER_STOP
	side.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	side.offset_right = 280
	root.add_child(side)
	ui_blockers.append(side)

	var title := _label("Skateboard Riders", 22, Color(0.97, 0.98, 0.99))
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.offset_left = 16
	title.offset_top = 10
	title.offset_right = 268
	title.offset_bottom = 48
	root.add_child(title)

	var sub := _label("Click a part, then drag across the map.", 14, Color(0.76, 0.79, 0.84))
	sub.set_anchors_preset(Control.PRESET_TOP_LEFT)
	sub.offset_left = 16
	sub.offset_top = 46
	sub.offset_right = 268
	sub.offset_bottom = 70
	root.add_child(sub)

	var best := _read_best()
	if best > 0:
		var best_label := _label("Best  %s" % _comma(best), 14, Color(0.97, 0.97, 0.98))
		best_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		best_label.offset_left = 16
		best_label.offset_top = 70
		best_label.offset_right = 268
		best_label.offset_bottom = 92
		root.add_child(best_label)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_TOP_LEFT)
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 8
	scroll.offset_top = 96
	scroll.offset_right = 272
	scroll.offset_bottom = -196
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.focus_mode = Control.FOCUS_NONE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var catalog: Array = pieces.catalog()
	for entry in catalog:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = entry
		_add_part(list, str(spec["id"]), str(spec["name"]))

	var footer := PanelContainer.new()
	footer.name = "BuilderFooter"
	footer.mouse_filter = Control.MOUSE_FILTER_STOP
	footer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	footer.offset_left = 0
	footer.offset_top = -188
	footer.offset_right = 280
	footer.offset_bottom = 0
	var footer_box := StyleBoxFlat.new()
	footer_box.bg_color = Color(0.06, 0.07, 0.09, 0.98)
	footer_box.border_color = Color(1, 1, 1, 0.1)
	footer_box.border_width_top = 1
	footer_box.content_margin_left = 12
	footer_box.content_margin_right = 12
	footer_box.content_margin_top = 12
	footer_box.content_margin_bottom = 12
	footer.add_theme_stylebox_override("panel", footer_box)
	root.add_child(footer)
	var footer_col := VBoxContainer.new()
	footer_col.add_theme_constant_override("separation", 8)
	footer_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_col)

	status_label = _label("", 18, Color(0.98, 0.98, 0.99))
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_col.add_child(status_label)
	count_label = _label("", 13, Color(0.72, 0.75, 0.8))
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_col.add_child(count_label)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(_tool_button("Controls", _toggle_help, false))
	tools.add_child(_tool_button("Clear", _clear_pieces, false))
	footer_col.add_child(tools)
	footer_col.add_child(_tool_button("Play", _play, true))
	_build_help(root)

	_build_spin_arrows()
	_build_mute_button()
	_select(selected_id)


func _build_mute_button() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MuteLayer"
	layer.layer = 40
	add_child(layer)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(holder)
	mute_button = Button.new()
	mute_button.name = "MuteButton"
	mute_button.focus_mode = Control.FOCUS_NONE
	mute_button.mouse_filter = Control.MOUSE_FILTER_STOP
	mute_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mute_button.offset_left = -156
	mute_button.offset_top = 16
	mute_button.offset_right = -16
	mute_button.offset_bottom = 56
	mute_button.pressed.connect(_toggle_mute)
	holder.add_child(mute_button)
	ui_blockers.append(mute_button)
	_sync_mute_button()


func _toggle_mute() -> void:
	Music.toggle_mute()
	_sync_mute_button()


func _sync_mute_button() -> void:
	if mute_button == null:
		return
	mute_button.text = Music.mute_label()
	_style_choice(mute_button, Music.muted)


func _build_help(parent: Control) -> void:
	help_root = Control.new()
	help_root.name = "HowToPlay"
	help_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	help_root.mouse_filter = Control.MOUSE_FILTER_STOP
	help_root.visible = false
	parent.add_child(help_root)
	ui_blockers.append(help_root)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.08, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	help_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -430
	panel.offset_top = -280
	panel.offset_right = 430
	panel.offset_bottom = 280
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.09, 0.12, 0.98)
	box.border_color = Color(1, 1, 1, 0.12)
	box.set_border_width_all(1)
	box.set_corner_radius_all(16)
	box.content_margin_left = 22
	box.content_margin_right = 22
	box.content_margin_top = 18
	box.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", box)
	help_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var heading := _label("How to Play", 28, Color(0.98, 0.98, 0.99))
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	var close := _tool_button("Close", _toggle_help, false)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.custom_minimum_size = Vector2(110, 40)
	head.add_child(close)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(columns)
	columns.add_child(_help_column("Controls", "res://assets/guide/ride.png", "W push    S brake\nA left    D right\nHold Space, release to ollie\nJump, then hold Shift to slide\nIn the air: A D spin\nQ kickflip    E heelflip\nS shove-it\nEsc builder    R restart"))
	columns.add_child(_help_column("Building", "res://assets/guide/build.png", "Click a part, then drag on the pad to stamp it.\nGrab the hand on the bottom-right corner and drag to turn that piece. It stays on its tile. R turns it too.\nRight click or Backspace deletes.\nClear wipes the park.\nScroll zooms. Arrow keys pan.\nStack only on concrete, 4 high.\nPlay rides the park you saved."))
	columns.add_child(_help_column("Riding", "res://assets/guide/slide.png", "Push to speed, carve, then ollie.\nJump onto a rail to grind. Space pops off early.\nTo slide, ollie and hold Shift while you are lined up with a concrete box edge or a ramp lip.\nYou can slide the top edge and off the corner.\nRelease Shift, or miss the edge, and the slide ends.\nRolling into an edge does not slide."))


func _help_column(title: String, image_path: String, body: String) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	var name_label := _label(title, 18, Color(0.98, 0.72, 0.42))
	col.add_child(name_label)
	var shot := TextureRect.new()
	shot.custom_minimum_size = Vector2(0, 132)
	shot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = load(image_path) as Texture2D
	if tex != null:
		shot.texture = tex
	col.add_child(shot)
	var copy := _label(body, 14, Color(0.86, 0.88, 0.92))
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(copy)
	return col


func _add_part(root: Control, id: String, label: String) -> void:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0, 52)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.set_meta("piece_id", id)
	row.gui_input.connect(_on_part_gui.bind(id))
	root.add_child(row)
	palette_buttons[id] = row
	var thumb := _thumb(id)
	thumb.set_anchors_preset(Control.PRESET_TOP_LEFT)
	thumb.offset_left = 6
	thumb.offset_top = 6
	thumb.offset_right = 46
	thumb.offset_bottom = 46
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(thumb)
	palette_thumbs[id] = thumb
	var name_label := _label(label, 15, Color(0.94, 0.95, 0.97))
	name_label.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	name_label.offset_left = 54
	name_label.offset_right = -8
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	palette_labels[id] = name_label


func _on_part_gui(event: InputEvent, id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
		return
	_begin_drag(id)
	get_viewport().set_input_as_handled()


func _thumb(id: String) -> SubViewportContainer:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 512)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.handle_input_locally = false
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	box.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, 36, 0)
	light.light_energy = 1.3
	world.add_child(light)
	pieces.make_icon(world, id)
	var cam := Camera3D.new()
	cam.fov = 28.0
	world.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(1.35, 1.15, 1.45), Vector3(0, 0.2, 0), Vector3.UP)
	return box


func _style_row(row: Panel, selected: bool) -> void:
	var box := StyleBoxFlat.new()
	var h := 78.0 if selected else 52.0
	row.custom_minimum_size = Vector2(0, h)
	if selected:
		box.bg_color = Color(0.90, 0.40, 0.16, 1)
		box.border_color = Color(1.0, 0.82, 0.62, 1)
		box.set_border_width_all(2)
	else:
		box.bg_color = Color(0.15, 0.16, 0.20, 1)
		box.border_color = Color(1, 1, 1, 0.07)
		box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	row.add_theme_stylebox_override("panel", box)
	var id := str(row.get_meta("piece_id", ""))
	var thumb: Control = palette_thumbs.get(id) as Control
	var name_label: Label = palette_labels.get(id) as Label
	if thumb != null:
		if selected:
			thumb.offset_left = 8
			thumb.offset_top = 8
			thumb.offset_right = 70
			thumb.offset_bottom = 70
		else:
			thumb.offset_left = 6
			thumb.offset_top = 6
			thumb.offset_right = 46
			thumb.offset_bottom = 46
	if name_label != null:
		name_label.add_theme_font_size_override("font_size", 20 if selected else 15)
		name_label.offset_left = 80 if selected else 54


func _add_side_button(root: Control, label: String, x: float, top: float, action: Callable, play: bool) -> void:
	var button := Button.new()
	button.text = label
	button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	button.offset_left = x
	button.offset_top = top
	button.offset_right = x + 124.0
	button.offset_bottom = top + 40.0
	button.pressed.connect(action)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.z_index = 10
	if play:
		_paint(button, Color(0.90, 0.38, 0.16), Color(0.98, 0.50, 0.24), 18)
	else:
		_style_choice(button, false)
	root.add_child(button)


func _add_tool(root: Control, label: String, x: float, action: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	button.offset_left = x
	button.offset_top = -116
	button.offset_right = x + 112.0
	button.offset_bottom = -68
	button.pressed.connect(action)
	_style_choice(button, false)
	root.add_child(button)


func _style_choice(button: Button, selected: bool) -> void:
	var bg := Color(0.16, 0.18, 0.22)
	var hot := Color(0.28, 0.31, 0.36)
	if selected:
		bg = Color(0.90, 0.38, 0.16)
		hot = Color(0.98, 0.50, 0.24)
	_paint(button, bg, hot, 16)


func _paint(button: Button, bg: Color, hot: Color, font_size: int) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", ui_font)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color(1, 1, 1))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	button.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	var normal := _button_box(bg)
	var hover := _button_box(hot)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", normal)


func _read_best() -> int:
	var cfg := ConfigFile.new()
	var err: int = cfg.load("user://mini_park.cfg")
	if err != OK:
		return 0
	return int(cfg.get_value("run", "best", 0))


func _label(text: String, size: int, color: Color, outline: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", ui_font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_constant_override("outline_size", outline)
		label.add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.08, 0.85))
	return label


func _button_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(12)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
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
