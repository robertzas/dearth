import 'package:meta/meta.dart';
import 'package:rrule/rrule.dart';

import '../calendar/recurrence.dart';
import '../db/database.dart';
import '../time/household_time.dart';
import '../time/local_date.dart';
import '../util/ids.dart';
import '../util/json.dart';

/// Kids, chores, routines and rewards domain (SPEC §10.7).

// ─────────────────────────────── Scheduling ────────────────────────────────

final Map<String, RecurrenceRule?> _ruleCache = {};

/// Whether a daily-granularity RRULE (chores, routines) is due on [day].
/// [anchor] is the series start (biweekly parity depends on it).
bool isDueOn(String rrule, LocalDate anchor, LocalDate day) {
  if (day.isBefore(anchor)) return false;
  final rule = _ruleCache.putIfAbsent(rrule, () => parseRrule(rrule, locationOrUtc('UTC')));
  if (rule == null) return true;
  final hits = rule.getInstances(
    start: anchor.utcMidnight,
    after: day.utcMidnight,
    includeAfter: true,
    before: day.addDays(1).utcMidnight,
  );
  return hits.isNotEmpty;
}

/// Deterministic ids so offline devices converge (SPEC §8.3).
String choreInstanceId(String choreId, LocalDate date, String? profileId) =>
    stableId('chore_instance', [choreId, date.iso, profileId ?? 'anyone']);

String routineRunId(String routineId, LocalDate date, String? profileId) =>
    stableId('routine_run', [routineId, date.iso, profileId ?? 'all']);

String grantLedgerId(String refTable, String refId, String currency, [int revision = 0]) =>
    stableId('grant', [refTable, refId, currency, revision]);

/// One expected chore occurrence for a person (or the Anyone pool).
@immutable
class DueChore {
  const DueChore(this.chore, this.date, this.profileId);
  final Chore chore;
  final LocalDate date;

  /// null = Anyone pool.
  final String? profileId;

  String get instanceId => choreInstanceId(chore.id, date, profileId);
}

/// Expands active chores into due items for [day].
List<DueChore> dueChores(Iterable<Chore> chores, LocalDate day, {LocalDate? defaultAnchor}) {
  final out = <DueChore>[];
  for (final c in chores) {
    if (c.deleted || !c.active) continue;
    final anchor = LocalDate.tryParse(c.anchorDate) ?? defaultAnchor ?? day;
    if (!isDueOn(c.rrule, anchor, day)) continue;
    final assignees = decodeStringList(c.assignees);
    if (assignees.isEmpty) {
      out.add(DueChore(c, day, null));
    } else {
      for (final p in assignees) {
        out.add(DueChore(c, day, p));
      }
    }
  }
  return out;
}

/// Chore instance status values.
abstract final class ChoreStatus {
  static const pending = 'pending';
  static const done = 'done'; // completed; awaiting approval if required
  static const approved = 'approved';
  static const skipped = 'skipped';
  static bool isComplete(String s) => s == done || s == approved;
}

// ───────────────────────────────── Ledger ──────────────────────────────────

/// Currencies on the append-only ledger.
abstract final class Currency {
  static const star = 'star';
  static const sticker = 'sticker';
  static const jar = 'jar';
  static const heart = 'heart';
  static const family = 'family';
}

/// Sums ledger deltas per currency for [profileId] (null = family pool).
Map<String, int> balances(Iterable<LedgerEntry> entries, String? profileId) {
  final out = <String, int>{};
  for (final e in entries) {
    if (e.deleted || e.profileId != profileId) continue;
    out[e.currency] = (out[e.currency] ?? 0) + e.delta;
  }
  return out;
}

// ──────────────────────────── Routine steps ────────────────────────────────

@immutable
class RoutineStep {
  const RoutineStep({required this.id, required this.title, this.emoji, this.timerSeconds, this.voiceLine, this.voiceBlob, this.song});

  factory RoutineStep.fromJson(Map<String, Object?> j) => RoutineStep(
        id: j['id'] as String? ?? newId(),
        title: j['title'] as String? ?? '',
        emoji: j['emoji'] as String?,
        timerSeconds: (j['timer'] as num?)?.toInt(),
        voiceLine: j['voice'] as String?,
        voiceBlob: j['voiceBlob'] as String?,
        song: j['song'] as String?,
      );

  final String id;
  final String title;
  final String? emoji;
  final int? timerSeconds;
  final String? voiceLine;
  final String? voiceBlob;

  /// Music tile id to play during the step (clean-up song challenge).
  final String? song;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        if (emoji != null) 'emoji': emoji,
        if (timerSeconds != null) 'timer': timerSeconds,
        if (voiceLine != null) 'voice': voiceLine,
        if (voiceBlob != null) 'voiceBlob': voiceBlob,
        if (song != null) 'song': song,
      };
}

List<RoutineStep> decodeSteps(String? json) => [for (final m in decodeMapList(json)) RoutineStep.fromJson(m)];

