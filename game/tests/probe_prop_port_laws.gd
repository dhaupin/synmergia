## probe_prop_port_laws -- the v7 prop laws the fold must carry.
##
## The prop fold (labs/prd-clipmap.md 9.5 port surface + 13 LANE A) moved the
## retired streamer's prop taxonomy into PropLayer. Three of those laws were the
## retired streamer's v7 texture: the VINE HANGS on wet-band canopies (TREE family),
## the SCREE COLLAR on rocky-band rocks (ROCK family), and the RIM COLLAR on
## boulders (BOULDER family). This receipt pins all three against a stub
## provider that forces the biome each law keys off, so the check is
## independent of where the boot happens to land.
##
## Run: godot --headless --path . --script res://tests/probe_prop_port_laws.gd
extends SceneTree

const PropLayer = preload("res://core/world/prop_layer.gd")
const PropChunk = preload("res://core/frame/geometry/prop_chunk.gd")
const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")
const GroundProvider = preload("res://core/world/ground_provider.gd")

var _fails: int = 0


## A stub provider: a flat land at height 10, a caller-chosen biome, one rock
## and one boulder on face 0, and a tree density so every chunk plants trees.
class StubProvider extends GroundProvider:
        var _biome: int = TerrainGen.BiomeId.JUNGLE
        var _face: int = PropChunk.face_of(PropChunk.chunk_for_dir(Vector3(0, 1, 0), 6))

        func ground_height(_dir: Vector3) -> float:
                return 10.0

        func biome_id(_dir: Vector3) -> int:
                return _biome

        func species_at(_dir: Vector3) -> int:
                return TerrainGen.TreeSpecies.BROADLEAF

        func sea_level() -> float:
                return -1.0e9

        func tree_density(_bid: int) -> float:
                return 30.0

        func detail_density(_bid: int) -> float:
                return 0.0

        func seed_bytes() -> PackedByteArray:
                var b := PackedByteArray()
                b.resize(32)
                for i in range(32):
                        b[i] = (i * 7 + 3) & 0xFF
                return b

        func rock_specs(face: int) -> Array:
                if face != _face:
                        return []
                return [_rock()]

        func boulder_specs(face: int) -> Array:
                if face != _face:
                        return []
                return [_boulder()]

        func _rock():
                var s = load("res://scenes/worlds/terrain_gen.gd").RockSpec.new()
                s.dir = PropChunk.chunk_center_dir(PropChunk.chunk_for_dir(Vector3(0, 1, 0), 6), 6)
                s.scale = 1.5
                s.yaw = 0.0
                return s

        func _boulder():
                var s = load("res://scenes/worlds/terrain_gen.gd").BoulderSpec.new()
                s.dir = PropChunk.chunk_center_dir(PropChunk.chunk_for_dir(Vector3(0, 1, 0), 6), 6)
                s.radius = 2.0
                s.yaw = 0.0
                return s
func _init() -> void:
        call_deferred("_run")


func _run() -> void:
        _test_vine_law()
        _test_scree_law()
        _test_collar_law()
        print("--- PROP PORT LAWS: %d passed, %d failed ---" % [_passed, _fails])
        quit(0 if _fails == 0 else 1)


var _passed: int = 0


func _check(label: String, cond: bool) -> void:
        if cond:
                _passed += 1
                print("  [OK] ", label)
        else:
                _fails += 1
                print("  [FAIL] ", label)


func _layer_for(provider) -> RefCounted:
        var layer = PropLayer.new()
        var parent := Node3D.new()
        get_root().add_child(parent)
        layer.configure(provider, 20000.0, parent)
        layer.chunk_depth = 6
        return layer


func _key() -> int:
        return PropChunk.chunk_for_dir(Vector3(0, 1, 0), 6)


