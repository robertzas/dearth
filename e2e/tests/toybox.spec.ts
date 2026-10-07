import { expect, test } from '@playwright/test';
import { Page } from '@playwright/test';
import { cheered, drag, expectCheered, expectText, goTo, hold, openDemo, scrollTo, tap, textOf, tid, tids } from './helpers';

// The Toybox (SPEC §10.8). Demo: Ava is 2½, so the 3+ games stay hidden.
// The demo has no PINs, so the grown-up corner opens the settings directly.

test.describe('Toybox', () => {
  test('FR-TOY-01: Ava’s Toybox shows her games; one opens full screen and the house goes home', async ({ page }) => {
    await openDemo(page);
    await goTo(page, 'toybox');
    await expectText(tid(page, 'toybox.title'), 'Ava’s Toybox');
    await expect(tid(page, 'toybox.game.farm')).toBeVisible();
    await expect(tid(page, 'toybox.game.counting')).toHaveCount(0);
    await expect(tid(page, 'toybox.new.farm')).toBeVisible();
    await tap(tid(page, 'toybox.game.farm'));
    await expect(tid(page, 'screen.game')).toBeVisible();
    await tap(tid(page, 'game.home'));
    await expect(tid(page, 'screen.toybox')).toBeVisible();
    await expect(tid(page, 'toybox.new.farm')).toHaveCount(0);
  });

  test('FR-TOY-02: on the farm, a tapped animal says hello with its name', async ({ page }) => {
    await openDemo(page, '/toybox');
    await tap(tid(page, 'toybox.game.farm'));
    const animal = tids(page, 'farm.animal.').first();
    const id = (await animal.getAttribute('flt-semantics-identifier'))!.replace('farm.animal.', '');
    await tap(animal);
    await expect(tid(page, `farm.says.${id}`)).toBeVisible();
    await expectText(tid(page, `farm.says.${id}`), '·');
  });

  test('FR-TOY-02: the parrot plays a tune, then it’s her turn', async ({ page }) => {
    await openDemo(page, '/toybox');
    await tap(await scrollTo(page, 'toybox.game.music'));
    await tap(tid(page, 'music.bar.0'));
    await tap(tid(page, 'music.drum.kick'));
    await tap(tid(page, 'music.echo'));
    await expectText(tid(page, 'music.echo'), 'Your turn');
  });

  test('FR-TOY-05: a daily budget from the grown-up corner shows the time left', async ({ page }) => {
    await openDemo(page, '/toybox');
    await expect(tid(page, 'toybox.timeleft')).toHaveCount(0);
    await hold(page, tid(page, 'toybox.grownups'));
    await expect(tids(page, 'screen.settings').first()).toBeVisible();
    await tap(await scrollTo(page, 'toybox.budget.15-min'));
    await goTo(page, 'toybox');
    await expectText(tid(page, 'toybox.timeleft'), '15 min');
  });

  test('FR-TOY-02: Memory Match — pairs stay up, two that differ turn back, a full board is cheered', async ({ page }) => {
    await openGame(page, 'memory');
    await expect(tid(page, 'memory.look')).toHaveCount(0, { timeout: 10_000 });
    await playMemory(page);
    await expectCheered(page);
  });

  test('FR-TOY-02: Shape Sorter — each shape dragged into its hole snaps in', async ({ page }) => {
    await openGame(page, 'shapes');
    for (const s of ['circle', 'square']) {
      await drag(page, tid(page, `shapes.piece.${s}`), tid(page, `shapes.hole.${s}`));
      await page.waitForTimeout(500);
    }
    await expectCheered(page);
  });

  test('FR-TOY-01/05: every game is on; a grown-up switches one off and it leaves the Toybox', async ({ page }) => {
    await openDemo(page, '/toybox');
    // Counting Garden is for 3+, and Ava (2½) has it anyway: ages are starting points.
    await expect(await scrollTo(page, 'toybox.game.counting')).toBeVisible();
    await hold(page, tid(page, 'toybox.grownups'));
    await expect(tids(page, 'screen.settings').first()).toBeVisible();
    await tap(await scrollTo(page, 'toybox.on.counting'));
    await goTo(page, 'toybox');
    await expect(tid(page, 'toybox.game.paint')).toBeVisible();
    await expect(tid(page, 'toybox.game.counting')).toHaveCount(0);
  });

  test('FR-TOY-02: Counting Garden — she counts the buds and picks how many', async ({ page }) => {
    await openGame(page, 'counting');
    const n = await tids(page, 'counting.bud.').count();
    for (let i = 0; i < n; i++) {
      await tap(tid(page, `counting.bud.${i}`));
      await expectText(tid(page, `counting.bud.${i}`), `Flower ${i + 1}`);
    }
    await expect(tid(page, 'counting.ask')).toBeVisible();
    await tap(tid(page, `counting.choice.${n}`));
    await expectCheered(page);
  });

  test('FR-TOY-02: Feed the Monster — it eats what its sign shows and refuses the rest', async ({ page }) => {
    await openGame(page, 'monster');
    await expectText(tid(page, 'monster.sign'), /Only \w+ food/);
    const n = await tids(page, 'monster.food.').count();
    for (let i = 0; i < n && !(await cheered(page)); i++) {
      await tap(tid(page, `monster.food.${i}`));
      await page.waitForTimeout(1000);
    }
    await expectCheered(page);
  });

  test('FR-TOY-02: Magic Coloring — a crayon and a tap fill each part; a finished picture is cheered', async ({ page }) => {
    await openGame(page, 'coloring');
    await tap(tid(page, 'coloring.color.blue'));
    const n = await tids(page, 'coloring.region.').count();
    for (let i = 0; i < n; i++) {
      await tap(tid(page, `coloring.region.${i}`));
      await page.waitForTimeout(450);
    }
    await expectCheered(page);
    await expectText(tid(page, 'coloring.canvas'), `Colored ${n} of ${n}`);
    await tap(tid(page, 'coloring.next'));
    await expectText(tid(page, 'coloring.canvas'), /Colored 0 of/);
  });

  test('FR-TOY-02: Jigsaw — pieces dragged to their spots snap in and the picture is cheered', async ({ page }) => {
    await openGame(page, 'jigsaw');
    await expect(tid(page, 'jigsaw.piece.0.0')).toBeVisible();
    const ids = await tids(page, 'jigsaw.piece.').evaluateAll((els) => els.map((e) => e.getAttribute('flt-semantics-identifier')!));
    expect(ids.length).toBe(2);
    for (const id of ids) {
      await drag(page, tid(page, id), tid(page, id.replace('piece', 'slot')));
      await page.waitForTimeout(500);
    }
    await expectCheered(page);
  });

  test('FR-TOY-02: Paint Studio — a stroke goes on the paper, and undo takes it back', async ({ page }) => {
    await openGame(page, 'paint');
    const paper = tid(page, 'paint.paper');
    await expectText(paper, 'Painting: 0 marks');
    const box = (await paper.boundingBox())!;
    await drag(page, paper, { x: box.x + box.width * 0.8, y: box.y + box.height * 0.7 });
    await expectText(paper, 'Painting: 1 mark');
    await tap(tid(page, 'paint.undo'));
    await expectText(paper, 'Painting: 0 marks');
  });
});

