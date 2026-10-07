import { expect, test } from '@playwright/test';
import { expectCheered, expectText, idsUnder, openToyboxGame, tap, textOf, tid } from './helpers';

// The Toybox's number and letter games (SPEC FR-TOY-03), played from what
// the screen shows (labels). The voice itself can't be heard here; the
// widget tests check which clips play.

test.describe('Toybox number and letter games', () => {
  test('FR-TOY-03: Dot-to-Dot — she joins the dots in order and the picture appears', async ({ page }) => {
    await openToyboxGame(page, 'dots');
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
    await openToyboxGame(page, 'biglittle');
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
    await openToyboxGame(page, 'hop');
    await expectText(tid(page, 'hop.ask'), /^Hop to \d+$/);
    const target = (await textOf(tid(page, 'hop.ask'))).trim().replace('Hop to ', '');
    await tap(tid(page, `hop.pad.${target}`));
    // A lasting label: it stays until the next round. (The pad's "frog"
    // races the next round on a slow runner, so the cheer count is next.)
    await expectText(tid(page, 'hop.ask'), `Landed on ${target}!`);
    await expectCheered(page);
  });

  test('FR-TOY-03: Word Builder — she puts the missing sound into the word', async ({ page }) => {
    await openToyboxGame(page, 'spell');
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
    await openToyboxGame(page, 'hear');
    await expectText(tid(page, 'hear.ask'), /^Which letter says [a-z]\?$/);
    const letter = (await textOf(tid(page, 'hear.ask'))).trim().replace('Which letter says ', '').replace('?', '');
    await tap(tid(page, 'hear.parrot'));
    await tap(tid(page, `hear.letter.${letter}`));
    // Lasting labels: the cheer can be over before a slow run gets there.
    await expectText(tid(page, 'hear.ask'), `You found ${letter}!`);
    await expectCheered(page);
  });

  test('FR-TOY-03: Sight Words — she finds the sign that says the word, and the bus stops there', async ({ page }) => {
    await openToyboxGame(page, 'sight');
    await expectText(tid(page, 'sight.ask'), /^Find the word [a-zA-Z]+$/);
    const word = (await textOf(tid(page, 'sight.ask'))).trim().replace('Find the word ', '');
    let sign = '';
    for (const id of await idsUnder(page, 'sight.sign.')) {
      if ((await textOf(tid(page, id))).trim() === `Sign: ${word}`) sign = id;
    }
    expect(sign).not.toBe('');
    await tap(tid(page, sign));
    // Lasting labels: they stay until the next round.
    await expectText(tid(page, 'sight.ask'), `You found ${word}!`);
    await expectCheered(page);
  });

  test('FR-TOY-03: Banana Balance — she picks the side with more and the see-saw tips that way', async ({ page }) => {
    await openToyboxGame(page, 'balance');
    await expectText(tid(page, 'balance.ask'), 'Which side has more?');
    const count = async (side: string) => Number((await textOf(tid(page, `balance.side.${side}`))).match(/(\d+)/)![1]);
    const left = await count('left');
    const right = await count('right');
    expect(left).not.toBe(right);
    await tap(tid(page, `balance.side.${left > right ? 'left' : 'right'}`));
    // Lasting labels: they stay until the next round.
    await expectText(tid(page, 'balance.ask'), `${Math.max(left, right)} is more than ${Math.min(left, right)}`);
    await expectCheered(page);
  });

  test('FR-TOY-03: Who Has More? — buses pull in with their numbers and she picks the one the voice asks for', async ({ page }) => {
    await openToyboxGame(page, 'compare');
    // The question comes once every bus has stopped and said its number.
    await expectText(tid(page, 'compare.ask'), /Which bus has (more|fewer) kids\?|Line up the buses/);
    const ask = await textOf(tid(page, 'compare.ask'));
    const buses = await idsUnder(page, 'compare.bus.');
    const numbers: number[] = [];
    for (const id of buses) numbers.push(Number((await textOf(tid(page, id))).match(/Bus (\d+)/)![1]));
    if (ask.includes('Line up')) {
      // Fewest first, then the next, then the most.
      for (const n of [...numbers].sort((a, b) => a - b)) await tap(tid(page, buses[numbers.indexOf(n)]));
      await expectText(tid(page, 'compare.ask'), `In order: ${[...numbers].sort((a, b) => a - b).join(', ')}`);
    } else {
      const want = ask.includes('fewer') ? Math.min(...numbers) : Math.max(...numbers);
      await tap(tid(page, buses[numbers.indexOf(want)]));
      // Lasting labels: they stay until the buses drive off.
      await expectText(tid(page, 'compare.ask'), `${want} has ${ask.includes('fewer') ? 'fewer' : 'more'}`);
    }
    await expectCheered(page);
  });

  test('FR-TOY-03: Name Zoo — the animal at the gate needs her name card, and she finds it', async ({ page }) => {
    await openToyboxGame(page, 'zoo');
    // Level 1: her own name, spelled by the voice; the label names it for tests.
    await expectText(tid(page, 'zoo.ask'), 'Find your name: Ava');
    const cards = await idsUnder(page, 'zoo.card.');
    expect(cards).toHaveLength(3);
    let mine = '';
    for (const id of cards) if ((await textOf(tid(page, id))).trim() === 'Ava') mine = id;
    expect(mine).not.toBe('');
    await tap(tid(page, mine));
    // Lasting labels: they stay until the animal has walked in.
    await expectText(tid(page, 'zoo.board'), 'Card: Ava');
    await expectText(tid(page, 'zoo.ask'), 'Ava, thank you!');
    await expectCheered(page);
  });

  test('FR-TOY-03: Tallies — one mark for each bunny that hops up, then the count', async ({ page }) => {
    await openToyboxGame(page, 'tally');
    await expectText(tid(page, 'tally.ask'), 'Make a mark for each bunny');
    // The first bunny says how many are coming.
    await expectText(tid(page, 'tally.bunny'), /^Bunny 1 of \d+, waiting$/);
    const n = Number((await textOf(tid(page, 'tally.bunny'))).match(/of (\d+)/)![1]);
    for (let k = 1; k <= n; k++) {
      await expectText(tid(page, 'tally.bunny'), `Bunny ${k} of ${n}, waiting`);
      await tap(tid(page, 'tally.board'));
      await expectText(tid(page, 'tally.board'), `Tally: ${k} mark`);
    }
    // Lasting labels: they stay until the next round.
    await expectText(tid(page, 'tally.ask'), `${n} bunn${n === 1 ? 'y' : 'ies'}`);
    await expectCheered(page);
  });

  test('FR-TOY-03: Hundred Square — the voice asks for a number and she finds it', async ({ page }) => {
    await openToyboxGame(page, 'hundred');
    await expectText(tid(page, 'hundred.ask'), /^Find \d+$/);
    const n = (await textOf(tid(page, 'hundred.ask'))).trim().split(' ').pop()!;
    await tap(tid(page, `hundred.cell.${n}`));
    // Lasting labels: they stay until the next round.
    await expectText(tid(page, 'hundred.ask'), `${n} found`);
    await expectCheered(page);
  });
});
