import { expect, Page, test } from '@playwright/test';
import { drag, expectCheered, expectText, idsUnder, openToyboxGame, tap, textOf, tid } from './helpers';

// The Toybox's expansion set (SPEC FR-TOY-03), played the way a child would:
// from what the screen shows (labels), not from the game's state. Every
// game is on by default, so Ava (2½ in the demo) has them all.

const openGame = openToyboxGame;
const ids = idsUnder;
const label = async (page: Page, id: string): Promise<string> => (await textOf(tid(page, id))).trim();

test.describe('Toybox expansion', () => {
  test('FR-TOY-03: Patterns — she reads the row and picks what comes next', async ({ page }) => {
    await openGame(page, 'patterns');
    const items = await ids(page, 'patterns.item.');
    const shown = await Promise.all(items.map((id) => label(page, id)));
    // AB at the first level: the next one is the one two back.
    const answer = shown[shown.length - 2];
    for (const id of await ids(page, 'patterns.choice.')) {
      if ((await label(page, id)) === answer) await tap(tid(page, id));
    }
    // The slot shows the answer only until the next round (~3 s, less than
    // a slow runner can take after the cheer), so it's read first.
    await expectText(tid(page, 'patterns.slot'), answer);
    await expectCheered(page);
  });

  test('FR-TOY-03: Odd One Out — tapping around until the different one is found', async ({ page }) => {
    await openGame(page, 'oddone');
    // Guessing counts as slips, and a round with many isn't cheered: the
    // prompt says when it's found.
    for (const id of await ids(page, 'oddone.item.')) {
      if ((await label(page, 'oddone.ask')).includes('found')) break;
      await tap(tid(page, id));
      await page.waitForTimeout(300);
    }
    await expectText(tid(page, 'oddone.ask'), 'You found it!');
  });

  test('FR-TOY-03: Shadow Match — each picture onto its own shadow', async ({ page }) => {
    await openGame(page, 'shadows');
    const pictures = await ids(page, 'shadows.picture.');
    expect(pictures.length).toBe(2);
    for (const p of pictures) {
      for (const s of await ids(page, 'shadows.shadow.')) {
        // A filled shadow shows its picture; an empty one says "Shadow".
        if (!(await label(page, s)).startsWith('Shadow')) continue;
        await drag(page, tid(page, p), tid(page, s));
        // It snaps in (the label becomes the picture) or floats back. A busy
        // machine can take more than a moment, so wait for the snap.
        const filled = await expect
          .poll(() => label(page, s), { timeout: 3000 })
          .not.toMatch(/^Shadow/)
          .then(() => true, () => false);
        if (filled) break;
      }
    }
    // Every shadow filled: the round is cheered. (Reading the shadows races
    // the next round, which a slow runner can already show.)
    await expectCheered(page);
  });

  test('FR-TOY-03: Small to Big — smallest first, into the line', async ({ page }) => {
    await openGame(page, 'sizes');
    const items = await ids(page, 'sizes.item.');
    const sizes = await Promise.all(items.map(async (id) => ({ id, size: parseInt(await label(page, id), 10) })));
    for (const { id } of sizes.sort((a, b) => a.size - b.size)) {
      await tap(tid(page, id));
      await expectText(tid(page, id), 'In the line');
    }
    await expectCheered(page);
  });

  test('FR-TOY-03: Picture Sudoku — each empty place gets the fruit its row is missing', async ({ page }) => {
    await openGame(page, 'sudoku');
    const fruitIds = await ids(page, 'sudoku.fruit.');
    const fruits = await Promise.all(fruitIds.map((id) => label(page, id)));
    const tried = new Map<number, Set<string>>();
    for (let step = 0; step < 30; step++) {
      const cells = await Promise.all([...Array(16).keys()].map((i) => label(page, `sudoku.cell.${i}`)));
      const chosen = cells.findIndex((c) => c === 'Empty, chosen');
      if (chosen < 0) break;
      const r = Math.floor(chosen / 4), c = chosen % 4;
      const box = [0, 1].flatMap((dr) => [0, 1].map((dc) => cells[(r - (r % 2) + dr) * 4 + c - (c % 2) + dc]));
      const seen = new Set([...cells.slice(r * 4, r * 4 + 4), ...[0, 1, 2, 3].map((k) => cells[k * 4 + c]), ...box]);
      // What its row, column and corner square don't have yet; a guess that
      // was wrong isn't tried again.
      const done = tried.get(chosen) ?? new Set<string>();
      tried.set(chosen, done);
      const fruit = fruits.find((f) => !seen.has(f) && !done.has(f)) ?? fruits.find((f) => !done.has(f))!;
      done.add(fruit);
      await tap(tid(page, fruitIds[fruits.indexOf(fruit)]));
      await page.waitForTimeout(300);
    }
    await expectCheered(page);
  });

  test('FR-TOY-03: What Happens Next — the story goes into the line card by card', async ({ page }) => {
    await openGame(page, 'stories');
    const cards = await ids(page, 'stories.card.');
    for (let place = 1; place <= cards.length; place++) {
      for (const c of cards) {
        if ((await label(page, c)).startsWith('Place')) continue;
        await tap(tid(page, c));
        await page.waitForTimeout(500);
        if ((await label(page, c)).startsWith(`Place ${place}`)) break;
      }
    }
    // The whole story is in the line.
    for (const c of cards) expect(await label(page, c)).toMatch(/^Place \d/);
  });

  test('FR-TOY-03: Spot the Difference — every difference found', async ({ page }) => {
    await openGame(page, 'differences');
    const spots = await ids(page, 'differences.spot.');
    for (const s of spots) await tap(tid(page, s));
    await expectText(tid(page, 'differences.count'), `Found ${spots.length} of ${spots.length}`);
    await expectCheered(page);
  });

  test('FR-TOY-03: Finger Mazes — the buddy finds the way home', async ({ page }) => {
    await openGame(page, 'mazes');
    const cells = await ids(page, 'mazes.cell.');
    const labels = await Promise.all(cells.map((id) => label(page, id)));
    // The maze's width: a square's "right" neighbour is the next one, "down" is a row on.
    const cols = Math.max(...labels.map((l, i) => (l.includes('home') ? i + 1 : 0)));
    const start = labels.findIndex((l) => l.includes('buddy here'));
    const home = labels.findIndex((l) => l.includes('home'));
    const step: Record<string, number> = { up: -cols, down: cols, left: -1, right: 1 };
    const prev = new Map<number, number>([[start, start]]);
    const queue = [start];
    while (queue.length) {
      const c = queue.shift()!;
      for (const w of labels[c].split(':')[1].split(',')[0].trim().split(' ').filter(Boolean)) {
        const n = c + step[w];
        if (!prev.has(n)) {
          prev.set(n, c);
          queue.push(n);
        }
      }
    }
    const path = [home];
    while (path[0] !== start) path.unshift(prev.get(path[0])!);
    for (const c of path.slice(1)) {
      await tap(tid(page, `mazes.cell.${c}`));
      await page.waitForTimeout(150);
    }
    await expectCheered(page);
  });
});
