class_name ZVisuals
extends RefCounted

static var materials: Dictionary = {}
static var crowd_materials: Dictionary={}
const CrowdShader = preload("res://shaders/crowd_pose.gdshader")

static func mat(color: Color, metallic: float = 0.0, roughness: float = 0.65, emission: float = 0.0) -> StandardMaterial3D:
	var key := str(color) + str(metallic) + str(roughness) + str(emission)
	if materials.has(key):
		return materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission > 0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	materials[key] = m
	return m

static func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = mat(color, 0.15, 0.5, glow)
	parent.add_child(node)
	return node

static func sphere(parent: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 10
	mesh.rings = 5
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = mat(color)
	parent.add_child(node)
	return node

static func bake_pose(parent: Node3D) -> ArrayMesh:
	# Keep the authored silhouette/materials, batching rigid parts by material.
	var surfaces: Dictionary={}
	for part in parent.get_children():
		if not part is MeshInstance3D or part.mesh==null: continue
		var material: StandardMaterial3D=part.material_override
		if not surfaces.has(material):
			var tool:=SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			if not crowd_materials.has(material):
				var batched_material:=ShaderMaterial.new()
				batched_material.shader=CrowdShader
				batched_material.set_shader_parameter("base_color",material.albedo_color)
				batched_material.set_shader_parameter("metalness",material.metallic)
				batched_material.set_shader_parameter("surface_roughness",material.roughness)
				batched_material.set_shader_parameter("glow_color",material.emission)
				batched_material.set_shader_parameter("glow_energy",material.emission_energy_multiplier if material.emission_enabled else 0)
				crowd_materials[material]=batched_material
			tool.set_material(crowd_materials[material])
			surfaces[material]=tool
		var arrays: Array=part.mesh.surface_get_arrays(0)
		var colors:=PackedColorArray()
		colors.resize(arrays[Mesh.ARRAY_VERTEX].size())
		var leg: bool=part.position.y<.8 and absf(part.position.x)<.3
		colors.fill(Color((.5 if part.position.x<0 else 1) if leg else 0,0,0))
		arrays[Mesh.ARRAY_COLOR]=colors
		var tagged:=ArrayMesh.new()
		tagged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		surfaces[material].append_from(tagged,0,part.transform)
	var result:=ArrayMesh.new()
	for tool in surfaces.values(): tool.commit(result)
	return result

static func humanoid(parent: Node3D, zombie: bool = false, elite: bool = false) -> Dictionary:
	var skin := Color("86917b") if zombie else Color("b4a18a")
	var cloth := Color("50493f") if zombie else Color("344f4d")
	if elite:
		cloth = Color("753f2d")
	var limbs := {}
	limbs.torso = box(parent, Vector3(.64,.68,.35), Vector3(0,1.05,0), cloth)
	limbs.head = box(parent, Vector3(.38,.42,.37), Vector3(0,1.63,-.015), skin)
	limbs.left_arm = box(parent, Vector3(.19,.67,.22), Vector3(-.44,1.0,-.05), cloth)
	limbs.right_arm = box(parent, Vector3(.19,.67,.22), Vector3(.44,1.0,-.05), cloth)
	limbs.left_leg = box(parent, Vector3(.23,.69,.27), Vector3(-.18,.38,0), cloth.darkened(.3))
	limbs.right_leg = box(parent, Vector3(.23,.69,.27), Vector3(.18,.38,0), cloth.darkened(.3))
	for side in [-1,1]:
		box(parent, Vector3(.23,.18,.4), Vector3(side*.18,.12,-.08), Color("172726"))
	if zombie:
		box(parent, Vector3(.24,.06,.035), Vector3(0,1.66,-.21), Color("c8e48b"), 1.4)
		box(parent, Vector3(.22,.3,.04), Vector3(-.13,1.1,-.19), Color("79372a"))
		limbs.left_arm.rotation.x = -.7
		limbs.right_arm.rotation.x = -.9
	else:
		box(parent, Vector3(.71,.46,.39), Vector3(0,1.17,0), Color("263a35"))
		box(parent, Vector3(.44,.2,.43), Vector3(0,1.82,.01), Color("53655d"))
		box(parent, Vector3(.4,.08,.08), Vector3(0,1.74,-.24), Color("233533"))
		box(parent, Vector3(.42,.53,.25), Vector3(0,1.15,.3), Color("7c7154"))
		box(parent, Vector3(.18,.09,.05), Vector3(-.19,1.24,-.23), Color("b4e8cb"), 2)
	return limbs
