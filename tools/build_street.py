"""Blender source generator. Coordinates in calls are Godot X/up Y/forward Z.
Run in Blender via MCP; exports a complete district plus reusable kit pieces.
"""
import bpy, math, random, json
from pathlib import Path
from mathutils import Vector

ROOT = Path('D:/Zombied')
OUT = ROOT / 'assets/models'
OUT.mkdir(parents=True, exist_ok=True)
random.seed(17)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):
    if c.name != 'Collection' and c.users == 0:
        bpy.data.collections.remove(c)

def material(name, color, metal=0, rough=.65, glow=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = rough
    if glow:
        p.inputs['Emission Color'].default_value = (*color, 1)
        p.inputs['Emission Strength'].default_value = glow
    return m

M = {
    'asphalt': material('Wet asphalt',(.055,.074,.071),.2,.22),
    'slab': material('Rainwashed concrete',(.23,.27,.245),.05,.5),
    'wall': material('Oxidised olive concrete',(.13,.19,.16),.15,.65),
    'edge': material('Concrete edges',(.33,.35,.29),.05,.7),
    'steel': material('Blackened steel',(.055,.085,.08),.75,.34),
    'rust': material('Weathered copper',(.32,.16,.08),.65,.5),
    'teal': material('Petrol blue paint',(.055,.23,.22),.5,.35),
    'red': material('Emergency vermilion',(.52,.11,.055),.2,.5),
    'glass': material('Smoked glass',(.025,.08,.09),.65,.15),
    'warm': material('Tungsten strip',(1,.42,.12),.1,.3,4),
    'cold': material('Fluorescent strip',(.35,.85,.8),.1,.3,3),
    'rubber': material('Rubber',(.018,.025,.023),0,.8),
    'paper': material('Old labels',(.6,.55,.36),0,.85),
}
colliders=[]
lights=[]
kit={}

def xyz(p): return (p[0],-p[2],p[1])
def box(name,p,s,mat='wall',bevel=.04,parent=None,rotation=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(p))
    o=bpy.context.object; o.name=name
    o.dimensions=(s[0],s[2],s[1]); o.rotation_euler.z=-rotation
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(M[mat])
    if bevel:
        mod=o.modifiers.new('Worn edges','BEVEL');mod.width=bevel;mod.segments=1
        bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
        o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    if parent:o.parent=parent
    return o

def cylinder(name,a,b,r,mat='steel',parent=None,vertices=10):
    av=Vector(xyz(a));bv=Vector(xyz(b));d=bv-av
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=d.length,location=(av+bv)/2)
    o=bpy.context.object;o.name=name;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();o.data.materials.append(M[mat])
    if parent:o.parent=parent
    return o

def text(name,body,p,size=.35,mat='paper'):
    bpy.ops.object.text_add(location=xyz(p),rotation=(math.pi/2,0,0))
    o=bpy.context.object;o.name=name;o.data.body=body;o.data.size=size;o.data.extrude=.004;o.data.materials.append(M[mat]);return o

def solid(name,p,s):colliders.append({'name':name,'position':p,'size':s})
def lamp(p,color,energy=4,range_=7):lights.append({'position':p,'color':color,'energy':energy,'range':range_})

# A sparse industrial street wrapped around a tiled court. Floor slab seams remain geometry.
box('Ground',(0,-.24,0),(36,.4,34),'asphalt',0)
for ix in range(-7,8):
    for iz in range(-6,7):
        if (ix>4 and iz>2) or (ix<-5 and iz<-3):continue
        x=ix*1.65;z=iz*1.65
        shade='slab' if random.random()>.12 else 'wall'
        box('Paving slab',(x,-.025+random.uniform(-.012,.012),z),(1.61,.09,1.61),shade,.015)
for x in [-13.1,13.1]:
    for z in range(-14,15,2):
        box('Raised curb',(x,.12,z),(.28,.28,1.94),'edge',.025)
for z in range(-13,14,3):
    box('Drain channel',(-12.6,.04,z),(.3,.07,1.1),'steel',.01)
    for off in [-.3,0,.3]:box('Drain slots',(-12.6,.081,z+off),(.26,.012,.045),'rubber',0)

