"""Authored Blender assets for the v5 visual pass; preserves all v4 sources."""
import bpy, math, json, sys, random, io, contextlib
from pathlib import Path
from mathutils import Vector, Matrix
ROOT=Path('D:/Zombied')
random.seed(51017)
MODE=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'icons'
def xyz(p): return Vector((p[0],-p[2],p[1]))
def material(name,color,metal=.2,rough=.45,glow=0):
    m=bpy.data.materials.get('V5 '+name) or bpy.data.materials.new('V5 '+name)
    if m.node_tree is None:m.use_nodes=True
    node=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    node.inputs['Base Color'].default_value=(*color,1)
    node.inputs['Metallic'].default_value=metal;node.inputs['Roughness'].default_value=rough
    node.inputs['Emission Color'].default_value=(*color,1);node.inputs['Emission Strength'].default_value=glow
    m.diffuse_color=(*color,1);return m
M={}
def palette():
    global M
    M={k:material(k,*v) for k,v in {'navy':((.027,.055,.08),.65,.25),'steel':((.27,.35,.4),.85,.27),'ceramic':((.64,.7,.66),.1,.6),'gold':((.6,.32,.09),.85,.25),'glass':((.025,.17,.22),.65,.16),'brick':((.26,.085,.045),.03,.84),'rubber':((.012,.018,.02),.02,.8),'cyan':((.08,.65,.85),.2,.2,3),'orange':((1,.28,.035),.2,.3,2),'green':((.12,.7,.35),.3,.3,1.5),'purple':((.6,.09,.95),.3,.3,2)}.items()}
root=None
def attach(o,mat):
    if root:o.parent=root
    o.data.materials.append(M[mat]);return o
def box(name,p,s,mat='navy',bevel=.025):
    # Direct mesh construction keeps large detail passes inexpensive.
    x,y,z=[a/2 for a in s]
    verts=[xyz(v) for v in [(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)]]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)]);mesh.update()
    o=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(o);o.location=xyz(p)
    if bevel:
        b=o.modifiers.new('Machined edge','BEVEL');b.width=min(bevel,min(s)*.2);b.segments=3
    return attach(o,mat)
def cyl(name,p,r,h,mat='steel',axis='Y',vertices=20):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=h,location=xyz(p));o=bpy.context.object;o.name=name
    if axis=='X':o.rotation_euler.y=math.pi/2
    elif axis=='Z':o.rotation_euler.x=math.pi/2
    b=o.modifiers.new('Rim bevel','BEVEL');b.width=min(.018,r*.12);b.segments=2
    return attach(o,mat)
def sphere(name,p,r,mat='cyan'):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,radius=r,location=xyz(p));o=bpy.context.object;o.name=name
    for poly in o.data.polygons:poly.use_smooth=True
    return attach(o,mat)
def torus(p,r,mat='gold',thickness=.045):
    bpy.ops.mesh.primitive_torus_add(major_segments=36,minor_segments=8,location=xyz(p),major_radius=r,minor_radius=thickness)
    return attach(bpy.context.object,mat)
def studio(scene,focus=(0,0,0),scale=3.0,res=384):
    world=bpy.data.worlds.new('V5 studio');world.use_nodes=True
    bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.06,.09,.15,1);bg.inputs[1].default_value=.45;scene.world=world
    focus=Vector(focus)
    for name,p,power,color in [('Key',(-3,-4,6),650,(.65,.85,1)),('Warm',(4,-1,4),500,(1,.55,.2)),('Rim',(0,4,4),900,(.25,.7,1))]:
        d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=4;d.color=color
        o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=focus+Vector(p);o.rotation_euler=(focus-o.location).to_track_quat('-Z','Y').to_euler()
    d=bpy.data.cameras.new('V5 camera');d.type='ORTHO';d.ortho_scale=scale
    o=bpy.data.objects.new('V5 camera',d);scene.collection.objects.link(o);o.location=focus+Vector((3,-4,3));o.rotation_euler=(focus-o.location).to_track_quat('-Z','Y').to_euler();scene.camera=o
    scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=res;scene.render.resolution_y=res;scene.render.resolution_percentage=100
    scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
