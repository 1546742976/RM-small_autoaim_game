"""Blender 4.5: author persistent skinned hands and six synchronized reloads.

Input geometry/UVs: DJMaesen CC BY 4.0; normalized weapon sources are produced
by prepare_visuals.py. All constraints are solved offline in meters, then baked.
"""
import bpy, math, json, tempfile
from pathlib import Path
from mathutils import Matrix, Vector, Quaternion
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
CACHE=ROOT/'tools/cache/visuals'
OUT=ROOT/'射击游戏/assets/models'
SOURCE=ROOT/'tools/source/first_person'; SOURCE.mkdir(parents=True,exist_ok=True)
tempfile.tempdir=str(ROOT/'artifacts/runtime/temp')
FPS=120
IDS={'deagle':2.2,'ak47':2.5,'m4a1':3.1}
NAMES={'L':('L_arm_01','L_elbow_02','L_wrist_03'),'R':('R_arm_024','R_elbow_025','R_wrist_026')}
def load(path):
    before=set(bpy.context.scene.objects);bpy.ops.import_scene.gltf(filepath=str(path))
    return list(set(bpy.context.scene.objects)-before)
def empty(name,parent=None,location=(0,0,0)):
    o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.parent=parent;o.location=location;return o
def smooth(a,b,t):
    x=max(0,min(1,(t-a)/(b-a)));return x*x*(3-2*x)
def interp(t,times,poses):
    for i in range(1,len(times)):
        if t<=times[i]:return poses[i-1].lerp(poses[i],smooth(times[i-1],times[i],t))
    return poses[-1].copy()
def rigid(pos,q=Quaternion()):return Matrix.Translation(pos)@q.to_matrix().to_4x4()
def solve_elbow(s,w,pole,a,b):
    v=w-s;d=v.length;axis=v.normalized();d=max(abs(a-b)+1e-5,min(a+b-1e-5,d))
    x=(a*a-b*b+d*d)/(2*d);h=math.sqrt(max(0,a*a-x*x))
    side=pole-s;side=(side-axis*side.dot(axis)).normalized()
    return s+axis*x+side*h
def key_object(o,frame):
    o.rotation_mode='QUATERNION'
    for prop in ['location','rotation_quaternion','scale']:o.keyframe_insert(prop,frame=frame)
def stash(o,name):
    a=o.animation_data.action;a.name=name+'_'+o.name
    tr=o.animation_data.nla_tracks.new();tr.name=name
    strip=tr.strips.new(name,0,a);strip.name=name
    o.animation_data.action=None
    tr.mute=True

