import { expect, test } from '@playwright/test';
import { button, expectText, isPhone, openDemo, replaceText, tap, tid, typeInto } from './helpers';

test.describe('Calendar', () => {
  test('FR-CAL-12: quick add parses natural language with a live preview', async ({ page }, info) => {
    await openDemo(page, '/calendar');
    if (isPhone(info)) await tap(tid(page, 'nav.add'));
    await typeInto(page, 'quickadd.input', 'Pottery class tomorrow 4pm Ava');
    await expectText(tid(page, 'quickadd.preview'), 'Pottery class');
    await expectText(tid(page, 'quickadd.preview'), 'Tomorrow');
    await page.keyboard.press('Enter');
    await expectText(tid(page, 'toast'), 'Added');
    await tap(tid(page, 'cal.view.agenda'));
    await expect(button(page, /Pottery class/)).toBeVisible();
  });

  test('FR-CAL-05..08: day, 3-day, week, month and agenda views render', async ({ page }, info) => {
    await openDemo(page, '/calendar');
    const views = isPhone(info) ? ['day', '3-days', 'month', 'agenda'] : ['day', '3-days', 'week', 'month', 'agenda'];
    for (const v of views) {
      await tap(tid(page, `cal.view.${v}`));
      await expectText(tid(page, 'cal.title'), /\S/);
    }
    await tap(tid(page, 'cal.view.month'));
    await expect(tid(page, 'cal.month.2026-10-03')).toBeVisible();
    await tap(tid(page, 'cal.month.2026-10-03'));
    await expect(tid(page, 'cal.daysheet')).toBeVisible();
    await expect(button(page, /Swim lesson/)).toBeVisible();
  });

  test('FR-CAL-11: person filters narrow the calendar, family events stay', async ({ page }) => {
    await openDemo(page, '/calendar');
    await tap(tid(page, 'cal.view.agenda'));
    await expect(button(page, /^Dentist/)).toBeVisible();
    await tap(tid(page, 'cal.filter.p-dad'));
    await expect(button(page, /^Dentist/)).toHaveCount(0);
    await expect(button(page, /^Pizza night/)).toBeVisible();
    await tap(tid(page, 'cal.filter.all'));
    await expect(button(page, /^Dentist/)).toBeVisible();
  });

  test('FR-CAL-13: edit an event from its sheet', async ({ page }) => {
    await openDemo(page, '/calendar');
    await tap(tid(page, 'cal.view.agenda'));
    await tap(tid(page, 'event.ev-dentist').first());
    await expectText(tid(page, 'event.sheet.title'), 'Dentist');
    await tap(tid(page, 'event.sheet.edit'));
    await replaceText(page, 'editor.title', 'Dentist checkup');
    await tap(tid(page, 'editor.save'));
    await expect(button(page, /^Dentist checkup/)).toBeVisible();
  });

  test('FR-CAL-13: delete one day of a repeating event', async ({ page }) => {
    await openDemo(page, '/calendar');
    await tap(tid(page, 'cal.view.agenda'));
    // Monday Oct 5 only has the daycare drop-off; deleting that one instance
    // empties the day (agenda skips empty days) while Tuesday keeps its own.
    await expect(tid(page, 'agenda.day.2026-10-05')).toBeVisible();
    await tap(tid(page, 'event.ev-daycare').first());
    await tap(tid(page, 'event.sheet.delete'));
    await tap(tid(page, 'event.scope.single'));
    await expectText(tid(page, 'toast'), 'Deleted');
    await expect(tid(page, 'agenda.day.2026-10-05')).toHaveCount(0);
    await expect(tid(page, 'agenda.day.2026-10-06')).toBeVisible();
  });
});
