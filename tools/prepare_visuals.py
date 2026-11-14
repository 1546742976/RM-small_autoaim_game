"""Blender 4.5: normalize attributed meshes, rigged arms and target for Godot."""
import bpy, math, json
import numpy as np
from pathlib import Path
from mathutils import Matrix, Vector

ROOT=Path(__file__).resolve().parents[1]
import tempfile
tempfile.tempdir=str(ROOT/'artifacts/runtime/temp')
Path(tempfile.tempdir).mkdir(parents=True,exist_ok=True)
CACHE=ROOT/'tools/cache/visuals'
OUT=ROOT/'射击游戏/assets/models'
OUT.mkdir(parents=True,exist_ok=True)

def empty(name, parent=None, location=(0,0,0)):
    obj=bpy.data.objects.new(name,None)
    bpy.context.collection.objects.link(obj)
    obj.parent=parent
    obj.location=location
    return obj

def load(name):
    before=set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(CACHE/name))
    return list(set(bpy.context.scene.objects)-before)

def export(name):
    for img in bpy.data.images:
        if max(img.size)>2048:img.scale(2048,2048)
    for obj in list(bpy.context.scene.objects):
        if obj.name.startswith('Icosphere'): bpy.data.objects.remove(obj,do_unlink=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/name),export_format='GLB',export_animations=True,
        export_animation_mode='ACTIONS',export_force_sampling=True,export_extras=True)

def remove_except(keep):
    for obj in list(bpy.context.scene.objects):
        if obj not in keep: bpy.data.objects.remove(obj,do_unlink=True)

