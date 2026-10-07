import { expect, Locator, Page, TestInfo } from '@playwright/test';

/** The UI clock for demo-mode tests: a Saturday morning (SPEC §16.3). */
export const NOW = '2026-10-03T08:30:00';

/** Semantics-identifier selector (the `tid()` contract, AGENTS.md rule 10). */
export const tid = (page: Page, id: string): Locator => page.locator(`[flt-semantics-identifier="${id}"]`);

/** Elements whose identifier starts with [prefix]. */
export const tids = (page: Page, prefix: string): Locator => page.locator(`[flt-semantics-identifier^="${prefix}"]`);

export const isPhone = (info: TestInfo): boolean => info.project.name === 'phone';
export const isWall = (info: TestInfo): boolean => info.project.name.startsWith('wall');

const screenFor = (route: string): string => {
  const first = route.replace(/^\//, '').split('/')[0];
  return first === '' ? 'screen.home' : `screen.${first}`;
};

/** Starts the app in local demo mode at [NOW] and waits for [route]. */
export async function openDemo(page: Page, route = '/'): Promise<void> {
  await page.goto(`/?demo=1&e2e=1&now=${NOW}#${route}`);
  // Prefix: phones show a settings section as its own screen.settings.<id>.
  await expect(tids(page, screenFor(route)).first()).toBeVisible({ timeout: 90_000 });
}

/**
 * Taps like a finger would. Flutter hit-tests the pointer position itself, so
 * once the target is visible the click is dispatched at its centre even if an
 * empty semantics container overlaps it in the DOM.
 */
export async function tap(target: Locator): Promise<void> {
  const el = target.first();
  await el.waitFor({ state: 'visible' });
  await el.click({ force: true });
}

/** The text a semantics node exposes (aria-label and/or text content). */
export async function textOf(target: Locator): Promise<string> {
  return target.first().evaluate((e) => [e.getAttribute('aria-label'), e.textContent].filter(Boolean).join(' '));
}

/** Waits until [target]'s exposed text matches [expected]. */
export async function expectText(target: Locator, expected: string | RegExp, timeout = 20_000): Promise<void> {
  const re = typeof expected === 'string' ? new RegExp(expected.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')) : expected;
  await expect.poll(() => textOf(target).catch(() => ''), { timeout }).toMatch(re);
}

/** Navigates with the visible chrome (rail, bottom bar or "More"). */
export async function goTo(page: Page, dest: string): Promise<void> {
  const direct = tid(page, `nav.${dest}`);
  if (await direct.count()) {
    await tap(direct);
  } else {
    await tap(tid(page, 'nav.more'));
    await tap(tid(page, `more.${dest}`));
  }
  await expect(tid(page, `screen.${dest}`).first()).toBeVisible();
}

/**
 * Scrolls the page content (mouse wheel over the middle of the viewport)
 * until [id] is built and inside the viewport — lists build lazily, so
 * off-screen widgets may have no semantics node yet, and a node in the cache
 * extent can't be tapped. Waits briefly first (the node may be about to
 * appear after a write), then scrolls down, then back up.
 */
export async function scrollTo(page: Page, id: string, maxSteps = 12): Promise<Locator> {
  const target = tid(page, id).first();
  const size = page.viewportSize() ?? { width: 1280, height: 800 };
  const inView = async (): Promise<boolean> => {
    if ((await tid(page, id).count()) === 0) return false;
    const box = await target.boundingBox();
    if (!box) return false;
    // Its middle must clear the top chrome and the phone's bottom bar.
    const middle = box.y + Math.min(box.height, size.height) / 2;
    return middle >= 40 && middle <= size.height - 110;
  };
  try {
    await target.waitFor({ state: 'attached', timeout: 2_000 });
  } catch {
    // not built yet: scroll for it
  }
  for (const direction of [1, -1]) {
    for (let i = 0; i < maxSteps * (direction === 1 ? 1 : 2) && !(await inView()); i++) {
      const box = (await tid(page, id).count()) ? await target.boundingBox() : null;
      // Built but out of view: scroll toward it; otherwise keep searching.
      const dir = box ? (box.y < 0 ? -1 : 1) : direction;
      const step = box ? Math.min(size.height * 0.6, Math.abs(box.y - size.height * 0.3) + 1) : size.height * 0.6;
      // Over the target's own column when it's built: a side sheet on a
      // wall starts near the middle, and a wheel over the backdrop would
      // scroll the page behind it.
      const x = box ? Math.min(Math.max(box.x + box.width / 2, 10), size.width - 10) : size.width * 0.6;
      await page.mouse.move(x, size.height * 0.55);
      await page.mouse.wheel(0, dir * step);
      await page.waitForTimeout(250);
    }
    if (await inView()) break;
  }
  await expect(target).toBeAttached();
  return target;
}

/** Focuses the text field inside [id] and types. */
export async function typeInto(page: Page, id: string, text: string): Promise<void> {
  await tap(tid(page, id).locator('input, textarea'));
  // Focusing can scroll a sheet to the field; keys typed before the editor
  // settles are lost (seen on a wall's side sheet).
  await page.waitForTimeout(300);
  await page.keyboard.type(text);
}

/** Replaces the text in the field inside [id]. */
export async function replaceText(page: Page, id: string, text: string): Promise<void> {
  await tap(tid(page, id).locator('input, textarea'));
  await page.waitForTimeout(300);
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.type(text);
}

/** A button-like semantics node by its accessible name. */
export const button = (page: Page, name: string | RegExp): Locator => page.getByRole('button', { name });

/**
 * Long-presses the centre of [target] past the deliberate 600 ms threshold
 * (SPEC §11.10), then drags by [dx], [dy] and releases (FR-CAL-14).
 */
export async function longPressDrag(page: Page, target: Locator, dx: number, dy: number, from: 'center' | 'bottom' = 'center'): Promise<void> {
  const el = target.first();
  await el.waitFor({ state: 'visible' });
  const box = (await el.boundingBox())!;
  const x = box.x + box.width / 2;
  const y = from === 'center' ? box.y + box.height / 2 : box.y + box.height - 4;
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.waitForTimeout(900);
  await page.mouse.move(x + dx, y + dy, { steps: 12 });
  await page.waitForTimeout(150);
  await page.mouse.up();
}

/** Drags the centre of [from] to the centre of [to] (or a point), as a finger would. */
export async function drag(page: Page, from: Locator, to: Locator | { x: number; y: number }): Promise<void> {
  const el = from.first();
  await el.waitFor({ state: 'visible' });
  const a = (await el.boundingBox())!;
  const b = 'x' in to ? to : await (async () => {
    const box = (await to.first().boundingBox())!;
    return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
  })();
  await page.mouse.move(a.x + a.width / 2, a.y + a.height / 2);
  await page.mouse.down();
  await page.mouse.move(b.x, b.y, { steps: 14 });
  await page.waitForTimeout(80);
  await page.mouse.up();
}

/** Holds a finger on [target] for [ms] (hold-to-activate controls). */
export async function hold(page: Page, target: Locator, ms = 3300): Promise<void> {
  const box = (await target.first().boundingBox())!;
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.waitForTimeout(ms);
  await page.mouse.up();
}


/** Opens [game] from Ava's Toybox (every game is on by default). */
export async function openToyboxGame(page: Page, game: string): Promise<void> {
  await openDemo(page, '/toybox');
  await tap(await scrollTo(page, `toybox.game.${game}`));
  await expect(tid(page, `game.${game}`)).toBeVisible();
}

/** Every element's id that starts with [prefix], in index order when they end in a number. */
export async function idsUnder(page: Page, prefix: string): Promise<string[]> {
  const all = await tids(page, prefix).evaluateAll((els) => els.map((e) => e.getAttribute('flt-semantics-identifier')!));
  const index = (id: string) => Number(id.split('.').pop());
  return all.sort((a, b) => (isNaN(index(a)) || isNaN(index(b)) ? a.localeCompare(b) : index(a) - index(b)));
}

/**
 * A Toybox round was cheered. Reads the game's lasting cheer count rather
 * than the celebration, which is gone in two seconds: a slow runner can
 * miss it.
 */
export async function expectCheered(page: Page, timeout = 20_000): Promise<void> {
  await expectText(tid(page, 'game.cheers'), /^[1-9]\d* rounds? cheered$/, timeout);
}

/** Whether the open Toybox game has cheered a round yet. */
export async function cheered(page: Page): Promise<boolean> {
  return /^[1-9]/.test(await textOf(tid(page, 'game.cheers')).catch(() => ''));
}