def render_icons():
    global root
    out=ROOT/'assets/ui/icons';out.mkdir(parents=True,exist_ok=True)
    names=['health','armor','dash','grenade','briefing','armory','crates','research','records','settings','ballistic','shotgun','fire','electric','explosion','survival','supply','blueprint']
    for name in names:
        scene=bpy.data.scenes.new('Icon '+name);bpy.context.window.scene=scene;palette();root=None
        if name in ['health','survival']:
            box('Medical case',(0,0,0),(1.25,.8,.55),'ceramic',.12)
            box('Cross vertical',(0,.05,.3),(.22,.58,.05),'green');box('Cross horizontal',(0,.05,.31),(.6,.21,.05),'green')
            for x in [-.52,.52]:box('Case latch',(x,-.1,.3),(.13,.2,.08),'gold')
        elif name=='armor':
            box('Armor plate',(0,0,0),(1.05,1.3,.25),'steel',.12)
            for x in [-.35,0,.35]:box('Ceramic segment',(x,.1,.17),(.23,.8,.11),'ceramic',.08)
            box('Core',(0,-.3,.25),(.36,.2,.07),'cyan')
        elif name in ['dash','electric']:
            for i in range(3):
                o=box('Energy chevron',(-.3+i*.3,-.3+i*.26,0),(.55,.19,.22),'cyan' if name=='dash' else 'purple');o.rotation_euler.y=.25;o.rotation_euler.z=-.5
        elif name=='grenade':
            s=sphere('Grenade body',(0,-.15,0),.5,'navy');s.scale=(.8,.8,1.1)
            for y in [-.3,0,.3]:torus((0,y,0),.36,'steel',.035)
            cyl('Fuse cap',(0,.46,0),.18,.2,'gold');box('Lever',(.12,.6,0),(.25,.13,.72),'ceramic')
            torus((-.26,.63,0),.16,'gold',.025)
        elif name in ['crates','supply']:
            box('Armored supply case',(0,0,0),(1.3,.8,.85),'navy',.09)
            for x in [-.47,.47]:box('Reinforced band',(x,0,0),(.15,.9,.94),'gold')
            for x in [-.24,.24]:box('Latch',(x,0,.46),(.12,.22,.08),'cyan')
            box('Handle',(0,.5,0),(.46,.1,.17),'steel')
        elif name=='research':
            cyl('Reactor base',(0,-.55,0),.5,.2,'navy');cyl('Glass chamber',(0,0,0),.3,.9,'glass')
            for y in [-.4,-.2,0,.2,.4]:torus((0,y,0),.33,'gold',.025)
            cyl('Energy',(0,0,0),.13,.85,'cyan');cyl('Cap',(0,.54,0),.4,.15,'steel')
        elif name=='records':
            torus((0,0,0),.52,'gold',.11);cyl('Medal',(0,0,0),.43,.13,'gold')
            box('Medal center',(0,.13,0),(.22,.2,.28),'cyan')
            for x in [-.3,.3]:box('Ribbon',(x,-.5,0),(.28,.75,.1),'navy')
        elif name=='settings':
            torus((0,0,0),.39,'steel',.16)
            for i in range(10):
                a=i*math.tau/10;o=box('Gear tooth',(math.sin(a)*.53,0,math.cos(a)*.53),(.24,.27,.24),'gold');o.rotation_euler.z=a
            cyl('Hub',(0,0,0),.17,.35,'cyan')
        elif name in ['briefing','blueprint']:
            for i in [-1,0,1]:
                o=box('Map fold',(i*.42,0,0),(.43,.85,.07),'ceramic' if name=='briefing' else 'glass');o.rotation_euler.y=i*.22
            for i in range(4):box('Route',(-.45+i*.27,.12 if i%2 else -.1,.1),(.15,.13,.04),'orange' if name=='briefing' else 'cyan')
            cyl('Locator',(.42,.3,.13),.1,.12,'gold')
        elif name in ['armory','ballistic','shotgun']:
            for x in ([-.23,.23] if name=='shotgun' else [-.28,0,.28]):
                cyl('Cartridge',(x,0,0),.12,.86,'gold');sphere('Projectile',(x,.44,0),.12,'ceramic');cyl('Rim',(x,-.45,0),.14,.07,'navy')
        elif name=='fire':
            for x,y,r in [(0,-.1,.43),(-.28,.05,.24),(.2,.3,.25),(0,.62,.13)]:
                o=sphere('Plasma flame',(x,y,0),r,'orange' if y<.3 else 'gold');o.scale.z=1.5
        elif name=='explosion':
            sphere('Core',(0,0,0),.26,'orange')
            for i in range(8):
                a=i*math.tau/8;o=box('Burst',(math.sin(a)*.4,math.cos(a)*.4,0),(.13,.44,.14),'gold');o.rotation_euler.y=a
        studio(scene,scale=2.25,res=320);scene.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True)
        print('ICON_READY',name,flush=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'assets/ui_icons_v5.blend'))
