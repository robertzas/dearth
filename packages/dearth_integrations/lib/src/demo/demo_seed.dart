import 'package:dearth_core/dearth_core.dart';

import '../recipes/catalog.dart';
import '../weather/weather_service.dart';

/// Demo profile ids (stable so E2E tests can address them).
abstract final class DemoIds {
  static const mom = 'p-mom';
  static const dad = 'p-dad';
  static const ava = 'p-ava';
  static const dog = 'p-biscuit';
}

/// Built-in melodies the music box can play offline (note sequences rendered
/// by the app's synth; all public-domain tunes).
const List<(String ref, String title, String emoji)> kBuiltinSongs = [
  ('twinkle', 'Twinkle Twinkle Little Star', '⭐'),
  ('mary', 'Mary Had a Little Lamb', '🐑'),
  ('happy-birthday', 'Happy Birthday', '🎂'),
  ('old-macdonald', 'Old MacDonald', '🐮'),
  ('row-boat', 'Row, Row, Row Your Boat', '🚣'),
  ('itsy-bitsy', 'Itsy Bitsy Spider', '🕷️'),
];

/// A complete, realistic demo household relative to "today" (demo mode and
/// E2E). Applied on top of [householdDefaultOps].
Future<List<Op>> demoSeedOps(Mutator m, HouseholdTime time, {double lat = 39.71, double lon = -104.70}) async {
  final today = time.today();
  final ops = <Op>[];
  void put(String table, String id, Map<String, Object?> f) => ops.add(m.makeOp(table, id, f));
  void insert(String table, String id, Map<String, Object?> f) => ops.add(m.makeOp(table, id, f, kind: OpKind.insertOnly));

  put('households', Ids.household, {
    'name': 'The Demo Family',
    'timezone': time.zoneName,
    'lat': lat,
    'lon': lon,
    'location_label': 'Aurora, CO',
    'postal_code': '80018',
    'country_code': 'US',
  });

  final avaBirthday = LocalDate(today.year - 2, today.month, 1).addMonths(-6);
  put('profiles', DemoIds.mom, {'name': 'Mom', 'role': 'adult', 'color': 0, 'emoji': '👩', 'sort_key': 'a'});
  put('profiles', DemoIds.dad, {'name': 'Dad', 'role': 'adult', 'color': 5, 'emoji': '👨', 'sort_key': 'b'});
  put('profiles', DemoIds.ava, {
    'name': 'Ava', 'role': 'child', 'color': 8, 'emoji': '👧', 'birthday': avaBirthday.iso, //
    'kid_stage': KidStage.little, 'buddy': 'bunny', 'sort_key': 'c',
  });
  put('profiles', DemoIds.dog, {'name': 'Biscuit', 'role': 'pet', 'color': 10, 'emoji': '🐶', 'sort_key': 'd'});

  // ── Calendar ──────────────────────────────────────────────────────────────
  int at(LocalDate d, int h, [int min = 0]) => time.msAt(d, h, min);
  final monday = today.startOfWeek(1);
  final saturday = monday.addDays(5);
  void event(String id, String title, LocalDate d, int h, int min, int durMin, List<String> who, {String? rrule, String? icon, String? location, bool countdown = false}) {
    put('events', id, {
      'source_id': Ids.familyCalendar,
      'title': title,
      'icon': icon ?? suggestEventIcon(title),
      'start_ms': at(d, h, min),
      'end_ms': at(d, h, min) + durMin * 60000,
      'tz': time.zoneName,
      'rrule': rrule,
      'location': location,
      'profile_ids': who,
      'countdown': countdown,
    });
  }

  void allDay(String id, String title, LocalDate d, {int days = 1, List<String> who = const [], String? rrule, bool countdown = false, String? icon}) {
    put('events', id, {
      'source_id': Ids.familyCalendar,
      'title': title,
      'icon': icon ?? suggestEventIcon(title),
      'all_day': true,
      'start_date': d.iso,
      'end_date': d.addDays(days).iso,
      'start_ms': time.startOfDayMs(d),
      'end_ms': time.startOfDayMs(d.addDays(days)),
      'rrule': rrule,
      'profile_ids': who,
      'countdown': countdown,
    });
  }

  event('ev-daycare', 'Daycare drop-off', monday.addDays(-7), 8, 0, 30, [DemoIds.ava, DemoIds.dad], rrule: 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR', icon: '🧸');
  event('ev-swim', 'Swim lesson', saturday.addDays(-7), 9, 0, 45, [DemoIds.ava, DemoIds.mom], rrule: 'FREQ=WEEKLY;BYDAY=SA', location: 'Rec Center pool');
  event('ev-music', 'Music class', monday.addDays(2 - 7), 10, 0, 45, [DemoIds.ava, DemoIds.mom], rrule: 'FREQ=WEEKLY;BYDAY=WE', icon: '🎶');
  event('ev-story', 'Library story time', today, 10, 30, 45, [DemoIds.ava, DemoIds.dad]);
  event('ev-pizza', 'Pizza night', today, 18, 0, 60, []);
  event('ev-dentist', 'Dentist', today.addDays(3), 15, 30, 60, [DemoIds.mom], location: 'Smile Dental');
  event('ev-date', 'Date night', today.addDays(5), 19, 0, 150, [DemoIds.mom, DemoIds.dad]);
  event('ev-market', 'Farmers market', saturday, 10, 30, 90, [DemoIds.mom, DemoIds.dad, DemoIds.ava]);
  event('ev-vet', 'Vet checkup', today.addDays(9), 11, 0, 30, [DemoIds.dad, DemoIds.dog]);
  allDay('ev-grandma', 'Grandma visits', today.addDays(8), days: 3, who: [DemoIds.mom, DemoIds.dad, DemoIds.ava], countdown: true, icon: '👵');
  allDay('ev-bday', "Ava's birthday", avaBirthday, rrule: 'FREQ=YEARLY', who: [DemoIds.ava], countdown: true);
  allDay('ev-trash', 'Trash day', monday.addDays(1 - 7), rrule: 'FREQ=WEEKLY;BYDAY=TU', icon: '🗑️');

  // ── Lists & notes ────────────────────────────────────────────────────────
  var sort = 0;
  String sk() => 'a${(sort++).toString().padLeft(3, '0')}';
  for (final (text, cat) in [('Bananas', 'produce'), ('Milk', 'dairyEggs'), ('Diapers (size 5)', 'household'), ('Coffee', 'beverages'), ('Dog food', 'household')]) {
    put('list_items', stableId('demo-item', [text]), {'list_id': Ids.shoppingList, 'text': text, 'category': cat, 'sort_key': sk()});
  }
  for (final text in ['Renew car registration', 'Call the plumber', 'Order Grandma\'s birthday gift']) {
    put('list_items', stableId('demo-item', [text]), {'list_id': Ids.todoList, 'text': text, 'sort_key': sk()});
  }
  put('notes', 'note-grandma', {'kind': 'announcement', 'body': 'Grandma visits next week! 🎉', 'color': 3, 'pinned': true, 'author_profile_id': DemoIds.mom});
  put('notes', 'note-bottle', {'kind': 'sticky', 'body': "Ava's water bottle is in the car 🚗", 'color': 0, 'author_profile_id': DemoIds.dad});

  // ── Kids: chores, routines, rewards ─────────────────────────────────────
  final anchor = monday.addDays(-7).iso;
  void chore(String id, String title, String emoji, List<String> who, {String rrule = 'FREQ=DAILY', String window = 'any', bool adult = false, String? voice, bool approval = false}) {
    put('chores', id, {
      'title': title, 'emoji': emoji, 'assignees': who, 'rrule': rrule, 'anchor_date': anchor, //
      'window': window, 'adult': adult, 'voice_line': voice, 'needs_approval': approval, 'stars': adult ? 0 : 1,
    });
  }

  chore('ch-toys', 'Toys in the bin', '🧸', [DemoIds.ava], window: 'evening', voice: 'Can you put your toys in the bin?');
  chore('ch-shoes', 'Shoes in the basket', '👟', [DemoIds.ava], voice: 'Shoes go in the basket!');
  chore('ch-feed', 'Help feed Biscuit', '🐶', [DemoIds.ava], window: 'morning', voice: "Let's feed Biscuit!");
  chore('ch-books', 'Books on the shelf', '📚', [DemoIds.ava], voice: 'Books go back home on the shelf!');
  chore('ch-trash', 'Take out the trash', '🗑️', [DemoIds.dad], rrule: 'FREQ=WEEKLY;BYDAY=TU', adult: true);
  chore('ch-laundry', 'Laundry', '🧺', [DemoIds.mom], rrule: 'FREQ=WEEKLY;BYDAY=SA', adult: true);
  chore('ch-plants', 'Water the plants', '🪴', const [], rrule: 'FREQ=WEEKLY;BYDAY=MO,TH', adult: true);

  for (final (i, tpl) in kRoutineTemplates.take(2).indexed) {
    put('routines', 'rt-${tpl.kind}', {
      'title': tpl.title, 'emoji': tpl.emoji, 'kind': tpl.kind, 'profile_ids': [DemoIds.ava], //
      'steps': [for (final s in tpl.buildSteps()) s.toJson()], 'rrule': 'FREQ=DAILY', 'anchor_date': anchor,
      'start_time': tpl.startTime, 'sort_key': 'a$i',
    });
  }
  put('rewards', 'rw-story', {'title': 'Extra bedtime story', 'emoji': '📖', 'kind': 'store', 'cost': 5, 'currency': 'star'});
  put('rewards', 'rw-park', {'title': 'Park trip', 'emoji': '🛝', 'kind': 'surprise', 'cost': 0, 'currency': 'jar'});
  put('rewards', 'rw-pancakes', {'title': 'Pancake breakfast', 'emoji': '🥞', 'kind': 'surprise', 'cost': 0, 'currency': 'jar'});
  put('rewards', 'rw-zoo', {'title': 'Zoo trip', 'emoji': '🦁', 'kind': 'family', 'cost': 40, 'currency': 'family'});
  final nowMs = time.nowMs();
  var n = 0;
  void grant(String? profile, String currency, int delta) =>
      insert('ledger_entries', stableId('demo-grant', [n++]), {'profile_id': profile, 'currency': currency, 'delta': delta, 'reason': 'demo', 'at_ms': nowMs - n * 3600000});
  for (var i = 0; i < 6; i++) {
    grant(DemoIds.ava, Currency.sticker, 1);
  }
  grant(DemoIds.ava, Currency.jar, 4);
  grant(DemoIds.ava, Currency.star, 3);
  grant(null, Currency.family, 12);
  final farm = kStickerThemes['farm']!.$3;
  for (var i = 0; i < 5; i++) {
    put('sticker_placements', stableId('demo-sticker', [i]), {
      'profile_id': DemoIds.ava, 'page': 0, 'sticker': farm[i], //
      'x': 0.15 + i * 0.17, 'y': 0.55 + (i.isEven ? 0.12 : -0.08), 'scale': 1.0, 'rotation': i * 0.15 - 0.3, 'at_ms': nowMs - i * 86400000,
    });
  }

  // ── Meals ───────────────────────────────────────────────────────────────
  final plan = ['chicken-tacos', 'spaghetti-bolognese', 'chicken-noodle-soup', 'fried-rice', 'flatbread-pizza', 'teriyaki-salmon', 'banana-pancakes'];
  final catalog = {for (final r in recipeCatalog) r.sourceId: r};
  for (final (i, sid) in plan.indexed) {
    final r = catalog[sid];
    if (r == null) continue;
    final rid = stableId('recipe', ['catalog', r.sourceId]);
    put('recipes', rid, r.toFields());
    final d = monday.addDays(i);
    final slot = sid == 'banana-pancakes' ? 'breakfast' : 'dinner';
    put('meal_entries', stableId('demo-meal', [d.iso, slot]), {'date': d.iso, 'slot': slot, 'recipe_id': rid, 'servings': 4});
  }

  // ── Music ───────────────────────────────────────────────────────────────
  for (final (i, (ref, title, emoji)) in kBuiltinSongs.indexed) {
    put('music_tiles', 'mt-$ref', {'board': 'kids', 'source': 'builtin', 'ref': ref, 'title': title, 'emoji': emoji, 'color': i % 12, 'sort_key': 'a$i'});
  }

  // ── Weather (deterministic) ─────────────────────────────────────────────
  final report = await FakeWeather(clock: () => DateTime.fromMillisecondsSinceEpoch(nowMs)).fetch(
    WeatherConfig(lat: lat, lon: lon, timezone: time.zoneName, label: 'Aurora, CO'),
  );
  put('weather_reports', Ids.weather, {'data': report.encode(), 'fetched_ms': report.fetchedMs});
  return ops;
}
