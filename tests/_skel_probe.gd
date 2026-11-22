extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://assets/kenney-mini-skate/character-skate-boy.glb") as PackedScene
	var node := packed.instantiate()
	root.add_child(node)
	_dump(node, 0)
	var board := load("res://assets/kenney-mini-skate/skateboard.glb") as PackedScene
	var b := board.instantiate()
	root.add_child(b)
	print("--- board ---")
	_dump(b, 0)
	quit()

func _dump(n: Node, d: int) -> void:
	var extra := ""
	if n is Skeleton3D:
		var sk := n as Skeleton3D
		extra = " bones=%d" % sk.get_bone_count()
		for i in sk.get_bone_count():
			extra += " [%s parent=%s]" % [sk.get_bone_name(i), sk.get_bone_parent(i)]
	print("  ".repeat(d) + n.name + ":" + n.get_class() + extra)
	for c in n.get_children():
		_dump(c, d + 1)