def environment():
    global root
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/modular_library_source.blend'));palette()
    library=bpy.data.collections['Zombied Modular Library'];library.hide_viewport=False
    for obj in list(library.objects):
        for mod in obj.modifiers:
            if mod.type=='BEVEL':mod.segments=3
    for root in [o for o in library.objects if o.type=='EMPTY']:
        kind=root.name
        if kind.startswith('road') or kind in ['parking_slab','landing_pad']:
            for child in root.children:
                if child.name.startswith('Asphalt'):
                    for modifier in list(child.modifiers):
                        if modifier.type=='BEVEL':child.modifiers.remove(modifier)
        if kind in ['shop_front','pharmacy_front','checkpoint_bunker']:
            for x in [-2.65,-1.35,1.35,2.65]:
                box('Display frame',(x,1.65,2.12),(.07,2.2,.12),'steel')
            for x in [-1.9,1.9]:
                box('Deep display',(x,1.55,2.06),(1.15,1.6,.08),'glass')
                box('Display glow',(x,2.3,2.14),(1.02,.035,.04),'cyan')
                for j in range(3):box('Display shelf',(x,.9+j*.4,2.15),(1.1,.04,.14),'gold')
            for x in [-3.07,3.07]:box('Brick pier',(x,1.6,1.95),(.18,3.2,.3),'brick')
            for y in [.45,1,1.55,2.1]:box('Door handle',(.18,y,2.21),(.035,.22,.045),'gold')
            for x in [-2.8,-2,-1.2,-.4,.4,1.2,2,2.8]:box('Awning rib',(x,3.21,2.25),(.05,.1,1.5),'steel')
            for x in [-1.5,1.4]:
                box('Rooftop HVAC',(x,3.7,-.4),(1.2,.6,.9),'steel')
                for j in range(7):box('HVAC slat',(x-.48+j*.16,3.78,.08),(.05,.35,.04),'navy')
            box('Entrance light',(0,2.6,2.25),(1.5,.04,.15),'orange')
        elif kind.startswith('apartment'):
            for child in root.children:
                if child.name.startswith('Apartment') and child.type=='MESH':
                    child.data=child.data.copy();child.data.materials.clear();child.data.materials.append(M['brick'])
            for y in [1.8,4.1,6.4]:
                for x in [-2,0,2]:
                    for side in [-1,1]:box('Recessed window frame',(x+side*.59,y,2.36),(.07,1.48,.13),'steel')
                    box('Window transom',(x,y+.7,2.36),(1.25,.07,.13),'steel')
                    box('Window divider',(x,y,2.37),(.045,1.3,.06),'gold')
                    if (int(y*10)+int(x))%3==0:
                        box('AC unit',(x,y-.8,2.55),(.85,.4,.55),'ceramic')
                        for j in range(5):box('AC grille',(x-.31+j*.15,y-.8,2.84),(.035,.27,.035),'steel')
                box('Balcony slab',(0,y-.7,2.65),(2.2,.12,.85),'steel')
                for x in [-1,-.5,0,.5,1]:cyl('Balcony baluster',(x,y-.3,3.04),.022,.75,'steel',vertices=8)
                box('Balcony handrail',(0,y+.1,3.04),(2.2,.045,.06),'gold')
            for x in [-2.9,2.9]:cyl('Rainwater pipe',(x,3.5,2.48),.065,7,'gold')
            for x in [-1.7,1.7]:
                box('Roof vent',(x,8.25,-.7),(.8,.5,.8),'steel');cyl('Vent cap',(x,8.58,-.7),.35,.15,'steel')
        elif kind in ['compact_car','utility_van']:
            for x in [-.85,.85]:
                for z in [-.9,.7]:box('Door pillar',(x,1.18,z),(.07,.75,.08),'steel')
                for z in [-.4,.65]:box('Door handle',(x,.92,z),(.08,.055,.26),'gold')
                box('Running board',(x,.42,0),(.18,.1,2.65),'steel')
                box('Side mirror',(x*1.15,1.18,-.9),(.24,.16,.25),'navy')
            for x in [-.91,.91]:
                for z in [-1.1,1.1]:
                    cyl('Wheel alloy',(x,.38,z),.22,.2,'steel',axis='X',vertices=24)
                    cyl('Axle cap',(x*1.12,.38,z),.09,.025,'gold',axis='X')
            for z in [-1.83,1.83]:box('Bumper',(0,.43,z),(1.76,.17,.12),'steel')
            for x in [-.6,.6]:box('Rear lamp',(x,.8,1.83),(.3,.13,.04),'orange')
            for x in [-.5,-.25,0,.25,.5]:box('Radiator grille',(x,.65,-1.84),(.09,.25,.06),'navy')
        elif kind=='sidewalk':
            for x in [-1,-.5,0,.5,1]:box('Paving seam',(x,.105,0),(.018,.012,5.8),'navy',0)
        elif kind=='fuel_pump':
            for x in [-.4,.4]:box('Protective pump trim',(x,1.05,.36),(.07,1.25,.08),'ceramic')
            box('Digital display',(0,1.3,.37),(.66,.34,.04),'glass')
            for i in range(4):box('Meter segment',(-.21+i*.14,1.32,.399),(.08,.14,.018),'cyan')
            for x in [-.23,0,.23]:cyl('Control button',(x,.87,.39),.043,.025,'orange',axis='Z')
            for y in [.5,.62]:box('Service panel',(0,y,.36),(.55,.035,.03),'steel')
            box('Nozzle grip',(.56,1.4,.05),(.13,.32,.2),'steel')
        elif kind=='oil_barrel':
            cyl('Recessed lid',(0,1.21,0),.33,.025,'navy')
            cyl('Cap bung',(.18,1.235,0),.055,.035,'gold')
            box('Hazard plate',(0,.64,.373),(.3,.34,.025),'gold')
            box('Warning mark',(0,.65,.392),(.04,.22,.02),'navy')
        elif kind in ['electric_box','supply_crate','trash_bin']:
            width,height,depth={'electric_box':(1.1,1.5,.65),'supply_crate':(1.6,1.2,1.2),'trash_bin':(.8,1.1,.8)}[kind]
            box('Inset service door',(0,height*.53,depth*.51),(width*.8,height*.7,.04),'steel')
            for x in [-width*.35,width*.35]:
                for y in [height*.2,height*.8]:cyl('Fastener',(x,y,depth*.55),.025,.03,'gold',axis='Z',vertices=10)
            if kind=='electric_box':
                for y in [.5,.62,.74,.86]:box('Vent slot',(0,y,.36),(.58,.035,.025),'navy')
                box('Status display',(0,1.15,.37),(.45,.15,.025),'cyan')
            elif kind=='supply_crate':
                for x in [-.57,.57]:box('Armored case band',(x,.6,0),(.15,1.27,1.3),'gold')
                box('Case latch',(0,.7,.64),(.24,.19,.06),'cyan')
            else:
                box('Bin lid',(0,1.16,0),(.86,.12,.86),'navy',.05)
        elif kind in ['wall_panel','wall_window']:
            for y in [.5,1.1,1.7,2.3,2.9,3.5]:box('Masonry course',(0,y,.22),(3.75,.025,.03),'brick',0)
    # New children belong to their authored module, not to an unrelated Scene collection.
    for obj in list(bpy.context.scene.objects):
        if obj.parent and obj.parent.name in library.objects and obj.name not in library.objects:
            for c in list(obj.users_collection):c.objects.unlink(obj)
            library.objects.link(obj)
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'assets/modular_library_v5.blend'))
    out=ROOT/'assets/models/v5';out.mkdir(parents=True,exist_ok=True);stats=[]
    kit_out=out/'kit';kit_out.mkdir(exist_ok=True)
    source_scene=bpy.context.scene;deps=bpy.context.evaluated_depsgraph_get()
    for name in ['compact_car','oil_barrel','electric_box','fuel_pump','trash_bin','low_barrier','supply_crate']:
        source=bpy.data.objects[name];scene=bpy.data.scenes.new('V5 prop '+name);copies=[]
        for child in source.children:
            if child.type not in ['MESH','FONT']:continue
            mesh=bpy.data.meshes.new_from_object(child.evaluated_get(deps));obj=bpy.data.objects.new(child.name,mesh);scene.collection.objects.link(obj);obj.matrix_world=child.matrix_basis.copy();copies.append(obj)
        bpy.context.window.scene=scene
        for obj in copies:obj.select_set(True)
        bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join()
        bpy.ops.export_scene.gltf(filepath=str(kit_out/(name+'.glb')),export_format='GLB',use_selection=True,use_active_scene=True,export_apply=True)
        bpy.context.window.scene=source_scene;deps=bpy.context.evaluated_depsgraph_get()
    for layout_path in sorted((ROOT/'assets').glob('chapter_*_layout.json')):
        layout=json.loads(layout_path.read_text());name=layout_path.stem.removesuffix('_layout')
        scene=bpy.data.scenes.new('V5 '+name);bpy.context.window.scene=scene
        deps=bpy.context.evaluated_depsgraph_get()
        # Evaluate the library in its own scene; keep transforms local to each module.
        source_scene=next(s for s in bpy.data.scenes if library.name in s.collection.children)
        bpy.context.window.scene=source_scene;deps=bpy.context.evaluated_depsgraph_get()
        objects=[]
        for placement in layout['module_instances']:
            source=bpy.data.objects[placement['module']]
            # +Y in Godot maps to +Z in Blender under xyz(); preserve yaw sign.
            matrix=Matrix.Translation(xyz(placement['position']))@Matrix.Rotation(math.radians(placement['rotation_y']),4,'Z')
            for child in source.children:
                if child.type not in ['MESH','FONT']:continue
                mesh=bpy.data.meshes.new_from_object(child.evaluated_get(deps));obj=bpy.data.objects.new(child.name,mesh);scene.collection.objects.link(obj);obj.matrix_world=matrix@child.matrix_basis;objects.append(obj)
        bpy.context.window.scene=scene
        for obj in objects:obj.select_set(True)
        bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();joined=bpy.context.object;joined.name=name
        # Consolidate identical material slots to keep a whole level batched.
        unique=[];remap={}
        for i,m in enumerate(joined.data.materials):
            if m not in unique:unique.append(m)
            remap[i]=unique.index(m)
        indices=[remap[p.material_index] for p in joined.data.polygons]
        joined.data.materials.clear()
        for m in unique:joined.data.materials.append(m)
        for p,index in zip(joined.data.polygons,indices):p.material_index=index
        joined.data.calc_loop_triangles()
        bpy.ops.export_scene.gltf(filepath=str(out/(name+'.glb')),export_format='GLB',use_selection=True,use_active_scene=True,export_apply=True)
        stats.append({'layout':name,'triangles':len(joined.data.loop_triangles),'materials':len(unique),'colliders':'unchanged original layout'})
        print('ENVIRONMENT_READY',stats[-1],flush=True)
        if name=='chapter_street':
            studio(scene,scale=38,res=1440);scene.render.resolution_y=900;scene.render.film_transparent=False
            scene.camera.location=(24,-27,29);scene.camera.rotation_euler=(Vector((0,1,0))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
            sun=bpy.data.lights.new('Moon','SUN');sun.energy=1.1;sun.color=(.55,.7,1)
            lamp=bpy.data.objects.new('Moon',sun);scene.collection.objects.link(lamp);lamp.rotation_euler=(.4,-.5,-.4)
            scene.render.filepath=str(ROOT/'assets/ui/city_backdrop.png');bpy.ops.render.render(write_still=True)
    (ROOT/'assets/visual_v5_manifest.json').write_text(json.dumps({'maps':stats,'source':'assets/modular_library_v5.blend'},indent=2))
if MODE=='icons':render_icons()
elif MODE=='environment':environment()
else:raise ValueError(MODE)
