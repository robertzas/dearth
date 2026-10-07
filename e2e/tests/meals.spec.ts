import { expect, test } from '@playwright/test';
import { button, expectText, goTo, openDemo, replaceText, scrollTo, tap, tid, typeInto } from './helpers';

// Demo week (Sun Sep 27 – Sat Oct 3): dinners Mon–Sat, Teriyaki salmon tonight.
const TONIGHT = 'meals.cell.2026-10-03.dinner';

test.describe('Meals', () => {
  test('FR-MEAL-01/02: the week plan shows the planned dinners and a summary', async ({ page }) => {
    await openDemo(page, '/meals');
    await expectText(tid(page, 'meals.summary'), /6 meals planned · \d+ ingredients to buy/);
    await expectText(await scrollTo(page, TONIGHT), 'Teriyaki salmon');
    await expectText(await scrollTo(page, 'meals.cell.2026-09-28.dinner'), 'Chicken soft tacos');
  });

  test('FR-RCP-06: the servings stepper rescales ingredients; units switch', async ({ page }) => {
    await openDemo(page, '/meals');
    await tap(await scrollTo(page, TONIGHT));
    await expect(tid(page, 'recipe.sheet')).toBeVisible();
    await expectText(tid(page, 'recipe.planned'), 'Planned for Today');
    await expectText(tid(page, 'recipe.ingredient.0'), '4 salmon fillets');
    await tap(tid(page, 'recipe.servings.plus'));
    await tap(tid(page, 'recipe.servings.plus'));
    await expectText(tid(page, 'recipe.ingredient.0'), '6 salmon fillets');
    await expectText(tid(page, 'recipe.ingredient.1'), '½ cup soy sauce');
    await tap(tid(page, 'recipe.units.metric'));
    await expectText(tid(page, 'recipe.ingredient.1'), /ml soy sauce/);
  });

  test('FR-MEAL-01: plan a recipe into an empty slot, then take it off', async ({ page }) => {
    await openDemo(page, '/meals');
    await tap(await scrollTo(page, 'meals.add.2026-10-03.lunch'));
    await expect(tid(page, 'plan.sheet')).toBeVisible();
    await typeInto(page, 'plan.search', 'quesadillas');
    await tap(tid(page, 'plan.result.quesadillas'));
    const lunch = await scrollTo(page, 'meals.cell.2026-10-03.lunch');
    await expectText(lunch, 'Cheesy bean quesadillas');
    await tap(lunch);
    await tap(tid(page, 'recipe.unplan'));
    await expectText(tid(page, 'toast'), 'Taken off the plan');
    await expect(tid(page, 'meals.cell.2026-10-03.lunch')).toHaveCount(0);
  });

  test('FR-MEAL-01: free-text entries like “Leftovers”', async ({ page }) => {
    await openDemo(page, '/meals');
    await tap(await scrollTo(page, 'meals.add.2026-09-27.dinner'));
    await tap(tid(page, 'plan.quick.leftovers'));
    await expectText(await scrollTo(page, 'meals.cell.2026-09-27.dinner'), 'Leftovers');
  });

  test('FR-RCP-03/FR-RCP-01: search, save to the recipe box', async ({ page }) => {
    await openDemo(page, '/meals');
    await tap(tid(page, 'meals.tab.discover'));
    await typeInto(page, 'meals.search', 'quesadillas');
    await tap(tid(page, 'recipe.quesadillas'));
    await tap(tid(page, 'recipe.save'));
    await expectText(tid(page, 'toast'), 'Saved to the recipe box');
    await tap(tid(page, 'sheet.close'));
    await tap(tid(page, 'meals.tab.recipes'));
    await expect(tid(page, 'recipe.quesadillas')).toBeVisible();
  });

  test('FR-RCP-01: a family recipe written by hand scales and cooks like any other', async ({ page }) => {
    await openDemo(page, '/meals');
    await tap(tid(page, 'meals.tab.recipes'));
    await tap(tid(page, 'box.new'));
    await expect(tid(page, 'recipe.editor')).toBeVisible();
    await typeInto(page, 'recipe.editor.title', "Grandma Rose's tostadas");
    await scrollTo(page, 'recipe.editor.ingredients');
    await typeInto(page, 'recipe.editor.ingredients', '8 corn tortillas\n1 can black beans\n2 limes');
    // What Dearth understood: amounts it can scale.
    await expectText(await scrollTo(page, 'recipe.editor.understood'), '3 ingredients · 3 with amounts that scale');
    await scrollTo(page, 'recipe.editor.steps');
    await typeInto(page, 'recipe.editor.steps', '1. Warm the beans for 5 minutes.\n2. Pile everything on the tortillas.');
    await expectText(await scrollTo(page, 'recipe.editor.stepcount'), '2 steps · 1 timer for cook mode');
    await tap(await scrollTo(page, 'recipe.editor.save'));
    await expectText(tid(page, 'toast'), "Added Grandma Rose's tostadas to the recipe box");
    // It opens like any recipe: the servings stepper rescales it…
    await expectText(tid(page, 'recipe.ingredient.0'), '8 corn tortillas');
    await tap(tid(page, 'recipe.servings.plus'));
    await tap(tid(page, 'recipe.servings.plus'));
    await expectText(tid(page, 'recipe.ingredient.0'), '12 corn tortillas');
    // …and cook mode steps through it with the timer it found.
    await tap(tid(page, 'recipe.cook'));
    await expectText(tid(page, 'cook.progress'), 'Step 1 of 2');
    await expectText(tid(page, 'cook.step'), 'Warm the beans for 5 minutes.');
    await expect(tid(page, 'cook.timer.0')).toBeVisible();
    await tap(tid(page, 'cook.close'));
    await tap(tid(page, 'sheet.close'));
    // Search finds it by what's in it, as it finds a source's recipes.
    await tap(tid(page, 'meals.tab.discover'));
    await typeInto(page, 'meals.search', 'black beans');
    await expect(button(page, /Grandma Rose's tostadas/).first()).toBeVisible();
  });

  test('FR-RCP-01: editing a planned recipe makes it the family\'s version, with notes', async ({ page }) => {
    await openDemo(page, '/meals');
    await tap(await scrollTo(page, TONIGHT));
    await tap(tid(page, 'recipe.edit'));
    await expect(tid(page, 'recipe.editor')).toBeVisible();
    await replaceText(page, 'recipe.editor.title', "Grandpa's teriyaki salmon");
    await scrollTo(page, 'recipe.editor.notes');
    await typeInto(page, 'recipe.editor.notes', 'Less soy sauce for the kids.');
    await tap(await scrollTo(page, 'recipe.editor.save'));
    await expectText(tid(page, 'toast'), "Saved Grandpa's teriyaki salmon");
    await expectText(tid(page, 'recipe.planned'), 'Planned for Today');
    // The source's ingredients came through the edit untouched.
    await expectText(tid(page, 'recipe.ingredient.0'), '4 salmon fillets');
    await expectText(await scrollTo(page, 'recipe.notes'), 'Less soy sauce for the kids.');
    await tap(tid(page, 'sheet.close'));
    await expectText(await scrollTo(page, TONIGHT), "Grandpa's teriyaki salmon");
  });

  test('FR-RCP-09/10: discover pairs recipes with the plan and says why', async ({ page }) => {
    await openDemo(page, '/meals');
    await tap(tid(page, 'meals.tab.discover'));
    await expectText(tid(page, 'discover.pairs'), /Uses your .+ · adds \d+ items?/);
  });

  test('FR-RCP-06/FR-SHOP-01: a recipe and the whole week go to the shopping list', async ({ page }) => {
    await openDemo(page, '/meals');
    await tap(await scrollTo(page, TONIGHT));
    await tap(tid(page, 'recipe.tolist'));
    await expectText(tid(page, 'toast'), /Added \d+ items? to Shopping/);
    await tap(tid(page, 'sheet.close'));
    await tap(tid(page, 'meals.week.tolist'));
    await expectText(tid(page, 'toast'), /Added \d+ items? to Shopping|already on Shopping/);
  });

  test('FR-RCP-07: cook mode steps through with detected timers', async ({ page }) => {
    await openDemo(page, '/meals');
    await tap(await scrollTo(page, TONIGHT));
    await tap(tid(page, 'recipe.cook'));
    await expect(tid(page, 'screen.cook')).toBeVisible();
    await expectText(tid(page, 'cook.progress'), 'Step 1 of 4');
    await expectText(tid(page, 'cook.step'), 'Cook the rice for 18 minutes.');
    await tap(tid(page, 'cook.timer.0'));
    // A shared kitchen timer named after the step (FR-TMR-02).
    await expectText(page.locator('[flt-semantics-identifier^="timer."][flt-semantics-identifier$=".left"]'), /step 1: 1[78]:\d\d left/);
    await tap(tid(page, 'cook.next'));
    await expectText(tid(page, 'cook.progress'), 'Step 2 of 4');
    await tap(tid(page, 'cook.close'));
    await expect(tid(page, 'screen.cook')).toHaveCount(0);
  });

  test('FR-MEAL-05: Home’s dinner card opens tonight’s recipe', async ({ page }) => {
    await openDemo(page);
    await tap(await scrollTo(page, 'home.dinner'));
    await expectText(tid(page, 'recipe.planned'), 'Planned for Today');
    await tap(tid(page, 'sheet.close'));
    await goTo(page, 'meals');
  });
});
