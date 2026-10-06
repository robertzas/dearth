# The Toybox voice

The kitchen frame has no text-to-speech engine (SPEC §6), so everything
the Toybox says is a clip made offline and bundled with the app: Piper
(MIT) speaking with its `en_US-ljspeech-high` voice, trained on the
public-domain LJ Speech dataset (FR-TOY-07). You can't hear the clips, so
correctness comes from three things: lines written in a way Piper reads
reliably, a check of the phonemes espeak produces, and the owner listening
on the frame.

## How it fits together

1. `packages/dearth_core/lib/src/toybox/voice.dart` builds `kVoiceLines`
   (clip id → words) in `_lines()`. Games ask for clips by id through small
   functions next to it: `letterClip('B')`, `findLetterClip`,
   `letterNameClip`, `numberClip(n)`, `countClip(n)`, `colorClip`,
   `PictureWord.clip`, `creatureClip`… One-off lines are `VoiceLine`
   constants.
2. `packages/dearth_core/tool/voice_lines.dart` prints `kVoiceLines` as
   JSON.
3. `tool/sounds/voice.py` speaks every new or changed line with Piper,
   trims it, levels it (−18 dBFS RMS, like the animal sounds) and writes
   `apps/dearth_app/assets/voice/<id>.mp3` (MP3, 40 kbps, mono, ~10 KB a
   clip). `tool/sounds/voice_index.json` remembers a hash of each clip's
   phonemes and settings, so unchanged lines are kept, and clips no line
   needs any more are deleted.
4. The game calls `c.say(id)`. One voice plays at a time: a new clip stops
   the one before.

## Writing lines

- **Reuse first.** Numbers ("Three."), counting ("One, two, three."),
  letter names ("B."), "Find the letter B.", letter sounds ("B. Buh, buh,
  ball."), picture words ("Zebra."), colors ("Purple!") already exist.
- **Counting things on screen: one number clip per thing.** Pop each
  thing with its own `numberClip(i)`, a beat (~1.1 s) apart. A single
  "One, two, three." clip runs ahead of the things appearing (Number
  Tracing did, on the frame).
- **Short and warm**: one idea, 1–3 seconds, words a 3-year-old knows.
  "Find the letter B." "It's a star!" "Let's make a silly creature!"
- **Write full sentences with punctuation.** Piper takes its intonation
  from it: a period falls, an exclamation lifts, commas pause.
- **Ids are file names**: `[a-z0-9_]+`, prefixed by the game or kind
  (`creature_body_2`, `breathe_in`). Build them with `voiceSlug()` from
  words.
- **Numbers as words** for anything spoken ("Find the number seven.");
  digits work but words are unambiguous.

## Phonemes, and the traps

Text inside `[[ ]]` is in the voice's own phonemes (espeak's IPA, the way
Piper reads it) and passes through untouched. Use it when spelling can't
say what you mean:

- **Letter sounds**: no spelling gives "buh" or a short "a". Consonants
  are written with a short "uh" (`[[bˈʌ]]`): alone, the voice slips a
  vowel in front ("sss" comes out "ess"). Short vowels alone are fine
  (`[[ˈa]]`). See `kLetterSounds` in `words.dart`.
- **The letter A** in the middle of a sentence is read as the article:
  "Start at A." comes out "start at uh". Write `[[ˈeɪ]]`. ("A." alone and
  "the letter A" are fine.)
- **British words.** This voice was trained on espeak's English phonemes,
  which are British. Accents don't matter: the model maps those symbols to
  LJ's American speech. But where British English uses *a different word
  or different sounds*, the voice follows the phonemes: the letter Z comes
  out "zed", a zebra "zebb-ra", a tomato "to-mah-to", a banana
  "ba-nah-na". Write those in phonemes with American sounds in espeak's
  symbols: Z `[[zˈiː]]`, zebra `[[zˈiːbɹə]]`, tomato `[[təmˈeɪtəʊ]]`,
  banana `[[bɐnˈanə]]`.

Check every new line before making clips:

```bash
python3 skills/toybox-game/scripts/phonemes.py "Find the number seven." "It's a zebra!"
python3 skills/toybox-game/scripts/phonemes.py --ids creature_   # every line whose id starts with creature_
```

It prints espeak's English phonemes (what the voice gets) and American
English for comparison. Ignore systematic symbol differences (`ɒ`/`ɑː`,
`əʊ`/`oʊ`, `ə`/`ɚ`, `a`/`æ`, `t`/`ɾ`, a missing `ɹ` after vowels); look for
a different word or a different stressed vowel, as in `zˈɛd` / `zˈiː`.

## Making clips

```bash
python3 tool/sounds/voice.py                 # new and changed lines only
python3 tool/sounds/voice.py letter_b find_b # remake these clips
```

The first run downloads Piper and the voice to `~/.cache/dearth/piper`.
It needs `dart`, `curl`, `tar`, `ffmpeg` (with libmp3lame) and Python's
`numpy`. It prints each clip it makes, with its length and words; a clip
much longer or shorter than its words suggest is worth a second look.

**Don't run `--all`.** Piper speaks a little differently every run, so it
would change every clip the owner has already listened to and approved.

## The guards

Two tests keep lines, ids and files in step; update both:

- Core, `packages/dearth_core/test/toybox_voice_test.dart`, "every clip a
  game asks for has a line, and every id is a file name": add every clip
  your game asks for to its `asked` list. It fails both ways, so a line no
  game says is an error too ("no line nothing says").
- App, `apps/dearth_app/test/toybox_voice_test.dart`, "every voice line is
  a bundled clip, and every clip is a line": fails until `voice.py` has
  made the clips, and if a clip is left over.

Widget tests check what was said with `RecordingSound.said` (clip ids in
order).

## Shipping clips

- They're binary, so Git LFS tracks them (`.gitattributes`); confirm with
  `git check-attr filter -- apps/dearth_app/assets/voice/<id>.mp3` (says
  `lfs`). Commit `tool/sounds/voice_index.json` with them.
- In the report, list the new clip ids for the owner to listen to on the
  frame, and say how to remake one: `python3 tool/sounds/voice.py <id>`.
