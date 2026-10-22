"""Run inside the live Blender through MCP. Non-destructive dedicated studio scene."""
import bpy,math,json,hashlib,io_scene_gltf2
from pathlib import Path
from mathutils import Vector,Matrix

ROOT=Path('D:/Zombied')
scene=bpy.data.scenes.new('Zombied Weapon Studio 0.3')
bpy.context.window.scene=scene
materials={}
def material(name,color,metal=.8,rough=.25,glow=0):
    m=bpy.data.materials.new('ZW4_'+name);m.use_nodes=True
    shader=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    shader.inputs['Base Color'].default_value=(*color,1)
    shader.inputs['Metallic'].default_value=metal
    shader.inputs['Roughness'].default_value=rough
    shader.inputs['Emission Color'].default_value=(*color,1)
    shader.inputs['Emission Strength'].default_value=glow
    m.diffuse_color=(*color,1)
    return m
materials['dark']=material('Graphite',(.035,.06,.085))
materials['steel']=material('Titanium',(.33,.43,.49),.92,.21)
materials['white']=material('Ceramic',(.66,.75,.79),.45,.22)
materials['gold']=material('AnodizedGold',(.65,.39,.12),.9,.21)
materials['rubber']=material('Grip',(.018,.025,.033),.05,.65)
bevel_type=next(i.identifier for i in bpy.types.Modifier.bl_rna.properties['type'].enum_items if i.identifier=='BEVEL')
glb_format=next(i[0] for i in io_scene_gltf2.get_format_items(scene,bpy.context) if i[0]=='GLB')
png_format=next(i.identifier for i in bpy.types.ImageFormatSettings.bl_rna.properties['file_format'].enum_items if i.identifier=='PNG')
rgba_mode=next(i.identifier for i in bpy.types.ImageFormatSettings.bl_rna.properties['color_mode'].enum_items if i.identifier=='RGBA')
models={};manifest=[]
root=None;parts=[]
def finish(obj,name,mat):
    obj.name=name;obj.parent=root
    obj.data.materials.append(materials[mat])
    parts.append(obj)
    return obj
def box(name,pos,size,mat='dark',bevel=.018):
    bpy.ops.mesh.primitive_cube_add(size=1,location=pos)
    o=bpy.context.object;o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new('Machined edge radii',bevel_type);mod.width=bevel;mod.segments=3
    return finish(o,name,mat)
def cylinder(name,pos,radius,length,mat='steel',axis='Y',vertices=20):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=length,location=pos)
    o=bpy.context.object
    if axis=='Y':o.rotation_euler.x=math.pi/2
    if axis=='X':o.rotation_euler.y=math.pi/2
    mod=o.modifiers.new('Lathed rim',bevel_type);mod.width=.006;mod.segments=2
    return finish(o,name,mat)

