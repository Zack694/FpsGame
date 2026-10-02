extends Node3D
# Dev-only: prints the posed height of each NPC model (max skeleton bone / mesh top).

func _ready() -> void:
	for spec: Array in [["scp173", ""], ["scp049", "idle"], ["scp049", "chase"], ["scp096", "idle"], ["scp096", "sit"], ["scp096", "run"], ["zombie", "idle"], ["zombie", "walk"]]:
		var inst: Node3D = (load("res://assets/models/npc/%s.glb" % spec[0]) as PackedScene).instantiate()
		add_child(inst)
		var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
		if ap and spec[1] != "":
			ap.play(spec[1])
			ap.seek(0.3, true)
		await get_tree().process_frame
		await get_tree().process_frame
		var top := -1e9
		var sk: Skeleton3D = inst.find_child("*", true, false) as Skeleton3D
		for s in inst.find_children("*", "Skeleton3D", true, false):
			var skel := s as Skeleton3D
			for b in skel.get_bone_count():
				top = maxf(top, (skel.global_transform * skel.get_bone_global_pose(b)).origin.y)
		var heads := ""
		for s2 in inst.find_children("*", "Skeleton3D", true, false):
			var sk2 := s2 as Skeleton3D
			for b in sk2.get_bone_count():
				var bn := sk2.get_bone_name(b).to_lower()
				if bn.contains("head") or bn.contains("neck"):
					heads += "%s=%.2f " % [bn, (sk2.global_transform * sk2.get_bone_global_pose(b)).origin.y]
		print("  heads ", heads)
		var mesh_top := -1e9
		for m in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			var bb := mi.global_transform * mi.get_aabb()
			mesh_top = maxf(mesh_top, bb.end.y)
		print("H ", spec[0], " ", spec[1], " bones_top=", snappedf(top, 0.01), " mesh_top=", snappedf(mesh_top, 0.01))
		inst.queue_free()
	get_tree().quit()
