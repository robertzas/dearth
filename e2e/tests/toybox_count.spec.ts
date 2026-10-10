import { expect, test } from '@playwright/test';
import { expectCheered, expectText, idsUnder, openToyboxGame, tap, textOf, tid } from './helpers';

// The Toybox's third set, six number games built on her longest-played
// games (SPEC FR-TOY-03), played from what the screen shows (labels). The
// widget tests check which clips play.

test.describe('Toybox third set', () => {
  test('FR-TOY-03: Creature Count — she gives the creature as many parts as the voice asks for and makes it dance', async ({ page }) => {
    await openToyboxGame(page, 'creaturecount');
    await expectText(tid(page, 'creaturecount.ask'), /^Give it \d+ (eye|leg|horn|spot)s?$/);
    const [, n, part] = (await textOf(tid(page, 'creaturecount.ask'))).match(/Give it (\d+) (eye|leg|horn|spot)/)!;
    for (let i = 1; i <= Number(n); i++) {
      await tap(tid(page, `creaturecount.add.${part}s`));
      // One part a tap: wait for it to land before the next.
      await expectText(tid(page, 'creaturecount.creature'), `Creature: ${i} ${part}${i === 1 ? '' : 's'}`);
    }
    await tap(tid(page, 'creaturecount.dance'));
    // A lasting label: it stays until the next creature.
    await expectText(tid(page, 'creaturecount.ask'), /^Yay! /);
    await expectCheered(page);
  });

  test('FR-TOY-03: Snack Snap — she taps the plate with the number of treats the monster asks for', async ({ page }) => {
    await openToyboxGame(page, 'snacksnap');
    await expectText(tid(page, 'snacksnap.ask'), /^Snack: (\d+) treats?$/);
    const want = (await textOf(tid(page, 'snacksnap.ask'))).match(/^Snack: (\d+) treats?$/)![1];
    // The plates are labelled by what they hold.
    const plates = await idsUnder(page, 'snacksnap.plate.');
    const wanted = `Plate with ${want} treat${want === '1' ? '' : 's'}`;
    const target = (await Promise.all(plates.map(async (id) => [id, await textOf(tid(page, id))] as const))).find(([, label]) => label === wanted)![0];
    await tap(tid(page, target));
    await expectText(tid(page, 'snacksnap.ask'), /^Yum! /);
    await expectCheered(page);
  });

  test('FR-TOY-03: Finger Count — she raises the fingers the voice asks for and gives a high five', async ({ page }) => {
    await openToyboxGame(page, 'fingers');
    await expectText(tid(page, 'fingers.ask'), /^Show (\d+)$/);
    const n = Number((await textOf(tid(page, 'fingers.ask'))).match(/^Show (\d+)$/)![1]);
    for (let i = 1; i <= n; i++) {
      await tap(tid(page, 'fingers.palm.right'));
      await expectText(tid(page, 'fingers.hand.right'), `Right hand: ${i} ${i === 1 ? 'finger' : 'fingers'} up`);
    }
    await tap(tid(page, 'fingers.done'));
    await expectText(tid(page, 'fingers.ask'), /^Yay! /);
    await expectCheered(page);
  });

  test('FR-TOY-03: Animal Race — she taps the animal that came where the voice asks', async ({ page }) => {
    await openToyboxGame(page, 'race');
    // The race runs before the question.
    await expectText(tid(page, 'race.ask'), /^Who came (\d)(st|nd|rd|th)\?$|^Who came last\?$/, 30000);
    const asked = (await textOf(tid(page, 'race.ask'))).match(/^Who came (.+)\?$/)![1];
    const animals = await idsUnder(page, 'race.animal.');
    const labelled = await Promise.all(animals.map(async (id) => [id, await textOf(tid(page, id))] as const));
    const place = (label: string) => Number(label.match(/came (\d)/)![1]);
    const target = asked === 'last'
      ? labelled.reduce((a, b) => (place(a[1]) > place(b[1]) ? a : b))
      : labelled.find(([, label]) => label.endsWith(`came ${asked}`))!;
    await tap(tid(page, target[0]));
    await expectText(tid(page, 'race.ask'), /^Yes! /);
    await expectCheered(page);
  });

  test('FR-TOY-03: Bead Slider — she slides the beads across and rings the bell', async ({ page }) => {
    await openToyboxGame(page, 'beads');
    await expectText(tid(page, 'beads.ask'), /^Show (\d+)$/);
    const n = Number((await textOf(tid(page, 'beads.ask'))).match(/^Show (\d+)$/)![1]);
    await tap(tid(page, `beads.bead.0.${n - 1}`));
    await expectText(tid(page, 'beads.row.0'), `Top row: ${n} ${n === 1 ? 'bead' : 'beads'} across`);
    await tap(tid(page, 'beads.bell'));
    await expectText(tid(page, 'beads.ask'), /^Yay! /);
    await expectCheered(page);
  });

  test('FR-TOY-03: Fair Share — she shares the cupcakes out evenly and rings the bell', async ({ page }) => {
    await openToyboxGame(page, 'share');
    await expectText(tid(page, 'share.ask'), /^Share (\d+) cupcakes$/);
    const n = Number((await textOf(tid(page, 'share.ask'))).match(/^Share (\d+) cupcakes$/)![1]);
    const plates = await idsUnder(page, 'share.plate.');
    // Round robin, one each, until the tray is empty.
    for (let given = 0; given < n; given++) {
      // The middle of the plate, on its cupcakes once it has some: every
      // tap on a plate gives it one.
      await tap(tid(page, `share.plate.${given % plates.length}`));
      await expectText(tid(page, 'share.tray'), `Tray: ${n - given - 1} ${n - given - 1 === 1 ? 'cupcake' : 'cupcakes'}`);
    }
    await tap(tid(page, 'share.bell'));
    await expectText(tid(page, 'share.ask'), / each/);
    await expectCheered(page);
  });
});
