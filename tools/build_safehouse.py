"""Generate an editable, cutaway safehouse and export only this collection."""
import bpy, math, json
from pathlib import Path

ROOT = Path('D:/Zombied')
old = bpy.data.collections.get('Zombied Safehouse')
if old:
    for obj in list(old.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(old)
collection = bpy.data.collections.new('Zombied Safehouse')
bpy.context.scene.collection.children.link(collection)

def material(name, color, emission=0, metal=0):
    mat = bpy.data.materials.new('Safehouse / '+name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Metallic'].default_value = metal
    shader.inputs['Roughness'].default_value = .6
    if emission:
        shader.inputs['Emission Color'].default_value = (*color,1)
        shader.inputs['Emission Strength'].default_value = emission
    return mat

mats = {
 'concrete':material('Concrete',(.14,.19,.17)),
 'edge':material('Painted plaster',(.3,.34,.28)),
 'steel':material('Steel',(.055,.085,.08),metal=.6),
 'teal':material('Teal',(.07,.3,.27),metal=.3),
 'wood':material('Wood',(.25,.15,.08)),
 'paper':material('Paper',(.64,.62,.43)),
 'warm':material('Warm tube',(1,.43,.12),3),
 'screen':material('Screen',(.18,.8,.61),2),
 'red':material('Emergency',(.65,.12,.05),1),
}

def box(name, p, size, mat='concrete'):
    bpy.ops.mesh.primitive_cube_add(size=1,location=(p[0],-p[2],p[1]))
    obj = bpy.context.object
    obj.name = 'SH / '+name
    obj.dimensions=(size[0],size[2],size[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for c in list(obj.users_collection): c.objects.unlink(obj)
    collection.objects.link(obj)
    obj.data.materials.append(mats[mat])
    mod=obj.modifiers.new('Soft edges','BEVEL'); mod.width=.025; mod.segments=1
    return obj

box('Foundation',(0,-.3,0),(22,.6,18))
for x in range(-10,11,2):
    for z in range(-8,9,2):
        box('Floor tile',(x,.025,z),(1.97,.05,1.97),'edge')
box('North wall',(0,2,-9),(22,4,.3))
box('West wall',(-11,2,0),(.3,4,18))
box('East cutaway',(11,.45,0),(.3,.9,18))
box('South cutaway',(0,.4,9),(22,.8,.3))
for x in [-10,-6,-2,2,6,10]:
    box('Wall pilaster',(x,2,-8.75),(.25,4,.25),'steel')
for x in [-7,0,7]:
    box('Warm fixture',(x,3.6,-8.5),(3,.12,.15),'warm')

# Six distinct service areas; their coordinates also drive the in-game labels.
stations=[
 {'id':'briefing','title':'MISSION BOARD','position':[-6,0,-6]},
 {'id':'armory','title':'ARMORY','position':[1,0,-6]},
 {'id':'crates','title':'SUPPLY CRATES','position':[7,0,-5]},
 {'id':'research','title':'RESEARCH','position':[-7,0,2]},
 {'id':'records','title':'FIELD RECORDS','position':[0,0,3]},
 {'id':'settings','title':'COMMS / SETTINGS','position':[7,0,3]},
]
box('Mission board',(-6,1.8,-7.6),(4,2.4,.2),'teal')
for dx,dz in [(-1,-.2),(0,.3),(1,-.1)]:
    box('Pinned map',(-6+dx,1.8+dz,-7.45),(.7,.85,.04),'paper')
box('Mission desk',(-6,.85,-6),(4,.16,1.5),'wood')
for x in [-7.5,-4.5]: box('Desk leg',(x,.42,-6),(.12,.84,1.2),'steel')
box('Gun cabinet',(1,1.45,-7.5),(4,2.9,1),'steel')
for x in [-.4,.3,1,1.7,2.4]:
    box('Rifle receiver',(x,1.7,-6.92),(.14,.85,.14),'teal')
    box('Rifle barrel',(x,2.4,-6.92),(.07,.65,.08),'edge')
for x,z in [(6,-6),(8,-6),(7,-4.2)]:
    box('Supply chest',(x,.6,z),(1.6,1.2,1.2),'teal')
    for dx in [-.55,.55]: box('Chest band',(x+dx,.61,z),(.12,1.23,1.23),'steel')
box('Laboratory bench',(-7,1,2),(4,.2,1.5),'edge')
for x in [-8.5,-5.5]: box('Lab leg',(x,.5,2),(.15,1,1.3),'steel')
for x in [-8,-7,-6]:
    box('Sample housing',(x,1.4,2),(.45,.6,.45),'teal')
    box('Sample glow',(x,1.4,2.25),(.25,.35,.035),'screen')
box('Archive cabinet',(0,.9,3),(2.8,1.8,1.2),'steel')
for y in [.3,.8,1.3]:
    box('Archive drawer',(0,y,3.62),(2.5,.4,.08),'teal')
    box('Drawer handle',(0,y,3.71),(.4,.05,.08),'edge')
box('Radio desk',(7,.85,3),(3.6,.2,1.5),'wood')
for x in [5.6,8.4]: box('Radio leg',(x,.42,3),(.12,.84,1.2),'steel')
box('Terminal',(6.6,1.4,3),(1.1,.85,.5),'steel')
box('Terminal screen',(6.6,1.4,3.26),(.9,.6,.02),'screen')
box('Radio',(7.8,1.25,3),(.8,.5,.5),'teal')
for x in [-9,9]:
    box('Bunk frame',(x,.45,6),(1.5,.12,3),'steel')
    box('Bunk mattress',(x,.62,6),(1.4,.25,2.8),'teal')
box('Center rug',(0,.065,-1),(5,.03,3),'teal')
for dx in [-.8,.8]: box('Rug stripe',(dx,.085,-1),(.05,.015,2.8),'paper')

bpy.ops.object.select_all(action='DESELECT')
for obj in collection.objects: obj.select_set(True)
bpy.context.view_layer.objects.active=next(iter(collection.objects))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'assets/safehouse_source.blend'))
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/models/safehouse.glb'),export_format='GLB',use_selection=True,export_apply=True)
(ROOT/'assets/safehouse_stations.json').write_text(json.dumps(stations,indent=2))
print('SAFEHOUSE_EXPORTED',len(collection.objects),'editable objects / 6 stations')
