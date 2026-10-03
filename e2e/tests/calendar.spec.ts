import { expect, test } from '@playwright/test';
import { button, expectText, goTo, isPhone, longPressDrag, openDemo, replaceText, tap, textOf, tid, typeInto } from './helpers';

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

  test('FR-CAL-09: People shows who’s where, one lane per person', async ({ page }, info) => {
    await openDemo(page, '/calendar');
    await tap(tid(page, 'cal.view.people'));
    for (const lane of ['family', 'p-mom', 'p-dad', 'p-ava']) {
      await expect(tid(page, `cal.lane.2026-10-03.${lane}`)).toBeVisible();
    }
    await expect(tid(page, 'cal.lane.2026-10-03.p-biscuit')).toHaveCount(0);
    // Story time is Ava’s and Dad’s, so it sits in both lanes.
    await expect(tid(page, 'event.block.ev-story')).toHaveCount(2);
    if (!isPhone(info)) {
      await tap(tid(page, 'cal.people.3-days'));
      await expect(tid(page, 'cal.lane.2026-10-05.p-ava')).toBeVisible();
    }
  });

  test('FR-CAL-14: long-press and drag moves an event; Undo puts it back', async ({ page }) => {
    await openDemo(page, '/calendar');
    await tap(tid(page, 'cal.view.day'));
    const block = tid(page, 'event.block.ev-story');
    await expectText(block, '10:30');
    // 45 minutes of grid → one hour is a third more.
    const hour = ((await block.boundingBox())!.height + 2) * (60 / 45);
    await longPressDrag(page, block, 0, hour * 1.05);
    await expectText(tid(page, 'toast'), 'Moved');
    await expectText(block, '11:30');
    await tap(tid(page, 'toast.action'));
    await expectText(block, '10:30');
  });

  test('FR-CAL-19: outdoor events and events with a place show their forecast', async ({ page }) => {
    await openDemo(page, '/calendar');
    await tap(tid(page, 'cal.view.agenda'));
    // Agenda rows speak for their children: the forecast is in the label.
    await expectText(tid(page, 'event.ev-market'), /forecast \w.*°/);
    expect(await textOf(tid(page, 'event.ev-pizza'))).not.toMatch(/forecast/);
    await tap(tid(page, 'event.ev-market').first());
    await expectText(tid(page, 'event.sheet.weather'), '°');
  });

  test('FR-CAL-20: a calendar’s default reminder fires as a banner that talks to the kid', async ({ page }, info) => {
    await openDemo(page, '/settings/calendars');
    await tap(tid(page, 'calendars.cal-family'));
    await tap(tid(page, 'calendars.remind.10'));
    await tap(tid(page, 'sheet.close'));
    await goTo(page, 'calendar');
    if (isPhone(info)) await tap(tid(page, 'nav.add'));
    // The demo clock starts at 8:30: a 10-minute reminder for 8:40 is due.
    await typeInto(page, 'quickadd.input', 'Piano 8:40am Ava');
    await expectText(tid(page, 'quickadd.preview'), 'Piano');
    await page.keyboard.press('Enter');
    await expectText(tid(page, 'reminder.title'), 'Ava, piano in');
    await tap(tid(page, 'reminder.ok'));
    await expect(tid(page, 'reminder.banner')).toHaveCount(0);
  });

  test('FR-CAL-18: holidays are on the calendar, read-only', async ({ page }) => {
    await openDemo(page, '/calendar');
    await tap(tid(page, 'cal.view.month'));
    await tap(tid(page, 'cal.month.2026-10-31'));
    await expect(tid(page, 'cal.daysheet')).toBeVisible();
    await tap(button(page, /^Halloween/));
    await expectText(tid(page, 'event.sheet.title'), 'Halloween');
    await expect(tid(page, 'event.sheet.edit')).toHaveCount(0);
  });
});
