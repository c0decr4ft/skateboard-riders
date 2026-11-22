extends SceneTree
## Collision follows the visible mesh. Air above a slope or a lower step stays empty.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var kit = load("res://scripts/pieces.gd").new()
	var ids: Array[String] = ["quarter", "ramp", "steps", "steps-rail"]
	var bodies: Dictionary = {}
	for i in range(ids.size()):
		var placed: Node3D = kit.place(world, ids[i], i * 4, 0, 0, 0.0)
		bodies[ids[i]] = placed
	for _frame in range(3):
		await physics_frame
	for id in ids:
		var body: StaticBody3D = bodies[id]
		var boxes := 0
		var concave := 0
		var other := 0
		var faces := 0
		for child in body.get_children():
			if not (child is CollisionShape3D):
				continue
			var shape: Shape3D = (child as CollisionShape3D).shape
			if shape is BoxShape3D:
				boxes += 1
				print("%s BOX size %s" % [id, (shape as BoxShape3D).size])
			elif shape is ConcavePolygonShape3D:
				concave += 1
				faces = (shape as ConcavePolygonShape3D).data.size() / 3
			else:
				other += 1
				print("%s OTHER %s" % [id, shape.get_class()])
		print("%s shapes concave=%d box=%d other=%d triangles=%d" % [id, concave, boxes, other, faces])
		if boxes == 0 and concave == 1 and faces > 12:
			print("PASS %s is a mesh trimesh" % id)
		else:
			print("FAIL %s collision is not the visual mesh" % id)
	_air(world, bodies["quarter"], "quarter")
	_air(world, bodies["ramp"], "ramp")
	_steps(world, bodies["steps"], "steps")
	_steps(world, bodies["steps-rail"], "steps-rail")
	quit()


func _air(world: Node3D, body: StaticBody3D, id: String) -> void:
	var origin: Vector3 = body.global_position
	var low := _down(world, origin + Vector3(0, 3, 0.32))
	var high := _down(world, origin + Vector3(0, 3, -0.32))
	print("%s down low=%s high=%s" % [id, _py(low), _py(high)])
	var low_y := 0.0
	if not low.is_empty():
		low_y = (low["position"] as Vector3).y
	var through := _ray(world, origin + Vector3(-1.5, low_y + 0.28, 0.32), origin + Vector3(1.5, low_y + 0.28, 0.32))
	var blocked: bool = not through.is_empty() and (through["collider"] as Node) == body
	if not low.is_empty() and not high.is_empty() and (high["position"] as Vector3).y > low_y + 0.12 and not blocked:
		print("PASS %s air above the slope is empty" % id)
	else:
		print("FAIL %s air check blocked=%s" % [id, blocked])


func _steps(world: Node3D, body: StaticBody3D, id: String) -> void:
	var origin: Vector3 = body.global_position
	var front := _down(world, origin + Vector3(0, 3, 0.35))
	var back := _down(world, origin + Vector3(0, 3, -0.35))
	print("%s step front=%s back=%s" % [id, _py(front), _py(back)])
	var front_y := 0.0
	if not front.is_empty():
		front_y = (front["position"] as Vector3).y
	var through := _ray(world, origin + Vector3(-1.2, front_y + 0.18, 0.35), origin + Vector3(1.2, front_y + 0.18, 0.35))
	var blocked: bool = not through.is_empty() and (through["collider"] as Node) == body
	var taller: bool = not front.is_empty() and not back.is_empty() and absf((back["position"] as Vector3).y - front_y) > 0.05
	if taller and not blocked:
		print("PASS %s follows the treads, air above the lower step is empty" % id)
	else:
		print("FAIL %s stairs taller=%s blocked=%s" % [id, taller, blocked])


func _down(world: Node3D, from: Vector3) -> Dictionary:
	return _ray(world, from, from + Vector3(0, -4, 0))


func _py(hit: Dictionary) -> String:
	if hit.is_empty():
		return "miss"
	return "%.3f" % (hit["position"] as Vector3).y


func _ray(world: Node3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	return world.get_world_3d().direct_space_state.intersect_ray(query)
