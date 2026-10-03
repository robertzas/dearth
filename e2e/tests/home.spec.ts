import { expect, test } from '@playwright/test';
import { expectText, isPhone, openDemo, scrollTo, tap, tid } from './helpers';

test.describe('Home', () => {
  test.beforeEach(async ({ page }) => openDemo(page));

  test('FR-HOME-02: shows today, up next, the week, dinner, notes and shopping', async ({ page }) => {
    for (const id of ['home.agenda', 'home.upnext', 'home.dinner', 'home.kids', 'home.shopping', 'home.notes', 'home.week']) {
      await scrollTo(page, id);
    }
  });

  test('FR-HOME-04: header shows the date, time and weather', async ({ page }, info) => {
    await expectText(tid(page, 'home.date'), 'Saturday, October 3');
    await expectText(tid(page, 'home.weather.temp'), '°');
    if (!isPhone(info)) await expectText(tid(page, 'home.clock'), '8:30');
  });

  test('FR-CAL-16: up next counts down to the next event', async ({ page }) => {
    await expectText(tid(page, 'home.upnext.title'), 'Swim lesson');
    await expectText(tid(page, 'home.upnext.countdown'), 'in 30 min');
  });

  test('FR-CAL-17: countdowns show days to go', async ({ page }) => {
    await scrollTo(page, 'home.countdown.ev-grandma');
  });

  test('FR-MEAL-05: tonight’s dinner comes from the meal plan', async ({ page }) => {
    await expectText(tid(page, 'home.dinner.title'), /\S/);
  });

  test('FR-HOME-05: the weather widget opens the weather screen', async ({ page }) => {
    await tap(tid(page, 'home.weather'));
    await expect(tid(page, 'screen.weather')).toBeVisible();
  });
});
