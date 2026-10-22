extends Node

var results: Array=[]
func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func run(game: Node3D) -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/modular_library.json"))
	check(data.units=="meters" and data.up_axis=="Y" and data.forward_axis=="-Z","Library shares Godot meter units and axis conventions")
	var categories := {}
	var ids := {}
	var total_triangles := 0
	for module in data.modules:
		categories[module.category]=true
		ids[module.id]=true
		var packed: PackedScene=load(module.path)
		var scene: Node3D=packed.instantiate()
		add_child(scene)
		var meshes: Array=scene.find_children("*","MeshInstance3D",true,false)
		var valid: bool=not meshes.is_empty()
		var surfaces := 0
		for mesh in meshes:
			var bounds: AABB=mesh.global_transform*mesh.get_aabb()
			valid=valid and bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.length()>0
			surfaces+=mesh.mesh.get_surface_count()
		for collider in module.colliders:
			valid=valid and collider.position.size()==3 and collider.size.size()==3 and float(collider.size[0])>0 and float(collider.size[1])>0 and float(collider.size[2])>0
		check(valid and surfaces<=16,module.id+" imports real geometry, finite bounds and valid local colliders")
		total_triangles+=int(module.triangles)
		scene.queue_free()
	check(ids.size()>=37 and categories.size()==12,"Reusable modules cover all twelve requested categories")
	check(total_triangles<30000,"Complete shared kit stays below thirty thousand authored triangles")
	for id in ["chapter_street","chapter_shop","chapter_apartments","chapter_garage","chapter_fuel","chapter_evac"]:
		var layout: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/"+id+"_layout.json"))
		var valid: bool=layout.module_instances.size()>=60
		for placement in layout.module_instances:
			valid=valid and ids.has(placement.module)
		check(valid and ResourceLoader.exists("res://assets/models/"+id+".glb"),id+" is assembled from referenced shared modules")
	var failed: Array=results.filter(func(item):return not item.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size(),"modules":ids.size(),"categories":categories.size(),"triangles":total_triangles}
	var file:=FileAccess.open("res://artifacts/modular-library-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("MODULAR_LIBRARY_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