## A1/A2: a JUNGLE tree site carries vine hangs; a DEAD_SNAG carries none.
func _test_vine_law() -> void:
        var prov = StubProvider.new()
        var layer = _layer_for(prov)
        var data: Dictionary = layer.derive_fresh(_key())
        var trees: Array = []
        for inst in data.get("instances", []):
                if int(inst.get("family", -1)) == layer.FAMILY_TREE:
                        trees.append(inst)
        _check("A1 the jungle chunk derives tree sites", trees.size() > 0)
        var any_vines: bool = false
        for t in trees:
                if int(t.get("vine_n", 0)) > 0:
                        any_vines = true
        _check("A2 jungle trees carry vine hangs (vine_n > 0)", any_vines)

        # Build the chunk and count the real hang nodes on a tree node.
        layer._build_chunk(_key(), Vector3(0, 1, 0))
        var built = layer._built.get(_key())
        var hangs: int = 0
        var tree_nodes: int = 0
        for ch in built.get_children():
                if String(ch.name).begins_with("Tree"):
                        tree_nodes += 1
                        for sub in ch.get_children():
                                if sub is MeshInstance3D and sub.mesh is CylinderMesh \
                                                and sub.mesh.height < 3.5 and sub.mesh.top_radius < 0.1:
                                        hangs += 1
        _check("A3 the built tree nodes carry hang meshes (%d hangs on %d trees)" % [hangs, tree_nodes], hangs > 0)

        # A dead snag bears no vines even in the jungle.
        prov._biome = TerrainGen.BiomeId.JUNGLE
        var layer2 = _layer_for(prov)
        var data2: Dictionary = layer2.derive_fresh(_key())
        var snag_ok := true
        for inst in data2.get("instances", []):
                if int(inst.get("family", -1)) == layer.FAMILY_TREE \
                                and int(inst.get("species", -1)) == TerrainGen.TreeSpecies.DEAD_SNAG \
                                and int(inst.get("vine_n", 0)) != 0:
                        snag_ok = false
        _check("A4 a dead snag carries no vine hangs", snag_ok)


## A5/A6: an ALPINE rock carries a scree collar; a GRASSLAND rock does not.
func _test_scree_law() -> void:
        var prov = StubProvider.new()
        prov._biome = TerrainGen.BiomeId.ALPINE
        var layer = _layer_for(prov)
        var data: Dictionary = layer.derive_fresh(_key())
        var rock: Dictionary = {}
        for inst in data.get("instances", []):
                if int(inst.get("family", -1)) == layer.FAMILY_ROCK:
                        rock = inst
        _check("A5 the alpine chunk derives its rock", not rock.is_empty())
        _check("A6 an alpine rock carries a scree collar", rock.get("scree", []).size() >= 2)

        var prov2 = StubProvider.new()
        prov2._biome = TerrainGen.BiomeId.GRASSLAND
        var layer2 = _layer_for(prov2)
        var data2: Dictionary = layer2.derive_fresh(_key())
        var rock2: Dictionary = {}
        for inst in data2.get("instances", []):
                if int(inst.get("family", -1)) == layer2.FAMILY_ROCK:
                        rock2 = inst
        _check("A7 a grassland rock carries no scree collar", rock2.get("scree", []).size() == 0)

        # Build the alpine chunk: the Scree nodes exist.
        layer._build_chunk(_key(), Vector3(0, 1, 0))
        var built = layer._built.get(_key())
        var scree_nodes: int = 0
        for ch in built.get_children():
                if String(ch.name).begins_with("Scree"):
                        scree_nodes += 1
        _check("A8 the built alpine chunk holds Scree nodes", scree_nodes >= 2)


## A9/A10: a boulder carries a rim collar; the collar builds real nodes.
func _test_collar_law() -> void:
        var prov = StubProvider.new()
        var layer = _layer_for(prov)
        var data: Dictionary = layer.derive_fresh(_key())
        var boulder: Dictionary = {}
        for inst in data.get("instances", []):
                if int(inst.get("family", -1)) == layer.FAMILY_BOULDER:
                        boulder = inst
        _check("A9 the chunk derives its boulder", not boulder.is_empty())
        _check("A10 a boulder carries a rim collar", boulder.get("collar", []).size() >= 1)

        layer._build_chunk(_key(), Vector3(0, 1, 0))
        var built = layer._built.get(_key())
        var collar_nodes: int = 0
        for ch in built.get_children():
                if String(ch.name).begins_with("Collar"):
                        collar_nodes += 1
        _check("A11 the built chunk holds Collar nodes", collar_nodes >= 1)
