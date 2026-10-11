# The Toybox voice

The kitchen frame has no text-to-speech engine (SPEC §6), so everything the
Toybox says is a clip made offline and bundled with the app: **Maya-1**
(Apache-2.0, maya-research/maya1) — a text-to-speech model whose voice is
*designed* in a written description (in `tool/sounds/voice.py`: a warm,
sunny preschool teacher with slow, clear, sing-song diction). It is an
original voice, not a clone of a real person. You can't hear the clips you
make, so correctness comes from three things: lines written in a way the
model reads reliably, `scripts/preview.py --say` to make and listen to a
clip before it ships, and the owner listening on the frame.

## How it fits together

1. `packages/dearth_core/lib/src/toybox/voice.dart` builds `kVoiceLines`
   (clip id → words) in `_lines()`. Games ask for clips by id through small
   functions next to it: `letterClip('B')`, `findLetterClip`,
   `letterNameClip`, `numberClip(n)`, `countClip(n)`, `colorClip`,
   `PictureWord.clip`, `creatureClip`… One-off lines are `VoiceLine`
   constants.
2. `packages/dearth_core/tool/voice_lines.dart` prints `kVoiceLines` as
   JSON.
3. `tool/sounds/voice.py` speaks every new or changed line with Maya1,
   trims it, levels it (−16 dBFS RMS, above the effects) and writes
   `apps/dearth_app/assets/voice/<id>.mp3` (MP3, 48 kbps, mono).
   `tool/sounds/voice_index.json` remembers a hash of each clip's final
   text and settings, so unchanged lines are kept, and clips no line needs
   any more are deleted.
4. The game calls `c.say(id)`. One voice plays at a time: a new clip stops
   the one before.

## Writing lines

- **Reuse first.** Numbers ("Three."), counting ("One, two, three."),
  letter names ("B."), "Find the letter B.", letter sounds ("B. Buh, buh,
  ball."), picture words ("Zebra."), colors ("Purple!") already exist.
- **Counting things on screen: one number clip per thing.** Pop each thing
  with its own `numberClip(i)`, a beat (~1.3 s) apart. A single "One, two,
  three." clip runs ahead of the things appearing.
- **Let a line finish.** A new clip stops the one before, so a timer that
  starts the next line waits `afterVoice(clip)` (the clip's measured length
  plus a breath; `atLeast:` for a floor). Never guess a clip's length: they
  change when the voice settings change.
- **Short and warm**: one idea, 1–3 seconds, words a 3-year-old knows.
  "Find the letter B." "It's a star!" "Let's make a silly creature!"
- **Write full sentences with punctuation.** Maya1 takes its intonation
  from it: a period falls, an exclamation lifts, commas pause. Expressive
  tags (`<laugh>`, `<giggle>`, `<whisper>`…) exist in the model but are not
  used in the lines; the voice description carries the register.
- **Ids are file names**: `[a-z0-9_]+`, prefixed by the game or kind
  (`creature_body_2`, `breathe_in`). Build them with `voiceSlug()` from
  words.
- **Numbers as words** for anything spoken ("Find the number seven.");
  digits work but words are unambiguous.

## [[ ]] spans and respelling

Text inside `[[ ]]` is a sound spelled in espeak-style IPA — a letter sound
that no spelling gives reliably ("buh", a short "a"). Maya1 doesn't read
IPA, so `voice.py`'s `RESPELL` table turns each span into the spelling it
says right and **the build fails on a span with no entry** — add one there
when you invent a new sound. A span that only fixed the old voice's British
phonemes ("zebra", "tomato", "banana", "one", a mid-sentence "A") is
already respelled to its plain word: this voice says those American-style
on its own.

- **Letter sounds**: consonants as sound + "uh" (`[[bˈʌ]]` → "buh",
  `[[ʃˈʌ]]` → "shuh"); alone, the model slips a vowel in front of a bare
  "sss". Short vowels use auditioned spellings (`[[ˈɛ]]` → "eh") — when a
  new one is needed, audition two or three spellings with `--say` and keep
  the one that sounds like the letter's sound.
- **A letter name in a sentence** is just the capital letter: "Start at
  [[ˈeɪ]]." → "Start at A."

Check every new line before making clips:

```bash
python3 skills/toybox-game/scripts/preview.py "Find the letter Z." "One, two, three!"
python3 skills/toybox-game/scripts/preview.py --say letter_b          # writes the clip to /tmp/kilo/voice-preview/
python3 skills/toybox-game/scripts/preview.py --ids creature_         # every line whose id starts with creature_
```

## Making clips

```bash
python3 tool/sounds/voice.py                 # new and changed lines only
python3 tool/sounds/voice.py letter_b find_b # remake these clips (and all stale ones)
python3 tool/sounds/voice.py --just letter_b # audition: ONLY the named clips
```

The first run builds `~/.cache/dearth/venv-voice` and downloads the model
(~7 GB, Hugging Face cache). It needs `dart`, `curl`, `uv`, `ffmpeg` (with
libmp3lame) and an NVIDIA GPU (Maya1 is 3.3 B parameters; a full corpus
rebuild is a few hours, line changes are seconds each). It prints each clip
it makes with its length and words; a clip flagged "long for its words"
looped instead of ending — listen to it, and remake it or shorten the line.
`DEARTH_VOICE_DESC` swaps the voice description for experiments. You'd only
want `--all` after a voice change on purpose.

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
