import { spawn, ChildProcess } from 'node:child_process';
import { mkdtempSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

/**
 * Starts a test Hub for the run: fresh data dir, deterministic fake
 * providers, demo household, auto-approved pairing, serving the web build.
 * Skipped when DEARTH_E2E_URL points at an already running Hub.
 */
export default async function globalSetup(): Promise<() => Promise<void>> {
  if (process.env.DEARTH_E2E_URL) return async () => {};
  const root = resolve(__dirname, '..');
  const web = join(root, 'apps/dearth_app/build/web');
  if (!existsSync(join(web, 'index.html'))) {
    throw new Error(`No web build at ${web}. Run tool/e2e.sh (it builds first) or flutter build web.`);
  }
  const port = Number(process.env.DEARTH_E2E_PORT ?? 18400);
  const data = mkdtempSync(join(tmpdir(), 'dearth-e2e-'));
  const env = {
    ...process.env,
    DEARTH_DATA_DIR: data,
    DEARTH_PORT: String(port),
    DEARTH_HOST: '127.0.0.1',
    DEARTH_FAKE_PROVIDERS: '1',
    DEARTH_SEED_DEMO: '1',
    DEARTH_AUTO_APPROVE: '1',
    DEARTH_ADMIN_PASSWORD: 'e2e-admin',
    DEARTH_WEB_DIR: web,
    DEARTH_LOG_LEVEL: 'warning',
    TZ: 'America/Denver',
  };
  const bin = process.env.DEARTH_HUB_BIN;
  const hub: ChildProcess = bin
    ? spawn(bin, ['serve'], { env, stdio: 'inherit' })
    : spawn('dart', ['run', 'bin/dearth_hub.dart', 'serve'], { cwd: join(root, 'hub/dearth_hub'), env, stdio: 'inherit' });

  const deadline = Date.now() + 120_000;
  for (;;) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/api/health`);
      if (res.ok) break;
    } catch {
      // not up yet
    }
    if (hub.exitCode !== null) throw new Error(`Test Hub exited early with code ${hub.exitCode}`);
    if (Date.now() > deadline) throw new Error('Test Hub did not start within 120 s');
    await new Promise((r) => setTimeout(r, 500));
  }
  return async () => {
    hub.kill('SIGTERM');
    await new Promise((r) => setTimeout(r, 500));
    rmSync(data, { recursive: true, force: true });
  };
}