def wall_segment(x,z,turn=False):
    sx,sz=(.6,3.96) if turn else (3.96,.6)
    box('Wall panel',(x,2.2,z),(sx,4.4,sz),'wall',.06)
    solid('Perimeter',(x,2.2,z),(sx,4.4,sz))
    box('Wall parapet',(x,4.5,z),(sx+.35,.28,sz+.35),'edge',.035)
    for t in [-1.8,1.8]:
        p=(x,2.25,z+t) if turn else (x+t,2.25,z)
        box('Buttress',p,(.82,4.6,.82),'steel',.03)
        for h in [.7,2.7,4.3]:box('Buttress collar',(p[0],h,p[2]),(.95,.15,.95),'edge',.025)
    for t in [-1.3,-.65,0,.65,1.3]:
        p=(x,4.8,z+t) if turn else (x+t,4.8,z)
        box('Uneven coping',p,(.5,random.uniform(.25,.6),.7),'edge',.02)
    if not turn:
        for y in [1,1.4]:cylinder('Wall service pipe',(x-1.7,y,z+.4),(x+1.7,y,z+.4),.065,'rust')

for x in range(-14,15,4):
    if abs(x)>2:wall_segment(x,-14)
    wall_segment(x,14)
for z in range(-10,11,4):
    wall_segment(-16,z,True);wall_segment(16,z,True)

# Gate remains traversable when the objective is complete.
for x in [-2.5,2.5]:box('Exit gate post',(x,2.6,-14),(.7,5.2,1),'steel')
box('Exit lintel',(0,5.1,-14),(5.5,.5,1.2),'edge')
text('Exit typography','NORTH / 02',(-2,4.4,-13.35),.39,'cold')
lamp((0,4.0,-12.5),[.3,.85,.8],5,9)

# Kiosk, rear warehouse and side service units use repeatable panel dimensions.
box('Kiosk shell',(8,1.8,-10.8),(8,3.6,4.5),'rust',.08)
solid('Kiosk',(8,1.8,-10.8),(8,3.6,4.5))
box('Kiosk fascia',(8,3.1,-8.45),(8.3,.65,.18),'red',.03)
text('Kiosk name','LAST LIGHT  /  SUPPLIES',(4.5,3.03,-8.3),.34,'warm')
for x in [5.3,7.1,8.9,10.7]:
    box('Service window',(x,1.9,-8.45),(1.6,1.35,.1),'glass',.02)
    box('Window light',(x,2.52,-8.3),(1.45,.07,.05),'warm',.01)
box('Kiosk counter',(8,1.17,-8.1),(8.2,.16,.8),'steel',.02)
for x in [4,12]:lamp((x,2.6,-7.9),[1,.43,.15],4,6)
for i in range(24):box('Corrugated roof',(4.1+i*.34,3.79,-10.8),(.23,.16,5.1),'edge',.02)
box('Roof ventilation',(10,4.2,-11),(1.6,.7,1.3),'steel')
for x in [9.5,9.8,10.1,10.4]:box('Vent louver',(x,4.58,-11),(.08,.06,1.05),'edge',.01)

box('Warehouse',(8,3.2,16),(14,6.4,5),'wall',.06)
for x in [2,5,8,11,14]:
    box('Warehouse window',(x,4.2,13.42),(1.7,1.15,.1),'glass')
    box('Warehouse mullion',(x,4.2,13.3),(.07,1.2,.1),'steel',0)
for x in [3,11]:box('Roller shutter',(x,1.8,13.4),(3.6,3.6,.15),'steel')
for y in [.4,.7,1,1.3,1.6,1.9,2.2,2.5,2.8,3.1]:
    for x in [3,11]:box('Shutter slat',(x,y,13.25),(3.5,.04,.05),'edge',0)
for x in [-14,14]:
    for z in [-5,2,7]:
        box('Electrical cabinet',(x,1.1,z),(1.1,2.2,1.5),'teal')
        solid('Cabinet',(x,1.1,z),(1.1,2.2,1.5))
        box('Warning label',(x,1.6,z+.77),(.4,.35,.02),'paper',0)
        cylinder('Conduit',(x,0,z),(x,3.5,z),.075,'rust')

def car(x,z,paint='teal'):
    pieces=[]
    pieces.append(box('Car chassis',(x,.55,z),(1.9,.65,4.1),paint,.17))
    pieces.append(box('Car cabin',(x,1.13,z+.2),(1.65,.7,2.1),'glass',.15))
    pieces.append(box('Car roof',(x,1.53,z+.25),(1.7,.11,1.9),paint,.08))
    for side in [-1,1]:
        for dz in [-1.3,1.3]:pieces.append(cylinder('Car wheel',(x+side*.83,.4,z+dz),(x+side*1.03,.4,z+dz),.38,'rubber'))
        pieces.append(box('Headlight',(x+side*.62,.62,z-2.07),(.4,.18,.06),'warm',.03))
    for dz in [-2.1,2.1]:pieces.append(box('Bumper',(x,.38,z+dz),(1.8,.2,.13),'steel'))
    solid('Parked car',(x,.8,z),(2,1.6,4.3))
    return pieces
car(-8,-5);car(9,5,'red')

