import { defineConfig } from '@playwright/test';

/**
 * Dearth web E2E (SPEC §16.1): every journey runs against the Flutter web
 * build served by a real Hub (fake providers, temp data dir) in four viewport
 * projects. Selectors are semantics identifiers (`flt-semantics-identifier`).
 */
const port = Number(process.env.DEARTH_E2E_PORT ?? 18400);

export default defineConfig({
  testDir: './tests',
  timeout: 120_000,
  expect: { timeout: 20_000 },
  fullyParallel: true,
  // CI runners render in software on 4 cores: two browsers each, and the
  // suite is split across twenty runners (--shard). Locally three: more
  // browsers drawing wall-size Flutter at once starve each other and
  // journeys start timing out (8 on a 16-core machine did).
  workers: process.env.CI ? 2 : 3,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }], ['github']] : [['list'], ['html', { open: 'never' }]],
  globalSetup: require.resolve('./global-setup'),
  use: {
    baseURL: process.env.DEARTH_E2E_URL ?? `http://127.0.0.1:${port}`,
    timezoneId: 'America/Denver',
    locale: 'en-US',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    // CI runners have no GPU: Flutter's renderer needs WebGL, which Chrome
    // only provides there through SwiftShader when explicitly allowed.
    launchOptions: {
      args: ['--enable-unsafe-swiftshader'],
      ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}),
    },
  },
  projects: [
    { name: 'wall-l', use: { viewport: { width: 1920, height: 1080 } } },
    { name: 'wall-p', use: { viewport: { width: 1080, height: 1920 } } },
    { name: 'tablet', use: { viewport: { width: 1280, height: 800 }, hasTouch: true } },
    { name: 'phone', use: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true } },
  ],
});
