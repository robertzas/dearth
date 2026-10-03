/// Keyword → emoji map for event auto-icons (FR-CAL-15, SPEC Appendix F).
///
/// Matching is word-based and case-insensitive; multi-word keys match
/// phrases. The first matching rule wins, so specific phrases come first.
const List<(List<String>, String)> kEventIconRules = [
  (['birthday party', 'bday party'], '🎉'),
  (['birthday', 'bday'], '🎂'),
  (['anniversary'], '💞'),
  (['wedding'], '💒'),
  (['swim', 'swimming', 'pool'], '🏊'),
  (['soccer'], '⚽'),
  (['basketball'], '🏀'),
  (['baseball', 'softball', 't-ball', 'tball'], '⚾'),
  (['football'], '🏈'),
  (['tennis'], '🎾'),
  (['hockey'], '🏒'),
  (['gymnastics', 'tumbling'], '🤸'),
  (['dance', 'ballet'], '🩰'),
  (['karate', 'martial arts', 'taekwondo'], '🥋'),
  (['ski', 'skiing', 'snowboard'], '⛷️'),
  (['skate', 'skating'], '⛸️'),
  (['bike', 'cycling'], '🚲'),
  (['run', 'running', 'marathon', '5k'], '🏃'),
  (['yoga'], '🧘'),
  (['gym', 'workout', 'training'], '🏋️'),
  (['hike', 'hiking', 'trail'], '🥾'),
  (['camping', 'campout'], '🏕️'),
  (['beach'], '🏖️'),
  (['park', 'playground'], '🛝'),
  (['zoo'], '🦁'),
  (['aquarium'], '🐠'),
  (['museum'], '🏛️'),
  (['library', 'story time', 'storytime'], '📚'),
  (['movie', 'movies', 'cinema', 'film'], '🎬'),
  (['concert', 'show'], '🎵'),
  (['piano'], '🎹'),
  (['guitar'], '🎸'),
  (['violin'], '🎻'),
  (['music', 'lesson'], '🎶'),
  (['art', 'painting', 'craft'], '🎨'),
  (['dentist', 'teeth', 'orthodontist'], '🦷'),
  (['doctor', 'checkup', 'check-up', 'pediatrician', 'appointment', 'clinic'], '🩺'),
  (['hospital'], '🏥'),
  (['vaccine', 'shot', 'flu shot'], '💉'),
  (['eye', 'optometrist'], '👓'),
  (['therapy', 'therapist'], '🛋️'),
  (['haircut', 'hair', 'barber', 'salon'], '💇'),
  (['vet', 'veterinarian'], '🐾'),
  (['dog', 'puppy', 'walk the dog'], '🐶'),
  (['daycare', 'preschool', 'nursery'], '🧸'),
  (['school', 'class', 'conference', 'pta'], '🏫'),
  (['college', 'university', 'exam'], '🎓'),
  (['homework', 'study'], '✏️'),
  (['work', 'office', 'meeting', 'standup'], '💼'),
  (['call', 'zoom', 'video call'], '📞'),
  (['flight', 'airport', 'fly'], '✈️'),
  (['trip', 'travel', 'vacation', 'holiday'], '🧳'),
  (['road trip', 'drive'], '🚗'),
  (['train'], '🚆'),
  (['grandma', 'grandpa', 'nana', 'papa', 'grandparents', 'granny', 'gigi'], '👵'),
  (['playdate', 'play date'], '🧒'),
  (['sleepover'], '🛏️'),
  (['party'], '🎈'),
  (['dinner', 'supper'], '🍽️'),
  (['lunch'], '🥪'),
  (['breakfast', 'brunch'], '🥞'),
  (['pizza'], '🍕'),
  (['bbq', 'barbecue', 'cookout'], '🍔'),
  (['coffee'], '☕'),
  (['date night', 'date'], '💕'),
  (['church', 'mass', 'service'], '⛪'),
  (['synagogue', 'temple'], '🕍'),
  (['groceries', 'grocery', 'shopping', 'costco', 'target'], '🛒'),
  (['farmers market', 'market'], '🥕'),
  (['bath'], '🛁'),
  (['nap'], '😴'),
  (['bedtime', 'sleep'], '🌙'),
  (['clean', 'cleaning', 'chores'], '🧹'),
  (['laundry'], '🧺'),
  (['trash', 'garbage', 'recycling', 'bins'], '🗑️'),
  (['car', 'oil change', 'mechanic'], '🔧'),
  (['bills', 'taxes', 'bank'], '💵'),
  (['halloween'], '🎃'),
  (['christmas', 'xmas'], '🎄'),
  (['thanksgiving'], '🦃'),
  (['easter'], '🐣'),
  (['valentine', "valentine's"], '❤️'),
  (['hanukkah', 'chanukah'], '🕎'),
  (['new year', "new year's"], '🎆'),
  (['fourth of july', 'independence day', 'july 4th'], '🎆'),
  (['holiday', 'day off', 'no school'], '🌟'),
];

/// Suggests an emoji for an event title, or null.
String? suggestEventIcon(String title, {Map<String, String> learned = const {}}) {
  final t = title.toLowerCase().trim();
  if (t.isEmpty) return null;
  final override = learned[t];
  if (override != null) return override;
  final words = ' ${t.replaceAll(RegExp(r"[^a-z0-9'\- ]"), ' ')} ';
  for (final (keys, icon) in kEventIconRules) {
    for (final k in keys) {
      if (words.contains(' $k ') || words.contains(' ${k}s ')) return icon;
    }
  }
  return null;
}
