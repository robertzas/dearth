import { expect, test } from '@playwright/test';
import { expectText, goTo, isPhone, openDemo, tap, tid, typeInto } from './helpers';

test.describe('Settings', () => {
  test('FR-SET-03: switching to the evening theme and 24 h clock', async ({ page }, info) => {
    await openDemo(page);
    await goTo(page, 'settings');
    if (isPhone(info)) await tap(tid(page, 'settings.nav.household'));
    await tap(tid(page, 'household.clock.24-h'));
    if (isPhone(info)) {
      await tap(tid(page, 'settings.back'));
      await tap(tid(page, 'settings.nav.device'));
    } else {
      await tap(tid(page, 'settings.nav.device'));
    }
    await tap(tid(page, 'device.theme.evening'));
    await goTo(page, 'home');
    if (!isPhone(info)) await expectText(tid(page, 'home.clock'), '8:30');
  });

  test('FR-SET-03: searching Settings finds a setting inside a section, and says when nothing matches', async ({ page }) => {
    await openDemo(page);
    await goTo(page, 'settings');
    await typeInto(page, 'settings.search', 'underground');
    // Only the section holding it is left, naming what matched.
    await expectText(tid(page, 'settings.nav.weather'), 'Weather: Weather Underground');
    await expect(tid(page, 'settings.nav.household')).toHaveCount(0);
    await tap(tid(page, 'settings.nav.weather'));
    await expect(tid(page, 'household.weather.5-min')).toBeVisible();
    await goTo(page, 'settings');
    if ((await tid(page, 'settings.search.clear').count()) > 0) await tap(tid(page, 'settings.search.clear'));
    await typeInto(page, 'settings.search', 'zzzz');
    await expectText(tid(page, 'settings.search.none'), 'Nothing in Settings matches');
  });

  test('§9.3 grown-up PIN gates adult actions once a PIN is set', async ({ page }) => {
    await openDemo(page);
    await goTo(page, 'settings');
    await tap(tid(page, 'settings.nav.people'));
    await tap(tid(page, 'people.p-mom'));
    await tap(tid(page, 'profile.pin.set'));
    for (const _ of [0, 1]) {
      for (const d of ['2', '4', '6', '8']) await tap(tid(page, `pin.key.${d}`));
    }
    await tap(tid(page, 'profile.save'));
    // The lock state shows in the Home header (and the rail on landscape).
    await goTo(page, 'home');
    await expectText(tid(page, 'home.lock'), 'Locked');
    // An adult action now asks for the PIN; the right one unlocks.
    await tap(tid(page, 'home.lock'));
    for (const d of ['2', '4', '6', '8']) await tap(tid(page, `pin.key.${d}`));
    await expectText(tid(page, 'home.lock'), 'Grown-up');
  });
});

test.describe('Kiosk', () => {
  test('§9.3 holding the clock for 3 s opens the kiosk menu', async ({ page }, info) => {
    test.skip(!['wall-l', 'tablet'].includes(info.project.name), 'the rail clock exists on landscape layouts');
    await openDemo(page);
    const clock = tid(page, 'kiosk.clock');
    const box = (await clock.boundingBox())!;
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    await page.waitForTimeout(3300);
    await page.mouse.up();
    await expect(tid(page, 'kiosk.sheet')).toBeVisible();
    await tap(tid(page, 'kiosk.frame'));
    await expect(tid(page, 'screensaver')).toBeVisible();
  });
});
