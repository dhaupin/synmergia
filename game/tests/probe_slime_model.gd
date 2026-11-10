extends SceneTree

## Probe: the slime .glb loads with mesh + skeleton + clips, and the
## hop cycle visibly drives the body bone (the blob rises and squashes).
## Exit 0 = all good.
##
## _initialize(), not _init(): the data-wiring section resolves the
## DataService autoload, which attaches after _init.

func _initialize() -> void:
        var scene: PackedScene = load("res://models/enemies/enemy_slime.glb")
        if scene == null:
                push_error("FAIL: slime glb did not load")
                quit(1)
                return
        var inst := scene.instantiate()
        inst.name = "rig_slime"
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
        for b in ["root", "body", "eye_l", "eye_r"]:
                if not (b in bone_names):
                        push_error("FAIL: missing bone %s (bones: %s)" % [b, str(bone_names)])
                        quit(1)
                        return
        print("[OK] slime skeleton: %d bones (root/body/eye_l/eye_r present)" % skel.get_bone_count())
        var anims := ap.get_animation_list()
        print("[OK] clips: %s" % str(anims))
        if not (anims.has("idle") and anims.has("walk")):
                push_error("FAIL: missing idle/walk clips")
                quit(1)
                return

        # Hop check: in the walk slot the root bone's vertical offset
        # changes between a grounded frame and the apex -- the blob
        # actually leaves the ground.
        var root_bone := skel.find_bone("root")
        ap.play("walk")
        ap.seek(1.70, true)
        var y0: float = skel.get_bone_pose_position(root_bone).y
        ap.seek(1.95, true)
        var y1: float = skel.get_bone_pose_position(root_bone).y
        var hop: float = absf(y1 - y0)
        print("[OK] hop: root Y delta = %.3f (grounded %.3f -> apex %.3f)" % [hop, y0, y1])
        if hop < 0.05:
                push_error("FAIL: hop does not lift the body")
                inst.free()
                quit(1)
                return
        print("[OK] hop cycle lifts the body off the ground")

        # Slime data wires the blob hitbox + the model.
        var ds = root.get_node_or_null("DataService")
        if ds == null:
                push_error("FAIL: no DataService")
                quit(1)
                return
        if not ds._loaded:
                ds.load_all_data()
        var slime = ds.get_enemy("slime")
        if slime == null:
                push_error("FAIL: enemy_slime data missing")
                quit(1)
                return
        var mp = slime.get("model_path")
        if mp == null or str(mp) != "res://models/enemies/enemy_slime.glb":
                push_error("FAIL: slime model_path not wired: %s" % str(mp))
                quit(1)
                return
        var hp = slime.get("hitbox_profile_id")
        if hp == null or str(hp) != "hitbox_blob":
                push_error("FAIL: slime hitbox_profile_id not blob: %s" % str(hp))
                quit(1)
                return
        print("[OK] enemy_slime.tres -> enemy_slime.glb + hitbox_blob")
        inst.free()
        print("--- SLIME MODEL PROBE: ok=true ---")
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
