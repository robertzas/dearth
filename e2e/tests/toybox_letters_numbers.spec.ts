import { expect, test } from '@playwright/test';
import { expectCheered, expectText, idsUnder, openToyboxGame, tap, textOf, tid } from './helpers';

// The Toybox's number and letter games (SPEC FR-TOY-03), played from what
// the screen shows (labels). The voice itself can't be heard here; the
// widget tests check which clips play. Ava is 2½ in the demo, so each game
// is opened early from Settings first.

test.describe('Toybox number and letter games', () => {
  test('FR-TOY-03: Dot-to-Dot — she joins the dots in order and the picture appears', async ({ page }) => {
    await openToyboxGame(page, 'dots', true);
    await expectText(tid(page, 'dots.ask'), 'Start at 1');
    await expectText(tid(page, 'dots.board'), 'Join the dots: 0 of 5');
    const dots = await idsUnder(page, 'dots.dot.');
    expect(dots).toEqual(['dots.dot.1', 'dots.dot.2', 'dots.dot.3', 'dots.dot.4', 'dots.dot.5']);
    for (const id of dots) {
      await tap(tid(page, id));
      await expectText(tid(page, id), 'joined');
    }
    // The cheer can be over before a slow run reaches it; the label stays
    // until the next picture.
    await expectText(tid(page, 'dots.ask'), /^It's (a|an|the) [a-z ]+!$/);
  });

  test('FR-TOY-03: Big & Little Letters — each small letter finds its capital', async ({ page }) => {
    await openToyboxGame(page, 'biglittle', true);
    await expectText(tid(page, 'biglittle.ask'), 'Little letters find big letters');
    const bigs = await idsUnder(page, 'biglittle.big.');
    const littles = await idsUnder(page, 'biglittle.little.');
    expect(bigs).toHaveLength(3);
    expect(littles).toHaveLength(3);
    const capitals = new Map<string, string>();
    for (const id of bigs) capitals.set((await textOf(tid(page, id))).trim().replace('Big ', ''), id);
    for (const id of littles) {
      const letter = (await textOf(tid(page, id))).trim().replace('Little ', '');
      const card = capitals.get(letter.toUpperCase())!;
      await tap(tid(page, id));
      await tap(tid(page, card));
      await expectText(tid(page, card), `Big ${letter.toUpperCase()}, little ${letter}`);
    }
    // A lasting label: the cheer can be over before a slow run gets there.
    await expectText(tid(page, 'biglittle.ask'), 'All found!');
  });

  test('FR-TOY-03: Frog Hop — the frog hops to the pad the voice asks for', async ({ page }) => {
    await openToyboxGame(page, 'hop', true);
    await expectText(tid(page, 'hop.ask'), /^Hop to \d+$/);
    const target = (await textOf(tid(page, 'hop.ask'))).trim().replace('Hop to ', '');
    await tap(tid(page, `hop.pad.${target}`));
    // A lasting label: it stays until the next round.
    await expectText(tid(page, 'hop.ask'), `Landed on ${target}!`);
    await expectText(tid(page, `hop.pad.${target}`), `${target}, frog`);
  });

  test('FR-TOY-03: Word Builder — she puts the missing sound into the word', async ({ page }) => {
    await openToyboxGame(page, 'spell', true);
    await expectText(tid(page, 'spell.ask'), /^Which sound is missing in [a-z]+\?$/);
    const word = (await textOf(tid(page, 'spell.picture'))).trim();
    expect(word).toMatch(/^[a-z]{3}$/);
    await expectText(tid(page, 'spell.slot.0'), 'Slot 1: empty, next');
    await expectText(tid(page, 'spell.slot.1'), `Slot 2: ${word[1]}`);
    // The tile with the first letter, read from the tray.
    let right = '';
    for (const id of await idsUnder(page, 'spell.tile.')) {
      if ((await textOf(tid(page, id))).trim() === `Letter ${word[0]}`) right = id;
    }
    expect(right).not.toBe('');
    await tap(tid(page, right));
    await expectText(tid(page, 'spell.slot.0'), `Slot 1: ${word[0]}`);
    // A lasting label, then the host's lasting cheer count.
    await expectText(tid(page, 'spell.ask'), `You built ${word}!`);
    await expectCheered(page);
  });

  test('FR-TOY-03: Hear the Sound — she taps the letter that makes the parrot’s sound', async ({ page }) => {
    await openToyboxGame(page, 'hear', true);
    await expectText(tid(page, 'hear.ask'), /^Which letter says [a-z]\?$/);
    const letter = (await textOf(tid(page, 'hear.ask'))).trim().replace('Which letter says ', '').replace('?', '');
    await tap(tid(page, 'hear.parrot'));
    await tap(tid(page, `hear.letter.${letter}`));
    // Lasting labels: the cheer can be over before a slow run gets there.
    await expectText(tid(page, 'hear.ask'), `You found ${letter}!`);
    await expectCheered(page);
  });
});
