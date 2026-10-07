import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Weather Dress-Up (SPEC FR-TOY-03, Appendix B: reasoning, self-care). The
// voice says what today's weather is, from the household's real forecast
// ("It's snowy today! What should Buddy wear?"), and she dresses a paper-
// doll buddy one part at a time from three choices: one that suits the
// day, two from the opposite kind of day (no sandals in the snow). Each
// pick says its name. The ladder: the top only → the top and the shoes →
// the whole outfit (top, legs, feet and one more thing). Without a
// forecast the game pretends ("Let's pretend it's rainy!"). The weather
// rules follow whatToWear (FR-WX-07); drawing lives in the app.

/// The kind of day, as a child would say it.
enum DressWeather {
  hot('☀️', "It's sunny and hot today!"),
  warm('🌤️', "It's warm today!"),
  cool('⛅', "It's cool today."),
  cold('🥶', "It's cold today! Brr!"),
  rain('🌧️', "It's rainy today!"),
  snow('❄️', "It's snowy today!");

  const DressWeather(this.emoji, this.line);
  final String emoji;

  /// What the voice says first.
  final String line;
}

/// Where a piece goes on the buddy.
enum DressSlot { top, legs, feet, extra }

/// The pieces of clothing (and things to bring).
enum DressItem {
  tank('🎽', 'A tank top!', DressSlot.top),
  tshirt('👕', 'A T-shirt!', DressSlot.top),
  jacket('🧥', 'A warm coat!', DressSlot.top),
  shorts('🩳', 'Shorts!', DressSlot.legs),
  jeans('👖', 'Long pants!', DressSlot.legs),
  sandals('👡', 'Sandals!', DressSlot.feet),
  sneakers('👟', 'Sneakers!', DressSlot.feet),
  boots('🥾', 'Boots!', DressSlot.feet),
  sunhat('👒', 'A sun hat!', DressSlot.extra),
  sunglasses('🕶️', 'Sunglasses!', DressSlot.extra),
  umbrella('☂️', 'An umbrella!', DressSlot.extra),
  mittens('🧤', 'Mittens!', DressSlot.extra),
  scarf('🧣', 'A warm scarf!', DressSlot.extra);

  const DressItem(this.emoji, this.line, this.slot);
  final String emoji;

  /// Its name, as the voice says it when picked.
  final String line;
  final DressSlot slot;
}

/// What suits each kind of day, part by part. Anything else for that part
/// is the wrong weather's.
const Map<DressWeather, Map<DressSlot, Set<DressItem>>> kDressSuits = {
  DressWeather.hot: {
    DressSlot.top: {DressItem.tank, DressItem.tshirt},
    DressSlot.legs: {DressItem.shorts},
    DressSlot.feet: {DressItem.sandals, DressItem.sneakers},
    DressSlot.extra: {DressItem.sunhat, DressItem.sunglasses},
  },
  DressWeather.warm: {
    DressSlot.top: {DressItem.tshirt},
    DressSlot.legs: {DressItem.shorts, DressItem.jeans},
    DressSlot.feet: {DressItem.sneakers, DressItem.sandals},
    DressSlot.extra: {DressItem.sunglasses, DressItem.sunhat},
  },
  DressWeather.cool: {
    DressSlot.top: {DressItem.jacket},
    DressSlot.legs: {DressItem.jeans},
    DressSlot.feet: {DressItem.sneakers, DressItem.boots},
    DressSlot.extra: {DressItem.scarf},
  },
  DressWeather.cold: {
    DressSlot.top: {DressItem.jacket},
    DressSlot.legs: {DressItem.jeans},
    DressSlot.feet: {DressItem.boots},
    DressSlot.extra: {DressItem.mittens, DressItem.scarf},
  },
  DressWeather.rain: {
    DressSlot.top: {DressItem.jacket},
    DressSlot.legs: {DressItem.jeans},
    DressSlot.feet: {DressItem.boots},
    DressSlot.extra: {DressItem.umbrella},
  },
  DressWeather.snow: {
    DressSlot.top: {DressItem.jacket},
    DressSlot.legs: {DressItem.jeans},
    DressSlot.feet: {DressItem.boots},
    DressSlot.extra: {DressItem.mittens, DressItem.scarf},
  },
};

/// The kind of day from the forecast, by the rules What to wear uses
/// (FR-WX-07): wet days first, then how warm the day feels.
DressWeather dressWeatherFor({required double feelsLikeC, double precipProb = 0, double precipMm = 0, bool snow = false, double windKph = 0}) {
  final wet = precipProb >= 50 || precipMm >= 1;
  if (wet && snow) return DressWeather.snow;
  if (wet) return DressWeather.rain;
  final feel = feelsLikeC - (windKph > 30 ? 3 : 0);
  if (feel < 8) return DressWeather.cold;
  if (feel < 20) return DressWeather.cool;
  if (feel < 26) return DressWeather.warm;
  return DressWeather.hot;
}

/// One part to dress: the three choices, the ones that suit among them.
@immutable
class DressPick {
  const DressPick(this.slot, this.choices, this.suits);
  final DressSlot slot;
  final List<DressItem> choices;
  final Set<DressItem> suits;
}

@immutable
class DressRound {
  const DressRound(this.weather, this.picks, {required this.pretend});
  final DressWeather weather;
  final List<DressPick> picks;

  /// No forecast: the game picks a day to pretend.
  final bool pretend;
}

/// A round at [level] for [weather] (null: pretend, a different kind of
/// day than [last]'s): the top → the top and the shoes → top, legs, feet
/// and one more thing. Each part offers one item that suits and up to two
/// that don't.
DressRound dressRound(int level, Random rng, {DressWeather? weather, DressRound? last}) {
  final pretend = weather == null;
  final DressWeather day = weather ?? _pick<DressWeather>([for (final w in DressWeather.values) if (w != last?.weather) w], rng);
  final slots = switch (level) { <= 1 => [DressSlot.top], 2 => [DressSlot.top, DressSlot.feet], _ => DressSlot.values };
  final picks = <DressPick>[];
  for (final slot in slots) {
    final suits = kDressSuits[day]![slot]!;
    final wrong = [for (final i in DressItem.values) if (i.slot == slot && !suits.contains(i)) i]..shuffle(rng);
    final right = _pick(suits.toList(), rng);
    // Legs have two kinds of item, so a legs pick is a choice of two.
    picks.add(DressPick(slot, [right, ...wrong.take(2)]..shuffle(rng), suits));
  }
  return DressRound(day, picks, pretend: pretend);
}

T _pick<T>(List<T> from, Random rng) => from[rng.nextInt(from.length)];

/// Slips over the whole outfit: one per part is fine.
String dressResult(DressRound r, int slips) => r.picks.length <= 1 ? countingResult(slips) : resultFor(slips, allowed: r.picks.length ~/ 2);
