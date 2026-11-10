extends SceneTree

## Probe: the bandit .glb loads with mesh + material + skeleton + clips,
## and the walk cycle visibly drives the legs (the biped strides rather
## than standing frozen). Exit 0 = all good.
##
## _initialize(), not _init(): the data-wiring section resolves the
## DataService autoload, which attaches after _init.

func _initialize() -> void:
        var scene: PackedScene = load("res://models/enemies/enemy_bandit.glb")
        if scene == null:
                push_error("FAIL: bandit glb did not load")
                quit(1)
                return
        var inst := scene.instantiate()
        inst.name = "rig_bandit"
        root.add_child(inst)
        var skel := _find_skel(inst)
        var ap := _find_ap(inst)
        if skel == null or ap == null:
                push_error("FAIL: missing skeleton or AnimationPlayer")
                quit(1)
                return

        # Real geometry: at least one MeshInstance3D with a mesh that has
        # surface(s) and a material assigned.
        var mesh_inst := _find_mesh(inst)
        if mesh_inst == null or mesh_inst.mesh == null:
                push_error("FAIL: no MeshInstance3D with a mesh")
                quit(1)
                return
        if mesh_inst.mesh.get_surface_count() < 1:
                push_error("FAIL: mesh has no surfaces")
                quit(1)
                return
        if mesh_inst.mesh.surface_get_material(0) == null:
                push_error("FAIL: mesh surface has no material")
                quit(1)
                return
        print("[OK] mesh: %d surface(s), material=%s" % [
                mesh_inst.mesh.get_surface_count(),
                mesh_inst.mesh.surface_get_material(0).resource_name])
        var bone_names := []
        for i in skel.get_bone_count():
                bone_names.append(skel.get_bone_name(i))
        for b in ["root", "hips", "spine", "chest", "neck", "head",
                        "arm_l", "arm_r", "forearm_l", "forearm_r",
                        "thigh_l", "thigh_r", "shin_l", "shin_r"]:
                if not (b in bone_names):
                        push_error("FAIL: missing bone %s (bones: %s)" % [b, str(bone_names)])
                        quit(1)
                        return
        print("[OK] bandit skeleton: %d bones (humanoid chain present)" % skel.get_bone_count())
        var anims := ap.get_animation_list()
        print("[OK] clips: %s" % str(anims))
        if not (anims.has("idle") and anims.has("walk")):
                push_error("FAIL: missing idle/walk clips")
                quit(1)
                return

        # Stride check: in the walk slot the thigh bones counter-rotate --
        # measure each leg's rotation delta between two timestamps inside
        # the walk NLA slot (starts at 1.6s; sample mid-cycle).
        ap.play("walk")
        ap.seek(1.70, true)
        var q0_l: Quaternion = skel.get_bone_pose(skel.find_bone("thigh_l")).basis.get_rotation_quaternion()
        var q0_r: Quaternion = skel.get_bone_pose(skel.find_bone("thigh_r")).basis.get_rotation_quaternion()
        ap.seek(1.95, true)
        var q1_l: Quaternion = skel.get_bone_pose(skel.find_bone("thigh_l")).basis.get_rotation_quaternion()
        var q1_r: Quaternion = skel.get_bone_pose(skel.find_bone("thigh_r")).basis.get_rotation_quaternion()
        var dl: float = q0_l.angle_to(q1_l)
        var dr: float = q0_r.angle_to(q1_r)
        print("[OK] stride deltas: thigh_l=%.3f thigh_r=%.3f" % [dl, dr])
        if dl < 0.05 or dr < 0.05:
                push_error("FAIL: walk cycle does not drive the legs")
                inst.free()
                quit(1)
                return
        print("[OK] walk cycle drives both legs")

        # Bandit data wires the humanoid hitbox + the model.
        var ds = root.get_node_or_null("DataService")
        if ds == null:
                push_error("FAIL: no DataService")
                quit(1)
                return
        if not ds._loaded:
                ds.load_all_data()
        var bandit = ds.get_enemy("bandit")
        if bandit == null:
                push_error("FAIL: enemy_bandit data missing")
                quit(1)
                return
        var mp = bandit.get("model_path")
        if mp == null or str(mp) != "res://models/enemies/enemy_bandit.glb":
                push_error("FAIL: bandit model_path not wired: %s" % str(mp))
                quit(1)
                return
        var hp = bandit.get("hitbox_profile_id")
        if hp == null or str(hp) != "hitbox_humanoid":
                push_error("FAIL: bandit hitbox_profile_id not humanoid: %s" % str(hp))
                quit(1)
                return
        print("[OK] enemy_bandit.tres -> enemy_bandit.glb + hitbox_humanoid")
        inst.free()
        print("--- BANDIT MODEL PROBE: ok=true ---")
        quit(0)

func _find_skel(n: Node) -> Skeleton3D:
        if n is Skeleton3D:
                return n
        for c in n.get_children():
                var s := _find_skel(c)
                if s != null:
                        return s
        return null

func _find_ap(n: Node) -> AnimationPlayer:
        if n is AnimationPlayer:
                return n
        for c in n.get_children():
                var a := _find_ap(c)
                if a != null:
                        return a
        return null

func _find_mesh(n: Node) -> MeshInstance3D:
        if n is MeshInstance3D and n.mesh != null:
                return n
        for c in n.get_children():
                var m := _find_mesh(c)
                if m != null:
                        return m
        return null
