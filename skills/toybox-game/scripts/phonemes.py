#!/usr/bin/env python3
"""Shows how the Toybox voice will read lines, before you make the clips.

The voice (Piper, en_US-ljspeech-high) was trained on espeak's English
phonemes, which are British. For each line this prints those phonemes (what
the voice gets) and espeak's American English beside them. Systematic
symbol differences are fine (ɒ/ɑː, əʊ/oʊ, ə/ɚ, a/æ, t/ɾ, no ɹ after a
vowel). A different word or stressed vowel is not: the letter Z as "zˈɛd"
instead of "zˈiː", a zebra "zˈɛbɹə". Write those in [[phonemes]] (see
skills/toybox-game/references/voice.md). Text already in [[ ]] is shown as
is.

    python3 skills/toybox-game/scripts/phonemes.py "Find the letter Z." "It's a zebra!"
    python3 skills/toybox-game/scripts/phonemes.py --ids creature_     # every voice line whose id starts with creature_

Needs Piper in ~/.cache/dearth/piper: run python3 tool/sounds/voice.py once.
"""
import json
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PIPER = pathlib.Path.home() / ".cache/dearth/piper/piper"


def phonemize(lang: str, texts: list) -> list:
    if not texts:
        return []
    env = dict(os.environ, LD_LIBRARY_PATH=str(PIPER))
    out = subprocess.run(
        [str(PIPER / "piper_phonemize"), "-l", lang, "--espeak_data", str(PIPER / "espeak-ng-data")],
        input="\n".join(texts) + "\n", capture_output=True, text=True, env=env, check=True,
    ).stdout.splitlines()
    return ["".join(json.loads(line)["phonemes"]) for line in out]


def voice_lines(prefix: str) -> list:
    out = subprocess.run(["dart", "run", "tool/voice_lines.dart"], cwd=ROOT / "packages/dearth_core", capture_output=True, text=True, check=True).stdout
    lines = json.loads(out[out.index("{"):])
    return [(k, v) for k, v in sorted(lines.items()) if k.startswith(prefix)]


def main() -> int:
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if args else 2
    if not (PIPER / "piper_phonemize").exists():
        print("Piper isn't downloaded yet: run python3 tool/sounds/voice.py once.", file=sys.stderr)
        return 1
    if args[0] == "--ids":
        if len(args) != 2:
            print("usage: phonemes.py --ids <prefix>", file=sys.stderr)
            return 2
        items = voice_lines(args[1])
        if not items:
            print(f"No voice line's id starts with {args[1]!r}.", file=sys.stderr)
            return 1
    else:
        items = [("", a) for a in args]

    # The parts outside [[ ]] of every line, phonemized in one call per language.
    split = [re.split(r"\[\[(.*?)\]\]", text) for _, text in items]
    plain = [p for parts in split for i, p in enumerate(parts) if i % 2 == 0 and p.strip(" ,.!?;:")]
    en, us = iter(phonemize("en", plain)), iter(phonemize("en-us", plain))
    for (cid, text), parts in zip(items, split):
        rows = {"en": [], "en-us": []}
        for i, p in enumerate(parts):
            if i % 2:
                rows["en"].append(f"[[{p}]]")
                rows["en-us"].append(f"[[{p}]]")
            elif p.strip(" ,.!?;:"):
                rows["en"].append(next(en))
                rows["en-us"].append(next(us))
        print(f"{cid + ': ' if cid else ''}{text}")
        print(f"  en     {' '.join(rows['en'])}")
        print(f"  en-us  {' '.join(rows['en-us'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
