extends Node3D

var grid := AStarGrid2D.new()
var obstacles: Array = []
var gate: StaticBody3D
var game: Node3D
var environment_props: Node3D
var indoor := false

func _ready() -> void:
	var layout_name: String=game.stage_manager.definition().layout
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/"+layout_name+"_layout.json"))
	indoor=layout.get("weather","rain")=="indoor"
	var authored_path: String="res://assets/models/v5/"+layout_name+".glb"
	var district: PackedScene = load(authored_path if ResourceLoader.exists(authored_path) else "res://assets/models/"+layout_name+".glb")
	var visual := district.instantiate()
	add_child(visual)
	weather_materials(visual)
	obstacles = layout.colliders
	# Service alleys behind the fences are scenery, not navigable combat pockets.
	for side in [-1,1]:
		obstacles.append({"name":"Service perimeter","position":[side*14.5,1.2,0],"size":[3.2,2.4,28]})
	add_collider(Vector3(0,-.24,0), Vector3(40,.5,38))
	for item in obstacles:
		add_collider(vec(item.position), vec(item.size))
	for side in [-1,1]:
		for z in range(-12,13,2):
			ZVisuals.box(self,Vector3(.065,1.1,.065),Vector3(side*12.9,.55,z),Color("647366"))
		for height in [.45,1.05]:
			ZVisuals.box(self,Vector3(.06,.06,26),Vector3(side*12.9,height,0),Color("647366"))
	# Seal decorative wall joints and both shoulders of the exit aperture.
	for x in [-9.2,9.2]:
		add_collider(Vector3(x,3,-14),Vector3(13.6,6,.7))
	for x in [-16.2,16.2]:
		add_collider(Vector3(x,3,0),Vector3(.6,6,29))
	add_collider(Vector3(0,3,14.4),Vector3(33,6,.6))
	gate = add_collider(Vector3(0,2,-14), Vector3(4.5,4,.5))
	var gate_mesh := ZVisuals.box(gate,Vector3(4.5,3.8,.3),Vector3.ZERO,Color("23433e"))
	gate_mesh.position.y = 0
	for x in [-1.8,-.9,0,.9,1.8]:
		ZVisuals.box(gate,Vector3(.05,3.8,.36),Vector3(x,0,0),Color("85917a"))
	setup_navigation()
	setup_environment(layout.lights)
	environment_props=preload("res://scripts/managers/environment_manager.gd").new()
	environment_props.game=game
	environment_props.world=self
	add_child(environment_props)

func vec(a: Array) -> Vector3:
	return Vector3(a[0],a[1],a[2])

func add_collider(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	return body

func setup_navigation() -> void:
	grid.region = Rect2i(-32,-30,65,61)
	grid.cell_size = Vector2(.5,.5)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for x in range(-32,33):
		for z in range(-30,31):
			var p := Vector2(x*.5,z*.5)
			var blocked := absf(p.x) > 15 or absf(p.y) > 13
			for item in obstacles:
				if item.position[1] + item.size[1]*.5 < .2:
					continue
				if absf(p.x-item.position[0]) < item.size[0]*.5+.36 and absf(p.y-item.position[2]) < item.size[2]*.5+.36:
					blocked = true
					break
			grid.set_point_solid(Vector2i(x,z),blocked)

func cell(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x/.5), roundi(pos.z/.5))

func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var result := PackedVector3Array()
	var a := nearest_open_cell(cell(from))
	var b := nearest_open_cell(cell(to))
	if not grid.is_in_boundsv(a) or not grid.is_in_boundsv(b) or grid.is_point_solid(a) or grid.is_point_solid(b):
		return result
	for p in grid.get_point_path(a,b):
		result.append(Vector3(p.x,0,p.y))
	return result

func nearest_open_cell(point: Vector2i) -> Vector2i:
	if grid.is_in_boundsv(point) and not grid.is_point_solid(point):
		return point
	var best := point
	var distance := INF
	for dx in range(-4,5):
		for dz in range(-4,5):
			var candidate := point+Vector2i(dx,dz)
			if not grid.is_in_boundsv(candidate) or grid.is_point_solid(candidate):
				continue
			var d := Vector2(dx,dz).length_squared()
			if d<distance:
				distance=d
				best=candidate
	return best

func walkable(p: Vector3) -> bool:
	var c := cell(p)
	return grid.is_in_boundsv(c) and not grid.is_point_solid(c)

func open_gate() -> void:
	gate.collision_layer = 0
	var tween := create_tween()
	tween.tween_property(gate,"position:y",6.5,1.2).set_trans(Tween.TRANS_CUBIC)

