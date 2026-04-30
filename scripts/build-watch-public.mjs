#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const result = spawnSync('scripts/build-watch.sh', process.argv.slice(2), {
  cwd: rootDir,
  env: {
    ...process.env,
    RISECUE_EMBED_PUBLIC_ENDPOINT_TOKEN: '1'
  },
  stdio: 'inherit'
});

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

process.exit(result.status ?? 1);
