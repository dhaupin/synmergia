/**
 * scripts/prestruct-build.mjs — run the published prestruct pipeline.
 *
 * `prestruct build` owns validate -> vite build -> inject-brand -> prerender
 * -> postBuild hooks -> audit. The raw Godot shell under dist/game/index.html
 * is not a prerendered page, so the Vite copy plugin defers it while prestruct
 * runs; we copy it in after the audit, exactly as the plugin would during a
 * plain `vite build`.
 */
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
const prestructPackage = require.resolve('prestruct/package.json');
const prestructCli = path.join(path.dirname(prestructPackage), 'bin', 'cli.mjs');

const result = spawnSync(process.execPath, [prestructCli, 'build'], {
  cwd: ROOT,
  stdio: 'inherit',
  env: { ...process.env, PRESTRUCT_BUILD: '1' },
});

if (result.error) {
  console.error('[prestruct-build] failed to start:', result.error.message);
  process.exit(1);
}
if (result.status !== 0) process.exit(result.status ?? 1);

copyGodotWebToDist();

function copyGodotWebToDist() {
  const srcDir = path.join(ROOT, 'web');
  const destDir = path.join(ROOT, 'dist', 'game');
  if (!fs.existsSync(srcDir)) return;

  const MAX_FILE = 25 * 1024 * 1024; // Cloudflare Pages per-file cap
  fs.cpSync(srcDir, destDir, { recursive: true });

  const excluded = [];
  const audit = (dir) => {
    for (const f of fs.readdirSync(dir)) {
      const p = path.join(dir, f);
      if (fs.statSync(p).isDirectory()) {
        audit(p);
      } else if (fs.statSync(p).size > MAX_FILE) {
        excluded.push(
          path.relative(destDir, p) + ' (' + (fs.statSync(p).size / 1048576).toFixed(1) + ' MiB)'
        );
        fs.rmSync(p);
      }
    }
  };
  audit(destDir);

  for (const name of excluded) {
    console.log(
      `[copy-godot-web] EXCLUDED >25MiB: ${name} -> served from R2 via functions/game/`
    );
  }
  if (excluded.length > 0) {
    fs.writeFileSync(path.join(destDir, '_oversize.txt'), excluded.join('\n') + '\n');
  }
  console.log(`[copy-godot-web] web/ -> dist/game/ (${fs.readdirSync(destDir).length} entries)`);
}
