"""Assemble Chapter 01 from the shared Blender module collection, never remake assets."""
import bpy, json, math, contextlib, io
from pathlib import Path
from mathutils import Matrix, Vector
ROOT=Path('D:/Zombied')
manifest=json.loads((ROOT/'assets/modular_library.json').read_text())
kit={entry['id']:entry for entry in manifest['modules']}
library=bpy.data.collections.get('Zombied Modular Library')
if library is None: raise RuntimeError('Open modular_library_source.blend before assembling maps')
library.hide_viewport=True

def xyz(p): return (p[0],-p[2],p[1])
def transform(p,location,yaw):
    a=math.radians(yaw); c=math.cos(a); s=math.sin(a)
    return [location[0]+p[0]*c+p[2]*s,location[1]+p[1],location[2]-p[0]*s+p[2]*c]

maps={}
def begin(id,title,indoor=False):
    maps[id]={'title':title,'size':[32,30],'weather':'indoor' if indoor else 'rain','module_instances':[],'colliders':[],'lights':[]}
def place(id,module,position,yaw=0):
    maps[id]['module_instances'].append({'module':module,'position':list(position),'rotation_y':yaw})
    for collider in kit[module]['colliders']:
        size=collider['size']; a=math.radians(yaw)
        ext=[abs(math.cos(a))*size[0]+abs(math.sin(a))*size[2],size[1],abs(math.sin(a))*size[0]+abs(math.cos(a))*size[2]]
        maps[id]['colliders'].append({'name':module+' / '+str(len(maps[id]['colliders'])),'position':transform(collider['position'],position,yaw),'size':ext})
def light(id,p,color=(.38,.8,.72),energy=3,radius=9):
    maps[id]['lights'].append({'position':list(p),'color':list(color),'energy':energy,'range':radius})
def frame(id,floor='road_plain'):
    for x in [-12,-6,0,6,12]:
        for z in [-12,-6,0,6,12]: place(id,floor,(x,0,z))
    for x in [-12,-8,-4,4,8,12]: place(id,'wall_panel',(x,0,-14))
    for z in [-12,-8,-4,0,4,8,12]: place(id,'wall_window',(-14,0,z),90)
    for x in [-12,-9,-6,-3,0,3,6,9,12]: place(id,'low_barrier',(x,0,14))
    for z in [-12,-9,-6,-3,0,3,6,9,12]: place(id,'low_barrier',(14,0,z),90)
    place(id,'evac_sign',(0,0,-12),180)

begin('chapter_street','RAIN STREET')
frame('chapter_street')
for x in [-8,8]: place('chapter_street','apartment_block',(x,0,-10.8))
place('chapter_street','shop_front',(-10.8,0,-1),90)
place('chapter_street','alley_stairs',(-10,0,7),90)
for z in [-9,-3,3,9]: place('chapter_street','sidewalk',(-11,0,z))
for x,z in [(10,-8),(10,5),(-11,8)]:
    place('chapter_street','street_lamp',(x,0,z)); light('chapter_street',(x,4,z),(1,.53,.25),4,9)
place('chapter_street','road_crossing',(0,.01,-2))
place('chapter_street','district_sign',(-8,0,10))
place('chapter_street','alley_pipe',(-12,0,-6))
place('chapter_street','small_tree',(10,0,10))

begin('chapter_shop','LAST LIGHT CONVENIENCE')
frame('chapter_shop')
place('chapter_shop','shop_front',(-5,0,-10.8))
place('chapter_shop','pharmacy_front',(5,0,-10.8))
for x in [-6,0,6]:
    for z in [-3,3]: place('chapter_shop','shelf',(x,0,z),90 if x==0 else 0)
for x,z in [(-10,-5),(-10,5),(10,4),(10,-5)]:
    place('chapter_shop','garage_light',(x,0,z)); light('chapter_shop',(x,3.6,z),(.3,.85,.75),4,11)
place('chapter_shop','pharmacy_sign',(-9,0,9))
for p in [(-10,0,0),(10,0,9)]: place('chapter_shop','planter',p)
place('chapter_shop','supply_crate',(-6,0,9))

begin('chapter_apartments','APARTMENT COURTYARD')
frame('chapter_apartments')
for x in [-8,8]: place('chapter_apartments','apartment_red',(x,0,-10.8))
place('chapter_apartments','apartment_block',(-11,0,-2),90)
for x,z in [(-6,-4),(6,-4),(-6,5),(6,5)]:
    place('chapter_apartments','planter',(x,0,z)); place('chapter_apartments','small_tree',(x,0,z))
for x in [-10,10]:
    place('chapter_apartments','street_lamp',(x,0,6)); light('chapter_apartments',(x,4,6),(1,.5,.25),4,12)
