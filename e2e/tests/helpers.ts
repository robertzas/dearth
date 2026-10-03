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
  await expect(tid(page, screenFor(route)).first()).toBeVisible({ timeout: 90_000 });
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
 * until [id] is built — lists build lazily, so off-screen widgets have no
 * semantics node yet. Waits briefly first (the node may be about to appear
 * after a write), then scrolls down, then back up.
 */
export async function scrollTo(page: Page, id: string, maxSteps = 12): Promise<Locator> {
  const target = tid(page, id);
  try {
    await target.first().waitFor({ state: 'attached', timeout: 2_000 });
    return target.first();
  } catch {
    // not built yet: scroll for it
  }
  const size = page.viewportSize() ?? { width: 1280, height: 800 };
  for (const direction of [1, -1]) {
    for (let i = 0; i < maxSteps * (direction === 1 ? 1 : 2) && (await target.count()) === 0; i++) {
      await page.mouse.move(size.width * 0.6, size.height * 0.55);
      await page.mouse.wheel(0, direction * size.height * 0.6);
      await page.waitForTimeout(250);
    }
    if (await target.count()) break;
  }
  await expect(target.first()).toBeAttached();
  return target.first();
}

/** Focuses the text field inside [id] and types. */
export async function typeInto(page: Page, id: string, text: string): Promise<void> {
  await tap(tid(page, id).locator('input, textarea'));
  await page.keyboard.type(text);
}

/** Replaces the text in the field inside [id]. */
export async function replaceText(page: Page, id: string, text: string): Promise<void> {
  await tap(tid(page, id).locator('input, textarea'));
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.type(text);
}

/** A button-like semantics node by its accessible name. */
export const button = (page: Page, name: string | RegExp): Locator => page.getByRole('button', { name });
