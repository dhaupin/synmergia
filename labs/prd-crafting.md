# PRD: Crafting -- making things lawfully
(S16.9, 2026-10-08. Third leg of the economy loop beside
prd-gathering.md (inputs) and prd-blacksmith.md (upgrade).)

## 0. The thesis

Crafting is not a minigame; it is a GATE. A recipe is data truth
(like every catalog in this repo): inputs, station, output, and the
failure posture. The crafter brings the bill of materials, the
service checks the ONE purse chain, and the output is an Item .tres
id -- the service invents nothing. Every craft is a world delta with
the full bill as provenance, so "where did this sword come from" is
always answerable.

## 1. Recipe shape (data truth)

    RecipeData (core/schemas/recipe_data.gd, recipe_ prefix,
    filename == id -- the catalog law):
      id, display_name
      station        NONE / FORGE / WORKBENCH / ALCHEMY
      inputs         [{item_id, qty}]     (ores, mats, components)
      output         {item_id, qty}
      byproducts     [{item_id, qty}]    (slag, scraps -- economy sink)
      craft_time_sec 0 for instant, >0 for a timed forge (world delta
                     on start AND finish -- a craft you can walk away
                     from is a craft you can lose, see 3)
      required_level, failure_rate

## 2. The gate chain (one shape, all stations)

    craft(player_id, recipe_id, times) ->
      {ok, reason | output:{item_id, qty}}
      - recipe exists (data is the law)
      - station proximity (the station node is an interaction target,
        the AncientDoor pattern)
      - purse has ALL inputs (InventoryService, no partial consumes)
      - QoS rate limit
      - failure roll (failure_rate from BalanceData): on failure the
        byproducts drop, the inputs are GONE (the forge eats)
      - success: inputs consumed, output granted, byproducts granted
      - world delta: craft/<recipe_id>/<short_nonce> with provenance
        (actor, epoch, inputs, output) -- the bill of materials IS
        the provenance

## 3. The timed forge (why craft_time exists)

An instant craft is a spreadsheet; a timed forge is a world event.
The forge START writes a delta (forge lit, actor, recipe), the finish
writes the outcome. Walking away mid-forge loses the forge (inputs
and all) -- the world does not hold your hand, and the blacksmith's
gamble spirit starts here, not at the upgrade anvil.

## 4. The economy loop (all three legs)

    gather (prd-gathering) -> craft (this) -> upgrade (prd-blacksmith)
    -> the item dies in a failed forge or wins -> drops/ledger feeds
    the next gatherer.

Recipes bind the legs: tools gate gathering (a forged pick harvests
higher grades), sacrifice items feed the blacksmith, byproducts feed
lower recipes. No recipe should exist that the loop cannot feed.

## 5. Species and agents (the citizen law, standing)

No recipe, station, or craft gate may special-case species or
agent/human. Everything rides the same purse chain, the same world
deltas, the same provenance. The agent law (prd-agent-law.md) watches
CRAFT CADENCE like harvest cadence -- a craft bot is a detector
class, not a design exception.

## 6. Build order

1. RecipeData schema + DataService scan (data/recipes/).
2. CraftingService: the gate chain above, headless probe first
   (same shape as probe_harvest).
3. Station interaction nodes (FORGE first -- it feeds the
   blacksmith directly).
4. Tool recipes (gathering gate closes the loop).
5. Timed forges (v2 -- start/finish deltas).

## 7. Explicitly out of scope

- Gem sockets (blacksmith PRD 5).
- Recipe discovery/unlock progression (later; recipes are lawful to
  read from day one -- knowledge gates, not artificial locks).
- Crafting XP or crafter levels (the ITEMS carry tier, not the
  crafter; a master smith is made by the forge's risks, not a bar).
