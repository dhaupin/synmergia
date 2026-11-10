// verify_lane.mjs — prove the installed gamestruct lane works from Synmergia.
//
// The world<->brain contract lives in the gamestruct npm package (MIT). This
// receipt imports it the way the web control client / a companion brain would
// and checks the pieces Synmergia depends on: the core tree vocabulary, the
// client (DoorClient), and the Synmergia adapter's door normalizer (`doorNodes`,
// which folds the door's own observe() snapshot into the SPEC node shape).
//
// Run: npm run verify:lane   (exit 0 = the lane is installed and usable)

import { ROLES, Bridge, agent } from 'gamestruct';
import { DoorClient } from 'gamestruct/adapters/vant';
import { doorNodes, buildBridge } from 'gamestruct/adapters/synmergia';

let pass = 0;
let fail = 0;
function check(name, cond) {
    if (cond) { pass += 1; console.log('  ok   ', name); }
    else { fail += 1; console.log('  FAIL ', name); }
}

// 1. the core vocabulary is present
check('core: ROLES.BUTTON', ROLES && ROLES.BUTTON === 'button');
check('core: Bridge is a class', typeof Bridge === 'function');
check('core: agent.toolCatalog', typeof agent.toolCatalog === 'function');

// 2. the client + the Synmergia door normalizer are present
check('vant: DoorClient', typeof DoorClient === 'function');
check('synmergia: doorNodes', typeof doorNodes === 'function');

// 3. doorNodes folds the door's own observe() wire shape into SPEC nodes
const nodes = doorNodes({
    scene: 'Login', in_world: false,
    actions: [
        { id: 'ui:Login/Form/UsernameField', kind: 'lineedit', action: 'Username input field', disabled: false, value: '' },
        { id: 'ui:Login/Form/Buttons/LoginButton', kind: 'button', action: 'Login', disabled: false },
    ],
});
check('doorNodes: one node per actionable', nodes.length === 2);
check('doorNodes: handle survives unchanged', nodes.some((n) => n.id === 'ui:Login/Form/Buttons/LoginButton'));
check('doorNodes: a settable control advertises set_value',
    nodes.find((n) => n.id.endsWith('UsernameField'))?.actions.includes('set_value'));

// 4. a local Bridge builds the same catalog both lanes read
const b = new Bridge({ name: 'synmergia-lane-check' });
b.tree.add(null, { id: 'ui:start', role: ROLES.BUTTON, name: 'Start' });
check('bridge: agent catalog sees the handle',
    agent.toolCatalog(b).some((t) => t._handle === 'ui:start'));

// 5. the SPEC v1.1 additions the lane depends on (the eyes + the catalog leg).
//    The door serves /see; DoorClient.see must exist, and catalog() must build
//    from observe().nodes (the 1.1.0 fix that reads a world door's own snapshot).
check('vant: DoorClient.see (the eyes)', typeof DoorClient.prototype.see === 'function');
check('vant: DoorClient.catalog (the tool list)', typeof DoorClient.prototype.catalog === 'function');
check('synmergia: buildBridge (the world mapping)', typeof buildBridge === 'function');

// 6. an offline DoorClient over a stub door: observe -> doorNodes -> catalog.
//    A door with a settable control advertises set_value; a door that serves
//    /see advertises the eyes tool. No network -- the stub is the fetch.
const seen = [];
globalThis.fetch = async (url, opts) => {
    const path = String(url).replace(/^https?:\/\/[^/]+/, '');
    seen.push(path);
    const body = path.startsWith('/observe')
        ? { scene: 'Login', in_world: false, actions: [
            { id: 'ui:Login/User', kind: 'lineedit', action: 'User', disabled: false, value: '' },
            { id: 'ui:Login/Go', kind: 'button', action: 'Go', disabled: false },
        ] }
        : { ok: true, path: '/tmp/frame.png', bytes: 4096 };
    return { ok: true, status: 200, json: async () => body, text: async () => JSON.stringify(body) };
};
const client = new DoorClient({ url: 'http://stub.local', token: 't', mapNodes: doorNodes });
const catalog = await client.catalog();
check('stub door: catalog builds from observe().nodes',
    catalog.ok !== false && (catalog.tools || catalog.nodes || []).length >= 2);
check('stub door: the eyes tool is advertised (serves /see)',
    (catalog.tools || catalog.nodes || []).some((t) => (t.name || '') === 'see'));
const shot = await client.see({ label: 'lane-check' });
check('stub door: see() returns the frame descriptor', shot && shot.ok === true && !!shot.path);

console.log(`\nLANE-VERIFY: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
