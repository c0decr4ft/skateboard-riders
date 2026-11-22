extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://assets/kenney-mini-skate/floor-concrete.glb") as PackedScene
	var node := packed.instantiate()
	root.add_child(node)
	var mesh_node := _find(node)
	var mesh: Mesh = mesh_node.mesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	print("uvs", uvs)
	var mat := mesh.surface_get_material(0)
	print("mat", mat)
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		print("albedo", sm.albedo_color, "tex", sm.albedo_texture)
	var tex: Texture2D = load("res://assets/kenney-mini-skate/Textures/colormap.png")
	var img := tex.get_image()
	print("tex size", img.get_width(), img.get_height())
	for uv in uvs:
		var x := clampi(int(uv.x * img.get_width()), 0, img.get_width() - 1)
		var y := clampi(int((1.0 - uv.y) * img.get_height()), 0, img.get_height() - 1)
		print("sample", uv, img.get_pixel(x, y))
	quit()

func _find(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find(child)
		if found:
			return found
	return null
