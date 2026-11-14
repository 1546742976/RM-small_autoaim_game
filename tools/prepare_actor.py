import bpy,json,math
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
R=Path(__file__).resolve().parents[1]
import tempfile
tempfile.tempdir=str(R/'artifacts/runtime/temp')
Path(tempfile.tempdir).mkdir(parents=True,exist_ok=True)
C=R/'tools/cache/visuals/baldman'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(C/'BaldMan_Painted_Rigged.fbx'))
bpy.context.view_layer.update()
for o in bpy.context.scene.objects:
 if o.type=='MESH':
  vs=[o.matrix_world@Vector(c) for c in o.bound_box];print('BOUNDS',list(o.matrix_world),[min(v[i] for v in vs) for i in range(3)],[max(v[i] for v in vs) for i in range(3)])
 if o.type=='ARMATURE':print('RIG',o.name,[b.name for b in o.data.bones])
for m in bpy.data.materials:
 m.use_nodes=True;n=m.node_tree.nodes;bs=n.get('Principled BSDF')
 if not bs:continue
 for kind,file in [('color','BaldMan_Default_AlbedoTransparency.png'),('normal','BaldMan_Default_Normal.png'),('metal','BaldMan_Default_MetallicSmoothness.png')]:
  t=n.new('ShaderNodeTexImage');t.image=bpy.data.images.load(str(C/file))
  if kind=='color':m.node_tree.links.new(t.outputs['Color'],bs.inputs['Base Color'])
  elif kind=='normal':
   t.image.colorspace_settings.name='Non-Color';nm=n.new('ShaderNodeNormalMap');m.node_tree.links.new(t.outputs['Color'],nm.inputs['Color']);m.node_tree.links.new(nm.outputs['Normal'],bs.inputs['Normal'])
 bs.inputs['Metallic'].default_value=0;bs.inputs['Roughness'].default_value=.82

rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
# Bake the supplied A-pose into both the mesh and bind skeleton before authoring clips.
bpy.context.view_layer.update()
bpy.context.view_layer.objects.active=mesh
for mod in list(mesh.modifiers):
 if mod.type=='ARMATURE':bpy.ops.object.modifier_apply(modifier=mod.name)
bpy.context.view_layer.objects.active=rig
rig.select_set(True)
bpy.ops.object.mode_set(mode='POSE')
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode='OBJECT')
if rig.animation_data:rig.animation_data_clear()
for action in list(bpy.data.actions):bpy.data.actions.remove(action)
mod=mesh.modifiers.new('TrainingSkin','ARMATURE');mod.object=rig

# Preserve the authored skinned pose; normalize evaluated feet and standing height.
bpy.context.view_layer.update()
ev=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
vs=[ev.matrix_world@v.co for v in ev.data.vertices]
lo=min(v.z for v in vs); hi=max(v.z for v in vs); factor=1.82/(hi-lo)
root=bpy.data.objects.new('Trainee',None);bpy.context.collection.objects.link(root)
for o in [o for o in bpy.context.scene.objects if o.parent is None and o!=root]:o.parent=root
root.scale=(factor,)*3;root.location.z=-lo*factor
# Tint only the fabric polygons, preserving the face/skin texture and normal map.
base=mesh.data.materials[0];cloth=base.copy();cloth.name='TrainingTop'
bs=next(n for n in cloth.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
cloth.diffuse_color=(.18,.55,.52,1)
mesh.data.materials.append(cloth)
boots=base.copy();boots.name='TrainingBoots';mesh.data.materials.append(boots)
uv=mesh.data.uv_layers.active.data
img=next(n.image for n in base.node_tree.nodes if n.type=='TEX_IMAGE' and n.image and 'Albedo' in n.image.name)
pixels=list(img.pixels);w,h=img.size
for poly in mesh.data.polygons:
 center=sum((mesh.matrix_world@mesh.data.vertices[i].co for i in poly.vertices),Vector())/len(poly.vertices)
 u=sum(uv[i].uv.x for i in poly.loop_indices)/len(poly.loop_indices);v=sum(uv[i].uv.y for i in poly.loop_indices)/len(poly.loop_indices)
 ix=(int(v*h)%h*w+int(u*w)%w)*4;r,g,b=pixels[ix:ix+3]
 if .92<(center.z-lo)*factor<1.56 and abs(r-b)<.18 and abs(r-g)<.15:poly.material_index=1
 if (center.z-lo)*factor<.30:poly.material_index=2
# Original, compact training motions. Local axes are derived from the authored rig.
base_pose={b.name:b.matrix_basis.copy() for b in rig.pose.bones}
def rotate_world(name,axis,angle):
 b=rig.pose.bones['mixamorig:'+name]
 local_axis=b.matrix.to_3x3().inverted()@(rig.matrix_world.to_3x3().inverted()@Vector(axis))
 b.rotation_mode='QUATERNION';b.rotation_quaternion=b.rotation_quaternion@Quaternion(local_axis,angle)
for clip,length in [('idle',2.4),('sidestep',.72),('death',.78)]:
 action=bpy.data.actions.new(clip);rig.animation_data_create();rig.animation_data.action=action
 for f in range(int(length*30)+1):
  t=f/30;p=t/length
  for b in rig.pose.bones:b.matrix_basis=base_pose[b.name].copy()
  bpy.context.view_layer.update()
  rotate_world('LeftArm',(0,1,0),1.2);rotate_world('RightArm',(0,1,0),-1.2)
  if clip=='idle':rotate_world('Spine2',(1,0,0),math.sin(p*math.tau)*.012)
  if clip=='sidestep':
   wave=math.sin(p*math.tau)
   rotate_world('LeftUpLeg',(0,1,0),wave*.16);rotate_world('RightUpLeg',(0,1,0),-wave*.16)
   rotate_world('LeftLeg',(1,0,0),max(0,wave)*.20);rotate_world('RightLeg',(1,0,0),max(0,-wave)*.20)
   rotate_world('Spine2',(0,1,0),wave*.025)
  if clip=='death':
   ease=p*p*(3-2*p)
   rotate_world('Hips',(1,0,0),-ease*1.35)
   rig.pose.bones['mixamorig:Hips'].location.y-=ease*75
   rotate_world('LeftArm',(0,1,0),-ease*.3);rotate_world('RightArm',(0,1,0),ease*.3)
  for b in rig.pose.bones:
   b.keyframe_insert('location',frame=f);b.keyframe_insert('rotation_quaternion',frame=f);b.keyframe_insert('scale',frame=f)
 action.use_fake_user=True
rig.animation_data.action=None
for b in rig.pose.bones:b.matrix_basis=base_pose[b.name].copy()
bpy.context.scene.render.fps=30
bpy.ops.export_scene.gltf(filepath=str(R/'射击游戏/assets/models/trainee.glb'),export_format='GLB',export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True)
