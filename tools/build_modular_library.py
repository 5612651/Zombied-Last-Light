"""Reusable meter-based Blender kit; editable source and batched GLB per module."""
import bpy, math, json, random, contextlib, io
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/Zombied')
OUT=ROOT/'assets/models/kit'
OUT.mkdir(parents=True,exist_ok=True)
random.seed(1817)
old=bpy.data.collections.get('Zombied Modular Library')
if old:
    for obj in list(old.objects): bpy.data.objects.remove(obj,do_unlink=True)
    bpy.data.collections.remove(old)
collection=bpy.data.collections.new('Zombied Modular Library')
bpy.context.scene.collection.children.link(collection)

def xyz(p): return (p[0],-p[2],p[1])
def material(name,color,metal=0,emission=0):
    mat=bpy.data.materials.new('Kit / '+name)
    mat.diffuse_color=(*color,1)
    mat.use_nodes=True
    shader=mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value=(*color,1)
    shader.inputs['Roughness'].default_value=.58
    shader.inputs['Metallic'].default_value=metal
    if emission:
        shader.inputs['Emission Color'].default_value=(*color,1)
        shader.inputs['Emission Strength'].default_value=emission
    return mat
M={key:material(key,*args) for key,args in {
 'concrete':((.22,.28,.24),), 'edge':((.38,.4,.32),), 'road':((.045,.07,.065),.2),
 'steel':((.055,.085,.075),.65), 'teal':((.055,.25,.23),.3), 'rust':((.42,.17,.075),.4),
 'glass':((.045,.12,.13),.6), 'rubber':((.015,.025,.02),), 'paper':((.65,.61,.4),),
 'green':((.11,.24,.12),), 'warm':((1,.46,.15),.1,3), 'cold':((.3,.8,.73),.1,2),
}.items()}
current=[]
manifest=[]
colliders=[]

def link(obj):
    for owner in list(obj.users_collection): owner.objects.unlink(obj)
    collection.objects.link(obj)
    current.append(obj)
    return obj

