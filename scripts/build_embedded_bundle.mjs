// build_embedded_bundle.mjs - derive the browser build of gamestruct's
// embedded binding (SPEC N27) from the INSTALLED package.
//
// The Godot web shell loads web/ as plain <script> tags (no bundler, no
// import map), and gamestruct ships ESM. So the client half of the boundary
// law -- createFacade -- has to reach the page as a classic script. This
// script is that step: it bundles gamestruct/lib/bindings/embedded.mjs into a
// single IIFE that assigns window.GamestructEmbedded, and the result is
// committed so the page needs no build-time tooling.
//
// The bundle is DERIVED, never hand-edited: `--check` re-renders in memory and
// fails if the committed file has drifted from the installed package (the
// same derive-never-hand-copy law site.config.js follows for the version
// badge). Run after any gamestruct re-pin:
//
//   node scripts/build_embedded_bundle.mjs          # write
//   node scripts/build_embedded_bundle.mjs --check  # verify (CI)
import { build } from 'esbuild';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
const OUT = path.join(ROOT, 'web/shared/gamestruct-embedded.js');

// Resolve through the package exports map so a future move of the file inside
// the package does not silently break the derivation. The package's own
// package.json is not in its exports map, so the version is read off the
// resolved entry's path (node_modules/gamestruct/lib/bindings/embedded.mjs).
const entry = require.resolve('gamestruct/embedded');
const pkgRoot = path.resolve(path.dirname(entry), '..', '..');
const pkgVersion = JSON.parse(readFileSync(path.join(pkgRoot, 'package.json'), 'utf8')).version;

const BANNER = `// gamestruct embedded binding (SPEC N27) - GENERATED, DO NOT EDIT.
//
// Source: gamestruct@${pkgVersion} lib/bindings/embedded.mjs
// Regenerate: node scripts/build_embedded_bundle.mjs
//
// The client half of the boundary law: createFacade({ callbacks, read })
// wraps a host's JSON-string callbacks plus a side-channel reader into the
// four primitives returning parsed objects. The host half (the GDScript
// WebInputBridge hooks) is the other end of the same contract.
`;

async function render() {
    const result = await build({
        entryPoints: [entry],
        bundle: true,
        format: 'iife',
        globalName: 'GamestructEmbedded',
        target: ['es2020'],
        legalComments: 'none',
        banner: { js: BANNER },
        write: false,
        logLevel: 'silent',
    });
    return result.outputFiles[0].text;
}

const text = await render();

if (process.argv.includes('--check')) {
    if (!existsSync(OUT)) {
        console.error(`embedded bundle: FAIL ${path.relative(ROOT, OUT)} is missing - run node scripts/build_embedded_bundle.mjs`);
        process.exit(1);
    }
    const have = readFileSync(OUT, 'utf8');
    if (have !== text) {
        console.error('embedded bundle: FAIL the committed bundle has drifted from the installed gamestruct - run node scripts/build_embedded_bundle.mjs and commit the result');
        process.exit(1);
    }
    console.log(`embedded bundle: in sync with gamestruct@${pkgVersion} - PASS`);
} else {
    writeFileSync(OUT, text);
    console.log(`embedded bundle: wrote ${path.relative(ROOT, OUT)} (${text.length} bytes) from gamestruct@${pkgVersion}`);
}