// ─────────────────────────────── Libraries ─────────────────────────────────

/// A chore template from the bundled library (SPEC Appendix C).
@immutable
class ChoreTemplate {
  const ChoreTemplate(this.title, this.emoji, this.minAge, this.voiceLine, {this.window = 'any', this.rrule = 'FREQ=DAILY'});
  final String title;
  final String emoji;
  final double minAge;
  final String voiceLine;
  final String window;
  final String rrule;
}

const List<ChoreTemplate> kChoreLibrary = [
  ChoreTemplate('Toys in the bin', '🧸', 2, 'Can you put your toys in the bin?', window: 'evening'),
  ChoreTemplate('Shoes in the basket', '👟', 2, 'Shoes go in the basket!'),
  ChoreTemplate('Clothes in the hamper', '🧺', 2, 'Dirty clothes go in the hamper!', window: 'evening'),
  ChoreTemplate('Help feed the pet', '🐶', 2, "Let's feed our furry friend!", window: 'morning'),
  ChoreTemplate('Plate to the counter', '🍽️', 2, 'All done eating? Bring your plate to the counter!'),
  ChoreTemplate('Books on the shelf', '📚', 2, 'Books go back home on the shelf!'),
  ChoreTemplate('Wipe up spills', '🧽', 2.5, 'Uh oh, spill! Can you wipe it up?'),
  ChoreTemplate('Water a plant', '🪴', 2.5, 'The plants are thirsty!', rrule: 'FREQ=WEEKLY;BYDAY=MO,TH'),
  ChoreTemplate('Set the napkins', '🧻', 3, 'Can you put a napkin at every seat?', window: 'evening'),
  ChoreTemplate('Match the socks', '🧦', 3, 'Find the sock twins!', rrule: 'FREQ=WEEKLY;BYDAY=SA'),
  ChoreTemplate('Sort laundry colors', '👕', 3, 'Lights in one pile, darks in the other!', rrule: 'FREQ=WEEKLY;BYDAY=SU'),
  ChoreTemplate('Pull up the blanket', '🛏️', 3, 'Make your bed cozy!', window: 'morning'),
  ChoreTemplate('Tidy art supplies', '🖍️', 3, 'Crayons back in the box!'),
  ChoreTemplate('Fill the pet water', '💧', 3.5, 'Fill up the water bowl!', window: 'morning'),
  ChoreTemplate('Set the table', '🍴', 4, 'Time to set the table!', window: 'evening'),
  ChoreTemplate('Clear the table', '🧼', 4, 'Help clear the table!', window: 'evening'),
  ChoreTemplate('Get dressed by yourself', '👗', 4, 'Can you get dressed all by yourself?', window: 'morning'),
  ChoreTemplate('Pack your daycare bag', '🎒', 4, "Let's pack your bag!", rrule: 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR', window: 'morning'),
  ChoreTemplate('Help put groceries away', '🛒', 4.5, 'Help put the groceries away!', rrule: 'FREQ=WEEKLY;BYDAY=SA'),
  ChoreTemplate('Dust low shelves', '🪶', 4.5, 'Dust bunny hunt!', rrule: 'FREQ=WEEKLY;BYDAY=SA'),
];

/// Routine templates (FR-KID-11).
@immutable
class RoutineTemplate {
  const RoutineTemplate(this.title, this.emoji, this.kind, this.steps, {this.startTime});
  final String title;
  final String emoji;
  final String kind;
  final List<(String title, String emoji, int? timer, String voice)> steps;
  final String? startTime;

  List<RoutineStep> buildSteps() => [
        for (final (t, e, timer, voice) in steps) RoutineStep(id: newId(), title: t, emoji: e, timerSeconds: timer, voiceLine: voice),
      ];
}

const List<RoutineTemplate> kRoutineTemplates = [
  RoutineTemplate('Good morning', '🌞', 'morning', [
    ('Potty', '🚽', null, 'Potty time!'),
    ('Wash hands', '🧼', 20, 'Scrub scrub scrub your hands!'),
    ('Get dressed', '👕', null, "Let's get dressed!"),
    ('Breakfast', '🥣', null, 'Yummy breakfast time!'),
    ('Brush teeth', '🪥', 120, 'Brush brush brush those teeth!'),
    ('Shoes on', '👟', null, 'Shoes on, ready to go!'),
  ], startTime: '07:00'),
  RoutineTemplate('Bedtime', '🌙', 'bedtime', [
    ('Bath', '🛁', null, 'Splashy bath time!'),
    ('Pajamas', '🩳', null, 'Cozy pajamas on!'),
    ('Brush teeth', '🪥', 120, 'Brush brush brush!'),
    ('Potty', '🚽', null, 'One more potty try!'),
    ('Story', '📖', null, 'Pick a story!'),
    ('Hugs & lights out', '🤗', null, 'Hugs and kisses, sweet dreams!'),
  ], startTime: '19:00'),
  RoutineTemplate('Clean-up time', '🧹', 'tidy', [
    ('Clean-up song', '🎵', 300, 'Can you finish before the song ends?'),
    ('Toys in the bin', '🧸', null, 'Toys go in the bin!'),
    ('Books on the shelf', '📚', null, 'Books go home!'),
    ('High five!', '🙌', null, 'You did it! High five!'),
  ]),
  RoutineTemplate('Potty time', '🚽', 'potty', [
    ('Pants down', '👖', null, 'Pants down!'),
    ('Sit on the potty', '🚽', 120, 'Sit and try!'),
    ('Wipe', '🧻', null, 'Wipe wipe!'),
    ('Flush', '🌊', null, 'Flush! Bye bye!'),
    ('Wash hands', '🧼', 20, 'Wash those hands!'),
  ]),
  RoutineTemplate('Off to daycare', '🎒', 'departure', [
    ('Backpack', '🎒', null, 'Grab your backpack!'),
    ('Water bottle', '🥤', null, "Don't forget your water bottle!"),
    ('Jacket', '🧥', null, 'Jacket on!'),
    ('Shoes', '👟', null, 'Shoes on!'),
  ], startTime: '07:45'),
];

/// Buddy characters (FR-KID-22).
const List<(String id, String emoji, String name)> kBuddies = [
  ('bunny', '🐰', 'Bunny'),
  ('dino', '🦕', 'Dino'),
  ('unicorn', '🦄', 'Unicorn'),
  ('puppy', '🐶', 'Puppy'),
  ('kitty', '🐱', 'Kitty'),
  ('bear', '🐻', 'Bear'),
  ('panda', '🐼', 'Panda'),
  ('robot', '🤖', 'Robot'),
];

String buddyEmoji(String? id) => kBuddies.firstWhere((b) => b.$1 == id, orElse: () => kBuddies.first).$2;

/// Sticker book themes (FR-KID-12).
const Map<String, (String name, String background, List<String> stickers)> kStickerThemes = {
  'farm': ('Farm', 'farm', ['🐮', '🐷', '🐔', '🐴', '🐑', '🐤', '🌻', '🚜', '🐰', '🌽', '🐶', '🦆']),
  'ocean': ('Ocean', 'ocean', ['🐠', '🐙', '🐳', '🦀', '🐬', '🐢', '🦈', '🐚', '⭐', '🪼', '🐡', '🦭']),
  'space': ('Space', 'space', ['🚀', '🪐', '⭐', '🌙', '👽', '🛸', '☄️', '🌍', '🌟', '👩‍🚀', '🛰️', '🌞']),
  'dinos': ('Dinosaurs', 'jungle', ['🦕', '🦖', '🌋', '🥚', '🌴', '🦴', '🐊', '🍃', '🪨', '🌿', '🦎', '☀️']),
  'garden': ('Garden', 'garden', ['🌷', '🌼', '🦋', '🐝', '🐞', '🌈', '🍓', '🐛', '🌳', '🍄', '🐌', '🌻']),
  'vehicles': ('Vehicles', 'city', ['🚗', '🚌', '🚒', '🚓', '🚑', '🚜', '🚂', '✈️', '🚁', '🚲', '🛴', '🚛']),
};

/// Default feelings for check-ins (FR-KID-23): core 8 for preschool.
const List<(String id, String emoji, String label)> kFeelings = [
  ('happy', '😊', 'Happy'),
  ('sad', '😢', 'Sad'),
  ('angry', '😠', 'Angry'),
  ('scared', '😨', 'Scared'),
  ('tired', '😴', 'Tired'),
  ('silly', '🤪', 'Silly'),
  ('calm', '😌', 'Calm'),
  ('excited', '🤩', 'Excited'),
  ('worried', '😟', 'Worried'),
  ('proud', '🥹', 'Proud'),
  ('loved', '🥰', 'Loved'),
  ('frustrated', '😤', 'Frustrated'),
  ('shy', '😳', 'Shy'),
  ('bored', '😐', 'Bored'),
  ('surprised', '😮', 'Surprised'),
  ('sick', '🤒', 'Sick'),
];

/// Reward ideas offered when creating rewards (SPEC Appendix C).
const List<(String title, String emoji, String kind, int cost)> kRewardIdeas = [
  ('Extra bedtime story', '📖', 'store', 5),
  ('Dance party', '💃', 'store', 5),
  ('Bubble bath', '🛁', 'store', 8),
  ('Pick dinner', '🍕', 'store', 10),
  ('Park trip', '🛝', 'surprise', 0),
  ('Pancake breakfast', '🥞', 'surprise', 0),
  ('Baking together', '🧁', 'surprise', 0),
  ('New book', '📚', 'store', 25),
  ('Movie night', '🍿', 'store', 20),
  ('Zoo trip', '🦁', 'family', 60),
  ('Living-room camping', '⛺', 'family', 40),
];