def crate(x,z):
    pieces=[box('Supply crate',(x,.5,z),(1.1,1,1.1),'wall')]
    for off in [-.4,.4]:
        pieces.append(box('Crate straps',(x+off,.5,z),(.1,1.08,1.18),'edge',.01))
    pieces.append(box('Crate stencil',(x,1.02,z),(.35,.015,.5),'paper',0))
    return pieces
kit['supply_crate']=crate(-5,6)
for x,z in [(-6.2,6),(-5,7.2),(5,-5.5),(6.2,-5.5),(-11,-9),(11,9)]:crate(x,z);solid('Crate',(x,.5,z),(1.15,1,1.15))
solid('Crate',(-5,.5,6),(1.15,1,1.15))

def street_lamp(x,z):
    pieces=[]
    pieces.append(cylinder('Lamp mast',(x,0,z),(x,4.4,z),.085))
    pieces.append(cylinder('Lamp arm',(x,4.4,z),(x+1,4.4,z),.07))
    pieces.append(box('Lamp housing',(x+1,4.35,z),(.8,.16,.38),'steel'))
    pieces.append(box('Lamp emitter',(x+1,4.25,z),(.65,.035,.26),'warm',.01))
    box('Lamp footing',(x,.13,z),(.5,.26,.5),'edge')
    lamp((x+1,4.05,z),[1,.67,.36],5,8)
    return pieces
kit['street_lamp']=street_lamp(-10,4)
for x,z in [(12,-4),(-11,-10),(11,10)]:street_lamp(x,z)

# Fence mesh with posts and diagonal wires, service catwalk and wall vegetation.
for z in range(2,11,2):
    for y in [.45,1.1,1.75]:cylinder('Fence rail',(-13,y,z),(-13,y,z+2),.023,'steel')
    cylinder('Fence post',(-13,0,z),(-13,2.1,z),.055,'rust')
    for off in [0,.5,1,1.5]:
        cylinder('Fence mesh',(-13,.2,z+off),(-13,1.9,z+off+.5),.012,'steel',vertices=4)
        cylinder('Fence mesh',(-13,1.9,z+off),(-13,.2,z+off+.5),.012,'steel',vertices=4)
solid('Fence',(-13,1,6),( .18,2,10))
for z in range(-6,10):box('Catwalk grating',(14.6,3,z), (1.9,.12,.85),'steel',.01)
for z in [-6,0,6]:
    cylinder('Catwalk support',(14,0,z),(14,3,z),.1)
    cylinder('Catwalk rail',(13.7,4,z),(13.7,4,z+5.5),.04)
    cylinder('Catwalk railing',(13.7,3,z),(13.7,4,z),.04)
for i in range(75):
    x=random.uniform(-15,15);z=random.choice([-13.5,13.5])
    box('Wall weed',(x,random.uniform(3.6,4.6),z),(.08,random.uniform(.3,1.3),.12),'wall',0,rotation=random.uniform(-.5,.5))
for i in range(45):
    x=random.uniform(-12,12);z=random.uniform(-11,11)
    if abs(x)<3 and abs(z)<6:continue
    box('Street litter',(x,.055,z),(random.uniform(.1,.4),.018,random.uniform(.12,.5)),'paper',0,rotation=random.random()*6.28)

text('Ground marking','SECTOR 17',(-4,.07,10.5),.65,'paper').rotation_euler=(0,0,0)
# Multiple cable segments make the hanging silhouette legible.
for offset in [-.18,.18]:
    for i in range(24):
        x=-15+i*1.25;x2=x+1.25
        a=(x,5.5-1.2*(1-(x/15)**2),-5+offset)
        b=(x2,5.5-1.2*(1-(x2/15)**2),-5+offset)
        cylinder('Overhead cable',a,b,.018,'rubber',vertices=5)

scene=bpy.context.scene
scene.unit_settings.system='METRIC'
scene.world.color=(.12,.17,.15)
# Save editable Blender source, then export all geometry. Runtime lighting is in Godot.
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'assets/street_source.blend'))

