import { expect, test } from '@playwright/test';
import { expectText, goTo, openDemo, scrollTo, tap, tid } from './helpers';

test.describe('Weather', () => {
  test('FR-WX-06: now, next hours, ten days, sun & moon and what to wear', async ({ page }) => {
    await openDemo(page, '/weather');
    await expectText(tid(page, 'weather.now.temp'), '°');
    for (const id of ['weather.hours', 'weather.days', 'weather.sun', 'weather.wear']) {
      await scrollTo(page, id);
    }
  });
});

test.describe('Photo frame', () => {
  test('FR-SSV-01 / FR-SSV-06: starts on demand, shows art without photos, a touch wakes', async ({ page }) => {
    await openDemo(page);
    await goTo(page, 'photos');
    await tap(tid(page, 'photos.start'));
    await expect(tid(page, 'screensaver')).toBeVisible();
    await expectText(tid(page, 'ss.clock'), ':');
    await tap(tid(page, 'screensaver'));
    await expect(tid(page, 'screensaver')).toHaveCount(0);
    await expect(tid(page, 'screen.photos')).toBeVisible();
  });
});
