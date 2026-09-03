"""
pipeline.jl - Synmergia content generation pipeline

This is the hot math / content generation pipeline that runs
alongside the Godot game server.

Usage:
    julia --project=. pipeline.jl [command]

Commands:
    generate  - Generate content (NPCs, loot, quests, etc.)
    serve    - Start HTTP server for real-time queries
    stats    - Print system statistics
"""
module Pipeline

using Random
using UUIDs

include("multi_iso.jl")
using .MultiIso

# ============================================================
# Configuration
# ============================================================

const SEED = 42
const NUM_NPCS = 1000
const NUM_ENTITIES = 10_000

# ============================================================
# NPC Generation
# ============================================================

struct NPC
    id::String
    name::String
    faction_id::Int
    spatial_vertex::Int
    level::Int
    difficulty::Symbol
end

function generate_npc(orch::Orchestrator; seed_offset::Int=0)
    rng = MersenneTwister(SEED + seed_offset)
    
    factions = 0:9
    vertices = 0:11
    levels = 1:100
    difficulties = [:common, :elite, :boss, :world_boss]
    
    faction = rand(rng, factions)
    vertex = rand(rng, vertices)
    level = rand(rng, levels)
    difficulty = rand(rng, difficulties)
    
    # Generate name
    prefixes = ["Grim", "Shadow", "Iron", "Crystal", "Storm", "Fire", "Ice", "Void"]
    suffixes = ["claw", "fang", "heart", "soul", "wing", "eye", "scale", "horn"]
    name = rand(rng, prefixes) * " " * rand(rng, suffixes)
    
    # Create entity in orchestrator
    entity = Entity(
        id = string(UUIDs.uuid4()),
        facility = 1,
        spatial_vertex = vertex,
        faction_id = faction,
        birth_year = 2026,
        social_group = 0,
        game_class = level
    )
    register!(orch, entity)
    
    return NPC(entity.id, name, faction, vertex, level, difficulty)
end

function generate_population(n::Int)
    orch = Orchestrator()
    npcs = NPC[]
    
    for i in 1:n
        push!(npcs, generate_npc(orch; seed_offset=i))
    end
    
    return orch, npcs
end

# ============================================================
# Loot Generation
# ============================================================

const RARITIES = [:common, :uncommon, :rare, :epic, :legendary]
const RARITY_WEIGHTS = [0.50, 0.25, 0.15, 0.08, 0.02]

function generate_loot(count::Int)
    rng = MersenneTwister(SEED)
    items = []
    
    for i in 1:count
        rarity = sample(rng, RARITIES, Weights(RARITY_WEIGHTS))
        power = rand(rng, 1:100) * (rarity == :legendary ? 10 : rarity == :epic ? 5 : 1)
        push!(items, (id=i, rarity=rarity, power=power))
    end
    
    return items
end

# ============================================================
# Stats
# ============================================================

function print_stats(orch::Orchestrator, npcs::Vector{NPC})
    println("\n" ^ "=" ^ 60)
    println("SYNMERGIA PIPELINE STATISTICS")
    println("=" ^ 60)
    
    println("\n📊 Entity Counts:")
    println("  Total NPCs: $(length(npcs))")
    println("  Total Entities in Orchestrator: $(length(orch.entities))")
    
    # Faction distribution
    faction_counts = Dict{Int, Int}()
    for npc in npcs
        faction_counts[npc.faction_id] = get(faction_counts, npc.faction_id, 0) + 1
    end
    
    println("\n⚔️ Faction Distribution:")
    for (faction, count) in sort(collect(faction_counts))
        println("  Faction $faction: $count NPCs")
    end
    
    # Vertex distribution
    vertex_counts = Dict{Int, Int}()
    for npc in npcs
        vertex_counts[npc.spatial_vertex] = get(vertex_counts, npc.spatial_vertex, 0) + 1
    end
    
    println("\n🗺️ Spatial Distribution (12 vertices):")
    for vertex in 0:11
        count = get(vertex_counts, vertex, 0)
        bar = "█" ^ div(count, 10)
        println("  Vertex $vertex: $count $bar")
    end
    
    # Difficulty distribution
    difficulty_counts = Dict{Symbol, Int}()
    for npc in npcs
        difficulty_counts[npc.difficulty] = get(difficulty_counts, npc.difficulty, 0) + 1
    end
    
    println("\n🎯 Difficulty Distribution:")
    for diff in [:common, :elite, :boss, :world_boss]
        count = get(difficulty_counts, diff, 0)
        pct = round(count / length(npcs) * 100, digits=1)
        println("  $diff: $count ($pct%)")
    end
    
    # Test query
    println("\n🔍 Sample Query (spatial=vertex 5, faction=3):")
    spatial_set = spatial_at(orch, 5)
    faction_set = faction_eq(orch, 3)
    result = intersect(orch, spatial=spatial_set, faction=faction_set)
    println("  Found $(length(result)) entities")
    
    println("\n" ^ "=" ^ 60)
end

# ============================================================
# CLI Interface
# ============================================================

function main()
    if length(ARGS) == 0
        println("Synmergia Pipeline - Usage:")
        println("  julia pipeline.jl generate  # Generate content")
        println("  julia pipeline.jl stats    # Show statistics")
        println("  julia pipeline.jl loot     # Generate loot table")
        return
    end
    
    cmd = ARGS[1]
    
    if cmd == "generate"
        println("Generating population...")
        orch, npcs = generate_population(NUM_ENTITIES)
        print_stats(orch, npcs)
        
    elseif cmd == "stats"
        println("Generating population for stats...")
        orch, npcs = generate_population(NUM_ENTITIES)
        print_stats(orch, npcs)
        
    elseif cmd == "loot"
        println("Generating loot table...")
        items = generate_loot(100)
        println("\n📦 Sample Loot Table (first 10):")
        for item in items[1:10]
            println("  $(item.rarity): power=$(item.power)")
        end
        
    else
        println("Unknown command: $cmd")
        println("Available: generate, stats, loot")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

end  # module