def box(name,pos,size,mat='concrete',bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1,location=xyz(pos))
    obj=link(bpy.context.object); obj.name=name
    obj.dimensions=(size[0],size[2],size[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    obj.data.materials.append(M[mat])
    if bevel:
        modifier=obj.modifiers.new('Edge wear','BEVEL'); modifier.width=bevel; modifier.segments=1
    return obj

def cylinder(name,pos,radius,height,mat='steel',vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=height,location=xyz(pos))
    obj=link(bpy.context.object); obj.name=name; obj.data.materials.append(M[mat]); return obj

def solid(pos,size): colliders.append({'position':list(pos),'size':list(size)})
def text(body,pos,size=.28,mat='paper'):
    bpy.ops.object.text_add(location=xyz(pos),rotation=(math.pi/2,0,0))
    obj=link(bpy.context.object); obj.name='Lettering / '+body
    obj.data.body=body; obj.data.size=size; obj.data.extrude=.002; obj.data.materials.append(M[mat])

def export(id,category,size):
    origin=Vector(xyz(((len(manifest)%7)*16,0,(len(manifest)//7)*16)))
    root=bpy.data.objects.new(id,None); collection.objects.link(root)
    for obj in current: obj.parent=root
    root.location=origin
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    copies=[]
    deps=bpy.context.evaluated_depsgraph_get()
    for obj in current:
        mesh=bpy.data.meshes.new_from_object(obj.evaluated_get(deps))
        clone=bpy.data.objects.new('Export / '+id,mesh); bpy.context.scene.collection.objects.link(clone)
        clone.matrix_world=obj.matrix_world.copy(); clone.location-=origin
        clone.select_set(True); copies.append(clone)
    bpy.context.view_layer.objects.active=copies[0]
    bpy.ops.object.join()
    joined=bpy.context.object; joined.name=id
    with contextlib.redirect_stdout(io.StringIO()):
        bpy.ops.export_scene.gltf(filepath=str(OUT/(id+'.glb')),export_format='GLB',use_selection=True,export_apply=True)
    triangles=sum(len(poly.vertices)-2 for poly in joined.data.polygons)
    manifest.append({'id':id,'category':category,'path':'res://assets/models/kit/'+id+'.glb','size':list(size),'pivot':'ground-center','colliders':list(colliders),'triangles':triangles,'source_objects':len(current)})
    bpy.data.objects.remove(joined,do_unlink=True)
    current.clear(); colliders.clear()

for id,paint in [('road_plain','plain'),('road_straight','lane'),('road_crossing','crossing'),('parking_slab','parking'),('landing_pad','pad')]:
    box('Asphalt',(0,-.07,0),(6,.14,6),'road')
    if paint=='lane':
        for z in [-2,0,2]: box('Lane dash',(0,.008,z),(.13,.02,.9),'paper',0)
    if paint=='crossing':
        for z in [-2,-1,0,1,2]: box('Crosswalk',(0,.008,z),(4.8,.02,.5),'paper',0)
    if paint=='parking':
        for x in [-2.5,2.5]: box('Parking line',(x,.008,0),(.1,.02,5.5),'paper',0)
        box('Parking stop',(0,.008,-2.5),(5,.02,.1),'paper',0)
    if paint=='pad':
        for x in [-1,1]: box('Landing H',(x,.008,0),(.25,.02,3),'paper',0)
        box('Landing H',(0,.008,0),(2,.02,.25),'paper',0)
        for x in [-2.8,2.8]: box('Landing boundary',(x,.008,0),(.12,.02,5.6),'warm',0)
        for z in [-2.8,2.8]: box('Landing boundary',(0,.008,z),(5.6,.02,.12),'warm',0)
    export(id,'Road',(6,.14,6))

for id,wide in [('sidewalk',2),('sidewalk_corner',4)]:
    box('Sidewalk',(0,.045,0),(wide,.09,4),'concrete')
    for z in [-1.5,-.5,.5,1.5]: box('Paving seam',(0,.093,z),(wide,.008,.018),'steel',0)
    box('Kerb',(-wide*.5+.08,.07,0),(.16,.14,4),'edge')
    export(id,'Sidewalk',(wide,.14,4))

for id in ['wall_panel','wall_window','garage_column','low_barrier']:
    if id=='garage_column':
        box('Column',(0,2.2,0),(.7,4.4,.7),'concrete'); solid((0,2.2,0),(.7,4.4,.7))
        for y in [.5,.9,1.3]: box('Safety stripe',(0,y,.36),(.72,.18,.025),'paper')
        size=(.8,4.4,.8)
    elif id=='low_barrier':
        box('Concrete barrier',(0,.45,0),(2.4,.9,.65),'edge'); solid((0,.45,0),(2.4,.9,.65)); size=(2.4,.9,.65)
    else:
        box('Wall',(0,2,0),(4,4,.4),'concrete'); solid((0,2,0),(4,4,.4)); size=(4,4,.5)
        for x in [-1.9,1.9]: box('Pillar',(x,2,.1),(.2,4.2,.5),'edge')
        if id=='wall_window':
            box('Dark window',(0,2,.23),(2.4,1.6,.05),'glass')
            for x in [-.8,0,.8]: box('Mullion',(x,2,.28),(.05,1.7,.05),'steel')
    export(id,'Wall',size)

for id,title in [('shop_front','LAST LIGHT / SUPPLIES'),('pharmacy_front','PHARMACY / 24H'),('checkpoint_bunker','EVAC / CONTROL')]:
    box('Shop shell',(0,1.7,0),(6,3.4,4),'concrete'); solid((0,1.7,0),(6,3.4,4))
    box('Display',(0,1.7,2.02),(5.2,1.6,.05),'glass')
    for x in [-2.4,0,2.4]: box('Frame',(x,1.6,2.08),(.09,2.8,.1),'steel')
    box('Canopy',(0,3.1,2.2),(6.7,.16,1.6),'teal')
    box('Fascia',(0,2.8,2.35),(6.4,.45,.13),'rust')
    text(title,(-2.7,2.7,2.44),.25,'warm')
    export(id,'Shop',(6.7,3.5,5))

box('Canopy frame',(0,4.2,0),(12,.15,.3),'teal')
for z in [-3.5,3.5]: box('Canopy rim',(0,4.2,z),(12,.2,.4),'teal')
for x in [-5.5,5.5]:
    box('Canopy rim',(x,4.2,0),(.3,.2,7),'teal')
    for z in [-3,3]: box('Canopy leg',(x,2.1,z),(.25,4.2,.25),'edge'); solid((x,2.1,z),(.25,4.2,.25))
text('NORTHLINE / FUEL',(-3.4,3.9,3.75),.38,'warm')
export('station_canopy','Shop',(12,4.4,8))

for id,color,height in [('apartment_block','concrete',8),('apartment_red','rust',7.5)]:
    box('Apartment',(0,height/2,0),(6,height,4.5),color); solid((0,height/2,0),(6,height,4.5))
    for y in [1.8,4.1,6.4]:
        box('Floor trim',(0,y+.9,2.3),(6.2,.12,.25),'edge')
        for x in [-2,0,2]:
            box('Window',(x,y,2.28),(1.1,1.3,.05),'warm' if random.random()<.25 else 'glass')
            box('Sill',(x,y-.7,2.35),(1.35,.13,.35),'edge')
    box('Roof cornice',(0,height,0),(6.5,.25,5),'edge')
    export(id,'Apartment',(6.5,height+.2,5))

for id in ['alley_pipe','alley_stairs']:
    if id=='alley_pipe':
        for x in [-.2,.2]: cylinder('Utility pipe',(x,1.5,0),.08,3,'rust')
        for y in [.4,1.5,2.6]: box('Bracket',(0,y,.08),(.65,.08,.2),'steel')
        solid((0,1.5,0),(.7,3,.35)); size=(.7,3,.4)
    else:
        for i in range(7): box('Service step',(0,.12+i*.24,-1.5+i*.45),(1.8,.24,.46),'steel')
        solid((0,.9,0),(1.8,1.8,3.3)); size=(1.8,1.8,3.3)
    export(id,'Alley',size)

for id in ['chain_fence','metal_gate']:
    for x in [-2,2]: cylinder('Fence post',(x,1.2,0),.055,2.4)
    for y in [.25,1.2,2.2]: box('Fence rail',(0,y,0),(4,.05,.06),'steel')
    for x in [-1.8,-1.2,-.6,0,.6,1.2,1.8]:
        box('Fence picket',(x,1.2,0),(.025,2,.025),'steel',0)
        if id=='metal_gate': box('Gate skin',(x,1.1,0),(.5,1.65,.06),'teal')
    solid((0,1.2,0),(4,2.4,.12)); export(id,'Fence',(4.2,2.4,.15))

for id,paint in [('compact_car','rust'),('utility_van','teal')]:
    box('Body',(0,.65,0),(1.8,.65,3.6),paint)
    box('Cab',(0,1.25,-.2),(1.65,.65,2.1),'glass')
    box('Roof',(0,1.6,-.2),(1.7,.1,2.2),paint)
    for x in [-.9,.9]:
        for z in [-1.1,1.1]:
            wheel=cylinder('Wheel',(x,.38,z),.35,.18,'rubber'); wheel.rotation_euler.y=math.pi/2
    for x in [-.65,.65]: box('Headlight',(x,.7,-1.83),(.3,.18,.04),'warm')
    solid((0,.8,0),(1.8,1.6,3.6)); export(id,'Vehicle',(2,1.7,3.7))

for id in ['street_lamp','garage_light']:
    if id=='street_lamp':
        cylinder('Lamp pole',(0,2.5,0),.075,5)
        box('Lamp arm',(.55,4.9,0),(1.2,.1,.12),'steel')
        box('Lamp shade',(1,4.8,0),(.7,.15,.45),'steel')
        box('Lamp tube',(1,4.7,0),(.55,.03,.3),'warm')
        solid((0,2.5,0),(.2,5,.2)); size=(1.6,5,.5)
    else:
        box('Fixture',(0,3.8,0),(2.2,.2,.4),'steel')
        box('Tube',(0,3.68,0),(2,.04,.25),'cold'); size=(2.2,3.9,.4)
    export(id,'Lamp',size)

for id in ['trash_bin','oil_barrel','supply_crate','electric_box','fuel_pump','shelf','glass_panel']:
    if id=='oil_barrel':
        cylinder('Drum',(0,.6,0),.37,1.2,'rust')
        for y in [.2,1]: cylinder('Drum ring',(0,y,0),.385,.07,'steel')
        size=(.8,1.2,.8)
    elif id=='fuel_pump':
        box('Pump plinth',(0,.15,0),(1.1,.3,.8),'steel')
        box('Fuel pump',(0,1,0),(.95,1.4,.65),'rust')
        box('Meter',(0,1.3,.34),(.7,.4,.025),'glass')
        box('Hose',(.58,1,.03),(.08,1,.1),'rubber'); size=(1.2,1.8,.8)
    elif id=='shelf':
        for x in [-1.4,1.4]: box('Upright',(x,1.2,0),(.08,2.4,.65),'steel')
        for y in [.25,.9,1.55,2.2]:
            box('Shelf',(0,y,0),(2.9,.08,.7),'edge')
            for x in [-1,-.4,.3,1]: box('Stock',(x,y+.22,0),(.32,.35,.4),'paper' if x<0 else 'teal')
        size=(3,2.4,.8)
    elif id=='glass_panel':
        for x in [-1.25,1.25]: box('Glass frame',(x,1.1,0),(.06,2.2,.08),'steel')
        box('Pane',(0,1.1,0),(2.45,2.15,.03),'glass'); size=(2.5,2.2,.1)
    else:
        size={'trash_bin':(.8,1.1,.8),'supply_crate':(1.6,1.2,1.2),'electric_box':(1.1,1.5,.65)}[id]
        box('Housing',(0,size[1]*.5,0),size,'teal')
        for y in [.15,size[1]-.1]: box('Band',(0,y,0),(size[0]*1.03,.1,size[2]*1.03),'steel')
        if id=='electric_box': text('HIGH VOLT',(-.4,.8,.34),.12,'warm')
    solid((0,size[1]/2,0),size)
    export(id,'Shop' if id in ['fuel_pump','shelf','glass_panel'] else 'Trash',size)

for id,title in [('evac_sign','EVAC / NORTH'),('district_sign','SECTOR / 17'),('pharmacy_sign','MEDICAL / SUPPLIES')]:
    for x in [-1,1]: cylinder('Sign post',(x,1.5,0),.04,3)
    box('Signboard',(0,2.4,0),(3,.8,.15),'teal')
    text(title,(-1.3,2.28,.09),.22,'cold'); solid((0,1.5,0),(2.2,3,.2))
    export(id,'Sign',(3.1,3,.25))

for id in ['planter','small_tree','wall_vines']:
    if id=='planter':
        box('Planter',(0,.3,0),(2,.6,1),'concrete')
        for x in [-.7,-.3,.2,.7]: box('Shrub',(x,.8,0),(.5,.75,.6),'green')
        solid((0,.6,0),(2,1.2,1)); size=(2,1.2,1)
    elif id=='small_tree':
        cylinder('Trunk',(0,1.5,0),.14,3,'rust')
        for x,z in [(-.45,0),(.5,.1),(0,-.4)]:
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=xyz((x,3,z)))
            obj=link(bpy.context.object); obj.name='Tree crown'; obj.data.materials.append(M['green'])
        solid((0,1.5,0),(.4,3,.4)); size=(3,4,3)
    else:
        for x in [-.7,-.3,.2,.6]: box('Hanging vine',(x,1.5+random.random(),0),(.15,random.uniform(1,2.5),.15),'green')
        size=(2,3,.2)
    export(id,'Vegetation',size)

(ROOT/'assets/modular_library.json').write_text(json.dumps({'schema_version':1,'units':'meters','up_axis':'Y','forward_axis':'-Z','modules':manifest},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'assets/modular_library_source.blend'))
print('MODULAR_LIBRARY_COMPLETE',len(manifest),'modules /',len(set(item['category'] for item in manifest)),'categories /',sum(item['triangles'] for item in manifest),'triangles')