def viewmodel(id,source,scale,grip,muzzle,left):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects=load(source)
    root=empty('ViewModel')
    body=empty('Gun',root)
    mag=empty('Magazine',root)
    bolt=empty('Bolt',root)
    slide=empty('Slide',root)
    keep={root,body,mag,bolt,slide}
    rotation=Matrix.Rotation(math.pi,4,'Z') if id=='deagle' else Matrix.Identity(4)
    g=rotation@Matrix.Scale(scale,4)
    g.translation=Vector((0,.132,.096))-g@Vector(grip)
    mag_objects=[]
    for obj in objects:
        if obj.type!='MESH':continue
        name=obj.name
        if any(t in name for t in ['SpareMagazine','Suppressor','OpticMount','OpticRail','BulletCase','Bullet_low']): continue
        group=body
        if 'Magazine' in name or 'BaseInside' in name:
            group=mag
            mag_objects.append(obj)
        elif 'ChargingHandleGeometry' in name: group=bolt
        elif id=='deagle' and any(t in name for t in ['Slide_low','Safety_low','BoltMain','BoltAdd','RearSight','SlidePart','BoltButton','BoltBack']):group=slide
        world=g@obj.matrix_world
        obj.parent=group
        obj.matrix_parent_inverse=Matrix.Identity(4)
        obj.data.transform(world)
        obj.matrix_world=Matrix.Identity(4)
        keep.add(obj)
    bpy.context.view_layer.update()
    # Use the real prop center as pivot; vertices retain their authored geometry.
    verts=[obj.matrix_world@Vector(c) for obj in mag_objects for c in obj.bound_box]
    center=Vector(tuple((min(v[i] for v in verts)+max(v[i] for v in verts))/2 for i in range(3)))
    mag.location=center
    for o in mag_objects:o.data.transform(Matrix.Translation(-center))
    keep.add(empty('MagazineGrip',mag,(-.025,0,0)))
    keep.add(empty('Muzzle',root,g@Vector(muzzle)))
    keep.add(empty('RightGrip',root,(0,.132,.096)))
    keep.add(empty('LeftGrip',root,left))
    remove_except(keep)
    arms=load('djmaesen_smg45_smg45_'+('pistol_large' if id=='deagle' else 'rifle')+'_arms.glb')
    left_frame=next(o for o in arms if o.name.startswith('LeftGripFrame'))
    shift=Vector(left)-left_frame.matrix_world.translation
    palm=next(o for o in arms if o.name.startswith('LeftPalmFrame'))
    keep.add(empty('LeftPalm',root,palm.matrix_world.translation+shift))
    for obj in arms:
        if obj.type=='MESH':
            world=obj.matrix_world.copy()
            obj.parent=root
            obj.matrix_parent_inverse=Matrix.Identity(4)
            if 'LeftArm' in obj.name:
                obj.name='LeftArm'
                world.translation+=shift
            else:obj.name='RightArm'
            pivot=Vector(left) if 'LeftArm' in obj.name else Vector((0,.132,.096))
            adjust=Matrix.Translation(pivot)@Matrix.Scale(.72,4)@Matrix.Translation(-pivot)
            obj.data.transform(adjust@world)
            obj.matrix_world=Matrix.Identity(4)
            keep.add(obj)
    remove_except(keep)
    # Physically based imported textures are kept at their native resolution.
    for material in bpy.data.materials:
        if not material.use_nodes:continue
        for node in material.node_tree.nodes:
            if node.type=='BSDF_PRINCIPLED':
                node.inputs['Coat Weight'].default_value=0.05

    if id=='ak47':
        for img in bpy.data.images:
            if img.size[0] and max(img.size)!=2048:img.scale(2048,2048)
        for mat in {slot.material for obj in keep if obj.type=='MESH' for slot in obj.material_slots}:
            if not mat or not mat.use_nodes:continue
            nodes=mat.node_tree.nodes;links=mat.node_tree.links
            bs=next((n for n in nodes if n.type=='BSDF_PRINCIPLED'),None)
            if not bs or bs.inputs['Normal'].is_linked:continue
            color_link=bs.inputs['Base Color'].links
            if not color_link or color_link[0].from_node.type!='TEX_IMAGE':continue
            source=color_link[0].from_node.image
            values=np.array(source.pixels[:],dtype=np.float32).reshape(2048,2048,4)
            gray=values[:,:,:3].mean(axis=2)
            dy,dx=np.gradient(gray);nx=-dx*.65;ny=-dy*.65
            pixels=np.ones((2048,2048,4),dtype=np.float32)
            length=np.sqrt(nx*nx+ny*ny+1)
            pixels[:,:,0]=nx/length*.5+.5;pixels[:,:,1]=ny/length*.5+.5;pixels[:,:,2]=1/length*.5+.5
            img=bpy.data.images.new(mat.name+'_Normal_2K',width=2048,height=2048)
            img.colorspace_settings.name='Non-Color';img.pixels.foreach_set(pixels.ravel());img.pack()
            tex=nodes.new('ShaderNodeTexImage');tex.image=img
            normal=nodes.new('ShaderNodeNormalMap');links.new(tex.outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],bs.inputs['Normal'])
    export(id+'.glb')

viewmodel('deagle','elizion_desert_eagle_desert_eagle.glb',.012,(0,10.8,16.5),(0,-10.8,24.14),(0,.16,.09))
viewmodel('ak47','steel_tide_ak74_ak47_reloadable_fp.glb',.7,(0,.15,-.14),(0,1.135,.005),(0,.475,.14))
viewmodel('m4a1','steel_tide_m4a1_steel_tide_m4a1.glb',.45,(0,-.245,-.2),(0,1.265,.049),(0,.503,.11))

# Keep only the three required support-arm clips, retaining the source skin.
bpy.ops.wm.read_factory_settings(use_empty=True)
load('djmaesen_smg45_animated_reload_arms.glb')
for obj in list(bpy.context.scene.objects):
    if obj.name.startswith(('FullReloadArmsAuditMesh','Icosphere')):bpy.data.objects.remove(obj,do_unlink=True)
for obj in bpy.context.scene.objects:
    if obj.type=='ARMATURE' and obj.animation_data:
        obj.animation_data.action=None
        for track in list(obj.animation_data.nla_tracks):obj.animation_data.nla_tracks.remove(track)
for action in list(bpy.data.actions):
    if action.name not in ['reload_ak74_empty','reload_desert_eagle_empty','reload_m4a1_empty']:
        bpy.data.actions.remove(action)
export('reload_arms.glb')

print('Prepared four weapon and arms GLBs; run prepare_actor.py for trainee')
