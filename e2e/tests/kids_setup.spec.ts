import { expect, test } from '@playwright/test';
import { button, expectText, goTo, openDemo, scrollTo, tap, textOf, tid, typeInto } from './helpers';

// Settings → Kids & chores. The demo has no PINs, so grown-up mode is open.

test.describe('Kids & chores settings', () => {
  test('FR-KID-04: a chore idea from the library lands on the kid’s chart', async ({ page }) => {
    await openDemo(page, '/settings/kids');
    await tap(await scrollTo(page, 'chores.ideas'));
    await expect(tid(page, 'chores.ideas.sheet')).toBeVisible();
    const idea = tid(page, 'chores.idea.0');
    const title = (await textOf(idea)).split(',')[0].trim();
    expect(title.length).toBeGreaterThan(2);
    await tap(idea);
    await expectText(tid(page, 'toast'), `Added “${title}” for Ava`);
    await tap(tid(page, 'sheet.close'));
    await goTo(page, 'kids');
    await expect(button(page, new RegExp(`^${title}`))).toBeVisible();
  });

  test('FR-KID-01: a custom weekend chore with its own picture', async ({ page }) => {
    await openDemo(page, '/settings/kids');
    await tap(await scrollTo(page, 'chores.add'));
    await expect(tid(page, 'chore.editor')).toBeVisible();
    await typeInto(page, 'chore.title', 'Feed the fish');
    await tap(tid(page, 'chore.emoji'));
    await tap(tid(page, 'picker.emoji.36')); // 🐟
    await tap(tid(page, 'chore.who.p-ava'));
    await tap(tid(page, 'chore.schedule.weekends'));
    await tap(tid(page, 'chore.save'));
    await expectText(tid(page, 'toast'), 'Saved “Feed the fish”');
    await expect(button(page, /^Feed the fish, Ava · Weekends/)).toBeVisible();
    await goTo(page, 'kids'); // the demo's today is a Saturday
    await expect(button(page, /^Feed the fish/)).toBeVisible();
  });

  test('FR-KID-06/11: a routine from a template, with an extra step', async ({ page }) => {
    await openDemo(page, '/settings/kids');
    await tap(await scrollTo(page, 'routines.add'));
    await tap(tid(page, 'routines.template.2'));
    await expect(tid(page, 'routine.editor')).toBeVisible();
    await tap(await scrollTo(page, 'routine.step.add'));
    await typeInto(page, 'routine.step.4', 'Happy dance');
    await tap(await scrollTo(page, 'routine.save'));
    await expectText(tid(page, 'toast'), 'Saved “Clean-up time”');
    await goTo(page, 'kids');
    await expect(button(page, /^Clean-up time, 5 steps|^Clean-up time, 0 of 5 steps/)).toBeVisible();
  });

  test('FR-KID-14: add a star-store reward from the ideas', async ({ page }) => {
    await openDemo(page, '/settings/kids');
    await tap(await scrollTo(page, 'rewards.add'));
    await tap(tid(page, 'rewards.idea.1'));
    await expect(tid(page, 'reward.editor')).toBeVisible();
    await tap(tid(page, 'reward.cost.plus'));
    await tap(tid(page, 'reward.save'));
    await expectText(tid(page, 'toast'), 'Saved “Dance party”');
    await expect(button(page, /^Dance party, Star store · 6 ⭐/)).toBeVisible();
  });
});