def export_runtime(objects,filename,origin=None,cutaway=False):
    # Bake evaluated geometry and batch static meshes by material in the export.
    # Blender source retains all individual editable modules.
    bpy.ops.object.select_all(action='DESELECT')
    copies=[]
    depsgraph=bpy.context.evaluated_depsgraph_get()
    for original in objects:
        if original.type not in {'MESH','FONT'}:continue
        if cutaway and original.name.startswith(('Warehouse','Roller','Shutter')):continue
        mesh=bpy.data.meshes.new_from_object(original.evaluated_get(depsgraph))
        clone=bpy.data.objects.new('Batched '+original.name,mesh)
        scene.collection.objects.link(clone)
        clone.matrix_world=original.matrix_world.copy()
        if cutaway and (original.location.y < -13.4 or original.location.x > 15.4) and original.name.startswith(('Wall','Buttress','Uneven')):
            clone.scale.z*=.34;clone.location.z*=.34
        if origin:clone.location-=Vector(xyz(origin))
        clone.select_set(True);copies.append(clone)
    bpy.context.view_layer.objects.active=copies[0]
    bpy.ops.object.join()
    joined=bpy.context.object
    joined.name='District static geometry' if cutaway else filename
    bpy.ops.export_scene.gltf(filepath=str(OUT/(filename+'.glb')),export_format='GLB',use_selection=True,export_apply=True)
    bpy.data.objects.remove(joined,do_unlink=True)

base_objects=list(scene.objects)
base_colliders=list(colliders)
base_lights=list(lights)
export_runtime(base_objects,'district',cutaway=True)
for name,objects in kit.items():
    export_runtime(objects,name,origin=(-5,0,6) if name=='supply_crate' else (-10,0,4))
# Additional reusable modules, each with a local origin.
for name,prefix,origin in [('parked_car','Car',(-8,0,-5)),('fence','Fence',(-13,0,6)),('wall_panel','Wall panel',(-14,0,-14)),('paving_slab','Paving slab',(0,0,0))]:
    objects=[o for o in base_objects if o.name.startswith(prefix)]
    if name=='parked_car':objects=[o for o in objects if (o.location-Vector(xyz(origin))).length<4]
    if name=='wall_panel':objects=objects[:1]
    if name=='paving_slab':objects=[min(objects,key=lambda o:o.location.length)]
    export_runtime(objects,name,origin=origin)

def write_layout(name,c,l):
    (ROOT/('assets/'+name+'_layout.json')).write_text(json.dumps({'size':[36,34],'colliders':c,'lights':l},indent=2))
write_layout('district',base_colliders,base_lights)

# Commercial block: distinct obstacle arrangement and a row of market booths.
for x,z,title in [(-8,-3,'NIGHT MARKET'),(8,4,'PHARMACY'),(-8,6,'REPAIR / 24H')]:
    box('Market booth',(x,1.5,z),(4,3,3),'wall')
    box('Booth glass',(x,1.7,z+1.55),(3.3,1.2,.12),'glass')
    box('Booth awning',(x,3.1,z+.3),(4.6,.2,4.2),'teal')
    box('Booth fascia',(x,2.7,z+1.65),(4.2,.4,.1),'red')
    text('Booth lettering',title,(x-1.7,2.62,z+1.72),.25,'warm')
    solid('Market booth',(x,1.5,z),(4,3,3))
    lamp((x,2.6,z+2),[1,.55,.25],4,6)
commercial_objects=[o for o in scene.objects if o not in base_objects]
commercial_base=[o for o in base_objects if not o.name.startswith(('Car','Bumper','Headlight'))]
export_runtime(commercial_base+commercial_objects,'commercial',cutaway=True)
write_layout('commercial',[c for c in colliders if c['name']!='Parked car'],lights)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'assets/commercial_source.blend'))

# Final court: open centre, emergency barricades and a service gantry.
for x in [-10,10]:
    for z in [-6,2,8]:
        box('Quarantine barrier',(x,.55,z),(3,1.1,.65),'red')
        for dx in [-1,-.5,0,.5,1]:
            box('Hazard stripes',(x+dx,.58,z+.34),(.22,.9,.04),'paper',.005,rotation=.2)
for x in [-11,11]:
    box('Gantry footing',(x,3,-6),(.65,6,.65),'steel')
box('Gantry span',(0,6.1,-6),(23,.6,.65),'rust')
for x in range(-10,11,2):
    box('Gantry warning lamp',(x,5.75,-6),(.3,.1,.35),'red')
arena_objects=[o for o in scene.objects if o not in base_objects and o not in commercial_objects]
arena_base=[o for o in base_objects if not o.name.startswith(('Car','Bumper','Headlight','Supply crate','Crate straps','Crate stencil'))]
export_runtime(arena_base+arena_objects,'arena',cutaway=True)
arena_colliders=[c for c in base_colliders if c['name'] not in {'Parked car','Crate'}]
for x in [-10,10]:
    for z in [-6,2,8]:arena_colliders.append({'name':'Barricade','position':[x,.55,z],'size':[3,1.1,.65]})
write_layout('arena',arena_colliders,base_lights)
for o in commercial_objects:bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'assets/arena_source.blend'))
print(json.dumps({'objects':len(base_objects),'colliders':len(base_colliders),'lights':len(base_lights),'export':str(OUT)}))
