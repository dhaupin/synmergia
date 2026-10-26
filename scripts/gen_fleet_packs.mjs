#!/usr/bin/env node
/**
 * gen_fleet_packs.mjs - the Synmergia fleet's packstruct packs, GENERATED.
 *
 * The deck ride probe hit the runner drift class ourselves (a DEFAULT_SET
 * name with no test file); the packstruct spec (dhaupin/packstruct@1)
 * formalizes the author-time refusal: a manifest that names an entry that
 * does not ship is an instant, nameable violation. So the fleet's packs are
 * DERIVED from the runner's own DEFAULT_SET -- the packs can never claim a
 * test the runner does not carry, and `npx packstruct lint packs/ --deep`
 * is the author-time gate.
 *
 * Usage:  node scripts/gen_fleet_packs.mjs
 *   - reads the DEFAULT_SET block out of scripts/godot_test_runner.sh
 *   - buckets the tests into families (deterministic prefix rules)
 *   - writes packs/public/<family>/{pack.json,main.mjs} (idempotent)
 * Bucketing law: any test the generator cannot file lands in
 * `unfiled-fleet` (which stays checked in and visible), never silently.
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const runner = fs.readFileSync(path.join(repo, 'scripts/godot_test_runner.sh'), 'utf8')

// The DEFAULT_SET block verbatim (between DEFAULT_SET=" and its close).
const m = runner.match(/DEFAULT_SET="([\s\S]*?)"\n/)
if (!m) {
	console.error('gen_fleet_packs: DEFAULT_SET block not found')
	process.exit(2)
}
const tests = m[1].split('\n').map((l) => l.trim().split('#')[0].trim()).filter(Boolean)
if (tests.length === 0) {
	console.error('gen_fleet_packs: DEFAULT_SET parsed empty')
	process.exit(2)
}

// The families. Order matters: first match wins. Names are kebab-case.
const BUCKETS = [
	['fleet-frame', (t) => t.startsWith('frame/')],
	['world-ticks', (t) => /^(test_tick_|test_scope_stack_order)/.test(t)],
	['ocean-ferry', (t) => /^(probe_ocean|probe_swim|probe_water_mounts|probe_ferry|frame\/srv\/test_swim_state|frame\/srv\/test_ferry_schedule$)/.test(t)],
	['arena-bouts', (t) => /^(probe_arena|probe_lobby|probe_bout|probe_trial|test_instance_contract|probe_scene_swap|probe_glider|probe_thermals|probe_royale|probe_riding|probe_duel)/.test(t)],
	['terrain-globe', (t) => /^(probe_stream|probe_planet|probe_terrain|probe_globe_world|test_world_|test_terrain_|probe_sundered|probe_world_lattice|probe_world_state|probe_underworld|probe_world_scoping|globe_driver|probe_blacksmith|probe_wolf|probe_anim|probe_sky_crate|probe_penrose|frame\/math\/test_penrose|frame\/math\/test_pentagrid|frame\/srv\/test_cosmic_rng|frame\/srv\/test_weather|frame\/srv\/test_world_registry|frame\/srv\/test_resource_scan)/.test(t)],
	['concord-services', (t) => /^(test_sign_service|test_daily_class_blessing|test_daily_quest|test_quest_|test_acts_service|test_blessed_mark|test_mysteries|test_audio_service|test_ambience|test_cosmic_service|test_flywheel|test_weather|probe_ancient_loop|probe_harvest|probe_crafting|probe_placeable)/.test(t)],
	['combat-movement', (t) => /^(test_movement_|test_anticheat|test_hitbox|test_layer_|test_combat|probe_climb|probe_calibration|test_a11y|test_data_naming)/.test(t)],
	['social-instances', (t) => /^(probe_dungeon|probe_recent_players|probe_social|probe_startup|probe_round2_ui|probe_character_panel|probe_playtest|probe_ward_gate|probe_world_shape)/.test(t)],
]

// Pack copy: one line per family (pack.json's description; the entry carries
// the same truth so lint --deep's import reads the live sentence).
const COPY = {
	'fleet-frame': 'Frame primitives: co-located NSC-9/KV/srv tests (no autoload, no class_name).',
	'ocean-ferry': 'The ocean layer: swim class, water volumes, ferries, mounts, and the ferry schedule contract.',
	'arena-bouts': 'Instance combat: arena modes, lobby, bouts, thermals, the ROYALE storm, rides and gliders.',
	'terrain-globe': 'The planet: terrain streaming, the 20 km walk/rebase chunks, the model pipeline.',
	'concord-services': 'The Skyward Concord: sky clock, the Chronicle, mysteries, blessings, audio and weather.',
	'combat-movement': 'Movement and combat law: profiles, anticheat stamps, hit tables, accessibility palettes.',
	'world-ticks': 'World plumbing: the tick pipeline and scope stack order.',
	'social-instances': 'World plumbing: gates, UI rounds, the dungeon front door, offline chats.',
	'unfiled-fleet': 'Tests the generator could not file -- NEVER ship work here.',
}

const packsDir = path.join(repo, 'packs/public')
const counts = {}
for (const t of tests) {
	const fam = BUCKETS.find(([, pred]) => pred(t))
	const name = fam ? fam[0] : 'unfiled-fleet'
	;(counts[name] ||= []).push(t)
}

// PRUNE: remove pack dirs whose pack.json carries the generator marker
// but that this run did not (re)write -- a bucket rename must not leave
// stale manifests behind. Non-generated dirs are never touched.
if (fs.existsSync(packsDir)) {
	for (const name of fs.readdirSync(packsDir)) {
		const dir = path.join(packsDir, name)
		const genMarker = path.join(dir, 'pack.json')
		if (!fs.existsSync(genMarker)) continue
		if (!counts[name] && fs.readFileSync(genMarker, 'utf8').includes('Generated from scripts/godot_test_runner.sh')) {
			fs.rmSync(dir, { recursive: true, force: true })
			console.log(`gen_fleet_packs: pruned stale ${name}`)
		}
	}
}

let packs = 0
let unfiled = 0
for (const [name, list] of Object.entries(counts)) {
	const dir = path.join(packsDir, name)
	const desc = COPY[name] || 'Synmergia fleet pack.'
	const cmd = `sh scripts/godot_test_runner.sh ${list.join(' ')}`
	const manifest = {
		schemaVersion: 1,
		name,
		description: `${desc} Generated from scripts/godot_test_runner.sh DEFAULT_SET -- do not hand-edit; run scripts/gen_fleet_packs.mjs.`,
		version: '1.0.0',
		entry: 'main.mjs',
	}
	const entry = `// GENERATED by scripts/gen_fleet_packs.mjs from the runner's DEFAULT_SET.
// ${desc}
// The Godot host runs: ${cmd}
export default {
	name: '${name}',
	description: ${JSON.stringify(desc)},
	command: ${JSON.stringify(cmd)},
	tests: ${JSON.stringify(list, null, '\t')},
}
`
	fs.mkdirSync(dir, { recursive: true })
	fs.writeFileSync(path.join(dir, 'pack.json'), JSON.stringify(manifest, null, 2) + '\n')
	fs.writeFileSync(path.join(dir, 'main.mjs'), entry)
	packs += 1
	if (name === 'unfiled-fleet') unfiled = list.length
}

for (const [name, list] of Object.entries(counts)) {
	console.log(`gen_fleet_packs: ${name} = ${list.length} tests`)
}
console.log(`gen_fleet_packs: ${packs} packs, ${unfiled} unfiled`)
process.exit(0)
