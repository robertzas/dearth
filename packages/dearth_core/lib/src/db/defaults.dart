import '../sync/op.dart';
import 'mutator.dart';

/// Well-known ids for rows every household has. Deterministic so the Hub and
/// any offline device converge on the same rows (SPEC §8.3).
abstract final class Ids {
  static const household = 'household';
  static const familyCalendar = 'cal-family';
  static const shoppingList = 'list-shopping';
  static const todoList = 'list-todo';
  static const weather = 'current';

  static String homeLayout(String role, String orientation) => 'layout:$role:$orientation';
  static String setting(String scope, String key) => '$scope:$key';
}

/// Setting keys (stored in `settings`, value is JSON).
abstract final class SettingKeys {
  static const mealSlots = 'meals.slots';
  static const householdSize = 'meals.household_size';
  static const excludedIngredients = 'meals.excluded';
  static const pantryStaples = 'meals.staples';
  static const weatherStation = 'weather.station';

  /// Lists mirrored to Google Tasks: `{lists: [listId…], account?: email}`
  /// (no account: the first Google account that allowed Tasks).
  static const listsGoogleTasks = 'lists.google_tasks';

  /// How often the Hub fetches the weather: `{minutes: 5…60}`.
  static const weatherRefresh = 'weather.refresh';
  static const screensaver = 'display.screensaver';
  static const nightSchedule = 'display.night';
  static const toybox = 'kids.toybox';
  static const learnedIcons = 'calendar.learned_icons';

  /// Per calendar id: default reminder leads (FR-CAL-20).
  static const calendarReminders = 'calendar.reminders';

  /// The shared "Family" Google calendar (FR-CAL-04): `{source: id,
  /// account: email, shared: [email…]}` once the Hub made it, or
  /// `{dismissed: true}` when the family said no to the offer.
  static const calendarGoogleFamily = 'calendar.google_family';

  /// Birthdays and holidays calendars (FR-CAL-18): `{birthdays: bool,
  /// holidays: bool, country: 'US', observances: bool}`.
  static const calendarVirtual = 'calendar.virtual';
  static const onboarding = 'household.onboarding';
}

/// Ops creating the household skeleton (idempotent: re-running only
/// re-asserts the same values with newer HLCs, so it is applied once at
/// bootstrap and never again).
List<Op> householdDefaultOps(Mutator m, {required String timezone, String name = 'Our family'}) => [
      m.makeOp('households', Ids.household, {'name': name, 'timezone': timezone}),
      m.makeOp('calendar_sources', Ids.familyCalendar, {
        'kind': 'local',
        'name': 'Family',
        'color': 0xFF5B5BD6,
        'writable': true,
        'is_default': true,
        'enabled': true,
        'sort_key': 'a',
      }),
      m.makeOp('lists', Ids.shoppingList, {'title': 'Shopping', 'kind': 'shopping', 'icon': '🛒', 'sort_key': 'a'}),
      m.makeOp('lists', Ids.todoList, {'title': 'To-do', 'kind': 'todo', 'icon': '✅', 'sort_key': 'b'}),
      m.makeOp('settings', Ids.setting('household', SettingKeys.mealSlots), {
        'scope': 'household',
        'key': SettingKeys.mealSlots,
        'value': [
          {'id': 'breakfast', 'label': 'Breakfast', 'emoji': '🥣'},
          {'id': 'lunch', 'label': 'Lunch', 'emoji': '🥪'},
          {'id': 'dinner', 'label': 'Dinner', 'emoji': '🍽️'},
          {'id': 'snack', 'label': 'Snack', 'emoji': '🍎'},
        ],
      }),
      m.makeOp('settings', Ids.setting('household', SettingKeys.screensaver), {
        'scope': 'household',
        'key': SettingKeys.screensaver,
        'value': {'idleMinutes': 5, 'photoSeconds': 30, 'kenBurns': false, 'clock': true, 'weather': true, 'nextEvent': true, 'caption': true},
      }),
      m.makeOp('settings', Ids.setting('household', SettingKeys.nightSchedule), {
        'scope': 'household',
        'key': SettingKeys.nightSchedule,
        'value': {'enabled': true, 'start': '21:00', 'end': '06:30', 'offEnabled': false},
      }),
    ];