func setup_environment(lights: Array) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("16272a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8b9cba")
	environment.ambient_light_energy = .2 if indoor else .3
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("243a35")
	environment.fog_sky_affect = 0
	environment.fog_density = .003
	environment.fog_height = 1.3
	environment.fog_height_density = .05
	environment.glow_enabled = true
	environment.glow_intensity = .55
	environment.ssao_enabled = true
	environment.ssao_radius = 1.3
	environment.ssao_intensity = 2.1
	environment.ssr_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-58,-28,0)
	moon.light_color = Color("9db8dc")
	moon.light_energy = .08 if indoor else .4
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 70
	add_child(moon)
	for info in lights:
		var light := OmniLight3D.new()
		light.position = vec(info.position)
		light.light_color = Color(info.color[0],info.color[1],info.color[2])
		light.light_energy = info.energy * .8
		light.omni_range = info.range
		light.omni_attenuation = 1.8
		add_child(light)
	if indoor:
		return
	# Shader rain: one draw call and a fixed population, no per-drop scene nodes.
	var rain := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.mesh.size = Vector3(.009,.22,.009)
	mm.instance_count = 300
	for i in mm.instance_count:
		mm.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3(randf_range(-18,18),randf_range(0,13),randf_range(-17,17))))
	rain.multimesh = mm
	var shader := Shader.new()
	# The world-space wrap must include each instance's original height.
	# Tall foreground streaks obscure aiming in the steep camera view. Keep
	# drizzle near street level and fade the rain closest to the camera.
	shader.code = "shader_type spatial; render_mode unshaded,cull_disabled; varying float rain_fade; void vertex(){ float height=mod(MODEL_MATRIX[3].y-TIME*12.0,13.0); VERTEX.y+=height-MODEL_MATRIX[3].y; VERTEX.x+=sin(TIME)*0.04; rain_fade=1.0-smoothstep(2.5,7.0,height); } void fragment(){ ALBEDO=vec3(0.40,0.56,0.55); ALPHA=0.065*rain_fade; }"
	var rain_mat := ShaderMaterial.new()
	rain_mat.shader = shader
	rain.material_override = rain_mat
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)
	setup_puddles()

func weather_materials(root: Node) -> void:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
uniform vec4 base_color: source_color = vec4(0.2,0.2,0.2,1.0);
uniform float wet = 0.0;
uniform float masonry = 0.0;
varying vec3 world_pos;
varying vec3 surface_normal;
float hash(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y); }
void vertex(){ world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; surface_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL); }
void fragment(){
 vec2 uv=abs(surface_normal.y)>0.6?world_pos.xz:(abs(surface_normal.x)>0.5?world_pos.zy:world_pos.xy);
 float grime=noise(uv*1.3)*0.5+noise(uv*6.0)*0.2+noise(uv*35.0)*0.1;
 float puddle=smoothstep(0.48,0.7,noise(uv*0.45))*wet;
 ALBEDO=base_color.rgb*(0.55+grime*0.65)*(1.0-puddle*0.28);
 vec2 brick=fract(uv*vec2(2.5,5.0)+vec2(mod(floor(uv.y*5.0),2.0)*0.5,0.0));
 float grout=step(0.035,brick.x)*step(0.07,brick.y);
 ALBEDO=mix(ALBEDO,mix(vec3(0.095,0.10,0.11),base_color.rgb*(0.8+grime*0.4),grout),masonry);
 METALLIC=mix(0.05,0.42,puddle);
 ROUGHNESS=mix(0.72,0.12,puddle);
 NORMAL_MAP=vec3(0.5+sin(uv.x*180.0+TIME*4.0)*puddle*0.015,0.5+noise(uv*70.0)*0.025,1.0);
}"""
	var cache := {}
	for child in root.find_children("*","MeshInstance3D",true,false):
		# Near-side architecture uses a low cutaway to preserve combat visibility.
		if child.name.begins_with("Warehouse") or child.name.begins_with("Roller") or child.name.begins_with("Shutter"):
			child.visible=false
		if child.position.z>13.4 and (child.name.begins_with("Wall") or child.name.begins_with("Buttress") or child.name.begins_with("Uneven")):
			child.scale.y*=.34
			child.position.y*=.34
		for surface in child.mesh.get_surface_count():
			var original = child.get_active_material(surface)
			if not original is StandardMaterial3D:
				continue
			if original.emission_enabled:
				continue
			var name_: String=original.resource_name
			if not ("concrete" in name_.to_lower() or "asphalt" in name_.to_lower() or "road" in name_.to_lower() or "brick" in name_.to_lower()):
				continue
			if not cache.has(name_):
				var m := ShaderMaterial.new()
				m.shader=shader
				m.set_shader_parameter("base_color",original.albedo_color)
				m.set_shader_parameter("masonry",1.0 if "brick" in name_.to_lower() else 0.0)
				m.set_shader_parameter("wet",1.0 if not indoor and ("asphalt" in name_.to_lower() or "road" in name_.to_lower() or "Rainwashed" in name_) else 0.0)
				cache[name_]=m
			child.set_surface_override_material(surface,cache[name_])

func setup_puddles() -> void:
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode blend_mix; void fragment(){ float rip=sin((UV.x+UV.y)*180.0+TIME*3.0)*0.5+0.5; ALBEDO=vec3(0.11,0.17,0.16); METALLIC=0.55; ROUGHNESS=0.09+rip*0.04; NORMAL_MAP=vec3(0.5+rip*0.018,0.5,1.0); ALPHA=0.5; }"
	var material := ShaderMaterial.new()
	material.shader = shader
	for info in [[-2,2,4.3,2.1],[3,-4,3.2,1.2],[-7,9,3.8,1.5],[7,-7,4.3,1.6],[0,-9,2.8,1.8]]:
		var plane := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 1
		mesh.bottom_radius = 1
		mesh.height = .006
		mesh.radial_segments = 22
		plane.mesh = mesh
		plane.scale = Vector3(info[2],1,info[3])
		plane.position = Vector3(info[0],.045,info[1])
		plane.material_override = material
		plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(plane)