for z in [-6,0,6]: place('chapter_apartments','wall_vines',(-13.7,1,z),90)
place('chapter_apartments','chain_fence',(0,0,-6))
place('chapter_apartments','alley_pipe',(-7,0,-8))

begin('chapter_garage','UNDERGROUND PARKING',True)
frame('chapter_garage','parking_slab')
for x in [-8,8]:
    for z in [-7,-1,5]:
        place('chapter_garage','garage_column',(x,0,z))
        place('chapter_garage','garage_light',(x,0,z))
        light('chapter_garage',(x,3.5,z),(.3,.75,.7),5,10)
for x,z,yaw in [(-5,-7,90),(5,-3,90),(-5,4,90),(5,8,90)]: place('chapter_garage','utility_van',(x,0,z),yaw)
for z in [-8,0,8]: place('chapter_garage','alley_pipe',(-13.5,0,z),90)
place('chapter_garage','district_sign',(10,0,10))

begin('chapter_fuel','NORTHLINE GAS STATION')
frame('chapter_fuel')
place('chapter_fuel','station_canopy',(0,0,-1))
place('chapter_fuel','shop_front',(-6,0,-10.5))
place('chapter_fuel','pharmacy_front',(5,0,-10.5))
for x in [-10,10]:
    place('chapter_fuel','street_lamp',(x,0,4)); light('chapter_fuel',(x,4,4),(1,.5,.22),5,12)
place('chapter_fuel','evac_sign',(10,0,10))
for p in [(-10,0,-5),(10,0,-5)]: place('chapter_fuel','supply_crate',p)

begin('chapter_evac','EVACUATION TERMINAL')
frame('chapter_evac')
place('chapter_evac','landing_pad',(0,.015,-1))
for x in [-8,7]: place('chapter_evac','checkpoint_bunker',(x,0,-10.5))
for z in [-7,-1,5]:
    place('chapter_evac','chain_fence',(-11,0,z),90)
    place('chapter_evac','metal_gate',(11,0,z),90)
for x,z in [(-9,9),(9,9),(-9,-7),(9,-7)]:
    place('chapter_evac','street_lamp',(x,0,z)); light('chapter_evac',(x,4,z),(.35,.8,.75),5,12)
for x in [-7,7]: place('chapter_evac','supply_crate',(x,0,4))

for id,data in maps.items():
    for c in bpy.data.collections:
        if c.name.startswith('Chapter / '): c.hide_viewport=True
    old=bpy.data.collections.get('Chapter / '+id)
    if old:
        for obj in list(old.objects): bpy.data.objects.remove(obj,do_unlink=True)
        bpy.data.collections.remove(old)
    collection=bpy.data.collections.new('Chapter / '+id)
    bpy.context.scene.collection.children.link(collection)
    for index,placement in enumerate(data['module_instances']):
        root=bpy.data.objects.new(placement['module']+' / '+str(index),None); collection.objects.link(root)
        root.location=xyz(placement['position']); root.rotation_euler.z=-math.radians(placement['rotation_y'])
        source=bpy.data.objects.get(placement['module'])
        if source is None: raise RuntimeError('Missing shared module '+placement['module'])
        for child in source.children:
            clone=child.copy(); clone.data=child.data
            collection.objects.link(clone)
            clone.parent=root; clone.matrix_parent_inverse=Matrix.Identity(4)
            clone.matrix_basis=child.matrix_basis.copy()
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    clones=[]; deps=bpy.context.evaluated_depsgraph_get()
    for obj in list(collection.objects):
        if obj.type not in {'MESH','FONT'}: continue
        mesh=bpy.data.meshes.new_from_object(obj.evaluated_get(deps))
        clone=bpy.data.objects.new('Export '+id,mesh); bpy.context.scene.collection.objects.link(clone)
        clone.matrix_world=obj.matrix_world.copy(); clone.select_set(True); clones.append(clone)
    bpy.context.view_layer.objects.active=clones[0]; bpy.ops.object.join()
    joined=bpy.context.object; joined.name=id
    with contextlib.redirect_stdout(io.StringIO()):
        bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/models'/f'{id}.glb'),export_format='GLB',use_selection=True,export_apply=True)
    data['triangles']=sum(len(p.vertices)-2 for p in joined.data.polygons)
    data['module_count']=len(data['module_instances'])
    bpy.data.objects.remove(joined,do_unlink=True)
    (ROOT/'assets'/f'{id}_layout.json').write_text(json.dumps(data,indent=2))
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'assets'/f'{id}_source.blend'))
    print('CHAPTER_MAP_EXPORTED',id,data['module_count'],'module placements /',data['triangles'],'triangles')