specs=[('ar',(.04,.65,1),'XR-17'),('shotgun',(1,.28,.035),'SG-08'),('smg',(.64,.08,1),'VX-9'),('magnum',(.25,.85,1),'M-6'),('lmg',(1,.075,.025),'H-249'),('grenade_launcher',(.14,1,.4),'GL-32')]
out=ROOT/'assets/models/weapons';out.mkdir(exist_ok=True)
for index,(kind,color,serial) in enumerate(specs):
    root=bpy.data.objects.new('Weapon_'+kind,None);scene.collection.objects.link(root);parts=[]
    materials['energy']=material(kind+'_Energy',color,.25,.15,4)
    length=.38 if kind in ['smg','magnum'] else .58
    box('Armored receiver',(0,0,0),(.26,length,.23),'dark')
    for side in [-1,1]:
        box('Ceramic side shell',(side*.139,.025,.025),(.035,length*.82,.15),'white',.009)
        box('Gold seam',(side*.16,.025,.108),(.016,length*.88,.018),'gold',.005)
        for vent in range(5):
            box('Cooling gill',(side*.161,-.14+vent*.065,.018),(.01,.022,.082),'dark',.003)
        for y in [-.18,.18]:
            cylinder('Titanium fastener',(side*.169,y,.065),.018,.012,'gold',axis='X',vertices=12)
    grip=box('Ergonomic grip',(0,-.15,-.23),(.125,.17,.29),'rubber');grip.rotation_euler.x=-.2
    for notch in range(4):box('Grip rib',(0,-.235,-.34+notch*.055),(.14,.02,.018),'steel',.003)
    box('Trigger guard',(0,.06,-.18),(.04,.25,.035),'gold',.009)
    if kind not in ['magnum','smg']:
        box('Stock spine',(0,-.43,.01),(.11,.37,.09),'steel')
        box('Shoulder pad',(0,-.63,-.04),(.2,.13,.27),'rubber')
        box('Stock accent',(0,-.48,.068),(.12,.2,.025),'gold',.006)
    box('Top rail',(0,.04,.154),(.075,length,.045),'steel',.008)
    cylinder('Optic housing',(0,.025,.225),.055,.19,'dark')
    cylinder('Optic lens',(0,.127,.225),.041,.012,'energy')
    if kind=='shotgun':
        for x in [-.105,.105]:
            cylinder('Plasma barrel',(x,.58,.005),.064,.64,'steel')
            cylinder('Muzzle collar',(x,.91,.005),.077,.07,'gold')
            cylinder('Plasma aperture',(x,.953,.005),.053,.018,'energy')
        box('Pump shroud',(0,.38,-.095),(.29,.28,.1),'white')
        box('Plasma cell',(0,-.02,-.16),(.19,.25,.1),'energy',.012)
    elif kind=='lmg':
        for x,z in [(-.065,-.06),(.065,-.06),(-.065,.07),(.065,.07)]:
            cylinder('Rotary cannon tube',(x,.62,z),.039,.79,'steel')
            cylinder('Hot barrel lip',(x,1.025,z),.047,.045,'gold')
            cylinder('Thermal core',(x,1.052,z),.026,.012,'energy')
        for y in [.35,.64,.86]:box('Barrel brace',(0,y,.015),(.25,.055,.24),'dark',.012)
        box('Heavy feed cassette',(.21,-.02,-.08),(.22,.34,.29),'dark')
        for y in [-.1,-.025,.05]:box('Feed energy cell',(.33,y,-.04),(.018,.035,.16),'energy',.004)
    elif kind=='grenade_launcher':
        cylinder('Launch tube',(0,.57,.015),.12,.6,'steel')
        cylinder('Gold breech',(0,.89,.015),.145,.08,'gold')
        cylinder('Core aperture',(0,.94,.015),.103,.022,'energy')
        cylinder('Rotating chamber',(0,-.005,-.11),.2,.34,'dark',axis='X',vertices=24)
        for angle in range(6):
            a=angle*math.tau/6
            cylinder('Capacitor chamber',(0,math.cos(a)*.145,math.sin(a)*.145-.11),.044,.37,'gold',axis='X',vertices=12)
    else:
        barrel_length=.43 if kind=='smg' else (.64 if kind=='ar' else .53)
        front=.25+barrel_length
        cylinder('Magnetic barrel',(0,.25+barrel_length/2,.005),.055,barrel_length,'steel')
        for y in [.32,.46,.6]:
            cylinder('Acceleration ring',(0,y,.005),.074,.04,'gold')
            cylinder('Energy coil',(0,y+.023,.005),.063,.018,'energy')
        cylinder('Muzzle brake',(0,front,.005),.086,.075,'dark')
        cylinder('Firing aperture',(0,front+.044,.005),.05,.018,'energy')
        for side in [-1,1]:box('Luminous guide rail',(side*.077,.46,.035),(.023,barrel_length*.8,.028),'energy',.006)
        if kind=='magnum':
            cylinder('Revolver chamber',(0,.055,.012),.14,.24,'dark')
            for i in range(6):
                a=i*math.tau/6
                cylinder('Cartridge',(math.cos(a)*.103,.055,math.sin(a)*.103+.012),.027,.26,'gold',vertices=12)
        else:
            box('Power magazine',(.01,.045,-.23),(.13,.21,.3),'dark')
            box('Charge indicator',(.082,.045,-.22),(.014,.14,.2),'energy',.005)
    models[kind]={'root':root,'parts':parts.copy(),'serial':serial}
    # Export a temporary baked/merged copy. Editable individual parts remain.
    copies=[]
    for obj in parts:
        for selected in bpy.context.selected_objects:selected.select_set(False)
        temp=obj.copy();temp.data=obj.data.copy();scene.collection.objects.link(temp)
        temp.parent=None;temp.matrix_world=obj.matrix_world.copy();temp.select_set(True)
        bpy.context.view_layer.objects.active=temp
        for modifier in list(temp.modifiers):bpy.ops.object.modifier_apply(modifier=modifier.name)
        copies.append(temp)
    for selected in bpy.context.selected_objects:selected.select_set(False)
    for obj in copies:obj.select_set(True)
    bpy.context.view_layer.objects.active=copies[0]
    bpy.ops.object.join();merged=bpy.context.object
    merged.data.transform(merged.matrix_world);merged.matrix_world=Matrix.Identity(4)
    merged.name='ZW4_'+kind
    merged.data.calc_loop_triangles()
    path=out/(kind+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format=glb_format,use_selection=True,use_active_scene=True,export_apply=True)
    manifest.append({'id':kind,'serial':serial,'parts':len(parts),'triangles':len(merged.data.loop_triangles),'materials':len(merged.data.materials),'file':str(path.relative_to(ROOT)).replace('\\','/'),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    bpy.data.objects.remove(merged,do_unlink=True)
    root.location=((index%3-1)*2.4,(index//3-.5)*2.8,0)

# Neutral showroom lighting, independent from the user's original scene.
root=None;parts=[]
materials['floor']=material('StudioFloor',(.018,.027,.045),.35,.35)
box('Studio plinth',(0,0,-.56),(8,6,.1),'floor',.05)
world=bpy.data.worlds.new('ZW4 Studio world');world.use_nodes=True
background=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND')
background.inputs[0].default_value=(.06,.08,.13,1)
background.inputs[1].default_value=.45
scene.world=world
for name,position,power,size,color in [('Key',(1,-3,7),1600,6,(.8,.9,1)),('Rim',(-4,3,4),1200,5,(.3,.6,1)),('Warm',(4,2,3),1000,4,(1,.58,.25))]:
    area_type=next(i.identifier for i in bpy.types.Light.bl_rna.properties['type'].enum_items if i.identifier=='AREA')
    data=bpy.data.lights.new('ZW4 '+name,area_type);data.energy=power;data.shape=next(i.identifier for i in data.bl_rna.properties['shape'].enum_items if i.identifier=='DISK');data.size=size;data.color=color
    light=bpy.data.objects.new(name,data);scene.collection.objects.link(light);light.location=position
    light.rotation_euler=(Vector((0,0,0))-light.location).to_track_quat('-Z','Y').to_euler()
camera_data=bpy.data.cameras.new('ZW4 Camera');camera_data.type=next(i.identifier for i in camera_data.bl_rna.properties['type'].enum_items if i.identifier=='ORTHO');camera_data.ortho_scale=9
camera=bpy.data.objects.new('ZW4 Camera',camera_data);scene.collection.objects.link(camera);camera.location=(6,-9,13)
camera.rotation_euler=(Vector((0,0,-.1))-camera.location).to_track_quat('-Z','Y').to_euler();scene.camera=camera
scene.render.resolution_x=1400;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.render.image_settings.file_format=png_format;scene.render.image_settings.color_mode=rgba_mode
scene.render.filepath=str(ROOT/'artifacts/scifi-weapons-contact.png')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'assets/weapon_studio_v4.blend'))
(ROOT/'assets/weapons-v4-manifest.json').write_text(json.dumps({'models':manifest,'source':'assets/weapon_studio_v4.blend','scope':'Blender-authored hard-surface models. Forward +Y in Blender, -Z in Godot after glTF export.'},indent=2),encoding='utf-8')
print(json.dumps({'scene':scene.name,'render_engine':scene.render.engine,'models':manifest}))