manifest={}
for wid,duration in IDS.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    gun_objects=load(CACHE/('normalized_'+wid+'.glb'))
    for o in list(gun_objects):
        if o.name.startswith(('LeftArm','RightArm')):bpy.data.objects.remove(o,do_unlink=True)
    # Imported glTF is already in Blender's Z-up meter frame.
    gun_root=next(o for o in bpy.context.scene.objects if o.parent is None)
    gun_root.name='WeaponMotion'
    root=empty('ViewModel');gun_root.parent=root
    magazine=next(o for o in bpy.context.scene.objects if o.name.split('.')[0]=='Magazine')
    magazine.name='Magazine'
    mag_home=magazine.matrix_local.copy()
    slide=bpy.data.objects.get('Slide');bolt=bpy.data.objects.get('Bolt')
    old_grip=next(o for o in bpy.context.scene.objects if o.name.split('.')[0]=='MagazineGrip')
    old_grip.name='MagazineGrip'
    old_grip.matrix_local=Matrix.Identity(4)
    # Actual left palm meets the left side of the magazine.
    old_grip.location=Vector((-.025,0,0))
    source=load(CACHE/'djmaesen_smg45_animated_reload_arms.glb')
    arm=next(o for o in source if o.type=='ARMATURE')
    mesh=next(o for o in source if o.name.startswith('FullReloadArmsAuditMesh'))
    # Capture source palm contact before deleting helper frames.
    src_contact=next(o for o in source if o.name.startswith('LeftGripAnchorFrame')).matrix_world.copy()
    source_rest={b.name:b.matrix_local.copy() for b in arm.data.bones}
    source_vertices=[v.co.copy() for v in mesh.data.vertices]
    src_scale=.0108
    G=Matrix.Rotation(math.pi,4,'Z')@Matrix.Scale(src_scale,4)
    G.translation=Vector((0,.132,.096))-G@Vector((0,-8.805893,6.411493))
    contact_world=G@(src_contact@Matrix.Scale(1/.015,4))
    # src_contact is in world meters; obtain the source unscaled translation.
    contact_world.translation=G@(src_contact.translation/.015)
    contact_world=rigid(contact_world.translation,contact_world.to_quaternion())
    for o in source:
        if o not in [arm,mesh]:bpy.data.objects.remove(o,do_unlink=True)
    arm.parent=root;arm.matrix_world=Matrix.Identity(4);arm.name='ArmsRig'
    mesh.parent=arm;mesh.matrix_world=Matrix.Identity(4);mesh.name='TacticalHands'
    if arm.animation_data:arm.animation_data_clear()
    for action in list(bpy.data.actions):bpy.data.actions.remove(action)
    arm.data.transform(G)
    mesh.data.transform(G)
    # Place the support hand around the fore-end, without moving the weapon.
    wrist_names=NAMES['L'];lwr=arm.data.bones[wrist_names[2]].matrix_local.copy()
    left_contact=Vector((-.025,.32,.105)) if wid!='deagle' else Vector((-.035,.135,.060))
    shift=left_contact-contact_world.translation
    # All left-hand bones receive the same translation; sleeve rebuilt below.
    bpy.context.view_layer.objects.active=arm;arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for b in arm.data.edit_bones:
        if b.name.startswith('L_') or (b.name.startswith('Joint') and int(b.name.split('_')[-1])<=23):b.translate(shift)
    bpy.ops.object.mode_set(mode='OBJECT')
    for v in mesh.data.vertices:
        side=sum(g.weight for g in v.groups if mesh.vertex_groups[g.group].name.startswith('L_') or mesh.vertex_groups[g.group].name in ['Joint_3_06','Joint_3_2_010','Joint_3_3_014','Joint_3_4_019','Joint_3_5_023'])
        v.co+=shift*side
    contact_world.translation+=shift
    # Rest-space palm frame follows the wrist (finger curls do not move it).
    wrist_rest=arm.data.bones[NAMES['L'][2]].matrix_local.copy()
    contact_local=wrist_rest.inverted()@contact_world
    # New physically bounded sleeve centerlines and fixed shoulder roots.
    shoulders={'L':Vector((-.23,-.12,-.20)),'R':Vector((.16,-.27,-.20))}
    lengths={'L':(.34,.34),'R':(.29,.29)}
    poles={'L':Vector((-.45,-.05,-.40)),'R':Vector((.38,-.08,-.35))}
    rest={b.name:b.matrix_local.copy() for b in arm.data.bones}
    wrist_positions={s:rest[NAMES[s][2]].translation for s in NAMES}
    elbows={s:solve_elbow(shoulders[s],wrist_positions[s],poles[s],*lengths[s]) for s in NAMES}
    bpy.ops.object.mode_set(mode='EDIT')
    for side,(upper,lower,wrist) in NAMES.items():
        for name,pos,child in [(upper,shoulders[side],elbows[side]),(lower,elbows[side],wrist_positions[side])]:
            b=arm.data.edit_bones[name];b.head=pos;b.tail=child;b.roll=0
    bpy.ops.object.mode_set(mode='OBJECT')
    # The source contains independent glove and sleeve islands. Retain the
    # complete gloves and join THEIR open wrists to the new sleeves; cutting
    # and extending the old sleeve island leaves the actual glove opening bare.
    import bmesh
    bm=bmesh.new();bm.from_mesh(mesh.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
    deform=bm.verts.layers.deform.active
    left_bones={b.name for b in arm.data.bones if b.name.startswith('L_') or (b.name.startswith('Joint') and int(b.name.split('_')[-1])<=23)}
    left_groups={g.index for g in mesh.vertex_groups if g.name in left_bones}
    fingertip_groups={mesh.vertex_groups[name].index for name in ['L_point3_09','R_point3_033']}
    unseen=set(bm.verts);discard=[];gloves=0
    while unseen:
        stack=[unseen.pop()];island=set(stack)
        while stack:
            for edge in stack.pop().link_edges:
                for v in edge.verts:
                    if v in unseen:unseen.remove(v);island.add(v);stack.append(v)
        if any(any(v[deform].get(index,0)>.5 for index in fingertip_groups) for v in island):gloves+=1
        else:discard.extend(island)
    assert gloves==2, (wid,'expected two complete glove islands',gloves)
    bmesh.ops.delete(bm,geom=discard,context='VERTS')
    for side,(upper,lower,wrist) in NAMES.items():
        selected={v for v in bm.verts if (sum(value for index,value in v[deform].items() if index in left_groups)>.5)==(side=='L')}
        boundary=[e for e in bm.edges if e.is_boundary and all(v in selected for v in e.verts)]
        adjacency={v:[] for edge in boundary for v in edge.verts}
        for edge in boundary:
            a,b=edge.verts;adjacency[a].append(b);adjacency[b].append(a)
        assert adjacency and all(len(n)==2 for n in adjacency.values()), (wid,side,'wrist must be a closed ring')
        start=min(adjacency,key=lambda v:(v.co.x,v.co.z))
        ring=[start];previous=None;current=start
        while True:
            next_vertex=next(v for v in adjacency[current] if v is not previous)
            if next_vertex is start:break
            ring.append(next_vertex);previous,current=current,next_vertex
        assert len(ring)==len(adjacency)==28, (wid,side,'expected the original 28-vertex glove wrist')
        center=sum((v.co for v in ring),Vector())/len(ring)
        w=wrist_positions[side];axis=(elbows[side]-w).normalized()
        xx=Vector((1,0,0));xx=(xx-axis*axis.dot(xx)).normalized();zz=xx.cross(axis).normalized()
        # Match the entire cut perimeter to an ellipse inside the sleeve's
        # first wrist-bound region. Arc length preserves winding even around
        # small folds; extending world -Y produced an unconnected flared tube.
        origin_points=[v.co.copy() for v in ring]
        distances=[0.0]
        for a,b in zip(origin_points,origin_points[1:]):distances.append(distances[-1]+(b-a).length)
        perimeter=distances[-1]+(origin_points[0]-origin_points[-1]).length
        winding=sum((a.x-center.x)*(-(b.z-center.z))-(-(a.z-center.z))*(b.x-center.x) for a,b in zip(origin_points,origin_points[1:]+origin_points[:1]))
        angle0=math.atan2(-(origin_points[0].z-center.z),origin_points[0].x-center.x)
        angles=[angle0+(1 if winding>0 else -1)*2*math.pi*d/perimeter for d in distances]
        end_center=w+axis*.065
        radius=(.043 if side=='L' else .040)*.96
        end_points=[end_center+xx*(math.cos(a)*radius)+zz*(math.sin(a)*radius*.88) for a in angles]
        wrist_group=mesh.vertex_groups[wrist].index
        for v in ring:v[deform].clear();v[deform][wrist_group]=1.0
        uv_layer=bm.loops.layers.uv.active
        for step in range(1,6):
            t=step/5;blend=smooth(0,1,t)
            new_ring=[]
            for a,b in zip(origin_points,end_points):
                v=bm.verts.new(a.lerp(b,blend));v[deform][wrist_group]=1.0;new_ring.append(v)
            for i in range(len(ring)):
                j=(i+1)%len(ring)
                face=bm.faces.new((ring[i],ring[j],new_ring[j],new_ring[i]));face.material_index=1;face.smooth=True
                for li,loop in enumerate(face.loops):
                    loop[uv_layer].uv=(.278+.093*((i+(li in [1,2]))/len(ring)),.113+.257*(t if li>=2 else (step-1)/5))
            ring=new_ring
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh.data);bm.free()
    for v in mesh.data.vertices:
        for side,(upper,lower,wrist) in NAMES.items():
            transfer=sum(g.weight for g in v.groups if mesh.vertex_groups[g.group].name in [upper,lower])
            existing=sum(g.weight for g in v.groups if mesh.vertex_groups[g.group].name==wrist)
            if transfer:
                for name in [upper,lower]:mesh.vertex_groups[name].remove([v.index])
                mesh.vertex_groups[wrist].add([v.index],existing+transfer,'REPLACE')
    sleeve_material=mesh.data.materials[0].copy();sleeve_material.name='CharcoalWovenSleeve'
    bs=next(n for n in sleeve_material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    for inp in ['Base Color','Metallic','Roughness']:
        for link in list(bs.inputs[inp].links):sleeve_material.node_tree.links.remove(link)
    bs.inputs['Base Color'].default_value=(.025,.030,.033,1)
    for n in sleeve_material.node_tree.nodes:
        if n.type=='NORMAL_MAP':n.inputs['Strength'].default_value=.15
    cuff_material=sleeve_material.copy();cuff_material.name='CharcoalRibbedCuff'
    next(n for n in cuff_material.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Base Color'].default_value=(.014,.018,.02,1)
    mesh.data.materials.append(cuff_material)
    bs.inputs['Roughness'].default_value=.95;bs.inputs['Metallic'].default_value=0
    bs.inputs['Specular IOR Level'].default_value=.15;bs.inputs['Coat Weight'].default_value=0
    for side,(upper,lower,wrist) in NAMES.items():
        w=wrist_positions[side];e=elbows[side];shoulder=shoulders[side]
        axis=(e-w).normalized();xx=Vector((1,0,0));xx=(xx-axis*xx.dot(axis)).normalized();zz=xx.cross(axis).normalized()
        vertices=[];faces=[];weights=[];rings=30;segments=40
        for i in range(rings+1):
            t=i/rings
            if t<=.5:
                center=(w+axis*.04).lerp(e,t*2)
            else:center=e.lerp(shoulder,(t-.5)*2)
            if .4<t<.6:
                tt=(t-.4)/.2;aa=(w+axis*.04).lerp(e,.8);bb=e.lerp(shoulder,.2)
                center=aa*(1-tt)**2+e*(2*tt*(1-tt))+bb*tt**2
            radius=(.043 if side=='L' else .040)+.017*t
            for j in range(segments):
                ang=j*2*math.pi/segments
                wrinkle=.0055*math.sin(t*math.pi*21+2*math.sin(ang))*(.45+.55*math.sin(math.pi*t))
                wrinkle+=.0015*math.exp(-math.sin(ang)**2/.008)
                rr=radius+wrinkle+(.001*math.cos(j*math.pi) if i<3 else 0)
                vertices.append(center+xx*(math.cos(ang)*rr)+zz*(math.sin(ang)*rr*.88))
                wrist_weight=1-smooth(.10,.23,t)
                upper_weight=smooth(.40,.60,t)
                weights.append((upper_weight,1-upper_weight-wrist_weight,wrist_weight))
                if i<rings:
                    k=i*segments+j;n=i*segments+(j+1)%segments
                    faces.append((k,n,n+segments,k+segments))
        # The glove bridge overlaps this open first ring; no disc across the
        # wrist, which previously appeared as a large folded collar.
        faces.append(tuple(rings*segments+j for j in range(segments)))
        data=bpy.data.meshes.new(side+'SleeveMesh');data.from_pydata(vertices,[],faces);data.materials.append(sleeve_material);data.materials.append(cuff_material)
        normals=bmesh.new();normals.from_mesh(data);bmesh.ops.recalc_face_normals(normals,faces=list(normals.faces));normals.to_mesh(data);normals.free()
        sleeve=bpy.data.objects.new(side+'Sleeve',data);bpy.context.collection.objects.link(sleeve);sleeve.parent=arm
        mod=sleeve.modifiers.new('Skin','ARMATURE');mod.object=arm
        vg_a=sleeve.vertex_groups.new(name=upper);vg_b=sleeve.vertex_groups.new(name=lower);vg_w=sleeve.vertex_groups.new(name=wrist)
        for i,(wa,wb,ww) in enumerate(weights):
            if wa:vg_a.add([i],wa,'REPLACE')
            if wb:vg_b.add([i],wb,'REPLACE')
            if ww:vg_w.add([i],ww,'REPLACE')
        uv=data.uv_layers.new(name='UVMap')
        for poly in data.polygons:
            poly.use_smooth=True
            if poly.index<segments*3:poly.material_index=1
            for li in poly.loop_indices:
                vi=data.loops[li].vertex_index
                uv.data[li].uv=(.278+(vi%segments)/segments*.093,.113+(vi//segments)/rings*.257)
    # Low-gloss dark fabric/gloves retain authored base, normal and roughness maps.
    for mat in mesh.data.materials:
        if not mat.use_nodes:continue
        for n in mat.node_tree.nodes:
            if n.type=='BSDF_PRINCIPLED':
                n.inputs['Metallic'].default_value=0;n.inputs['Roughness'].default_value=.85
                n.inputs['Coat Weight'].default_value=0
    rest={b.name:b.matrix_local.copy() for b in arm.data.bones}
    contact=empty('LeftMagazineContact',arm)
    contact.parent_type='BONE';contact.parent_bone=NAMES['L'][2]
    # Blender bone parent origin is at the tail rather than head.
    contact.matrix_local=Matrix.Translation((0,-arm.data.bones[NAMES['L'][2]].length,0))@contact_local
    right_contact=empty('RightHandContact',arm)
    right_contact.parent_type='BONE';right_contact.parent_bone=NAMES['R'][2]
    right_local=rest[NAMES['R'][2]].inverted()@bpy.data.objects['RightGrip'].matrix_local
    right_contact.matrix_local=Matrix.Translation((0,-arm.data.bones[NAMES['R'][2]].length,0))@right_local
    # Uniform contact orientation: the marker frame and the prop frame coincide.
    grip=old_grip.matrix_local.copy()
    bone_rest_vec={s:(rest[NAMES[s][1]].translation-rest[NAMES[s][0]].translation,rest[NAMES[s][2]].translation-rest[NAMES[s][1]].translation)for s in NAMES}
    def pose_arm(side,W,mechanical_phase=0.0):
        upper,lower,wrist=NAMES[side];s=shoulders[side];w=W.translation
        pole=poles[side]
        if side=='L' and wid=='ak47':
            # Route the support forearm below the firing hand while operating
            # the handle; the wrist contact and both limb lengths stay fixed.
            pole=pole+Vector((0,0,-.18))*mechanical_phase
        elbow=solve_elbow(s,w,pole,*lengths[side])
        targets={}
        for name,pos,vec,oldvec in [(upper,s,elbow-s,bone_rest_vec[side][0]),(lower,elbow,w-elbow,bone_rest_vec[side][1])]:
            q=oldvec.normalized().rotation_difference(vec.normalized())
            targets[name]=rigid(pos,q@rest[name].to_quaternion())
        targets[wrist]=W
        for name in [upper,lower,wrist]:
            parent=arm.data.bones[name].parent.name
            parent_pose=targets.get(parent,rest[parent])
            arm.pose.bones[name].matrix_basis=rest[name].inverted()@rest[parent]@parent_pose.inverted()@targets[name]
    # Mechanical contact is derived from the real index fingertip surface.
    # Pose that finger differently for a button press, hook, or slide pinch.
    mechanical_angles={n:-.24 for n in ['L_middle2_012','L_middle3_013','L_ring2_017','L_ring3_018','L_pink2_021','L_pink3_022']}
    mechanical_angles.update({'L_point2_08':.80,'L_point3_09':.85} if wid=='m4a1' else {'L_point2_08':-.20,'L_point3_09':-.18} if wid=='ak47' else {'L_point2_08':.08,'L_point3_09':.05})
    finger_basis={n:Quaternion(rest[n].to_3x3().inverted()@Vector((0,0,1)),angle).to_matrix().to_4x4() for n,angle in mechanical_angles.items()}
    finger_pose={}
    for b in arm.data.bones:
        if b.parent:
            finger_pose[b.name]=finger_pose[b.parent.name]@rest[b.parent.name].inverted()@rest[b.name]@finger_basis.get(b.name,Matrix.Identity(4))
        else:finger_pose[b.name]=rest[b.name]
    finger='L_point3_09'
    tip_position=rest['Joint_3_2_010'].translation
    closest=min(mesh.data.vertices,key=lambda v:(v.co-tip_position).length)
    posed_tip=finger_pose[finger]@rest[finger].inverted()@closest.co
    mechanical_local=Matrix.Translation(rest[NAMES['L'][2]].inverted()@posed_tip)
    angle=math.radians(-90 if wid=='m4a1' else 90 if wid=='ak47' else 70)
    mechanical_q=Quaternion((0,0,1),angle)@rest[NAMES['L'][2]].to_quaternion()
    mechanical_position={'deagle':Vector((.017,.16,.18)),'ak47':Vector((.056,.21,.155)),'m4a1':Vector((-.047,.265,.125))}[wid]
    mechanical_part=slide if wid=='deagle' else bolt if wid=='ak47' else bpy.data.objects['Gun']
    mechanism=empty('MechanicalContact',mechanical_part)
    mechanism.matrix_local=rigid(mechanical_position,mechanical_q)
    hand_mechanism=empty('LeftMechanicalContact',arm)
    hand_mechanism.parent_type='BONE';hand_mechanism.parent_bone=NAMES['L'][2]
    hand_mechanism.matrix_local=Matrix.Translation((0,-arm.data.bones[NAMES['L'][2]].length,0))@mechanical_local
    meta={'duration':duration,'bones':{s:list(NAMES[s])for s in NAMES},'clips':{}}
    for clip in ['idle','reload_empty','reload_tactical']:
        count=1 if clip=='idle' else round(duration*FPS)
        bpy.context.scene.render.fps=FPS;bpy.context.scene.frame_start=0;bpy.context.scene.frame_end=count
        objects=[arm,gun_root,magazine,slide,bolt]
        for o in objects:
            o.animation_data_create();o.animation_data.action=bpy.data.actions.new(clip+'_'+o.name)
        for frame in range(count+1):
            p=0 if clip=='idle' else frame/count
            for b in arm.pose.bones:b.matrix_basis=Matrix.Identity(4)
            tilt=smooth(0,.16,p)*(1-smooth(.87,1,p))
            q=Quaternion((0,1,0),(-.27 if wid=='deagle' else -.34)*tilt)
            gun_matrix=rigid(Vector((0,0,0)),q)
            gun_root.matrix_local=gun_matrix
            M=mag_home.copy()
            drop=Vector((-.06,-.045,-.20));pouch=Vector((-.10,-.09,-.40))
            offset=interp(p,[0,.20,.33,.44,.52,.65,.72,1],[Vector(),Vector(),drop,pouch,pouch,drop,Vector(),Vector()])
            mag_q=Quaternion((1,0,0),(-.32 if wid=='ak47' else .06)*smooth(.20,.33,p)*(1-smooth(.65,.72,p)))
            M=rigid(mag_home.translation+offset,mag_q)
            magazine.matrix_local=M
            slide.location=Vector();bolt.location=Vector()
            mechanical=smooth(.80,.84,p)*(1-smooth(.87,.90,p)) if clip=='reload_empty' else 0
            if wid=='deagle':slide.location.y=-.037*mechanical
            elif wid=='ak47':bolt.location.y=-.045*mechanical
            W_R=gun_matrix@rest[NAMES['R'][2]]
            initial=gun_matrix@rest[NAMES['L'][2]]
            # Palm orientation blends before touching; while carrying it is
            # mathematically identical to the magazine's actual reference.
            carry=gun_matrix@M@grip@contact_local.inverted()
            blend=smooth(.04,.20,p)*(1-smooth(.72,.79,p))
            W_L=rigid(initial.translation.lerp(carry.translation,blend),initial.to_quaternion().slerp(carry.to_quaternion(),blend))
            if clip=='reload_empty':
                mech_pos=mechanical_position.copy()
                if wid=='deagle':mech_pos.y-=.037*mechanical
                elif wid=='ak47':mech_pos.y-=.045*mechanical
                W_m=gun_matrix@rigid(mech_pos,mechanical_q)@mechanical_local.inverted()
                b=smooth(.75,.81,p)*(1-smooth(.90,.98,p))
                W_L=rigid(W_L.translation.lerp(W_m.translation,b),W_L.to_quaternion().slerp(W_m.to_quaternion(),b))
            pose_arm('R',W_R);pose_arm('L',W_L,smooth(.75,.81,p)*(1-smooth(.90,.98,p)) if clip=='reload_empty' else 0.0)
            mb=smooth(.75,.81,p)*(1-smooth(.90,.98,p)) if clip=='reload_empty' else 0
            for name,angle in mechanical_angles.items():
                axis=rest[name].to_3x3().inverted()@Vector((0,0,1))
                arm.pose.bones[name].rotation_mode='QUATERNION';arm.pose.bones[name].rotation_quaternion=Quaternion(axis,angle*mb)
            for name in ['R_middle2_036','R_ring2_041','R_pink2_045','R_middle3_037','R_ring3_042','R_pink3_046']:
                axis=rest[name].to_3x3().inverted()@Vector((0,0,1))
                arm.pose.bones[name].rotation_mode='QUATERNION'
                arm.pose.bones[name].rotation_quaternion=Quaternion(axis,.30 if '2_' in name else .20)
            for b in arm.pose.bones:
                b.rotation_mode='QUATERNION'
                b.keyframe_insert('location',frame=frame);b.keyframe_insert('rotation_quaternion',frame=frame)
            for o in [gun_root,magazine,slide,bolt]:key_object(o,frame)
        for o in objects:stash(o,clip)
        for a in bpy.data.actions:
            for layer in a.layers:
                for strip in layer.strips:
                    for bag in strip.channelbags:
                        for fc in bag.fcurves:
                            for k in fc.keyframe_points:k.interpolation='LINEAR'
        if clip!='idle':
            meta['clips'][clip]={'events':[{'name':'remove','progress':.20},{'name':'insert','progress':.72}]+([{'name':'mechanism','progress':.84}]if clip=='reload_empty'else[]),'contacts':[{'start':.20,'end':.72,'a':'LeftMagazineContact','b':'MagazineGrip'},{'start':0,'end':1,'a':'RightHandContact','b':'RightGrip'}],'transitions':[0,.20,.33,.44,.52,.65,.72,.79,.81,.90,.98,1]}
    meta['clips']['reload_empty']['contacts'].append({'start':.82,'end':.88,'a':'LeftMechanicalContact','b':'MechanicalContact'})
    for tr in arm.animation_data.nla_tracks:tr.mute=True
    bpy.context.scene.frame_set(0)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(wid+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(wid+'.glb')),export_format='GLB',export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_extras=True,export_anim_slide_to_zero=True)
    manifest[wid]=meta
    print('FIRST_PERSON_BUILT',wid,flush=True)
(OUT/'viewmodel_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