/** Opens [game] from Ava's Toybox. */
async function openGame(page: Page, game: string, fresh = true): Promise<void> {
  if (fresh) await openDemo(page, '/toybox');
  await tap(await scrollTo(page, `toybox.game.${game}`));
  await expect(tid(page, `game.${game}`)).toBeVisible();
}

/** Plays a Memory Match board the way she would: turn, remember, match. */
async function playMemory(page: Page): Promise<void> {
  const card = (i: number) => tid(page, `memory.card.${i}`);
  const n = await tids(page, 'memory.card.').count();
  const faceOf = async (i: number): Promise<string> => {
    let text = '';
    await expect.poll(async () => (text = await textOf(card(i)))).not.toMatch(/Card/);
    return text.trim();
  };
  const known = new Map<number, string>();
  const done = new Set<number>();
  const settle = () => page.waitForTimeout(700);
  while (done.size < n) {
    const pair = [...known].flatMap(([a, f]) => [...known].filter(([b, g]) => b > a && g === f && !done.has(a) && !done.has(b)).map(([b]) => [a, b]))[0];
    if (pair) {
      await tap(card(pair[0]));
      await tap(card(pair[1]));
      pair.forEach((i) => done.add(i));
      await settle();
      continue;
    }
    const fresh = [...Array(n).keys()].filter((i) => !done.has(i) && !known.has(i));
    const a = fresh[0];
    await tap(card(a));
    known.set(a, await faceOf(a));
    const partner = [...known].find(([j, f]) => j !== a && f === known.get(a) && !done.has(j));
    const b = partner ? partner[0] : fresh[1];
    await tap(card(b));
    known.set(b, await faceOf(b));
    if (known.get(a) === known.get(b)) {
      done.add(a).add(b);
      await settle();
    } else {
      await expect.poll(() => textOf(card(a)), { timeout: 5_000 }).toMatch(/Card/);
    }
  }
}

