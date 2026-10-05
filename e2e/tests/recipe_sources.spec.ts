import { Browser, expect, Page, test } from '@playwright/test';
import { expectText, goTo, tap, tid, typeInto } from './helpers';

// Settings → Recipes (SPEC FR-RCP-01, FR-RCP-13) against the test Hub: the
// free recipe sources it searches, switched on and off, and a key for one
// that needs it. The Hub keeps these for every display, so one viewport is
// enough (the test Hub runs with fake providers, so searches don't change).

async function pairedPage(browser: Browser, baseURL: string): Promise<Page> {
  const ctx = await browser.newContext({ baseURL, viewport: { width: 1920, height: 1080 }, timezoneId: 'America/Denver' });
  const page = await ctx.newPage();
  await page.goto('/?e2e=1&reset=1');
  await tap(tid(page, 'onboarding.hub'));
  await tap(tid(page, 'onboarding.connect'));
  await expect(tid(page, 'screen.home')).toBeVisible({ timeout: 60_000 });
  return page;
}

test.describe('Recipe sources', () => {
  test('FR-RCP-13: a grown-up switches a recipe source off and on, and adds a free key', async ({ browser, baseURL }, info) => {
    test.skip(info.project.name !== 'wall-l', 'the Hub keeps these settings; one display is enough');
    const page = await pairedPage(browser, baseURL!);
    await goTo(page, 'settings');
    await tap(tid(page, 'settings.nav.recipes'));
    await expectText(tid(page, 'recipes.source.wikibooks'), 'Wikibooks Cookbook, On');
    await expectText(tid(page, 'recipes.source.recipeapi'), 'Needs a free key');

    await tap(tid(page, 'recipes.source.wikibooks'));
    await expectText(tid(page, 'recipes.source.wikibooks'), 'Wikibooks Cookbook, Off');

    await tap(tid(page, 'recipes.key.recipeapi'));
    await typeInto(page, 'recipes.key.input', 'sk_live_e2e_key');
    await tap(tid(page, 'recipes.key.save'));
    await expectText(tid(page, 'recipes.key.recipeapi'), 'Change the RecipeAPI.io key');
    await expectText(tid(page, 'recipes.source.recipeapi'), /0 of 500 used this month/);

    // Back on, for the rest of the suite.
    await tap(tid(page, 'recipes.source.wikibooks'));
    await expectText(tid(page, 'recipes.source.wikibooks'), 'Wikibooks Cookbook, On');
  });
});
