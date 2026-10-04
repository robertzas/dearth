import { expect, test } from '@playwright/test';
import { expectText, goTo, openDemo, scrollTo, tap, tid } from './helpers';

// Demo: Ava (Little stage, bunny buddy) has four chores today, two routines,
// 6 stickers earned with 5 placed, and 4 of 10 jar tokens.

test.describe('Kids', () => {
  test('FR-KID-03: “I did it!” completes a chore with a celebration and a new sticker', async ({ page }) => {
    await openDemo(page, '/kids');
    const shoes = await scrollTo(page, 'kids.chore.ch-shoes');
    await expectText(shoes, 'tap when you did it');
    await tap(shoes);
    await expect(tid(page, 'celebration')).toBeVisible();
    await expectText(tid(page, 'toast'), 'Shoes in the basket: done!');
    await expectText(tid(page, 'kids.chore.ch-shoes'), 'Done');
    await expectText(tid(page, 'kids.chart.progress'), '⭐');
    await expectText(await scrollTo(page, 'kids.stickers'), '2 to place');
  });

  test('FR-KID-03: Undo puts the chore back', async ({ page }) => {
    await openDemo(page, '/kids');
    await tap(await scrollTo(page, 'kids.chore.ch-books'));
    await expectText(tid(page, 'kids.chore.ch-books'), 'Done');
    await tap(tid(page, 'toast.action'));
    await expectText(tid(page, 'kids.chore.ch-books'), 'tap when you did it');
  });

  test('FR-KID-12: pick a sticker and place it on the scene', async ({ page }) => {
    await openDemo(page, '/kids');
    await tap(await scrollTo(page, 'kids.stickers'));
    await expect(tid(page, 'screen.stickers')).toBeVisible();
    await expectText(tid(page, 'stickers.prompt'), 'Pick a sticker!');
    await tap(tid(page, 'stickers.choice.0'));
    const scene = await tid(page, 'stickers.scene').boundingBox();
    expect(scene).not.toBeNull();
    await page.mouse.click(scene!.x + scene!.width * 0.5, scene!.y + scene!.height * 0.45);
    await expect(tid(page, 'stickers.prompt')).toHaveCount(0);
    await tap(tid(page, 'stickers.close'));
    await expect(tid(page, 'screen.kids')).toBeVisible();
  });

  test('FR-KID-06/07: a routine runs step by step and keeps its progress', async ({ page }) => {
    await openDemo(page, '/kids');
    await tap(await scrollTo(page, 'kids.routine.rt-morning'));
    await expect(tid(page, 'screen.routine')).toBeVisible();
    await expectText(tid(page, 'routine.progress'), 'Step 1 of 6');
    await expectText(tid(page, 'routine.step'), 'Potty');
    await tap(tid(page, 'routine.done'));
    await expectText(tid(page, 'routine.progress'), 'Step 2 of 6');
    await expectText(tid(page, 'routine.step'), 'Wash hands');
    await expectText(tid(page, 'routine.timer'), 'Start the timer, 0:20');
    await tap(tid(page, 'routine.timer'));
    await expectText(tid(page, 'routine.timer'), 'Timer running');
    await tap(tid(page, 'routine.close'));
    await expectText(tid(page, 'kids.routine.rt-morning'), '1 of 6 steps');
  });

  test('FR-CAL-10: the Kids screen starts with Ava’s day in pictures; a routine starts from its picture', async ({ page }) => {
    await openDemo(page, '/kids');
    await expect(tid(page, 'kids.myday')).toBeVisible();
    await expect(tid(page, 'timeline.p-ava.now')).toBeVisible();
    // The morning routine's picture sits next to now, so it's on screen at
    // every size (the strip scrolls sideways on phones, opening at now).
    await tap(await scrollTo(page, 'timeline.p-ava.stop.routine-rt-morning'));
    await expectText(tid(page, 'timeline.sheet.title'), 'Good morning');
    await tap(tid(page, 'timeline.sheet.start'));
    await expect(tid(page, 'screen.routine')).toBeVisible();
  });

  test('FR-KID-05: grown-ups tick off household chores', async ({ page }) => {
    await openDemo(page, '/kids');
    await tap(tid(page, 'kids.tab.grown-ups'));
    const laundry = await scrollTo(page, 'grownups.chore.ch-laundry');
    await expectText(laundry, 'Laundry');
    await tap(laundry);
    await expectText(tid(page, 'grownups.chore.ch-laundry'), 'Done');
    await expectText(await scrollTo(page, 'kids.family'), '13 of 40');
  });

  test('FR-HOME: the Home kids card opens the Kids screen', async ({ page }) => {
    await openDemo(page);
    await tap(await scrollTo(page, 'home.kids'));
    await expect(tid(page, 'screen.kids')).toBeVisible();
    await goTo(page, 'kids');
  });
});
