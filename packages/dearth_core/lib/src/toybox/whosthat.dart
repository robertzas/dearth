import 'dart:math';

import 'package:meta/meta.dart';

import 'expansion.dart' show expansionResult;

// Who's That? (SPEC FR-TOY-03, Appendix B: family recognition). The family's
// own faces, cut from the photo library in Settings → People, and the voice
// asks for one: "Where's Grandma?", "Where are you?". The voice can only say
// what's bundled, so a person is asked for by the family word their name or
// nickname is (Mommy, Daddy, Grandma, Nana, Papa…), the child by "you", and
// a dog or a cat by "the doggy", "the kitty"; anyone else is a face to tell
// apart from the others. The game shows once two people have faces and one
// of them can be asked for. Two faces → four → six. Drawing lives in the app.

/// Family words the voice says, by how the family writes them.
const Map<String, String> kWhoWords = {
  'mom': 'Mom', 'mommy': 'Mommy', 'mama': 'Mama', 'mum': 'Mum', //
  'dad': 'Dad', 'daddy': 'Daddy', 'dada': 'Dada', 'papa': 'Papa',
  'grandma': 'Grandma', 'grandpa': 'Grandpa', 'granny': 'Granny', 'nana': 'Nana',
  'grandad': 'Grandad', 'gramps': 'Gramps', 'auntie': 'Auntie', 'uncle': 'Uncle',
};

/// A face on the board: the person, and the clip that asks for them (null
/// when the voice can't).
@immutable
class WhoFace {
  const WhoFace(this.id, this.ask);
  final String id;
  final String? ask;
}

/// The clip asking for a person, from their name or nickname: "Where's
/// Mommy?" (`who_mommy`), "Where are you?" for the child playing, "Where's
/// the doggy?" for a dog; null when the voice can't say who they are.
String? whoAskFor({required String name, String? nickname, String? emoji, bool you = false, bool pet = false}) {
  if (you) return 'who_you';
  if (pet) {
    if (emoji == '🐶' || emoji == '🐕') return 'who_doggy';
    if (emoji == '🐱' || emoji == '🐈') return 'who_kitty';
  }
  for (final n in [?nickname, name]) {
    final key = n.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
    if (kWhoWords.containsKey(key)) return 'who_$key';
  }
  return null;
}

/// Whether [faces] make a game: two faces, one the voice can ask for.
bool whoPlayable(List<WhoFace> faces) => faces.length >= 2 && faces.any((f) => f.ask != null);

@immutable
class WhoRound {
  const WhoRound(this.target, this.faces);

  /// The face the voice asks for.
  final WhoFace target;

  /// On the board, in order: the target among them.
  final List<WhoFace> faces;
}

/// A round at [level]: two faces → four → six (as many as the family has),
/// asking for one the voice can name, not the one asked for [last].
WhoRound whoRound(int level, Random rng, {required List<WhoFace> faces, String? last}) {
  final count = min(faces.length, switch (level) { <= 1 => 2, 2 => 4, _ => 6 });
  final askable = [for (final f in faces) if (f.ask != null) f];
  final fresh = [for (final f in askable) if (f.id != last) f];
  final target = (fresh.isEmpty ? askable : fresh)[rng.nextInt((fresh.isEmpty ? askable : fresh).length)];
  final others = [for (final f in faces) if (f.id != target.id) f]..shuffle(rng);
  return WhoRound(target, [target, ...others.take(count - 1)]..shuffle(rng));
}

/// Two faces: right first time is a win; more faces allow a slip or so.
String whoResult(WhoRound r, int slips) => expansionResult(slips, size: r.faces.length);
