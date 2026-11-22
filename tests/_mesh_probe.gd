extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var kit = load("res://scripts/pieces.gd").new()
	var world := Node3D.new()
	root.add_child(world)
	var ids: Array[String] = ["quarter", "half-pipe-low", "bank", "floor-concrete", "low-rail", "high-rail", "rail-curve", "ledge", "obstacle-box", "steps", "ramp"]
	for id in ids:
		var body: Node3D = kit.place(world, id, 0, 0, 0, 0.0)
		await process_frame
		var pts := PackedVector3Array()
		_gather(body, Transform3D.IDENTITY, pts)
		if pts.is_empty():
			print(id, " NO PTS")
			body.queue_free()
			continue
		var min_v := pts[0]
		var max_v := pts[0]
		for p in pts:
			min_v = min_v.min(p)
			max_v = max_v.max(p)
		print("%s n=%d min=%s max=%s" % [id, pts.size(), min_v, max_v])
		if id == "quarter" or id == "half-pipe-low" or id == "bank":
			_profile(id, pts)
		body.queue_free()
		await process_frame
	# stacked rail
	var concrete: Node3D = kit.place(world, "floor-concrete", 2, 0, 0, 0.0)
	var rail: Node3D = kit.place(world, "low-rail", 2, 0, 0, 0.2)
	await process_frame
	print("concrete y", concrete.position.y, "stack", concrete.get_meta("stack_y"))
	print("rail y", rail.position.y, "stack", rail.get_meta("stack_y"))
	var rail_pts := PackedVector3Array()
	_gather(rail, Transform3D.IDENTITY, rail_pts)
	var rmin := rail_pts[0]
	var rmax := rail_pts[0]
	for p in rail_pts:
		rmin = rmin.min(p)
		rmax = rmax.max(p)
	print("rail world min", rmin, "max", rmax)
	var cpts := PackedVector3Array()
	_gather(concrete, Transform3D.IDENTITY, cpts)
	var cmin := cpts[0]
	var cmax := cpts[0]
	for p in cpts:
		cmin = cmin.min(p)
		cmax = cmax.max(p)
	print("concrete world min", cmin, "max", cmax, "height fn", kit.piece_height("floor-concrete"))
	print("rail local bar", kit._rail_local("low-rail"))
	quit()

func _profile(id: String, pts: PackedVector3Array) -> void:
	# Highest points and z of the lip (max y band)
	var top := -1000.0
	for p in pts:
		top = maxf(top, p.y)
	var lip_z := 0.0
	var lip_n := 0
	var band := top - 0.04
	var min_z := 1000.0
	var max_z := -1000.0
	for p in pts:
		if p.y >= band:
			lip_z += p.z
			lip_n += 1
			min_z = minf(min_z, p.z)
			max_z = maxf(max_z, p.z)
	print("  top y %.3f lip z avg %.3f range %.3f..%.3f n %d" % [top, lip_z / maxf(lip_n, 1), min_z, max_z, lip_n])
	# sample height along z at x~0
	var bins := {}
	for p in pts:
		if absf(p.x) > 0.15:
			continue
		var key := int(round(p.z * 20.0))
		var prev: float = float(bins.get(key, -1000.0))
		if p.y > prev:
			bins[key] = p.y
	var keys: Array = bins.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key in keys:
		parts.append("%d:%.2f" % [key, float(bins[key])])
	print("  centerline ", " ".join(parts))

func _gather(node: Node, xform: Transform3D, pts: PackedVector3Array) -> void:
	var here := xform
	if node is Node3D:
		here = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			for s in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(s)
				var raw = arrays[Mesh.ARRAY_VERTEX]
				if raw is PackedVector3Array:
					for v in raw:
						pts.append(here * v)
	for child in node.get_children():
		_gather(child, here, pts)
